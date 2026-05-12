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
