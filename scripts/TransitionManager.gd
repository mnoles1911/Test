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

	print("[TransitionManager] Initialized.")


# =============================================================
# PUBLIC API
# =============================================================

func change_scene(scene_path: String, spawn_id: String = "", type: Type = Type.FADE_BLACK) -> void:
	# Call this from any trigger to change scenes.
	# scene_path  — "res://scenes/zones/Aldenholt.tscn"
	# spawn_id    — matches a SpawnPoint.spawn_id in the destination scene
	# type        — FADE_BLACK (default), FADE_WHITE, or CUT
	if _is_transitioning:
		return

	_is_transitioning = true

	# Push current scene onto history before leaving it.
	var current_path: String = GameState.current_scene
	if current_path != "":
		_push_history(current_path, GameState.player_spawn_id)

	# Store where to spawn the player in the new scene.
	GameState.player_spawn_id = spawn_id
	GameState.current_scene = scene_path

	# Autosave before every scene change.
	GameState.save_game()

	_do_transition(scene_path, type)


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

func _do_transition(scene_path: String, type: Type) -> void:
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

	_fade_in(type)


func _fade_in(type: Type = Type.FADE_BLACK) -> void:
	# Reset the rect to the correct opaque color first (in case a cut transition
	# left it transparent), then animate to transparent.
	var r: float = 0.0 if type == Type.FADE_BLACK else 1.0
	_fade_rect.color = Color(r, r, r, 1.0)

	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, FADE_DURATION)
	await tween.finished
	_is_transitioning = false
