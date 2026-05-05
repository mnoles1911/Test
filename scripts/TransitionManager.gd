extends Node
# TransitionManager — Autoload singleton. Handles all scene changes.
#
# What "scene transition" means in plain English:
#   When Roland walks through a door, we don't just teleport him — we fade
#   the screen to black, load the next room, then fade back in. This script
#   handles that entire sequence so every scene in the game works the same way.
#
# Usage from any script (e.g. a door trigger):
#   TransitionManager.change_scene("res://scenes/act1/Archive.tscn", "entrance_south")
#   TransitionManager.change_scene("res://scenes/act1/Archive.tscn", "entrance_south", TransitionManager.Type.FADE_WHITE)
#   TransitionManager.go_back()   ← return to the previous scene
#
# What this script does automatically:
#   1. Fades screen (black, white, or cut)
#   2. Saves GameState to disk (autosave on every transition)
#   3. Loads the new scene
#   4. Fades back in


# =============================================================
# TRANSITION TYPE
# =============================================================

enum Type {
	FADE_BLACK,   # Standard: fade to black, load, fade back in
	FADE_WHITE,   # Dream / memory sequence: fade to white and back
	CUT           # Instant: no fade at all, just swap the scene
}


# =============================================================
# CONSTANTS
# =============================================================

const FADE_DURATION: float = 0.4
# Seconds for fade-out and fade-in.

const HISTORY_MAX: int = 10
# How many scenes to remember for go_back().


# =============================================================
# STATE
# =============================================================

var _is_transitioning: bool = false
# Guard flag — prevents double-triggering if two triggers fire at once.

var _scene_history: Array = []
# Stack of {path, spawn_id} dicts — most recent at the back.
# go_back() pops the last entry and transitions to it.

var _canvas_layer: CanvasLayer
var _fade_rect: ColorRect

# Loading screen — a labelled overlay shown WHILE the fade rect is
# still opaque, AFTER the destination scene has been loaded but
# BEFORE we fade back in. Gives Zylann's worker threads a window to
# stream the player's nearby chunks so the world is partially
# rendered the moment the fade clears. Only used for transitions
# into the open world (NEW GAME, LOAD GAME); regular door-to-door
# scene swaps skip the loading screen entirely.
var _loading_root: Control
var _loading_title_label: Label
var _loading_dots_label: Label
var _loading_dots_timer: float = 0.0


# =============================================================
# SETUP
# =============================================================

func _ready() -> void:
	# CanvasLayer at 100 renders above everything — UI, player, dialogue boxes.
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_fade_rect)

	_build_loading_screen()
	process_mode = Node.PROCESS_MODE_ALWAYS

	print("[TransitionManager] Initialized.")


func _build_loading_screen() -> void:
	# Stacked above the fade rect. Hidden by default; toggled by
	# _show_loading_screen / _hide_loading_screen.
	_loading_root = Control.new()
	_loading_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.visible = false
	_canvas_layer.add_child(_loading_root)

	# Centre column: title + animated dots.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.size = Vector2(600, 100)
	vbox.position = Vector2(-300, -50)
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_root.add_child(vbox)

	_loading_title_label = Label.new()
	_loading_title_label.text = "Loading..."
	_loading_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_title_label.add_theme_font_size_override("font_size", 36)
	_loading_title_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	vbox.add_child(_loading_title_label)

	_loading_dots_label = Label.new()
	_loading_dots_label.text = "Streaming voxel chunks"
	_loading_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_dots_label.add_theme_font_size_override("font_size", 16)
	_loading_dots_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	vbox.add_child(_loading_dots_label)


func _process(delta: float) -> void:
	# Animate the trailing dots on the loading-screen subtitle so
	# the player sees a heartbeat while we wait. Cheap — one string
	# write every ~0.5 s while the screen is visible, no-op otherwise.
	if _loading_root != null and _loading_root.visible and _loading_dots_label != null:
		_loading_dots_timer += delta
		var dot_count: int = int(fmod(_loading_dots_timer * 2.0, 4.0))  # 0..3
		var dots: String = ".".repeat(dot_count)
		_loading_dots_label.text = "Streaming voxel chunks" + dots


# =============================================================
# PUBLIC API
# =============================================================

