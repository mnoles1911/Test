extends CanvasLayer
# DebugOverlay — Autoload. F1 toggles the dev panel.
#
# THREE TABS (cycle with TAB while panel is open):
#   1. COMMANDS    — clickable dev buttons (DELETE ALL SAVES, etc.)
#   2. CONSOLE     — recent player-action log (mining, throwing,
#                    saving, loading) — last MAX_LOG_ENTRIES events
#   3. PLAYER STATE — live position, rotation, HP, endurance,
#                    equipped item, raycast target
#
# Player-action code calls DebugOverlay.log_action(msg) to push an
# entry into the console buffer. The same method also writes to
# Godot's print() stream so the Output panel keeps working.
#
# Always-on HUD (rendered separately from the F1 panel and visible
# during normal play, when DebugOverlay.enabled = true):
#   - Top-left coords:  X N  Y N  Z N
#   - AIM label:         (x,y,z)  dist Nm
#   - Crosshair `+` at screen center
#
# Set `enabled = false` for release builds — hides everything.


# =============================================================
# CONFIGURATION
# =============================================================

@export var enabled: bool = true

const MAX_LOG_ENTRIES: int = 100
# Ring-buffer cap for the CONSOLE tab. Older entries fall off as
# new actions log.

const DELETE_SAVES_ARM_SECONDS: float = 3.0
# Two-click confirmation window for the DELETE ALL SAVES button.


# =============================================================
# STATE
# =============================================================

var _root: Control
var _tab_label: Label

# Tab containers (one VBox per tab, only one visible at a time).
var _commands_tab: VBoxContainer
var _console_tab: VBoxContainer
var _player_state_tab: VBoxContainer

# Commands tab — three sub-views inside the COMMANDS tab. Only one
# is visible at a time; the rest are hidden. Sub-views switch by
# clicking a command in the list, and BACK in a sub-view returns.
enum CommandView { LIST, DELETE_SAVE, TELEPORT, TIME_SKIP, VIEW_DIST, WEATHER }
var _commands_view: CommandView = CommandView.LIST

# Sub-view containers.
var _commands_list_view: VBoxContainer
var _commands_delete_save_view: VBoxContainer
var _commands_teleport_view: VBoxContainer
var _commands_time_view: VBoxContainer
var _commands_view_dist_view: VBoxContainer
var _commands_weather_view: VBoxContainer

# Command list buttons.
var _btn_delete_all: Button
var _btn_delete_one: Button
var _btn_teleport: Button
var _btn_advance_day: Button
var _btn_advance_time: Button
var _btn_fly_mode: Button
var _btn_view_dist: Button
var _btn_weather: Button

# SQLite voxel-cache size readout. Refreshed each time the F1
# overlay opens (cheap — just a stat() on user://voxel_deltas.sqlite
# plus its WAL/journal sidecars). Lives at the top of the command
# list as an info-only row, no button. With full-caching enabled
# (save_generator_output = true on VoxelStreamSQLite), this number
# grows as the player explores; useful for spotting runaway growth.
var _sqlite_size_label: Label

# View-distance sub-view.
var _view_dist_back_btn: Button
var _view_dist_label: Label
var _view_dist_minus_500: Button
var _view_dist_minus_100: Button
var _view_dist_plus_100: Button
var _view_dist_plus_500: Button

# WEATHER sub-view widgets. One button per State plus override-clear,
# force-lightning, and live readouts for current state and wind.
var _weather_back_btn: Button
var _weather_state_label: Label
var _weather_wind_label: Label
var _weather_state_buttons: Dictionary = {}  # state_id -> Button
var _weather_clear_override_btn: Button
var _weather_force_lightning_btn: Button

# DELETE ALL SAVES — two-click confirm state.
var _delete_saves_armed: bool = false
var _delete_saves_arm_remaining: float = 0.0

# DELETE A SAVE sub-view.
var _delete_save_back_btn: Button
var _delete_save_list: VBoxContainer

# TELEPORT sub-view.
var _teleport_x_edit: LineEdit
var _teleport_y_edit: LineEdit
var _teleport_z_edit: LineEdit
var _teleport_confirm_btn: Button
var _teleport_back_btn: Button

# Time-skip sub-view fields.
var _time_days_edit: LineEdit
var _time_hours_edit: LineEdit
var _time_confirm_btn: Button
var _time_back_btn: Button

# Console tab.
var _console_scroll: ScrollContainer
var _console_label: Label
var _action_log: Array[String] = []

# Player state tab.
var _ps_position_label: Label
var _ps_rotation_label: Label
var _ps_pitch_label: Label
var _ps_health_label: Label
var _ps_endurance_label: Label
var _ps_equipped_label: Label
var _ps_aim_label: Label
var _ps_time_label: Label
var _ps_played_label: Label

# Always-on HUD (visible without F1).
var _coords_label: Label
var _aim_label: Label
var _world_time_label: Label
var _terrain_scale_label: Label
var _crosshair_root: Control

# Top-RIGHT FPS + worst-frame-ms readout. Used to live on HUDOverlay
# but moved here on 2026-05-06 — the FPS readout is dev info, sits
# better next to coords / aim / world-time on the dev overlay than on
# the player-facing HUD chrome. Visible whenever DebugOverlay.enabled
# is true, regardless of whether a player is in the tree (so it works
# on the title screen, settings, dev scenes, etc.).
var _fps_label: Label

# Frame-time sliding window for spike detection. 60 samples = ~1 sec
# at 60fps, ~0.4 sec at 144fps. Long enough to catch the periodic
# chunk-streaming hitches; short enough that the worst-ms readout
# updates fast as stutters come and go. Pre-allocated so the per-
# frame writeback doesn't allocate.
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _frame_times_idx: int = 0

# F7 cycles through these voxels-per-metre values for the Copper Isles
# scale-test scene. Stored as (vox_per_metre, terrain_scale) pairs;
# terrain_scale = 1 / vox_per_metre — keeping both pre-computed avoids
# float-division noise in the comparison and read-back path.
const F7_CYCLE: Array = [
	{"vox_per_m": 6, "scale": 1.0 / 6.0},
	{"vox_per_m": 8, "scale": 1.0 / 8.0},
	{"vox_per_m": 10, "scale": 1.0 / 10.0},
]
# Index of the entry F7 will apply on its NEXT press. Advances after
# every press so the cycle reads 6 → 8 → 10 → 6 → ... regardless of
# whether F5 / F6 / F8 / F9 also fired in between.
var _f7_next_index: int = 0

enum DebugTab { COMMANDS, CONSOLE, PLAYER_STATE }
const TAB_NAMES: Array[String] = ["COMMANDS", "CONSOLE", "PLAYER STATE"]
var _current_tab: DebugTab = DebugTab.COMMANDS


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 98
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_overlay_panel()
	_build_coords_hud()
	_build_aim_hud()
	_build_world_time_hud()
	_build_terrain_scale_hud()
	_build_fps_hud()
	_build_crosshair()
	_root.visible = false

	# Pre-size the frame-time ring so per-frame writes don't allocate.
	_frame_times.resize(60)
	for i in _frame_times.size():
		_frame_times[i] = 0.0

	log_action("DebugOverlay initialized.")


