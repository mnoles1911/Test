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

	# Configure the terrain's CHANNEL_TYPE storage depth. After the v13
	# VoxelMesherBlocky migration we store material_id directly in
	# CHANNEL_TYPE — 8-bit is sufficient (material_id range 0-254).
	# Default depth for TYPE is already 8-bit, but we set it explicitly
	# so the format is documented in code rather than implicit.
	if "format" in terrain:
		_configure_voxel_format(terrain)

	# Move per-edit voxel-block updates off the main thread.
	# `threaded_update_enabled` defaults to FALSE in this Zylann
	# build, which is what made `tool.do_box(...)` cost ~37 ms per
	# 3×3×3 mining swing — the mesh rebuild for the affected mesh
	# blocks ran synchronously on the main thread and was the
	# entirety of the [SPIKE _apply_edit total=37 ms (carve=37 ms)]
	# we just measured. Turning it on offloads the work to a worker.
	if "threaded_update_enabled" in terrain:
		terrain.set("threaded_update_enabled", true)
		print("[World3D] terrain.threaded_update_enabled = true")
	# Defer collision-shape rebuilds so they batch instead of firing
	# on every single edit. 0.1 s is imperceptible to the player
	# (they're not pressed flush against the carved face within 100
	# ms of breaking it), and it lets Zylann coalesce multiple
	# edits' collision updates. Default 0 means rebuild-immediately,
	# which is the worst case for stutter.
	if "collision_update_delay" in terrain:
		terrain.set("collision_update_delay", 0.1)
		print("[World3D] terrain.collision_update_delay = 0.1")

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
			# Runtime fix for a Zylann gdextension serialization bug:
			# VoxelBlockyModelCube's per-surface `material_override_0`
			# saves into blocky_library.tres but doesn't restore on load
			# (get_material_override(0) returns null at runtime even
			# though the .tres clearly carries the SubResource ref).
			# Workaround: load the atlas texture, build a fresh shared
			# StandardMaterial3D, and inject it into every cube model's
			# surface 0 right now. Tile coords serialize/restore fine,
			# so only the materials need this round-trip bypass.
			_inject_atlas_materials_into_library(mesher)

			print("[World3D] Mesher class: %s" % mesher.get_class())
			# Verify the blocky library's first cube model has an
			# atlas material attached. In Zylann's current API,
			# materials live on each VoxelBlockyModelCube and are
			# accessed via get_material_override(surface_idx) — the
			# `material_override_0` listed in get_property_list() is
			# a dynamic per-surface property name and the `in`
			# operator returns false for it even when the property
			# really exists. Use the method directly to avoid that.
			var lib: Resource = mesher.get("library") if "library" in mesher else null
			if lib != null and "models" in lib:
				var models_arr: Array = lib.get("models")
				var first_solid = null
				for m in models_arr:
					if m != null:
						first_solid = m
						break
				if first_solid != null and first_solid.has_method("get_material_override"):
					var mat0 = first_solid.call("get_material_override", 0)
					if mat0 == null:
						print("[World3D]   ⚠ blocky library model[0] has no material_override(0) — re-run tools/build_blocky_library.gd.")
					else:
						var has_tex: bool = false
						if mat0 is BaseMaterial3D:
							has_tex = (mat0 as BaseMaterial3D).albedo_texture != null
						print("[World3D]   ✓ blocky library model[0].material = %s (albedo_texture=%s)" % [
							mat0.get_class(), "yes" if has_tex else "MISSING"
						])
				else:
					print("[World3D]   ⚠ blocky library has no usable first model.")
			else:
				print("[World3D]   ⚠ mesher has no library — wire it in World3D.tscn.")
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
	# basins, leaves highlands dry.
	#
	# OCEAN_DEPTH_M was 200 m, which was nonsense — the AABB extended
	# almost to the bedrock floor. WaterFlowManager.is_position_in_water
	# now uses a clear-vertical-path check that prevents tunnel
	# flooding even with a deep AABB, but a tighter AABB is still good
	# defence-in-depth (and a bit faster: no clear-path call needed
	# for queries below the AABB bottom). 18 m extends from Y=-8 to
	# Y=10, fully covering all natural sub-sea-level terrain
	# (min_ground_y ≈ -7) plus a small buffer.
	const OCEAN_SURFACE_Y: float = 10.0
	const OCEAN_DEPTH_M: float   = 18.0
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


const _ATLAS_TEXTURE_PATH: String = "res://assets/voxels/texture_packs/default/atlas.png"


func _inject_atlas_materials_into_library(mesher: Resource) -> void:
	# See call site for the why. Build the shared atlas material once
	# and pin it to every cube model's surface 0. Tile coords already
	# survived the .tres round-trip; only the material is missing.
	var lib: Resource = mesher.get("library") if "library" in mesher else null
	if lib == null:
		print("[World3D]   ⚠ inject_atlas_materials: no library on mesher.")
		return

	var atlas_tex: Texture2D = load(_ATLAS_TEXTURE_PATH) as Texture2D
	if atlas_tex == null:
		printerr("[World3D]   ⚠ inject_atlas_materials: failed to load %s" % _ATLAS_TEXTURE_PATH)
		return

	var atlas_mat: StandardMaterial3D = StandardMaterial3D.new()
	atlas_mat.resource_name = "atlas_default_runtime"
	atlas_mat.albedo_texture = atlas_tex
	atlas_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	atlas_mat.alpha_scissor_threshold = 0.5
	atlas_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	atlas_mat.roughness = 0.85
	atlas_mat.metallic = 0.0
	atlas_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	if not "models" in lib:
		print("[World3D]   ⚠ inject_atlas_materials: library has no models array.")
		return
	var models_arr: Array = lib.get("models")
	var injected: int = 0
	for m in models_arr:
		if m == null:
			continue
		if m.has_method("set_material_override"):
			m.call("set_material_override", 0, atlas_mat)
			injected += 1

	# Re-bake so Zylann recomputes whatever per-material LUTs it
	# caches off model materials.
	if lib.has_method("bake"):
		lib.bake()

	print("[World3D] inject_atlas_materials: assigned atlas to %d models, library re-baked." % injected)


