extends Area2D
# Attached to the DialogueTrigger node in World.tscn.
#
# This trigger fires when two conditions are both true:
#   1. The player is physically inside the trigger zone (an Area2D)
#   2. The player presses the E key
#
# For Milestone 1, "firing" just prints a message to the Godot output console.
# In a future milestone, this will call Dialogic.start() to launch a
# dialogue timeline.
#
# Note: We use _unhandled_input + a direct keycode check instead of
# Input.is_action_just_pressed("interact"). The action-based approach depends
# on project.godot having the action registered correctly, which is fragile.
# A direct keycode check works no matter how project.godot is configured.


# Tracks whether the player is currently standing in the trigger zone.
# Set to true when player enters, false when they leave.
var player_inside: bool = false


func _ready() -> void:
	# Connect this Area2D's built-in signals to our handler functions.
	# body_entered fires when a physics body enters the area's collision shape.
	# body_exited fires when a physics body leaves it.
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	# _unhandled_input fires for any input event the rest of the game didn't consume.
	# We only care about it when the player is standing in the trigger zone.
	if not player_inside:
		return

	# Check that this is a key press (not release), it's the E key,
	# and it's not a held-key auto-repeat (we only want the initial press).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.physical_keycode == KEY_E:
			_fire_trigger()
			# Mark the event handled so it doesn't bubble to other systems.
			get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	# body is whatever physics body just entered the area.
	# We check the name to make sure it's the player, not a wall or prop.
	if body.name == "Player":
		player_inside = true
		print("[Trigger] Player entered trigger zone. Press E to interact.")


func _on_body_exited(body: Node2D) -> void:
	if body.name == "Player":
		player_inside = false
		print("[Trigger] Player left trigger zone.")


func _fire_trigger() -> void:
	print("[Trigger] Dialogue trigger fired!")
	# TODO Milestone 2: Replace this print with:
	# Dialogic.start("timeline_name_here")
