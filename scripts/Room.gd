extends Node2D
class_name Room
# Room — marks one room within a Zone.
#
# What this does in plain English:
#   A Room node is the parent for all the visual and collision content
#   in one room (walls, floors, lights, NPCs, etc.).
#   It knows its own bounds rectangle so the Zone can constrain the camera.
#
# HOW TO SET UP A ROOM:
#   1. Add a Node2D child inside your Zone scene
#   2. Attach this script to it
#   3. Set room_id to a short unique name, e.g. "town_square" or "archive_main"
#   4. Set room_bounds to a Rect2 in global coordinates:
#      - position = top-left corner of the room (in world space)
#      - size = width × height of the room in pixels
#   5. Add all the room's content as children of this node


# =============================================================
# ROOM IDENTITY
# =============================================================

@export var room_id: String = ""
# Unique name for this room within the zone. Used in Zone.enter_room() print logs.
# Examples: "town_square", "archive_main", "iron_chalice_nave"

@export var room_bounds: Rect2 = Rect2(0, 0, 320, 180)
# The camera will be locked to these bounds when the player is in this room.
# Position is the world-space top-left corner of the room.
# Size is the pixel dimensions of the room.
#
# For a 320×180 viewport room:
#   room_bounds = Rect2(0, 0, 320, 180)         ← first room, top-left at origin
#   room_bounds = Rect2(2000, 0, 320, 180)       ← second room, offset right


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	print("[Room] '%s' initialized at %s, size %s" % [
		room_id,
		str(room_bounds.position),
		str(room_bounds.size)
	])
