extends Area2D
# Attached to the DialogueTrigger node in World.tscn.
#
# This trigger fires when two conditions are both true:
#   1. The player is physically inside the trigger zone (an Area2D)
#   2. The player presses the E key
#
# When fired, it calls Dialogic.start() to launch a dialogue timeline.
# Dialogic is a plugin — see design/DIALOGIC_SETUP.md for installation steps.


# Path to the Dialogic timeline file for this trigger.
const TIMELINE_PATH: String = "res://dialogue/henrietta_archive.dtl"

# Tracks whether the player is currently standing in the trigger zone.
var player_inside: bool = false

# Prevents the dialogue from firing again while it's already open.
var dialogue_active: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
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
	if get_node_or_null("/root/Dialogic") == null:
		push_error("[DialogueTrigger] Dialogic autoload not found. See design/DIALOGIC_SETUP.md.")
		return

	dialogue_active = true

	# Dialogic.start() returns the layout CanvasLayer node, NOT a timeline object.
	# The timeline_ended signal lives on the Dialogic autoload itself.
	# We connect it here (with a one-shot flag so it auto-disconnects after firing)
	# rather than on the return value of start().
	Dialogic.timeline_ended.connect(_on_dialogue_ended, CONNECT_ONE_SHOT)
	Dialogic.start(TIMELINE_PATH)


func _on_dialogue_ended() -> void:
	dialogue_active = false
	print("[Trigger] Dialogue ended.")
