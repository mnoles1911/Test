@tool
extends VoxelGeneratorScript
class_name SpikeStoneGeneratorAdapter

# SpikeStoneGeneratorAdapter — Phase 0 spike bridge, throwaway.
#
# Why this exists in plain English:
#
# Zylann's VoxelGeneratorScript is a GDScript-side base class. Subclassing it
# directly from a C++ GDExtension is fragile because godot-cpp only ships
# wrapper headers for engine-core classes, not for third-party extension
# classes like VoxelGeneratorScript itself. The clean way to keep the heavy
# work in C++ is to put it in a plain Resource (which godot-cpp DOES wrap)
# and have a thin GDScript class extend VoxelGeneratorScript and call
# straight into the C++ Resource per chunk.
#
# That is what this script does. The override _generate_block is the real
# Zylann entry point; it delegates everything to `cpp_impl.generate_block_into_buffer`,
# which is the C++ implementation.
#
# Phase 0 success criterion: open scenes/_dev/SpikeStoneTest.tscn in Godot
# and see a solid stone sphere around the spawn point. That proves the chain
# end-to-end:
#     Zylann worker pool -> _generate_block (GDScript) -> generate_block_into_buffer (C++)
#                       -> Variant calls back into the Zylann VoxelBuffer (set_voxel)
#                       -> mesh build by VoxelMesherBlocky
#                       -> on screen.
#
# If you see white / textureless voxels, the material id is being written
# correctly but the test scene isn't wired to a VoxelBlockyLibrary — that's
# expected for the spike. The Output panel should print one
# "SpikeStoneGenerator: filled chunk ..." line per streamed chunk.

@export var cpp_impl: SpikeStoneGenerator

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if cpp_impl == null:
		# Print once per chunk so we notice the misconfiguration without
		# spamming hundreds of lines.
		push_warning("SpikeStoneGeneratorAdapter: no cpp_impl assigned; emitting air")
		return
	cpp_impl.generate_block_into_buffer(out_buffer, origin_in_voxels, lod)
