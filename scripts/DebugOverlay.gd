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

# Commands tab.
var _delete_saves_btn: Button
var _delete_saves_armed: bool = false
var _delete_saves_arm_remaining: float = 0.0

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

	# DELETE ALL SAVES — same button as before, just relocated
	# from the corner into the tab. Two-click confirmation logic
	# unchanged: first click arms, second within 3s wipes saves.
	_delete_saves_btn = Button.new()
	_delete_saves_btn.text = "DELETE ALL SAVES"
	_delete_saves_btn.add_theme_font_size_override("font_size", 16)
	_delete_saves_btn.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
	_delete_saves_btn.custom_minimum_size = Vector2(280, 44)
	_commands_tab.add_child(_delete_saves_btn)

	# Hint about future commands so the tab doesn't feel empty.
	var hint := Label.new()
	hint.text = "(more commands as needed: give item, teleport, set time of day, etc.)"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_commands_tab.add_child(hint)


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
				if not _root.visible:
					_disarm_delete_saves()
				else:
					# Make sure the displayed tab content is fresh
					# the moment the panel opens.
					_show_tab(_current_tab)
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

	# COMMANDS tab buttons.
	if _current_tab == DebugTab.COMMANDS and _delete_saves_btn != null \
		and _delete_saves_btn.get_global_rect().has_point(mb.position):
		_on_delete_saves_clicked()


# =============================================================
# COMMANDS — DELETE ALL SAVES
# =============================================================

func _on_delete_saves_clicked() -> void:
	if not _delete_saves_armed:
		_delete_saves_armed = true
		_delete_saves_arm_remaining = DELETE_SAVES_ARM_SECONDS
		_delete_saves_btn.text = "CONFIRM? (%ds)" % int(DELETE_SAVES_ARM_SECONDS)
		return
	if get_node_or_null("/root/GameState"):
		var n: int = GameState.delete_all_save_files()
		log_action("DEV: deleted %d save file(s) via debug menu." % n)
	_disarm_delete_saves()


func _disarm_delete_saves() -> void:
	_delete_saves_armed = false
	_delete_saves_arm_remaining = 0.0
	if _delete_saves_btn != null:
		_delete_saves_btn.text = "DELETE ALL SAVES"
