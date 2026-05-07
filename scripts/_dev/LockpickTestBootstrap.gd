extends Node3D
# LockpickTestBootstrap — root script for scenes/LockpickTest.tscn
#
# What this does in plain English:
#   This is a self-contained test environment for the lockpicking minigame.
#   No Player3D, no terrain, no world systems needed. Just run the scene
#   and use the keyboard to open any lock tier. A full debug menu (F1)
#   lets you tweak every feel parameter without touching code or restarting.
#
# CONTROLS:
#   1 — Open Easy lock (1 pin)
#   2 — Open Medium lock (2 pins)
#   3 — Open Hard lock (3 pins + 1 false resonance)
#   4 — Open Very Hard lock (3 pins + 2 false resonances)
#   F1 — Toggle the debug menu
#   Esc — Close current lock (no pick consumed)
#
# DEBUG MENU PANELS:
#   Panel A — Lock Setup (tier, skill tier, pick inventory, open button)
#   Panel B — Feel Tuning (live sliders for all LockpickingUI constants)
#   Panel C — Debug Visibility (pin positions, zones, back-pressure, timer)
#   Panel D — Result Log (last 20 events)


# ─── STATE ─────────────────────────────────────────────────────────────────

var _active_ui: LockpickingUI = null   # currently open UI instance, or null
var _debug_canvas: CanvasLayer = null  # the debug menu layer
var _debug_visible: bool = false

# References to debug sliders so _process can push values to _active_ui.
var _sliders: Dictionary = {}     # slider_name → HSlider
var _debug_checks: Dictionary = {} # check_name → CheckBox
var _log_label: RichTextLabel = null

# Current settings from Panel A.
var _selected_tier: int       = 0    # 0–3
var _selected_skill: int      = 0    # 0–2
var _selected_fine: bool      = false

# Event log ring buffer.
var _log_entries: Array[String] = []
const LOG_MAX: int = 20


# ─── READY ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Tell gameplay UI autoloads to stay dormant in this dev scene.
	add_to_group("dev_scene")

	# Seed the inventory with picks for testing.
	InventoryManager.add_item("lockpick_standard", 15)
	InventoryManager.add_item("lockpick_fine", 5)

	_build_instructions_ui()
	_build_debug_menu()

	_log_event("Test scene ready. Press 1–4 to open a lock.")


# ─── KEYBOARD INPUT ────────────────────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		return  # let LockpickingUI handle Esc

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _open_lock(0)
			KEY_2: _open_lock(1)
			KEY_3: _open_lock(2)
			KEY_4: _open_lock(3)
			KEY_F1: _toggle_debug_menu()


# ─── LOCK OPEN ─────────────────────────────────────────────────────────────

func _open_lock(tier: int) -> void:
	if _active_ui != null:
		return   # already picking a lock

	# Ensure inventory isn't empty before opening.
	if not (InventoryManager.has_item("lockpick_standard")
	        or InventoryManager.has_item("lockpick_fine")):
		InventoryManager.add_item("lockpick_standard", 5)
		_log_event("No picks left — refilled 5 standard picks.")

	# Build a LockData inline (no .tres file needed for testing).
	var ld := LockData.new()
	ld.lock_id    = "test_lock_%d_%d" % [tier, randi() % 1000]
	ld.tier       = tier
	ld.pin_count  = [1, 2, 3, 3][tier]

	# Create the UI.
	_active_ui = LockpickingUI.new()

	# Apply current debug-menu skill tier setting.
	_active_ui._skill_tier = _selected_skill

	# Wire signals.
	_active_ui.lock_opened.connect(_on_lock_opened)
	_active_ui.lock_closed.connect(_on_lock_closed)

	get_tree().root.add_child(_active_ui)
	_active_ui.open(ld)

	_log_event("Opened %s lock (skill: %s, pick: %s)" % [
		["Easy", "Medium", "Hard", "Very Hard"][tier],
		["Novice", "Trained", "Expert"][_selected_skill],
		"Fine" if InventoryManager.has_item("lockpick_fine") else "Standard",
	])


func _on_lock_opened(lock_id: String) -> void:
	_log_event("✓ OPENED — %s" % lock_id)
	_active_ui = null


func _on_lock_closed() -> void:
	_active_ui = null


# ─── _PROCESS — push debug slider values to active UI every frame ──────────

