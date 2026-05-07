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

## When true, the player is teleported to Player3D.SPAWN_POSITION on
## _ready (and after every F7 scale change). The actual coords live as
## a constant in scripts/Player3D.gd — that's the single source of
## truth for both this initial-spawn path AND the toggle_fly_mode
## reset path. Change there, both behaviours follow.
##
## When false, the bootstrap reverts to the dynamic spawn that samples
## the heightmap centre and drops the player above the actual ground.
@export var spawn_override_enabled: bool = true

## When true, immediately enable Player3D's fly mode after spawn so
## the camera doesn't fall off the peak. Player3D.gd exposes
## toggle_fly_mode(); we call it once at startup if requested.
@export var start_in_fly_mode: bool = true

# Vertical drop height for the player on first spawn (dynamic mode
# only — overridden when spawn_override_enabled is true).
const SPAWN_HEIGHT_MARGIN_M: float = 30.0


func _enter_tree() -> void:
	# CRITICAL ordering: this seed copy MUST happen before the
	# VoxelLodTerrain child opens its SQLite stream. Godot's _enter_tree
	# fires top-down (parent before children), whereas _ready fires
	# bottom-up (children before parent). If we did the copy in _ready,
	# Zylann would already have opened the empty/missing user:// file
	# and our copy would land too late — exactly the "39.7 MB on disk
	# but generator runs anyway" symptom we hit on first attempt.
	_seed_from_baseline_if_needed()


func _ready() -> void:
	# Mark this scene as a developer test scene so the gameplay UI
	# autoloads (HUDOverlay, PauseMenu, JournalUI, SaveNotification)
	# stay dormant. See GameState.is_dev_scene() for the contract.
	add_to_group("dev_scene")

	# Defensive belt-and-suspenders: even with the _enter_tree seed,
	# reassign the terrain.stream to a fresh VoxelStreamSQLite pointing
	# at the same path. Forces Zylann to re-open the file from a known
	# clean state. Costs nothing if the seed already worked; saves us
	# if the .tscn's stream resource was constructed before _enter_tree
	# fired (which can happen when scene resources cache aggressively).
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null:
		push_error("[CopperIslesTest] VoxelLodTerrain not found at: %s" % voxel_terrain_path)
		return

	# Force-reopen the stream against the (possibly newly-seeded) file.
	# We rebuild the resource rather than mutating the existing one so
	# Zylann's internal SQLite handle is fully torn down + reopened.
	# Carries forward the .tscn-defined settings so the .tscn stays the
	# source of truth for stream config.
	if "stream" in terrain:
		var old_stream: Resource = terrain.get("stream")
		if old_stream != null and old_stream is VoxelStreamSQLite:
			var fresh := VoxelStreamSQLite.new()
			fresh.database_path = old_stream.database_path
			fresh.save_generator_output = old_stream.save_generator_output
			if "preferred_coordinate_format" in old_stream:
				fresh.preferred_coordinate_format = old_stream.preferred_coordinate_format
			if "compression_mode" in old_stream:
				fresh.compression_mode = old_stream.compression_mode
			terrain.set("stream", fresh)
			# One-shot diagnostic — confirms the reopen happened with
			# the populated file. Compare bytes printed here with the
			# size of user://copper_isles_test.sqlite on disk.
			var f: FileAccess = FileAccess.open(fresh.database_path, FileAccess.READ)
			var sz: int = f.get_length() if f != null else 0
			if f != null:
				f.close()
			print("[CopperIslesTest] Reopened stream: %s (%d bytes on disk)" % [fresh.database_path, sz])

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

	# Belt-and-suspenders LOD enforcement (mirror of WorldBakeController).
	# These MUST match the bake scene or cached chunks are at the wrong
	# LOD coords. Set in script so Godot editor's silent .tscn property
	# normalisation can't break the cache contract.
	_enforce_lod_config(terrain)

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

	# Spawn the velocity / camera-aware lookahead VoxelViewer as a child
	# of the player. The base viewer in Player3D.tscn keeps its
	# omnidirectional 8000-vox bubble; this one adds a smaller, biased
	# bubble ahead of where the player is looking and moving, so chunks
	# along the heading load earlier when sprinting or riding. See
	# scripts/ForwardLookaheadViewer.gd for the per-frame blend rule.
	call_deferred("_spawn_lookahead_viewer")

	# Snap the player above the terrain so they fall into the world
	# rather than spawning inside an island peak.
	call_deferred("_snap_player_above_terrain")


func _spawn_lookahead_viewer() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# Don't double-spawn on hot reload or scale-change re-runs.
	if player.get_node_or_null("ForwardLookaheadViewer") != null:
		return
	var script: Script = load("res://scripts/ForwardLookaheadViewer.gd")
	if script == null:
		return
	var viewer: Node = script.new()
	viewer.name = "ForwardLookaheadViewer"
	player.add_child(viewer)


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


