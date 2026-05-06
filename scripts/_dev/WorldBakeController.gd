extends Node3D
# WorldBakeController — drives the Copper Isles world bake.
#
# What this does in plain English:
#
#   The Copper Isles map is fixed (heightmap-driven, every player gets the
#   same terrain). Today, the runtime regenerates voxel chunks on every
#   fresh load — the CopperIslesHeightmapGenerator runs on Zylann's
#   worker threads. That's wasted work for a static map.
#
#   This controller walks an invisible viewer across the entire world in
#   a grid, lets Zylann stream + persist every chunk into a SQLite cache
#   at user://baked_baseline.sqlite, and provides a UI to start / pause
#   / cancel the process plus copy the finished DB into assets/voxel/
#   for shipping.
#
#   The bake runs at the canonical terrain.transform.scale (1/6, ≈ 6
#   voxels per metre). World metres × 6 = voxel-grid coordinates.
#
# Attached to the root node of scenes/_dev/BakeWorld.tscn.

# =============================================================
# CONFIGURATION
# =============================================================

@export var voxel_terrain_path: NodePath = "VoxelLodTerrain"

# Walker tile size in WORLD METRES. Each tile gets one or more viewer
# placements. With the canonical view_distance of 1500 voxels (250 m
# world), a 200 m tile gives ~50 m of streaming overlap with neighbours
# so no chunk is missed at boundaries.
const TILE_SIZE_M: float = 200.0

# Wait time at each viewer position (seconds) for Zylann to stream
# everything within view_distance and persist it via
# save_generator_output. Conservative — chunks are precious; better to
# wait too long than miss any.
const WAIT_PER_POSITION_S: float = 5.0

# Force a SQLite flush every N tiles. Crash safety + UI file-size
# update cadence.
const SAVE_EVERY_N_TILES: int = 8

# When a column's max_ground_y is taller than this many world metres,
# the walker uses multiple vertical viewer positions to cover the
# whole column. Single-position fallback is correct for low islands
# but misses tall spires.
const MULTI_VERTICAL_THRESHOLD_M: float = 200.0
const VERTICAL_STEP_M: float = 200.0  # spacing between vertical positions on tall columns

# Bake DB path. user:// because res:// is read-only at runtime; a
# separate "Copy to assets/voxel" UI button shifts the finished DB
# into the project tree for PCK inclusion.
const BAKE_DB_PATH: String = "user://baked_baseline.sqlite"
const FINAL_BASELINE_PATH: String = "res://assets/voxel/copper_isles_baseline.sqlite"

# Voxels per world metre at the canonical terrain.transform.scale of
# 1/6. Used to convert tile centres (world metres) into voxel-grid
# coords for generator sampling.
const VOXELS_PER_METRE: float = 6.0


# =============================================================
# STATE
# =============================================================

var _viewer: Node = null
var _running: bool = false
var _cancel_requested: bool = false
var _pause_requested: bool = false
var _bake_start_time_ms: int = 0
var _tiles_done: int = 0
var _tiles_total: int = 0
var _tile_durations_ms: Array[int] = []  # rolling 10-tile window for ETA
var _current_tile_xz: Vector2 = Vector2.ZERO

# UI references — built programmatically in _build_ui().
var _ui_root: CanvasLayer
var _btn_diagnostics: Button
var _btn_bake_1km: Button
var _btn_bake_5km: Button
var _btn_pause: Button
var _btn_cancel: Button
var _btn_copy: Button
var _label_status: Label
var _label_progress: Label
var _label_filesize: Label
var _label_eta: Label
var _label_current_tile: Label
var _progress_bar: ProgressBar
var _diag_text: TextEdit


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # don't run anything in the editor's tool context
	_build_ui()
	_configure_terrain()
	_set_status("Ready. Run Diagnostics first to verify Zylann APIs, then Bake 1 km central.")


func _configure_terrain() -> void:
	# Mirror CopperIslesTestBootstrap's terrain wiring (32-bit colour,
	# threaded mesh updates, edit-manager hand-off). Without this, mining
	# in the bake scene would be broken — mostly irrelevant since the
	# bake doesn't use mining, but the format settings are also what
	# make the SQLite cache valid for the actual game scene.
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null:
		push_error("[Bake] VoxelLodTerrain not found at: %s" % voxel_terrain_path)
		return
	if "format" in terrain:
		_configure_voxel_format(terrain)
	if "threaded_update_enabled" in terrain:
		terrain.set("threaded_update_enabled", true)
	if "collision_update_delay" in terrain:
		terrain.set("collision_update_delay", 0.1)


