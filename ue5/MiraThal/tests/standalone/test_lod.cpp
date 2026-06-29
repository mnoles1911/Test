// test_lod.cpp — headless parity harness for Core/LodDownsample.h.
//   cd tests/standalone && ./build.sh lod
//
// Covers:
//   - all-stone 2^3 -> 1^3 = stone
//   - 7 air + 1 stone -> stone (solid wins over majority air)
//   - 8 air -> air
//   - 7 air + 1 flora (grass blade id 24) -> air (passthrough != solid)
//   - top-wins material rule (surface-preserving): the topmost solid voxel
//     along world-up (grid Y) wins, so a thin grass cap survives the halving
//   - DECISIVE: a 32^3 grass/dirt/stone column keeps GRASS on top at LOD 1..5
//   - water max-level via WaterByteCodec (codec encodes inputs, codec reads output)
//   - downsample_to_lod chains (4^3 -> lod 2 = 1^3; 32^3 -> lod 1 = 16^3)
//   - odd-side contract guard returns empty grid (side 0)

#include <cstdio>
#include <cstdint>

#include "Core/LodDownsample.h"   // the unit under test
#include "Core/VoxelChunk.h"      // DenseGrid
#include "Core/MaterialIds.h"     // mat::STONE, mat::AIR, mat::GRASS_BLADE_ID, etc.
#include "Core/WaterByteCodec.h"  // encode/decode water bytes

// ---------------------------------------------------------------------------
// Harness boilerplate (matches every other test_*.cpp in this suite)
// ---------------------------------------------------------------------------
static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { \
    ++g_checks; \
    if (!(cond)) { \
        ++g_fails; \
        std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__); \
    } \
} while (0)

// ---------------------------------------------------------------------------
// Helper: fill every voxel of a DenseGrid with the given type (and 0 water).
// ---------------------------------------------------------------------------
static void fill_type(mira::DenseGrid& g, uint8_t t) {
    g.fill_type(t);
    g.fill_water(0);
}

