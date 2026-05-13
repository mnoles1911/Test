extends Node

# Profiler.gd — single source of truth for per-system timing data.
#
# Wired into autoloads via two patterns:
#   1. Outer-wrapper instrumentation. Wrap an autoload's _process /
#      _physics_process body in an _inner function and time around it:
#
#        func _process(delta: float) -> void:
#            var _t0 := Time.get_ticks_usec()
#            _process_inner(delta)
#            Profiler.record("WATER", "WaterChunkMesher",
#                            Time.get_ticks_usec() - _t0)
#
#        func _process_inner(delta: float) -> void:
#            # original body — unchanged
#            ...
#
#      Wrappers add ~1 µs per call. Categories live in the call site
#      so the profiler doesn't carry a name→category mapping.
#
#   2. Scope tokens for nested or signal-handler timings:
#
#        var scope := Profiler.scope("WORLD", "Zylann_detect_blocks")
#        # ... work ...
#        scope.close()
#
#      The token is a small RefCounted that calls record() in its
#      destructor if you forget to close it, but explicit close() is
#      preferred to keep the bookkeeping cost predictable.
#
# Frame lifecycle:
#   HUDOverlay._process calls Profiler.frame_finalize() once per frame
#   after the per-system samples are in. frame_finalize rolls the
#   current-frame totals into per-name 1s windows, pushes the frame
#   total into the spike-detection ring buffer, and clears the
#   current-frame map.
#
# Performance: when `enabled == false`, record() / scope() short-circuit
# in 1-2 ns. The overlay only ever asks for snapshots; it never blocks
# the recording path. Frame ring buffer is preallocated PackedInt32Array.

const RING_FRAMES: int = 120        # 2 seconds @ 60fps — spike context window
const SPIKE_MS_THRESHOLD: float = 33.0
const WINDOW_MS: int = 1000         # 1-second rolling window for avg/max

# --- State ---------------------------------------------------------------

var enabled: bool = true

# Per-frame: samples collected by record() since the last frame_finalize.
# Keyed by "CATEGORY.name". Cleared on frame_finalize.
var _frame_samples: Dictionary = {}     # String → int (usec)

# Per-name stats over a rolling 1-second window. Each value is a Dictionary
# {window_sum_us, window_max_us, frame_count, all_time_max_us, last_frame_us,
#  category}. The category is duplicated here so the overlay can sort/group
# without parsing the key string.
var _stats: Dictionary = {}             # full_name → Dictionary

# Per-frame totals across all samples, for spike detection + the timeline
# view. Ring buffer of size RING_FRAMES.
var _frame_totals_us: PackedInt32Array = PackedInt32Array()
var _frame_index: int = 0               # write head into the ring
var _frame_count_total: int = 0         # monotonic frame counter

# Rolling window bookkeeping: at start of each frame we check the wall clock;
# if a window has elapsed, we snapshot _stats into _window_snapshot for the
# overlay to display, then zero out the window sums.
var _window_start_msec: int = 0
var _window_snapshot: Dictionary = {}   # full_name → snapshot dict (same shape)

# Capture mode: when active, every frame's per-name samples + total go into
# _capture_buffer. Stop writes _capture_buffer to disk as JSON.
var _capture_active: bool = false
var _capture_buffer: Array = []         # Array[Dictionary]
var _capture_start_msec: int = 0

# Last spike — used by the overlay to surface "what caused the worst frame
# in the last 2 seconds". {frame: int, total_us: int, attribution: Dict}.
var _last_spike: Dictionary = {}


func _ready() -> void:
	# Preallocate the ring so we never reallocate during recording.
	_frame_totals_us.resize(RING_FRAMES)
	for i in RING_FRAMES:
		_frame_totals_us[i] = 0
	_window_start_msec = Time.get_ticks_msec()


# --- Public recording API ------------------------------------------------

