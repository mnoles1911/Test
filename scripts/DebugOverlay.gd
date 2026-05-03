extends CanvasLayer
# DebugOverlay — Autoload. F1 key shows a runtime debug panel.
#
# What this does in plain English:
#   Press F1 during the game (any scene) to toggle a translucent overlay
#   showing the last 20 flag changes and the current GameState values.
#   This is entirely development-only — you can disable it for release builds
#   by setting enabled = false.
#
#   The overlay does NOT pause the game. It renders above everything else
#   (layer 98, just below the SaveNotification at 99).
#
# Tabs (cycle with TAB key while overlay is open):
#   FLAGS RECENT  — last 20 flag changes, newest at top
#   FLAGS ALL     — full current flag dictionary (alphabetical)
#   COMPANIONS    — companion roster states


# =============================================================
# CONFIGURATION
# =============================================================

@export var enabled: bool = true
# Set to false to disable completely — useful for release builds.
# Can also be toggled at runtime: DebugOverlay.enabled = false


# =============================================================
# STATE
# =============================================================

var _root: Control
var _content_label: Label
var _tab_label: Label

# "DELETE ALL SAVES" button — shown in the top-right corner of
# the F1 overlay. Clicked via the manual dispatch pattern in
# _input (Button.pressed signal doesn't fire because GUI dispatch
# is broken in this project; same workaround as MainMenu /
# PauseMenu). Two-click confirmation: first click flips the
# button label to "CONFIRM?"; second click within 3 seconds
# actually wipes user://saves/.
var _delete_saves_btn: Button
var _delete_saves_armed: bool = false
var _delete_saves_arm_remaining: float = 0.0

# Always-on coords HUD (separate from the F1 toggleable overlay).
# Small label in the top-left corner that updates every frame
# with the player's world position. Useful for "where am I?" and
# voxel debugging without having to open the full debug panel.
var _coords_label: Label

# Always-on "where am I aiming?" debug — a crosshair at screen
# center plus a label showing the world-space hit position from
# the camera-forward raycast. If the label says "(no hit)" you
# know the ray isn't reaching anything; if it has coordinates,
# you're aiming at terrain at that exact spot.
var _aim_label: Label
var _crosshair_h: ColorRect
var _crosshair_v: ColorRect

enum DebugTab { RECENT, ALL_FLAGS, COMPANIONS }
var _current_tab: DebugTab = DebugTab.RECENT


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 98
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_ui()
	_build_coords_hud()
	_build_aim_hud()
	_root.visible = false

	print("[DebugOverlay] Initialized.")


func _process(delta: float) -> void:
	# Live HUD updates — runs every frame the overlay autoload is
	# alive (always, in practice). Cheap: a few node lookups and
	# string formats per frame.
	if not enabled:
		return
	if _coords_label != null:
		_update_coords_label()
	if _aim_label != null:
		_update_aim_label()

	# Disarm the delete-saves button after 3 seconds of inactivity.
	# Prevents an accidental "armed" state from persisting indefinitely.
	if _delete_saves_armed:
		_delete_saves_arm_remaining -= delta
		if _delete_saves_arm_remaining <= 0.0:
			_disarm_delete_saves()


func _build_coords_hud() -> void:
	# A small always-visible label in the top-left corner showing
	# Roland's current world position. NOT inside the F1 toggle
	# overlay — this lives directly on the CanvasLayer so it
	# stays visible during normal play. Tied to `enabled` so a
	# release build with enabled=false hides everything.
	#
	# mouse_filter = IGNORE so this label can NEVER intercept a
	# click. The DebugOverlay CanvasLayer sits at layer 98, above
	# the main menu (layer 0), pause menu (layer 50), and journal
	# (layer 10) — without IGNORE, a Label here at higher layer
	# can swallow clicks meant for a button on a lower layer.
	_coords_label = Label.new()
	_coords_label.position = Vector2(12, 12)
	_coords_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coords_label.add_theme_font_size_override("font_size", 14)
	_coords_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	# Add a subtle drop-shadow so the label reads on light backgrounds.
	_coords_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_coords_label.add_theme_constant_override("shadow_offset_x", 1)
	_coords_label.add_theme_constant_override("shadow_offset_y", 1)
	_coords_label.text = "X 0.0  Y 0.0  Z 0.0"
	add_child(_coords_label)


