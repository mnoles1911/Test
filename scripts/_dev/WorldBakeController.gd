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

## When true, the walker's pre-pass scans the EXR for tiles with land
## and skips pure-ocean tiles (faster bake, but the runtime cache
## won't contain water voxels — player will see only grey skirt over
## the sea). Use for fast iteration bakes when you're tuning land
## materials. Leave OFF for production bakes — the user actually
## wants the ocean to be ocean.
@export var scan_land_only_for_speed: bool = false

# Walker tile size in WORLD METRES. Sized for LOD0 coverage at the
# runtime's lod_distance:
#
#   LOD0 radius (m world) = lod_distance / 6     (terrain.scale = 1/6)
#   For full corner-to-corner coverage on an axis-aligned grid:
#     S × √2 / 2 ≤ R   →   S ≤ R × √2
#
#   lod_distance = 128  →  R = 21 m  →  S ≤ 30 m   (CURRENT)
#
# Zylann caps lod_distance at 128 (verified via the probe button),
# so this is the only working value pair. Earlier we set
# TILE_SIZE_M=180 sized for an imaginary lod_distance=768 — caused
# 95% LOD0 cache misses because the real LOD0 was only 21 m.
#
# Bake time scales as (1/S)²:
#   1 km² @ 30 m → 33² ≈ 1089 tiles → ~75 min @ 4 s/tile
#   5 km² @ 30 m → 167² ≈ 28000 tiles → ~31 hours overnight
# To shorten bakes, drop voxel resolution (3 vox/m would give R=43m
# and let TILE_SIZE_M go to ~60 → 9× fewer tiles).
const TILE_SIZE_M: float = 30.0

# Wait time at each viewer position (seconds) for Zylann to stream
# everything within view_distance and persist it via
# save_generator_output. Bumped 2026-05-08 from 4 → 6 to give the
# larger view sphere (8000 vox / 1333 m, matched to runtime) time
# to resolve all LODs. Per-tile chunk count is significantly higher
# than at the old 1500-vox viewer because LOD4-6 are now in scope.
# With 12 worker threads chunks usually finish in 3-4 s; 6 s leaves
# margin for the slowest tiles.
const WAIT_PER_POSITION_S: float = 6.0

# Force a SQLite flush every N tiles. Crash safety + UI file-size
# update cadence.
const SAVE_EVERY_N_TILES: int = 8

# Tile classification + walker stop offsets.
# Per design/COPPER_ISLES_BAKE_NOTES.md "Walker plan — surface-band,
# ±30 m editing window" (2026-05-09). The player edits voxels almost
# exclusively within ±30 m of the local ground surface; the bake
# covers exactly that band per land tile, plus an upward margin for
# scaffold/tower placements. LOD0 sphere radius is ≈21 m world
# (lod_distance=128 vox at 1/6 scale), so two stops 42 m apart
# overlap and bound a 60 m+ band cleanly.
enum TileClass {
	LAND,           # gray ≥ 2× ocean threshold; full surface band
	COAST,          # narrow beach band; treat like land but use sea level as anchor
	SHALLOW_OCEAN,  # below sea level, has land/coast neighbour within 1 tile
	DEEP_OCEAN,     # below sea level, isolated → SKIP (horizon plane covers it)
}

# World-metre offsets relative to the anchor point for each class:
#   LAND uses  ground+offset
#   COAST + SHALLOW_OCEAN use  sea_level+offset
const STOP_LAND_BELOW: float = -9.0    # ground − 9   covers ground−30..+12
const STOP_LAND_ABOVE: float = 33.0    # ground + 33  covers ground+12..+54
const STOP_COAST_LOW: float  = 5.0     # sea + 5      covers sea−16..+26
const STOP_COAST_HIGH: float = 35.0    # sea + 35     covers sea+14..+56
const STOP_SHALLOW: float    = 5.0     # sea + 5      single stop, covers sea−16..+26

# Beach band: how many voxels above sea level still counts as COAST
# rather than LAND. Mirrors generator.beach_y_threshold semantics —
# kept generous so the walker uses the sea-level-anchored stops where
# the visual sand band actually exists.
const COAST_BAND_VOXELS_ABOVE_SEA: int = 12   # = 2 m world

# Legacy multi-vertical knobs — retained for backward-compat with
# code paths that may still reference them. The new classifier-driven
# walker plan above renders these moot for the production bake. Don't
# rely on these for sweep behaviour; use _vertical_positions_for_class.
const MULTI_VERTICAL_THRESHOLD_M: float = 99999.0
const VERTICAL_STEP_M: float = 200.0

