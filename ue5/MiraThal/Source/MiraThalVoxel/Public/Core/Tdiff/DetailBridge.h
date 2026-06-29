// DetailBridge.h — the "30 m -> 10 cm detail bridge" for runtime terrain-diffusion.
//
// WHAT THIS IS (plain English):
// Our terrain-diffusion AI model paints the world at a COARSE resolution: roughly
// one elevation value every 30 metres ("30 m / pixel"). But our voxels are tiny —
// 10 cm cubes, i.e. 10 voxels per metre — so a single coarse pixel covers a
// 30 m × 30 m patch, which at 10 voxels/m is 300 × 300 voxels. If we just stretched
// the coarse grid straight onto the voxels we'd get giant smooth ramps with no
// structure smaller than 30 m: it would read as melted plastic, not terrain.
//
// This module is the BRIDGE between the two scales. For any single world voxel
// column (x, z) it answers one question — "how high is the ground here, in voxels?"
// — by combining two things:
//
//   (a) SMOOTH MACRO UPSAMPLE. We sample the coarse elevation grid with a
//       Catmull-Rom bicubic interpolation. Catmull-Rom is a cubic spline that
//       passes EXACTLY through the original coarse values at the pixel centres
//       (so we never drift from what the model painted) and curves smoothly
//       between them (so no stair-steps, no creased bilinear diamonds).
//
//   (b) DETERMINISTIC FRACTAL DETAIL. On top of the smooth macro height we add
//       fractal noise (fBm) to put back the sub-30 m structure the coarse grid
//       cannot carry — little ridges, bumps, erosion grain. Crucially this detail
//       is *keyed* to the terrain so it looks natural rather than uniform:
//         • SLOPE keying  — steep coarse regions (cliffs, valley walls) get MORE
//           detail; near-flat regions (plains, lake beds) get less. Real terrain
//           is rougher where it is steeper.
//         • ALTITUDE keying — higher ground can get more detail (rocky peaks vs
//           smooth lowlands). Off by default; turn up altitudeBoost to enable.
//       The detail comes from mira::noise::fbm2d (Core/Noise.h) — we REUSE the
//       engine's existing deterministic noise, we do not invent a new one. Same
//       (seed, x, z) always yields the identical height on every machine.
//
// The result is a single height in VOXELS (10 voxels = 1 m, matching the rest of
// Core — see HeightmapGenerator.h / ImageHeightmap.h). Whoever voxelizes it floors
// to an integer voxel-Y, so the world stays true blocky cubes — the smoothing and
// detail live in the *continuous* height, the cubes fall out at the very end.
//
// CONVENTIONS borrowed from ImageHeightmap.h so this drops in alongside it:
//   * heights are in voxels (10 voxels / metre),
//   * the coarse grid is a row-major float array of width*height values,
//   * world→pixel uses an origin (world voxel of pixel (0,0)'s centre) plus a
//     "voxels per coarse pixel" pitch (= metersPerCoarsePixel * voxelsPerMeter,
//     e.g. 30 * 10 = 300),
//   * off-grid reads CLAMP to the nearest border pixel (terrain extends flat).
//
// HEADER-ONLY, pure C++17, no engine headers — so the standalone clang harness in
// tests/standalone can unit-test it (see test_tdiff_detail.cpp). Only dependency
// is Core/Noise.h (itself dependency-free).

#pragma once

#include <cstdint>
#include <cstddef>
#include <cmath>
#include <algorithm>

#include "Core/Noise.h" // mira::noise::fbm2d — the REUSED deterministic noise

namespace mira {
namespace tdiff {

// =============================================================================
// DetailBridgeParams — every knob the bridge exposes, with sane 30 m→10 cm
// defaults. The designer tunes these; the test overrides them per assertion.
// =============================================================================
struct DetailBridgeParams {
    // --- Scale (informational + helper; the sampler takes the pitch directly) ---
    double metersPerCoarsePixel = 30.0;   // model paints ~one value per 30 m
    double voxelsPerMeter       = 10.0;   // engine-wide: 10 cm voxels

    // --- Macro fractal detail amplitude (in VOXELS) ---
    // The peak height the detail layer can add/subtract on FLAT ground before
    // slope/altitude keying scales it up. 40 voxels = 4 m of sub-30 m relief.
    double detailAmpVoxels = 40.0;

    // fBm octaves handed to mira::noise::fbm2d. More octaves = finer grain.
    int    octaves = 4;

