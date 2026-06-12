@tool
extends VoxelGeneratorScript
class_name CubicHeightmapGeneratorAdapter

# CubicHeightmapGeneratorAdapter — Phase 2 bridge.
#
# Mirror of SpikeStoneGeneratorAdapter, but pointing at the real
# CubicHeightmapGeneratorCpp class. Zylann's VoxelLodTerrain still
# wants to call into a GDScript-side VoxelGeneratorScript subclass
# (godot-cpp can't subclass it directly without engine-side bindings),
# so this thin adapter is the actual node-tree-visible generator.
# All work happens in the C++ resource referenced by cpp_impl.
#
# Wire-up in a .tscn:
#   1. Set the VoxelLodTerrain's `generator` to a SubResource of this
#      adapter type.
#   2. Set the adapter's `cpp_impl` to a SubResource of
#      CubicHeightmapGeneratorCpp, configured with the same noise +
#      height params you would on the legacy GDScript generator.
#
# This adapter exists during Phases 2-5 of the port. Phase 6 retires
# the legacy GD generator and may collapse this adapter as well if
# Zylann gains a path for direct C++ subclassing.

@export var cpp_impl: CubicHeightmapGeneratorCpp


# Declare which VoxelBuffer channels the C++ inner loop writes. Without
# this override Zylann assumes default-SDF and may silently fail to
# allocate the channels the mesher reads — manifesting as full-atlas
# UVs on cube faces (the white-with-dark-squares artifact). The cubic
# generator's symptoms were quieter than Copper Isles' but the bug was
# the same; declare the mask explicitly. See LESSONS_LEARNED.md
# 2026-05-03 entry on `_get_used_channels_mask`.
func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_TYPE) | (1 << VoxelBuffer.CHANNEL_DATA5)


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if cpp_impl == null:
		push_warning("CubicHeightmapGeneratorAdapter: no cpp_impl assigned; emitting air")
		return
	cpp_impl.generate_block_into_buffer(out_buffer, origin_in_voxels, lod)


# --- Phase 4d snapshot translators -----------------------------------
#
# The World3DBootstrap / CopperIslesTestBootstrap pattern is
#   if gen.has_method("set_ore_materials"):
#       gen.call("set_ore_materials", VoxelMaterialRegistry.get_ore_materials())
#
# The bootstrap doesn't know whether `gen` is the GDScript generator or
# this C++ adapter, so we expose the same method names here. We
# translate Array[VoxelMaterial] into Array[Dictionary] (plain data the
# C++ side can parse without reaching into VoxelMaterial.gd) and forward
# to the C++ resource.
#
# Called on the main thread before terrain streaming starts. Worker
# threads then iterate the std::vector that lives inside cpp_impl
# without touching the SceneTree.

func set_ore_materials(list: Array[VoxelMaterial]) -> void:
	if cpp_impl == null:
		return
	var translated: Array = []
	translated.resize(list.size())
	for i in list.size():
		var m: VoxelMaterial = list[i]
		translated[i] = {
			"material_id": m.material_id,
			"replaces_material_id": m.replaces_material_id,
			"min_altitude_voxels": m.min_altitude_voxels,
			"max_altitude_voxels": m.max_altitude_voxels,
			"ore_noise_threshold": m.ore_noise_threshold,
			"ore_noise_scale": m.ore_noise_scale,
		}
	cpp_impl.set_ore_materials(translated)


func set_disk_materials(list: Array[VoxelMaterial]) -> void:
	if cpp_impl == null:
		return
	var translated: Array = []
	translated.resize(list.size())
	for i in list.size():
		var m: VoxelMaterial = list[i]
		translated[i] = {
			"material_id": m.material_id,
			"disk_radius_voxels": m.disk_radius_voxels,
			"disk_half_height_voxels": m.disk_half_height_voxels,
			"disk_anchor_density": m.disk_anchor_density,
			"disk_max_distance_to_water_voxels": m.disk_max_distance_to_water_voxels,
		}
	cpp_impl.set_disk_materials(translated)


