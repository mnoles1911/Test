extends Control
# Settings — the settings screen.
#
# What this does in plain English:
#   Shows adjustable options: master volume, music volume, SFX volume,
#   fullscreen toggle, and a keybindings section (stub for now).
#   Settings are saved to user://settings.json on Apply and loaded on _ready.
#
# Called from: MainMenu._on_settings() and PauseMenu._on_settings()
# Back navigation: the Back button returns to whoever called this.
#   TransitionManager.go_back() handles this automatically.


# =============================================================
# CONSTANTS
# =============================================================

const SETTINGS_PATH: String = "user://settings.json"


# =============================================================
# NODE REFERENCES
# =============================================================

@onready var master_slider: HSlider    = $VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider     = $VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider       = $VBox/SFXRow/SFXSlider
@onready var fullscreen_check: CheckBox = $VBox/FullscreenCheck
@onready var back_btn: Button          = $VBox/ButtonRow/BackBtn
@onready var apply_btn: Button         = $VBox/ButtonRow/ApplyBtn


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	apply_btn.pressed.connect(_on_apply)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	_load_settings()
	_apply_to_audio()

	print("[Settings] Ready.")


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_back() -> void:
	_save_settings()
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
		# First run — apply sensible defaults.
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

	# Apply fullscreen state on load.
	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