func _process(delta: float) -> void:
	if not enabled:
		return

	# Top-left HUD labels (coords / aim / world time) and the
	# crosshair are gameplay-only — hide them when no player is in
	# the tree (title screen, settings, load picker, etc.). Same
	# pattern as _update_crosshair_visibility below.
	var has_player: bool = not get_tree().get_nodes_in_group("player").is_empty()
	if _coords_label != null:
		_coords_label.visible = has_player
		if has_player:
			_update_coords_label()
	if _aim_label != null:
		_aim_label.visible = has_player
		if has_player:
			_update_aim_label()
	if _world_time_label != null:
		_world_time_label.visible = has_player
		if has_player:
			_update_world_time_label()
	# Terrain-scale readout — visible only when the active scene owns
	# a VoxelLodTerrain (the Copper Isles test scene + main world).
	# `_update_terrain_scale_label` does its own present/absent check.
	if _terrain_scale_label != null:
		_update_terrain_scale_label()
	# FPS / worst-ms readout — always on while DebugOverlay.enabled.
	if _fps_label != null:
		_update_fps_label(delta)
	_update_crosshair_visibility()

	# DELETE ALL SAVES auto-disarm timer.
	if _delete_saves_armed:
		_delete_saves_arm_remaining -= delta
		if _delete_saves_arm_remaining <= 0.0:
			_disarm_delete_saves()

	# Live PLAYER STATE refresh while the panel is open on that tab.
	if _root.visible and _current_tab == DebugTab.PLAYER_STATE:
		_refresh_player_state_tab()

	# Live WEATHER readout refresh while the submenu is open.
	if _root.visible and _current_tab == DebugTab.COMMANDS and _commands_view == CommandView.WEATHER:
		_refresh_weather_labels()


# =============================================================
# UI — overlay panel (the F1 toggleable thing)
# =============================================================

func _build_overlay_panel() -> void:
	# Root Control covers the screen; bg is a translucent dark
	# fill; tab label sits at the top; three tab containers
	# stack below (only one visible).
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_tab_label = Label.new()
	_tab_label.position = Vector2(12, 8)
	_tab_label.add_theme_font_size_override("font_size", 18)
	_tab_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4, 1))
	_tab_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tab_label)

	_commands_tab = _make_tab_container()
	_console_tab  = _make_tab_container()
	_player_state_tab = _make_tab_container()
	_build_commands_tab()
	_build_console_tab()
	_build_player_state_tab()
	_show_tab(_current_tab)


func _make_tab_container() -> VBoxContainer:
	# Tab content sits under the tab label. Anchored full-rect with
	# top inset so it doesn't overlap the title.
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_top = 44
	v.offset_right = -16
	v.offset_bottom = -16
	v.add_theme_constant_override("separation", 10)
	v.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(v)
	return v


# --- Commands tab ---

func _build_commands_tab() -> void:
	# Top-level heading shared across all command sub-views.
	var heading := Label.new()
	heading.text = "DEV COMMANDS"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_tab.add_child(heading)

	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(0.35, 0.35, 0.35, 1)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_tab.add_child(div)

	_build_commands_list_view()
	_build_commands_delete_save_view()
	_build_commands_teleport_view()
	_build_commands_time_view()
	_build_commands_view_dist_view()
	_build_commands_weather_view()
	_show_command_list()


# --- Commands LIST view (default — clickable command rows) ---

func _build_commands_list_view() -> void:
	_commands_list_view = VBoxContainer.new()
	_commands_list_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_list_view.add_theme_constant_override("separation", 4)
	_commands_tab.add_child(_commands_list_view)

	# --- Info row: voxel-cache size (top of list, above buttons) ---
	# Auto-refreshed each time the overlay's commands tab is shown.
	_sqlite_size_label = Label.new()
	_sqlite_size_label.text = "Voxel cache: —"
	_sqlite_size_label.add_theme_font_size_override("font_size", 14)
	_sqlite_size_label.add_theme_color_override("font_color", Color(0.65, 0.85, 0.95, 1))
	_sqlite_size_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sqlite_size_label.custom_minimum_size = Vector2(0, 26)
	_commands_list_view.add_child(_sqlite_size_label)

	# Thin divider so the info row reads as separate from the button list.
	var info_div := ColorRect.new()
	info_div.custom_minimum_size = Vector2(0, 1)
	info_div.color = Color(0.25, 0.25, 0.25, 1)
	info_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_list_view.add_child(info_div)

	_btn_delete_all   = _make_command_row("DELETE ALL SAVES")
	_btn_delete_one   = _make_command_row("DELETE A SAVE FILE")
	_btn_teleport     = _make_command_row("TELEPORT PLAYER")
	_btn_advance_day  = _make_command_row("ADVANCE 1 DAY")
	_btn_advance_time = _make_command_row("ADVANCE TIME...")
	_btn_fly_mode     = _make_command_row("TOGGLE FLY MODE")
	_btn_view_dist    = _make_command_row("VIEW DISTANCE...")
	_btn_weather      = _make_command_row("WEATHER...")

	for b in [_btn_delete_all, _btn_delete_one, _btn_teleport,
			_btn_advance_day, _btn_advance_time, _btn_fly_mode,
			_btn_view_dist, _btn_weather]:
		_commands_list_view.add_child(b)
	_refresh_fly_mode_label()


func _make_command_row(label: String) -> Button:
	# Flat, left-aligned button styled as a list row. Visually
	# uniform so the list reads as a menu of equal-weight options.
	var b := Button.new()
	b.text = "  " + label
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


# --- DELETE A SAVE sub-view ---

func _build_commands_delete_save_view() -> void:
	_commands_delete_save_view = VBoxContainer.new()
	_commands_delete_save_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_delete_save_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_commands_delete_save_view.add_theme_constant_override("separation", 6)
	_commands_delete_save_view.visible = false
	_commands_tab.add_child(_commands_delete_save_view)

	_delete_save_back_btn = _make_command_row("← BACK")
	_commands_delete_save_view.add_child(_delete_save_back_btn)

	var hint := Label.new()
	hint.text = "Click a save's DELETE button to remove it."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_delete_save_view.add_child(hint)

	# Scrollable list of saves so an arbitrary number fits.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	_commands_delete_save_view.add_child(scroll)

	_delete_save_list = VBoxContainer.new()
	_delete_save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_save_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_delete_save_list)


func _populate_delete_save_list() -> void:
	# Refreshes the rows from disk every time the sub-view opens
	# so deletions show up live.
	for child in _delete_save_list.get_children():
		child.queue_free()

	if not get_node_or_null("/root/GameState"):
		return
	var saves: Array = GameState.list_save_files()
	if saves.is_empty():
		var empty := Label.new()
		empty.text = "(no saves on disk)"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_delete_save_list.add_child(empty)
		return

	for meta in saves:
		_delete_save_list.add_child(_make_delete_save_row(meta))


func _make_delete_save_row(meta: Dictionary) -> Control:
	# One row per save: name + timestamp on the left, DELETE on the right.
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 36)
	hbox.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.text = "%s   (%s)" % [
		meta.get("save_name", "?"),
		meta.get("timestamp", "?"),
	]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 1))
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info)

	var del := Button.new()
	del.text = "DELETE"
	del.add_theme_font_size_override("font_size", 14)
	del.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
	del.custom_minimum_size = Vector2(80, 32)
	# Stash the filename in the button's metadata so _input dispatch
	# can read it at click time without rebuilding closures.
	del.set_meta("save_filename", meta.get("filename", ""))
	hbox.add_child(del)

	return hbox


# --- TELEPORT sub-view ---

func _build_commands_teleport_view() -> void:
	_commands_teleport_view = VBoxContainer.new()
	_commands_teleport_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_teleport_view.add_theme_constant_override("separation", 8)
	_commands_teleport_view.visible = false
	_commands_tab.add_child(_commands_teleport_view)

	_teleport_back_btn = _make_command_row("← BACK")
	_commands_teleport_view.add_child(_teleport_back_btn)

	var hint := Label.new()
	hint.text = "Type X / Y / Z and click TELEPORT.  Default values are Roland's current position."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_teleport_view.add_child(hint)

	_teleport_x_edit = _make_axis_input("X")
	_teleport_y_edit = _make_axis_input("Y")
	_teleport_z_edit = _make_axis_input("Z")
	_commands_teleport_view.add_child(_make_axis_row("X", _teleport_x_edit))
	_commands_teleport_view.add_child(_make_axis_row("Y", _teleport_y_edit))
	_commands_teleport_view.add_child(_make_axis_row("Z", _teleport_z_edit))

	_teleport_confirm_btn = Button.new()
	_teleport_confirm_btn.text = "TELEPORT"
	_teleport_confirm_btn.add_theme_font_size_override("font_size", 16)
	_teleport_confirm_btn.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))
	_teleport_confirm_btn.custom_minimum_size = Vector2(160, 36)
	_commands_teleport_view.add_child(_teleport_confirm_btn)