# R4 — wire the three flora CHANNEL_TYPE ids into the C++ scatter. The
# bootstrap calls this duck-typed off the terrain's generator at startup
# (same pattern as set_ore_materials). Passing the registry ids here keeps
# the generator decoupled from FloraMaterial — if a flora id ever moves,
# the bootstrap reads the new value and re-pushes it; nothing in C++ hard-
# codes 24/25/26. Default 0 (the C++ default) means "scatter disabled", so
# a stale build / missing wire-up simply grows no flora rather than writing
# garbage ids into the terrain.
func set_flora_materials(grass_blade_id: int, flower_red_id: int, flower_blue_id: int) -> void:
	if cpp_impl == null:
		return
	cpp_impl.set("grass_blade_material_id", grass_blade_id)
	cpp_impl.set("flower_red_material_id", flower_red_id)
	cpp_impl.set("flower_blue_material_id", flower_blue_id)


# D1 — wire the two surface-detail (pebble/twig) CHANNEL_TYPE ids into the
# C++ scatter. Same duck-typed bootstrap pattern + 0-default-disabled
# rationale as set_flora_materials above. Nothing in C++ hardcodes 27/28;
# the bootstrap reads them from FloraMaterial and pushes them here.
func set_surface_detail_materials(pebble_id: int, twig_id: int) -> void:
	if cpp_impl == null:
		return
	cpp_impl.set("pebble_material_id", pebble_id)
	cpp_impl.set("twig_material_id", twig_id)


# TREES — wire the log + leaves CHANNEL_TYPE ids into the C++ tree scatter.
# Same duck-typed bootstrap pattern + 0-default-disabled rationale as the
# flora/surface-detail wirers above: until the bootstrap calls this the C++
# tree ids are 0, so the generator (and the legacy `gen` baseline path) emits
# no trees. Nothing in C++ hardcodes 10/11; the bootstrap reads the ids from
# the VoxelMaterialRegistry and pushes them here.
func set_tree_materials(log_id: int, leaves_id: int) -> void:
	if cpp_impl == null:
		return
	cpp_impl.set("tree_log_material_id", log_id)
	cpp_impl.set("tree_leaves_material_id", leaves_id)


# --- Biome framework forwarders --------------------------------------
#
# The World3DBootstrap BIOME FRAMEWORK block calls these duck-typed off the
# terrain's generator (same pattern as set_ore_materials). The adapter
# flattens Array[BiomeProfile] into Array[Dictionary] PODs (worker-thread-
# safe plain data the C++ side parses without reaching into BiomeProfile.gd)
# and forwards to the C++ resource. With NO profiles ever pushed the C++
# generator stays on its legacy single-recipe path (biome_active() false).

func set_biome_profiles(list: Array) -> void:
	if cpp_impl == null:
		return
	var translated: Array = []
	translated.resize(list.size())
	for i in list.size():
		var p = list[i]
		# Accept either a BiomeProfile resource (has to_pod_dict) or an
		# already-flattened Dictionary (lets the gate push raw PODs).
		if p != null and p.has_method("to_pod_dict"):
			translated[i] = p.to_pod_dict()
		elif p is Dictionary:
			translated[i] = p
		else:
			translated[i] = {}
	cpp_impl.call("set_biome_profiles", translated)


func set_biome_field_params(control_frequency_per_m: float, warp_frequency_per_m: float,
		warp_strength: float, blend_margin: float, voxels_per_metre: float,
		plains_index: int, hills_index: int, forest_index: int,
		desert_index: int, mountains_index: int) -> void:
	if cpp_impl == null:
		return
	cpp_impl.call("set_biome_field_params", control_frequency_per_m, warp_frequency_per_m,
		warp_strength, blend_margin, voxels_per_metre,
		plains_index, hills_index, forest_index, desert_index, mountains_index)


func set_biome_control_noise(noise: FastNoiseLite) -> void:
	if cpp_impl == null:
		return
	cpp_impl.call("set_biome_control_noise", noise)


# The bake controller (scripts/_dev/WorldBakeController.gd) calls this
# duck-typed off the terrain's generator during tile classification.
# CopperIslesHeightmapGenerator defines it; the GDScript Cubic generator
# does not. We forward to cpp_impl so the bake works against this adapter
# without controller-side knowledge of which generator is attached.
func get_ground_voxel_y_at(world_x: int, world_z: int) -> int:
	if cpp_impl == null:
		return 0
	return cpp_impl.get_ground_voxel_y_at(world_x, world_z)
