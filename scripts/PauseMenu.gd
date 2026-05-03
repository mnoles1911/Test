extends CanvasLayer
# PauseMenu — Autoload. ESC key overlay during gameplay.
#
# What this does in plain English:
#   Press ESC during the game to pause everything and show a small menu:
#     RESUME  — closes the menu and unpauses
#     SAVE    — opens a dialog where Roland names the save, then writes it
#     LOAD    — opens a picker listing every save with name + time + coords
#     SETTINGS — opens the Settings screen
#     EXIT TO MENU — saves and returns to the main menu
#     QUIT    — saves and closes the application
#
# Three sub-panels live inside the same CanvasLayer:
#   1. Main pause panel   (RESUME / SAVE / LOAD / ...)
#   2. Save name dialog   (LineEdit for save name + Confirm / Cancel)
#   3. Load picker        (scrollable list of saves, Load / Delete per row)
# Only one is visible at a time. Save and Load buttons hide the main
# panel and show their respective sub-panel; Cancel returns to main.


# =============================================================
# CONSTANTS
# =============================================================

const MAIN_MENU_SCENE: String = "res://scenes/ui/MainMenu.tscn"
const SETTINGS_SCENE: String  = "res://scenes/ui/Settings.tscn"


# =============================================================
# NODE REFERENCES
# =============================================================

# Main pause panel.
var _root: Control
var _main_panel: Panel
var _resume_btn: Button
var _save_btn: Button
var _load_btn: Button
var _settings_btn: Button
var _exit_menu_btn: Button
var _quit_btn: Button

# Save name dialog.
var _save_panel: Panel
var _save_name_edit: LineEdit
var _save_confirm_btn: Button
var _save_cancel_btn: Button

# Load picker.
var _load_panel: Panel
var _load_list_container: VBoxContainer
var _load_cancel_btn: Button


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 50
	# Process always so buttons work while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_ui()
	_build_save_dialog()
	_build_load_picker()
	_root.visible = false

	print("[PauseMenu] Initialized.")


func _build_ui() -> void:
	# Top-level Control covers the screen and dims with a backdrop.
	# The three sub-panels are siblings inside this Control; only
	# one is visible at any time.
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	_root.add_child(backdrop)

	# --- Main pause panel ---
	_main_panel = Panel.new()
	_main_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_main_panel.offset_left   = -220
	_main_panel.offset_top    = -200
	_main_panel.offset_right  =  220
	_main_panel.offset_bottom =  200
	_root.add_child(_main_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  6
	vbox.offset_top    =  6
	vbox.offset_right  = -6
	vbox.offset_bottom = -6
	_main_panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "— PAUSED —"
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(0.35, 0.35, 0.35, 1)
	vbox.add_child(div)

	var make_btn := func(label: String) -> Button:
		var b := Button.new()
		b.text = label
		b.flat = true
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 22)
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		return b

	_resume_btn    = make_btn.call("RESUME")
	_save_btn      = make_btn.call("SAVE")
	_load_btn      = make_btn.call("LOAD")
	_settings_btn  = make_btn.call("SETTINGS")
	_exit_menu_btn = make_btn.call("EXIT TO MENU")
	_quit_btn      = make_btn.call("QUIT")

	for btn in [_resume_btn, _save_btn, _load_btn, _settings_btn, _exit_menu_btn, _quit_btn]:
		vbox.add_child(btn)

	_resume_btn.pressed.connect(_on_resume)
	_save_btn.pressed.connect(_on_save)
	_load_btn.pressed.connect(_on_load)
	_settings_btn.pressed.connect(_on_settings)
	_exit_menu_btn.pressed.connect(_on_exit_menu)
	_quit_btn.pressed.connect(_on_quit)


