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

	# Configure the terrain's CHANNEL_COLOR storage depth to 32-bit.
	# Default is 8-bit (1 byte per voxel), which truncates our packed
	# RGBA+mat_id values to just the R byte. The right knob lives on
	# VoxelLodTerrain.format — a VoxelFormat resource that's null by
	# default. We instantiate it, override the channel depth, and
	# assign it BEFORE the terrain starts streaming chunks.
	if "format" in terrain:
		_configure_voxel_format(terrain)

	# DIAGNOSTIC — dump every public property on VoxelLodTerrain so we
	# can hunt for a "max mesh blocks applied per frame" or similar
	# setting. The earlier filtered dump only showed depth/format/
	# channel/block matches; the lag investigation now needs a wider
	# net (anything that controls streaming pacing, threading, view
	# distance, queue caps, etc.).
	print("[World3D] Full VoxelLodTerrain property dump:")
	for prop in terrain.get_property_list():
		var p_name: String = prop.get("name", "")
		if p_name == "" or p_name.begins_with("script") or p_name == "resource_local_to_scene":
			continue
		if p_name == "resource_path" or p_name == "resource_name":
			continue
		# Skip uninteresting Node-level properties (transform, visibility,
		# editor scaffolding) — those don't have streaming-perf relevance.
		if p_name in ["transform", "global_transform", "visible",
				"position", "rotation", "scale", "rotation_order",
				"top_level", "metadata", "owner", "name",
				"unique_name_in_owner", "process_priority",
				"editor_description", "process_mode", "_import_path",
				"multiplayer", "physics_interpolation_mode"]:
			continue
		print("[World3D]   terrain.%s = %s" % [p_name, terrain.get(p_name)])

	if "mesher" in terrain:
		var mesher: Resource = terrain.mesher
		if mesher != null:
			print("[World3D] Mesher class: %s" % mesher.get_class())
			# Highlight opaque_material specifically — this is the
			# property that controls whether vertex colours reach
			# the rendered terrain. If it's null at runtime despite
			# the .tscn assignment, Godot didn't reimport the scene
			# or the property name is being silently rejected.
			var om = mesher.get("opaque_material") if "opaque_material" in mesher else null
			if om == null:
				print("[World3D]   ⚠ opaque_material is NULL (vertex colours WILL fall back to default — flat grey).")
			else:
				print("[World3D]   ✓ opaque_material is set: %s, vertex_color_use_as_albedo=%s" % [
					om.get_class(),
					om.get("vertex_color_use_as_albedo") if "vertex_color_use_as_albedo" in om else "(no such property)",
				])
			for prop in mesher.get_property_list():
				var pname: String = prop.get("name", "")
				if pname == "" or pname.begins_with("script") or pname == "resource_local_to_scene":
					continue
				if pname == "resource_path" or pname == "resource_name":
					continue
				print("[World3D]   mesher.%s = %s" % [pname, mesher.get(pname)])

	# Same dump for VoxelStreamSQLite so we can find the right
	# property name for full-caching mode. With save_generator_output
	# = true in the .tscn, the cache file should grow into MBs as
	# the player explores. If it's stuck at 20 KB (only edit deltas),
	# the property name is wrong for this Zylann build.
	if "stream" in terrain:
		var stream: Resource = terrain.stream
		if stream != null:
			print("[World3D] Stream class: %s" % stream.get_class())
			for prop in stream.get_property_list():
				var pname: String = prop.get("name", "")
				if pname == "" or pname.begins_with("script") or pname == "resource_local_to_scene":
					continue
				if pname == "resource_path" or pname == "resource_name":
					continue
				print("[World3D]   stream.%s = %s" % [pname, stream.get(pname)])

	# Guard with get_node_or_null in case the autoload isn't registered
	# yet (e.g. a fresh project without our autoload entries). The
	# project should always have it registered, but this prevents a
	# crash if something is misconfigured.
	if get_node_or_null("/root/VoxelEditManager"):
		VoxelEditManager.set_terrain(terrain)
		print("[World3D] Voxel terrain handed to VoxelEditManager.")
	else:
		push_warning("[World3D] VoxelEditManager autoload not registered; voxel edits will not work.")

	# --- Seed water source regions ---
	# Replace the old WaterVolume_Test and OceanVolume Area3D scenes
	# (deleted in the voxel-water refactor) with WaterFlowManager source
	# regions. Source regions are AABBs — O(1) memory regardless of size,
	# so a 200×200 m ocean costs nothing extra.
	#
	# Test pond: 10×3×10 m centered at world (-18, 0, 4), surface at
	# Y=1.5. Visible animated surface arrives in Phase 2 with the
	# WaterChunkMesher. Phase 1 only registers the region for swim/
	# breath physics queries.
	#
	# Ocean: massive XZ footprint so the surface continuously fills
	# every basin within the playable area. Was 200×200 m centred on
	# origin → terrain past X=±100 / Z=±100 had no water even when
	# the ground dipped below sea level, producing a sharp vertical
	# "world edge" cutoff (looked like the lake just stopped). New
	# footprint is 20000×20000 m centred on origin — covers the
	# whole 12×10 km playable Mira and still costs O(1) memory
	# (source regions are AABBs, not voxel cells).
	#
	# Surface at Y=10. Generator caps terrain at ~Y=29 (max_ground_y)
	# and bottoms at ~Y=-9 (min_ground_y) given height_range_voxels=200
	# + height_offset=60 at terrain scale 1/6. So Y=10 floods low
	# basins, leaves highlands dry. Volume extends 200 m below
	# surface so deep dive still registers as submerged.
	const OCEAN_SURFACE_Y: float = 10.0
	const OCEAN_DEPTH_M: float   = 200.0
	const OCEAN_HALF_SIZE_M: float = 10000.0  # ±10 km
	if get_node_or_null("/root/WaterFlowManager"):
		var pond_aabb := AABB(Vector3(-23.0, -1.5, -1.0), Vector3(10.0, 3.0, 10.0))
		WaterFlowManager.add_source_region(pond_aabb)
		var ocean_aabb := AABB(
			Vector3(-OCEAN_HALF_SIZE_M, OCEAN_SURFACE_Y - OCEAN_DEPTH_M, -OCEAN_HALF_SIZE_M),
			Vector3(OCEAN_HALF_SIZE_M * 2.0, OCEAN_DEPTH_M, OCEAN_HALF_SIZE_M * 2.0),
		)
		WaterFlowManager.add_source_region(ocean_aabb)
		print("[World3D] Seeded WaterFlowManager with %d source regions (ocean surface Y=%.1f, footprint ±%.0f m)." % [
			2, OCEAN_SURFACE_Y, OCEAN_HALF_SIZE_M,
		])
	else:
		push_warning("[World3D] WaterFlowManager autoload not registered; water disabled.")

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
		else:
			# Fresh New Game (no saved position) — snap player to the
			# top of whatever terrain exists at his X,Z spawn rather
			# than letting him fall from the scene's default Y=120.
			# Falling 100+ m through unloaded chunks looks bad and
			# wastes the first few seconds of play. Retry every
			# 0.2 s for up to 5 s while terrain streams in.
			call_deferred("_snap_spawn_to_ground")


