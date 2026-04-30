extends Area2D
class_name RoomTrigger
# RoomTrigger — an invisible Area2D at a doorway that shifts the camera.
#
# What this does in plain English:
#   Place this node at the edge of a doorway between two rooms.
#   When the player walks through, it tells the Zone to shift the camera
#   to frame the new room — no scene reload, instant.
#
#   If exit_zone is set (non-empty), walking through instead calls
#   TransitionManager.change_scene() to load a different zone entirely.
#   Use this for major area transitions (e.g. leaving Aldenholt entirely).
#
# HOW TO PLACE:
#   1. Add an Area2D child somewhere near a doorway (inside the Zone scene)
#   2. Attach this script
#   3. Set target_room_id to the room_id of the room on the other side
#   4. Add a CollisionShape2D child — a thin rectangle spanning the doorway
#   5. Leave exit_zone empty for same-zone transitions
#      Set exit_zone to the scene path for cross-zone transitions
#
# EXAMPLE — same zone:
#   target_room_id = "archive_restricted"
#   exit_zone = ""
#
# EXAMPLE — different zone:
#   target_room_id = ""
#   exit_zone = "res://scenes/zones/VosskaraDocks.tscn"
#   exit_spawn_id = "arrival_from_aldenholt"


# =============================================================
# CONFIGURATION
# =============================================================

@export var target_room_id: String = ""
# The room_id to transition to within this zone.
# Leave blank if this trigger exits the zone.

@export var exit_zone: String = ""
# Scene path for a cross-zone transition.
# Example: "res://scenes/zones/VosskaraDocks.tscn"
# Leave blank for same-zone room transitions.

@export var exit_spawn_id: String = ""
# The spawn_id the player should appear at in the destination zone.
# Only relevant when exit_zone is set.

@export var one_way: bool = false
# If true, only triggers when the player moves in the positive direction
# (right or down, based on trigger_axis). Useful for one-way doors.

@export_enum("horizontal", "vertical") var trigger_axis: String = "horizontal"
# Used with one_way to determine which direction counts as "forward."


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Connect the body_entered signal to our handler.
	body_entered.connect(_on_body_entered)


# =============================================================
# TRIGGER
# =============================================================

func _on_body_entered(body: Node2D) -> void:
	# Only react to the Player node.
	if not body.is_in_group("player"):
		return

	# One-way check: if enabled, verify the player is moving in the right direction.
	if one_way and not _moving_forward(body):
		return

	if exit_zone != "":
		# Cross-zone transition — hand off to TransitionManager.
		print("[RoomTrigger] Cross-zone transition → %s (spawn: %s)" % [exit_zone, exit_spawn_id])
		if get_node_or_null("/root/TransitionManager"):
			TransitionManager.change_scene(exit_zone, exit_spawn_id)
	elif target_room_id != "":
		# Same-zone room switch — find the Room and tell the Zone.
		var zone: Zone = _find_zone()
		if zone:
			var target_room: Room = _find_room_by_id(zone, target_room_id)
			if target_room:
				zone.enter_room(target_room)
			else:
				push_warning("[RoomTrigger] Room '%s' not found in zone." % target_room_id)
		else:
			push_warning("[RoomTrigger] No parent Zone found.")


func _moving_forward(body: Node2D) -> bool:
	# Checks if the body's velocity is in the positive direction for the axis.
	if not body.has_method("get"):
		return true
	var vel: Vector2 = body.velocity if "velocity" in body else Vector2.ZERO
	if trigger_axis == "horizontal":
		return vel.x > 0
	else:
		return vel.y > 0


func _find_zone() -> Zone:
	# Walk up the tree to find the Zone node.
	var node: Node = get_parent()
	while node != null:
		if node is Zone:
			return node
		node = node.get_parent()
	return null


func _find_room_by_id(zone: Zone, id: String) -> Room:
	# Search all children of the Zone for a Room with matching room_id.
	for child in zone.get_children():
		if child is Room and child.room_id == id:
			return child
	return null
