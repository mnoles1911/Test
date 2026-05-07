extends Control

# Voxelmark loading screen — port of Voxelmark Loading Screen.html.
#
# Shows: animated hourglass (custom-drawn particle sim), "LOADING" title,
# rotating tip line, sand-gradient progress bar, footer hint.
#
# Public API:
#   show_loading()             — make visible, start animations
#   hide_loading()             — fade out, stop animations
#   set_progress(pct: float)   — 0..1, drives the bar fill
#
# STATUS (2026-05-06):
#   TransitionManager.gd retains its own inline loading screen — the
#   in-tree one with background-art rotation (LOADING_BG_DIR), music
#   adoption (adopt_music), and quip shuffling (LOADING_QUIPS). That
#   loader has been retrofitted onto Colors / UIStyles in the same pass
#   that introduced this scene, so the runtime look already matches the
#   Voxelmark palette. This scene remains as a future swap target for
#   when the team is ready to consolidate the loader into a Control
#   subtree — it currently lacks BG rotation and music adoption, both of
#   which would have to be replicated (or the orchestration kept on
#   TransitionManager and the visuals delegated here) before the swap.

const HOURGLASS_W := 120.0
const HOURGLASS_H := 180.0
const MAX_GRAINS  := 38
const TIP_INTERVAL := 3.4

const TIPS: Array[String] = [
	"Mira-Thal — in the third age. Your sword is sharp. The goblins are coming",
	"Press [E] to talk to NPCs. They have names. Most have things to do.",
	"Edits to the world persist. The pit you dug last week is still there.",
	"Hold attack longer for a heavier swing — at the cost of stamina.",
	"Lock-on with [RMB]. Useful when one-vs-many.",
	"Settlements are protected. The world won't yield inside their walls.",
	"Water flows. If you carve under a pond, expect a small flood.",
	"Companions can be ordered to hold position or follow at distance.",
	"Save anywhere from the pause menu. Rest at a fire to autosave.",
	"Lethe's Draught lets you re-spec — once. Spend it carefully.",
	"Rain dampens fire. Wet bowstrings misfire. Dress for the weather.",
	"The compass points north. The sun rises east. The map is hand-drawn.",
	"You can throw most things. Sometimes that solves the problem.",
]

var _grains: Array[Dictionary] = []  # each: {pos: Vector2, vel: Vector2, in_top: bool}
var _hourglass_node: Control
var _title_label: Label
var _message_label: Label
var _progress_bar_bg: ColorRect
var _progress_bar_fill: ColorRect
var _tip_label: Label
var _tip_timer: Timer
var _tip_index := 0
var _progress := 0.0
var _active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()
	_seed_grains()


func _build_ui() -> void:
	# Black background.
	var bg := ColorRect.new()
	bg.color = Colors.BG_NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Center stack.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(stack)

	# Hourglass (custom-drawn).
	_hourglass_node = Control.new()
	_hourglass_node.custom_minimum_size = Vector2(HOURGLASS_W, HOURGLASS_H)
	_hourglass_node.draw.connect(_draw_hourglass)
	stack.add_child(_hourglass_node)

	# Title.
	_title_label = Label.new()
	_title_label.text = "LOADING"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_title_label(_title_label, 40)
	stack.add_child(_title_label)

	# Rotating message.
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.custom_minimum_size = Vector2(560, 0)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyles.apply_dim_label(_message_label, 18)
	_message_label.text = TIPS[0]
	stack.add_child(_message_label)

	# Progress bar — bg + fill, manual layout so we can do gradient fill.
	var bar_root := Control.new()
	bar_root.custom_minimum_size = Vector2(420, 10)
	stack.add_child(bar_root)
	_progress_bar_bg = ColorRect.new()
	_progress_bar_bg.color = Colors.PARCHMENT_2.darkened(0.4)
	_progress_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_root.add_child(_progress_bar_bg)
	_progress_bar_fill = ColorRect.new()
	_progress_bar_fill.color = Colors.GOLD
	_progress_bar_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_progress_bar_fill.size_flags_horizontal = 0
	_progress_bar_fill.offset_right = 0
	bar_root.add_child(_progress_bar_fill)

	# Tip label below.
	_tip_label = Label.new()
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_muted_label(_tip_label, 13)
	_tip_label.text = "Tip: edits persist. The world remembers."
	stack.add_child(_tip_label)

	# Tip rotation timer.
	_tip_timer = Timer.new()
	_tip_timer.wait_time = TIP_INTERVAL
	_tip_timer.timeout.connect(_advance_tip)
	add_child(_tip_timer)