func _configure_voxel_format(terrain: Object) -> void:
	# Set CHANNEL_COLOR depth to 32-bit so our packed RGBA + mat_id
	# values survive storage. Default is 8-bit (1 byte per voxel),
	# which truncates to just the R byte and loses both the rest of
	# the color and the material id.
	#
	# The knob is VoxelLodTerrain.format — a VoxelFormat resource
	# that's null by default. We construct one, override the
	# CHANNEL_COLOR depth, and assign it BEFORE the terrain starts
	# streaming chunks. Per-block set_channel_depth in _generate_block
	# was tried and confirmed to break generation entirely (terrain
	# disappears) — the global format resource is the right path.
	#
	# The exact API of VoxelFormat depends on the Zylann build. We
	# probe a couple of common patterns: a method (set_channel_depth)
	# or an array property (channel_depths). One should work.
	var fmt: Resource = null
	if ClassDB.class_exists("VoxelFormat"):
		fmt = ClassDB.instantiate("VoxelFormat")
	if fmt == null:
		push_warning("[World3D] VoxelFormat class not found; CHANNEL_COLOR will stay at 8-bit and mining will be broken.")
		return

	print("[World3D] VoxelFormat created: %s" % fmt.get_class())
	# Dump every property of the new format so we can see the API
	# surface and pick the right knob if our guesses miss.
	for prop in fmt.get_property_list():
		var pname: String = prop.get("name", "")
		if pname == "" or pname.begins_with("script") or pname == "resource_local_to_scene":
			continue
		if pname == "resource_path" or pname == "resource_name":
			continue
		print("[World3D]   format.%s = %s" % [pname, fmt.get(pname)])

	var configured: bool = false

	# Path 1 — method-based API: VoxelFormat.set_channel_depth(channel, depth)
	if fmt.has_method("set_channel_depth"):
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
		print("[World3D] Set CHANNEL_COLOR depth via fmt.set_channel_depth(...)")
		configured = true

	# Path 2 — typed per-channel property: VoxelFormat.color_depth = X
	if not configured and "color_depth" in fmt:
		fmt.set("color_depth", VoxelBuffer.DEPTH_32_BIT)
		print("[World3D] Set CHANNEL_COLOR depth via fmt.color_depth")
		configured = true

	# Path 3 — array property indexed by channel
	if not configured and "channel_depths" in fmt:
		var depths = fmt.get("channel_depths")
		if depths is Array:
			depths[VoxelBuffer.CHANNEL_COLOR] = VoxelBuffer.DEPTH_32_BIT
			fmt.set("channel_depths", depths)
			print("[World3D] Set CHANNEL_COLOR depth via fmt.channel_depths[CHANNEL_COLOR]")
			configured = true

	if not configured:
		push_warning("[World3D] VoxelFormat exists but no known API path worked; CHANNEL_COLOR will stay at 8-bit.")

	# Assign the format BEFORE terrain begins generating blocks. The
	# property in our diagnostic dump showed up as `format`, so just
	# write to it. If the terrain has already started generating, this
	# may not retroactively fix existing chunks — fresh save / new game
	# may be needed for the depth to apply across the world.
	terrain.set("format", fmt)
	print("[World3D] terrain.format assigned.")


