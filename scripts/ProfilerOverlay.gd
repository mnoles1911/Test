extends CanvasLayer

# ProfilerOverlay.gd — F3-toggled live view onto Profiler state.
#
# Three pages, cycled with Tab:
#   1. Overview — sortable table of all profiled systems (top 20 by max).
#   2. Timeline — last 120 frames as a bar chart + drill-down on a frame.
#   3. GPU — Performance.* counters + Zylann [DIAG] values.
#
# Controls (all keyboard, no mouse — the project's GUI input dispatch
# is unreliable per CLAUDE.md, so we route raw InputEventKey instead):
#   F3      toggle visibility
#   Tab     cycle page
#   P       pause/resume Profiler.enabled
#   C       capture_start / capture_stop (toggles)
#   S       save current snapshot to disk
#   Q       clear all stats
#   ← →     in Timeline, move the inspect cursor
#
# Built programmatically (no .tscn) because the layout is data-driven —
# rows in the Overview table change every second. CanvasLayer = 90 so we
# sit above HUDOverlay (5) and JournalUI (50) but below the loading
# screen overlay (100).

const PAGE_OVERVIEW: int = 0
const PAGE_TIMELINE: int = 1
const PAGE_GPU: int = 2
const PAGE_COUNT: int = 3

const ROW_LIMIT: int = 20
const COL_PAD: int = 12      # horizontal spacing between columns
const ROW_HEIGHT: int = 18

var _visible: bool = false
var _page: int = PAGE_OVERVIEW

# Timeline state — cursor offset 0 = newest frame, RING_FRAMES-1 = oldest.
var _timeline_cursor: int = 0

# Root container; children are the three page panels.
var _root: Control
var _header: Label
var _overview_panel: Control
var _timeline_panel: Control
var _gpu_panel: Control

# Overview page widgets. Built once, contents rewritten each frame.
var _overview_rows: VBoxContainer
var _overview_header_row: HBoxContainer

# Timeline page widgets.
var _timeline_bars_node: Control          # custom-drawn via _draw on a parent
var _timeline_detail_label: Label

# GPU page widgets.
var _gpu_label: Label                     # multi-line summary; uses RichTextLabel

# Subscribed-once panel state to avoid rebuilding labels each frame.
var _overview_row_pool: Array = []        # Array[HBoxContainer]

# Cached references for the Zylann [DIAG] block. We don't subscribe — we
# read the latest values on the GPU page each frame from the terrain
# directly. _zylann_terrain is found lazily.
var _zylann_terrain: Node = null


func _ready() -> void:
	layer = 90
	_build_ui()
	_root.visible = false
	# F3 must always reach us — sit at the top of _input dispatch order.
	# CanvasLayer doesn't intercept raw _input, so we register at the
	# autoload level (this script is the autoload root).


func _build_ui() -> void:
	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Semi-transparent backdrop so labels are readable over busy scenes.
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# Top header line. Updated each frame with status + page indicator.
	_header = _make_label("", 14)
	_header.position = Vector2(16, 12)
	_header.size = Vector2(1800, 22)
	_root.add_child(_header)

	# Page panels — only one visible at a time.
	_overview_panel = _build_overview_panel()
	_timeline_panel = _build_timeline_panel()
	_gpu_panel = _build_gpu_panel()
	_overview_panel.position = Vector2(16, 44)
	_timeline_panel.position = Vector2(16, 44)
	_gpu_panel.position = Vector2(16, 44)
	_overview_panel.visible = true
	_timeline_panel.visible = false
	_gpu_panel.visible = false
	_root.add_child(_overview_panel)
	_root.add_child(_timeline_panel)
	_root.add_child(_gpu_panel)


