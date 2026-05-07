class_name BarkOverlay
extends Control

# BarkOverlay — top-centre text frame that surfaces NPC barks.
#
# Contract with BarkManager (see scripts/BarkManager.gd):
#   - Joins the "bark_overlay" group on _ready so BarkManager can find
#     it via get_first_node_in_group.
#   - Exposes show_bark(npc_id, line, duration) — BarkManager calls
#     this after _pick_line.
#
# Visuals:
#   Oak-gradient panel below the compass strip, ~560×96. Left column is
#   a 64×64 iron portrait placeholder containing the NPC's first
#   initial (real portraits land later — see assets/portraits/ +
#   NPCData). Right column is the NPC name (serif gold, 16 px) above
#   the line itself (body ink, 16 px, word-wrapped).
#
# Lifecycle:
#   show_bark fades the panel in (0.18 s) and starts the hide timer.
#   On timeout the panel fades out (0.4 s) and toggles visible=false
#   so it doesn't absorb future tween writes when off-screen.
#
# Built once in code at HUDOverlay._build_bark_overlay() — there's no
# .tscn for this scene; the layout is small enough that the script
# owns it entirely.

const FADE_IN_S: float = 0.18
const FADE_OUT_S: float = 0.40
const PORTRAIT_SIZE: float = 64.0
const PANEL_W: float = 560.0
const PANEL_H: float = 96.0
# Vertical offset from the top of the viewport — sits below the compass
# strip (which occupies ~y=18 to y=90 with its coord label).
const TOP_OFFSET: float = 110.0

var _panel: Panel
var _portrait: Panel
var _portrait_initial: Label
var _name_label: Label
var _line_label: Label
var _hide_timer: Timer
var _active_tween: Tween


func _ready() -> void:
	# BarkManager looks up the overlay every fire() until it has a
	# reference. Joining the group up front means the very first bark
	# of the session resolves cleanly.
	add_to_group("bark_overlay")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_self()
	_build_ui()
	_hide_immediately()


func _layout_self() -> void:
	# Top-centre, fixed-width.
	anchor_left   = 0.5
	anchor_right  = 0.5
	anchor_top    = 0.0
	anchor_bottom = 0.0
	offset_left   = -(PANEL_W * 0.5)
	offset_right  =  (PANEL_W * 0.5)
	offset_top    = TOP_OFFSET
	offset_bottom = TOP_OFFSET + PANEL_H


func _build_ui() -> void:
	# Oak panel chrome.
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UIStyles.menu_body_panel())
	add_child(_panel)

	# Inner padding.
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left   = 12
	hbox.offset_right  = -12
	hbox.offset_top    = 8
	hbox.offset_bottom = -8
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(hbox)

	# Portrait placeholder — iron square with the NPC's first initial.
	# Real portraits land later (assets/portraits/ + NPCData lookup).
	_portrait = Panel.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_sb := StyleBoxFlat.new()
	portrait_sb.bg_color = Colors.PANEL_IRON
	portrait_sb.border_color = Colors.PANEL_IRON_EDGE
	portrait_sb.set_border_width_all(2)
	_portrait.add_theme_stylebox_override("panel", portrait_sb)
	hbox.add_child(_portrait)

	_portrait_initial = Label.new()
	_portrait_initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyles.apply_title_label(_portrait_initial, 36)
	_portrait.add_child(_portrait_initial)

	# Right column — name on top, line below.
	var text_v := VBoxContainer.new()
	text_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_v.size_flags_vertical = Control.SIZE_FILL
	text_v.add_theme_constant_override("separation", 4)
	text_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_v)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyles.apply_subtitle_label(_name_label)
	_name_label.add_theme_font_size_override("font_size", 16)
	text_v.add_child(_name_label)

	_line_label = Label.new()
	_line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyles.apply_body_label(_line_label, 16)
	text_v.add_child(_line_label)

	# Auto-hide timer — restarted on every show_bark.
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_on_hide_timeout)
	add_child(_hide_timer)


# --- Public API -----------------------------------------------------

# Display a bark from `npc_id` reading `line`. The frame fades in,
# stays visible for `duration` seconds, then fades out.
# Restarts the timer if a bark is already showing — interrupting one
# is fine, the new one takes the slot.
func show_bark(npc_id: String, line: String, duration: float = 3.5) -> void:
	var display_name := _display_name(npc_id)
	if _name_label != null:
		_name_label.text = display_name
	if _portrait_initial != null:
		_portrait_initial.text = display_name.left(1).to_upper() if display_name != "" else "?"
	if _line_label != null:
		_line_label.text = line
	visible = true
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_S)
	if _hide_timer != null:
		_hide_timer.start(duration)


# --- Internal -------------------------------------------------------

func _hide_immediately() -> void:
	visible = false
	modulate.a = 0.0


func _on_hide_timeout() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_S)
	_active_tween.tween_callback(func():
		visible = false
	)


# Best-effort display name lookup. NPCData resources live in
# assets/npcs/{npc_id}.tres (per CLAUDE.md). If the resource doesn't
# exist yet (early production), capitalise the npc_id as a fallback.
func _display_name(npc_id: String) -> String:
	if npc_id == "":
		return "?"
	var resource_path := "res://assets/npcs/%s.tres" % npc_id
	if ResourceLoader.exists(resource_path):
		var data: Resource = load(resource_path)
		if data != null and "display_name" in data:
			var dn: String = String(data.get("display_name"))
			if dn != "":
				return dn
	return npc_id.capitalize()
