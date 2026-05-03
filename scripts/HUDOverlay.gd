extends CanvasLayer
# HUDOverlay — Health and endurance bars, bottom-center of the screen.
#
# What this does in plain English:
#   During gameplay two progress bars sit near the bottom of the screen.
#   The top bar (red) shows Roland's health. The bottom bar (green) shows
#   his endurance — how much sprinting energy he has left.
#   A small status label above the bars shows "CROUCHING" or "EXHAUSTED"
#   when those states are active.
#
#   This script finds the player automatically each frame by searching for
#   nodes in the "player" group (Player3D.tscn adds itself to that group).
#   If no player exists — e.g. when the main menu is showing — the HUD
#   hides itself cleanly.
#
# HOW TO ADJUST THE LOOK:
#   Edit the constants at the top of _build_ui() below.
#   PANEL_WIDTH / PANEL_HEIGHT — overall size of the HUD container.
#   BAR_HP_HEIGHT / BAR_END_HEIGHT — thickness of each bar.
#   Fill and background colors are in the StyleBoxFlat blocks.


# =============================================================
# NODE REFERENCES (set in _build_ui, read in _process every frame)
# =============================================================

var _root: Control
var _hp_bar: ProgressBar
var _end_bar: ProgressBar
var _hp_value_label: Label
var _end_value_label: Label
var _status_label: Label

# Cached so _find_player() doesn't search every frame when the player
# hasn't changed. Invalidated when the node becomes null.
var _cached_player: Node = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 5
	# Layer 5: above the game world, below the journal (10) and pause (50).
	_build_ui()
	print("[HUDOverlay] Initialized.")


func _build_ui() -> void:
	# --- Size / position constants ---
	const PANEL_WIDTH: float    = 540.0   # Width of the HUD panel in pixels.
	const PANEL_HEIGHT: float   = 110.0   # Height of the HUD panel.
	const BOTTOM_MARGIN: float  = 36.0    # Pixels from the bottom edge of the screen.
	const LABEL_FONT: int       = 18      # "HP" / "END" label font size.
	const VALUE_FONT: int       = 16      # "80/100" value font size.
	const STATUS_FONT: int      = 16      # CROUCHING / EXHAUSTED font size.
	const BAR_HP_HEIGHT: float  = 26.0    # Height of the health bar.
	const BAR_END_HEIGHT: float = 22.0    # Height of the endurance bar.

	# Root control anchored to bottom-center of the viewport.
	# mouse_filter = IGNORE so this purely-visual HUD never
	# intercepts clicks meant for menus or the world. The HUD
	# only displays HP/endurance/status; it doesn't take input.
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.anchor_left   = 0.5
	_root.anchor_right  = 0.5
	_root.anchor_top    = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left   = -(PANEL_WIDTH * 0.5)
	_root.offset_right  =  (PANEL_WIDTH * 0.5)
	_root.offset_top    = -(PANEL_HEIGHT + BOTTOM_MARGIN)
	_root.offset_bottom = -BOTTOM_MARGIN
	add_child(_root)

	# Semi-transparent dark background so bars are readable against any scene.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# Vertical layout inside the panel.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  14
	vbox.offset_top    =  10
	vbox.offset_right  = -14
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vbox)

	# --- Status label (CROUCHING / EXHAUSTED) ---
	# Always present in the layout; text is set to "" when not needed.
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size = Vector2(0, STATUS_FONT + 4)
	_status_label.add_theme_font_size_override("font_size", STATUS_FONT)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.1, 1))
	vbox.add_child(_status_label)

	# --- Health row: [HP label] [bar] [80/100] ---
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	vbox.add_child(hp_row)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP"
	hp_lbl.custom_minimum_size = Vector2(46, 0)
	hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_lbl.add_theme_font_size_override("font_size", LABEL_FONT)
	hp_lbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35, 1))
	hp_row.add_child(hp_lbl)

	_hp_bar = ProgressBar.new()
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.custom_minimum_size = Vector2(0, BAR_HP_HEIGHT)
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value     = 100.0
	_hp_bar.show_percentage = false
	var hp_bg_style := StyleBoxFlat.new()
	hp_bg_style.bg_color = Color(0.20, 0.05, 0.05, 1)
	_hp_bar.add_theme_stylebox_override("background", hp_bg_style)
	var hp_fill_style := StyleBoxFlat.new()
	hp_fill_style.bg_color = Color(0.85, 0.15, 0.15, 1)
	_hp_bar.add_theme_stylebox_override("fill", hp_fill_style)
	hp_row.add_child(_hp_bar)

	_hp_value_label = Label.new()
	_hp_value_label.custom_minimum_size = Vector2(80, 0)
	_hp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_value_label.add_theme_font_size_override("font_size", VALUE_FONT)
	_hp_value_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.75, 1))
	hp_row.add_child(_hp_value_label)

	# --- Endurance row: [END label] [bar] [50/100] ---
	var end_row := HBoxContainer.new()
	end_row.add_theme_constant_override("separation", 8)
	vbox.add_child(end_row)

	var end_lbl := Label.new()
	end_lbl.text = "END"
	end_lbl.custom_minimum_size = Vector2(46, 0)
	end_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_lbl.add_theme_font_size_override("font_size", LABEL_FONT)
	end_lbl.add_theme_color_override("font_color", Color(0.30, 0.90, 0.45, 1))
	end_row.add_child(end_lbl)

	_end_bar = ProgressBar.new()
	_end_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_bar.custom_minimum_size = Vector2(0, BAR_END_HEIGHT)
	_end_bar.min_value = 0.0
	_end_bar.max_value = 100.0
	_end_bar.value     = 100.0
	_end_bar.show_percentage = false
	var end_bg_style := StyleBoxFlat.new()
	end_bg_style.bg_color = Color(0.05, 0.18, 0.05, 1)
	_end_bar.add_theme_stylebox_override("background", end_bg_style)
	var end_fill_style := StyleBoxFlat.new()
	end_fill_style.bg_color = Color(0.20, 0.80, 0.30, 1)
	_end_bar.add_theme_stylebox_override("fill", end_fill_style)
	end_row.add_child(_end_bar)

	_end_value_label = Label.new()
	_end_value_label.custom_minimum_size = Vector2(80, 0)
	_end_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_end_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_value_label.add_theme_font_size_override("font_size", VALUE_FONT)
	_end_value_label.add_theme_color_override("font_color", Color(0.70, 0.85, 0.72, 1))
	end_row.add_child(_end_value_label)


# =============================================================
# UPDATE LOOP
# =============================================================

func _process(_delta: float) -> void:
	var player := _find_player()

	if player == null:
		_root.visible = false
		return

	_root.visible = true

	# Read values from the player and push them into the bars.
	_hp_bar.max_value      = player.max_health
	_hp_bar.value          = player.health
	_hp_value_label.text   = "%d / %d" % [int(player.health), int(player.max_health)]

	_end_bar.max_value     = player.max_endurance
	_end_bar.value         = player.endurance
	_end_value_label.text  = "%d / %d" % [int(player.endurance), int(player.max_endurance)]

	# Status label: "CROUCHING", "EXHAUSTED", or blank.
	_status_label.text = player.status_text


# =============================================================
# PLAYER LOOKUP
# =============================================================

func _find_player() -> Node:
	# Use the cached reference if it's still valid.
	if is_instance_valid(_cached_player):
		return _cached_player

	# Search by group — Player3D.tscn adds itself to the "player" group.
	var players := get_tree().get_nodes_in_group("player")
	_cached_player = players[0] if not players.is_empty() else null
	return _cached_player
