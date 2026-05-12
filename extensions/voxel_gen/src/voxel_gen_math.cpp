#include "voxel_gen_math.h"

#include <cmath>

namespace voxel_gen::math {

// Mirror of scripts/VoxelGenerationMath.gd hash3.
//
// Source GDScript:
//   var h: int = ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
//                 ^ (seed * 39916801)) & 0xFFFFFF
//   return float(h) / float(0xFFFFFF)
//
// The four primes here are not load-bearing in any special way -- they
// just decorrelate axes for the XOR. If we ever change them, every
// baked SQLite world becomes invalid (different ore positions, different
// marble jitter, different disk anchors). Bump WORLD_GENERATOR_VERSION
// in lockstep if that ever happens.
double hash3(int64_t x, int64_t y, int64_t z, int64_t seed) {
    int64_t h = ((x * 73856093LL) ^ (y * 19349663LL) ^ (z * 83492791LL) ^ (seed * 39916801LL)) & 0xFFFFFFLL;
    return static_cast<double>(h) / static_cast<double>(0xFFFFFFLL);
}

// Mirror of scripts/VoxelGenerationMath.gd cliff_threshold_for_angle_voxels.
//
// Source GDScript:
//   return int(ceil(tan(deg_to_rad(angle_degrees)) * float(sample_distance_voxels)))
//
// GDScript's deg_to_rad is just angle * PI / 180. C++'s std::tan
// takes radians directly. Output is int(ceil(double)).
int cliff_threshold_for_angle_voxels(double angle_degrees, int sample_distance_voxels) {
    static constexpr double PI = 3.14159265358979323846;
    double radians = angle_degrees * PI / 180.0;
    return static_cast<int>(std::ceil(std::tan(radians) * static_cast<double>(sample_distance_voxels)));
}

}  // namespace voxel_gen::math