func _update_coords_label() -> void:
	# Find the player by group. Group "player" is set on the
	# Player3D scene root (see scenes/Player3D.tscn).
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_coords_label.text = "(no player)"
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return
	var p: Vector3 = player.global_position
	# One decimal place is enough for "where am I" debugging without
	# making the label flicker too fast as the player walks.
	_coords_label.text = "X %.1f   Y %.1f   Z %.1f" % [p.x, p.y, p.z]


func _build_aim_hud() -> void:
	# Crosshair at screen center — two thin ColorRects forming a +.
	# CanvasLayer respects FullRect anchors so we anchor each rect
	# to screen center via a wrapper Control.
	var crosshair_root := Control.new()
	crosshair_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair_root)

	var crosshair_color := Color(1, 1, 1, 0.7)

	_crosshair_h = ColorRect.new()
	_crosshair_h.color = crosshair_color
	_crosshair_h.size = Vector2(14, 2)
	_crosshair_h.position = Vector2(-7, -1)  # center the rect on (0,0)
	_crosshair_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_root.add_child(_crosshair_h)

	_crosshair_v = ColorRect.new()
	_crosshair_v.color = crosshair_color
	_crosshair_v.size = Vector2(2, 14)
	_crosshair_v.position = Vector2(-1, -7)
	_crosshair_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_root.add_child(_crosshair_v)

	# "Aim target" label — sits below the coords label in the top-
	# left corner. Shows the world position the camera-forward ray
	# is currently hitting, plus distance from the player. Updates
	# every frame so the developer can see what they're aiming at
	# without clicking. Same IGNORE filter so it can't block clicks.
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
	# Query the same raycast EditToolHandler uses on click. If it
	# returns a hit, show the world position and the distance
	# from the player. If it returns nothing, show "(no hit)".
	#
	# Uses the same code path as the click handler so the label
	# is a true preview — if this shows coordinates, a click would
	# remove a voxel exactly there.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_aim_label.text = "AIM: (no player)"
		return
	var player: Node3D = players[0] as Node3D
	var camera_rig := player.get_node_or_null("CameraTarget/SpringArm3D")
	if camera_rig == null or not camera_rig.has_method("get_camera_forward_hit"):
		_aim_label.text = "AIM: (no camera rig)"
		return

	# Use the same default reach as EditToolHandler (4m from player).
	var hit: Dictionary = camera_rig.get_camera_forward_hit(4.0)
	if hit.is_empty():
		_aim_label.text = "AIM: (no hit within 4m of player)"
		return

	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
	var dist_from_player: float = player.global_position.distance_to(hit_pos)
	_aim_label.text = "AIM: (%.1f, %.1f, %.1f)  dist %.1fm" % [
		hit_pos.x, hit_pos.y, hit_pos.z, dist_from_player
	]


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	# Semi-transparent dark background covering the right half of the screen.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# Tab label at the top — sized for 1920×1080.
	_tab_label = Label.new()
	_tab_label.position = Vector2(12, 8)
	_tab_label.add_theme_font_size_override("font_size", 18)
	_tab_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4, 1))
	_root.add_child(_tab_label)

	# DELETE ALL SAVES button — top-right corner. Two-click
	# confirmation gates the destructive action.
	_delete_saves_btn = Button.new()
	_delete_saves_btn.text = "DELETE ALL SAVES"
	_delete_saves_btn.add_theme_font_size_override("font_size", 14)
	_delete_saves_btn.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
	_delete_saves_btn.size = Vector2(180, 30)
	_delete_saves_btn.anchor_left = 1.0
	_delete_saves_btn.anchor_right = 1.0
	_delete_saves_btn.offset_left = -190
	_delete_saves_btn.offset_top = 4
	_delete_saves_btn.offset_right = -10
	_delete_saves_btn.offset_bottom = 34
	_root.add_child(_delete_saves_btn)

	# Scrollable content label below.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 38
	_root.add_child(scroll)

	_content_label = Label.new()
	_content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_label.add_theme_font_size_override("font_size", 15)
	_content_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(_content_label)


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
					_refresh()
				else:
					_disarm_delete_saves()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				if _root.visible:
					_current_tab = ((_current_tab + 1) % 3) as DebugTab
					_refresh()
					get_viewport().set_input_as_handled()