func _build_save_dialog() -> void:
	# Save name dialog — appears when SAVE is clicked. Player types
	# a name and confirms; the save writes to user://saves/{slug}.json.
	_save_panel = Panel.new()
	_save_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_save_panel.offset_left   = -260
	_save_panel.offset_top    = -120
	_save_panel.offset_right  =  260
	_save_panel.offset_bottom =  120
	_save_panel.visible = false
	_root.add_child(_save_panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left   = 12
	v.offset_top    = 12
	v.offset_right  = -12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 12)
	_save_panel.add_child(v)

	var title := Label.new()
	title.text = "— SAVE GAME —"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var prompt := Label.new()
	prompt.text = "Name this save:"
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	v.add_child(prompt)

	_save_name_edit = LineEdit.new()
	_save_name_edit.add_theme_font_size_override("font_size", 18)
	_save_name_edit.placeholder_text = "e.g. Roland Day 1"
	_save_name_edit.process_mode = Node.PROCESS_MODE_ALWAYS
	# Submit on Enter.
	_save_name_edit.text_submitted.connect(func(_text: String): _on_save_confirm())
	v.add_child(_save_name_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_row)

	_save_confirm_btn = Button.new()
	_save_confirm_btn.text = "CONFIRM"
	_save_confirm_btn.add_theme_font_size_override("font_size", 18)
	_save_confirm_btn.custom_minimum_size = Vector2(140, 40)
	_save_confirm_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_confirm_btn.pressed.connect(_on_save_confirm)
	btn_row.add_child(_save_confirm_btn)

	_save_cancel_btn = Button.new()
	_save_cancel_btn.text = "CANCEL"
	_save_cancel_btn.add_theme_font_size_override("font_size", 18)
	_save_cancel_btn.custom_minimum_size = Vector2(140, 40)
	_save_cancel_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_cancel_btn.pressed.connect(_show_main_panel)
	btn_row.add_child(_save_cancel_btn)


func _build_load_picker() -> void:
	# Load picker — appears when LOAD is clicked. Lists every save
	# with name, last-played timestamp, and the world coordinates
	# Roland was at when the save was taken.
	_load_panel = Panel.new()
	_load_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_load_panel.offset_left   = -340
	_load_panel.offset_top    = -260
	_load_panel.offset_right  =  340
	_load_panel.offset_bottom =  260
	_load_panel.visible = false
	_root.add_child(_load_panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left   = 12
	v.offset_top    = 12
	v.offset_right  = -12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 8)
	_load_panel.add_child(v)

	var title := Label.new()
	title.text = "— LOAD GAME —"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	# Scrollable list — sized to fill panel space.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	_load_list_container = VBoxContainer.new()
	_load_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_load_list_container)

	_load_cancel_btn = Button.new()
	_load_cancel_btn.text = "CANCEL"
	_load_cancel_btn.add_theme_font_size_override("font_size", 18)
	_load_cancel_btn.custom_minimum_size = Vector2(140, 40)
	_load_cancel_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_load_cancel_btn.pressed.connect(_show_main_panel)
	v.add_child(_load_cancel_btn)


func _populate_load_list() -> void:
	# Rebuild the list of save rows from disk. Called every time
	# the picker opens so deletions and new saves show up live.
	for child in _load_list_container.get_children():
		child.queue_free()

	var saves: Array = GameState.list_save_files()
	if saves.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No saves yet. Use SAVE to create one."
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_load_list_container.add_child(empty_lbl)
		return

	for meta in saves:
		_load_list_container.add_child(_make_save_row(meta))


func _make_save_row(meta: Dictionary) -> Control:
	# A single row in the load picker. Two-column layout: info (left,
	# expanding) and action buttons (right).
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 56)
	hbox.add_theme_constant_override("separation", 8)

	var pos: Vector3 = meta.get("player_position", Vector3.ZERO)

	var info_lbl := Label.new()
	info_lbl.text = "%s\n%s   X %.0f  Y %.0f  Z %.0f" % [
		meta.get("save_name", "?"),
		meta.get("timestamp", "?"),
		pos.x, pos.y, pos.z,
	]
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.add_theme_font_size_override("font_size", 14)
	info_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 1))
	hbox.add_child(info_lbl)

	var load_btn := Button.new()
	load_btn.text = "LOAD"
	load_btn.add_theme_font_size_override("font_size", 14)
	load_btn.custom_minimum_size = Vector2(80, 40)
	load_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	load_btn.pressed.connect(_on_load_select.bind(meta.get("filename", "")))
	hbox.add_child(load_btn)

	var delete_btn := Button.new()
	delete_btn.text = "DELETE"
	delete_btn.add_theme_font_size_override("font_size", 14)
	delete_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5, 1))
	delete_btn.custom_minimum_size = Vector2(80, 40)
	delete_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	delete_btn.pressed.connect(_on_load_delete.bind(meta.get("filename", "")))
	hbox.add_child(delete_btn)

	return hbox