func _configure_voxel_format(terrain: Object) -> void:
	# Lifted from CopperIslesTestBootstrap. CHANNEL_COLOR must be
	# 32-bit so packed RGBA + material id survive storage.
	var fmt: Resource = null
	if ClassDB.class_exists("VoxelFormat"):
		fmt = ClassDB.instantiate("VoxelFormat")
	if fmt == null:
		return
	if fmt.has_method("set_channel_depth"):
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_DATA5, VoxelBuffer.DEPTH_8_BIT)
	terrain.set("format", fmt)


# =============================================================
# UI — built programmatically (matches DebugOverlay style)
# =============================================================

func _build_ui() -> void:
	_ui_root = CanvasLayer.new()
	_ui_root.layer = 100
	add_child(_ui_root)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.08, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(bg)

	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(560, 0)
	_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var heading := Label.new()
	heading.text = "COPPER ISLES — WORLD BAKE TOOL"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color(1.0, 0.93, 0.55, 1.0))
	vbox.add_child(heading)

	_label_status = _make_label("Initialising...")
	vbox.add_child(_label_status)

	vbox.add_child(_make_divider())

	# Buttons.
	_btn_diagnostics = _make_button("1. Run Diagnostics  (probe Zylann APIs)")
	_btn_diagnostics.pressed.connect(_on_run_diagnostics)
	vbox.add_child(_btn_diagnostics)

	_btn_bake_1km = _make_button("2a. Bake 1 km central  (validation; ~2-5 min)")
	_btn_bake_1km.pressed.connect(_on_bake_1km)
	vbox.add_child(_btn_bake_1km)

	_btn_bake_5km = _make_button("2b. Bake full 5 km  (~30-90 min)")
	_btn_bake_5km.pressed.connect(_on_bake_5km)
	vbox.add_child(_btn_bake_5km)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	_btn_pause = _make_button("Pause")
	_btn_pause.pressed.connect(_on_pause_pressed)
	_btn_pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cancel = _make_button("Cancel")
	_btn_cancel.pressed.connect(_on_cancel_pressed)
	_btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_btn_pause)
	hbox.add_child(_btn_cancel)
	vbox.add_child(hbox)

	vbox.add_child(_make_divider())

	# Live counters.
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0
	_progress_bar.max_value = 1
	_progress_bar.value = 0
	_progress_bar.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(_progress_bar)

	_label_progress = _make_label("Progress: —")
	vbox.add_child(_label_progress)
	_label_eta = _make_label("ETA: —")
	vbox.add_child(_label_eta)
	_label_current_tile = _make_label("Current tile: —")
	vbox.add_child(_label_current_tile)
	_label_filesize = _make_label("Bake DB size: —")
	vbox.add_child(_label_filesize)

	vbox.add_child(_make_divider())

	_btn_copy = _make_button("3. Copy bake DB → assets/voxel/copper_isles_baseline.sqlite")
	_btn_copy.pressed.connect(_on_copy_to_assets)
	vbox.add_child(_btn_copy)

	var btn_bake_skirt: Button = _make_button("4. Bake horizon skirt → assets/voxel/copper_isles_skirt.res")
	btn_bake_skirt.pressed.connect(_on_bake_skirt)
	vbox.add_child(btn_bake_skirt)

	vbox.add_child(_make_divider())

	# Diagnostics output area.
	var diag_label := Label.new()
	diag_label.text = "Diagnostic output:"
	diag_label.add_theme_font_size_override("font_size", 13)
	diag_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	vbox.add_child(diag_label)
	_diag_text = TextEdit.new()
	_diag_text.editable = false
	_diag_text.custom_minimum_size = Vector2(0, 280)
	_diag_text.scroll_fit_content_height = false
	_diag_text.placeholder_text = "(Click Run Diagnostics)"
	vbox.add_child(_diag_text)

	# Refresh timer for live counters during a bake.
	var refresh := Timer.new()
	refresh.wait_time = 1.0
	refresh.autostart = true
	refresh.timeout.connect(_refresh_live_counters)
	add_child(refresh)


