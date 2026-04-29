extends Area2D
# Attached to the DialogueTrigger node in World.tscn.
#
# This trigger fires when two conditions are both true:
#   1. The player is physically inside the trigger zone (an Area2D)
#   2. The player presses the E key
#
# When fired, it calls Dialogic.start() to launch a dialogue timeline.
# Dialogic is a plugin — see design/DIALOGIC_SETUP.md for installation steps.
#
# If Dialogic isn't installed yet, the trigger degrades gracefully:
# it prints an error to the Output panel instead of crashing the game.


# Path to the Dialogic timeline file for this trigger.
# Change this constant to point to a different timeline for a different trigger.
const TIMELINE_PATH: String = "res://dialogue/henrietta_archive.dtl"

# Tracks whether the player is currently standing in the trigger zone.
var player_inside: bool = false

# Prevents the dialogue from firing again while it's already open.
# Set to true when dialogue starts, false when it ends.
var dialogue_active: bool = false


func _ready() -> void:
	# Connect this Area2D's body signals so we know when the player enters/exits.
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	# Only respond to E key presses when the player is in the zone
	# and dialogue isn't already running.
	if not player_inside or dialogue_active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.physical_keycode == KEY_E:
			_fire_trigger()
			get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		player_inside = true
		print("[Trigger] Player entered trigger zone. Press E to interact.")


func _on_body_exited(body: Node2D) -> void:
	if body.name == "Player":
		player_inside = false
		print("[Trigger] Player left trigger zone.")


func _fire_trigger() -> void:
	# Check that the Dialogic plugin is loaded before trying to use it.
	# Engine.has_singleton() returns true if the autoload exists.
	# Dialogic adds itself as an autoload when the plugin is enabled.
	if not Engine.has_singleton("Dialogic"):
		# Plugin not installed — degrade gracefully.
		push_error("[DialogueTrigger] Dialogic plugin not found. Install it via the Asset Library and enable it in Project > Project Settings > Plugins. See design/DIALOGIC_SETUP.md for full instructions.")
		print("[Trigger] Dialogue trigger fired! (Dialogic not installed yet — see Output for setup instructions.)")
		return

	# Start the Dialogic timeline.
	# Dialogic.start() takes the path to a .dtl file and displays the dialogue
	# box over the current scene. The player presses Enter or E to advance lines.
	dialogue_active = true
	var timeline = Dialogic.start(TIMELINE_PATH)

	# timeline_ended fires when the last line is dismissed and the box closes.
	# We use it to re-enable the trigger so dialogue could theoretically play again.
	# For a one-shot trigger (fires only once ever), add: queue_free() here instead.
	if timeline:
		timeline.timeline_ended.connect(_on_dialogue_ended)


func _on_dialogue_ended() -> void:
	dialogue_active = false
	print("[Trigger] Dialogue ended.")
