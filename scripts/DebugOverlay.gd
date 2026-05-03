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

# Always-on coords HUD (separate from the F1 toggleable overlay).
# Small label in the top-left corner that updates every frame
# with the player's world position. Useful for "where am I?" and
# voxel debugging without having to open the full debug panel.
var _coords_label: Label

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
	_root.visible = false

	print("[DebugOverlay] Initialized.")


func _process(_delta: float) -> void:
	# Live coords update — runs every frame the overlay autoload is
	# alive (always, in practice). Cheap: one node lookup + one
	# string format per frame.
	if not enabled or _coords_label == null:
		return
	_update_coords_label()


func _build_coords_hud() -> void:
	# A small always-visible label in the top-left corner showing
	# Roland's current world position. NOT inside the F1 toggle
	# overlay — this lives directly on the CanvasLayer so it
	# stays visible during normal play. Tied to `enabled` so a
	# release build with enabled=false hides everything.
	_coords_label = Label.new()
	_coords_label.position = Vector2(12, 12)
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
				get_viewport().set_input_as_handled()
			KEY_TAB:
				if _root.visible:
					_current_tab = ((_current_tab + 1) % 3) as DebugTab
					_refresh()
					get_viewport().set_input_as_handled()


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
	lines.insert(2, "save_slot: %d" % GameState.active_save_slot)
	lines.insert(3, "")
	return "\n".join(lines)


func _build_companions_text() -> String:
	var lines: Array = ["COMPANION ROSTER\n"]
	# Access the internal _companions dict directly for debug purposes.
	for companion_id in GameState._companions.keys():
		var state: String = "ACTIVE" if GameState._companions[companion_id] else "inactive"
		lines.append("%s  —  %s" % [companion_id.to_upper(), state])
	return "\n".join(lines)