func _make_label(initial: String) -> Label:
	var l := Label.new()
	l.text = initial
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 32)
	return b


func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.35, 0.35, 0.35, 1.0)
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _set_status(msg: String) -> void:
	if _label_status != null:
		_label_status.text = msg


func _diag_print(line: String) -> void:
	# Append a line to the in-panel diagnostic area AND to the Output panel
	# so the developer can grep either way.
	print(line)
	if _diag_text != null:
		_diag_text.text += line + "\n"


func _refresh_live_counters() -> void:
	if not _running:
		_label_filesize.text = "Bake DB size: %s" % _format_filesize(_db_filesize_bytes())
		return
	var pct: float = 0.0
	if _tiles_total > 0:
		pct = float(_tiles_done) / float(_tiles_total)
	_progress_bar.value = pct
	_label_progress.text = "Progress: %d / %d tiles  (%.1f%%)" % [_tiles_done, _tiles_total, pct * 100.0]
	_label_eta.text = "ETA: %s" % _eta_string()
	_label_current_tile.text = "Current tile: world (%.0f, %.0f) m" % [_current_tile_xz.x, _current_tile_xz.y]
	_label_filesize.text = "Bake DB size: %s" % _format_filesize(_db_filesize_bytes())


func _eta_string() -> String:
	if _tile_durations_ms.is_empty():
		return "calculating..."
	var avg_ms: float = 0.0
	for d in _tile_durations_ms:
		avg_ms += d
	avg_ms /= _tile_durations_ms.size()
	var remaining_ms: float = avg_ms * float(_tiles_total - _tiles_done)
	var remaining_s: int = int(remaining_ms / 1000.0)
	if remaining_s < 60:
		return "%d s" % remaining_s
	@warning_ignore("integer_division")
	var minutes_part: int = remaining_s / 60
	if remaining_s < 3600:
		return "%d min %d s" % [minutes_part, remaining_s % 60]
	@warning_ignore("integer_division")
	var hours_part: int = remaining_s / 3600
	@warning_ignore("integer_division")
	var minutes_in_hour: int = (remaining_s % 3600) / 60
	return "%d h %d min" % [hours_part, minutes_in_hour]


# =============================================================
# DIAGNOSTICS — probe Zylann APIs at runtime
# =============================================================

func _on_run_diagnostics() -> void:
	_diag_text.text = ""
	_diag_print("=== Zylann VoxelTools API probe ===")
	_diag_print("Time: %s" % Time.get_datetime_string_from_system())

	# Probe 1: VoxelViewer instantiation.
	var viewer_class_exists: bool = ClassDB.class_exists("VoxelViewer")
	_diag_print("[1] ClassDB.class_exists('VoxelViewer'): %s" % viewer_class_exists)
	if viewer_class_exists:
		var test_viewer = ClassDB.instantiate("VoxelViewer")
		_diag_print("    instantiated OK: %s" % (test_viewer != null))
		if test_viewer != null:
			if "view_distance" in test_viewer:
				test_viewer.view_distance = 1500
				_diag_print("    view_distance writable: yes (set to %d)" % test_viewer.view_distance)
			else:
				_diag_print("    view_distance NOT in property list — !!!")
			# Free the probe instance. Use plain if-statement (the
			# ternary form fails because queue_free() returns void —
			# can't be assembled into a ternary expression result).
			if test_viewer is Node:
				(test_viewer as Node).queue_free()
			elif test_viewer is RefCounted:
				pass  # RefCounted auto-frees when the local var goes out of scope

	# Probe 2: VoxelStreamScript subclass-ability.
	var stream_script_exists: bool = ClassDB.class_exists("VoxelStreamScript")
	_diag_print("[2] ClassDB.class_exists('VoxelStreamScript'): %s" % stream_script_exists)
	# Subclassability: an `extends VoxelStreamScript` GDScript would be
	# the next test, but that's a load-time check — see the
	# VoxelStreamFallthrough.gd compile result.

	# Probe 3: VoxelLodTerrain properties + signals.
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null:
		_diag_print("[3] VoxelLodTerrain NOT found at %s — skipping property/signal dump." % voxel_terrain_path)
	else:
		_diag_print("[3] VoxelLodTerrain properties (filtered to streaming-relevant):")
		for prop in terrain.get_property_list():
			var pname: String = prop.get("name", "")
			# Filter to relevant streaming properties.
			if "stream" in pname.to_lower() or "block" in pname.to_lower() or \
					"queue" in pname.to_lower() or "save" in pname.to_lower() or \
					"thread" in pname.to_lower() or "lod" in pname.to_lower():
				_diag_print("      %s = %s" % [pname, terrain.get(pname)])
		_diag_print("[3] VoxelLodTerrain signals:")
		for sig in terrain.get_signal_list():
			_diag_print("      signal %s" % sig.get("name", "?"))
		# Save method probe.
		_diag_print("    has_method('save_modified_blocks'): %s" % terrain.has_method("save_modified_blocks"))

	# Probe 4: VoxelStreamSQLite property dump.
	if terrain != null and "stream" in terrain:
		var stream: Resource = terrain.get("stream")
		if stream != null:
			_diag_print("[4] VoxelStreamSQLite properties:")
			for prop in stream.get_property_list():
				var pname: String = prop.get("name", "")
				if pname == "" or pname.begins_with("script") or pname == "resource_local_to_scene":
					continue
				if pname == "resource_path" or pname == "resource_name":
					continue
				_diag_print("      %s = %s" % [pname, stream.get(pname)])
		else:
			_diag_print("[4] terrain.stream is null.")

	_diag_print("=== End probe ===")
	_diag_print("Update design/COPPER_ISLES_BAKE_NOTES.md with these findings.")


