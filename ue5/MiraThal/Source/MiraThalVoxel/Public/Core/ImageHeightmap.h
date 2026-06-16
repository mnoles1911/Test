// ImageHeightmap.h — a georeferenced float heightmap (e.g. a Gaea EXR), sampled
// per voxel column to drive terrain generation.
//
// WHAT THIS IS (plain English):
// An artist hand-crafts a terrain in Gaea and exports it as an EXR image: a big
// 2D grid of floating-point "height" values. This Core class holds that grid of
// numbers and answers one question the generator asks millions of times:
//   "at world voxel column (wx, wz), how high is the ground?"
//
// It does two jobs:
//   1. GEOREFERENCE — decide which image pixel a world voxel maps to. The image
//      covers a square of the world (e.g. 5 km × 5 km) centred wherever we want,
//      so one pixel spans several voxels. We BILINEARLY blend the four nearest
//      pixels so the ground is smooth, not stair-stepped per pixel.
//   2. VERTICAL MAP — turn the raw image value into a voxel height. Gaea usually
//      exports normalised 0..1 values, so height_voxels = base + value * scale.
//
// IMPORTANT SPLIT: this class does NOT read the .exr file. Decoding EXR needs an
// image library (Unreal's ImageWrapper does it on the engine side). The engine
// fills `data` with raw floats and sets the georef fields; this Core class is
// pure C++17 + std::vector so the standalone clang harness can unit-test the
// sampling math with a synthetic grid (no Unreal, no real file needed).
//
// Pure C++17, no engine types.

#pragma once

#include <cstdint>
#include <vector>
#include <cmath>
#include <algorithm>

namespace mira {

// =============================================================================
// ImageHeightmap — raw float grid + georeferencing + bilinear sampling.
// =============================================================================
class ImageHeightmap {
public:
    // ---- The raw pixel grid (filled by the engine's EXR decoder) ----
    int width  = 0;                 // pixels across (image columns)
    int height = 0;                 // pixels down  (image rows)
    std::vector<float> data;        // row-major width*height single-channel values

    // ---- Horizontal georeferencing (world VOXEL space) ----
    // How many world voxels one image pixel spans. For a 5 km map exported at
    // 5000 px and a world at 10 voxels/m: 50000 voxels / 5000 px = 10 vox/px.
    double voxels_per_pixel = 10.0;
    // World voxel coordinate that the CENTRE of pixel (0,0) sits on. For a map
    // centred on the world origin this is -(width/2)*voxels_per_pixel, etc.
    double origin_voxel_x = 0.0;
    double origin_voxel_z = 0.0;
    // Image rows usually run top→down while world +Z runs "north"; flipping Z
    // keeps the imported terrain the same way up as it looks in Gaea.
    bool flip_z = false;

    // ---- Vertical mapping (image value → ground voxel-Y) ----
    // ground_y = vertical_base_voxels + value * vertical_scale_voxels.
    // e.g. a 0..1 EXR with 700 m of relief at 10 vox/m → scale = 7000, and
    // base = sea level so value 0 sits at the shoreline.
    double vertical_scale_voxels = 1000.0;
    double vertical_base_voxels  = 0.0;

    // Usable only once the engine has filled a matching-size grid.
    bool valid() const {
        return width > 0 && height > 0
            && static_cast<int64_t>(data.size())
               == static_cast<int64_t>(width) * static_cast<int64_t>(height);
    }

    // -------------------------------------------------------------------------
    // Raw bilinear sample of the image value at a world voxel column. Coordinates
    // off the edge clamp to the nearest border pixel (so terrain outside the map
    // extends flat rather than wrapping or exploding).
    // -------------------------------------------------------------------------
    float sample_value(double world_x, double world_z) const {
        if (!valid()) return 0.0f;

        // World voxel → fractional pixel coordinate.
        double px = (world_x - origin_voxel_x) / voxels_per_pixel;
        double pz = (world_z - origin_voxel_z) / voxels_per_pixel;
        if (flip_z) {
            pz = static_cast<double>(height - 1) - pz;
        }

        // Four surrounding pixel centres, clamped to the grid.
        const int x0 = clampi(ifloor(px), 0, width  - 1);
        const int z0 = clampi(ifloor(pz), 0, height - 1);
        const int x1 = clampi(x0 + 1,     0, width  - 1);
        const int z1 = clampi(z0 + 1,     0, height - 1);

        // Blend weights (also clamped so off-map reads sit exactly on the edge).
        double fx = px - static_cast<double>(ifloor(px));
        double fz = pz - static_cast<double>(ifloor(pz));
        fx = std::clamp(fx, 0.0, 1.0);
        fz = std::clamp(fz, 0.0, 1.0);

        const double v00 = at(x0, z0);
        const double v10 = at(x1, z0);
        const double v01 = at(x0, z1);
        const double v11 = at(x1, z1);

        const double top    = v00 + (v10 - v00) * fx;
        const double bottom = v01 + (v11 - v01) * fx;
        return static_cast<float>(top + (bottom - top) * fz);
    }

    // -------------------------------------------------------------------------
    // Ground voxel-Y at a world column: bilinear value mapped through the
    // vertical scale, floored to an integer voxel (matches the generator's
    // floor-to-voxel convention so banding sits right on the surface).
    // -------------------------------------------------------------------------
    int height_voxels_at(int world_x, int world_z) const {
        const double v = sample_value(static_cast<double>(world_x),
                                      static_cast<double>(world_z));
        const double y = vertical_base_voxels + v * vertical_scale_voxels;
        return static_cast<int>(std::floor(y));
    }

    // Convenience: centre the map on the world origin given its world span in
    // voxels (width_voxels = height_voxels for a square map). Sets the pixel
    // pitch and the (0,0) origin so the image's middle is world (0,0).
    void set_centered_extent(double span_voxels_x, double span_voxels_z) {
        if (width  > 0) voxels_per_pixel = span_voxels_x / static_cast<double>(width);
        origin_voxel_x = -0.5 * span_voxels_x;
        origin_voxel_z = -0.5 * span_voxels_z;
        (void)span_voxels_z; // pitch derived from X; maps are square in practice
    }

private:
    double at(int x, int z) const {
        return static_cast<double>(data[static_cast<size_t>(z) * width + x]);
    }
    static int ifloor(double f) { return static_cast<int>(std::floor(f)); }
    static int clampi(int v, int lo, int hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }
};

} // namespace mira
