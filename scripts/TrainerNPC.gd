extends NPC
class_name TrainerNPC

# Extends NPC to add a gold-for-skill-levels training UI. Activated
# when service_type == "TRAINER" in the NPCData resource. Press E
# while in interact range to open the training modal.
#
# Gating:
#   - FactionManager.is_friendly(npc_data.faction) must be true
#     (disposition >= 75). Otherwise the trainer refuses with a bark.
#   - Per-Act per-skill per-trainer cap from npc_data.max_levels_per_act.
#   - Gold cost = npc_data.gold_per_level * current_level_in_skill.
#     (Scales the price with the player's current level so reaching
#     L80 costs much more than L20.)

const REFUSAL_LINE: String = "I don't teach strangers."
const CAP_LINE: String = "You have learned all I can teach you this season."
const TRAINING_DONE_LINE: String = "Good. Practice what you've learned."

var _modal: CanvasLayer = null
var _modal_root: Control = null

func _start_dialogue() -> void:
	# Trainers bypass the generic Dialogic flow.
	if npc_data == null:
		return
	if String(npc_data.service_type) != "TRAINER":
		# Fall back to base behavior for non-trainer NPCs that share
		# this script for any reason.
		super._start_dialogue()
		return
	if not FactionManager.is_friendly(String(npc_data.faction)):
		_say_refusal()
		return
	_open_training_modal()


func _say_refusal() -> void:
	# Bark-channel refusal — no full dialogue UI. Print as a fallback if
	# BarkManager isn't loaded.
	if get_node_or_null("/root/BarkManager"):
		BarkManager.fire(npc_data.npc_id, "TRAINER_REFUSE", global_position)
	else:
		print("[Trainer:%s] %s" % [npc_data.npc_id, REFUSAL_LINE])


# =============================================================
# Training modal (programmatic)
# =============================================================

func _open_training_modal() -> void:
	if _modal != null and is_instance_valid(_modal):
		_close_training_modal()
	_modal = CanvasLayer.new()
	_modal.layer = 11   # one above JournalUI (10)
	get_tree().get_root().add_child(_modal)
	_modal.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.65)
	_modal.add_child(backdrop)

	_modal_root = Panel.new()
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_modal_root.custom_minimum_size = Vector2(640, 480)
	_modal_root.offset_left   = -320
	_modal_root.offset_top    = -240
	_modal_root.offset_right  =  320
	_modal_root.offset_bottom =  240
	_modal_root.add_theme_stylebox_override("panel", UIStyles.menu_body_panel())
	_modal.add_child(_modal_root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 20
	vbox.offset_top    = 16
	vbox.offset_right  = -20
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 8)
	_modal_root.add_child(vbox)

	var title := Label.new()
	title.text = "%s — Training" % npc_data.display_name
	UIStyles.apply_title_label(title, 24)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Faction: %s   |   Disposition: %s (%d)   |   Your gold: %d" % [
		String(npc_data.faction).capitalize(),
		FactionManager.disposition_label(FactionManager.get_disposition(String(npc_data.faction))),
		FactionManager.get_disposition(String(npc_data.faction)),
		InventoryManager.get_gold() if InventoryManager.has_method("get_gold") else 0,
	]
	UIStyles.apply_muted_label(sub, 14)
	vbox.add_child(sub)

	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 2)
	div.color = Colors.PANEL_OAK_EDGE
	vbox.add_child(div)

	for skill in npc_data.skills_taught:
		vbox.add_child(_build_skill_row(String(skill)))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var close := Button.new()
	close.text = "Leave"
	close.custom_minimum_size = Vector2(0, 36)
	close.focus_mode = Control.FOCUS_NONE
	UIStyles.apply_menu_button(close)
	close.pressed.connect(_close_training_modal)
	vbox.add_child(close)


func _build_skill_row(skill: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var current_level: int = SkillManager.get_level(skill)
	var visits_this_act: int = GameState.get_trainer_visits(npc_data.npc_id, skill)
	var visits_remaining: int = max(0, npc_data.max_levels_per_act - visits_this_act)
	var cost: int = _compute_cost(skill)

	var lbl := Label.new()
	lbl.text = "%s   L%d   (this season: %d / %d)" % [
		skill.capitalize(), current_level, visits_this_act, npc_data.max_levels_per_act,
	]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyles.apply_body_label(lbl, 15)
	row.add_child(lbl)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 32)
	btn.focus_mode = Control.FOCUS_NONE
	UIStyles.apply_menu_button(btn)
	if current_level >= SkillCurve.MAX_LEVEL:
		btn.text = "At cap"
		btn.disabled = true
	elif visits_remaining <= 0:
		btn.text = "Cap reached"
		btn.disabled = true
	elif not _player_has_gold(cost):
		btn.text = "Need %d gold" % cost
		btn.disabled = true
	else:
		btn.text = "Train (%d gold)" % cost
		btn.pressed.connect(_on_train_pressed.bind(skill))
	row.add_child(btn)
	return row


func _on_train_pressed(skill: String) -> void:
	var cost: int = _compute_cost(skill)
	if not _spend_gold(cost):
		return
	# Grant just enough XP to push the player to the next level.
	var current: int = SkillManager.get_level(skill)
	var to_next: float = SkillCurve.xp_to_next_level(current)
	var progress: float = SkillManager.get_xp_progress(skill)
	var needed: float = max(to_next - progress, 1.0)
	SkillManager.add_xp(skill, needed)
	GameState.increment_trainer_visits(npc_data.npc_id, skill)
	if get_node_or_null("/root/BarkManager"):
		BarkManager.fire(npc_data.npc_id, "TRAINER_DONE", global_position)
	else:
		print("[Trainer:%s] %s" % [npc_data.npc_id, TRAINING_DONE_LINE])
	# Rebuild the modal so cost/cap/gold all refresh.
	_close_training_modal()
	_open_training_modal()


func _close_training_modal() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_modal_root = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =============================================================
# Cost + gold helpers (defensive — InventoryManager gold API
# may not exist yet)
# =============================================================

func _compute_cost(skill: String) -> int:
	var level: int = SkillManager.get_level(skill)
	# Base cost * (1 + level / 10): L1 = 1.1x, L50 = 6x, L99 = 10.9x.
	return int(npc_data.gold_per_level * (1.0 + float(level) / 10.0))


func _player_has_gold(cost: int) -> bool:
	if not get_node_or_null("/root/InventoryManager"):
		return false
	if InventoryManager.has_method("get_gold"):
		return int(InventoryManager.call("get_gold")) >= cost
	# Fallback: count "gold" items in inventory.
	if InventoryManager.has_method("count_item"):
		return int(InventoryManager.call("count_item", "gold")) >= cost
	return cost <= 0


func _spend_gold(cost: int) -> bool:
	if not _player_has_gold(cost):
		return false
	if InventoryManager.has_method("spend_gold"):
		return bool(InventoryManager.call("spend_gold", cost))
	if InventoryManager.has_method("remove_item"):
		return bool(InventoryManager.call("remove_item", "gold", cost))
	# Last-resort silent permit so the system stays usable even if
	# InventoryManager hasn't been wired with a gold API.
	push_warning("[TrainerNPC] No gold API on InventoryManager; training granted free.")
	return true