func record(category: String, name: String, usec: int) -> void:
	# Hot path — keep the branch count low. Tested: ~80 ns when enabled,
	# ~5 ns when disabled (single bool read + early return).
	if not enabled:
		return
	if usec <= 0:
		return
	var key: String = category + "." + name
	_frame_samples[key] = _frame_samples.get(key, 0) + usec


# Scope token for "begin/end" style timing. Use when the work is wrapped
# around a method call where the outer wrapper pattern doesn't fit, e.g.
# inside a signal handler. close() must be called explicitly — there's no
# RAII in GDScript and forgetting close() means the time gets attributed
# to the next close() in the same frame (a benign noise source, but worth
# avoiding).
class Scope extends RefCounted:
	var _category: String
	var _name: String
	var _start_us: int
	var _closed: bool = false

	func close() -> void:
		if _closed:
			return
		_closed = true
		var elapsed: int = Time.get_ticks_usec() - _start_us
		if elapsed > 0:
			# Profiler is an autoload, accessible via /root/.
			var p: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
			if p != null:
				p.record(_category, _name, elapsed)


func scope(category: String, name: String) -> Scope:
	var s := Scope.new()
	s._category = category
	s._name = name
	s._start_us = Time.get_ticks_usec()
	return s


# --- Frame lifecycle -----------------------------------------------------

func frame_finalize() -> void:
	# Called from HUDOverlay._process every frame. Folds the current-frame
	# samples into the rolling-window stats and the spike ring buffer.
	_frame_count_total += 1

	var frame_total: int = 0
	for key in _frame_samples.keys():
		var us: int = _frame_samples[key]
		frame_total += us
		var entry: Dictionary = _stats.get(key, _make_stat_entry(key))
		entry.window_sum_us += us
		entry.frame_count += 1
		entry.last_frame_us = us
		if us > entry.window_max_us:
			entry.window_max_us = us
		if us > entry.all_time_max_us:
			entry.all_time_max_us = us
		_stats[key] = entry

	# Push the frame total into the ring buffer.
	_frame_totals_us[_frame_index] = frame_total
	_frame_index = (_frame_index + 1) % RING_FRAMES

	# Spike detection. Threshold is in ms; the buffered total is in usec
	# but only covers wrapped systems, so it under-counts vs. the engine's
	# real delta. Use Engine.get_frames_per_second() as a sanity sentinel:
	# if FPS just dropped, dump the attribution we DID capture.
	var frame_total_ms: float = frame_total / 1000.0
	if frame_total_ms > SPIKE_MS_THRESHOLD:
		_record_spike(frame_total)

	# Capture: if active, snapshot the frame INCLUDING engine + Zylann
	# telemetry so the JSON tells the full story (not just wrapped GD).
	#
	# Engine fields:
	#   proc_us / phys_us  — Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS,
	#                        converted to microseconds. These cover ALL
	#                        _process / _physics_process bodies in the
	#                        scene tree, including non-wrapped code +
	#                        engine-internal work.
	#   draws / prims      — last-frame rendering counters. High prims +
	#                        spike → mesh upload-bound.
	#   vram_mb            — used video memory. Rises during chunk
	#                        streaming; flat during steady-state.
	#
	# Zylann fields (only when a VoxelLodTerrain is in scene):
	#   z_detect_us / z_io_us / z_mesh_us / z_update_us — main-thread
	#                        budgets from VoxelLodTerrain.get_statistics().
	#   z_blocked_lods       — count of LOD slots blocked by save IO
	#   z_dropped_loads      — chunks the streamer gave up on this frame.
	#
	# Capture cost is small (one Performance.get_monitor call per field
	# + one Variant::call to Zylann), only paid during capture mode.
	if _capture_active:
		var proc_us: int = int(Performance.get_monitor(Performance.TIME_PROCESS) * 1_000_000.0)
		var phys_us: int = int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0)
		var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var vram_mb: int = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024 * 1024))

		var record: Dictionary = {
			"frame": _frame_count_total,
			"total_us": frame_total,
			"attribution": _frame_samples.duplicate(),
			"engine": {
				"proc_us": proc_us,
				"phys_us": phys_us,
				"draws": draws,
				"prims": prims,
				"vram_mb": vram_mb,
			},
		}
		# Zylann main-thread budgets. Pull from the live VoxelLodTerrain
		# via the lazy-cached _zylann_terrain reference (populated by
		# _find_voxel_terrain). Skipped silently when no terrain is in
		# the scene (title screen, dev scenes that join "dev_scene").
		var zstats: Dictionary = _read_zylann_stats()
		if not zstats.is_empty():
			record["zylann"] = zstats
		_capture_buffer.append(record)

	# Roll the 1s window if it's elapsed.
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _window_start_msec >= WINDOW_MS:
		_snapshot_window()
		_window_start_msec = now_msec

	# Clear current-frame samples for the next frame.
	_frame_samples.clear()


