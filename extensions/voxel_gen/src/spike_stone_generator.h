#pragma once

// SpikeStoneGenerator — Phase 0 spike, throwaway.
//
// Purpose: prove that a C++ class registered via this GDExtension can be
// instantiated as a Resource, configured from the editor, attached to a
// GDScript-side VoxelGeneratorScript adapter, and have its
// generate_block_into_buffer() method invoked on Zylann's worker pool with
// the per-chunk buffer + origin + lod.
//
// Behavior: fills CHANNEL_TYPE (channel 0 in Zylann's VoxelBuffer) with
// material id 1 (= "stone" in this project's VoxelMaterialRegistry) for
// every voxel in the buffer. No noise, no tiers. If the player sees a
// solid stone sphere around them in SpikeStoneTest.tscn, the integration
// works and the rest of the port can proceed.

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3i.hpp>

class SpikeStoneGenerator : public godot::Resource {
    GDCLASS(SpikeStoneGenerator, godot::Resource)

public:
    SpikeStoneGenerator();
    ~SpikeStoneGenerator();

    // The material id to write into CHANNEL_TYPE for every voxel.
    // Exposed so the spike can be re-tuned in the Inspector without rebuilding.
    void set_material_id(int p_id);
    int get_material_id() const;

    // Called by the GDScript adapter from _generate_block on Zylann's worker
    // pool. `out_buffer` is a Zylann VoxelBuffer; we talk to it via Variant
    // since godot-cpp has no native wrapper for Zylann's types.
    void generate_block_into_buffer(godot::Variant out_buffer,
                                    godot::Vector3i origin_in_voxels,
                                    int lod);

protected:
    static void _bind_methods();

private:
    int _material_id = 1;
};