func _make_label(text: String, size: int = 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Overview page ------------------------------------------------------

func _build_overview_panel() -> Control:
	var c := Control.new()
	c.size = Vector2(1800, 900)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Column header.
	_overview_header_row = _build_overview_row(
			"NAME", "CAT", "LAST", "AVG/F", "MAX", "%FR", true)
	_overview_header_row.position = Vector2(0, 0)
	c.add_child(_overview_header_row)

	# Body rows.
	_overview_rows = VBoxContainer.new()
	_overview_rows.position = Vector2(0, ROW_HEIGHT + 4)
	_overview_rows.add_theme_constant_override("separation", 2)
	c.add_child(_overview_rows)
	for i in ROW_LIMIT:
		var row := _build_overview_row("", "", "", "", "", "", false)
		_overview_rows.add_child(row)
		_overview_row_pool.append(row)

	return c


func _build_overview_row(name_t: String, cat_t: String, last_t: String,
		avg_t: String, max_t: String, pct_t: String, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COL_PAD)

	var name_lbl := _make_label(name_t, 12)
	name_lbl.custom_minimum_size = Vector2(360, 0)
	var cat_lbl := _make_label(cat_t, 12)
	cat_lbl.custom_minimum_size = Vector2(80, 0)
	var last_lbl := _make_label(last_t, 12)
	last_lbl.custom_minimum_size = Vector2(80, 0)
	last_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var avg_lbl := _make_label(avg_t, 12)
	avg_lbl.custom_minimum_size = Vector2(80, 0)
	avg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var max_lbl := _make_label(max_t, 12)
	max_lbl.custom_minimum_size = Vector2(80, 0)
	max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var pct_lbl := _make_label(pct_t, 12)
	pct_lbl.custom_minimum_size = Vector2(60, 0)
	pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	if is_header:
		for lbl in [name_lbl, cat_lbl, last_lbl, avg_lbl, max_lbl, pct_lbl]:
			lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))

	row.add_child(name_lbl)
	row.add_child(cat_lbl)
	row.add_child(last_lbl)
	row.add_child(avg_lbl)
	row.add_child(max_lbl)
	row.add_child(pct_lbl)
	row.set_meta("labels", [name_lbl, cat_lbl, last_lbl, avg_lbl, max_lbl, pct_lbl])
	return row


# --- Timeline page ------------------------------------------------------

func _build_timeline_panel() -> Control:
	var c := Control.new()
	c.size = Vector2(1800, 900)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Bar chart drawn via _draw on a sub-Control. Width = 1200, height = 200.
	_timeline_bars_node = Control.new()
	_timeline_bars_node.position = Vector2(0, 0)
	_timeline_bars_node.size = Vector2(1200, 220)
	_timeline_bars_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timeline_bars_node.draw.connect(_draw_timeline_bars)
	c.add_child(_timeline_bars_node)

	# Drill-down label below the bars. Multi-line via Label autowrap.
	_timeline_detail_label = _make_label("", 12)
	_timeline_detail_label.position = Vector2(0, 240)
	_timeline_detail_label.size = Vector2(1200, 600)
	_timeline_detail_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	c.add_child(_timeline_detail_label)

	return c


func _draw_timeline_bars() -> void:
	# Render the ring buffer as vertical bars. X = frame index (oldest left,
	# newest right). Bar height proportional to frame total µs. 33ms line
	# overlay so spikes are obvious.
	if Engine.get_main_loop().root.get_node_or_null("Profiler") == null:
		return
	var prof: Node = Engine.get_main_loop().root.get_node("Profiler")
	var ring: Array = prof.get_frame_ring()
	if ring.is_empty():
		return

	var rect_w: float = _timeline_bars_node.size.x
	var rect_h: float = _timeline_bars_node.size.y
	var n: int = ring.size()
	var bar_w: float = rect_w / float(n)

	# Spike threshold line (33 ms).
	var spike_us: float = 33000.0
	var max_y_us: float = 50000.0   # show up to 50 ms before clipping
	var spike_y: float = rect_h - (spike_us / max_y_us) * rect_h
	_timeline_bars_node.draw_line(
			Vector2(0, spike_y), Vector2(rect_w, spike_y),
			Color(1.0, 0.4, 0.4, 0.6), 1.0)

	# Bars.
	for i in n:
		var us: int = ring[i]
		var h: float = clamp(float(us) / max_y_us, 0.0, 1.0) * rect_h
		var x: float = i * bar_w
		var color: Color = Color(0.45, 0.85, 0.55)
		if us > 16667:
			color = Color(1.0, 0.85, 0.35)
		if us > spike_us:
			color = Color(1.0, 0.35, 0.35)
		_timeline_bars_node.draw_rect(
				Rect2(x, rect_h - h, max(bar_w - 1.0, 1.0), h), color)

	# Inspect cursor — orange vertical line at _timeline_cursor offset from
	# the newest frame.
	var cursor_idx: int = n - 1 - _timeline_cursor
	if cursor_idx < 0:
		cursor_idx = 0
	var cursor_x: float = cursor_idx * bar_w + bar_w * 0.5
	_timeline_bars_node.draw_line(
			Vector2(cursor_x, 0), Vector2(cursor_x, rect_h),
			Color(1.0, 0.7, 0.2, 0.9), 2.0)