# Bake DB path. user:// because res:// is read-only at runtime; a
# separate "Copy to assets/voxel" UI button shifts the finished DB
# into the project tree for PCK inclusion.
#
# Versioned baseline path — bumped whenever generator output
# changes shape. Matches CopperIslesTestBootstrap.BAKED_BASELINE_PATH
# so a fresh bake lands at the path the runtime reads.
#   _v13: textured tileset (CHANNEL_COLOR → CHANNEL_TYPE)
#   _v14: Tiers 1-6 generation rules (cliff / snow / jitter /
#         ore veins / disks / cliff outcrops)
const BAKE_DB_PATH: String = "user://baked_baseline_v14.sqlite"
const FINAL_BASELINE_PATH: String = "res://assets/voxel/copper_isles_baseline_v14.sqlite"

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
var _btn_bake_2km: Button
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
	# Mark as a developer test scene — keeps gameplay UI autoloads
	# (HUDOverlay, PauseMenu, JournalUI, SaveNotification) dormant.
	# See GameState.is_dev_scene() for the contract.
	add_to_group("dev_scene")
	_build_ui()
	_configure_terrain()
	_probe_sqlite_stream_for_pragma_hooks()
	_set_status("Ready. Run Diagnostics first to verify Zylann APIs, then Bake 1 km central.")


# =============================================================
# ONE-SHOT SPIKE — does VoxelStreamSQLite expose PRAGMA hooks?
# =============================================================
#
# WAL mode + larger cache + `synchronous=NORMAL` gives SQLite a
# 1.2-2× write throughput boost. To wire it into the bake we need
# Zylann to expose journal_mode / synchronous / cache_size / page_size
# as @export properties on VoxelStreamSQLite, OR expose methods that
# accept arbitrary PRAGMAs.
#
# This probe dumps the stream's property + method lists at scene load
# and tries to set each common PRAGMA name to see if Zylann accepts
# the value (no error + readable back). Output goes to the Output
# panel. Once we know what's available, we wire the optimization
# permanently and delete this probe.
func _probe_sqlite_stream_for_pragma_hooks() -> void:
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null or not ("stream" in terrain):
		print("[Spike-SQLite] terrain or stream missing; skipping probe")
		return
	var stream: Resource = terrain.get("stream") as Resource
	if stream == null:
		print("[Spike-SQLite] stream is null; skipping probe")
		return
	print("=============================================================")
	print("[Spike-SQLite] PROBE START — stream class: %s" % stream.get_class())
	print("=============================================================")
	# 1. Property list — anything PRAGMA-shaped?
	var pragma_keywords: PackedStringArray = PackedStringArray([
		"journal", "synchronous", "cache_size", "page_size", "wal",
		"mode", "pragma", "transaction", "batch", "flush", "fsync"
	])
	var found_props: Array[String] = []
	for prop in stream.get_property_list():
		var pname: String = prop.get("name", "")
		if pname == "" or pname.begins_with("script") or pname.begins_with("resource"):
			continue
		var ptype: int = int(prop.get("type", 0))
		var phint: int = int(prop.get("hint", 0))
		var phint_string: String = str(prop.get("hint_string", ""))
		var keyword_hit: bool = false
		for kw in pragma_keywords:
			if pname.findn(kw) != -1:
				keyword_hit = true
				break
		var marker: String = " <-- PRAGMA candidate" if keyword_hit else ""
		print("[Spike-SQLite]   prop: %s (type=%d hint=%d '%s')%s" % [
			pname, ptype, phint, phint_string, marker,
		])
		if keyword_hit:
			found_props.append(pname)
	# 2. Method list — anything PRAGMA-shaped?
	var found_methods: Array[String] = []
	for m in stream.get_method_list():
		var mname: String = m.get("name", "")
		if mname == "" or mname.begins_with("_"):
			continue
		for kw in pragma_keywords:
			if mname.findn(kw) != -1:
				print("[Spike-SQLite]   method: %s  <-- PRAGMA candidate" % mname)
				found_methods.append(mname)
				break
	# 3. Trial sets for common PRAGMA names. If a property exists and
	# accepts the value (readable back as set), it's wireable.
	var trial_values: Dictionary = {
		"journal_mode": 3,        # often an enum: 0=DEFAULT 1=DELETE 2=TRUNCATE 3=WAL...
		"synchronous": 1,         # 0=OFF 1=NORMAL 2=FULL
		"cache_size": -65536,     # negative = KB; -65536 = 64 MB
		"page_size": 8192,        # bytes
	}
	for k in trial_values.keys():
		if k in stream:
			var before = stream.get(k)
			stream.set(k, trial_values[k])
			var after = stream.get(k)
			var ok: bool = after == trial_values[k]
			print("[Spike-SQLite]   trial set %s: before=%s → asked %s → after=%s%s" % [
				k, before, trial_values[k], after, " ✓" if ok else " ✗ (rejected)",
			])
			# Restore so the bake's default behaviour isn't perturbed.
			stream.set(k, before)
	print("[Spike-SQLite] SUMMARY: %d PRAGMA-looking properties, %d PRAGMA-looking methods" % [
		found_props.size(), found_methods.size(),
	])
	if found_props.is_empty() and found_methods.is_empty():
		print("[Spike-SQLite] No native hooks found. Options: (a) godot-sqlite addon, (b) write PRAGMA via raw SQLite FFI before stream open, (c) skip WAL.")
	print("=============================================================")


