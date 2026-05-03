extends Node3D
# World3DBootstrap — wires up scene-level systems when the World3D
# scene loads.
#
# What this does in plain English:
#
#   When World3D.tscn opens for play, the autoloads (VoxelEditManager,
#   NoEditZoneRegistry) are alive but they don't yet know about the
#   VoxelLodTerrain that lives inside this scene. This script runs in
#   _ready() and hands the terrain over so every voxel edit verb
#   (pickaxe, axe, shovel, explosive, spell) can find its target.
#
# This script is the single entry point for "things that have to
# happen at world load." If we add more world-level wiring later
# (per-slot voxel save paths, NoEditZoneRegistry pre-warm, weather
# system init), it goes here.
#
# Attached to the root node of World3D.tscn.


@export var voxel_terrain_path: NodePath = "VoxelLodTerrain"
# Path to the VoxelLodTerrain node within this World3D scene.
# Exposed as a NodePath so the scene can be reorganized without
# touching this script.


func _ready() -> void:
	# --- Hand the voxel terrain to the edit manager ---
	# Without this call, VoxelEditManager has no terrain to write to
	# and silently rejects every queue_edit_* call (returns false).
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null:
		push_error("[World3D] VoxelLodTerrain not found at path: %s" % voxel_terrain_path)
		return

	# Guard with get_node_or_null in case the autoload isn't registered
	# yet (e.g. a fresh project without our autoload entries). The
	# project should always have it registered, but this prevents a
	# crash if something is misconfigured.
	if get_node_or_null("/root/VoxelEditManager"):
		VoxelEditManager.set_terrain(terrain)
		print("[World3D] Voxel terrain handed to VoxelEditManager.")
	else:
		push_warning("[World3D] VoxelEditManager autoload not registered; voxel edits will not work.")

	# --- Apply saved player position ---
	# When the world scene loads after a load_save_file() call,
	# GameState.player_position holds Roland's saved 3D position.
	# Apply it to the live player so he respawns where the save
	# was taken. Without this, every load drops Roland at the
	# scene's default Player3D spawn (Y=35 on noise terrain).
	#
	# Skip on a fresh New Game where player_position is the default
	# Vector3.ZERO — let the scene's default placement win.
	#
	# Deferred one frame so the Player3D node has run its own
	# _ready (collision shape resolved, voxel terrain has had a
	# chance to load nearby chunks for collision).
	if get_node_or_null("/root/GameState"):
		if GameState.player_position != Vector3.ZERO:
			call_deferred("_apply_saved_player_position")


func _apply_saved_player_position() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		push_warning("[World3D] No player in tree to apply saved position to")
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return
	player.global_position = GameState.player_position
	# Restore facing direction (Y rotation only — pitch and roll
	# live on the camera, not the body). The CameraRig follows the
	# player body's rotation.y in standard mode, so this also gets
	# the camera looking the same way Roland was looking at save.
	player.rotation.y = GameState.player_rotation_y
	print("[World3D] Restored player position to %s, rotation_y=%.2f rad" % [
		GameState.player_position, GameState.player_rotation_y
	])