# --- GPU + Zylann page --------------------------------------------------

func _build_gpu_panel() -> Control:
	var c := Control.new()
	c.size = Vector2(1800, 900)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gpu_label = _make_label("", 13)
	_gpu_label.position = Vector2(0, 0)
	_gpu_label.size = Vector2(1200, 800)
	_gpu_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	c.add_child(_gpu_label)
	return c


# --- Input ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return

	# F3 always works (toggle).
	if k.keycode == KEY_F3:
		_toggle()
		get_viewport().set_input_as_handled()
		return

	# F9 — streaming-diagnostic one-shot dump. Always fires (no overlay
	# required, matches F3/F5/F6 always-on convention). Prints a single
	# multi-line snapshot to Output: every VoxelViewer's position +
	# alignment + view_distance, Zylann queue depths, per-LOD chunk
	# counts where available, and the most recent spike attribution.
	# Added 2026-05-26 — the kind of dump you reach for when "streaming
	# feels slow" but the per-second [PERF] line doesn't pinpoint why.
	if k.keycode == KEY_F9:
		_dump_stream_diag()
		get_viewport().set_input_as_handled()
		return

	if not _visible:
		return

	match k.keycode:
		KEY_TAB:
			_page = (_page + 1) % PAGE_COUNT
			_show_page(_page)
			get_viewport().set_input_as_handled()
		KEY_P:
			var prof: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
			if prof != null:
				prof.set_enabled(not prof.enabled)
			get_viewport().set_input_as_handled()
		KEY_C:
			var prof2: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
			if prof2 != null:
				if prof2._capture_active:
					prof2.capture_stop()
				else:
					prof2.capture_start()
			get_viewport().set_input_as_handled()
		KEY_S:
			var prof3: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
			if prof3 != null and prof3._capture_active:
				prof3.capture_stop()
			get_viewport().set_input_as_handled()
		KEY_Q:
			var prof4: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
			if prof4 != null:
				prof4._stats.clear()
				prof4._window_snapshot.clear()
				prof4._last_spike.clear()
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			if _page == PAGE_TIMELINE:
				_timeline_cursor = mini(_timeline_cursor + 1, 119)
				_timeline_bars_node.queue_redraw()
				get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if _page == PAGE_TIMELINE:
				_timeline_cursor = maxi(_timeline_cursor - 1, 0)
				_timeline_bars_node.queue_redraw()
				get_viewport().set_input_as_handled()