# Terrain config the bake MUST run with. These are the same values
# scenes/CopperIslesTest.tscn uses at runtime — chunks cached at
# different LOD addressing won't be served. We enforce them in
# script (rather than trusting only the .tscn) because Godot's editor
# has been observed silently reverting .tscn properties to "defaults"
# on save, producing baked DBs the runtime can't read. Set once here
# at startup; takes effect before the first viewer placement.
const REQUIRED_LOD_COUNT: int = 9
const REQUIRED_LOD_DISTANCE: float = 128.0
const REQUIRED_SECONDARY_LOD_DISTANCE: float = 128.0
const REQUIRED_LOD_FADE_DURATION: float = 1.0
const REQUIRED_STREAMING_SYSTEM: int = 1   # 1 = CLIPBOX, 0 = LEGACY_OCTREE


# =============================================================
# BAKE PERF — temporary overrides applied during the bake walk
# =============================================================
#
# The bake doesn't need visuals or collision — it just needs the
# generator output persisted to the stream SQLite. Two tweaks
# applied at bake-start and reverted at bake-end:
#
# (1) Skip LOD 0. The bake walker cannot densely sample LOD 0
#     across the full region in reasonable time (radius 21 m at
#     30 m tile spacing → mostly-but-not-perfectly overlapping
#     spheres; misses still cause empty LOD 0 entries to be
#     persisted, which then OVERRIDE the runtime generator).
#     Solution: shrink lod_distance to a value smaller than the
#     data-block size (16 voxels) so no LOD 0 chunk's center can
#     fall inside the viewer's LOD 0 sphere → Zylann never
#     requests LOD 0 → no empty LOD 0 entries written to SQLite.
#     Runtime live-generates LOD 0 on demand (fast — small block).
#
# (2) Skip meshing. The viewer triggers chunk LOADs which run
#     the generator and persist via cache_generated_blocks. The
#     meshing step is required for visuals and collision but not
#     for the persisted data. Disabling the mesher during bake
#     skips that GPU+CPU work, ~1.5-3× wall-clock speedup.
#
# Both overrides revert in a finally-style cleanup at the end
# of `_bake_region` (and on cancel), so the BakeWorld scene's
# observer camera still gets a normally-rendering terrain
# between bakes if the user re-runs interactively.

const BAKE_LOD_DISTANCE: float = 8.0     # < 16 vox data-block size → no LOD0 requests
const BAKE_DISABLE_MESHING: bool = true  # set false to debug bake-time visuals
# All MUST match CopperIslesTestBootstrap.REQUIRED_*. lod_distance
# capped at 128 by Zylann (probe-verified). lod_count=9 covers LODs
# out to LOD8 (~5.5 km world at lod_distance=128). Trimmed 2026-05-07
# from 14 — the upper shells sat outside view_distance permanently
# and only added bookkeeping cost. Zylann MAX_LOD is 24, well within.
# Lowering only affects future bakes; existing baselines remain
# readable (Zylann ignores LOD slots above the active lod_count).


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
		# Property is INT in this Zylann build; 0.1 truncates to 0.
		# 100 = ~100 ms batching window for collision-shape rebuilds.
		terrain.set("collision_update_delay", 100)
	# mesh_block_size: 32 makes each rendered mesh cover 8× more voxels
	# than the default 16. World3DBootstrap forces it programmatically;
	# we mirror that here so bake and runtime configurations match.
	if "mesh_block_size" in terrain:
		terrain.set("mesh_block_size", 32)
		print("[Bake] terrain.mesh_block_size set to 32 (actual=%s)" % terrain.get("mesh_block_size"))

	# Belt-and-suspenders LOD enforcement. Override the .tscn values in
	# case Godot editor's normalisation stripped them. Print the before/
	# after so any silent revert is visible in the Output panel.
	_enforce_lod_config(terrain)


