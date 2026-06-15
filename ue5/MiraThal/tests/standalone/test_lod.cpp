// test_lod.cpp — headless parity harness for Core/LodDownsample.h.
//   cd tests/standalone && ./build.sh lod
//
// Covers:
//   - all-stone 2^3 -> 1^3 = stone
//   - 7 air + 1 stone -> stone (solid wins over majority air)
//   - 8 air -> air
//   - 7 air + 1 flora (grass blade id 24) -> air (passthrough != solid)
//   - majority + tie-break across two solid ids
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
    // TEST 5a: majority — more of id A than id B -> picks A
    // ========================================================================
    // Build a 2x2x2 with 5 STONE (id 1) and 3 DIRT (id 2).
    // Stone wins outright (5 > 3).
    {
        mira::DenseGrid src(2);
        // Fill all 8 with DIRT first, then overwrite 5 with STONE.
        fill_type(src, static_cast<uint8_t>(mira::mat::DIRT));
        // STONE at (0,0,0), (1,0,0), (0,1,0), (1,1,0), (0,0,1) => 5 slots
        src.set_type(0, 0, 0, mira::mat::STONE);
        src.set_type(1, 0, 0, mira::mat::STONE);
        src.set_type(0, 1, 0, mira::mat::STONE);
        src.set_type(1, 1, 0, mira::mat::STONE);
        src.set_type(0, 0, 1, mira::mat::STONE);
        // Remaining 3 slots stay DIRT.

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.type_at(0,0,0) == mira::mat::STONE,
              "majority 5stone+3dirt: stone wins (more frequent)");
    }

    // ========================================================================
    // TEST 5b: tie-break — equal count, smaller id wins
    // ========================================================================
    // 4 STONE (id 1) and 4 DIRT (id 2) -> tie -> smaller id = STONE (1).
    {
        mira::DenseGrid src(2);
        fill_type(src, static_cast<uint8_t>(mira::mat::DIRT));
        src.set_type(0, 0, 0, mira::mat::STONE);
        src.set_type(1, 0, 0, mira::mat::STONE);
        src.set_type(0, 1, 0, mira::mat::STONE);
        src.set_type(1, 1, 0, mira::mat::STONE);
        // (0,0,1), (1,0,1), (0,1,1), (1,1,1) remain DIRT

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.type_at(0,0,0) == mira::mat::STONE,
              "tie-break 4stone+4dirt: smaller id (stone=1) wins over dirt=2");
    }

    // ========================================================================
    // TEST 5c: tie-break second scenario — 4 DIRT (id 2) vs 4 MARBLE (id 9)
    //          -> tie -> smaller id = DIRT (2)
    // ========================================================================
    {
        mira::DenseGrid src(2);
        fill_type(src, static_cast<uint8_t>(mira::mat::MARBLE));
        src.set_type(0, 0, 0, mira::mat::DIRT);
        src.set_type(1, 0, 0, mira::mat::DIRT);
        src.set_type(0, 1, 0, mira::mat::DIRT);
        src.set_type(1, 1, 0, mira::mat::DIRT);

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.type_at(0,0,0) == mira::mat::DIRT,
              "tie-break 4dirt+4marble: smaller id (dirt=2) wins over marble=9");
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