func _make_axis_input(axis: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = "%s coord" % axis
	le.add_theme_font_size_override("font_size", 16)
	le.custom_minimum_size = Vector2(140, 30)
	le.process_mode = Node.PROCESS_MODE_ALWAYS
	return le


func _make_axis_row(axis: String, edit: LineEdit) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = axis + ":"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	lbl.custom_minimum_size = Vector2(24, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	row.add_child(edit)
	return row


# --- Sub-view switching ---

func _show_command_list() -> void:
	_commands_view = CommandView.LIST
	if _commands_list_view != null:
		_commands_list_view.visible = true
	if _commands_delete_save_view != null:
		_commands_delete_save_view.visible = false
	if _commands_teleport_view != null:
		_commands_teleport_view.visible = false
	if _commands_time_view != null:
		_commands_time_view.visible = false
	if _commands_view_dist_view != null:
		_commands_view_dist_view.visible = false
	if _commands_weather_view != null:
		_commands_weather_view.visible = false
	# Sync fly-mode label in case the player toggled it via some
	# other route (or returned from a save where fly was on).
	_refresh_fly_mode_label()
	_refresh_sqlite_size_label()


func _refresh_sqlite_size_label() -> void:
	# Sums the SQLite database file plus its sidecar journal/WAL files
	# (SQLite's `journal_mode = WAL` produces a `-wal` file alongside
	# the main DB). Reports the total in MB so the player can see how
	# fast the voxel cache is growing as they explore.
	#
	# DB path is resolved DYNAMICALLY from the active scene's terrain
	# stream — World3D uses `voxel_deltas.sqlite`, CopperIslesTest uses
	# `copper_isles_test.sqlite`, the bake tool uses `baked_baseline.sqlite`,
	# etc. Earlier this method hardcoded the World3D path, which made the
	# label read 20 KB in every other scene.
	if _sqlite_size_label == null:
		return
	var db_path: String = _resolve_active_voxel_db_path()
	if db_path == "":
		_sqlite_size_label.text = "Voxel cache: (no terrain in scene)"
		return
	var total_bytes: int = 0
	for path in [db_path, db_path + "-wal", db_path + "-journal"]:
		if FileAccess.file_exists(path):
			var f: FileAccess = FileAccess.open(path, FileAccess.READ)
			if f != null:
				total_bytes += f.get_length()
				f.close()
	if total_bytes == 0:
		_sqlite_size_label.text = "Voxel cache: (no DB yet)"
		return
	# Format with a unit step that stays readable across the file's
	# growth range — a fresh world is bytes/KB, mid-game is MB, late
	# game is GB.
	var size_str: String
	if total_bytes < 1024:
		size_str = "%d B" % total_bytes
	elif total_bytes < 1024 * 1024:
		size_str = "%.1f KB" % (float(total_bytes) / 1024.0)
	elif total_bytes < 1024 * 1024 * 1024:
		size_str = "%.1f MB" % (float(total_bytes) / (1024.0 * 1024.0))
	else:
		size_str = "%.2f GB" % (float(total_bytes) / (1024.0 * 1024.0 * 1024.0))
	# Strip the user:// prefix for display brevity — the user already
	# knows it's the user-data dir.
	var display_path: String = db_path.replace("user://", "")
	_sqlite_size_label.text = "Voxel cache: %s  (%s)" % [size_str, display_path]


func _resolve_active_voxel_db_path() -> String:
	# Walks the active scene for any VoxelLodTerrain (the same helper
	# the F5–F9 scale hotkeys use), then asks its stream resource for
	# the database_path. Falls back to the legacy World3D path so the
	# label still shows something sensible if no terrain is in the
	# tree (e.g. on the title screen).
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return ""
	var terrains: Array[Node] = []
	_collect_voxel_terrains(scene_root, terrains)
	if terrains.is_empty():
		return ""
	var terrain: Node = terrains[0]
	if not "stream" in terrain:
		return ""
	var stream: Resource = terrain.get("stream") as Resource
	if stream == null or not "database_path" in stream:
		return ""
	return stream.get("database_path") as String


func _show_delete_save_view() -> void:
	_commands_view = CommandView.DELETE_SAVE
	_commands_list_view.visible = false
	_commands_delete_save_view.visible = true
	_commands_teleport_view.visible = false
	_commands_time_view.visible = false
	_populate_delete_save_list()


func _show_teleport_view() -> void:
	_commands_view = CommandView.TELEPORT
	_commands_list_view.visible = false
	_commands_delete_save_view.visible = false
	_commands_teleport_view.visible = true
	_commands_time_view.visible = false

	# Pre-fill the X/Y/Z fields with Roland's current position so
	# small relative teleports ("10 meters that way") are quick.
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var p: Vector3 = (players[0] as Node3D).global_position
		_teleport_x_edit.text = "%.2f" % p.x
		_teleport_y_edit.text = "%.2f" % p.y
		_teleport_z_edit.text = "%.2f" % p.z
	# Focus the X field so the player can start typing immediately.
	_teleport_x_edit.grab_focus()
	_teleport_x_edit.select_all()


func _do_teleport() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		log_action("Teleport: no player in scene")
		return
	var player: Node3D = players[0] as Node3D
	# Float coercion — strings might be "12", "12.5", "-3.14", etc.
	# Empty fields default to current position so the dev can leave
	# axes they don't want to change blank.
	var x: float = float(_teleport_x_edit.text) if _teleport_x_edit.text != "" else player.global_position.x
	var y: float = float(_teleport_y_edit.text) if _teleport_y_edit.text != "" else player.global_position.y
	var z: float = float(_teleport_z_edit.text) if _teleport_z_edit.text != "" else player.global_position.z
	var target := Vector3(x, y, z)
	player.global_position = target
	# Zero velocity so Roland doesn't keep falling through whatever
	# was there before the teleport.
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	log_action("DEV: teleported to (%.2f, %.2f, %.2f)" % [x, y, z])
	_show_command_list()


# --- TIME-SKIP sub-view ---

func _build_commands_time_view() -> void:
	_commands_time_view = VBoxContainer.new()
	_commands_time_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_time_view.add_theme_constant_override("separation", 8)
	_commands_time_view.visible = false
	_commands_tab.add_child(_commands_time_view)

	_time_back_btn = _make_command_row("← BACK")
	_commands_time_view.add_child(_time_back_btn)

	var hint := Label.new()
	hint.text = "Type a number of DAYS and/or HOURS to advance, then click ADVANCE.  Either field can be left blank (treated as 0)."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_time_view.add_child(hint)

	_time_days_edit  = _make_axis_input("days")
	_time_hours_edit = _make_axis_input("hours")
	_commands_time_view.add_child(_make_axis_row("Days",  _time_days_edit))
	_commands_time_view.add_child(_make_axis_row("Hours", _time_hours_edit))

	_time_confirm_btn = Button.new()
	_time_confirm_btn.text = "ADVANCE"
	_time_confirm_btn.add_theme_font_size_override("font_size", 16)
	_time_confirm_btn.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))
	_time_confirm_btn.custom_minimum_size = Vector2(160, 36)
	_commands_time_view.add_child(_time_confirm_btn)


