// LodTier.h — pick a voxel LOD level (0..3) from a chunk-column's distance.
//
// THE JOB (plain English): the streaming system knows, for each chunk-column,
// how far it sits from the "focus" (usually the camera/player) measured in
// CHUNKS (1 unit == one 32-voxel chunk edge). This file turns that distance
// into a LOD LEVEL — a single number 0..3 that says how coarse to draw it:
//
//   LOD 0  — near terrain, full 10cm voxels                (tier T0)
//   LOD 1  — mid terrain, 20cm voxels (downsampled once)   (tier T1)
//   LOD 2  — farther, 40cm voxels (downsampled twice)      (tier T1)
//   LOD 3  — far, 80cm voxels (downsampled three times)    (tier T1, edge of T2)
//
// (Beyond LOD 3 the world is drawn as a flat heightmesh — see FarHeightmesh.h.
//  That switch is the renderer's call; this file only ever returns 0..3.)
//
// The LOD LEVEL produced here is EXACTLY the `lod` argument the render path
// already takes — feed it straight into mira::lod::downsample_to_lod() in
// LodDownsample.h. We deliberately do NOT redefine any downsample math or any
// chunk constant here; this header is purely the distance->level *decision*.
//
// WHY A SEPARATE HEADER (not BandPolicy.h): BandPolicy.h answers a DIFFERENT
// question — it sorts chunks into render TREATMENTS (HOT dynamic mesh / COLD
// Nanite bake / FAR ray-march) across a single near/far line. That is about
// *how* a chunk is drawn. LodTier answers *how coarse* a meshed chunk's voxels
// are, across several thresholds. They compose (a COLD chunk still has a LOD
// level), so this is its own small policy rather than a tweak to BandPolicy.
//
// HYSTERESIS (the sticky part): a column hovering right on a tier boundary must
// not flip LOD every frame as the camera jitters — re-downsampling and swapping
// meshes that often would thrash the mesher and shimmer on screen. So we offer a
// hysteresis variant that keeps the CURRENT level until the distance moves a
// `margin` of chunks PAST the boundary, in whichever direction it's heading.
//
// Pure C++17, no engine types — compiles in the headless clang harness and in
// the UE5 module alike. Header-only (all inline/constexpr): no .cpp, so the
// harness's Core-source list is untouched.

#pragma once

#include "Core/ChunkCoords.h"  // coords::CHUNK (so callers/readers see the unit)