func change_scene(scene_path: String, spawn_id: String = "", type: Type = Type.FADE_BLACK, loading_seconds: float = 0.0) -> void:
	# Call this from any trigger to change scenes.
	# scene_path       — "res://scenes/zones/Aldenholt.tscn"
	# spawn_id         — matches a SpawnPoint.spawn_id in the destination scene
	# type             — FADE_BLACK (default), FADE_WHITE, or CUT
	# loading_seconds  — if > 0, hold the destination scene under a "Loading..."
	#                    overlay for this many seconds AFTER the scene loads
	#                    but BEFORE the fade-in. Use this for transitions into
	#                    the open world where chunks need time to stream in
	#                    (NEW GAME / LOAD GAME). Door-to-door swaps leave it 0.
	if _is_transitioning:
		return

	_is_transitioning = true

	# Push current scene onto history before leaving it.
	# On first launch GameState.current_scene is empty (TransitionManager
	# was never called before), so fall back to the tree's actual scene
	# path — that way go_back() can return to MainMenu even from the
	# very first scene change the player triggers.
	var current_path: String = GameState.current_scene
	if current_path == "" and get_tree().current_scene != null:
		current_path = get_tree().current_scene.scene_file_path
	if current_path != "":
		_push_history(current_path, GameState.player_spawn_id)

	# Store where to spawn the player in the new scene.
	GameState.player_spawn_id = spawn_id
	GameState.current_scene = scene_path

	# (Previously called GameState.save_game() here on every scene
	# transition. Removed: it created an untagged save on top of the
	# PauseMenu's already-explicit '[Auto]' save on EXIT TO MENU and
	# QUIT, so going to the menu produced two saves at the same
	# timestamp. Save points are now exclusively the explicit player
	# action (SAVE button) and the on-exit/on-quit auto-save in
	# PauseMenu, both of which produce one named/autosave file each.)

	_do_transition(scene_path, type, loading_seconds)


func go_back() -> void:
	# Return to the previous scene. Does nothing if there is no history.
	if _scene_history.is_empty():
		print("[TransitionManager] go_back() called with no history.")
		return
	if _is_transitioning:
		return

	var entry: Dictionary = _scene_history.pop_back()
	change_scene(entry["path"], entry["spawn_id"], Type.FADE_BLACK)


func fade_in_only() -> void:
	# Call from a scene's _ready() if you need manual fade-in control
	# (e.g. after a cutscene that should start black).
	_fade_in(Type.FADE_BLACK)


func has_history() -> bool:
	return not _scene_history.is_empty()


func peek_back() -> String:
	# Returns the scene path that go_back() would transition to,
	# without actually popping it. Returns "" if history is empty.
	if _scene_history.is_empty():
		return ""
	return _scene_history.back()["path"]


# =============================================================
# HISTORY
# =============================================================

func _push_history(path: String, spawn_id: String) -> void:
	_scene_history.append({"path": path, "spawn_id": spawn_id})
	# Keep history bounded so it doesn't grow forever.
	if _scene_history.size() > HISTORY_MAX:
		_scene_history.pop_front()


# =============================================================
# TRANSITION SEQUENCE
# =============================================================

func _do_transition(scene_path: String, type: Type, loading_seconds: float = 0.0) -> void:
	if type == Type.CUT:
		# No fade — swap immediately.
		get_tree().change_scene_to_file(scene_path)
		await get_tree().process_frame
		_is_transitioning = false
		return

	# Determine the fade color.
	var fade_color: Color = Color(0.0, 0.0, 0.0, 0.0) if type == Type.FADE_BLACK else Color(1.0, 1.0, 1.0, 0.0)
	var _opaque_color: Color = Color(fade_color.r, fade_color.g, fade_color.b, 1.0)

	_fade_rect.color = fade_color

	# Fade out.
	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_DURATION)
	await tween.finished

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame

	# Optional loading-screen hold — fade rect stays opaque, loading
	# overlay shows on top, the destination scene streams in
	# behind the curtain. Skipped when loading_seconds <= 0.
	if loading_seconds > 0.0:
		_show_loading_screen()
		await get_tree().create_timer(loading_seconds, true).timeout
		_hide_loading_screen()

	_fade_in(type)


func _show_loading_screen() -> void:
	if _loading_root != null:
		_loading_root.visible = true
		_loading_dots_timer = 0.0


func _hide_loading_screen() -> void:
	if _loading_root != null:
		_loading_root.visible = false


func _fade_in(type: Type = Type.FADE_BLACK) -> void:
	# Reset the rect to the correct opaque color first (in case a cut transition
	# left it transparent), then animate to transparent.
	var r: float = 0.0 if type == Type.FADE_BLACK else 1.0
	_fade_rect.color = Color(r, r, r, 1.0)

	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, FADE_DURATION)
	await tween.finished
	_is_transitioning = false
