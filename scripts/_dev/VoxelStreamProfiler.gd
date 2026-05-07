extends Node
# VoxelStreamProfiler.gd
#
# Plain English: every second, print one line that summarises what the
# voxel streamer, water flow sim, and water mesher are actually doing.
# The user reports perf dips that are hard to pin down — this turns
# "feels slow" into a timeline of measurable numbers we can scroll back
# through in the Godot Output panel.
#
# Read-only. This script never writes to gameplay state — it samples
# counters that other systems already maintain on their own (the
# generator's miss_count, WaterFlowManager.last_tick_ms, etc.) and prints.
# All counters are plain ints / floats read on the main thread; the
# systems that write them either also live on the main thread or accept
# a ±1 race for diagnostics. No Mutex.
#
# Activation: register as autoload via Project Settings → Autoload, name
# "VoxelStreamProfiler", path "res://scripts/_dev/VoxelStreamProfiler.gd".
# Disabled by default outside dev scenes — only ticks while the player is
# inside the CopperIslesTest scene (or any future scene that opts in
# via the "dev_scene" group).
#
# Output format (one line per tick):
#   [PROF] fps=58.4 frame_ms=17.1 prims=120K objs=1280 |
#          gen.miss/s=12 sqlite_kb_delta=42 |
#          water.tick_ms=3.2 chunks=18 ticks=4 mesh.built/s=22 queue=87 budget=4 |
#          pos=(123,40,-220) speed=4.7 moving=true
# A second one-shot line `[STREAM] Initial load complete after X.X s`
# fires when generator misses fall below INITIAL_LOAD_THRESHOLD for
# INITIAL_LOAD_QUIET_TICKS consecutive ticks.

const TICK_SECONDS: float = 1.0
const INITIAL_LOAD_THRESHOLD: int = 10
const INITIAL_LOAD_QUIET_TICKS: int = 3

# Path of the CopperIslesTest working DB. Profiler tracks file size delta
# tick-over-tick as a proxy for how aggressively the stream is persisting
# new chunks. Hardcoded to match CopperIslesTestBootstrap.WORKING_SQLITE_PATH.
const SQLITE_PATH: String = "user://copper_isles_test.sqlite"

var _timer: Timer = null
var _frame_count: int = 0
var _frame_time_sum_ms: float = 0.0
var _last_miss_count: int = 0
var _last_sqlite_size: int = -1
var _quiet_ticks: int = 0
var _initial_load_done: bool = false
var _start_time_ms: int = 0


func _ready() -> void:
	_start_time_ms = Time.get_ticks_msec()
	_timer = Timer.new()
	_timer.wait_time = TICK_SECONDS
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)


func _process(delta: float) -> void:
	# Accumulate frame timing. Reset each tick.
	_frame_count += 1
	_frame_time_sum_ms += delta * 1000.0


