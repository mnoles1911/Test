extends Control
# Settings — the settings screen.
#
# What this does in plain English:
#   Shows adjustable options: master volume, music volume, SFX volume,
#   fullscreen toggle, and a keybindings section (stub for now).
#   Settings are saved to user://settings.json on Apply and loaded on _ready.
#
# Called from: MainMenu._on_settings() and PauseMenu._on_settings()
# Back navigation:
#   - Opened from MainMenu  → Back / ESC returns to MainMenu
#   - Opened from PauseMenu → Back / ESC returns to game + reopens PauseMenu
#
# Why _input instead of Button.pressed signals:
#   Dialogic's input subsystem consumes LMB events before Godot's GUI
#   dispatcher runs, so _gui_input never fires on Button or HSlider.
#   Both MainMenu and PauseMenu work around this the same way: manual
#   hit-detection in _input(). We do the same here.


# =============================================================
# CONSTANTS
# =============================================================

const SETTINGS_PATH: String = "user://settings.json"


# =============================================================
# NODE REFERENCES
# =============================================================

@onready var master_slider: HSlider     = $VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider      = $VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider        = $VBox/SFXRow/SFXSlider
@onready var fullscreen_check: CheckBox = $VBox/FullscreenCheck
@onready var back_btn: Button           = $VBox/ButtonRow/BackBtn
@onready var apply_btn: Button          = $VBox/ButtonRow/ApplyBtn


# =============================================================
# STATE
# =============================================================

# Slider currently being dragged (null when nothing is being dragged).
var _drag_slider: HSlider = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Must process even if a parent paused the tree (e.g. leftover
	# pause state from PauseMenu before the scene change completed).
	process_mode = Node.PROCESS_MODE_ALWAYS

	# PauseMenu._close() sets mouse to CAPTURED before transitioning
	# here. Sliders and buttons are unclickable with a captured mouse,
	# so force it visible as soon as Settings loads.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_load_settings()
	_apply_to_audio()

	print("[Settings] Ready.")


# =============================================================
# INPUT — manual dispatch (mirrors PauseMenu._input pattern)
# =============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_lmb_press(mb.position)
			else:
				_drag_slider = null

	elif event is InputEventMouseMotion:
		if _drag_slider != null:
			_update_slider_drag((event as InputEventMouseMotion).global_position)


func _unhandled_input(event: InputEvent) -> void:
	# ESC anywhere on the settings screen → same as clicking Back.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			_on_back()
			get_viewport().set_input_as_handled()


func _on_lmb_press(pos: Vector2) -> void:
	# Check each slider first — press starts a drag.
	for s in [master_slider, music_slider, sfx_slider]:
		var slider := s as HSlider
		if slider.get_global_rect().has_point(pos):
			_drag_slider = slider
			_set_slider_from_pos(slider, pos)
			return

	# Buttons.
	if back_btn.get_global_rect().has_point(pos):
		_on_back()
		return
	if apply_btn.get_global_rect().has_point(pos):
		_on_apply()
		return

	# Fullscreen checkbox — toggle on click anywhere in its rect.
	if fullscreen_check.get_global_rect().has_point(pos):
		fullscreen_check.button_pressed = not fullscreen_check.button_pressed
		_on_fullscreen_toggled(fullscreen_check.button_pressed)
		return


func _update_slider_drag(global_pos: Vector2) -> void:
	if _drag_slider == null:
		return
	_set_slider_from_pos(_drag_slider, global_pos)


func _set_slider_from_pos(slider: HSlider, global_pos: Vector2) -> void:
	# Map the mouse X position within the slider's screen rect to a
	# value in [min_value, max_value].
	var rect: Rect2 = slider.get_global_rect()
	var t: float = clamp((global_pos.x - rect.position.x) / rect.size.x, 0.0, 1.0)
	slider.value = lerp(slider.min_value, slider.max_value, t)


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_back() -> void:
	_save_settings()
	# If the previous scene was the gameplay world (opened from PauseMenu),
	# ask PauseMenu to reopen itself once the world scene finishes loading.
	if _prev_scene_is_gameplay():
		var pause_menu: Node = get_node_or_null("/root/PauseMenu")
		if pause_menu != null and pause_menu.has_method("request_reopen"):
			pause_menu.request_reopen()
	TransitionManager.go_back()


func _on_apply() -> void:
	_apply_to_audio()
	_save_settings()


func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# =============================================================
# CONTEXT HELPERS
# =============================================================

func _prev_scene_is_gameplay() -> bool:
	# Returns true when Settings was opened from the PauseMenu (i.e. the
	# scene we'd return to is a world/gameplay scene, not a menu scene).
	var prev: String = TransitionManager.peek_back()
	# Heuristic: menu scenes live in scenes/ui/, gameplay scenes don't.
	# Adjust this if a menu scene ever lives outside scenes/ui/.
	return prev != "" and ("ui/" not in prev) and ("MainMenu" not in prev)


# =============================================================
# AUDIO APPLICATION
# =============================================================

func _apply_to_audio() -> void:
	# Godot uses a logarithmic bus volume system. linear_to_db() converts
	# a 0.0–1.0 slider value to the correct decibel value for the audio bus.
	var master_idx: int = AudioServer.get_bus_index("Master")
	var music_idx: int  = AudioServer.get_bus_index("Music")
	var sfx_idx: int    = AudioServer.get_bus_index("SFX")

	AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_slider.value))
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_slider.value))
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_slider.value))


# =============================================================
# PERSIST
# =============================================================

func _save_settings() -> void:
	var data: Dictionary = {
		"master_volume": master_slider.value,
		"music_volume":  music_slider.value,
		"sfx_volume":    sfx_slider.value,
		"fullscreen":    fullscreen_check.button_pressed,
	}
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[Settings] Saved.")


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		master_slider.value = 0.8
		music_slider.value  = 0.7
		sfx_slider.value    = 1.0
		fullscreen_check.button_pressed = false
		return

	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if result == null:
		return

	master_slider.value = result.get("master_volume", 0.8)
	music_slider.value  = result.get("music_volume",  0.7)
	sfx_slider.value    = result.get("sfx_volume",    1.0)
	fullscreen_check.button_pressed = result.get("fullscreen", false)

	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