func _enforce_lod_config(terrain: Object) -> void:
	var fields: Array = [
		["lod_count", REQUIRED_LOD_COUNT],
		["lod_distance", REQUIRED_LOD_DISTANCE],
		["secondary_lod_distance", REQUIRED_SECONDARY_LOD_DISTANCE],
		["lod_fade_duration", REQUIRED_LOD_FADE_DURATION],
		["streaming_system", REQUIRED_STREAMING_SYSTEM],
		["cache_generated_blocks", true],
	]
	var changes_made: int = 0
	var clamps_detected: int = 0
	for f in fields:
		var key: String = f[0]
		var want = f[1]
		if not key in terrain:
			push_warning("[Bake] terrain has no property '%s' — Zylann version mismatch?" % key)
			continue
		var before = terrain.get(key)
		if before == want:
			# Already correct — silent success.
			continue
		terrain.set(key, want)
		# Verify the set actually took. Zylann silently CLAMPS some
		# properties (e.g., lod_distance has a hard max at 128). If
		# the after-value differs from `want`, the cache-contract is
		# effectively whatever Zylann allowed.
		var after = terrain.get(key)
		changes_made += 1
		if after != want:
			clamps_detected += 1
			push_error("[Bake] CLAMP DETECTED on terrain.%s: asked %s, got %s (Zylann silently capped)" % [
				key, want, after,
			])
		print("[Bake] enforced terrain.%s: %s → %s (actual after set: %s)" % [
			key, before, want, after,
		])
	# Always emit a one-line summary so the developer gets visible
	# confirmation the enforcement ran, even when no drift was found.
	if changes_made == 0:
		print("[Bake] LOD config already aligned — all %d required properties match. No enforcement needed." % fields.size())
	elif clamps_detected > 0:
		print("[Bake] LOD config enforcement: %d changes, %d CLAMPS — see [CLAMP DETECTED] lines above." % [changes_made, clamps_detected])
	else:
		print("[Bake] LOD config enforcement: %d changes applied successfully, no clamps." % changes_made)


func _configure_voxel_format(terrain: Object) -> void:
	# v13 textured tileset: CHANNEL_TYPE (8-bit) carries the
	# material_id integer that VoxelMesherBlocky reads; CHANNEL_DATA5
	# (8-bit) carries water source bytes. Must match CopperIslesTest
	# runtime so cached baseline chunks read back correctly.
	var fmt: Resource = null
	if ClassDB.class_exists("VoxelFormat"):
		fmt = ClassDB.instantiate("VoxelFormat")
	if fmt == null:
		return
	if fmt.has_method("set_channel_depth"):
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_8_BIT)
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

	_btn_bake_1km = _make_button("2a. Bake 1 km central  (validation; ~110 min)")
	_btn_bake_1km.pressed.connect(_on_bake_1km)
	vbox.add_child(_btn_bake_1km)

	_btn_bake_2km = _make_button("2b. Bake 2 km central  (working dev bake; ~7 hr)")
	_btn_bake_2km.pressed.connect(_on_bake_2km)
	vbox.add_child(_btn_bake_2km)

	_btn_bake_5km = _make_button("2c. Bake full 5 km  (overnight; ~47 hr / ~14 hr land-only+3s)")
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

	_btn_copy = _make_button("3. Copy bake DB → assets/voxel/copper_isles_baseline_v14.sqlite")
	_btn_copy.pressed.connect(_on_copy_to_assets)
	vbox.add_child(_btn_copy)

	var btn_bake_skirt: Button = _make_button("4. Bake horizon skirt → assets/voxel/copper_isles_skirt.res")
	btn_bake_skirt.pressed.connect(_on_bake_skirt)
	vbox.add_child(btn_bake_skirt)

	# Manual flush — useful when debugging persistence issues. Calls
	# save_modified_blocks on the terrain immediately so you can
	# verify the SQLite file size grows.
	var btn_force_save: Button = _make_button("Force Save (manual SQLite flush)")
	btn_force_save.pressed.connect(_on_force_save)
	vbox.add_child(btn_force_save)

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

	# Lod-distance probe — sweeps a range of values and reports what
	# Zylann actually accepts. Diagnoses the silent-clamp problem
	# without re-baking. Result tells us what TILE_SIZE_M to use.
	var btn_probe_lod: Button = _make_button("Probe lod_distance accepted range")
	btn_probe_lod.pressed.connect(_on_probe_lod_distance)
	vbox.add_child(btn_probe_lod)

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
				# Probe sentinel: match the actual bake walker's
				# view_distance (line 676) so the diagnostic mirrors
				# what the bake will use.
				test_viewer.view_distance = 8000
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
	# Quick validation pass — 1 km × 1 km centred on world (0, 0).
	# Useful for sanity-checking config changes before committing to
	# longer bakes.
	_start_bake(Vector2(-500, -500), Vector2(500, 500))