func _seed_grains() -> void:
	# Seed a few grains so the first frame isn't empty.
	for i in range(8):
		_grains.append({
			"pos": Vector2(HOURGLASS_W * 0.5 + randf_range(-12, 12), HOURGLASS_H * 0.45 + randf_range(-20, 0)),
			"vel": Vector2(randf_range(-4, 4), randf_range(40, 80)),
		})


func _process(delta: float) -> void:
	if not _active:
		return
	_step_grains(delta)
	if _hourglass_node:
		_hourglass_node.queue_redraw()


func _step_grains(delta: float) -> void:
	# Spawn new grains at the top while under cap.
	if _grains.size() < MAX_GRAINS and randf() < 0.7:
		_grains.append({
			"pos": Vector2(HOURGLASS_W * 0.5 + randf_range(-30, 30), 12.0),
			"vel": Vector2(randf_range(-6, 6), randf_range(20, 50)),
		})

	var bottom_floor := HOURGLASS_H - 16.0
	var to_remove: Array[int] = []

	for i in range(_grains.size()):
		var g: Dictionary = _grains[i]
		var pos: Vector2 = g["pos"]
		var vel: Vector2 = g["vel"]
		vel.y += 220.0 * delta  # gravity
		pos += vel * delta
		# Funnel through neck around mid-height.
		var t: float = pos.y / HOURGLASS_H
		if t > 0.4 and t < 0.55:
			var neck_x: float = HOURGLASS_W * 0.5
			pos.x = lerp(pos.x, neck_x + randf_range(-2, 2), 0.5)
			vel.x *= 0.6
		# Settle on the bottom mound.
		if pos.y >= bottom_floor:
			pos.y = bottom_floor
			vel = Vector2.ZERO
			# Mark very-old settled grains for replacement to keep flow visible.
			if randf() < 0.02:
				to_remove.append(i)
		g["pos"] = pos
		g["vel"] = vel
		_grains[i] = g

	# Remove from back to keep indices valid.
	for idx in range(to_remove.size() - 1, -1, -1):
		_grains.remove_at(to_remove[idx])


func _draw_hourglass() -> void:
	# Glass outline — two opposed triangles meeting at the neck.
	var w := HOURGLASS_W
	var h := HOURGLASS_H
	var glass_col := Colors.PARCHMENT_EDGE.darkened(0.2)
	# Top bell.
	_hourglass_node.draw_polyline(PackedVector2Array([
		Vector2(8, 0), Vector2(w - 8, 0), Vector2(w * 0.5, h * 0.5), Vector2(8, 0),
	]), glass_col, 2.0, true)
	# Bottom bell.
	_hourglass_node.draw_polyline(PackedVector2Array([
		Vector2(8, h), Vector2(w - 8, h), Vector2(w * 0.5, h * 0.5), Vector2(8, h),
	]), glass_col, 2.0, true)
	# Brass caps.
	var brass := Colors.BRONZE
	_hourglass_node.draw_rect(Rect2(0, -4, w, 6), brass, true)
	_hourglass_node.draw_rect(Rect2(0, h - 2, w, 6), brass, true)
	# Sand grains.
	for g in _grains:
		var gp: Vector2 = g["pos"]
		_hourglass_node.draw_rect(Rect2(gp - Vector2(1.5, 1.5), Vector2(3, 3)), Colors.GOLD, true)


func _advance_tip() -> void:
	_tip_index = (_tip_index + 1) % TIPS.size()
	# Quick fade swap.
	var t := create_tween()
	t.tween_property(_message_label, "modulate:a", 0.0, 0.25)
	t.tween_callback(func():
		_message_label.text = TIPS[_tip_index]
	)
	t.tween_property(_message_label, "modulate:a", 1.0, 0.25)


# --- Public API ----------------------------------------------------------

func show_loading() -> void:
	visible = true
	_active = true
	_progress = 0.0
	_update_progress_bar_visual()
	_tip_index = 0
	if _message_label:
		_message_label.text = TIPS[0]
		_message_label.modulate.a = 1.0
	if _tip_timer:
		_tip_timer.start()

func hide_loading() -> void:
	_active = false
	if _tip_timer:
		_tip_timer.stop()
	# Quick fade out.
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_callback(func():
		visible = false
		modulate.a = 1.0
	)

func set_progress(pct: float) -> void:
	_progress = clamp(pct, 0.0, 1.0)
	_update_progress_bar_visual()

func _update_progress_bar_visual() -> void:
	if _progress_bar_fill == null:
		return
	# The bar root is 420 wide; fill spans the same parent rect by setting offset_right.
	var parent_w: float = _progress_bar_fill.get_parent_control().size.x
	if parent_w <= 0:
		parent_w = 420.0
	_progress_bar_fill.anchor_right = 0.0
	_progress_bar_fill.offset_right = parent_w * _progress
