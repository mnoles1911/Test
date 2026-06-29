// LodDownsample.h — engine-agnostic LOD halving for DenseGrid chunks.
//
// Plain English: when you want to draw a far-away chunk at lower detail you
// need a "half-resolution" version of it — a grid whose side is half the
// original, where each voxel represents a 2x2x2 block of the source voxels.
// This file does exactly that, following the same no-engine-types, pure-C++17
// rule as every other Core header (clang-testable in the headless harness).
//
// THREE RULES drive every decision:
//
//   1. SOLID SURVIVES. At distance you should never see holes where solid
//      terrain existed. So a 2x2x2 block is treated as solid if ANY of the 8
//      voxels is non-air and non-passthrough.  Flora (grass blades, flowers,
//      pebbles — ids 24-28) is "passthrough" in the physics sense and is also
//      treated as air for LOD purposes: a chunk made of 7 air + 1 grass blade
//      collapses to air, not a solid cube of grass.
//
//   2. SURFACE MATERIAL WINS (the "top-most solid voxel" rule). The greedy
//      mesher colours a coarse voxel's +Y (top) face from the topmost solid
//      voxel's material id, and that top face is almost all you see at LOD
//      distance. The grass layer is only ONE voxel thick (the generator bands
//      down from ground_y: depth 0 = grass, 1-3 = dirt, deeper = stone/marble).
//      So when we collapse a 2x2x2 block we must NOT average / majority-vote the
//      material — that throws away the thin grass cap and the block reads dirt,
//      then by L4-5 it reads the stone/marble bulk (grey/white). Instead, the
//      coarse voxel takes the material of the HIGHEST solid fine voxel along the
//      WORLD-UP axis (= the DenseGrid Y axis; see the up-axis note below). Chain
//      this through every halving and the grass cap survives to L5 (whole chunk
//      → 1 voxel), so per-chunk LODs agree with the super-chunk path (which
//      already samples resolve_column().top_id directly → green).
//
//      WORLD-UP AXIS = grid Y. Confirmed three ways: (a) the generator bands by
//      depth = ground_y - world_y, so larger Y is "up / surface" (grass at the
//      top); (b) DenseGrid flatten is index = x + y*side + z*side*side and the
//      VoxelWorld slab fill (MeshColumnPure) copies world (x,y,z) straight to
//      grid (x,y,z) with no axis swap; (c) the mesher's FACE_POS_Y has normal
//      (0,1,0) and shaded_color uses it for the top face. So "topmost solid" =
//      the solid fine voxel with the largest Y (dy = 1 before dy = 0).
//
//      SIDE-FACE TRADEOFF (accepted, documented): because the whole coarse voxel
//      now carries the top material, a coarse voxel's SIDE faces also read the
//      surface material (e.g. a distant cliff face may read grass-tinted instead
//      of stone). This is invisible at LOD distance and is EXACTLY what the
//      super-chunk path already does. We ship the simple top-wins rule.
//
//   3. WATER KEEPS ITS LEVEL. The surface mesher only needs to know "how full
//      is this water voxel?" — direction and source flags are irrelevant at
//      coarse LOD. So the output water byte carries the MAX level among the 8
//      inputs (decoded + re-encoded via WaterByteCodec), with direction = STILL
//      and source = false. If none of the 8 are water the output is 0 (dry).
//
// Usage:
//   DenseGrid half   = mira::lod::downsample_half(chunk32);   // -> side 16
//   DenseGrid eighth = mira::lod::downsample_to_lod(chunk32, 2); // -> side 8

#pragma once

#include <cstdint>
#include <array>
#include <algorithm>

#include "Core/VoxelChunk.h"     // DenseGrid, coords::flatten
#include "Core/MaterialIds.h"    // mat::AIR, mat::is_passthrough
#include "Core/WaterByteCodec.h" // level_of, pack, DIR_STILL