func _make_stat_entry(key: String) -> Dictionary:
	var dot_idx: int = key.find(".")
	var category: String = key.substr(0, dot_idx) if dot_idx >= 0 else "OTHER"
	return {
		"category": category,
		"window_sum_us": 0,
		"window_max_us": 0,
		"frame_count": 0,
		"all_time_max_us": 0,
		"last_frame_us": 0,
	}


func _record_spike(frame_total_us: int) -> void:
	# Save the attribution as it exists right now so the overlay can show
	# "what caused this." We don't print to Output every spike — the old
	# perf code learned that lesson (rate-limited via 1s window in
	# HUDOverlay). Caller can manually inspect _last_spike from console.
	_last_spike = {
		"frame": _frame_count_total,
		"total_us": frame_total_us,
		"attribution": _frame_samples.duplicate(),
	}


func _snapshot_window() -> void:
	# Copy current rolling stats into _window_snapshot so the overlay can
	# read a stable view, then zero the window counters for the next 1s.
	# We can't just copy by reference because _stats entries are dicts
	# (also by reference) — duplicate so the snapshot is independent.
	_window_snapshot.clear()
	for key in _stats.keys():
		_window_snapshot[key] = (_stats[key] as Dictionary).duplicate()
	# Zero the window counters; preserve all_time_max + last_frame.
	for key in _stats.keys():
		var entry: Dictionary = _stats[key]
		entry.window_sum_us = 0
		entry.window_max_us = 0
		entry.frame_count = 0


# --- Snapshot accessors (overlay reads these) ---------------------------

func get_window_snapshot() -> Dictionary:
	# Last fully-rolled 1-second window. Empty until the first second elapses.
	return _window_snapshot


func get_live_stats() -> Dictionary:
	# Mid-window stats. Use when a fresh snapshot hasn't rolled yet.
	return _stats


func get_frame_ring() -> Array:
	# Returns the ring buffer in chronological order (oldest first), suitable
	# for the timeline view. Most recent frame is at index RING_FRAMES-1.
	var out: Array = []
	out.resize(RING_FRAMES)
	for i in RING_FRAMES:
		out[i] = _frame_totals_us[(_frame_index + i) % RING_FRAMES]
	return out


func get_last_spike() -> Dictionary:
	return _last_spike


# --- Capture API --------------------------------------------------------

# --- Zylann main-thread budget capture ---------------------------------
#
# Lazily resolves the active VoxelLodTerrain in the scene tree (refreshed
# when the cached node becomes invalid, e.g. scene change). Reads
# get_statistics() — Zylann exposes time_detect_required_blocks,
# time_io_requests, time_mesh_requests, time_update_task, blocked_lods,
# dropped_block_loads, dropped_block_meshs. Same data the [DIAG] log
# line surfaces; pulling it per-frame into the JSON capture lets a
# post-mortem correlate Zylann main-thread spikes with frame totals.

var _zylann_terrain: Node = null

