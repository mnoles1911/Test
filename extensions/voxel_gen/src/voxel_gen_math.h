#pragma once

// VoxelGenMath -- C++ port of scripts/VoxelGenerationMath.gd.
//
// Pure namespace (no Godot Object base). The future C++ generators
// (CubicHeightmapGenerator, CopperIslesHeightmapGenerator) will use
// these directly. ParityProbe is the only Godot-registered class that
// exposes these to GDScript, and it exists solely for the parity
// harness in scripts/_dev/GeneratorParityHarness.gd.
//
// Bit-exact contract with the GDScript implementation:
//   * GDScript `int` is 64-bit signed. The hash multiplications can
//     reach ~2.2e12 at the project's 30 000-voxel extent, which
//     overflows 32-bit signed. We use int64_t throughout to match.
//   * GDScript `float` is 64-bit IEEE-754 (double). The final divide
//     must use `double`, not `float`.
//   * `& 0xFFFFFF` truncates to 24 bits before the divide.
//
// Verify parity via the harness; do not change these helpers without
// re-running the harness and getting 0 mismatches.

#include <cstdint>

namespace voxel_gen::math {

// Triple-prime XOR hash. Returns a deterministic value in [0, 1] for
// any integer (x, y, z, seed) tuple. Used by Tier 3-6 of the
// generator.
double hash3(int64_t x, int64_t y, int64_t z, int64_t seed = 0);

// Cliff slope angle -> minimum voxel-Y drop over the given horizontal
// sample distance. Mirrors VoxelGenerationMath.cliff_threshold_for_angle_voxels.
int cliff_threshold_for_angle_voxels(double angle_degrees, int sample_distance_voxels);

}  // namespace voxel_gen::math