func _on_tick() -> void:
	# Only print when inside a dev scene — otherwise this autoload is
	# silent baggage during normal gameplay scenes.
	if get_node_or_null("/root/GameState") and not GameState.is_dev_scene():
		_reset_frame_window()
		return

	var fps: float = 0.0
	var frame_ms: float = 0.0
	if _frame_count > 0:
		fps = float(_frame_count) / TICK_SECONDS
		frame_ms = _frame_time_sum_ms / _frame_count

	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))

	# Generator misses. Resolve the terrain and read the generator's
	# atomic-ish counter. Fail soft if the terrain isn't found yet.
	var miss_delta: int = 0
	var miss_total: int = 0
	var terrain: Node = _find_terrain()
	if terrain != null and "generator" in terrain:
		var gen: Resource = terrain.get("generator")
		if gen != null and "miss_count" in gen:
			miss_total = int(gen.get("miss_count"))
			miss_delta = miss_total - _last_miss_count
			if miss_delta < 0:
				miss_delta = 0  # generator reset (unlikely, defensive)
			_last_miss_count = miss_total

	# SQLite growth.
	var sqlite_kb_delta: int = 0
	var current_size: int = _file_size(SQLITE_PATH)
	if _last_sqlite_size >= 0 and current_size > 0:
		sqlite_kb_delta = (current_size - _last_sqlite_size) / 1024
	if current_size > 0:
		_last_sqlite_size = current_size

	# Water flow + mesher counters. Both autoloads expose plain int /
	# float fields written from their tick / process functions.
	var water_tick_ms: float = 0.0
	var water_chunks: int = 0
	var water_ticks: int = 0
	var wfm: Node = get_node_or_null("/root/WaterFlowManager")
	if wfm != null:
		if "last_tick_ms" in wfm:
			water_tick_ms = float(wfm.get("last_tick_ms"))
		if "last_tick_chunks_active" in wfm:
			water_chunks = int(wfm.get("last_tick_chunks_active"))
		if "ticks_run" in wfm:
			water_ticks = int(wfm.get("ticks_run"))

	var mesh_built: int = 0
	var mesh_queue: int = 0
	var mesh_budget: int = 0
	if wfm != null:
		var mesher: Node = wfm.get_node_or_null("WaterChunkMesher")
		if mesher == null:
			# Some Zylann builds parent the mesher under a different name.
			# Walk children once.
			for child in wfm.get_children():
				if child.get_script() != null and "meshed_this_second" in child:
					mesher = child
					break
		if mesher != null:
			if "meshed_this_second" in mesher:
				mesh_built = int(mesher.get("meshed_this_second"))
				mesher.set("meshed_this_second", 0)
			if "dirty_queue_len" in mesher:
				mesh_queue = int(mesher.get("dirty_queue_len"))
			if "current_budget" in mesher:
				mesh_budget = int(mesher.get("current_budget"))

	# Player state.
	var pos_str: String = "?"
	var speed: float = 0.0
	var moving: bool = false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and "global_position" in player:
		var p: Vector3 = player.global_position
		pos_str = "(%d,%d,%d)" % [int(p.x), int(p.y), int(p.z)]
		if "velocity" in player:
			speed = (player.velocity as Vector3).length()
			moving = speed > 0.5

	print("[PROF] fps=%.1f frame_ms=%.1f prims=%d objs=%d | gen.miss/s=%d sqlite_kb_delta=%d | water.tick_ms=%.1f chunks=%d ticks=%d mesh.built/s=%d queue=%d budget=%d | pos=%s speed=%.1f moving=%s" % [
		fps, frame_ms, prims, objs,
		miss_delta, sqlite_kb_delta,
		water_tick_ms, water_chunks, water_ticks, mesh_built, mesh_queue, mesh_budget,
		pos_str, speed, str(moving)
	])

	# Initial-load-done detection. Once miss_delta sits below the
	# threshold for N consecutive ticks, fire one-shot timing line.
	if not _initial_load_done:
		if miss_delta < INITIAL_LOAD_THRESHOLD:
			_quiet_ticks += 1
			if _quiet_ticks >= INITIAL_LOAD_QUIET_TICKS:
				_initial_load_done = true
				var elapsed_s: float = (Time.get_ticks_msec() - _start_time_ms) / 1000.0
				print("[STREAM] Initial load complete after %.1f s" % elapsed_s)
		else:
			_quiet_ticks = 0

	_reset_frame_window()


func _reset_frame_window() -> void:
	_frame_count = 0
	_frame_time_sum_ms = 0.0


func _find_terrain() -> Node:
	# Search the current scene tree for the first VoxelLodTerrain.
	# Cached lookups would go stale across scene changes; this is one
	# tree walk per second, negligible cost.
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return _find_voxel_terrain_recursive(root)


func _find_voxel_terrain_recursive(n: Node) -> Node:
	if n.get_class() == "VoxelLodTerrain":
		return n
	for child in n.get_children():
		var hit: Node = _find_voxel_terrain_recursive(child)
		if hit != null:
			return hit
	return null


func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var sz: int = f.get_length()
	f.close()
	return sz
