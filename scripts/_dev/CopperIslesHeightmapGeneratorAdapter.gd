@tool
extends VoxelGeneratorScript
class_name CopperIslesHeightmapGeneratorAdapter

# CopperIslesHeightmapGeneratorAdapter — bridge between Zylann's
# VoxelLodTerrain (which calls _generate_block on a worker thread) and
# the C++ CopperIslesHeightmapGeneratorCpp Resource (which holds the
# actual inner loop).
#
# Mirrors CubicHeightmapGeneratorAdapter — same forwarding pattern.
# Bootstrap (CopperIslesTestBootstrap) calls set_ore_materials /
# set_disk_materials / get_ground_voxel_y_at duck-typed on this adapter;
# each is implemented here to translate VoxelMaterial → Dictionary
# (where needed) and forward to cpp_impl.

@export var cpp_impl: CopperIslesHeightmapGeneratorCpp

# Stub kept for backwards-compat with bootstrap code that did
# `gen.set("require_heightmap_in_editor_only", true)` to skip the EXR
# load in shipped builds. The C++ class always loads the EXR for now;
# adding a real opt-out is a future follow-up (low priority while the
# bake pipeline covers cold-start).
@export var require_heightmap_in_editor_only: bool = false


# Declare which VoxelBuffer channels the generator writes. Without this
# override Zylann assumes default-SDF and silently fails to allocate the
# channels VoxelMesherBlocky / WaterChunkMesher actually read — result:
# chunks render with the full atlas mapped onto each cube face (the
# white-with-dark-squares artifact). The C++ inner loop writes:
#   CHANNEL_TYPE   — material_id integers (for VoxelMesherBlocky)
#   CHANNEL_DATA5  — water source bytes  (for WaterChunkMesher)
# Mirror of the override on the retired CopperIslesHeightmapGenerator.gd
# (line 368 in the deleted file). Lives on the adapter because Zylann
# reads it from the script attached to the VoxelGeneratorScript — it has
# no view into cpp_impl. See LESSONS_LEARNED.md 2026-05-03 entry.
func _get_used_channels_mask() -> int:
	# Retained for completeness even though Zylann appears to ignore the
	# override on adapter-script-wrapped generators (verified empirically
	# 2026-05-12 — terrain.format CHANNEL_TYPE+DATA5 setup in the bootstrap
	# is what actually allocates the channels). Match the legacy GD
	# CopperIslesHeightmapGenerator.gd declaration for symmetry.
	return (1 << VoxelBuffer.CHANNEL_TYPE) | (1 << VoxelBuffer.CHANNEL_DATA5)


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if cpp_impl == null:
		push_warning("CopperIslesHeightmapGeneratorAdapter: no cpp_impl assigned; emitting air")
		return
	cpp_impl.generate_block_into_buffer(out_buffer, origin_in_voxels, lod)


# --- Translator setters mirroring CopperIslesHeightmapGenerator.gd ---
#
# Bootstrap pattern (unchanged from the cubic adapter):
#   if gen.has_method("set_ore_materials"):
#       gen.call("set_ore_materials", VoxelMaterialRegistry.get_ore_materials())

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


# Bake controller + bootstrap spawn-snap call this duck-typed.
func get_ground_voxel_y_at(world_x: int, world_z: int) -> int:
	if cpp_impl == null:
		return 0
	return cpp_impl.get_ground_voxel_y_at(world_x, world_z)


# NoEditZone water-AABB push (called by CopperIslesTestBootstrap and the
# World3DBootstrap-pattern). Dropped during the cubic port; same drop
# applies here. Stub keeps the bootstrap's `has_method` gate happy if
# any caller checks for it explicitly.
func set_no_edit_water_aabbs(_aabbs: Array[AABB]) -> void:
	pass