namespace mira {
namespace lodtier {

// The coarsest LOD this policy ever returns. Past this the renderer switches to
// the far heightmesh. LOD k renders 2^k-voxel cubes: 0=10cm .. 5=320cm. The coarsest
// levels (4/5) make a chunk just a handful of big cubes, so the render distance can
// grow far (a 32^3 chunk at LOD 5 is ONE 320 cm cube). CHUNK=32 stays divisible
// through LOD 5 (32 / 2^5 = 1).
constexpr int MAX_LOD = 5;

// ---------------------------------------------------------------------------
// LodTierConfig — the distance thresholds, in CHUNK units.
//
// Read each `t<N>_max` as "a column at this distance (in chunks) or NEARER gets
// at most LOD N". They must be NON-DECREASING (t0 <= t1 <= t2) for the result to
// be monotonic; the defaults satisfy that. The brief's tier story maps on as:
//
//   dist <= t0_max  -> LOD 0  (T0 full-res near terrain)
//   dist <= t1_max  -> LOD 1  (T1 first downsample)
//   dist <= t2_max  -> LOD 2  (T1 second downsample)
//   else            -> LOD 3  (T1 third downsample / edge of the far T2 band)
//
// All three default to the brief's tier distances (8 / 24 / 64 chunks). Change
// them per streaming profile by passing a tweaked config — nothing here is
// hard-wired except the clamp to [0, MAX_LOD].
// ---------------------------------------------------------------------------
struct LodTierConfig {
    int t0_max = 8;    // <= 8   -> LOD 0 (10 cm)
    int t1_max = 24;   // <= 24  -> LOD 1 (20 cm)
    int t2_max = 64;   // <= 64  -> LOD 2 (40 cm)
    int t3_max = 128;  // <= 128 -> LOD 3 (80 cm)
    int t4_max = 256;  // <= 256 -> LOD 4 (160 cm); beyond -> LOD 5 (320 cm)
};

// ---------------------------------------------------------------------------
// lod_for_distance — the plain (no-memory) rule: distance in chunks -> LOD 0..3.
//
// Walks the thresholds from nearest to farthest and returns the first tier the
// distance fits inside. A negative distance is treated as 0 (right on top of the
// focus -> full res). Because the thresholds are non-decreasing, the result is
// MONOTONIC: moving farther away can only raise the LOD, never lower it.
// ---------------------------------------------------------------------------
inline int lod_for_distance(int dist_chunks, const LodTierConfig& cfg = LodTierConfig{}) {
    // Clamp a nonsensical negative distance up to 0 (you can't be "behind" the
    // focus in radial distance; treat it as on top of it -> finest LOD).
    if (dist_chunks < 0) dist_chunks = 0;

    if (dist_chunks <= cfg.t0_max) return 0;  // near band: full resolution
    if (dist_chunks <= cfg.t1_max) return 1;  // downsampled once  (20 cm)
    if (dist_chunks <= cfg.t2_max) return 2;  // downsampled twice (40 cm)
    if (dist_chunks <= cfg.t3_max) return 3;  // 80 cm
    if (dist_chunks <= cfg.t4_max) return 4;  // 160 cm
    return MAX_LOD;                           // far band: coarsest meshed LOD (5 = 320 cm)
}

// ---------------------------------------------------------------------------
// lod_for_distance_hys — the STICKY rule: like the above, but it resists
// flipping when the column sits near a boundary.
//
//   dist_chunks  — current distance in chunks.
//   current_lod  — the LOD this column had LAST frame (the memory that makes it
//                  sticky). Pass the value this function returned previously.
//   cfg          — the same thresholds as the plain rule.
//   margin_chunks— how far (in chunks) the distance must move PAST a boundary
//                  before we actually change level. 0 means "no hysteresis"
//                  (identical to lod_for_distance). A typical value is 1-2.
//
// HOW IT STAYS STICKY (plain English): we first compute where the column WOULD
// go with no memory (the "raw" target). Then:
//
//   * If raw == current_lod, nothing to do — stay put.
//
//   * If the world wants us COARSER (raw > current): only step up once the
//     distance is at least `margin` PAST the boundary we're leaving — i.e. past
//     (the current level's far edge + margin). Until then we hold the finer
//     level. We step up by ONE level at a time so a big jump still passes
//     through the in-between meshes rather than popping straight to the coarsest.
//
//   * If the world wants us FINER (raw < current): symmetric — only step down
//     once the distance has come back at least `margin` INSIDE the boundary for
//     the finer level we'd drop into, i.e. to (that level's far edge - margin).
//     Again, one level at a time.
//
// Net effect: a column oscillating +/- a chunk around a threshold keeps its LOD
// rock-steady; only a genuine, sustained crossing (boundary +/- margin) flips it.
// The hysteresis band is therefore 2*margin chunks wide, centred on each
// threshold.
// ---------------------------------------------------------------------------
inline int lod_for_distance_hys(int dist_chunks, int current_lod,
                                const LodTierConfig& cfg = LodTierConfig{},
                                int margin_chunks = 1) {
    if (dist_chunks < 0) dist_chunks = 0;
    if (margin_chunks < 0) margin_chunks = 0;

    // Keep the remembered level honest in case a caller passes garbage.
    if (current_lod < 0)       current_lod = 0;
    if (current_lod > MAX_LOD) current_lod = MAX_LOD;

    // Where would we go with no memory at all?
    const int raw = lod_for_distance(dist_chunks, cfg);

    if (raw == current_lod) {
        // Already at the right level — the common, cheap case.
        return current_lod;
    }

    // The "far edge" (last distance still inside) of a given LOD level. This is
    // the boundary the level is leaving as you move outward. Level 3 has no
    // upper edge (it's the last meshed band), so we never need its edge here.
    auto far_edge_of = [&cfg](int lod) -> int {
        switch (lod) {
            case 0:  return cfg.t0_max;  // LOD 0 ends at t0_max
            case 1:  return cfg.t1_max;  // LOD 1 ends at t1_max
            case 2:  return cfg.t2_max;  // LOD 2 ends at t2_max
            case 3:  return cfg.t3_max;  // LOD 3 ends at t3_max
            default: return cfg.t4_max;  // LOD 4 ends at t4_max (LOD 5 is the last band)
        }
    };

    if (raw > current_lod) {
        // World wants us COARSER. Step up ONE level, but only once we're a full
        // margin past the edge we're currently sitting against. The edge we must
        // clear is the far edge of our CURRENT level.
        const int edge = far_edge_of(current_lod);
        if (dist_chunks > edge + margin_chunks) {
            return current_lod + 1;  // committed crossing -> drop one level of detail
        }
        return current_lod;          // inside the sticky band -> hold finer level
    }

    // raw < current_lod: world wants us FINER. Step down ONE level, but only once
    // we've come back a full margin INSIDE the boundary for the finer level we'd
    // move into. That boundary is the far edge of the level just below us.
    const int finer = current_lod - 1;
    const int edge  = far_edge_of(finer);
    if (dist_chunks <= edge - margin_chunks) {
        return finer;                // committed crossing -> gain one level of detail
    }
    return current_lod;              // inside the sticky band -> hold coarser level
}

} // namespace lodtier
} // namespace mira
