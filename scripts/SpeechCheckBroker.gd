extends Node

# Autoload. Presents a Speech-check choice modal in the KCD2 style:
# both options visible at all times, but the option that fails the DC
# is greyed and prefixed [Speech N]. Clicking either resolves
# immediately and emits resolved(success).
#
# Two entry points:
#
#   1. Direct call from gameplay code (TrainerNPC dialogue, e.g.):
#        SpeechCheckBroker.present(40, "Convinced", "Refused")
#        var ok = await SpeechCheckBroker.resolved
#
#   2. From a Dialogic timeline via a Signal event with argument
#      formatted as "speech_check:DC:success_branch:fail_branch", where
#      success_branch/fail_branch are Dialogic timeline names. The
#      broker hooks Dialogic.signal_event in _ready and routes
#      automatically.
#
# Authoring conventions: see dialogue/STYLE.md "Speech checks".

const SUCCESS_PREFIX_GOLD: String = "[Speech %d ✓]  "
const FAIL_PREFIX_GREY: String =    "[Speech %d ✗]  "

signal resolved(success: bool, dc: int)

var _modal: CanvasLayer = null

func _ready() -> void:
	# Bind Dialogic signal events. The signal_event is fired when a
	# Dialogic timeline reaches a [signal] node — we listen for the
	# "speech_check:DC:success_timeline:fail_timeline" convention.
	if get_node_or_null("/root/Dialogic") and Dialogic.has_signal("signal_event"):
		Dialogic.signal_event.connect(_on_dialogic_signal)

func _on_dialogic_signal(argument: Variant) -> void:
	var arg: String = String(argument)
	if not arg.begins_with("speech_check:"):
		return
	var parts: PackedStringArray = arg.split(":")
	if parts.size() < 4:
		push_warning("[SpeechCheckBroker] Malformed signal arg: %s" % arg)
		return
	var dc: int = int(parts[1])
	var success_branch: String = parts[2]
	var fail_branch: String = parts[3]
	# Pause any auto-advance so the modal is exclusive.
	present(dc, "Persuade", "Refuse", true)
	var ok: bool = await resolved
	# Route to the right follow-up timeline.
	if not get_node_or_null("/root/Dialogic"):
		return
	if ok:
		Dialogic.start(success_branch)
	else:
		Dialogic.start(fail_branch)

# =============================================================
# Public API
# =============================================================

func present(dc: int, success_label: String = "Convince", fail_label: String = "Back down", locked_visible: bool = true) -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = CanvasLayer.new()
	_modal.layer = 12
	_modal.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().get_root().add_child(_modal)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.6)
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	_modal.add_child(backdrop)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 220)
	panel.offset_left = -260
	panel.offset_top = -110
	panel.offset_right = 260
	panel.offset_bottom = 110
	panel.add_theme_stylebox_override("panel", UIStyles.menu_body_panel())
	_modal.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18
	vbox.offset_top = 14
	vbox.offset_right = -18
	vbox.offset_bottom = -14
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var speech_level: int = SkillManager.get_level("speech")
	# Oratorical perk lets persuasion succeed at DC 5 above your Speech.
	# The cushion is queried via PerkQuery so any future perks adding to
	# dc_cushion (e.g. faction-specific bonuses) stack automatically.
	var cushion: int = int(PerkQuery.sum("dc_cushion", "speech", {"passive": true}))
	var effective_level: int = speech_level + cushion
	var passes: bool = effective_level >= dc

	var title := Label.new()
	title.text = "Speech Check"
	UIStyles.apply_title_label(title, 22)
	vbox.add_child(title)

	var sub := Label.new()
	var cushion_note: String = "" if cushion == 0 else "  (+%d perk)" % cushion
	sub.text = "Your Speech: %d%s   |   Required: %d   |   %s" % [
		speech_level, cushion_note, dc, "PASS" if passes else "FAIL",
	]
	UIStyles.apply_muted_label(sub, 14)
	vbox.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# SUCCESS option — clickable if passes, else greyed (still visible
	# unless locked_visible=false, in which case we hide it entirely).
	var success_btn := Button.new()
	success_btn.custom_minimum_size = Vector2(0, 40)
	success_btn.focus_mode = Control.FOCUS_NONE
	if passes:
		success_btn.text = (SUCCESS_PREFIX_GOLD % dc) + success_label
		success_btn.pressed.connect(_on_resolve.bind(true, dc))
	elif locked_visible:
		success_btn.text = (FAIL_PREFIX_GREY % dc) + success_label
		success_btn.disabled = true
	UIStyles.apply_menu_button(success_btn)
	if passes or locked_visible:
		vbox.add_child(success_btn)

	# FAIL option — always available.
	var fail_btn := Button.new()
	fail_btn.text = fail_label
	fail_btn.custom_minimum_size = Vector2(0, 36)
	fail_btn.focus_mode = Control.FOCUS_NONE
	UIStyles.apply_menu_button(fail_btn)
	fail_btn.pressed.connect(_on_resolve.bind(false, dc))
	vbox.add_child(fail_btn)


func _on_resolve(success: bool, dc: int) -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if success:
		# XP scales with DC: 20 * (dc/10). DC 40 -> 80 XP. DC 80 -> 160 XP.
		SkillManager.add_xp("speech", 20.0 * float(dc) / 10.0)
	resolved.emit(success, dc)
