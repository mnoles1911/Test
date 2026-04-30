extends Node3D
# SpawnPoint3D — marks a position in a 3D Zone where the player
# should appear when entering with a matching spawn_id.
#
# Direct port of SpawnPoint.gd. The only changes:
#   - extends Node3D instead of Node2D
#   - facing_direction is a Vector3 (with Y=0; we don't yet face up/down)
#   - the editor visualisation is dropped because Node3D shows its
#     own gizmo in the 3D editor (no _draw equivalent in 3D)
#
# Place SpawnPoint3D nodes in your World3D scene at every doorway,
# stairwell, or scripted entry. Zone3D reads them in _ready() and
# uses GameState.player_spawn_id to choose where to place the player.


@export var spawn_id: String = ""
# Unique within the zone. Examples:
#   "default"            — fallback when no spawn_id is set
#   "from_archive"       — player came from the Archive
#   "chapel_back_door"   — entering via the rear of the Iron Chalice

@export var facing_direction: Vector3 = Vector3(0.0, 0.0, 1.0)
# Direction the player should face after spawning, in world space.
# Vector3(0, 0, 1) = facing south (towards camera). Vector3(1, 0, 0) = east.
# Y component is ignored — characters stand upright, they don't tilt.