// ---------------------------------------------------------------------------
// Helper: build a 2x2x2 grid, set one voxel at (0,0,0) to the given type,
// and leave the other 7 as AIR.  Used for "N air + 1 X" tests.
// ---------------------------------------------------------------------------
static mira::DenseGrid mostly_air_with_one(uint8_t id) {
    mira::DenseGrid g(2);
    fill_type(g, mira::mat::AIR);
    g.set_type(0, 0, 0, id);
    return g;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main() {

    // ========================================================================
    // TEST 1: all-stone 2x2x2 -> 1x1x1 stone
    // ========================================================================
    // The simplest case: every voxel is the same solid material (stone, id 1).
    // The majority is unambiguously stone, so the output must be stone.
    {
        mira::DenseGrid src(2);
        fill_type(src, static_cast<uint8_t>(mira::mat::STONE));

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.side == 1, "all-stone 2^3: output side is 1");
        CHECK(out.type_at(0,0,0) == mira::mat::STONE, "all-stone 2^3: output type is stone");
        CHECK(out.water_at(0,0,0) == 0, "all-stone 2^3: no water");
    }

    // ========================================================================
    // TEST 2: 7 air + 1 stone -> stone
    // ========================================================================
    // "Solid survives": even though 7 out of 8 voxels are air, the one solid
    // voxel should dominate.  Distant terrain must not dissolve into holes.
    {
        mira::DenseGrid src = mostly_air_with_one(
            static_cast<uint8_t>(mira::mat::STONE));

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.side == 1, "7air+1stone: output side is 1");
        CHECK(out.type_at(0,0,0) == mira::mat::STONE,
              "7air+1stone: stone survives despite minority (solid always wins)");
    }

    // ========================================================================
    // TEST 3: 8 air -> air
    // ========================================================================
    {
        mira::DenseGrid src(2);
        fill_type(src, static_cast<uint8_t>(mira::mat::AIR));

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.side == 1, "8air: output side is 1");
        CHECK(out.type_at(0,0,0) == mira::mat::AIR,
              "8air: all air -> air output");
    }

    // ========================================================================
    // TEST 4: 7 air + 1 flora (grass blade id 24) -> air
    // ========================================================================
    // Flora is "passthrough" — treated as air for physics and for LOD purposes.
    // A block with only passthrough voxels has zero solid voxels and must output
    // AIR, not a solid grass-cube that would block movement at LOD distance.
    {
        mira::DenseGrid src = mostly_air_with_one(
            static_cast<uint8_t>(mira::mat::GRASS_BLADE_ID)); // id 24

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.side == 1, "7air+1flora: output side is 1");
        CHECK(out.type_at(0,0,0) == mira::mat::AIR,
              "7air+1flora: grass blade (passthrough) does not count as solid -> air");
    }

    // ========================================================================
    // TEST 5a: TOP-WINS — grass cap on top of dirt survives the halving
    // ========================================================================
    // The whole point of the surface-preserving rule. Build a 2x2x2 block whose
    // TOP layer (grid Y = 1, dy = 1) is GRASS (id 3) and whose BOTTOM layer
    // (Y = 0) is DIRT (id 2). The old majority rule would have tied 4-4 and
    // picked the SMALLER id (dirt) — losing the grass. Top-wins must keep GRASS
    // because grid Y is world-up and the grass voxels are the highest solids.
    {
        mira::DenseGrid src(2);
        fill_type(src, static_cast<uint8_t>(mira::mat::DIRT)); // bottom row dirt
        // Overwrite the entire TOP row (y = 1) with grass.
        src.set_type(0, 1, 0, mira::mat::GRASS);
        src.set_type(1, 1, 0, mira::mat::GRASS);
        src.set_type(0, 1, 1, mira::mat::GRASS);
        src.set_type(1, 1, 1, mira::mat::GRASS);

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.type_at(0,0,0) == mira::mat::GRASS,
              "top-wins 4grass(top)+4dirt(bottom): grass (top, world-up) survives");
    }

    // ========================================================================
    // TEST 5b: TOP-WINS — a SINGLE grass voxel on top beats a dirt majority
    // ========================================================================
    // Only ONE of the 8 is grass, and it sits in the top row (y = 1). The other
    // 7 are dirt (one in the top row, four in the bottom... wait: 1 grass + 7
    // dirt). Top-wins scans the top row first, finds grass, and keeps it even
    // though dirt is the 7-vs-1 majority. This is the thin-grass-cap case that
    // the old majority rule destroyed.
    {
        mira::DenseGrid src(2);
        fill_type(src, static_cast<uint8_t>(mira::mat::DIRT));
        src.set_type(0, 1, 0, mira::mat::GRASS); // one grass voxel in the TOP row

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.type_at(0,0,0) == mira::mat::GRASS,
              "top-wins 1grass(top)+7dirt: lone top grass beats dirt majority");
    }

    // ========================================================================
    // TEST 5c: TOP-WINS — grass only in the BOTTOM row does NOT win
    // ========================================================================
    // Symmetric guard: if the only grass is in the BOTTOM row (y = 0) and the
    // top row is dirt, the surface material is dirt, so dirt must win. This
    // proves we scan the correct (world-up) direction and don't just pick grass
    // wherever it appears.
    {
        mira::DenseGrid src(2);
        fill_type(src, static_cast<uint8_t>(mira::mat::DIRT)); // top row dirt
        // Bottom row (y = 0) all grass; top row (y = 1) stays dirt.
        src.set_type(0, 0, 0, mira::mat::GRASS);
        src.set_type(1, 0, 0, mira::mat::GRASS);
        src.set_type(0, 0, 1, mira::mat::GRASS);
        src.set_type(1, 0, 1, mira::mat::GRASS);

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.type_at(0,0,0) == mira::mat::DIRT,
              "top-wins grass-in-bottom-only: top (dirt) wins, not the buried grass");
    }

    // ========================================================================
    // TEST 5d: DECISIVE REGRESSION GATE — grass cap survives EVERY LOD 1..5
    // ========================================================================
    // Build a realistic 32^3 chunk column matching the generator's banding:
    //   grass(1 voxel on top) + dirt(3) + stone(28), stacked along world-up = Y.
    // Then downsample to EVERY lod level 1..5 and assert that the TOP solid
    // voxel's id == GRASS at every level (so green reaches the rendered top
    // face), AND that no level produced air-where-solid (the column is fully
    // solid, so the coarse column must be fully solid too).
    //
    // y = 31 (highest)         -> GRASS  (1 voxel thick top cap)
    // y = 30, 29, 28           -> DIRT   (3 voxels)
    // y = 27 .. 0              -> STONE  (28 voxels)
    {
        mira::DenseGrid src(32);
        fill_type(src, static_cast<uint8_t>(mira::mat::AIR));
        for (int z = 0; z < 32; ++z)
        for (int x = 0; x < 32; ++x)
        {
            for (int y = 0; y <= 27; ++y)  src.set_type(x, y, z, mira::mat::STONE);
            for (int y = 28; y <= 30; ++y) src.set_type(x, y, z, mira::mat::DIRT);
            src.set_type(x, 31, z, mira::mat::GRASS); // 1-voxel grass cap on top
        }

        for (int L = 1; L <= 5; ++L) {
            mira::DenseGrid out = mira::lod::downsample_to_lod(src, L);
            const int s = out.side;
            CHECK(s == (32 >> L), "grass-cap LOD: coarse side is 32>>L");
            if (s <= 0) continue;

            // For each (x,z) coarse column, the TOP solid voxel (highest Y) must
            // be GRASS, and every voxel in the column must be solid (no holes).
            bool all_top_grass = true;
            bool any_hole = false;
            for (int z = 0; z < s; ++z)
            for (int x = 0; x < s; ++x)
            {
                // Find the topmost solid voxel in this coarse column.
                int top_y = -1;
                for (int y = s - 1; y >= 0; --y) {
                    const uint8_t t = out.type_at(x, y, z);
                    if (t != mira::mat::AIR && !mira::mat::is_passthrough(t)) {
                        top_y = y;
                        break;
                    }
                }
                if (top_y < 0) { any_hole = true; continue; }
                if (out.type_at(x, top_y, z) != mira::mat::GRASS) all_top_grass = false;
                // The whole input column was solid, so every coarse voxel from
                // 0..top_y must be solid too (the cap can't sit on a hole).
                for (int y = 0; y <= top_y; ++y) {
                    const uint8_t t = out.type_at(x, y, z);
                    if (t == mira::mat::AIR || mira::mat::is_passthrough(t)) any_hole = true;
                }
                // The coarse voxel's id must never map to a white base color
                // (the grey/white rock bug we are fixing). GRASS is green; a
                // sanity check that the top id is specifically GRASS covers this.
            }
            CHECK(all_top_grass, "grass-cap LOD: top solid voxel is GRASS at this L");
            CHECK(!any_hole,     "grass-cap LOD: no air-where-solid in the coarse column");
        }
    }

    // ========================================================================
    // TEST 6: water max-level — codec encodes inputs, codec reads output
    // ========================================================================
    // Build a 2x2x2 where all 8 voxels are dry EXCEPT two:
    //   - one at level 3 (flowing, direction POS_X)
    //   - one at level 7 (still)
    // The output water byte should decode to level 7 (the max), with direction
    // STILL and source=false (flow state is intentionally dropped at LOD).
    //
    // We use WaterByteCodec::pack to build the input bytes and
    // WaterByteCodec::level_of / dir_of / is_source to verify the output —
    // so the test never hardcodes any bit positions.
    {
        // Build two input water bytes via the codec.
        const uint8_t w_level3 = static_cast<uint8_t>(
            mira::WaterByteCodec::pack(3, false, mira::WaterByteCodec::DIR_POS_X));
        const uint8_t w_level7 = static_cast<uint8_t>(
            mira::WaterByteCodec::pack(7, false, mira::WaterByteCodec::DIR_STILL));

        mira::DenseGrid src(2);
        fill_type(src, static_cast<uint8_t>(mira::mat::AIR));
        // Mark the two water voxels as full-fluid type so the water byte is
        // meaningful (type channel: water at level L uses WATER_FLUID_BASE_ID + L - 1).
        src.set_type(0, 0, 0, static_cast<uint8_t>(
            mira::mat::WATER_FLUID_BASE_ID + 3 - 1)); // level 3 fluid id
        src.set_water(0, 0, 0, w_level3);

        src.set_type(1, 0, 0, static_cast<uint8_t>(
            mira::mat::WATER_FLUID_BASE_ID + 7 - 1)); // level 7 fluid id
        src.set_water(1, 0, 0, w_level7);
        // The other 6 voxels remain air with water byte 0.

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.side == 1, "water max-level: output side is 1");

        const uint8_t out_w = out.water_at(0, 0, 0);
        CHECK(mira::WaterByteCodec::is_water(out_w),
              "water max-level: output water byte is non-zero (is_water)");
        CHECK(mira::WaterByteCodec::level_of(out_w) == 7,
              "water max-level: output level is 7 (the max of 3 and 7)");
        CHECK(mira::WaterByteCodec::dir_of(out_w) == mira::WaterByteCodec::DIR_STILL,
              "water max-level: flow direction is STILL (dropped at LOD)");
        CHECK(!mira::WaterByteCodec::is_source(out_w),
              "water max-level: source flag is false (dropped at LOD)");
    }

    // ========================================================================
    // TEST 7a: downsample_to_lod — 4^3 at lod 2 -> side 1
    // ========================================================================
    // A 4x4x4 all-stone grid halved twice: 4 -> 2 -> 1.
    {
        mira::DenseGrid src(4);
        fill_type(src, static_cast<uint8_t>(mira::mat::STONE));

        mira::DenseGrid out = mira::lod::downsample_to_lod(src, 2);

        CHECK(out.side == 1, "chain lod 2 on side-4: output side is 1");
        CHECK(out.type_at(0,0,0) == mira::mat::STONE,
              "chain lod 2 on side-4: stone preserved through two halvings");
    }

    // ========================================================================
    // TEST 7b: downsample_to_lod — 32^3 at lod 1 -> side 16
    // ========================================================================
    {
        mira::DenseGrid src(32);
        fill_type(src, static_cast<uint8_t>(mira::mat::DIRT));

        mira::DenseGrid out = mira::lod::downsample_to_lod(src, 1);

        CHECK(out.side == 16, "chain lod 1 on side-32: output side is 16");
        // Spot-check a few output voxels.
        CHECK(out.type_at(0,0,0)   == mira::mat::DIRT, "lod1 on 32^3: voxel (0,0,0) is dirt");
        CHECK(out.type_at(15,15,15) == mira::mat::DIRT, "lod1 on 32^3: voxel (15,15,15) is dirt");
    }

    // ========================================================================
    // TEST 7c: downsample_to_lod — lod 0 returns a copy (no reduction)
    // ========================================================================
    {
        mira::DenseGrid src(8);
        fill_type(src, static_cast<uint8_t>(mira::mat::GRASS));
        src.set_type(3, 3, 3, mira::mat::STONE); // a marker to confirm copy fidelity

        mira::DenseGrid out = mira::lod::downsample_to_lod(src, 0);

        CHECK(out.side == 8, "lod 0: output side unchanged (8)");
        CHECK(out.type_at(3,3,3) == mira::mat::STONE,
              "lod 0: marker voxel preserved (it is a copy, not a reduction)");
    }

    // ========================================================================
    // TEST 8: odd side -> contract guard -> returns empty grid (side 0)
    // ========================================================================
    // A 3x3x3 grid cannot be evenly halved.  The function must return an empty
    // grid (side == 0) rather than reading out of bounds or asserting fatally.
    // (In release builds the assert is disabled; we test the fallback return.)
    {
        mira::DenseGrid src(3);
        fill_type(src, static_cast<uint8_t>(mira::mat::STONE));

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.side == 0,
              "odd-side contract: downsample_half on side-3 returns empty grid (side 0)");
    }

    // ========================================================================
    // Final verdict
    // ========================================================================
    std::printf("[lod     ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