func _show_time_view() -> void:
	_commands_view = CommandView.TIME_SKIP
	_commands_list_view.visible = false
	_commands_delete_save_view.visible = false
	_commands_teleport_view.visible = false
	_commands_time_view.visible = true

	# Default to 0 / 0 so the player isn't forced to clear an old entry.
	_time_days_edit.text = "0"
	_time_hours_edit.text = "0"
	_time_days_edit.grab_focus()
	_time_days_edit.select_all()


func _advance_time(days: int, hours: int) -> void:
	# Single-source-of-truth path through WorldClock.advance_hours so the
	# in-game clock, all the GameState time flags, NPC schedules, and
	# the day-night cycle all roll forward together. Negative inputs
	# are clamped to 0 — going backwards in time would mismatch save
	# state in subtle ways and we don't have a use case for it.
	if days < 0:
		days = 0
	if hours < 0:
		hours = 0
	var total_hours: int = days * 24 + hours
	if total_hours <= 0:
		log_action("DEV: time skip ignored (0 hours requested)")
		return
	if not get_node_or_null("/root/WorldClock"):
		log_action("DEV: time skip failed — WorldClock not available")
		return
	WorldClock.advance_hours(total_hours)
	log_action("DEV: advanced time by %d day(s) %d hour(s) → Day %d %s" % [
		days, hours, WorldClock.current_day, WorldClock.get_time_string()
	])


func _do_advance_time_form() -> void:
	# Read the form inputs, coerce to int, and dispatch via _advance_time.
	# Empty fields are treated as 0 so a user who only fills DAYS gets a
	# pure day skip without having to type "0" into HOURS.
	var days: int = int(_time_days_edit.text) if _time_days_edit.text != "" else 0
	var hours: int = int(_time_hours_edit.text) if _time_hours_edit.text != "" else 0
	_advance_time(days, hours)
	_show_command_list()


# --- FLY MODE toggle ---

func _toggle_fly_mode() -> void:
	# Calls Player3D.toggle_fly_mode and updates the button label so
	# the player can see whether fly is currently engaged. Logs to
	# the action console for after-the-fact debugging.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		log_action("DEV: fly mode toggle ignored — no player in scene")
		return
	var player: Node = players[0]
	if not player.has_method("toggle_fly_mode"):
		log_action("DEV: fly mode toggle ignored — Player3D.toggle_fly_mode missing")
		return
	var now_flying: bool = player.toggle_fly_mode()
	_refresh_fly_mode_label()
	log_action("DEV: fly mode %s" % ("ON" if now_flying else "OFF"))


func _refresh_fly_mode_label() -> void:
	# Mirrors the player's current fly state into the button text so
	# the menu reads "TOGGLE FLY MODE  (ON)" / "(OFF)" at a glance.
	if _btn_fly_mode == null:
		return
	var on: bool = false
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and "is_flying" in players[0]:
		on = bool(players[0].is_flying)
	_btn_fly_mode.text = "  TOGGLE FLY MODE  (%s)" % ("ON" if on else "OFF")


# --- VIEW DISTANCE sub-view ---

func _build_commands_view_dist_view() -> void:
	_commands_view_dist_view = VBoxContainer.new()
	_commands_view_dist_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_view_dist_view.add_theme_constant_override("separation", 10)
	_commands_view_dist_view.visible = false
	_commands_tab.add_child(_commands_view_dist_view)

	_view_dist_back_btn = _make_command_row("← BACK")
	_commands_view_dist_view.add_child(_view_dist_back_btn)

	var hint := Label.new()
	hint.text = "Adjusts VoxelViewer streaming radius live. Higher values show more distant terrain at lower LOD. Very high values may cause stuttering while chunks load."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_view_dist_view.add_child(hint)

	_view_dist_label = Label.new()
	_view_dist_label.add_theme_font_size_override("font_size", 22)
	_view_dist_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))
	_view_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_view_dist_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_view_dist_view.add_child(_view_dist_label)

	# Two rows of step buttons: coarse (+/-500) and fine (+/-100).
	var row_coarse := HBoxContainer.new()
	row_coarse.add_theme_constant_override("separation", 8)
	row_coarse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_view_dist_view.add_child(row_coarse)

	var row_fine := HBoxContainer.new()
	row_fine.add_theme_constant_override("separation", 8)
	row_fine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_view_dist_view.add_child(row_fine)

	_view_dist_minus_500 = _make_step_btn("− 500 m")
	_view_dist_plus_500  = _make_step_btn("+ 500 m")
	_view_dist_minus_100 = _make_step_btn("− 100 m")
	_view_dist_plus_100  = _make_step_btn("+ 100 m")

	row_coarse.add_child(_view_dist_minus_500)
	row_coarse.add_child(_view_dist_plus_500)
	row_fine.add_child(_view_dist_minus_100)
	row_fine.add_child(_view_dist_plus_100)


func _make_step_btn(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _show_view_dist_view() -> void:
	_commands_view = CommandView.VIEW_DIST
	_commands_list_view.visible = false
	_commands_delete_save_view.visible = false
	_commands_teleport_view.visible = false
	_commands_time_view.visible = false
	_commands_view_dist_view.visible = true
	_refresh_view_dist_label()


func _refresh_view_dist_label() -> void:
	if _view_dist_label == null:
		return
	var viewer := _get_voxel_viewer()
	var dist_vox: int = int(viewer.view_distance) if viewer != null else -1
	if dist_vox >= 0:
		# VoxelViewer.view_distance is in voxels; terrain is 6 vox/m.
		# Truncating to whole meters for the label is the intent (the
		# voxel count is shown in parentheses for precision).
		@warning_ignore("integer_division")
		var dist_m: int = dist_vox / 6
		_view_dist_label.text = "%d m  (%d vox)" % [dist_m, dist_vox]
	else:
		_view_dist_label.text = "— (no VoxelViewer)"


func _adjust_view_distance(delta_m: int) -> void:
	var viewer := _get_voxel_viewer()
	if viewer == null:
		log_action("DEV: view distance change ignored — VoxelViewer not found")
		return
	# VoxelViewer.view_distance is in voxels. Multiply meters × 6 to convert.
	# Clamp: 600 vox (100 m) minimum, 18000 vox (3000 m) maximum.
	var before_vox: int = int(viewer.view_distance)
	var requested_vox: int = clamp(before_vox + delta_m * 6, 600, 18000)
	viewer.view_distance = requested_vox
	# Read back to verify the write — Zylann's plugin can silently clamp
	# view_distance against an internal max.
	var actual_vox: int = int(viewer.view_distance)
	_refresh_view_dist_label()
	log_action("DEV: view distance %d → asked %d, got %d vox" %
		[before_vox, requested_vox, actual_vox])
	# Streaming is event-driven: new chunks only generate when the viewer
	# moves and the streamer re-evaluates. Walk a few meters to see the
	# wider radius take effect.


func _get_voxel_viewer() -> VoxelViewer:
	# VoxelViewer is a direct child of Player3D, which is in the "player" group.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0].get_node_or_null("VoxelViewer") as VoxelViewer


# --- WEATHER sub-view ---

func _build_commands_weather_view() -> void:
	# Six state buttons stacked vertically + clear-override + force-lightning
	# + readouts for current state and live wind. Hidden until the player
	# clicks WEATHER... in the list view.
	_commands_weather_view = VBoxContainer.new()
	_commands_weather_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_weather_view.add_theme_constant_override("separation", 6)
	_commands_weather_view.visible = false
	_commands_tab.add_child(_commands_weather_view)

	_weather_back_btn = _make_command_row("← BACK")
	_commands_weather_view.add_child(_weather_back_btn)

	var hint := Label.new()
	hint.text = "Forces a weather state for 99 hours. Use CLEAR OVERRIDE to hand control back to the schedule."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_weather_view.add_child(hint)

	_weather_state_label = Label.new()
	_weather_state_label.add_theme_font_size_override("font_size", 16)
	_weather_state_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))
	_weather_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_weather_view.add_child(_weather_state_label)

	_weather_wind_label = Label.new()
	_weather_wind_label.add_theme_font_size_override("font_size", 13)
	_weather_wind_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.85, 1))
	_weather_wind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commands_weather_view.add_child(_weather_wind_label)

	# State buttons. Order matches enum (CLEAR..SNOW) so clicks read
	# top-to-bottom from calmest to wildest.
	if get_node_or_null("/root/WeatherManager") != null:
		var states: Array = WeatherManager.STATE_NAMES.keys()
		for state_id in states:
			var label: String = (WeatherManager.STATE_NAMES[state_id] as String).to_upper()
			var b: Button = _make_command_row("SET WEATHER: " + label)
			_weather_state_buttons[state_id] = b
			_commands_weather_view.add_child(b)

	_weather_clear_override_btn = _make_command_row("CLEAR OVERRIDE")
	_commands_weather_view.add_child(_weather_clear_override_btn)

	_weather_force_lightning_btn = _make_command_row("FORCE LIGHTNING")
	_commands_weather_view.add_child(_weather_force_lightning_btn)