func _dump_stream_diag() -> void:
	# One-shot, console-friendly snapshot. Designed to be pasted into
	# chat as-is when reporting a streaming issue. Sections, in order:
	#   1) Viewers: positions, view_distances, lead/alignment vs player
	#   2) Zylann main-thread stats: detect/io/mesh budgets, drops,
	#      blocked LODs, per-LOD chunk counts
	#   3) Last spike: frame + top attribution buckets
	#
	# All data is pulled live from /root/Profiler. Cheap (~ms), never
	# blocks input.
	var prof: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
	if prof == null:
		print("[F9 StreamDiag] /root/Profiler not loaded — dev scene?")
		return
	print("=== [F9 StreamDiag] @ %d ms ===" % Time.get_ticks_msec())

	# --- Viewers ---
	if prof.has_method("read_viewer_telemetry"):
		var vt: Dictionary = prof.call("read_viewer_telemetry")
		var p_pos: Vector3 = vt.get("player_position", Vector3.ZERO)
		var p_vel: Vector3 = vt.get("player_velocity", Vector3.ZERO)
		var p_speed: float = Vector3(p_vel.x, 0.0, p_vel.z).length()
		print("  player: pos=(%.1f, %.1f, %.1f)  horiz_speed=%.1f m/s" % [
			p_pos.x, p_pos.y, p_pos.z, p_speed,
		])
		var viewers: Array = vt.get("viewers", [])
		if viewers.is_empty():
			print("  viewers: NONE in scene")
		else:
			for v in viewers:
				var flag: String = ""
				if p_speed > 0.5 and v["alignment"] < 0.3:
					flag = "   !!! MISALIGNED — viewer is not leading player"
				print("  viewer %s:" % v["path"])
				print("    pos=(%.1f, %.1f, %.1f)  vd=%d vox  lead=%.1f m  align=%+.3f%s" % [
					v["global_position"].x, v["global_position"].y, v["global_position"].z,
					v["view_distance"], v["distance_to_player_m"], v["alignment"], flag,
				])

	# --- Zylann stats ---
	if prof.has_method("_read_zylann_stats"):
		var z: Dictionary = prof.call("_read_zylann_stats")
		if z.is_empty():
			print("  zylann: no VoxelLodTerrain in scene")
		else:
			print("  zylann main-thread budgets:")
			print("    detect_us=%.2f ms  io_us=%.2f ms  mesh_us=%.2f ms  update_us=%.2f ms" % [
				z.get("detect_us", 0) / 1000.0,
				z.get("io_us", 0) / 1000.0,
				z.get("mesh_us", 0) / 1000.0,
				z.get("update_us", 0) / 1000.0,
			])
			print("    blocked_lods=%d  dropped_loads=%d  dropped_meshs=%d" % [
				z.get("blocked_lods", 0), z.get("dropped_loads", 0), z.get("dropped_meshs", 0),
			])
	if prof.has_method("read_zylann_per_lod_stats"):
		var lc: Dictionary = prof.call("read_zylann_per_lod_stats")
		if not lc.is_empty():
			print("  zylann chunk counts:")
			if "loaded_per_lod" in lc:
				print("    loaded_per_lod = %s" % str(lc["loaded_per_lod"]))
			if "data_block_count" in lc:
				print("    data_block_count = %d" % int(lc["data_block_count"]))

	# --- Last spike (most recent >33 ms frame from the ring) ---
	if prof.has_method("get_last_spike"):
		var spike: Dictionary = prof.call("get_last_spike")
		if not spike.is_empty():
			print("  last spike: frame=%d  total=%.1f ms" % [
				int(spike.get("frame", -1)), int(spike.get("total_us", 0)) / 1000.0,
			])
			var attr: Dictionary = spike.get("attribution", {})
			if not attr.is_empty():
				var entries: Array = []
				for kk in attr.keys():
					entries.append([kk, attr[kk]])
				entries.sort_custom(func(a, b): return a[1] > b[1])
				for i in range(mini(5, entries.size())):
					var us: int = entries[i][1]
					if us < 200:
						continue
					print("    %s = %.2f ms" % [entries[i][0], us / 1000.0])
	print("=== /F9 StreamDiag ===")
	# Re-assert mouse capture (2026-05-26). Pressing F9 during gameplay
	# was popping the mouse out of the test scene window — Godot's
	# stdout-flush + focus-grab during a large console burst seems to
	# release MOUSE_MODE_CAPTURED on Windows. Re-assert it AFTER the
	# print burst finishes so the player isn't yanked out of FPS look
	# control. Only re-assert if we WERE captured; never silently
	# capture from CAPTURED-state to avoid stealing the cursor while
	# the player is intentionally using a menu (mouse_mode == VISIBLE).
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		# Player is in a menu / pause — leave alone.
		pass
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _toggle() -> void:
	_visible = not _visible
	_root.visible = _visible
	if _visible:
		_show_page(_page)