func _on_bake_2km() -> void:
	# 2 km × 2 km centred on world (0, 0). The "real" working bake
	# for active dev — covers the central archipelago islands the
	# player spawns in (Player3D.SPAWN_POSITION = (0, 500, 0)) plus
	# enough surroundings to fly a few hundred metres in any
	# direction without hitting uncached territory.
	# At 30 m walker + 4 s/tile + ~4400 tiles ≈ ~5 hours.
	_start_bake(Vector2(-1000, -1000), Vector2(1000, 1000))


func _on_bake_5km() -> void:
	# Full 5 km × 5 km. Matches the heightmap's exact extent. Long
	# bake (~31 hours at default settings; ~9 hours with land-only
	# + 2 s wait). Run overnight or over a weekend.
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

	# Pre-pass: scan the EXR for tiles + classify each as
	# LAND / COAST / SHALLOW_OCEAN / DEEP_OCEAN. Deep-ocean tiles are
	# skipped (the horizon plane covers their visuals; first runtime
	# dive triggers cache_generated_blocks fill on demand).
	_set_status("Scanning EXR + classifying tiles...")
	await get_tree().process_frame
	var all_tiles: Array[Vector2] = _scan_land_tiles(generator, min_xz, max_xz)
	# Pull sea-level + beach-band thresholds from the generator config,
	# fall back to defaults if the property doesn't exist on this build.
	var sea_level_voxels: int = 1200
	if "sea_level_voxels" in generator:
		sea_level_voxels = int(generator.get("sea_level_voxels"))
	var coast_band_top_voxels: int = sea_level_voxels + COAST_BAND_VOXELS_ABOVE_SEA
	if "beach_y_threshold" in generator:
		coast_band_top_voxels = int(generator.get("beach_y_threshold"))
	var sea_level_world_m: float = float(sea_level_voxels) / VOXELS_PER_METRE

	var tile_classes: Dictionary = _classify_tiles(
			generator, all_tiles, sea_level_voxels, coast_band_top_voxels)

	# Build the actual walk list: skip DEEP_OCEAN tiles entirely.
	var bake_tiles: Array[Vector2] = []
	var counts: Dictionary = {
		TileClass.LAND: 0,
		TileClass.COAST: 0,
		TileClass.SHALLOW_OCEAN: 0,
		TileClass.DEEP_OCEAN: 0,
	}
	for tile in all_tiles:
		var c: int = tile_classes[tile]
		counts[c] += 1
		if c != TileClass.DEEP_OCEAN:
			bake_tiles.append(tile)
	_tiles_total = bake_tiles.size()
	_set_status("Tile classification: %d LAND, %d COAST, %d SHALLOW, %d DEEP (skipped). Walking %d tiles." % [
		counts[TileClass.LAND], counts[TileClass.COAST],
		counts[TileClass.SHALLOW_OCEAN], counts[TileClass.DEEP_OCEAN],
		_tiles_total,
	])
	print("[Bake] sea_level world Y=%.1f m  coast band top vox=%d" % [
		sea_level_world_m, coast_band_top_voxels])
	print("[Bake] tile classes: LAND=%d  COAST=%d  SHALLOW=%d  DEEP=%d  (skipped DEEP, baking %d / %d)" % [
		counts[TileClass.LAND], counts[TileClass.COAST],
		counts[TileClass.SHALLOW_OCEAN], counts[TileClass.DEEP_OCEAN],
		_tiles_total, all_tiles.size(),
	])
	await get_tree().process_frame

	# Resolve the bake terrain once. Subsequent lod_distance / mesher
	# overrides target this node.
	var terrain := get_node_or_null(voxel_terrain_path)

	# --- Apply BAKE-ONLY perf overrides ---
	# Both are reverted in the cleanup tail at the end of this function.
	var bake_lod_distance_before: float = 0.0
	var bake_mesher_before: Resource = null
	if terrain != null:
		# (1) Disable LOD 0 generation. See BAKE_LOD_DISTANCE comment.
		if "lod_distance" in terrain:
			bake_lod_distance_before = float(terrain.get("lod_distance"))
			terrain.set("lod_distance", BAKE_LOD_DISTANCE)
			print("[Bake] lod_distance: %s → %s (LOD 0 disabled during bake)" % [
				bake_lod_distance_before, terrain.get("lod_distance"),
			])
		# (2) Detach the mesher. See BAKE_DISABLE_MESHING comment.
		# Stash the current mesher so we can restore it on completion.
		if BAKE_DISABLE_MESHING and "mesher" in terrain:
			bake_mesher_before = terrain.get("mesher") as Resource
			terrain.set("mesher", null)
			print("[Bake] mesher detached for bake (was %s) — skipping mesh build for perf." % [
				bake_mesher_before.get_class() if bake_mesher_before != null else "null",
			])

	# Phantom viewer.
	if not ClassDB.class_exists("VoxelViewer"):
		_set_status("ABORT — VoxelViewer class unavailable.")
		_restore_bake_overrides(terrain, bake_lod_distance_before, bake_mesher_before)
		_running = false
		return
	_viewer = ClassDB.instantiate("VoxelViewer")
	if _viewer == null:
		_set_status("ABORT — could not instantiate VoxelViewer.")
		_restore_bake_overrides(terrain, bake_lod_distance_before, bake_mesher_before)
		_running = false
		return
	if "view_distance" in _viewer:
		# Phantom viewer view_distance MUST match (or exceed) the
		# runtime player's view_distance, or the bake won't generate
		# chunks at LODs whose outer ring exceeds 1500 vox. With
		# runtime view_distance = 8000 vox, the previous 1500 captured
		# LODs 0-3 fully but missed LOD4 (radius 2048 vox), LOD5 (4096),
		# LOD6 (8192). Those chunks cache-missed at runtime → generator
		# fired at L4-L7 unnecessarily. Matching to 8000 makes each
		# bake tile load all LODs the runtime will request.
		_viewer.view_distance = 8000
	add_child(_viewer)

	# Walk.
	for tile_center in bake_tiles:
		if _cancel_requested:
			break
		while _pause_requested:
			await get_tree().process_frame
		_current_tile_xz = tile_center
		var tile_start_ms: int = Time.get_ticks_msec()

		# Compute vertical positions based on tile classification.
		var tile_class: int = tile_classes[tile_center]
		var voxel_x: int = int(tile_center.x * VOXELS_PER_METRE)
		var voxel_z: int = int(tile_center.y * VOXELS_PER_METRE)
		var ground_voxels: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z)
		var ground_world_m: float = float(ground_voxels) / VOXELS_PER_METRE
		var positions: Array[float] = _vertical_positions_for_class(
				tile_class, ground_world_m, sea_level_world_m)

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

	# Park the phantom viewer 100 km away so Zylann unloads every chunk
	# in the bake region. With cache_generated_blocks=true on the
	# terrain, unloading triggers a save-before-evict for each block
	# — that's how generator output reaches SQLite.
	_set_status("Bake walk done. Parking viewer + flushing chunks to disk...")
	await _park_viewer_far_and_drain(terrain)

	# Final flush — ensures any in-flight save tasks settle before we
	# tell the user the bake is done.
	await _flush_save(terrain)

	# Tear down phantom viewer.
	if _viewer != null:
		_viewer.queue_free()
		_viewer = null

	# Revert bake-only overrides so the BakeWorld scene's observer
	# camera renders normally if the user runs another bake or just
	# pokes around interactively after this one.
	_restore_bake_overrides(terrain, bake_lod_distance_before, bake_mesher_before)

	_running = false
	if _cancel_requested:
		_set_status("Cancelled at tile %d/%d." % [_tiles_done, _tiles_total])
	else:
		var elapsed_min: float = (Time.get_ticks_msec() - _bake_start_time_ms) / 60000.0
		_set_status("DONE — %d tiles in %.1f minutes. DB size: %s." % [
			_tiles_done, elapsed_min, _format_filesize(_db_filesize_bytes()),
		])


