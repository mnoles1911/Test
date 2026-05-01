extends CanvasLayer
# PauseMenu — Autoload. ESC key overlay during gameplay.
#
# What this does in plain English:
#   Press ESC during the game to pause everything and show a small menu:
#     RESUME — closes the menu and unpauses
#     SAVE   — saves immediately (shows the SaveNotification toast)
#     LOAD   — reloads the last save
#     SETTINGS — opens the Settings screen
#     EXIT TO MENU — saves and returns to the main menu
#     QUIT   — saves and closes the application
#
# This is an Autoload so it's always available regardless of the current scene.
# It uses get_tree().paused = true to freeze all game nodes while the menu
# is visible. The CanvasLayer itself has process_mode = ALWAYS so it keeps
# running while the game is paused.
#
# The journal (J) also pauses the game in a similar way. They don't
# conflict because _unhandled_input() checks visibility: only the
# visible overlay handles ESC/J.


# =============================================================
# CONSTANTS
# =============================================================

const MAIN_MENU_SCENE: String = "res://scenes/ui/MainMenu.tscn"
const SETTINGS_SCENE: String  = "res://scenes/ui/Settings.tscn"


# =============================================================
# NODE REFERENCES
# =============================================================

var _root: Control
var _resume_btn: Button
var _save_btn: Button
var _load_btn: Button
var _settings_btn: Button
var _exit_menu_btn: Button
var _quit_btn: Button


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 50
	# Process always so buttons work while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_ui()
	_root.visible = false

	print("[PauseMenu] Initialized.")


func _build_ui() -> void:
	# Build the pause menu programmatically so no .tscn is needed for an Autoload.

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	# Dark backdrop.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	_root.add_child(backdrop)

	# Centered panel.
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left   = -60
	frame.offset_top    = -55
	frame.offset_right  =  60
	frame.offset_bottom =  55
	_root.add_child(frame)

	# VBox inside the panel.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  6
	vbox.offset_top    =  6
	vbox.offset_right  = -6
	vbox.offset_bottom = -6
	frame.add_child(vbox)

	# Title.
	var title_lbl := Label.new()
	title_lbl.text = "— PAUSED —"
	title_lbl.add_theme_font_size_override("font_size", 8)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	# Divider.
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(0.35, 0.35, 0.35, 1)
	vbox.add_child(div)

	# Helper to create a flat button.
	var make_btn := func(label: String) -> Button:
		var b := Button.new()
		b.text = label
		b.flat = true
		b.custom_minimum_size = Vector2(0, 14)
		b.add_theme_font_size_override("font_size", 7)
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

	# Connect handlers.
	_resume_btn.pressed.connect(_on_resume)
	_save_btn.pressed.connect(_on_save)
	_load_btn.pressed.connect(_on_load)
	_settings_btn.pressed.connect(_on_settings)
	_exit_menu_btn.pressed.connect(_on_exit_menu)
	_quit_btn.pressed.connect(_on_quit)


# =============================================================
# INPUT
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			if _root.visible:
				_on_resume()
			else:
				_open()
			get_viewport().set_input_as_handled()


# =============================================================
# OPEN / CLOSE
# =============================================================

func _open() -> void:
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_load_btn.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)
	print("[PauseMenu] Opened.")

func _close() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[PauseMenu] Closed.")


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_resume() -> void:
	_close()

func _on_save() -> void:
	GameState.save_game()

func _on_load() -> void:
	_close()
	GameState.load_game()
	var scene: String = GameState.current_scene
	if scene == "" or not ResourceLoader.exists(scene):
		scene = "res://scenes/World3D.tscn"
	TransitionManager.change_scene(scene, GameState.player_spawn_id)

func _on_settings() -> void:
	_close()
	TransitionManager.change_scene(SETTINGS_SCENE, "", TransitionManager.Type.CUT)

func _on_exit_menu() -> void:
	GameState.save_game()
	_close()
	TransitionManager.change_scene(MAIN_MENU_SCENE, "", TransitionManager.Type.FADE_BLACK)

func _on_quit() -> void:
	GameState.save_game()
	get_tree().quit()