func _process(_delta: float) -> void:
	if _active_ui == null or not _debug_visible:
		return

	# Panel B — push live slider values to the UI constants.
	if _sliders.has("rotate_speed"):
		_active_ui.ROTATE_SPEED_DEG = _sliders["rotate_speed"].value
	if _sliders.has("hold_novice"):
		_active_ui.HOLD_TIMER_BY_SKILL[0] = _sliders["hold_novice"].value
	if _sliders.has("hold_trained"):
		_active_ui.HOLD_TIMER_BY_SKILL[1] = _sliders["hold_trained"].value
	if _sliders.has("hold_expert"):
		_active_ui.HOLD_TIMER_BY_SKILL[2] = _sliders["hold_expert"].value
	if _sliders.has("fine_bonus"):
		# FINE_PICK_BONUS is a const in LockpickingUI — can't override directly;
		# this is a prototype-only workaround via a public var added to the UI.
		pass
	if _sliders.has("fill_rate"):
		_active_ui.BASE_FILL_RATE = _sliders["fill_rate"].value
	if _sliders.has("drain_moving"):
		_active_ui.DRAIN_RATE_MOVING = _sliders["drain_moving"].value
	if _sliders.has("back_dist"):
		_active_ui.BACK_PRESSURE_MIN_DIST = _sliders["back_dist"].value

	# Panel C — debug visibility flags.
	if _debug_checks.has("show_pins"):
		_active_ui.debug_mode       = true
		_active_ui.debug_show_pins  = _debug_checks["show_pins"].button_pressed
	if _debug_checks.has("show_zones"):
		_active_ui.debug_show_zones = _debug_checks["show_zones"].button_pressed
	if _debug_checks.has("show_bp"):
		_active_ui.debug_show_back_pressure = _debug_checks["show_bp"].button_pressed
	if _debug_checks.has("show_timer"):
		_active_ui.debug_show_hold_timer = _debug_checks["show_timer"].button_pressed

	# Slow mode.
	if _debug_checks.has("slow_mode"):
		Engine.time_scale = 0.25 if _debug_checks["slow_mode"].button_pressed else 1.0


# ─── INSTRUCTIONS UI ───────────────────────────────────────────────────────

func _build_instructions_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)

	var label := Label.new()
	label.text = (
		"LOCKPICK PROTOTYPE\n"
		+ "──────────────────\n"
		+ "1  Easy lock\n"
		+ "2  Medium lock\n"
		+ "3  Hard lock\n"
		+ "4  Very Hard lock\n"
		+ "F1  Debug menu\n"
		+ "Esc  Cancel picking"
	)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#f3e6c4"))
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.position = Vector2(20.0, 20.0)
	canvas.add_child(label)

	# Live pick count display.
	var pick_label := Label.new()
	pick_label.name = "PickCountLabel"
	pick_label.add_theme_font_size_override("font_size", 13)
	pick_label.add_theme_color_override("font_color", Color("#b4a07a"))
	pick_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pick_label.position = Vector2(20.0, 185.0)
	canvas.add_child(pick_label)

	# Update pick count every frame via a tiny _process on the label itself.
	pick_label.set_script(null)  # no script on the label; we update it from here
	set_meta("pick_count_label", pick_label)


func _process_pick_label() -> void:
	var lbl = get_meta("pick_count_label", null) as Label
	if lbl:
		var std  := InventoryManager.get_quantity("lockpick_standard")
		var fine := InventoryManager.get_quantity("lockpick_fine")
		lbl.text = "Picks: %d std  |  %d fine" % [std, fine]


# ─── DEBUG MENU ─────────────────────────────────────────────────────────────

func _toggle_debug_menu() -> void:
	_debug_visible = not _debug_visible
	if _debug_canvas:
		_debug_canvas.visible = _debug_visible


