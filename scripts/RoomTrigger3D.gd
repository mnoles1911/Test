extends Area3D
class_name RoomTrigger3D
# RoomTrigger3D — invisible Area3D at a doorway that shifts the camera
# bounds (same-zone) or transitions to a new zone scene (cross-zone).
#
# Direct port of RoomTrigger.gd. Only the node types change:
#   Area2D     → Area3D
#   Node2D     → Node3D
#   Vector2    → Vector3 (velocity check uses .x and .z, since Y is up)
#
# HOW TO PLACE:
#   1. Add an Area3D child near the doorway (inside the Zone3D scene)
#   2. Attach this script
#   3. Set target_room_id to the room_id of the room on the other side
#   4. Add a CollisionShape3D child — a thin BoxShape3D spanning the doorway
#   5. Leave exit_zone empty for same-zone transitions
#      Set exit_zone to a scene path for cross-zone transitions


@export var target_room_id: String = ""
@export var exit_zone: String = ""
@export var exit_spawn_id: String = ""
@export var one_way: bool = false
@export_enum("x", "z") var trigger_axis: String = "x"
# In 3D, doorways usually align to either the X or Z axis on the
# horizontal floor plane. (Y is vertical — we don't have ladder
# triggers yet.)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	if one_way and not _moving_forward(body):
		return

	if exit_zone != "":
		print("[RoomTrigger3D] Cross-zone transition → %s (spawn: %s)" % [exit_zone, exit_spawn_id])
		if get_node_or_null("/root/TransitionManager"):
			TransitionManager.change_scene(exit_zone, exit_spawn_id)
	elif target_room_id != "":
		var zone: Node = _find_zone()
		if zone:
			var target_room: Node = _find_room_by_id(zone, target_room_id)
			if target_room:
				zone.enter_room(target_room)
			else:
				push_warning("[RoomTrigger3D] Room '%s' not found in zone." % target_room_id)
		else:
			push_warning("[RoomTrigger3D] No parent Zone found.")


func _moving_forward(body: Node3D) -> bool:
	var vel: Vector3 = body.velocity if "velocity" in body else Vector3.ZERO
	if trigger_axis == "x":
		return vel.x > 0
	else:
		return vel.z > 0


func _find_zone() -> Node:
	var node: Node = get_parent()
	while node != null:
		# Match by node name or class — Zone3D will be a Node3D with
		# a Zone3D.gd script. We avoid hard-coding the class_name to
		# keep this loosely coupled.
		if node.has_method("enter_room"):
			return node
		node = node.get_parent()
	return null


func _find_room_by_id(zone: Node, id: String) -> Node:
	for child in zone.get_children():
		if "room_id" in child and child.room_id == id:
			return child
	return null
