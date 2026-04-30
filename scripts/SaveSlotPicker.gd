extends Control
# SaveSlotPicker — shown when the player manually saves or loads.
#
# What this does in plain English:
#   Displays three save slots with their timestamps and current location.
#   The player clicks a slot to save into it or load from it.
#   The mode (SAVE vs LOAD) is set before this scene is shown via GameState flag
#   or by passing a signal/mode — here we use a simple exported var.
#
# Usage from PauseMenu or MainMenu:
#   GameState.set_flag("slot_picker_mode", "save")  ← or "load"
#   TransitionManager.change_scene("res://scenes/ui/SaveSlotPicker.tscn", "", TransitionManager.Type.CUT)


# =============================================================
# NODE REFERENCES
# =============================================================

@onready var header_label: Label = $VBox/Header
@onready var back_btn: Button    = $VBox/BackBtn
@onready var slot_rows: VBoxContainer = $VBox/SlotRows


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	back_btn.pressed.connect(_on_back)

	var mode: String = GameState.get_flag("slot_picker_mode", "save")
	header_label.text = "— SAVE GAME —" if mode == "save" else "— LOAD GAME —"

	_build_slot_rows(mode)

	print("[SaveSlotPicker] Ready in mode: %s" % mode)


func _build_slot_rows(mode: String) -> void:
	# Remove any existing children.
	for child in slot_rows.get_children():
		child.queue_free()

	for i in range(GameState.SAVE_SLOT_COUNT):
		var info: Dictionary = GameState.get_slot_info(i)
		var row := _make_slot_row(i, info, mode)
		slot_rows.add_child(row)


func _make_slot_row(slot: int, info: Dictionary, mode: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 22)

	# Slot number label.
	var num_lbl := Label.new()
	num_lbl.text = "SLOT %d" % (slot + 1)
	num_lbl.custom_minimum_size = Vector2(40, 0)
	num_lbl.theme_override_font_sizes/font_size = 7
	num_lbl.theme_override_colors/font_color = Color(0.6, 0.6, 0.6, 1)
	hbox.add_child(num_lbl)

	# Info label (timestamp + scene or "Empty").
	var info_lbl := Label.new()
	if info.get("exists", false):
		var scene_short: String = info.get("current_scene", "").get_file().get_basename()
		info_lbl.text = "%s\n%s" % [info.get("timestamp", "?"), scene_short]
	else:
		info_lbl.text = "Empty"
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.theme_override_font_sizes/font_size = 6
	info_lbl.theme_override_colors/font_color = Color(0.75, 0.72, 0.65, 1)
	hbox.add_child(info_lbl)

	# Action button.
	var btn := Button.new()
	btn.text = "SAVE" if mode == "save" else "LOAD"
	btn.flat = true
	btn.custom_minimum_size = Vector2(36, 0)
	btn.theme_override_font_sizes/font_size = 7
	if mode == "load" and not info.get("exists", false):
		btn.disabled = true
	btn.pressed.connect(_on_slot_pressed.bind(slot, mode))
	hbox.add_child(btn)

	return hbox


# =============================================================
# HANDLERS
# =============================================================

func _on_slot_pressed(slot: int, mode: String) -> void:
	if mode == "save":
		GameState.active_save_slot = slot
		GameState.save_game(slot)
		TransitionManager.go_back()
	else:
		GameState.load_game(slot)
		var scene: String = GameState.current_scene
		if scene == "" or not ResourceLoader.exists(scene):
			scene = "res://scenes/World.tscn"
		TransitionManager.change_scene(scene, GameState.player_spawn_id)

func _on_back() -> void:
	TransitionManager.go_back()
