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


# The bake controller (scripts/_dev/WorldBakeController.gd) calls this
# duck-typed off the terrain's generator during tile classification.
# CopperIslesHeightmapGenerator defines it; the GDScript Cubic generator
# does not. We forward to cpp_impl so the bake works against this adapter
# without controller-side knowledge of which generator is attached.
func get_ground_voxel_y_at(world_x: int, world_z: int) -> int:
	if cpp_impl == null:
		return 0
	return cpp_impl.get_ground_voxel_y_at(world_x, world_z)