func _restore_bake_overrides(
		terrain: Object,
		lod_distance_before: float,
		mesher_before: Resource
) -> void:
	# Counterpart of the bake-start overrides. Safe to call multiple
	# times — `lod_distance_before == 0.0` means we never applied the
	# override (terrain was null or didn't have the property), so we
	# skip the restore.
	if terrain == null:
		return
	if lod_distance_before > 0.0 and "lod_distance" in terrain:
		terrain.set("lod_distance", lod_distance_before)
		print("[Bake] lod_distance restored: %s" % terrain.get("lod_distance"))
	if BAKE_DISABLE_MESHING and mesher_before != null and "mesher" in terrain:
		terrain.set("mesher", mesher_before)
		print("[Bake] mesher restored.")


func _vertical_positions_for_class(
		tile_class: int,
		ground_world_m: float,
		sea_level_world_m: float
) -> Array[float]:
	# Returns the list of viewer Y positions to visit for this tile,
	# parameterised by tile class. See TileClass enum and the STOP_*
	# constants for the rationale. Deep ocean returns an empty array
	# (skipped — horizon plane covers visuals; first dive at runtime
	# triggers cache_generated_blocks fill).
	var positions: Array[float] = []
	match tile_class:
		TileClass.LAND:
			positions.append(ground_world_m + STOP_LAND_BELOW)
			positions.append(ground_world_m + STOP_LAND_ABOVE)
		TileClass.COAST:
			positions.append(sea_level_world_m + STOP_COAST_LOW)
			positions.append(sea_level_world_m + STOP_COAST_HIGH)
		TileClass.SHALLOW_OCEAN:
			positions.append(sea_level_world_m + STOP_SHALLOW)
		TileClass.DEEP_OCEAN:
			pass  # skipped
	return positions


