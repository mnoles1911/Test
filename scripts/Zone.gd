extends Node2D
class_name Zone
# Zone — the top-level node for a multi-room area.
#
# What a "zone" is in plain English:
#   A zone is one .tscn file that contains multiple rooms. The rooms are
#   placed at different world coordinates (e.g. Room A at x=0, Room B at x=1000,
#   Room C at x=-1000) so they are spatially separated but loaded at the same time.
#   When the player walks through a door, the camera shifts to the new room —
#   no load screen, no scene change.
#
#   A full zone reload (change_scene) still happens when moving between major areas,
#   e.g. Aldenholt → Vosskara. That is intentional — major areas have their own .tscn.
#
# HOW TO USE THIS IN A NEW SCENE:
#   1. Create a new .tscn with root node type Node2D
#   2. Attach this script (Zone.gd) to the root
#   3. Add Room child nodes (attach Room.gd to each)
#   4. Add RoomTrigger nodes at doorways (attach RoomTrigger.gd)
#   5. Add SpawnPoint nodes where players can be placed (attach SpawnPoint.gd)
#   6. Set zone_id to something unique like "aldenholt" or "cave_entrance"
#
# TREE STRUCTURE EXAMPLE:
#   Aldenholt (Zone.gd)
#   ├── RoomA_TownSquare (Node2D, Room.gd) — at position (0, 0)
#   ├── RoomB_Archive (Node2D, Room.gd) — at position (2000, 0)
#   ├── RoomC_Tavern (Node2D, Room.gd) — at position (4000, 0)
#   ├── Player (instance of Player.tscn)
#   └── ... lights, triggers, NPCs ...


# =============================================================
# ZONE IDENTITY
# =============================================================

@export var zone_id: String = ""
# Unique identifier for this zone. Used by TransitionManager to find spawn points.
# Examples: "aldenholt", "cave_entrance", "iron_chalice"


# =============================================================
# ROOM MANAGEMENT
# =============================================================

var active_room: Room = null
# The room the player is currently inside.

var _rooms: Array = []
# All Room children in this zone. Populated on _ready.

var _spawn_points: Dictionary = {}
# spawn_id → SpawnPoint node. Populated on _ready.


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Collect all Room children.
	for child in get_children():
		if child is Room:
			_rooms.append(child)

	# Collect all SpawnPoint nodes anywhere in the tree.
	_collect_spawn_points(self)

	# If GameState has a spawn ID set, move player to that spawn point.
	var spawn_id: String = GameState.player_spawn_id
	if spawn_id != "" and _spawn_points.has(spawn_id):
		var sp: SpawnPoint = _spawn_points[spawn_id]
		_place_player_at_spawn(sp)
	elif _spawn_points.size() > 0:
		# Fall back to the first spawn point found.
		var sp: SpawnPoint = _spawn_points.values()[0]
		_place_player_at_spawn(sp)

	GameState.current_scene = zone_id
	print("[Zone] '%s' ready. Rooms: %d, Spawn points: %d" % [zone_id, _rooms.size(), _spawn_points.size()])


func _collect_spawn_points(node: Node) -> void:
	# Walks the entire scene tree recursively to find SpawnPoint nodes.
	for child in node.get_children():
		if child is SpawnPoint:
			if child.spawn_id != "":
				_spawn_points[child.spawn_id] = child
		_collect_spawn_points(child)


# =============================================================
# ROOM TRANSITIONS
# =============================================================

func enter_room(room: Room) -> void:
	# Called by RoomTrigger when the player enters a new room.
	if room == active_room:
		return

	active_room = room

	# Move the camera limits to frame this room.
	var player_node = get_node_or_null("Player")
	if player_node:
		var cam: Camera2D = player_node.get_node_or_null("Camera2D")
		if cam:
			cam.limit_left   = room.room_bounds.position.x
			cam.limit_top    = room.room_bounds.position.y
			cam.limit_right  = room.room_bounds.position.x + room.room_bounds.size.x
			cam.limit_bottom = room.room_bounds.position.y + room.room_bounds.size.y

	print("[Zone] Entered room: %s" % room.room_id)


# =============================================================
# SPAWN PLACEMENT
# =============================================================

func _place_player_at_spawn(sp: SpawnPoint) -> void:
	var player_node = get_node_or_null("Player")
	if player_node:
		player_node.global_position = sp.global_position
		print("[Zone] Player placed at spawn '%s' (%s)" % [sp.spawn_id, str(sp.global_position)])