    // Base detail frequency in CYCLES PER VOXEL. 0.01 → the largest detail
    // wavelength is ~100 voxels (10 m), comfortably finer than the 30 m macro;
    // octaves add the smaller stuff on top.
    double detailFreq = 0.01;

    // --- Slope keying ---
    // amplitude *= (1 + slopeBoost * slope), where slope is the coarse grid's
    // local gradient magnitude in voxels-per-voxel (dimensionless). slopeBoost=2
    // means a 45° coarse slope (slope≈1) triples the detail amplitude.
    double slopeBoost = 2.0;

    // --- Altitude keying (off by default) ---
    // amplitude *= (1 + altitudeBoost * altKey), where altKey ramps 0→1 as the
    // macro height climbs from altitudeRefVoxels to altitudeRefVoxels+altitudeRangeVoxels.
    double altitudeBoost      = 0.0;     // 0 = altitude keying disabled
    double altitudeRefVoxels  = 120.0;   // sea level (= 12 m, matches HeightmapGenerator)
    double altitudeRangeVoxels = 2000.0; // 200 m of climb to reach full altitude boost

    // --- Determinism ---
    int64_t seed = 0;                    // fed to fbm2d; fixes the detail field

    // Convenience: the voxel pitch of one coarse pixel implied by the scale knobs
    // (30 m/px * 10 vox/m = 300 vox/px). The sampler still takes the pitch as an
    // explicit argument (mirroring ImageHeightmap::voxels_per_pixel) so a caller
    // can pass a value that came straight from import metadata.
    double voxels_per_coarse_pixel() const {
        return metersPerCoarsePixel * voxelsPerMeter;
    }
};

// =============================================================================
// Low-level helpers (free inline functions, distinct names to avoid shadowing).
// =============================================================================

// Clamped read of one coarse grid cell (heights in voxels). Off-grid → border.
inline double dbridge_grid_at(const float* coarse, int cw, int ch, int x, int z) {
    if (x < 0) x = 0; else if (x >= cw) x = cw - 1;
    if (z < 0) z = 0; else if (z >= ch) z = ch - 1;
    return static_cast<double>(coarse[static_cast<size_t>(z) * static_cast<size_t>(cw) + static_cast<size_t>(x)]);
}

// One-dimensional Catmull-Rom: a cubic through p1,p2 using neighbours p0,p3.
// At t=0 it returns p1 exactly, at t=1 it returns p2 exactly (interpolating),
// and it reproduces linear data exactly (so ramps stay straight + monotone).
inline double dbridge_catmull(double p0, double p1, double p2, double p3, double t) {
    const double t2 = t * t;
    const double t3 = t2 * t;
    return 0.5 * ((2.0 * p1)
                  + (-p0 + p2) * t
                  + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                  + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}

// Bicubic (Catmull-Rom) sample of the coarse grid at fractional pixel (px, pz).
// Interpolates 4×4 surrounding cells; passes exactly through the grid at integer
// pixel coordinates. Edges clamp via dbridge_grid_at.
inline double dbridge_bicubic(const float* coarse, int cw, int ch, double px, double pz) {
    const double fpx = std::floor(px);
    const double fpz = std::floor(pz);
    const int ix = static_cast<int>(fpx);
    const int iz = static_cast<int>(fpz);
    const double tx = px - fpx;
    const double tz = pz - fpz;

    double col[4];
    for (int j = 0; j < 4; ++j) {
        const int zz = iz - 1 + j;
        const double p0 = dbridge_grid_at(coarse, cw, ch, ix - 1, zz);
        const double p1 = dbridge_grid_at(coarse, cw, ch, ix,     zz);
        const double p2 = dbridge_grid_at(coarse, cw, ch, ix + 1, zz);
        const double p3 = dbridge_grid_at(coarse, cw, ch, ix + 2, zz);
        col[j] = dbridge_catmull(p0, p1, p2, p3, tx);
    }
    return dbridge_catmull(col[0], col[1], col[2], col[3], tz);
}

// Local coarse-grid slope at fractional pixel (px, pz), returned as a
// dimensionless voxels-per-voxel gradient magnitude. We take a central
// difference on the grid at the nearest pixel (heights are voxels, the step is
// one coarse pixel = voxelsPerCoarsePixel voxels), so flat regions give 0 and
// steep regions give a large value — this is what keys the detail amplitude.
inline double dbridge_slope(const float* coarse, int cw, int ch,
                            double px, double pz, double voxelsPerCoarsePixel) {
    long lx = std::lround(px);
    long lz = std::lround(pz);
    int ipx = static_cast<int>(lx);
    int ipz = static_cast<int>(lz);
    if (ipx < 0) ipx = 0; else if (ipx >= cw) ipx = cw - 1;
    if (ipz < 0) ipz = 0; else if (ipz >= ch) ipz = ch - 1;

    const double hxm = dbridge_grid_at(coarse, cw, ch, ipx - 1, ipz);
    const double hxp = dbridge_grid_at(coarse, cw, ch, ipx + 1, ipz);
    const double hzm = dbridge_grid_at(coarse, cw, ch, ipx, ipz - 1);
    const double hzp = dbridge_grid_at(coarse, cw, ch, ipx, ipz + 1);

    // voxels of height change per coarse pixel of horizontal travel.
    const double gx = (hxp - hxm) * 0.5;
    const double gz = (hzp - hzm) * 0.5;
    const double per_pixel = std::sqrt(gx * gx + gz * gz);

    // divide by the pixel pitch (voxels) → voxels of rise per voxel of run.
    if (voxelsPerCoarsePixel <= 0.0) return 0.0;
    return per_pixel / voxelsPerCoarsePixel;
}

// =============================================================================
// sample_height_voxels — THE bridge entry point.
//
// Maps world voxel column (worldX, worldZ) into coarse-pixel space, bicubic-
// samples the macro height, estimates the local coarse slope, adds slope/altitude-
// keyed fBm detail, and returns the total ground height in VOXELS.
//
//   coarse                  row-major cw*ch float grid, values = heights in voxels
//   cw, ch                  coarse grid dimensions
//   originVoxelX/Z          world voxel coordinate of coarse pixel (0,0)'s centre
//   voxelsPerCoarsePixel    voxels spanned by one coarse pixel (e.g. 300)
//   worldX, worldZ          the world voxel column we want a height for
//   p                       tuning knobs (see DetailBridgeParams)
// =============================================================================
inline double sample_height_voxels(const float* coarse, int cw, int ch,
                                   double originVoxelX, double originVoxelZ,
                                   double voxelsPerCoarsePixel,
                                   int worldX, int worldZ,
                                   const DetailBridgeParams& p) {
    if (coarse == nullptr || cw <= 0 || ch <= 0 || voxelsPerCoarsePixel <= 0.0) {
        return 0.0;
    }

    // 1) World voxel → fractional coarse-pixel coordinate.
    const double px = (static_cast<double>(worldX) - originVoxelX) / voxelsPerCoarsePixel;
    const double pz = (static_cast<double>(worldZ) - originVoxelZ) / voxelsPerCoarsePixel;

    // 2) Smooth macro upsample (Catmull-Rom bicubic). Height in voxels.
    const double macroH = dbridge_bicubic(coarse, cw, ch, px, pz);

    // Detail disabled → return the pure macro height (used by macro-fidelity tests
    // and by callers who want only the smooth upsample).
    if (p.detailAmpVoxels == 0.0) {
        return macroH;
    }

    // 3) Local slope from the coarse grid (voxels per voxel).
    const double slope = dbridge_slope(coarse, cw, ch, px, pz, voxelsPerCoarsePixel);

    // 4) Keyed amplitude: base * slope factor * altitude factor.
    const double slopeFactor = 1.0 + p.slopeBoost * slope;

    double altFactor = 1.0;
    if (p.altitudeBoost != 0.0 && p.altitudeRangeVoxels > 0.0) {
        double altKey = (macroH - p.altitudeRefVoxels) / p.altitudeRangeVoxels;
        altKey = std::clamp(altKey, 0.0, 1.0);
        altFactor = 1.0 + p.altitudeBoost * altKey;
    }

    const double amp = p.detailAmpVoxels * slopeFactor * altFactor;

    // 5) Fractal detail from the REUSED engine noise. fbm2d returns [-1, 1];
    //    sampled in cycles-per-voxel so neighbouring columns differ.
    const double d = noise::fbm2d(static_cast<double>(worldX) * p.detailFreq,
                                  static_cast<double>(worldZ) * p.detailFreq,
                                  p.seed, p.octaves);

    // 6) Total continuous height in voxels (caller floors to a cube).
    return macroH + d * amp;
}

} // namespace tdiff
} // namespace mira
