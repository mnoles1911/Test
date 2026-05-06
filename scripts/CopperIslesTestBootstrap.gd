extends Node3D
# CopperIslesTestBootstrap — minimal world wiring for the Copper Isles
# scale-test scene.
#
# What this does in plain English:
#
#   The test scene contains a VoxelLodTerrain driven by the Copper Isles
#   heightmap generator and a Player3D. The autoloads (VoxelEditManager,
#   WaterFlowManager, etc.) are alive but they don't yet know about the
#   terrain in this scene. This script handles the small set of wire-ups
#   needed to make mining and water work, and snaps the player above the
#   highest possible terrain so they don't spawn inside an island.
#
#   This is a slimmed-down sibling of World3DBootstrap.gd — it skips the
#   features the test scene doesn't need (dialogue triggers, NoEditZones,
#   per-slot save paths, save/load player position) and keeps only what
#   the F7 scale-cycle workflow needs.
#
# Attached to the root node of CopperIslesTest.tscn.


@export var voxel_terrain_path: NodePath = "VoxelLodTerrain"

# Vertical drop height for the player on first spawn and after every
# scale change. Calculated lazily from the generator's max peak so it
# stays valid no matter what scale the player is testing.
const SPAWN_HEIGHT_MARGIN_M: float = 30.0


func _ready() -> void:
	# Bake-as-seed: if a baked baseline exists in res://assets/voxel/
	# AND the player's working SQLite isn't on disk yet (fresh install
	# or after a manual delete), copy the baseline into place. The
	# stream then reads from the populated DB instead of regenerating
	# every chunk on first visit. Player edits accumulate in the same
	# file from that point on (save_generator_output=true).
	#
	# Why a copy instead of two-tier chaining: VoxelStreamSQLite's
	# load methods aren't exposed to GDScript (verified via probe in
	# scenes/_dev/BakeWorld.tscn → Run Diagnostics). A custom
	# VoxelStreamScript subclass would need to read Zylann's SQLite
	# schema directly, which isn't documented. Copy is simple and
	# robust; revisit if Zylann ever adds a public chain API.
	_seed_from_baseline_if_needed()

	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null:
		push_error("[CopperIslesTest] VoxelLodTerrain not found at: %s" % voxel_terrain_path)
		return

	# Configure CHANNEL_COLOR depth to 32-bit so packed RGBA + mat_id
	# values survive storage. Default 8-bit truncates to just the red
	# byte, which makes mining + colours both broken.
	if "format" in terrain:
		_configure_voxel_format(terrain)

	# Tell the generator to skip the EXR load in shipped builds. The
	# baked SQLite covers every in-bounds chunk, so the generator only
	# runs for out-of-bounds (deep ocean) — which doesn't need the
	# heightmap. Editor + dev builds keep loading the EXR for re-bakes.
	# `OS.has_feature("template")` is true ONLY in release export
	# builds; false in editor and debug exports.
	if "generator" in terrain:
		var gen: Resource = terrain.get("generator")
		if gen != null and "require_heightmap_in_editor_only" in gen:
			gen.set("require_heightmap_in_editor_only", true)

	# Move per-edit voxel-block updates off the main thread; defer
	# collision-shape rebuilds so they batch instead of firing on every
	# edit. Same settings World3DBootstrap applies to Mira.
	if "threaded_update_enabled" in terrain:
		terrain.set("threaded_update_enabled", true)
	if "collision_update_delay" in terrain:
		terrain.set("collision_update_delay", 0.1)

	# Hand the terrain to VoxelEditManager so the pickaxe / shovel in
	# the player loadout can carve it.
	if get_node_or_null("/root/VoxelEditManager"):
		VoxelEditManager.set_terrain(terrain)

	# Ocean source region — gives the central archipelago a visible
	# waterline. The generator already writes water source bytes into
	# CHANNEL_DATA at LOD0 below sea level; this AABB tells
	# WaterFlowManager that the surface is at world Y = 10 m so swim /
	# breath physics work and the WaterChunkMesher can render it.
	#
	# Surface Y = sea_level_voxels (60) × terrain.transform.scale (1/6)
	# = 10 m world at the default scale. When the F5–F9 hotkeys cycle
	# scale, the surface moves with the terrain — the AABB stays fixed
	# in world space, so at smaller scales the water surface shifts to
	# the actual world-Y the generator's sea level renders at.
	# Re-applied on each scale change in _reseed_water_for_scale.
	if get_node_or_null("/root/WaterFlowManager"):
		_reseed_water_for_scale(_terrain_scale(terrain))

	# Snap the player above the terrain so they fall into the world
	# rather than spawning inside an island peak.
	call_deferred("_snap_player_above_terrain")


# Path of the player's working SQLite (matches the .tscn's
# VoxelStreamSQLite.database_path). Hardcoded here rather than
# read off the stream because we run BEFORE the stream resource
# initialises — the copy must happen first or the stream opens an
# empty file at the user:// path.
const WORKING_SQLITE_PATH: String = "user://copper_isles_test.sqlite"
const BAKED_BASELINE_PATH: String = "res://assets/voxel/copper_isles_baseline.sqlite"