func _classify_tiles(
		generator: Resource,
		tiles: Array[Vector2],
		sea_level_voxels: int,
		coast_band_top_voxels: int
) -> Dictionary:
	# Classifies every tile in the bake region. Two passes:
	#   1. Per-tile ground-Y vs sea level: LAND / COAST / OCEAN(provisional)
	#   2. For each ocean tile, check 8 neighbours. If any neighbour is
	#      LAND or COAST, promote to SHALLOW_OCEAN; else DEEP_OCEAN.
	# Tiles outside the bake region are unknown — edge ocean tiles that
	# border land beyond the region get classified as DEEP, which is a
	# minor over-skip but acceptable.
	var classes: Dictionary = {}
	# Pass 1
	for tile in tiles:
		var voxel_x: int = int(tile.x * VOXELS_PER_METRE)
		var voxel_z: int = int(tile.y * VOXELS_PER_METRE)
		var ground: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z)
		if ground < sea_level_voxels:
			classes[tile] = TileClass.SHALLOW_OCEAN  # provisional
		elif ground < coast_band_top_voxels:
			classes[tile] = TileClass.COAST
		else:
			classes[tile] = TileClass.LAND
	# Pass 2: ocean tiles with no land/coast neighbour become DEEP_OCEAN.
	# Build a Vector2 lookup by quantising tile centres so cross-tile
	# float arithmetic doesn't miss the dictionary key.
	for tile in tiles:
		if classes[tile] != TileClass.SHALLOW_OCEAN:
			continue
		var has_shore: bool = false
		for dx in [-TILE_SIZE_M, 0.0, TILE_SIZE_M]:
			for dz in [-TILE_SIZE_M, 0.0, TILE_SIZE_M]:
				if dx == 0.0 and dz == 0.0:
					continue
				var n_key: Vector2 = Vector2(tile.x + dx, tile.y + dz)
				if classes.has(n_key):
					var nc: int = classes[n_key]
					if nc == TileClass.LAND or nc == TileClass.COAST:
						has_shore = true
						break
			if has_shore:
				break
		if not has_shore:
			classes[tile] = TileClass.DEEP_OCEAN
	return classes


func _class_name(tile_class: int) -> String:
	match tile_class:
		TileClass.LAND: return "LAND"
		TileClass.COAST: return "COAST"
		TileClass.SHALLOW_OCEAN: return "SHALLOW"
		TileClass.DEEP_OCEAN: return "DEEP"
	return "?"


func _scan_land_tiles(generator: Resource, min_xz: Vector2, max_xz: Vector2) -> Array[Vector2]:
	# Returns every tile in the bake region. Earlier this filtered out
	# pure-ocean tiles to save bake time, but that left the runtime
	# without any cached water voxels — the user saw grey skirt mesh
	# everywhere instead of an actual sea around the islands. Now we
	# include all tiles so the generator's CHANNEL_DATA5 water bytes
	# (LOD0-only, emitted for every column where ground < sea_level)
	# get persisted into the cache during the bake.
	#
	# Bake-time cost: ~10× more tiles than land-only at full 5 km, but
	# ocean tiles process faster (the generator early-outs on most
	# vertical bands since there's no ground above sea level). Net
	# wall-clock cost is ~3× the old land-only bake.
	#
	# If you need a fast iteration bake (e.g. validating a change to
	# the LAND material bands), set scan_land_only_for_speed = true on
	# the controller node — the heightmap pre-pass returns only the
	# land tiles like before.
	var tiles: Array[Vector2] = []
	var x: float = min_xz.x + TILE_SIZE_M * 0.5
	while x < max_xz.x:
		var z: float = min_xz.y + TILE_SIZE_M * 0.5
		while z < max_xz.y:
			if scan_land_only_for_speed:
				var voxel_x: int = int(x * VOXELS_PER_METRE)
				var voxel_z: int = int(z * VOXELS_PER_METRE)
				var ground_y: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z)
				var sea_level_voxels: int = generator.get("sea_level_voxels") if "sea_level_voxels" in generator else 0
				if ground_y >= sea_level_voxels - 4:
					tiles.append(Vector2(x, z))
			else:
				tiles.append(Vector2(x, z))
			z += TILE_SIZE_M
		x += TILE_SIZE_M
	return tiles