func _show_weather_view() -> void:
	_commands_view = CommandView.WEATHER
	_commands_list_view.visible = false
	_commands_delete_save_view.visible = false
	_commands_teleport_view.visible = false
	_commands_time_view.visible = false
	_commands_view_dist_view.visible = false
	_commands_weather_view.visible = true
	_refresh_weather_labels()


func _refresh_weather_labels() -> void:
	if _weather_state_label == null:
		return
	if get_node_or_null("/root/WeatherManager") == null:
		_weather_state_label.text = "WeatherManager not loaded"
		_weather_wind_label.text = ""
		return
	var state_name: String = WeatherManager.get_state_name()
	var target_id: int = WeatherManager._target_state
	var target_name: String = WeatherManager.STATE_NAMES.get(target_id, "?")
	var override_id: int = WeatherManager._override_state
	var override_str: String = "none"
	if override_id != -1:
		override_str = "%s (%.1f h)" % [WeatherManager.STATE_NAMES.get(override_id, "?"), WeatherManager._override_hours_remaining]
	_weather_state_label.text = "Current: %s   Target: %s   Override: %s" % [state_name, target_name, override_str]
	var wind: Vector3 = WeatherManager.wind_direction
	var strength: float = WeatherManager._live_wind_strength
	_weather_wind_label.text = "Wind: (%.2f, %.2f) × %.2f" % [wind.x, wind.z, strength]


# --- Console tab ---

func _build_console_tab() -> void:
	var heading := Label.new()
	heading.text = "CONSOLE — last %d player actions" % MAX_LOG_ENTRIES
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_tab.add_child(heading)

	_console_scroll = ScrollContainer.new()
	_console_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console_scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	_console_tab.add_child(_console_scroll)

	_console_label = Label.new()
	_console_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console_label.add_theme_font_size_override("font_size", 14)
	_console_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	_console_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_console_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_scroll.add_child(_console_label)


func _refresh_console_label() -> void:
	if _console_label == null:
		return
	if _action_log.is_empty():
		_console_label.text = "(no actions logged yet)"
		return
	# Newest entries at the bottom — natural reading order.
	_console_label.text = "\n".join(_action_log)
	# Scroll to bottom so the latest entry is visible.
	if _console_scroll != null:
		_console_scroll.scroll_vertical = int(_console_label.size.y)


# --- Player state tab ---

func _build_player_state_tab() -> void:
	var heading := Label.new()
	heading.text = "PLAYER STATE — live"
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_state_tab.add_child(heading)

	_ps_position_label  = _make_state_label()
	_ps_rotation_label  = _make_state_label()
	_ps_pitch_label     = _make_state_label()
	_ps_health_label    = _make_state_label()
	_ps_endurance_label = _make_state_label()
	_ps_equipped_label  = _make_state_label()
	_ps_aim_label       = _make_state_label()
	_ps_time_label      = _make_state_label()
	_ps_played_label    = _make_state_label()

	for lbl in [_ps_position_label, _ps_rotation_label, _ps_pitch_label,
				_ps_health_label, _ps_endurance_label, _ps_equipped_label,
				_ps_aim_label, _ps_time_label, _ps_played_label]:
		_player_state_tab.add_child(lbl)


func _make_state_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _refresh_player_state_tab() -> void:
	# Pull live values from the player + camera + inventory each
	# frame the tab is visible. Cheap (a few group lookups + string
	# formats per frame).
	# WorldClock + play-time are global — show their state even when no
	# player is loaded (e.g. the user opens F1 from the title screen).
	# _refresh_world_clock_label updates BOTH the time and the played
	# labels, so this single call handles both.
	_refresh_world_clock_label()

	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_ps_position_label.text   = "Position:    (no player in scene)"
		_ps_rotation_label.text   = "Facing:      —"
		_ps_pitch_label.text      = "Pitch:       —"
		_ps_health_label.text     = "Health:      —"
		_ps_endurance_label.text  = "Endurance:   —"
		_ps_equipped_label.text   = "Equipped:    —"
		_ps_aim_label.text        = "Aim Target:  —"
		return

	var player: Node3D = players[0] as Node3D
	var p: Vector3 = player.global_position
	# Axis labels: Godot is Y-up, so X and Z are both horizontal axes.
	# The "(E/W)" / "(N/S)" / "(UP)" hints stop "why does walking
	# sideways change Z and not Y?" confusion at a glance.
	_ps_position_label.text = "Position:    X %.1f (E/W)   Y %.1f (UP)   Z %.1f (N/S)" % [p.x, p.y, p.z]
	_ps_rotation_label.text = "Facing:      %+.1f°" % rad_to_deg(player.rotation.y)

	# Camera pitch lives on the SpringArm3D (CameraRig).
	var camera_rig := player.get_node_or_null("CameraTarget/SpringArm3D") as SpringArm3D
	if camera_rig != null:
		_ps_pitch_label.text = "Pitch:       %+.1f°" % rad_to_deg(camera_rig.rotation.x)
	else:
		_ps_pitch_label.text = "Pitch:       —"

	# Health / endurance — Player3D exposes them as plain vars.
	if "health" in player and "max_health" in player:
		_ps_health_label.text = "Health:      %d / %d" % [int(player.health), int(player.max_health)]
	if "endurance" in player and "max_endurance" in player:
		_ps_endurance_label.text = "Endurance:   %d / %d" % [int(player.endurance), int(player.max_endurance)]

	# Equipped weapon from InventoryManager.
	if get_node_or_null("/root/InventoryManager"):
		var equipped: String = InventoryManager.get_equipped("weapon")
		_ps_equipped_label.text = "Equipped:    %s" % (equipped if equipped != "" else "(empty)")

	# Aim raycast — same call EditToolHandler uses on click.
	if camera_rig != null and camera_rig.has_method("get_camera_forward_hit"):
		var hit: Dictionary = camera_rig.get_camera_forward_hit(4.0)
		if hit.is_empty():
			_ps_aim_label.text = "Aim Target:  (no hit within 4m of player)"
		else:
			var hp: Vector3 = hit.get("position", Vector3.ZERO)
			var dist: float = player.global_position.distance_to(hp)
			var collider = hit.get("collider")
			var collider_name: String = "?"
			if collider != null:
				collider_name = String((collider as Node).name)
			_ps_aim_label.text = "Aim Target:  (%.1f, %.1f, %.1f)  dist %.1fm  hit '%s'" % [
				hp.x, hp.y, hp.z, dist, collider_name
			]


