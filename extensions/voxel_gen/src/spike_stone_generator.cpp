#include "spike_stone_generator.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// Channel index for CHANNEL_TYPE in Zylann's VoxelBuffer. Matches
// CLAUDE.md's note that terrain material id lives in CHANNEL_TYPE (channel 0).
// If Zylann ever renumbers, this constant moves; for the spike we hard-code it
// to keep the binding surface minimal.
static constexpr int CHANNEL_TYPE = 0;

SpikeStoneGenerator::SpikeStoneGenerator() {}
SpikeStoneGenerator::~SpikeStoneGenerator() {}

void SpikeStoneGenerator::set_material_id(int p_id) { _material_id = p_id; }
int SpikeStoneGenerator::get_material_id() const { return _material_id; }

void SpikeStoneGenerator::generate_block_into_buffer(Variant out_buffer,
                                                    Vector3i origin_in_voxels,
                                                    int lod) {
    // out_buffer is a Zylann VoxelBuffer. Discover its dimensions via the
    // exposed get_size() method (returns Vector3i). For Zylann, default
    // mesh block size is 16; lod scales the buffer extent.
    Variant size_v = out_buffer.call("get_size");
    if (size_v.get_type() != Variant::VECTOR3I) {
        UtilityFunctions::printerr(
                "SpikeStoneGenerator: out_buffer.get_size() did not return Vector3i");
        return;
    }
    Vector3i size = size_v;

    // Walk every voxel and write material_id into CHANNEL_TYPE.
    //
    // This is the slow path — one Variant call per voxel. The real generator
    // (Phase 2+) will use a bulk fill primitive. The spike intentionally uses
    // the slow path so the integration surface is as small as possible and
    // any failure is easy to attribute.
    for (int z = 0; z < size.z; ++z) {
        for (int y = 0; y < size.y; ++y) {
            for (int x = 0; x < size.x; ++x) {
                out_buffer.call("set_voxel", _material_id, x, y, z, CHANNEL_TYPE);
            }
        }
    }

    // One log line per chunk lets us confirm the worker pool is calling into
    // C++. Disable for Phase 2+ when the volume becomes too noisy.
    UtilityFunctions::print("SpikeStoneGenerator: filled chunk origin=",
                            origin_in_voxels, " size=", size, " lod=", lod,
                            " mat=", _material_id);
}

void SpikeStoneGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_material_id", "id"),
                         &SpikeStoneGenerator::set_material_id);
    ClassDB::bind_method(D_METHOD("get_material_id"),
                         &SpikeStoneGenerator::get_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "material_id"),
                 "set_material_id", "get_material_id");

    ClassDB::bind_method(
            D_METHOD("generate_block_into_buffer", "out_buffer", "origin_in_voxels", "lod"),
            &SpikeStoneGenerator::generate_block_into_buffer);
}