func _build_debug_menu() -> void:
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.layer   = 20   # above everything, including LockpickingUI (layer 10)
	_debug_canvas.visible = false
	add_child(_debug_canvas)

	# ── Outer panel ─────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	var ps    := StyleBoxFlat.new()
	ps.bg_color     = Color(0.08, 0.06, 0.04, 0.92)
	ps.border_color = Color("#4a4038")
	ps.border_width_left = ps.border_width_right = ps.border_width_top = ps.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", ps)
	panel.custom_minimum_size = Vector2(380.0, 680.0)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical   = Control.GROW_DIRECTION_END
	panel.position        = Vector2(-10.0, 10.0)
	_debug_canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_add_debug_heading(vbox, "⚙  LOCKPICK DEBUG  [ F1 ]")

	# ── Panel A — Lock Setup ──────────────────────────────────────────────
	_add_debug_heading(vbox, "A — Lock Setup")

	_add_debug_label(vbox, "Lock tier (1-4 keys also work)")
	var tier_opts := OptionButton.new()
	tier_opts.add_item("Easy")
	tier_opts.add_item("Medium")
	tier_opts.add_item("Hard")
	tier_opts.add_item("Very Hard")
	tier_opts.selected = 0
	tier_opts.item_selected.connect(func(idx): _selected_tier = idx)
	vbox.add_child(tier_opts)

	_add_debug_label(vbox, "Skill tier (affects hold timer)")
	var skill_opts := OptionButton.new()
	skill_opts.add_item("Novice (2.5 s)")
	skill_opts.add_item("Trained (3.5 s)")
	skill_opts.add_item("Expert (5.0 s)")
	skill_opts.selected = 0
	skill_opts.item_selected.connect(func(idx): _selected_skill = idx)
	vbox.add_child(skill_opts)

	var open_btn := Button.new()
	open_btn.text = "Open Selected Lock"
	open_btn.pressed.connect(func(): _open_lock(_selected_tier))
	vbox.add_child(open_btn)

	var refill_btn := Button.new()
	refill_btn.text = "Refill Picks (10 std + 3 fine)"
	refill_btn.pressed.connect(func():
		InventoryManager.add_item("lockpick_standard", 10)
		InventoryManager.add_item("lockpick_fine", 3)
		_log_event("Picks refilled: 10 std + 3 fine.")
	)
	vbox.add_child(refill_btn)

	_add_debug_separator(vbox)

	# ── Panel B — Feel Tuning ─────────────────────────────────────────────
	_add_debug_heading(vbox, "B — Feel Tuning (live)")

	_sliders["rotate_speed"] = _add_slider(vbox, "Rotate Speed (deg/s)",  30.0, 180.0, 90.0)
	_sliders["hold_novice"]  = _add_slider(vbox, "Hold Timer — Novice (s)", 1.0, 6.0, 2.5)
	_sliders["hold_trained"] = _add_slider(vbox, "Hold Timer — Trained (s)", 1.0, 6.0, 3.5)
	_sliders["hold_expert"]  = _add_slider(vbox, "Hold Timer — Expert (s)",  1.5, 8.0, 5.0)
	_sliders["fill_rate"]    = _add_slider(vbox, "Fill Rate (/s at I=1.0)",  0.2, 2.0, 0.65)
	_sliders["drain_moving"] = _add_slider(vbox, "Drain Rate — Moving (/s)", 0.5, 4.0, 1.5)
	_sliders["back_dist"]    = _add_slider(vbox, "Back Pressure Dist (°)",   80.0, 170.0, 130.0)

	_add_debug_separator(vbox)

	# ── Panel C — Debug Visibility ────────────────────────────────────────
	_add_debug_heading(vbox, "C — Debug Visibility")

	_debug_checks["show_pins"]  = _add_checkbox(vbox, "Show pin positions (dots on dial)")
	_debug_checks["show_zones"] = _add_checkbox(vbox, "Show resonance zone arcs")
	_debug_checks["show_bp"]    = _add_checkbox(vbox, "Show back-pressure zone")
	_debug_checks["show_timer"] = _add_checkbox(vbox, "Show hold-timer arc")
	_debug_checks["slow_mode"]  = _add_checkbox(vbox, "Slow Mode (0.25× speed)")

	_add_debug_separator(vbox)

	# ── Panel D — Result Log ──────────────────────────────────────────────
	_add_debug_heading(vbox, "D — Event Log")

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_active  = true
	_log_label.custom_minimum_size = Vector2(340.0, 120.0)
	_log_label.add_theme_font_size_override("font_size", 11)
	var log_bg := StyleBoxFlat.new()
	log_bg.bg_color = Color(0.04, 0.03, 0.02, 0.9)
	_log_label.add_theme_stylebox_override("normal", log_bg)
	vbox.add_child(_log_label)

	var clear_btn := Button.new()
	clear_btn.text = "Clear Log"
	clear_btn.pressed.connect(func():
		_log_entries.clear()
		_log_label.clear()
	)
	vbox.add_child(clear_btn)


# ─── DEBUG UI HELPERS ───────────────────────────────────────────────────────

func _add_debug_heading(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color("#f0c14b"))
	lbl.add_theme_font_size_override("font_size", 13)
	parent.add_child(lbl)


func _add_debug_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color("#b4a07a"))
	lbl.add_theme_font_size_override("font_size", 11)
	parent.add_child(lbl)


func _add_debug_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	var ss  := StyleBoxFlat.new()
	ss.bg_color = Color("#4a4038")
	ss.content_margin_top    = 0.5
	ss.content_margin_bottom = 0.5
	sep.add_theme_stylebox_override("separator", ss)
	parent.add_child(sep)


func _add_slider(parent: Control, label: String,
                 min_v: float, max_v: float, default: float) -> HSlider:
	_add_debug_label(parent, label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.value     = default
	slider.step      = (max_v - min_v) / 100.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size   = Vector2(200.0, 20.0)
	row.add_child(slider)

	var value_lbl := Label.new()
	value_lbl.text = "%.2f" % default
	value_lbl.custom_minimum_size = Vector2(42.0, 0.0)
	value_lbl.add_theme_font_size_override("font_size", 11)
	value_lbl.add_theme_color_override("font_color", Color("#f3e6c4"))
	row.add_child(value_lbl)

	slider.value_changed.connect(func(v: float): value_lbl.text = "%.2f" % v)

	return slider


func _add_checkbox(parent: Control, label: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label
	cb.add_theme_font_size_override("font_size", 12)
	cb.add_theme_color_override("font_color", Color("#d4c08c"))
	parent.add_child(cb)
	return cb


# ─── EVENT LOG ─────────────────────────────────────────────────────────────

func _log_event(text: String) -> void:
	var time_str: String = Time.get_time_string_from_system()
	var entry: String    = "[%s] %s" % [time_str, text]

	_log_entries.append(entry)
	if _log_entries.size() > LOG_MAX:
		_log_entries.pop_front()

	if _log_label:
		_log_label.clear()
		for e in _log_entries:
			_log_label.append_text(e + "\n")
		# Scroll to bottom.
		_log_label.scroll_to_line(_log_label.get_line_count() - 1)

	# Also route to DebugOverlay so it appears in the in-game console tab.
	DebugOverlay.log_action(text)