func _flush_save(terrain: Object) -> void:
	# Ask Zylann to flush in-memory blocks to SQLite. Fire-and-forget
	# — earlier we awaited the return value, but the empirical 96 %
	# hang showed that awaiting can stall indefinitely (the returned
	# Signal apparently never fires in some cases, possibly because
	# there's nothing to save). The save proceeds on a worker thread
	# anyway; we just give it a couple of frames to drain.
	if terrain == null or not terrain.has_method("save_modified_blocks"):
		return
	terrain.call("save_modified_blocks")
	# Yield three frames so the worker pool gets CPU time before the
	# next walker step crowds it again.
	for _i in 3:
		await get_tree().process_frame


func _park_viewer_far_and_drain(terrain: Object) -> void:
	# After the walker finishes, move the phantom viewer far outside
	# the bake region so Zylann unloads every chunk. With
	# cache_generated_blocks=true on the terrain, unloading triggers
	# the per-block "save before evict" pathway — exactly what makes
	# generator output land in SQLite. Without this step, the last
	# tile's chunks may stay in memory and never persist.
	if _viewer == null:
		return
	(_viewer as Node3D).global_position = Vector3(100_000.0, 0.0, 100_000.0)
	# Generous wait — chunks have to unload, which fires save events
	# that drain through the worker pool to SQLite.
	await _wait_seconds(8.0)
	await _flush_save(terrain)
	await _wait_seconds(2.0)


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


func _on_probe_lod_distance() -> void:
	# Try a sweep of lod_distance values and report what each one
	# actually settles at after the property setter runs. Zylann
	# silently clamps lod_distance — this tells us the real ceiling
	# so we can pick an appropriate value (and matching walker tile
	# spacing) rather than guessing.
	#
	# Reads back via terrain.get(key) immediately after the set so
	# we capture any setter-clamping the engine does. If a value
	# matches the asked-for value, that's accepted; otherwise it's
	# clamped (and the actual cap is revealed).
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null or not "lod_distance" in terrain:
		_diag_print("[Probe] No terrain or no lod_distance property; aborting.")
		return
	var saved_original = terrain.get("lod_distance")
	_diag_print("=== lod_distance acceptance probe ===")
	_diag_print("  saved original value: %s" % saved_original)
	var test_values: Array = [16, 32, 64, 96, 128, 160, 192, 256, 384, 512, 768, 1024]
	for v in test_values:
		terrain.set("lod_distance", float(v))
		var actual = terrain.get("lod_distance")
		var verdict: String
		if absf(float(actual) - float(v)) < 0.01:
			verdict = "ACCEPTED"
		else:
			verdict = "CLAMPED → %s" % actual
		_diag_print("  asked %4d  →  %s" % [v, verdict])
	# Restore the original so the bake state isn't disturbed.
	terrain.set("lod_distance", saved_original)
	var restored = terrain.get("lod_distance")
	_diag_print("  restored to: %s" % restored)
	_diag_print("=== End probe ===")


func _on_force_save() -> void:
	# Manual save trigger. Calls save_modified_blocks on the live
	# terrain. Reports DB size before/after so the developer can see
	# whether the flush actually wrote anything.
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null:
		_set_status("Force Save: terrain not found.")
		return
	var size_before: int = _db_filesize_bytes()
	_set_status("Force Save: flushing... (was %s)" % _format_filesize(size_before))
	await _flush_save(terrain)
	var size_after: int = _db_filesize_bytes()
	_set_status("Force Save done: %s → %s (delta %s)" % [
		_format_filesize(size_before),
		_format_filesize(size_after),
		_format_filesize(size_after - size_before),
	])


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
	# Bake area extends 1.5 km past the heightmap edge so the player
	# standing on a peak doesn't see the skirt cut off short. The
	# generator returns deep-ocean ground for out-of-bounds samples,
	# so the extension reads as flat sea-floor — fine since the water
	# horizon plane covers it visually.
	var mesh: ArrayMesh = SkirtBaker.bake_mesh(
		generator,
		Vector2(-4000.0, -4000.0),
		Vector2(4000.0, 4000.0),
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
	# Ensure the destination directory exists. DirAccess.copy_absolute
	# does NOT auto-create parents, so a missing assets/voxel/ folder
	# (fresh clone, accidental deletion) silently fails the copy with
	# err=ERR_CANT_OPEN — which is what bit us 2026-05-10 morning.
	var dst_dir: String = dst.get_base_dir()
	if not DirAccess.dir_exists_absolute(dst_dir):
		var mk_err: int = DirAccess.make_dir_recursive_absolute(dst_dir)
		if mk_err != OK:
			_set_status("Copy failed: could not create destination dir %s (err=%d)" % [dst_dir, mk_err])
			return
		print("[Bake] created missing destination directory: %s" % dst_dir)
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