func _show_page(p: int) -> void:
	_overview_panel.visible = (p == PAGE_OVERVIEW)
	_timeline_panel.visible = (p == PAGE_TIMELINE)
	_gpu_panel.visible = (p == PAGE_GPU)
	if p == PAGE_TIMELINE:
		_timeline_bars_node.queue_redraw()


# --- Per-frame refresh ---------------------------------------------------

func _process(_delta: float) -> void:
	if not _visible:
		return
	_refresh_header()
	match _page:
		PAGE_OVERVIEW: _refresh_overview()
		PAGE_TIMELINE: _refresh_timeline()
		PAGE_GPU:      _refresh_gpu()


func _refresh_header() -> void:
	var prof: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
	if prof == null:
		_header.text = "PROFILER: autoload missing"
		return
	var page_name: String = ["Overview", "Timeline", "GPU"][_page]
	var status: String = "RECORDING" if prof.enabled else "PAUSED"
	var cap: String = ("CAPTURE %d frames" % prof._capture_buffer.size()) if prof._capture_active else "idle"
	_header.text = "PROFILER · %s    [F3 hide] [Tab page] [P %s] [C capture]   |  Status: %s   Capture: %s   Total frames: %d" % [
		page_name,
		"resume" if not prof.enabled else "pause",
		status, cap, prof._frame_count_total,
	]


func _refresh_overview() -> void:
	var prof: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
	if prof == null:
		return
	var snap: Dictionary = prof.get_window_snapshot()
	if snap.is_empty():
		# Window hasn't rolled yet — fall back to live stats so the user
		# sees something within the first second.
		snap = prof.get_live_stats()

	# Build sortable rows. Sort by window_max_us desc.
	var entries: Array = []
	for key in snap.keys():
		var e: Dictionary = snap[key]
		entries.append({
			"key": key,
			"category": e.get("category", "OTHER"),
			"last_us": e.get("last_frame_us", 0),
			"avg_us": (e.get("window_sum_us", 0) / max(1, e.get("frame_count", 1))) as int,
			"max_us": e.get("window_max_us", 0),
		})
	entries.sort_custom(func(a, b): return a.max_us > b.max_us)

	# Frame budget @ 60 fps = 16667 µs.
	const FRAME_BUDGET_US: int = 16667

	for i in ROW_LIMIT:
		var row: HBoxContainer = _overview_row_pool[i]
		var labels: Array = row.get_meta("labels")
		if i >= entries.size():
			(labels[0] as Label).text = ""
			(labels[1] as Label).text = ""
			(labels[2] as Label).text = ""
			(labels[3] as Label).text = ""
			(labels[4] as Label).text = ""
			(labels[5] as Label).text = ""
			continue
		var e: Dictionary = entries[i]
		# Strip "CATEGORY." prefix from the display name.
		var key: String = e.key
		var dot: int = key.find(".")
		var name_only: String = key.substr(dot + 1) if dot >= 0 else key
		(labels[0] as Label).text = name_only
		(labels[1] as Label).text = e.category
		(labels[2] as Label).text = _fmt_us(e.last_us)
		(labels[3] as Label).text = _fmt_us(e.avg_us)
		(labels[4] as Label).text = _fmt_us(e.max_us)
		var pct: int = int((float(e.max_us) / float(FRAME_BUDGET_US)) * 100.0)
		(labels[5] as Label).text = "%d%%" % pct
		# Tint max column red if it's eating > 50% of frame budget.
		var col_max: Color = Color(0.95, 0.95, 0.95)
		if pct > 50:
			col_max = Color(1.0, 0.45, 0.45)
		elif pct > 25:
			col_max = Color(1.0, 0.85, 0.35)
		(labels[4] as Label).add_theme_color_override("font_color", col_max)
		(labels[5] as Label).add_theme_color_override("font_color", col_max)


func _fmt_us(us: int) -> String:
	if us < 1000:
		return "%d µs" % us
	if us < 100000:
		return "%.2f ms" % (us / 1000.0)
	return "%d ms" % (us / 1000)