func _refresh_world_clock_label() -> void:
	# Reads the autoloaded clock and renders day + time + period.
	# Falls back to a dash if WorldClock isn't registered (shouldn't
	# happen — listed in project.godot — but guarded anyway so the
	# debug overlay never breaks if the autoload list shifts).
	if get_node_or_null("/root/WorldClock"):
		_ps_time_label.text = "World Time:  Day %d   %s   (%s)" % [
			WorldClock.current_day,
			WorldClock.get_time_string(),
			WorldClock.get_time_of_day_period(),
		]
	else:
		_ps_time_label.text = "World Time:  —"

	if get_node_or_null("/root/GameState"):
		_ps_played_label.text = "Played:      %s" % GameState.get_play_time_string()
	else:
		_ps_played_label.text = "Played:      —"


# --- Tab switching ---

func _show_tab(tab: DebugTab) -> void:
	_current_tab = tab
	_commands_tab.visible     = tab == DebugTab.COMMANDS
	_console_tab.visible      = tab == DebugTab.CONSOLE
	_player_state_tab.visible = tab == DebugTab.PLAYER_STATE
	_tab_label.text = "[ F1 ] DEBUG — %s   (TAB to switch)" % TAB_NAMES[tab]
	if tab == DebugTab.CONSOLE:
		_refresh_console_label()
	elif tab == DebugTab.PLAYER_STATE:
		_refresh_player_state_tab()


# =============================================================
# UI — always-on HUD (visible without F1)
# =============================================================

func _build_coords_hud() -> void:
	# Moved from top-left to bottom-right (2026-05-12) so the F3 Profiler
	# overlay doesn't compete with the always-on debug readouts. Three
	# labels stack bottom-up: world_time (bottom-most), aim, then coords.
	_coords_label = Label.new()
	_coords_label.anchor_left = 1.0
	_coords_label.anchor_right = 1.0
	_coords_label.anchor_top = 1.0
	_coords_label.anchor_bottom = 1.0
	_coords_label.offset_left = -400
	_coords_label.offset_right = -12
	_coords_label.offset_top = -72
	_coords_label.offset_bottom = -52
	_coords_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coords_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coords_label.add_theme_font_size_override("font_size", 14)
	_coords_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_coords_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_coords_label.add_theme_constant_override("shadow_offset_x", 1)
	_coords_label.add_theme_constant_override("shadow_offset_y", 1)
	_coords_label.text = "X 0.0  Y 0.0  Z 0.0"
	add_child(_coords_label)


func _update_coords_label() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_coords_label.text = "(no player)"
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return
	var p: Vector3 = player.global_position
	_coords_label.text = "X %.1f   Y %.1f   Z %.1f" % [p.x, p.y, p.z]


func _build_aim_hud() -> void:
	# Bottom-right stack — middle row (see _build_coords_hud comment).
	_aim_label = Label.new()
	_aim_label.anchor_left = 1.0
	_aim_label.anchor_right = 1.0
	_aim_label.anchor_top = 1.0
	_aim_label.anchor_bottom = 1.0
	_aim_label.offset_left = -400
	_aim_label.offset_right = -12
	_aim_label.offset_top = -52
	_aim_label.offset_bottom = -32
	_aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_label.add_theme_font_size_override("font_size", 12)
	_aim_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5, 0.85))
	_aim_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_aim_label.add_theme_constant_override("shadow_offset_x", 1)
	_aim_label.add_theme_constant_override("shadow_offset_y", 1)
	_aim_label.text = "AIM: —"
	add_child(_aim_label)


func _update_aim_label() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_aim_label.text = "AIM: (no player)"
		return
	var player: Node3D = players[0] as Node3D
	var camera_rig := player.get_node_or_null("CameraTarget/SpringArm3D")
	if camera_rig == null or not camera_rig.has_method("get_camera_forward_hit"):
		_aim_label.text = "AIM: (no camera rig)"
		return
	var hit: Dictionary = camera_rig.get_camera_forward_hit(4.0)
	if hit.is_empty():
		_aim_label.text = "AIM: (no hit within 4m of player)"
		return
	var hp: Vector3 = hit.get("position", Vector3.ZERO)
	var dist: float = player.global_position.distance_to(hp)
	_aim_label.text = "AIM: (%.1f, %.1f, %.1f)  dist %.1fm" % [hp.x, hp.y, hp.z, dist]


func _build_world_time_hud() -> void:
	# Bottom-right stack — bottom-most row. Always visible (no F1
	# required) so the player can glance at the time of day and total
	# play time without opening the debug overlay. Moved from top-left
	# 2026-05-12 to deconflict with the F3 Profiler overlay.
	_world_time_label = Label.new()
	_world_time_label.anchor_left = 1.0
	_world_time_label.anchor_right = 1.0
	_world_time_label.anchor_top = 1.0
	_world_time_label.anchor_bottom = 1.0
	_world_time_label.offset_left = -400
	_world_time_label.offset_right = -12
	_world_time_label.offset_top = -32
	_world_time_label.offset_bottom = -12
	_world_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_world_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_time_label.add_theme_font_size_override("font_size", 12)
	_world_time_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.85))
	_world_time_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_world_time_label.add_theme_constant_override("shadow_offset_x", 1)
	_world_time_label.add_theme_constant_override("shadow_offset_y", 1)
	_world_time_label.text = "Day 1  08:00  (MORNING)   |   Played: 0m 00s"
	add_child(_world_time_label)


func _update_world_time_label() -> void:
	# Two pieces: in-game time (Day N HH:MM PERIOD) and total wall-clock
	# play time across all sessions. WorldClock + GameState are both
	# autoloads so the labels work on the title screen too — they just
	# won't tick until a world is loaded.
	var time_part: String = "—"
	if get_node_or_null("/root/WorldClock"):
		time_part = "Day %d  %s  (%s)" % [
			WorldClock.current_day,
			WorldClock.get_time_string(),
			WorldClock.get_time_of_day_period(),
		]
	var played_part: String = "—"
	if get_node_or_null("/root/GameState"):
		played_part = GameState.get_play_time_string()
	_world_time_label.text = "%s   |   Played: %s" % [time_part, played_part]


func _build_terrain_scale_hud() -> void:
	# Top-centre readout of the live VoxelLodTerrain scale, shown only
	# when a terrain exists in the active scene. Designed for the
	# Copper Isles scale-test workflow — F7 cycles 6 → 8 → 10 vox/m
	# and this label confirms which value is currently rendering.
	#
	# Anchored to the top-centre via a top-anchored Control wrapper
	# so the label stays centred across viewport resizes. We can't
	# anchor a Label directly because Label sizes itself to its text;
	# we want the text centred regardless of length.
	var wrapper := Control.new()
	wrapper.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wrapper.offset_top = 12
	wrapper.offset_bottom = 50
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrapper)

	_terrain_scale_label = Label.new()
	_terrain_scale_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terrain_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_terrain_scale_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_terrain_scale_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_scale_label.add_theme_font_size_override("font_size", 22)
	_terrain_scale_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.55, 0.95))
	_terrain_scale_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_terrain_scale_label.add_theme_constant_override("shadow_offset_x", 2)
	_terrain_scale_label.add_theme_constant_override("shadow_offset_y", 2)
	_terrain_scale_label.add_theme_constant_override("shadow_outline_size", 4)
	_terrain_scale_label.text = ""
	wrapper.add_child(_terrain_scale_label)


func _build_fps_hud() -> void:
	# Top-RIGHT FPS + worst-frame-ms readout. Two lines, outlined white
	# text so it stays readable against any backdrop. Sits in a fixed-
	# width slot anchored to the top-right corner so digits can grow
	# (FPS 60 → 144) without the layout shifting. Mirrors the style
	# language of the top-left coords / aim labels (12-14 px font,
	# semi-transparent white, hard 1 px shadow), with the addition of
	# a 4 px outline for legibility on bright skies.
	_fps_label = Label.new()
	_fps_label.text = "FPS: --\nworst: --"
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.add_theme_constant_override("shadow_offset_x", 1)
	_fps_label.add_theme_constant_override("shadow_offset_y", 1)
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.anchor_top = 0.0
	_fps_label.anchor_bottom = 0.0
	# Slot wide enough for "worst: 999 ms" plus margin. Tall enough
	# for two lines at font size 14.
	_fps_label.offset_left = -160
	_fps_label.offset_right = -12
	_fps_label.offset_top = 12
	_fps_label.offset_bottom = 56
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps_label)