func _configure_voxel_format(terrain: Object) -> void:
	# Set CHANNEL_TYPE depth to 8-bit. After the v13 migration to
	# VoxelMesherBlocky we store the material_id directly in TYPE,
	# which fits in a single byte (0-254 is the valid range).
	#
	# 8-bit is the Zylann default for TYPE so this is mostly defensive
	# documentation — but we still set it explicitly because (a) older
	# saves may have a stored format with COLOR depth pinned to 32-bit
	# from the pre-v13 era, and (b) being explicit makes the file
	# easier to find via grep when something goes wrong.
	#
	# The exact API of VoxelFormat depends on the Zylann build. We
	# probe a couple of common patterns: a method (set_channel_depth)
	# or an array property (channel_depths). One should work.
	var fmt: Resource = null
	if ClassDB.class_exists("VoxelFormat"):
		fmt = ClassDB.instantiate("VoxelFormat")
	if fmt == null:
		# No VoxelFormat — pre-v13 builds didn't need this either, the
		# defaults (8-bit TYPE) are correct. Skip silently.
		return

	var configured: bool = false

	# Path 1 — method-based API: VoxelFormat.set_channel_depth(channel, depth)
	if fmt.has_method("set_channel_depth"):
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_8_BIT)
		print("[World3D] Set CHANNEL_TYPE depth via fmt.set_channel_depth(...)")
		configured = true

	# Path 2 — typed per-channel property: VoxelFormat.type_depth = X
	if not configured and "type_depth" in fmt:
		fmt.set("type_depth", VoxelBuffer.DEPTH_8_BIT)
		print("[World3D] Set CHANNEL_TYPE depth via fmt.type_depth")
		configured = true

	# Path 3 — array property indexed by channel
	if not configured and "channel_depths" in fmt:
		var depths = fmt.get("channel_depths")
		if depths is Array:
			depths[VoxelBuffer.CHANNEL_TYPE] = VoxelBuffer.DEPTH_8_BIT
			fmt.set("channel_depths", depths)
			print("[World3D] Set CHANNEL_TYPE depth via fmt.channel_depths[CHANNEL_TYPE]")
			configured = true

	if not configured:
		# Defaults are 8-bit on TYPE, so missing API path isn't fatal.
		return

	terrain.set("format", fmt)
	print("[World3D] terrain.format assigned (CHANNEL_TYPE 8-bit).")


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
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	print("[World3D] Restored player position to %s, rotation_y=%.2f rad" % [
		GameState.player_position, GameState.player_rotation_y
	])

	# Freeze physics until terrain has streamed in below the saved
	# position. Without this freeze, gravity pulls Roland straight
	# through unloaded chunks — by the time voxel collision arrives,
	# he's hundreds of metres below the world. _wait_for_ground_under_player
	# raycasts every 0.2 s; once it finds floor, it unfreezes the player
	# (who then settles onto the actual surface in a frame or two).
	if "_spawn_freeze" in player:
		player.set("_spawn_freeze", true)
	_wait_for_ground_under_player()


func _wait_for_ground_under_player(retries_remaining: int = 25) -> void:
	# Casts a short ray downward from the player to confirm a voxel
	# collider exists below. While terrain is still streaming, the ray
	# misses and we retry every 0.2 s (× 25 = 5 s budget). Once it
	# hits, we clear the spawn-freeze flag and let normal physics run.
	#
	# We don't snap the player to the hit — the saved position is the
	# ground truth (the player WAS standing somewhere when they saved).
	# The natural settle from "saved Y" to "actual collider Y" is
	# usually a fraction of a metre and physics handles it cleanly.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return

	# Ray spans from 1 m above the player down 100 m. 1 m up gives the
	# capsule centre clearance so we don't start inside the player's
	# own collider; 100 m down covers any plausible drop including
	# tall caves and surface-to-ocean-floor distances.
	var origin: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var dest: Vector3 = player.global_position + Vector3(0, -100.0, 0)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, dest)
	params.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(params)

	if hit.is_empty():
		if retries_remaining <= 0:
			# Out of retries — unfreeze anyway so the player isn't
			# permanently stuck. Better to fall through the void with
			# gravity than to be locked in place forever.
			print("[World3D] Saved-position ground check timed out; unfreezing player.")
			if "_spawn_freeze" in player:
				player.set("_spawn_freeze", false)
			return
		var timer: SceneTreeTimer = get_tree().create_timer(0.2)
		timer.timeout.connect(_wait_for_ground_under_player.bind(retries_remaining - 1))
		return

	# Ground confirmed. Unfreeze and let physics take it from here.
	if "_spawn_freeze" in player:
		player.set("_spawn_freeze", false)
	print("[World3D] Saved-position ground confirmed at Y=%.2f; unfreezing player." % hit["position"].y)
