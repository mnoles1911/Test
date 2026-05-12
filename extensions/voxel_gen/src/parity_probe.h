#pragma once

// ParityProbe -- Godot-registered shim that exposes the pure-C++
// voxel_gen::math helpers to GDScript so the parity harness can call
// them and bit-compare against the GDScript originals.
//
// Not used on any production hot path. Lives only to drive
// scripts/_dev/GeneratorParityHarness.gd.

#include <godot_cpp/classes/ref_counted.hpp>

class ParityProbe : public godot::RefCounted {
    GDCLASS(ParityProbe, godot::RefCounted)

public:
    ParityProbe();
    ~ParityProbe();

    // Mirrors VoxelGenerationMath.hash3(x, y, z, seed).
    // Godot ints are 64-bit, so the int64_t signature in C++ binds
    // cleanly through Variant::INT.
    double hash3(int64_t x, int64_t y, int64_t z, int64_t seed) const;

    // Mirrors VoxelGenerationMath.cliff_threshold_for_angle_voxels.
    int cliff_threshold_for_angle_voxels(double angle_degrees, int sample_distance_voxels) const;

protected:
    static void _bind_methods();
};
