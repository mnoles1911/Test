extends Node2D
class_name SpawnPoint
# SpawnPoint — marks where the player appears when entering this zone/room.
#
# What this does in plain English:
#   Place this node at the exact pixel where the player should stand
#   when arriving from a specific location. Zone.gd finds all SpawnPoints
#   on _ready and places the player at the one matching GameState.player_spawn_id.
#
#   TransitionManager.change_scene(path, spawn_id) sets GameState.player_spawn_id
#   before the scene loads, so the Zone knows which SpawnPoint to use.
#
# HOW TO PLACE:
#   1. Add a Node2D anywhere in your Zone or Room
#   2. Attach this script
#   3. Set spawn_id to a descriptive string
#      Convention: "from_<origin>" e.g. "from_town_square", "from_docks"
#   4. Position the node where the player should appear
#
# EXAMPLE — the Archive entrance:
#   spawn_id = "from_town_square"
#   position = Vector2(160, 160)   ← just inside the Archive doorway
#
# EXAMPLE — returning from the restricted section:
#   spawn_id = "from_restricted"
#   position = Vector2(80, 90)


# =============================================================
# CONFIGURATION
# =============================================================

@export var spawn_id: String = ""
# Unique ID within this zone. Must match what TransitionManager passes as spawn_id.
# Convention: "from_<origin>" or "default"

@export var facing_direction: Vector2 = Vector2.DOWN
# The direction the player faces when spawned here.
# DOWN = facing toward camera (standard for entering a room from north)
# LEFT/RIGHT = facing sideways (entering from a side door)
# Not used by Zone.gd directly — Player.gd can read this from the SpawnPoint if needed.


# =============================================================
# DEBUG DRAWING
# =============================================================

func _draw() -> void:
	# In the editor, draw a small cross so designers can see spawn positions.
	# This does not appear at runtime.
	if Engine.is_editor_hint():
		var color := Color(0.2, 1.0, 0.4, 0.8)
		draw_line(Vector2(-8, 0), Vector2(8, 0), color, 1.0)
		draw_line(Vector2(0, -8), Vector2(0, 8), color, 1.0)
		draw_circle(Vector2.ZERO, 3.0, color)