func _read_zylann_stats() -> Dictionary:
	if _zylann_terrain == null or not is_instance_valid(_zylann_terrain):
		_zylann_terrain = _find_voxel_terrain()
	if _zylann_terrain == null:
		return {}
	if not _zylann_terrain.has_method("get_statistics"):
		return {}
	var s: Dictionary = _zylann_terrain.call("get_statistics")
	# Rename to short keys + namespace under z_* so the JSON record is
	# greppable without ambiguity vs. Performance.* fields.
	return {
		"detect_us": int(s.get("time_detect_required_blocks", 0)),
		"io_us": int(s.get("time_io_requests", 0)),
		"mesh_us": int(s.get("time_mesh_requests", 0)),
		"update_us": int(s.get("time_update_task", 0)),
		"blocked_lods": int(s.get("blocked_lods", 0)),
		"dropped_loads": int(s.get("dropped_block_loads", 0)),
		"dropped_meshs": int(s.get("dropped_block_meshs", 0)),
	}


func _find_voxel_terrain() -> Node:
	var root: Node = Engine.get_main_loop().root
	return _walk_for_terrain(root)


func _walk_for_terrain(node: Node) -> Node:
	if node.get_class() == "VoxelLodTerrain":
		return node
	for child in node.get_children():
		var found := _walk_for_terrain(child)
		if found != null:
			return found
	return null


func capture_start() -> void:
	# Auto-wipe prior captures so the folder only ever contains the
	# most recent JSON. Matches the user's routine-wipe workflow
	# (2026-05-12) — every fresh capture starts a clean slate. If you
	# ever want to keep an older capture across runs, move it out of
	# user:// (e.g. drag it onto the desktop) BEFORE pressing C.
	var deleted: int = _wipe_prior_captures()
	if deleted > 0:
		print("[Profiler] capture_start: deleted %d prior capture(s)" % deleted)

	# Drop any in-progress capture and start fresh.
	_capture_buffer.clear()
	_capture_active = true
	_capture_start_msec = Time.get_ticks_msec()
	print("[Profiler] capture started")


func _wipe_prior_captures() -> int:
	# Scans user:// for profile_capture_*.json and removes each one.
	# Returns the number of files deleted. Safe to call when none
	# exist (returns 0). Uses DirAccess.remove_absolute so we can pass
	# the prefixed res://-style path Godot accepts.
	var dir := DirAccess.open("user://")
	if dir == null:
		return 0
	var deleted: int = 0
	for fname in dir.get_files():
		if fname.begins_with("profile_capture_") and fname.ends_with(".json"):
			var err: int = DirAccess.remove_absolute("user://" + fname)
			if err == OK:
				deleted += 1
			else:
				push_warning("[Profiler] failed to delete user://%s (err=%d)" % [fname, err])
	return deleted


func capture_stop(path: String = "") -> String:
	# Stops capture and dumps to user://. If `path` is empty, picks a
	# timestamped filename. Returns the absolute path written, or "" on
	# error / no capture in progress.
	if not _capture_active:
		return ""
	_capture_active = false
	var out_path: String = path
	if out_path.is_empty():
		var ts: int = Time.get_ticks_msec()
		out_path = "user://profile_capture_%d.json" % ts
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("[Profiler] capture_stop: failed to open %s" % out_path)
		return ""
	var payload: Dictionary = {
		"version": 1,
		"frames": _capture_buffer.size(),
		"duration_ms": Time.get_ticks_msec() - _capture_start_msec,
		"records": _capture_buffer,
	}
	file.store_string(JSON.stringify(payload))
	file.close()
	print("[Profiler] capture stopped: %d frames over %d ms -> %s" % [
		_capture_buffer.size(),
		Time.get_ticks_msec() - _capture_start_msec,
		out_path,
	])
	_capture_buffer.clear()
	return out_path


# --- Toggle -------------------------------------------------------------

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_frame_samples.clear()