func _update_fps_label(delta: float) -> void:
	# Engine.get_frames_per_second() is a smoothed average that hides
	# hitches; the 60-sample sliding-window worst-delta is what actually
	# correlates with perceived stutter. Show both: the smoothed FPS
	# tells you the steady-state rate, the worst-ms calls out spikes
	# that the average is hiding. Tints red when worst > 33 ms (= a
	# sub-30-fps spike) so stutters surface visually rather than
	# requiring the dev to read the digits.
	_frame_times[_frame_times_idx] = delta
	_frame_times_idx = (_frame_times_idx + 1) % _frame_times.size()
	var worst: float = 0.0
	for ft in _frame_times:
		if ft > worst:
			worst = ft
	var worst_ms: int = int(round(worst * 1000.0))
	_fps_label.text = "FPS: %d\nworst: %d ms" % [
		Engine.get_frames_per_second(), worst_ms,
	]
	if worst_ms > 33:
		_fps_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 0.95))
	else:
		_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))


func _update_terrain_scale_label() -> void:
	# Walks the active scene for a VoxelLodTerrain, reads its uniform
	# scale, converts to voxels-per-metre, and renders both.
	#
	# Visibility: ONLY shown while the F1 debug panel is open (per user
	# request 2026-05-12 — the always-on top-centre readout was visual
	# clutter for a value that only matters during scale-tuning tests).
	# The label still updates its text every frame so the panel sees a
	# current value the moment F1 opens.
	var panel_open: bool = (_root != null and _root.visible)
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		_terrain_scale_label.visible = false
		return
	var terrains: Array[Node] = []
	_collect_voxel_terrains(scene_root, terrains)
	if terrains.is_empty():
		_terrain_scale_label.visible = false
		return
	var n3d := terrains[0] as Node3D
	if n3d == null:
		_terrain_scale_label.visible = false
		return
	_terrain_scale_label.visible = panel_open
	# Local var renamed from `scale` to dodge the CanvasLayer.scale
	# property shadow warning. CanvasLayer (this autoload's base class)
	# exposes a 2D scale Vector2 — different concept from the 3D voxel
	# terrain's uniform basis scale, but Godot's lint catches the name
	# collision and warns.
	var terrain_scale: float = n3d.transform.basis.get_scale().x
	# vox/m = 1 / scale. Tiny scale → many vox/m. Guard div-by-zero.
	var vox_per_m: float = 0.0
	if absf(terrain_scale) > 0.00001:
		vox_per_m = 1.0 / terrain_scale
	_terrain_scale_label.text = "TERRAIN SCALE — %.2f voxels/m   (transform.scale %.4f)" % [vox_per_m, terrain_scale]