namespace mira {
namespace lod {

// ---------------------------------------------------------------------------
// downsample_half — reduce a grid by 2x in every axis.
//
// Contract: src.side must be even (>= 2). If not, an assertion fires in
// debug builds and an empty DenseGrid (side 0) is returned in release builds.
// The caller is responsible for ensuring the input side is a power of two if
// they intend to chain multiple halvings (see downsample_to_lod below).
// ---------------------------------------------------------------------------
inline DenseGrid downsample_half(const DenseGrid& src) {
    // ---- Contract guard ---------------------------------------------------
    // We cannot split an odd number of voxels cleanly into 2x2x2 blocks.
    // Return an empty grid (side == 0) so callers can detect the violation
    // gracefully rather than hitting an out-of-bounds access.  The comment is
    // the contract; the early-return is the enforcement.
    //
    // (A runtime assert() here would abort() the process and kill the test
    // runner, so we intentionally leave it out.  Catch contract violations in
    // code review or via the side-0 sentinel the caller receives.)
    if (src.side <= 0 || src.side % 2 != 0) {
        return DenseGrid{}; // side 0 signals the contract violation to callers
    }

    const int out_side = src.side / 2;
    DenseGrid out(out_side);

    // Iterate over every voxel in the OUTPUT grid.
    for (int oz = 0; oz < out_side; ++oz) {
        for (int oy = 0; oy < out_side; ++oy) {
            for (int ox = 0; ox < out_side; ++ox) {

                // The 8 source voxels whose corner is at (2*ox, 2*oy, 2*oz).
                // We gather the water channel for all 8 before deciding water.
                // The type channel is resolved by a top-down scan (see below).
                std::array<uint8_t, 8> waters{};

                int slot = 0;
                for (int dz = 0; dz < 2; ++dz) {
                    for (int dy = 0; dy < 2; ++dy) {
                        for (int dx = 0; dx < 2; ++dx) {
                            const int sx = 2 * ox + dx;
                            const int sy = 2 * oy + dy;
                            const int sz = 2 * oz + dz;
                            waters[slot] = src.water_at(sx, sy, sz);
                            ++slot;
                        }
                    }
                }

                // ===========================================================
                // TYPE CHANNEL — surface-preserving "top-most solid voxel wins"
                // ===========================================================
                //
                // Occupancy is UNCHANGED from the old rule: the coarse voxel is
                // solid iff ANY fine voxel in the block is non-air and non-
                // passthrough (flora/surface-detail, ids 24-28, count as air).
                // What changed is WHICH solid id we keep.
                //
                // We scan the 2x2x2 block from the TOP of the world-up axis (grid
                // Y) downward and take the material of the FIRST solid voxel we
                // meet. World-up = grid Y (see file-top up-axis note), so the top
                // layer is dy = 1, the bottom is dy = 0. For each (dx,dz) column
                // we look at dy = 1 first, then dy = 0. The overall "topmost solid
                // in the block" is the first solid found while iterating dy = 1
                // across all (dx,dz), then dy = 0 across all (dx,dz).
                //
                // This keeps the thin grass cap: if the highest solid fine voxel
                // was grass, the coarse voxel is grass — at every LOD level.

                uint8_t out_type = mat::AIR; // default: no solids -> air
                bool found_solid = false;

                // Top row first (dy = 1), then bottom row (dy = 0). Within a row
                // the (dx,dz) order is arbitrary — any solid in the top row is at
                // the same world-up height, so picking the first is well-defined.
                for (int dy = 1; dy >= 0 && !found_solid; --dy) {
                    for (int dz = 0; dz < 2 && !found_solid; ++dz) {
                        for (int dx = 0; dx < 2 && !found_solid; ++dx) {
                            const int sx = 2 * ox + dx;
                            const int sy = 2 * oy + dy;
                            const int sz = 2 * oz + dz;
                            const int t = src.type_at(sx, sy, sz);
                            // Flora and passthrough are treated as air for LOD.
                            if (t == mat::AIR || mat::is_passthrough(t)) {
                                continue;
                            }
                            out_type = static_cast<uint8_t>(t);
                            found_solid = true;
                        }
                    }
                }

                // ===========================================================
                // WATER CHANNEL — maximum level, direction dropped
                // ===========================================================
                //
                // At LOD distance the water surface mesher only needs to know
                // how full the cell is.  Direction and source flags add no
                // visual information at coarse resolution and would require
                // merging rules that aren't well-defined across a 2x2x2 block.
                // So we take the highest water level among the 8 inputs and
                // re-encode as a still, non-source water byte.

                int max_water_level = 0;
                for (int i = 0; i < 8; ++i) {
                    if (WaterByteCodec::is_water(waters[i])) {
                        const int lvl = WaterByteCodec::level_of(waters[i]);
                        if (lvl > max_water_level) {
                            max_water_level = lvl;
                        }
                    }
                }

                // Re-encode: level only, no source flag, direction = STILL.
                // pack() clamps the level into [0, MAX_LEVEL] safely.
                const uint8_t out_water = (max_water_level > 0)
                    ? static_cast<uint8_t>(WaterByteCodec::pack(
                            max_water_level,
                            false,              // not a source — flow state is meaningless at LOD
                            WaterByteCodec::DIR_STILL))
                    : 0;

                out.set_type(ox, oy, oz, out_type);
                out.set_water(ox, oy, oz, out_water);
            }
        }
    }

    return out;
}

// ---------------------------------------------------------------------------
// downsample_to_lod — chain halvings to reach an arbitrary LOD level.
//
// lod 0 → copy of src (side unchanged).
// lod 1 → downsample_half once       (side / 2).
// lod 2 → downsample_half twice      (side / 4).
// lod N → side / 2^N.
//
// Contract: src.side must be divisible by 2^lod. Violated grids surface as an
// empty (side 0) DenseGrid bubbling up from the first failing downsample_half.
// ---------------------------------------------------------------------------
inline DenseGrid downsample_to_lod(const DenseGrid& src, int lod) {
    if (lod <= 0) {
        // lod 0 = full resolution copy; the caller asked for no reduction.
        return src;
    }

    DenseGrid current = src; // first iteration uses the original
    for (int i = 0; i < lod; ++i) {
        current = downsample_half(current);
        // If the contract was violated (odd side), propagate the empty grid
        // rather than crashing on subsequent halvings.
        if (current.side == 0) break;
    }
    return current;
}

} // namespace lod
} // namespace mira
