extends CanvasLayer
# Settings — persistent overlay for audio/display settings.
#
# What this does in plain English:
#   An always-present CanvasLayer (autoload, layer 60) that overlays whatever
#   scene is currently running. Showing settings does NOT replace the current
#   scene, so MainMenu music keeps playing while settings are open.
#
#   Both MainMenu and PauseMenu call Settings.open() on the same single
#   instance — there is only one Settings in the whole game.
#
#   open(from_gameplay)  — show the overlay.
#     Pass true when opened from PauseMenu so closing it re-opens PauseMenu.
#     Pass false (or omit) when opened from MainMenu.
#   close()              — save settings, hide the overlay, re-open PauseMenu
#                          if from_gameplay was true.
#
# Button layout:
#   APPLY          — applies audio changes immediately without closing
#   SAVE & LEAVE   — saves all settings and closes the overlay
#   ESC            — same as SAVE & LEAVE
#
# Why _input instead of Button.pressed signals:
#   Dialogic's input subsystem consumes LMB events before Godot's GUI
#   dispatcher runs, so _gui_input never fires on Button or HSlider.
#   MainMenu, PauseMenu, and DebugOverlay all work around this the same
#   way: manual hit-detection in _input().
#
# Why _content_root.visible instead of CanvasLayer.visible:
#   CanvasLayer.visible = false suppresses rendering but Control nodes inside
#   still absorb mouse events (their input filter is independent of the
#   CanvasLayer's render visibility). This is the same pattern PauseMenu uses:
#   the CanvasLayer is always present, the content Control is hidden/shown.


# =============================================================
# CONSTANTS
# =============================================================

const SETTINGS_PATH: String = "user://settings.json"


# =============================================================
# NODE REFERENCES
# =============================================================

# The root Control that wraps all visible content. We show/hide THIS
# rather than the CanvasLayer itself so that mouse-event blocking is tied
# to actual visual visibility. (CanvasLayer.visible only affects rendering.)
@onready var _content_root: Control        = $Root

@onready var master_slider: HSlider        = $Root/VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider         = $Root/VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider           = $Root/VBox/SFXRow/SFXSlider
@onready var fullscreen_check: CheckBox    = $Root/VBox/FullscreenCheck
@onready var mining_anchor_btn: Button     = $Root/VBox/MiningAnchorRow/MiningAnchorBtn
@onready var back_btn: Button              = $Root/VBox/ButtonRow/BackBtn
@onready var apply_btn: Button             = $Root/VBox/ButtonRow/ApplyBtn


# Mining-volume anchor preference. Read by EditToolHandler.
# Mirror of EditToolHandler.MiningAnchor enum:
#   0 = DEPTH_BIASED — bias the carve box INTO the terrain along the
#       surface normal (default). 3×3×3 against a wall = 27 terrain
#       voxels, no air slab. Matches Minecraft / Vintage Story
#       conventions.
#   1 = CENTERED — symmetric box centred on the aim voxel. The
#       carve includes one slab of air on flat surfaces but the
#       aim point sits in the middle of the box for predictable
#       precision work.
const MINING_ANCHOR_DEPTH_BIASED: int = 0
const MINING_ANCHOR_CENTERED: int = 1
var mining_volume_anchor: int = MINING_ANCHOR_DEPTH_BIASED


# =============================================================
# STATE
# =============================================================

# True when opened via PauseMenu; close() will reopen PauseMenu when done.
var _from_gameplay: bool = false

# Slider currently being dragged (null when nothing is being dragged).
var _drag_slider: HSlider = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Always process so sliders/buttons work even while the game tree is
	# paused (PauseMenu sets paused=true before opening us).
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Start hidden. We hide _content_root (the child Control), not the
	# CanvasLayer itself, because CanvasLayer.visible only controls rendering
	# — the Controls inside would still block mouse events while "invisible".
	_content_root.visible = false

	# Apply saved settings immediately so the audio buses are at the right
	# volume before any scene plays audio.
	_load_settings()
	_apply_to_audio()
	_refresh_mining_anchor_button()

	print("[Settings] Initialized (overlay mode).")


# =============================================================
# PUBLIC API
# =============================================================

## Returns true when the settings overlay is currently visible.
func is_open() -> bool:
	return _content_root.visible


## Show the settings overlay.
## from_gameplay = true  → was opened from PauseMenu (close() will reopen it).
## from_gameplay = false → was opened from MainMenu.
func open(from_gameplay: bool = false) -> void:
	_from_gameplay = from_gameplay
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_content_root.visible = true
	print("[Settings] Opened (from_gameplay=%s)." % from_gameplay)