func _seed_from_baseline_if_needed() -> void:
	# If the working DB already exists, leave it alone (player has a
	# game in progress; don't stomp on it).
	if FileAccess.file_exists(WORKING_SQLITE_PATH):
		return
	# If the baseline doesn't ship in this build, fall back to live
	# generation — silent, as this is the expected first-run state
	# before any bake has been done.
	if not FileAccess.file_exists(BAKED_BASELINE_PATH):
		return
	# Resolve to OS-absolute paths so DirAccess.copy_absolute can
	# bridge res:// → user:// (the high-level .copy() method refuses
	# cross-prefix copies).
	var src_abs: String = ProjectSettings.globalize_path(BAKED_BASELINE_PATH)
	var dst_abs: String = ProjectSettings.globalize_path(WORKING_SQLITE_PATH)
	# Make sure the user:// directory exists. ProjectSettings handles
	# the standard user-data dir creation, but a fresh OS account on
	# the very first run might not have it yet.
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		push_warning("[CopperIslesTest] user:// not accessible; skipping baseline seed.")
		return
	var err: int = DirAccess.copy_absolute(src_abs, dst_abs)
	if err == OK:
		var size_bytes: int = 0
		var f: FileAccess = FileAccess.open(WORKING_SQLITE_PATH, FileAccess.READ)
		if f != null:
			size_bytes = f.get_length()
			f.close()
		print("[CopperIslesTest] Seeded %s from baseline (%.1f MB)." % [
			WORKING_SQLITE_PATH, float(size_bytes) / (1024.0 * 1024.0),
		])
	else:
		push_warning("[CopperIslesTest] Failed to copy baseline (err=%d)." % err)


func _configure_voxel_format(terrain: Object) -> void:
	# Lifted from World3DBootstrap. See that file for the long-form
	# explanation — short version: we instantiate VoxelFormat, force
	# CHANNEL_COLOR to DEPTH_32_BIT, and assign it BEFORE the terrain
	# starts streaming.
	var fmt: Resource = null
	if ClassDB.class_exists("VoxelFormat"):
		fmt = ClassDB.instantiate("VoxelFormat")
	if fmt == null:
		push_warning("[CopperIslesTest] VoxelFormat class not found.")
		return
	if fmt.has_method("set_channel_depth"):
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_DATA5, VoxelBuffer.DEPTH_8_BIT)
	elif "color_depth" in fmt:
		fmt.set("color_depth", VoxelBuffer.DEPTH_32_BIT)
	elif "channel_depths" in fmt:
		var depths = fmt.get("channel_depths")
		if depths is Array:
			depths[VoxelBuffer.CHANNEL_COLOR] = VoxelBuffer.DEPTH_32_BIT
			fmt.set("channel_depths", depths)
	terrain.set("format", fmt)


func _terrain_scale(terrain: Node3D) -> float:
	return terrain.transform.basis.get_scale().x


# Sea level + peak-elevation constants for player-spawn and water-
# horizon math. These mirror the defaults baked into
# `assets/voxel/copper_isles_generator.tres` — keep them in sync if
# you tune the generator there. (Reading the values back off the live
# generator resource at runtime would be cleaner, but the property
# names are versioned and a stale read would silently put the player
# inside the islands; hardcoding here is the safer option for a dev
# scene.)
const GEN_SEA_LEVEL_VOXELS: float = 0.0
const GEN_PEAK_ABOVE_SEA_VOXELS: float = 15000.0


func _reseed_water_for_scale(scale: float) -> void:
	# Phase 5: AABB source regions are gone — water is per-voxel in
	# CHANNEL_DATA5, written by the generator. The only thing this
	# function still controls is the horizon plane Y, which scales
	# with terrain.transform.scale so a 1:1000 demo still shows water
	# at the right elevation.
	if not get_node_or_null("/root/WaterFlowManager"):
		return
	var sea_level_world_y: float = GEN_SEA_LEVEL_VOXELS * scale
	WaterFlowManager.set_horizon_plane_y(sea_level_world_y)


func _snap_player_above_terrain() -> void:
	# Drops the player just above the central island's actual peak,
	# sampled live from the generator. Falling from the
	# theoretically-highest-possible peak (~2500 m at scale 1/6, ~7500 m
	# at scale 0.5) wastes 5–10 s per scale change while the player
	# falls through unloaded chunks; sampling avoids that.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	var terrain := get_node_or_null(voxel_terrain_path) as Node3D
	if terrain == null:
		return
	var scale: float = _terrain_scale(terrain)
	var ground_voxels: float = (GEN_SEA_LEVEL_VOXELS + GEN_PEAK_ABOVE_SEA_VOXELS)
	var generator = terrain.get("generator") if "generator" in terrain else null
	if generator != null and generator.has_method("get_ground_voxel_y_at"):
		# Sample the column directly under spawn (world X=0, Z=0 maps
		# to the centre of the heightmap → middle island per the spec).
		ground_voxels = float(generator.call("get_ground_voxel_y_at", 0, 0))
	var spawn_y: float = ground_voxels * scale + SPAWN_HEIGHT_MARGIN_M
	player.global_position = Vector3(0.0, spawn_y, 0.0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


# =============================================================
# PUBLIC API — called by DebugOverlay's F7 scale-cycle hotkey
# =============================================================

func apply_terrain_scale(new_scale: float) -> void:
	# Applies a uniform scale to the VoxelLodTerrain transform, then
	# re-seeds water and snaps the player above the new highest peak.
	# No mesh rebuild is required — Zylann uses the node transform for
	# render scaling, so the same voxel data renders at the new size
	# immediately. Streaming radii (in voxels) stay the same; the
	# player perceives a different world-meters extent.
	var terrain := get_node_or_null(voxel_terrain_path) as Node3D
	if terrain == null:
		return
	var origin: Vector3 = terrain.transform.origin
	terrain.transform = Transform3D(Basis().scaled(Vector3.ONE * new_scale), origin)
	_reseed_water_for_scale(new_scale)
	_snap_player_above_terrain()
