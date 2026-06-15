// LodDownsample.h — engine-agnostic LOD halving for DenseGrid chunks.
//
// Plain English: when you want to draw a far-away chunk at lower detail you
// need a "half-resolution" version of it — a grid whose side is half the
// original, where each voxel represents a 2x2x2 block of the source voxels.
// This file does exactly that, following the same no-engine-types, pure-C++17
// rule as every other Core header (clang-testable in the headless harness).
//
// TWO RULES drive every decision:
//
//   1. SOLID SURVIVES. At distance you should never see holes where solid
//      terrain existed. So a 2x2x2 block is treated as solid if ANY of the 8
//      voxels is non-air and non-passthrough.  Flora (grass blades, flowers,
//      pebbles — ids 24-28) is "passthrough" in the physics sense and is also
//      treated as air for LOD purposes: a chunk made of 7 air + 1 grass blade
//      collapses to air, not a solid cube of grass.
//
//   2. WATER KEEPS ITS LEVEL. The surface mesher only needs to know "how full
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
                // We gather both channels for all 8 before making decisions.
                std::array<uint8_t, 8> types{};
                std::array<uint8_t, 8> waters{};

                int slot = 0;
                for (int dz = 0; dz < 2; ++dz) {
                    for (int dy = 0; dy < 2; ++dy) {
                        for (int dx = 0; dx < 2; ++dx) {
                            const int sx = 2 * ox + dx;
                            const int sy = 2 * oy + dy;
                            const int sz = 2 * oz + dz;
                            types[slot]  = src.type_at(sx, sy, sz);
                            waters[slot] = src.water_at(sx, sy, sz);
                            ++slot;
                        }
                    }
                }

                // ===========================================================
                // TYPE CHANNEL — majority vote, solid survives, flora = air
                // ===========================================================
                //
                // Step 1: count only ids that are NOT air and NOT passthrough
                // (passthrough = flora + surface detail, ids 24-28).  These are
                // the "solid" voxels that can win the majority vote.
                //
                // Step 2: if there are no solid voxels at all, the output is AIR.
                //
                // Step 3: among the solid ids, pick the MOST FREQUENT one.
                // Tie-break: choose the SMALLER id (deterministic; also happens
                // to favour the "base terrain" material when there is ambiguity
                // at an interface, since terrain ids are generally lower).
                //
                // We use a tiny hand-rolled frequency table over the 8 slots to
                // avoid allocating anything.  With only 8 entries a linear scan
                // is cheaper than sorting.

                // Accumulate counts for each unique solid id seen.
                // We have at most 8 distinct ids across 8 voxels.
                uint8_t seen_id[8]    = {};
                int     seen_cnt[8]   = {};
                int     unique_count  = 0;
                int     total_solid   = 0;

                for (int i = 0; i < 8; ++i) {
                    const int t = types[i];

                    // Flora and passthrough are treated as air for LOD purposes.
                    if (t == mat::AIR || mat::is_passthrough(t)) {
                        continue;
                    }

                    ++total_solid;

                    // Find the slot for this id (or add a new one).
                    bool found = false;
                    for (int k = 0; k < unique_count; ++k) {
                        if (seen_id[k] == static_cast<uint8_t>(t)) {
                            ++seen_cnt[k];
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        seen_id[unique_count]  = static_cast<uint8_t>(t);
                        seen_cnt[unique_count] = 1;
                        ++unique_count;
                    }
                }

                uint8_t out_type = mat::AIR; // default: no solids -> air

                if (total_solid > 0) {
                    // Find the id with the highest count, tie-break by smaller id.
                    int best_cnt = -1;
                    uint8_t best_id = 255;
                    for (int k = 0; k < unique_count; ++k) {
                        const int   c = seen_cnt[k];
                        const uint8_t id = seen_id[k];
                        // Prefer higher count; on equal count prefer smaller id.
                        if (c > best_cnt || (c == best_cnt && id < best_id)) {
                            best_cnt = c;
                            best_id  = id;
                        }
                    }
                    out_type = best_id;
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