## Save settings and hide the overlay.
## If opened from PauseMenu, re-opens PauseMenu afterwards.
func close() -> void:
	_save_settings()
	_content_root.visible = false
	if _from_gameplay:
		var pause_menu := get_node_or_null("/root/PauseMenu")
		if pause_menu != null:
			pause_menu.call("reopen_after_settings")
	print("[Settings] Closed.")


# =============================================================
# INPUT — manual dispatch (mirrors MainMenu / PauseMenu pattern)
# =============================================================

func _input(event: InputEvent) -> void:
	if not _content_root.visible:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_lmb_press(mb.position)
				get_viewport().set_input_as_handled()
			else:
				_drag_slider = null

	elif event is InputEventMouseMotion:
		if _drag_slider != null:
			_update_slider_drag((event as InputEventMouseMotion).global_position)


func _unhandled_input(event: InputEvent) -> void:
	# ESC anywhere in settings → same as clicking SAVE & LEAVE.
	if not _content_root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


func _on_lmb_press(pos: Vector2) -> void:
	# Check sliders first — a press on a slider starts a drag.
	for s in [master_slider, music_slider, sfx_slider]:
		var slider := s as HSlider
		if slider.get_global_rect().has_point(pos):
			_drag_slider = slider
			_set_slider_from_pos(slider, pos)
			return

	# SAVE & LEAVE button.
	if back_btn.get_global_rect().has_point(pos):
		close()
		return

	# APPLY button.
	if apply_btn.get_global_rect().has_point(pos):
		_on_apply()
		return

	# Fullscreen checkbox — toggle on click anywhere in its rect.
	if fullscreen_check.get_global_rect().has_point(pos):
		fullscreen_check.button_pressed = not fullscreen_check.button_pressed
		_on_fullscreen_toggled(fullscreen_check.button_pressed)
		return

	# Mining anchor button — cycle between the two anchor modes on
	# each click. Updates the public `mining_volume_anchor` field that
	# EditToolHandler reads on every carve, so the change applies the
	# next swing without a save/reload.
	if mining_anchor_btn.get_global_rect().has_point(pos):
		mining_volume_anchor = (
			MINING_ANCHOR_CENTERED
			if mining_volume_anchor == MINING_ANCHOR_DEPTH_BIASED
			else MINING_ANCHOR_DEPTH_BIASED
		)
		_refresh_mining_anchor_button()
		return


func _update_slider_drag(global_pos: Vector2) -> void:
	if _drag_slider == null:
		return
	_set_slider_from_pos(_drag_slider, global_pos)


func _set_slider_from_pos(slider: HSlider, global_pos: Vector2) -> void:
	var rect: Rect2 = slider.get_global_rect()
	var t: float = clamp((global_pos.x - rect.position.x) / rect.size.x, 0.0, 1.0)
	slider.value = lerp(slider.min_value, slider.max_value, t)


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_apply() -> void:
	_apply_to_audio()
	_save_settings()


func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _refresh_mining_anchor_button() -> void:
	# Sync the button label + tint to match the current
	# `mining_volume_anchor` value. Called after a click toggle and
	# after _load_settings (so the button reflects persisted state on
	# first show).
	if mining_anchor_btn == null:
		return
	if mining_volume_anchor == MINING_ANCHOR_CENTERED:
		mining_anchor_btn.text = "Centered (aim in middle)"
		mining_anchor_btn.add_theme_color_override(
			"font_color", Color(0.95, 0.92, 0.55, 1)
		)
	else:
		mining_anchor_btn.text = "Depth-biased (into terrain)"
		mining_anchor_btn.add_theme_color_override(
			"font_color", Color(0.7, 0.95, 0.7, 1)
		)


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
		"master_volume":         master_slider.value,
		"music_volume":          music_slider.value,
		"sfx_volume":            sfx_slider.value,
		"fullscreen":            fullscreen_check.button_pressed,
		"mining_volume_anchor":  mining_volume_anchor,
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
		mining_volume_anchor = MINING_ANCHOR_DEPTH_BIASED
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
	mining_volume_anchor = clampi(
		int(result.get("mining_volume_anchor", MINING_ANCHOR_DEPTH_BIASED)),
		MINING_ANCHOR_DEPTH_BIASED,
		MINING_ANCHOR_CENTERED,
	)

	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
