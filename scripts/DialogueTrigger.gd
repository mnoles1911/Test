extends Area2D
# Attached to the DialogueTrigger node in World.tscn.
#
# This trigger fires when two conditions are both true:
#   1. The player is physically inside the trigger zone (an Area2D)
#   2. The player presses the interact key (E, defined in project.godot)
#
# For Milestone 1, "firing" just prints a message to the Godot output console.
# In a future milestone, this will call Dialogic.start() to launch a
# dialogue timeline.


# Tracks whether the player is currently standing in the trigger zone.
# Set to true when player enters, false when they leave.
var player_inside: bool = false


func _ready() -> void:
	# Connect this Area2D's built-in signals to our handler functions.
	# body_entered fires when a physics body enters the area's collision shape.
	# body_exited fires when a physics body leaves it.
	#
	# We connect them in code here instead of in the editor so everything
	# is visible in one place and works without manual editor wiring.
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	# Check every frame: is the player inside AND pressing interact?
	# is_action_just_pressed only returns true on the frame the key is first pressed,
	# so holding E down won't spam the trigger repeatedly.
	if player_inside and Input.is_action_just_pressed("interact"):
		_fire_trigger()


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
