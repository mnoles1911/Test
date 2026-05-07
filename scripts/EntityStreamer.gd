extends Node3D
# EntityStreamer — Phase 5-3D STUB version.
#
# In the finished game (Phase 6+), this node is responsible for spawning
# and despawning every world entity (NPCs, props, enemies, triggers) as
# the player moves around. It reads `EntityRegistry`, instantiates scenes
# inside the load radius, and saves+frees them on exit.
#
# But for Phase 5-3D — the milestone where we're proving terrain streaming
# works — we don't have an EntityRegistry yet, and we don't want to load
# real entities. We just want to see in the Output panel that the streamer
# is tracking the player correctly as chunks come and go beneath them.
#
# So this version does ONE thing: print "entered chunk (cx, cz)" whenever
# the player crosses into a new chunk. That's enough to confirm:
#   1. The streamer is alive and ticking.
#   2. The player position is being read correctly.
#   3. Chunk coordinates make sense as Roland walks east/north/south/west.
#
# When Phase 6-3D arrives, replace `_on_chunk_changed` with real entity
# load/unload logic. Keep this file in place — the chunk-tracking math
# below is exactly what the final version needs too.
#
# Reference: design/3D_VOXEL_MIGRATION.md → entity streaming
#            DESIGNER_TODO.md → Phase 5-3D and Phase 6-3D


@export var chunk_size: int = 16
# How big a "chunk" is, in metres. 16 m is a typical voxel-chunk size and
# matches what VoxelLodTerrain uses by default. Don't change this without
# also updating the terrain node — they need to agree.

@export var print_chunk_changes: bool = false
# Toggle on if you want to see chunk-transition events in the Output
# panel while debugging streaming. Defaults OFF (changed 2026-05-07)
# because at fly speed the player crosses ~19 chunks/second and each
# print() to Godot's Output panel can cost 0.5–2 ms — visible as
# steady frame-time noise during movement.

@export var player_node_path: NodePath
# Drag the player (or any Node3D you want to track) into this slot in the
# inspector. If left empty we'll search the "player" group at runtime,
# the same trick HUDOverlay uses, so the streamer keeps working even when
# the player is spawned dynamically.


var _player: Node3D = null
# Cached reference to the player so we don't search the tree every frame.

var _last_chunk: Vector2i = Vector2i(-99999, -99999)
# Where the player was last frame, in chunk coordinates. Initialised to a
# nonsense value so the very first frame is guaranteed to count as a
# "chunk change" and print once.


func _ready() -> void:
	# Try the explicit path first.
	if not player_node_path.is_empty():
		var n: Node = get_node_or_null(player_node_path)
		if n is Node3D:
			_player = n

	# Fall back to the "player" group (set in Player3D.tscn).
	if _player == null:
		var matches: Array = get_tree().get_nodes_in_group("player")
		for candidate in matches:
			if candidate is Node3D:
				_player = candidate
				break

	if _player == null:
		push_warning(
			"EntityStreamer: no player node found. " \
			+ "Set player_node_path or add the player to the 'player' group."
		)


func _process(_delta: float) -> void:
	if _player == null:
		# Nothing to track. We could try to find the player again here,
		# but a single warning at _ready time is usually enough — every-frame
		# searches just hide a real bug.
		return

	var current_chunk: Vector2i = _world_to_chunk(_player.global_position)
	if current_chunk != _last_chunk:
		_on_chunk_changed(_last_chunk, current_chunk)
		_last_chunk = current_chunk


func _world_to_chunk(world_pos: Vector3) -> Vector2i:
	# Convert XZ world position to a chunk index. We only care about
	# horizontal chunks here — vertical streaming will matter when we
	# add caves, but for surface terrain the chunk grid is 2D.
	# floor() handles negative coordinates correctly: e.g. -1 m falls
	# into chunk -1, not chunk 0.
	var cx: int = int(floor(world_pos.x / chunk_size))
	var cz: int = int(floor(world_pos.z / chunk_size))
	return Vector2i(cx, cz)


func _on_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i) -> void:
	# Phase 5-3D: just log it. Phase 6-3D will replace this body with real
	# entity load/unload calls against EntityRegistry.
	if print_chunk_changes:
		print(
			"[EntityStreamer] entered chunk ", new_chunk,
			" (was ", old_chunk, ")  world=",
			Vector3(_player.global_position.x, _player.global_position.y, _player.global_position.z).round()
		)
