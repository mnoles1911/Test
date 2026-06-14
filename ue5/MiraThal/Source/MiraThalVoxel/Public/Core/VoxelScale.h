// VoxelScale.h — THE single authority for the voxel grid scale.
//
// Ported 1:1 from Godot scripts/VoxelScale.gd (10 voxels/metre, 10cm cubes,
// the "Lay of the Land" re-architecture). This is the ONE place that knows the
// scale; every other Core file and the UE wrapper layer reads from here.
//
// RULE (carried over from the Godot build): never hardcode 10.0, 0.1, or
// 1.0/10.0 anywhere near voxel math. Use VoxelsPerMeter / VoxelSizeM here.
//
// In Unreal the runtime-tunable mirror is UVoxelScaleSettings (UDeveloperSettings),
// which is initialized FROM these constants so the editor can expose them while
// the Core stays a pure compile-time authority.

#pragma once

#include <cstdint>
#include <cmath>

namespace mira {
namespace scale {

// How many voxels (grid cells) span one metre of world space.
// 10 since the 10cm-voxel re-architecture (was 6 from the original 3D pivot).
constexpr double VoxelsPerMeter = 10.0;

// Edge length of one voxel in world-space metres. 1/10 = 0.1 m = 10 cm exactly.
// This is the uniform scale the Voxel Plugin world must use.
constexpr double VoxelSizeM = 1.0 / VoxelsPerMeter;

// Convert a world-space distance (metres) to the nearest integer voxel count.
// Rounds to nearest (matches Godot roundi), NOT floor — a 0.9 m object is
// 9 voxels wide at 10 vox/m, not 8. Pure calc, worker-thread safe.
inline int32_t MetersToVoxels(double m) {
    return static_cast<int32_t>(std::llround(m * VoxelsPerMeter));
}

// Convert an integer voxel count to its world-space distance in metres.
inline double VoxelsToMeters(int32_t v) {
    return static_cast<double>(v) * VoxelSizeM;
}

} // namespace scale
} // namespace mira