func _build_crosshair() -> void:
	# Two thin ColorRects forming a + at exact screen center.
	# Visibility is toggled per-frame in _process based on whether
	# a player exists in the scene, so the reticle disappears
	# automatically on the title screen, settings menu, and any
	# other non-gameplay scene.
	_crosshair_root = Control.new()
	_crosshair_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair_root)

	var c := Color(1, 1, 1, 0.7)

	var h := ColorRect.new()
	h.color = c
	h.size = Vector2(14, 2)
	h.position = Vector2(-7, -1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_root.add_child(h)

	var v := ColorRect.new()
	v.color = c
	v.size = Vector2(2, 14)
	v.position = Vector2(-1, -7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_root.add_child(v)


func _update_crosshair_visibility() -> void:
	# Reticle is gameplay-only — hide when no player is in the tree
	# (title screen, settings, load picker, etc.).
	if _crosshair_root == null:
		return
	var has_player: bool = not get_tree().get_nodes_in_group("player").is_empty()
	_crosshair_root.visible = has_player


# =============================================================
# PUBLIC API — action logging
# =============================================================

func log_action(message: String) -> void:
	# Pushes one entry into the CONSOLE tab buffer + Godot's
	# Output panel. Call from any player-action site that's worth
	# surfacing to the in-game console: mining, throwing, saving,
	# loading, taking damage, etc.
	#
	# Format: "[HH:MM:SS]  <message>". The timestamp comes from the
	# system clock so concurrent actions are easy to read in order.
	var entry: String = "[%s]  %s" % [Time.get_time_string_from_system(), message]
	_action_log.append(entry)
	while _action_log.size() > MAX_LOG_ENTRIES:
		_action_log.pop_front()
	# Stay in the Output panel too so traditional stdout debugging
	# keeps working alongside the in-game console.
	print(entry)
	# Live-refresh the CONSOLE tab if the player is reading it.
	if _root != null and _root.visible and _current_tab == DebugTab.CONSOLE:
		_refresh_console_label()


# =============================================================
# INPUT
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				_root.visible = not _root.visible
				if _root.visible:
					# Free the mouse cursor so the player can click
					# command buttons. CameraRig captures the mouse
					# during gameplay; without this, the cursor stays
					# locked at screen center and clicks land on the
					# wrong target.
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					_show_tab(_current_tab)
				else:
					# Re-capture the mouse so gameplay aiming resumes.
					# If the pause menu / journal is also open they'll
					# set their own VISIBLE state next frame.
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					_disarm_delete_saves()
					_show_command_list()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				if _root.visible:
					var next := (int(_current_tab) + 1) % 3
					_show_tab(next as DebugTab)
					get_viewport().set_input_as_handled()
				# F7 cycles the Copper Isles scale-test through 6 → 8
				# → 10 voxels/m. Routed through the active scene's
				# apply_terrain_scale method when present (e.g.
				# CopperIslesTestBootstrap) so the player gets
				# re-snapped above the terrain after each change;
				# falls back to direct transform mutation otherwise.
				# Bound to F7 to avoid clashing with F1 (debug
				# overlay) and F2 (freelook camera).
			KEY_F7:
				_cycle_f7_vox_per_m()
				get_viewport().set_input_as_handled()


# Manual click dispatch — same pattern as MainMenu / PauseMenu.
# GUI dispatch is silently broken in this project; click on COMMANDS
# tab buttons by hit-testing global rects.
func _input(event: InputEvent) -> void:
	if not enabled or _root == null or not _root.visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return

	# Wheel scrolls the CONSOLE tab.
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and _current_tab == DebugTab.CONSOLE:
		_console_scroll.scroll_vertical -= 60
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and _current_tab == DebugTab.CONSOLE:
		_console_scroll.scroll_vertical += 60
		return

	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	# COMMANDS tab — dispatch by sub-view.
	if _current_tab == DebugTab.COMMANDS:
		_dispatch_commands_click(mb.position)


func _dispatch_commands_click(pos: Vector2) -> void:
	# COMMANDS LIST view: which top-level command did the player click?
	if _commands_view == CommandView.LIST:
		if _hits_button(_btn_delete_all, pos):
			_on_delete_saves_clicked()
			return
		if _hits_button(_btn_delete_one, pos):
			_show_delete_save_view()
			return
		if _hits_button(_btn_teleport, pos):
			_show_teleport_view()
			return
		if _hits_button(_btn_advance_day, pos):
			# Quick path — instant +24 hours. No submenu.
			_advance_time(1, 0)
			return
		if _hits_button(_btn_advance_time, pos):
			_show_time_view()
			return
		if _hits_button(_btn_fly_mode, pos):
			_toggle_fly_mode()
			return
		if _hits_button(_btn_view_dist, pos):
			_show_view_dist_view()
			return
		if _hits_button(_btn_weather, pos):
			_show_weather_view()
			return
		return

	# DELETE A SAVE sub-view: BACK or per-row DELETE.
	if _commands_view == CommandView.DELETE_SAVE:
		if _hits_button(_delete_save_back_btn, pos):
			_show_command_list()
			return
		# Walk the dynamic save rows; each row's right-side Button
		# carries the filename in its meta dict.
		for row in _delete_save_list.get_children():
			if not (row is HBoxContainer):
				continue
			for child in row.get_children():
				if child is Button and _hits_button(child as Button, pos):
					var fname: String = (child as Button).get_meta("save_filename", "")
					if fname == "":
						return
					if get_node_or_null("/root/GameState"):
						GameState.delete_save_file(fname)
						log_action("DEV: deleted save '%s'" % fname)
					_populate_delete_save_list()
					return
		return

	# TELEPORT sub-view: BACK / CONFIRM / focus on a LineEdit.
	if _commands_view == CommandView.TELEPORT:
		if _hits_button(_teleport_back_btn, pos):
			_show_command_list()
			return
		if _hits_button(_teleport_confirm_btn, pos):
			_do_teleport()
			return
		# Click on a LineEdit → focus it for typing.
		if _hits_control(_teleport_x_edit, pos):
			_teleport_x_edit.grab_focus()
			return
		if _hits_control(_teleport_y_edit, pos):
			_teleport_y_edit.grab_focus()
			return
		if _hits_control(_teleport_z_edit, pos):
			_teleport_z_edit.grab_focus()
			return

	# VIEW DISTANCE sub-view: BACK or step buttons.
	if _commands_view == CommandView.VIEW_DIST:
		if _hits_button(_view_dist_back_btn, pos):
			_show_command_list()
			return
		if _hits_button(_view_dist_minus_500, pos):
			_adjust_view_distance(-500)
			return
		if _hits_button(_view_dist_minus_100, pos):
			_adjust_view_distance(-100)
			return
		if _hits_button(_view_dist_plus_100, pos):
			_adjust_view_distance(100)
			return
		if _hits_button(_view_dist_plus_500, pos):
			_adjust_view_distance(500)
			return

	# WEATHER sub-view: BACK / state buttons / clear / force-lightning.
	if _commands_view == CommandView.WEATHER:
		if _hits_button(_weather_back_btn, pos):
			_show_command_list()
			return
		if _hits_button(_weather_clear_override_btn, pos):
			if get_node_or_null("/root/WeatherManager") != null:
				WeatherManager.clear_weather_override()
				log_action("DEV: cleared weather override")
				_refresh_weather_labels()
			return
		if _hits_button(_weather_force_lightning_btn, pos):
			if get_node_or_null("/root/WeatherManager") != null and WeatherManager.has_method("trigger_lightning_strike"):
				WeatherManager.trigger_lightning_strike()
				log_action("DEV: forced lightning")
			return
		for state_id in _weather_state_buttons.keys():
			var b: Button = _weather_state_buttons[state_id]
			if _hits_button(b, pos):
				if get_node_or_null("/root/WeatherManager") != null:
					var state_name: String = WeatherManager.STATE_NAMES.get(state_id, "")
					WeatherManager.set_weather_override(state_name, 99.0)
					log_action("DEV: set weather → %s" % state_name)
					_refresh_weather_labels()
				return

	# TIME-SKIP sub-view: BACK / ADVANCE / focus on a LineEdit.
	if _commands_view == CommandView.TIME_SKIP:
		if _hits_button(_time_back_btn, pos):
			_show_command_list()
			return
		if _hits_button(_time_confirm_btn, pos):
			_do_advance_time_form()
			return
		if _hits_control(_time_days_edit, pos):
			_time_days_edit.grab_focus()
			return
		if _hits_control(_time_hours_edit, pos):
			_time_hours_edit.grab_focus()
			return


func _hits_button(b: Button, pos: Vector2) -> bool:
	# True if the button is visible, not disabled, and the click
	# is inside its global rect.
	if b == null or not b.visible or b.disabled:
		return false
	return b.get_global_rect().has_point(pos)


func _hits_control(c: Control, pos: Vector2) -> bool:
	if c == null or not c.visible:
		return false
	return c.get_global_rect().has_point(pos)


# =============================================================
# COMMANDS — DELETE ALL SAVES
# =============================================================

func _on_delete_saves_clicked() -> void:
	if not _delete_saves_armed:
		_delete_saves_armed = true
		_delete_saves_arm_remaining = DELETE_SAVES_ARM_SECONDS
		_btn_delete_all.text = "  CONFIRM? (%ds)" % int(DELETE_SAVES_ARM_SECONDS)
		return
	if get_node_or_null("/root/GameState"):
		var n: int = GameState.delete_all_save_files()
		log_action("DEV: deleted %d save file(s) via debug menu." % n)
	_disarm_delete_saves()


func _disarm_delete_saves() -> void:
	_delete_saves_armed = false
	_delete_saves_arm_remaining = 0.0
	if _btn_delete_all != null:
		_btn_delete_all.text = "  DELETE ALL SAVES"


# =============================================================
# TERRAIN SCALE HOTKEYS — Copper Isles iteration
# =============================================================

func _apply_terrain_scale_hotkey(new_scale: float, key_label: String) -> void:
	# Sets a uniform scale on every VoxelLodTerrain in the current
	# scene. Routes through the scene root's apply_terrain_scale
	# method when present (CopperIslesTestBootstrap exposes it and
	# also re-seeds water + re-snaps the player above the new highest
	# peak). Falls back to raw transform mutation if the scene root
	# doesn't have the helper — useful for testing the hotkeys in any
	# scene that owns a VoxelLodTerrain, including the main World3D.
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		log_action("DEV: %s scale=%.3f ignored (no current scene)" % [key_label, new_scale])
		return
	if scene_root.has_method("apply_terrain_scale"):
		scene_root.call("apply_terrain_scale", new_scale)
		log_action("DEV: %s terrain scale → %.3f (via bootstrap)" % [key_label, new_scale])
		return
	# Fallback: walk the tree, scale every VoxelLodTerrain we find.
	var terrains: Array[Node] = []
	_collect_voxel_terrains(scene_root, terrains)
	if terrains.is_empty():
		log_action("DEV: %s scale=%.3f ignored (no VoxelLodTerrain in scene)" % [key_label, new_scale])
		return
	for t in terrains:
		var n3d := t as Node3D
		if n3d == null:
			continue
		var origin: Vector3 = n3d.transform.origin
		n3d.transform = Transform3D(Basis().scaled(Vector3.ONE * new_scale), origin)
	log_action("DEV: %s terrain scale → %.3f (%d terrain(s), no bootstrap)" % [
		key_label, new_scale, terrains.size(),
	])


func _collect_voxel_terrains(node: Node, out: Array[Node]) -> void:
	if node.get_class() == "VoxelLodTerrain" or node.get_class() == "VoxelTerrain":
		out.append(node)
	for child in node.get_children():
		_collect_voxel_terrains(child, out)


func _cycle_f7_vox_per_m() -> void:
	# Advances through F7_CYCLE on each F7 press: 6 → 8 → 10 → 6 → ...
	# The label at top-centre updates from the live terrain scale on
	# the next _process tick, so the reading always matches what's
	# rendered (no risk of label drift if the bootstrap clamps the
	# scale or some other path mutates it).
	var entry: Dictionary = F7_CYCLE[_f7_next_index]
	var vox_per_m: int = int(entry.get("vox_per_m", 6))
	var new_scale: float = float(entry.get("scale", 1.0 / 6.0))
	_f7_next_index = (_f7_next_index + 1) % F7_CYCLE.size()
	_apply_terrain_scale_hotkey(new_scale, "F7  (%d vox/m)" % vox_per_m)
