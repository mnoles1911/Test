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