# =============================================================
# BAKE — region presets
# =============================================================

func _on_bake_1km() -> void:
	# 1 km × 1 km centred on world (0, 0). With the heightmap centred
	# on origin, this catches the central island ("Caer Aelynd" per
	# the spec) plus immediate neighbours.
	_start_bake(Vector2(-500, -500), Vector2(500, 500))


func _on_bake_5km() -> void:
	# Full 5 km × 5 km. Matches the heightmap's exact extent.
	_start_bake(Vector2(-2500, -2500), Vector2(2500, 2500))


func _start_bake(min_xz: Vector2, max_xz: Vector2) -> void:
	if _running:
		_set_status("Already running. Cancel first.")
		return
	_running = true
	_cancel_requested = false
	_pause_requested = false
	_bake_start_time_ms = Time.get_ticks_msec()
	_tiles_done = 0
	_tile_durations_ms.clear()
	_set_status("Baking %.0f m × %.0f m region..." % [
		max_xz.x - min_xz.x, max_xz.y - min_xz.y,
	])
	_bake_region(min_xz, max_xz)


func _bake_region(min_xz: Vector2, max_xz: Vector2) -> void:
	var generator: Resource = _get_generator()
	if generator == null:
		_set_status("ABORT — generator not found on terrain.")
		_running = false
		return

	# Pre-pass: scan the EXR (via the generator) at tile granularity.
	# Builds an ordered list of tile centres that have any land. Skips
	# pure-ocean tiles entirely (~40 % of the full 5 km region).
	_set_status("Scanning EXR for land-bearing tiles...")
	await get_tree().process_frame
	var land_tiles: Array[Vector2] = _scan_land_tiles(generator, min_xz, max_xz)
	_tiles_total = land_tiles.size()
	_set_status("Found %d land-bearing tiles. Spawning phantom viewer." % _tiles_total)
	await get_tree().process_frame

	# Phantom viewer.
	if not ClassDB.class_exists("VoxelViewer"):
		_set_status("ABORT — VoxelViewer class unavailable.")
		_running = false
		return
	_viewer = ClassDB.instantiate("VoxelViewer")
	if _viewer == null:
		_set_status("ABORT — could not instantiate VoxelViewer.")
		_running = false
		return
	if "view_distance" in _viewer:
		_viewer.view_distance = 1500
	add_child(_viewer)

	# Walk.
	var terrain := get_node_or_null(voxel_terrain_path)
	for tile_center in land_tiles:
		if _cancel_requested:
			break
		while _pause_requested:
			await get_tree().process_frame
		_current_tile_xz = tile_center
		var tile_start_ms: int = Time.get_ticks_msec()

		# Compute vertical positions for this tile based on max_ground.
		var voxel_x: int = int(tile_center.x * VOXELS_PER_METRE)
		var voxel_z: int = int(tile_center.y * VOXELS_PER_METRE)
		var max_ground_voxels: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z)
		var max_ground_world_m: float = float(max_ground_voxels) / VOXELS_PER_METRE
		var positions: Array[float] = _vertical_positions_for_tile(max_ground_world_m)

		for y_world in positions:
			if _cancel_requested:
				break
			(_viewer as Node3D).global_position = Vector3(tile_center.x, y_world, tile_center.y)
			# Wait for Zylann to stream + persist. Conservative fixed wait;
			# can be replaced with a real idle signal if Phase 0 finds one.
			await _wait_seconds(WAIT_PER_POSITION_S)

		_tiles_done += 1
		var dur: int = Time.get_ticks_msec() - tile_start_ms
		_tile_durations_ms.append(dur)
		if _tile_durations_ms.size() > 10:
			_tile_durations_ms.pop_front()

		if _tiles_done % SAVE_EVERY_N_TILES == 0:
			await _flush_save(terrain)

	# Final flush.
	await _flush_save(terrain)

	# Tear down phantom viewer.
	if _viewer != null:
		_viewer.queue_free()
		_viewer = null

	_running = false
	if _cancel_requested:
		_set_status("Cancelled at tile %d/%d." % [_tiles_done, _tiles_total])
	else:
		var elapsed_min: float = (Time.get_ticks_msec() - _bake_start_time_ms) / 60000.0
		_set_status("DONE — %d tiles in %.1f minutes. DB size: %s." % [
			_tiles_done, elapsed_min, _format_filesize(_db_filesize_bytes()),
		])


