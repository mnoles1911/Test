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
enum CommandView { LIST, DELETE_SAVE, TELEPORT }
var _commands_view: CommandView = CommandView.LIST

# Sub-view containers.
var _commands_list_view: VBoxContainer
var _commands_delete_save_view: VBoxContainer
var _commands_teleport_view: VBoxContainer

# Command list buttons.
var _btn_delete_all: Button
var _btn_delete_one: Button
var _btn_teleport: Button

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

# Always-on HUD (visible without F1).
var _coords_label: Label
var _aim_label: Label

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
	_build_crosshair()
	_root.visible = false

	log_action("DebugOverlay initialized.")


func _process(delta: float) -> void:
	if not enabled:
		return

	# Always-on HUD updates (cheap; runs every frame).
	if _coords_label != null:
		_update_coords_label()
	if _aim_label != null:
		_update_aim_label()

	# DELETE ALL SAVES auto-disarm timer.
	if _delete_saves_armed:
		_delete_saves_arm_remaining -= delta
		if _delete_saves_arm_remaining <= 0.0:
			_disarm_delete_saves()

	# Live PLAYER STATE refresh while the panel is open on that tab.
	if _root.visible and _current_tab == DebugTab.PLAYER_STATE:
		_refresh_player_state_tab()


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
	_show_command_list()


# --- Commands LIST view (default — clickable command rows) ---

func _build_commands_list_view() -> void:
	_commands_list_view = VBoxContainer.new()
	_commands_list_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_list_view.add_theme_constant_override("separation", 4)
	_commands_tab.add_child(_commands_list_view)

	_btn_delete_all = _make_command_row("DELETE ALL SAVES")
	_btn_delete_one = _make_command_row("DELETE A SAVE FILE")
	_btn_teleport   = _make_command_row("TELEPORT PLAYER")

	for b in [_btn_delete_all, _btn_delete_one, _btn_teleport]:
		_commands_list_view.add_child(b)


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


func _show_delete_save_view() -> void:
	_commands_view = CommandView.DELETE_SAVE
	_commands_list_view.visible = false
	_commands_delete_save_view.visible = true
	_commands_teleport_view.visible = false
	_populate_delete_save_list()


func _show_teleport_view() -> void:
	_commands_view = CommandView.TELEPORT
	_commands_list_view.visible = false
	_commands_delete_save_view.visible = false
	_commands_teleport_view.visible = true

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

	for lbl in [_ps_position_label, _ps_rotation_label, _ps_pitch_label,
				_ps_health_label, _ps_endurance_label, _ps_equipped_label,
				_ps_aim_label]:
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
	_ps_position_label.text = "Position:    X %.1f   Y %.1f   Z %.1f" % [p.x, p.y, p.z]
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
			var collider_name: String = "?" if collider == null else (collider as Node).name
			_ps_aim_label.text = "Aim Target:  (%.1f, %.1f, %.1f)  dist %.1fm  hit '%s'" % [
				hp.x, hp.y, hp.z, dist, collider_name
			]


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
	_coords_label = Label.new()
	_coords_label.position = Vector2(12, 12)
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
	_aim_label = Label.new()
	_aim_label.position = Vector2(12, 32)
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


func _build_crosshair() -> void:
	# Two thin ColorRects forming a + at exact screen center.
	var crosshair_root := Control.new()
	crosshair_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair_root)

	var c := Color(1, 1, 1, 0.7)

	var h := ColorRect.new()
	h.color = c
	h.size = Vector2(14, 2)
	h.position = Vector2(-7, -1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_root.add_child(h)

	var v := ColorRect.new()
	v.color = c
	v.size = Vector2(2, 14)
	v.position = Vector2(-1, -7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_root.add_child(v)


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