func _refresh_timeline() -> void:
	_timeline_bars_node.queue_redraw()
	# Drill-down: show attribution for the frame under the cursor. We only
	# have the live ring of totals, not per-frame attribution (that's only
	# retained for the last spike + during capture). Show whatever we have.
	var prof: Node = Engine.get_main_loop().root.get_node_or_null("Profiler")
	if prof == null:
		_timeline_detail_label.text = ""
		return
	var ring: Array = prof.get_frame_ring()
	if ring.is_empty():
		_timeline_detail_label.text = ""
		return
	var cursor_idx: int = (ring.size() - 1) - _timeline_cursor
	if cursor_idx < 0: cursor_idx = 0
	var frame_total_us: int = ring[cursor_idx]
	var detail := "Frame offset from now: -%d    Total: %s\n" % [_timeline_cursor, _fmt_us(frame_total_us)]

	# Spike attribution if we have one.
	var spike: Dictionary = prof.get_last_spike()
	if not spike.is_empty():
		detail += "\nLast spike: frame %d, total %s\n" % [spike.frame, _fmt_us(spike.total_us)]
		var attr: Dictionary = spike.attribution
		var rows: Array = []
		for k in attr.keys():
			rows.append([k, attr[k]])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		var shown: int = 0
		for r in rows:
			if shown >= 10:
				break
			detail += "  %-40s %s\n" % [r[0], _fmt_us(r[1])]
			shown += 1
	else:
		# Inline literal — accessing autoload constants by bare identifier
		# doesn't resolve at parse time in Godot 4.x. Keep in sync with
		# Profiler.SPIKE_MS_THRESHOLD if you ever change it (currently 33.0).
		detail += "\n(no spike recorded yet — threshold is 33.0 ms)\n"
	_timeline_detail_label.text = detail


func _refresh_gpu() -> void:
	var fps: int = int(Engine.get_frames_per_second())
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var vram_mb: int = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024 * 1024))
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var bodies: int = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))

	var zylann: Dictionary = _read_zylann_diag()

	var text := "RENDERING\n"
	text += "  FPS                          %d\n" % fps
	text += "  Process / Physics            %.2f ms / %.2f ms\n" % [proc_ms, phys_ms]
	text += "  Draws                        %d\n" % draws
	text += "  Primitives                   %s\n" % _comma_int(prims)
	text += "  Objects in frame             %d\n" % objs
	text += "  VRAM                         %d MB\n" % vram_mb
	text += "\nZYLANN VOXEL\n"
	if zylann.is_empty():
		text += "  (no VoxelLodTerrain found in scene)\n"
	else:
		for k in ["time_detect_required_blocks", "time_io_requests",
				"time_mesh_requests", "time_update_task",
				"blocked_lods", "dropped_block_loads", "dropped_block_meshs"]:
			text += "  %-30s %s\n" % [k, str(zylann.get(k, "-"))]
	text += "\nSCENE\n"
	text += "  Nodes                        %d\n" % nodes
	text += "  Orphan nodes                 %d\n" % orphans
	text += "  Active physics bodies        %d\n" % bodies
	_gpu_label.text = text


func _read_zylann_diag() -> Dictionary:
	# Lazily resolve the active VoxelLodTerrain in the current scene tree.
	if _zylann_terrain == null or not is_instance_valid(_zylann_terrain):
		_zylann_terrain = _find_voxel_terrain()
	if _zylann_terrain == null:
		return {}
	# Zylann exposes get_statistics() returning a Dictionary of these keys.
	if not _zylann_terrain.has_method("get_statistics"):
		return {}
	return _zylann_terrain.call("get_statistics")


func _find_voxel_terrain() -> Node:
	# Walk the scene tree once looking for a VoxelLodTerrain node.
	# Cheap enough at the page-refresh cadence (only when the GPU page is
	# active) and self-healing across scene changes.
	var root: Node = get_tree().root
	return _walk_for_terrain(root)


func _walk_for_terrain(node: Node) -> Node:
	if node.get_class() == "VoxelLodTerrain":
		return node
	for child in node.get_children():
		var found := _walk_for_terrain(child)
		if found != null:
			return found
	return null


func _comma_int(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = s[i] + out
		count += 1
	return out