func _vertical_positions_for_tile(max_ground_world_m: float) -> Array[float]:
	# Returns the list of viewer Y positions to visit for this tile.
	# For low islands one position suffices (view_distance covers the
	# whole vertical column). Tall peaks need multiple positions
	# stepping up at VERTICAL_STEP_M increments.
	var positions: Array[float] = []
	if max_ground_world_m <= MULTI_VERTICAL_THRESHOLD_M:
		# Single position: midway between sea floor and peak. View
		# sphere reaches well above peak and well below sea floor.
		positions.append(max(0.0, max_ground_world_m * 0.5))
	else:
		# Multi-position: step from base to peak at VERTICAL_STEP_M.
		var y: float = 0.0
		while y <= max_ground_world_m + VERTICAL_STEP_M:
			positions.append(y)
			y += VERTICAL_STEP_M
	return positions


func _scan_land_tiles(generator: Resource, min_xz: Vector2, max_xz: Vector2) -> Array[Vector2]:
	# Sample the EXR at each tile centre. Tiles whose centre is land
	# (ground above sea level) get baked; tiles whose centre is ocean
	# get skipped to save time.
	#
	# Subtle: a tile could be 95 % ocean with one bright pixel near a
	# corner that the centre sample misses. We tolerate that — those
	# edge cases will get baked when the player walks into them at
	# runtime. The pre-pass is a fast filter, not exhaustive coverage.
	var tiles: Array[Vector2] = []
	var sea_level_voxels: int = generator.get("sea_level_voxels") if "sea_level_voxels" in generator else 0
	var x: float = min_xz.x + TILE_SIZE_M * 0.5
	while x < max_xz.x:
		var z: float = min_xz.y + TILE_SIZE_M * 0.5
		while z < max_xz.y:
			var voxel_x: int = int(x * VOXELS_PER_METRE)
			var voxel_z: int = int(z * VOXELS_PER_METRE)
			var ground_y: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z)
			# Land = ground at or above sea level. Tiny margin so the
			# coastline still gets baked from the ocean side too.
			if ground_y >= sea_level_voxels - 4:
				tiles.append(Vector2(x, z))
			z += TILE_SIZE_M
		x += TILE_SIZE_M
	return tiles


