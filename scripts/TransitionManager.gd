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
#
# The second argument ("entrance_south") is the name of a SpawnPoint node in
# the destination scene. The scene reads GameState.player_spawn_id in its _ready()
# to know where to place Roland. Leave it empty to use the scene's default position.
#
# What this script does automatically:
#   1. Fades screen to black
#   2. Saves GameState to disk (autosave on every transition)
#   3. Loads the new scene
#   4. Fades back in from black


const FADE_DURATION: float = 0.4
# Seconds for the fade-out and fade-in. 0.4s feels cinematic without being slow.

var _is_transitioning: bool = false
# Guard flag — prevents double-triggering if two triggers fire at once.

var _canvas_layer: CanvasLayer
var _fade_rect: ColorRect


# =============================================================
# SETUP
# =============================================================

func _ready() -> void:
	# Create a CanvasLayer at layer 100 so it renders above everything else
	# in the game — above the UI, above the player, above dialog boxes.
	# It contains a single black ColorRect that we animate to create the fade.
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)  # Fully transparent at start
	# PRESET_FULL_RECT makes the ColorRect fill the entire viewport automatically,
	# even if the window is resized or the viewport scales.
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_fade_rect)

	print("[TransitionManager] Initialized.")


# =============================================================
# PUBLIC API
# =============================================================

func change_scene(scene_path: String, spawn_id: String = "") -> void:
	# Call this from any trigger to change scenes.
	# spawn_id = the name of the SpawnPoint node to use in the new scene.
	if _is_transitioning:
		return  # Already mid-transition — ignore duplicate calls

	_is_transitioning = true

	# Store where to spawn the player in the new scene.
	GameState.player_spawn_id = spawn_id
	GameState.current_scene = scene_path

	# Autosave before every scene change.
	# This means the player always has a valid save at the last door they walked through.
	GameState.save_game()

	_do_transition(scene_path)

func fade_in_only() -> void:
	# Call this from a scene's _ready() if you need manual control over the
	# fade-in (e.g. after a cutscene that should start black).
	# Under normal circumstances TransitionManager handles this automatically.
	_fade_in()


# =============================================================
# TRANSITION SEQUENCE
# =============================================================

func _do_transition(scene_path: String) -> void:
	# Step 1: Fade to black.
	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_DURATION)

	# Step 2: Once black, load the new scene.
	# "await" here means: pause this function until the tween completes,
	# then continue. It does NOT freeze the game — other code keeps running.
	await tween.finished

	# change_scene_to_file tells Godot to swap out the current scene.
	# It takes effect at the end of this frame.
	get_tree().change_scene_to_file(scene_path)

	# Step 3: Wait one frame for the new scene to finish loading,
	# then fade back in.
	await get_tree().process_frame
	_fade_in()


func _fade_in() -> void:
	# Animate the black overlay back to transparent.
	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, FADE_DURATION)
	await tween.finished
	_is_transitioning = false