# =============================================================
# INPUT
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			# If the journal/inventory overlay is open, let JournalUI handle
			# Escape to close itself instead of opening the pause menu on top.
			var journal := get_node_or_null("/root/JournalUI")
			if journal != null and journal.is_overlay_visible():
				return
			if _root.visible:
				# Sub-panels: Escape returns to the main pause panel,
				# not directly to gameplay. Players can re-Escape to
				# unpause from the main panel.
				if _save_panel.visible or _load_panel.visible:
					_show_main_panel()
				else:
					_on_resume()
			else:
				_open()
			get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _root != null and _root.visible


# =============================================================
# OPEN / CLOSE / SUB-PANEL SWITCHING
# =============================================================

func _open() -> void:
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Disable LOAD if there are no saves on disk.
	_load_btn.disabled = GameState.list_save_files().is_empty()
	_show_main_panel()
	print("[PauseMenu] Opened.")


func _close() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[PauseMenu] Closed.")


func _show_main_panel() -> void:
	_main_panel.visible = true
	_save_panel.visible = false
	_load_panel.visible = false


func _show_save_dialog() -> void:
	_main_panel.visible = false
	_load_panel.visible = false
	_save_panel.visible = true
	# Suggest a default name based on the current scene + timestamp
	# so the player can just hit Enter for a quick save.
	var default_name: String = "Save %s" % Time.get_datetime_string_from_system()
	_save_name_edit.text = default_name
	_save_name_edit.select_all()
	_save_name_edit.grab_focus()


func _show_load_picker() -> void:
	_main_panel.visible = false
	_save_panel.visible = false
	_load_panel.visible = true
	_populate_load_list()


# =============================================================
# BUTTON HANDLERS — main panel
# =============================================================

func _on_resume() -> void:
	_close()


func _on_save() -> void:
	_show_save_dialog()


func _on_load() -> void:
	_show_load_picker()


func _on_settings() -> void:
	_close()
	TransitionManager.change_scene(SETTINGS_SCENE, "", TransitionManager.Type.CUT)


func _on_exit_menu() -> void:
	# Auto-save with a default name so progress isn't silently lost
	# on exit. Players who want a named save should use SAVE first.
	GameState.save_game("Auto-save on exit")
	_close()
	TransitionManager.change_scene(MAIN_MENU_SCENE, "", TransitionManager.Type.FADE_BLACK)


func _on_quit() -> void:
	GameState.save_game("Auto-save on quit")
	get_tree().quit()


# =============================================================
# BUTTON HANDLERS — save dialog
# =============================================================

func _on_save_confirm() -> void:
	var name_input: String = _save_name_edit.text.strip_edges()
	if name_input == "":
		# Empty → fall back to a timestamp default; save_game()
		# applies the same default when called with an empty string.
		name_input = ""
	if GameState.save_game(name_input):
		# Successful save returns to the main pause panel so the
		# player sees the SAVE notification + confirmation that
		# nothing else broke.
		_show_main_panel()
		# Re-enable the LOAD button now that there's at least one save.
		_load_btn.disabled = false


# =============================================================
# BUTTON HANDLERS — load picker
# =============================================================

func _on_load_select(filename: String) -> void:
	if filename == "":
		return
	if not GameState.load_save_file(filename):
		print("[PauseMenu] Load failed for: %s" % filename)
		return
	_close()
	var scene: String = GameState.current_scene
	if scene == "" or not ResourceLoader.exists(scene):
		scene = "res://scenes/World3D.tscn"
	TransitionManager.change_scene(scene, GameState.player_spawn_id)


func _on_load_delete(filename: String) -> void:
	if filename == "":
		return
	GameState.delete_save_file(filename)
	# Refresh the picker in place so the deleted row disappears.
	_populate_load_list()
	# Disable LOAD on the main panel if the last save was deleted.
	_load_btn.disabled = GameState.list_save_files().is_empty()