func _snap_spawn_to_ground(retries_remaining: int = 25) -> void:
	# Raycast straight down from a high point above the player and
	# place the player on whatever solid surface we hit. If the
	# raycast misses (terrain chunks not yet loaded), retry after
	# a short delay until either a hit lands or we run out of retries.
	#
	# `retries_remaining` defaults to 25 (× 0.2 s = 5 s total budget).
	# After that we give up — the player will fall from the scene's
	# default Y, which is ugly but never permanently stuck.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return

	# Cast from a high origin DOWN through the player's X,Z. Origin
	# above the scene's spawn Y (120) by another 100 m so we cover
	# any terrain peak. Cast down to Y = -200 (well below valley
	# floors) so we cover any depth.
	var origin: Vector3 = Vector3(player.global_position.x, 250.0, player.global_position.z)
	var dest: Vector3 = Vector3(player.global_position.x, -200.0, player.global_position.z)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, dest)
	# Exclude the player's own collision shape so we don't hit it.
	params.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(params)

	if hit.is_empty():
		# No terrain under spawn yet. Voxel chunks still streaming.
		if retries_remaining <= 0:
			print("[World3D] Spawn-snap gave up after retries; falling from default Y.")
			return
		# Retry after a short delay using a SceneTreeTimer (no scene
		# changes / signals needed).
		var timer: SceneTreeTimer = get_tree().create_timer(0.2)
		timer.timeout.connect(_snap_spawn_to_ground.bind(retries_remaining - 1))
		return

	# Hit something. Place player just above the hit point — capsule
	# is offset by 0.9 m (half-height) so we add a small margin to
	# avoid clipping into terrain on landing.
	var ground_y: float = hit["position"].y
	player.global_position = Vector3(
		player.global_position.x,
		ground_y + 1.0,  # 1 m above ground = capsule clears the surface
		player.global_position.z,
	)
	# Zero the player's vertical velocity so any momentum from the
	# previous-frame fall doesn't punch them back through the surface.
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	print("[World3D] Spawn snapped to ground at Y=%.2f (hit at %.2f)." % [
		player.global_position.y, ground_y,
	])


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