# Manual click dispatch — same workaround as MainMenu / PauseMenu.
# GUI dispatch is silently disabled in this project, so Button.pressed
# never fires. We listen in _input and dispatch by hit-testing each
# interactive Control's global rect.
func _input(event: InputEvent) -> void:
	if not enabled or _root == null or not _root.visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _delete_saves_btn != null and _delete_saves_btn.visible \
		and _delete_saves_btn.get_global_rect().has_point(mb.position):
		_on_delete_saves_clicked()


func _on_delete_saves_clicked() -> void:
	if not _delete_saves_armed:
		# First click — arm the button. Visual change so the dev can
		# see the second click is destructive.
		_delete_saves_armed = true
		_delete_saves_arm_remaining = 3.0
		_delete_saves_btn.text = "CONFIRM? (3s)"
		return
	# Second click within window — execute.
	if get_node_or_null("/root/GameState"):
		var n: int = GameState.delete_all_save_files()
		print("[DebugOverlay] Wiped %d save file(s) via debug button." % n)
	_disarm_delete_saves()


func _disarm_delete_saves() -> void:
	_delete_saves_armed = false
	_delete_saves_arm_remaining = 0.0
	if _delete_saves_btn != null:
		_delete_saves_btn.text = "DELETE ALL SAVES"


# =============================================================
# CONTENT
# =============================================================

func _refresh() -> void:
	match _current_tab:
		DebugTab.RECENT:
			_tab_label.text = "[ F1 ] DEBUG — RECENT FLAGS  (TAB to switch)"
			_content_label.text = _build_recent_text()
		DebugTab.ALL_FLAGS:
			_tab_label.text = "[ F1 ] DEBUG — ALL FLAGS  (TAB to switch)"
			_content_label.text = _build_all_flags_text()
		DebugTab.COMPANIONS:
			_tab_label.text = "[ F1 ] DEBUG — COMPANIONS  (TAB to switch)"
			_content_label.text = _build_companions_text()


func _build_recent_text() -> String:
	var lines: Array = []
	var history: Array = GameState.get_flag_history(30)
	if history.is_empty():
		return "No flag changes yet."
	for entry in history:
		lines.append("[%s]  %s\n  %s → %s" % [
			entry["time"],
			entry["flag"],
			entry["old"],
			entry["new"],
		])
	return "\n\n".join(lines)


func _build_all_flags_text() -> String:
	var all_flags: Dictionary = {}
	# Build a sorted list.
	for flag_name in GameState._flags.keys():
		all_flags[flag_name] = GameState._flags[flag_name]
	var keys: Array = all_flags.keys()
	keys.sort()
	var lines: Array = []
	for k in keys:
		lines.append("%s = %s" % [k, str(all_flags[k])])
	if lines.is_empty():
		return "No flags set."
	lines.insert(0, "scene: %s" % GameState.current_scene)
	lines.insert(1, "spawn_id: %s" % GameState.player_spawn_id)
	lines.insert(2, "active_save: %s" % (GameState.active_save_filename if GameState.active_save_filename != "" else "(none)"))
	lines.insert(3, "")
	return "\n".join(lines)


func _build_companions_text() -> String:
	var lines: Array = ["COMPANION ROSTER\n"]
	# Access the internal _companions dict directly for debug purposes.
	for companion_id in GameState._companions.keys():
		var state: String = "ACTIVE" if GameState._companions[companion_id] else "inactive"
		lines.append("%s  —  %s" % [companion_id.to_upper(), state])
	return "\n".join(lines)
