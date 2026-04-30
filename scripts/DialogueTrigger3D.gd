extends Area3D
class_name DialogueTrigger3D
# DialogueTrigger3D — invisible 3D trigger zone that fires on press-E.
#
# Direct port of DialogueTrigger.gd. The 2D version waited for the
# player to be inside an Area2D, then watched for the "interact"
# action. This is the same logic in 3D — Area3D + body_entered/exited
# signals + Input check in _process.
#
# Wire-up:
#   1. Place an Area3D in your World3D scene at the NPC's location
#   2. Attach this script
#   3. Add a CollisionShape3D child (BoxShape3D, sized to the
#      conversation reach — usually 2×2×2 m)
#   4. Set timeline_name to the Dialogic timeline this trigger plays
#
# This is a M4-3D placeholder. Until Dialogic is wired up in 3D and
# until we have a real NPC to talk to, _fire_trigger() just prints.


@export var timeline_name: String = ""
# The Dialogic timeline file (without extension) to play.
# Example: "henrietta_archive"
# If empty, the trigger just prints to the Output panel for debugging.

var _player_inside: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if _player_inside and Input.is_action_just_pressed("interact"):
		_fire_trigger()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		print("[DialogueTrigger3D] Player entered. Press E to interact.")


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false


func _fire_trigger() -> void:
	if timeline_name == "":
		print("[DialogueTrigger3D] Fired (no timeline assigned).")
		return
	# Dialogic autoload must exist before calling start.
	# Same pattern as the 2D DialogueTrigger.
	if get_node_or_null("/root/Dialogic"):
		print("[DialogueTrigger3D] Starting timeline: %s" % timeline_name)
		Dialogic.start(timeline_name)
	else:
		push_warning("[DialogueTrigger3D] Dialogic autoload not found.")