# Terrain config the runtime MUST run with. MUST stay in lockstep
# with REQUIRED_* constants in scripts/_dev/WorldBakeController.gd —
# changing one without the other corrupts the cache contract.
const REQUIRED_LOD_COUNT: int = 8
# 768 vox = 128 m world LOD0 radius at 6 vox/m. Sized for
# mountaintop-vista feel + fast walker bakes (180 m tile spacing).
# MUST match BakeWorld terrain config and the .tscn explicit values.
const REQUIRED_LOD_DISTANCE: float = 768.0
const REQUIRED_LOD_FADE_DURATION: float = 0.5


func _enforce_lod_config(terrain: Object) -> void:
	# Belt-and-suspenders LOD enforcement. Override the .tscn values so
	# Godot editor's silent property normalisation can't break the
	# bake/runtime cache contract. Prints any drift to Output.
	var fields: Array = [
		["lod_count", REQUIRED_LOD_COUNT],
		["lod_distance", REQUIRED_LOD_DISTANCE],
		["lod_fade_duration", REQUIRED_LOD_FADE_DURATION],
		["cache_generated_blocks", true],
	]
	for f in fields:
		var key: String = f[0]
		var want = f[1]
		if not key in terrain:
			push_warning("[CopperIslesTest] terrain has no property '%s' — Zylann version mismatch?" % key)
			continue
		var before = terrain.get(key)
		if before == want:
			continue
		terrain.set(key, want)
		print("[CopperIslesTest] enforced terrain.%s: %s → %s" % [key, before, want])


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
# Sea level moved to voxel-Y 720 (= world Y 120 m at scale 1/6). MUST
# match `sea_level_voxels` in assets/voxel/copper_isles_generator.tres.
const GEN_SEA_LEVEL_VOXELS: float = 720.0
const GEN_PEAK_ABOVE_SEA_VOXELS: float = 15000.0


func _reseed_water_for_scale(terrain_scale: float) -> void:
	# Phase 5: AABB source regions are gone — water is per-voxel in
	# CHANNEL_DATA5, written by the generator. The only thing this
	# function still controls is the horizon plane Y, which scales
	# with terrain.transform.scale so a 1:1000 demo still shows water
	# at the right elevation.
	#
	# Parameter renamed from `scale` → `terrain_scale` to dodge the
	# Node3D.scale property shadow warning (this script's class
	# extends Node3D).
	if not get_node_or_null("/root/WaterFlowManager"):
		return
	var sea_level_world_y: float = GEN_SEA_LEVEL_VOXELS * terrain_scale
	WaterFlowManager.set_horizon_plane_y(sea_level_world_y)
	# Tell WaterChunkMesher (via the manager) which voxel-Y row to
	# scan for the ocean surface mesh. Default is Mira's 72; Copper
	# Isles needs 720 or the mesher misses every water chunk.
	if WaterFlowManager.has_method("set_sea_level_voxel_y"):
		WaterFlowManager.set_sea_level_voxel_y(int(GEN_SEA_LEVEL_VOXELS))


func _snap_player_above_terrain() -> void:
	# Two modes — see the @export comments at the top of the script:
	#   spawn_override_enabled = true:  hard-coded position, fly mode
	#                                   on, no terrain sampling.
	#   spawn_override_enabled = false: dynamic spawn above the
	#                                   heightmap centre (legacy).
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D

	if spawn_override_enabled:
		# Engage fly mode first — toggle_fly_mode() now ALSO teleports
		# to Player3D.SPAWN_POSITION as part of its reset behaviour
		# (shared single source of truth, see Player3D.SPAWN_POSITION
		# const). So engaging fly here puts the player exactly where
		# we want them. The explicit assignment below is redundant
		# when fly mode runs but kept as defence for the
		# start_in_fly_mode = false case.
		if start_in_fly_mode and player.has_method("toggle_fly_mode"):
			var already_flying: bool = "is_flying" in player and bool(player.get("is_flying"))
			if not already_flying:
				player.call("toggle_fly_mode")
		player.global_position = Player3D.SPAWN_POSITION
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
		return

	# --- Dynamic spawn (no override) ---
	var terrain := get_node_or_null(voxel_terrain_path) as Node3D
	if terrain == null:
		return
	# Local renamed `scale` → `terrain_scale` to dodge the Node3D.scale
	# property shadow warning.
	var terrain_scale: float = _terrain_scale(terrain)
	var ground_voxels: float = (GEN_SEA_LEVEL_VOXELS + GEN_PEAK_ABOVE_SEA_VOXELS)
	var generator = terrain.get("generator") if "generator" in terrain else null
	if generator != null and generator.has_method("get_ground_voxel_y_at"):
		# Sample the column directly under spawn (world X=0, Z=0 maps
		# to the centre of the heightmap → middle island per the spec).
		ground_voxels = float(generator.call("get_ground_voxel_y_at", 0, 0))
	var spawn_y: float = ground_voxels * terrain_scale + SPAWN_HEIGHT_MARGIN_M
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
