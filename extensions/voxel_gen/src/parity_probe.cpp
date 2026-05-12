#include "parity_probe.h"

#include "voxel_gen_math.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

ParityProbe::ParityProbe() {}
ParityProbe::~ParityProbe() {}

double ParityProbe::hash3(int64_t x, int64_t y, int64_t z, int64_t seed) const {
    return voxel_gen::math::hash3(x, y, z, seed);
}

int ParityProbe::cliff_threshold_for_angle_voxels(double angle_degrees, int sample_distance_voxels) const {
    return voxel_gen::math::cliff_threshold_for_angle_voxels(angle_degrees, sample_distance_voxels);
}

void ParityProbe::_bind_methods() {
    ClassDB::bind_method(D_METHOD("hash3", "x", "y", "z", "seed"), &ParityProbe::hash3);
    ClassDB::bind_method(D_METHOD("cliff_threshold_for_angle_voxels",
                                  "angle_degrees", "sample_distance_voxels"),
                         &ParityProbe::cliff_threshold_for_angle_voxels);
}
