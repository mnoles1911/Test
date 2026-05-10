extends Control
# SaveSlotPicker — legacy stand-alone scene for selecting saves.
#
# The PauseMenu now hosts the canonical save dialog and load picker
# (built inline in scripts/PauseMenu.gd). This stand-alone scene is
# retained for the MainMenu / dedicated save-screen workflow but
# refactored to use the new named-save API rather than the old
# 3-slot system.
#
# What this does in plain English:
#   On enter, lists every save file in user://saves/. The player
#   picks one to load. (Save-naming uses PauseMenu's inline dialog
#   and is not exposed here any more — naming a save inline at
#   the moment of saving is more discoverable than a separate
#   save-mode screen.)
#
# Usage:
#   TransitionManager.change_scene("res://scenes/ui/SaveSlotPicker.tscn", ...)


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
	header_label.text = "LOAD GAME"
	# Scene targets a 320x180 viewport — keep font sizes small to fit
	# the existing layout. apply_title_label sets serif + gold colour;
	# the 12 here override its default 36.
	UIStyles.apply_title_label(header_label, 12)
	UIStyles.apply_menu_button(back_btn)
	back_btn.add_theme_font_size_override("font_size", 8)
	_build_save_rows()
	print("[SaveSlotPicker] Ready (named-save mode).")


func _build_save_rows() -> void:
	# Remove any existing children.
	for child in slot_rows.get_children():
		child.queue_free()

	var saves: Array = GameState.list_save_files()
	if saves.is_empty():
		var lbl := Label.new()
		lbl.text = "No saves found."
		UIStyles.apply_muted_label(lbl, 16)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_rows.add_child(lbl)
		return

	for save_meta in saves:
		var row := _make_save_row(save_meta)
		slot_rows.add_child(row)


func _make_save_row(meta: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 32)

	# Save info: name + timestamp + coords.
	var info_lbl := Label.new()
	var pos: Vector3 = meta.get("player_position", Vector3.ZERO)
	info_lbl.text = "%s\n%s    (%.0f, %.0f, %.0f)" % [
		meta.get("save_name", "?"),
		meta.get("timestamp", "?"),
		pos.x, pos.y, pos.z,
	]
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyles.apply_body_label(info_lbl, 12)
	hbox.add_child(info_lbl)

	# Load button.
	var btn := Button.new()
	btn.text = "LOAD"
	btn.custom_minimum_size = Vector2(60, 18)
	UIStyles.apply_menu_button(btn)
	btn.add_theme_font_size_override("font_size", 8)
	btn.pressed.connect(_on_save_pressed.bind(meta.get("filename", "")))
	hbox.add_child(btn)

	return hbox


# =============================================================
# HANDLERS
# =============================================================

func _on_save_pressed(filename: String) -> void:
	if filename == "":
		return
	if not GameState.load_save_file(filename):
		return
	var scene: String = GameState.current_scene
	if scene == "" or not ResourceLoader.exists(scene):
		scene = "res://scenes/World3D.tscn"
	TransitionManager.change_scene(scene, GameState.player_spawn_id)


func _on_back() -> void:
	TransitionManager.go_back()