func _flush_save(terrain: Object) -> void:
	# Force Zylann to flush any in-memory blocks to SQLite. The real
	# behaviour of save_modified_blocks (sync vs async, awaitable vs
	# fire-and-forget) is unverified — see Phase 0. Awaiting it is
	# safe even if it returns nothing; Godot resolves immediately.
	if terrain == null or not terrain.has_method("save_modified_blocks"):
		return
	var result = terrain.call("save_modified_blocks")
	if result is Signal:
		await result


func _wait_seconds(seconds: float) -> void:
	# get_tree().create_timer is the simplest pause that respects the
	# scene tree (handles pause/cancel cleanly via the per-frame yield).
	var timer := get_tree().create_timer(seconds)
	await timer.timeout


# =============================================================
# UI EVENT HANDLERS
# =============================================================

func _on_pause_pressed() -> void:
	_pause_requested = not _pause_requested
	_btn_pause.text = "Resume" if _pause_requested else "Pause"
	_set_status("Paused." if _pause_requested else "Resumed.")


func _on_cancel_pressed() -> void:
	if not _running:
		_set_status("Nothing to cancel.")
		return
	_cancel_requested = true
	_set_status("Cancel requested — finishing current tile...")


func _on_bake_skirt() -> void:
	# Bake the low-LOD horizon skirt for the entire 5 km × 5 km region.
	# Saves to res://assets/voxel/copper_isles_skirt.res so it ships in
	# the PCK and gets loaded by HorizonSkirt at runtime. Cheap enough
	# (~12k triangles) to bake synchronously — done in a few seconds.
	if _running:
		_set_status("Bake in progress; cancel first.")
		return
	var generator: Resource = _get_generator()
	if generator == null:
		_set_status("Skirt bake: generator not found.")
		return
	# Force the EXR to load (and the max-gray scan to run) before we
	# sample heights — without this the first 1000+ get_ground_voxel_y_at
	# calls would each trigger a load attempt.
	if generator.has_method("_ensure_image"):
		generator.call("_ensure_image")
	_set_status("Baking horizon skirt...")
	await get_tree().process_frame
	var mesh: ArrayMesh = SkirtBaker.bake_mesh(
		generator,
		Vector2(-2500.0, -2500.0),
		Vector2(2500.0, 2500.0),
		VOXELS_PER_METRE,
	)
	if mesh == null:
		_set_status("Skirt bake failed — see Output panel.")
		return
	const SKIRT_PATH: String = "res://assets/voxel/copper_isles_skirt.res"
	var err: int = ResourceSaver.save(mesh, SKIRT_PATH)
	if err == OK:
		_set_status("Skirt baked → %s" % SKIRT_PATH)
	else:
		_set_status("Skirt save failed (err=%d)" % err)


func _on_copy_to_assets() -> void:
	# Copy the bake DB from user:// into assets/voxel/ so it ships in
	# the PCK. Only allowed when the bake isn't running (concurrent
	# read/write of an open SQLite is a recipe for corruption).
	if _running:
		_set_status("Cannot copy while baking. Cancel or finish first.")
		return
	var src: String = ProjectSettings.globalize_path(BAKE_DB_PATH)
	var dst: String = ProjectSettings.globalize_path(FINAL_BASELINE_PATH)
	if not FileAccess.file_exists(BAKE_DB_PATH):
		_set_status("Bake DB not found at %s — run a bake first." % BAKE_DB_PATH)
		return
	var err: int = DirAccess.copy_absolute(src, dst)
	if err == OK:
		_set_status("Copied %s → %s" % [BAKE_DB_PATH, FINAL_BASELINE_PATH])
	else:
		_set_status("Copy failed (err=%d). Check the destination directory exists." % err)


# =============================================================
# HELPERS
# =============================================================

func _get_generator() -> Resource:
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null or not "generator" in terrain:
		return null
	return terrain.get("generator") as Resource


func _db_filesize_bytes() -> int:
	var total: int = 0
	for path in [BAKE_DB_PATH, BAKE_DB_PATH + "-wal", BAKE_DB_PATH + "-journal"]:
		if FileAccess.file_exists(path):
			var f: FileAccess = FileAccess.open(path, FileAccess.READ)
			if f != null:
				total += f.get_length()
				f.close()
	return total


func _format_filesize(bytes: int) -> String:
	if bytes == 0:
		return "(empty)"
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	if bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
	return "%.2f GB" % (float(bytes) / (1024.0 * 1024.0 * 1024.0))
