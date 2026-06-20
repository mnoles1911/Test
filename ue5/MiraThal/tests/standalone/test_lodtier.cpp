// test_lodtier.cpp — headless harness for Core/LodTier.h (distance -> LOD tier).
//   cd tests/standalone && ./build.sh lodtier
//
// Covers:
//   - Monotonic: increasing distance never lowers the LOD (plain rule).
//   - Exact thresholds: a column at each boundary picks the expected tier.
//   - Hysteresis: a column oscillating +/-1 chunk around a boundary does NOT
//     flip LOD until it crosses threshold + margin; a full crossing DOES flip it.
//   - Sanity: downsampling a known 4x4x4 solid block yields a 2x2x2 solid block
//     of the same material (drives LodDownsample, the matching render path).

#include <cstdio>
#include <cstdint>

#include "Core/LodTier.h"        // the unit under test
#include "Core/LodDownsample.h"  // the matching render path (for the sanity check)
#include "Core/VoxelChunk.h"     // DenseGrid
#include "Core/MaterialIds.h"    // mat::STONE
#include "Core/ChunkCoords.h"    // coords::CHUNK (documents the distance unit)

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
// main
// ---------------------------------------------------------------------------
int main() {
    using namespace mira::lodtier;

    // Default thresholds: t0_max=8, t1_max=24, t2_max=64 -> LOD 0/1/2/3.
    const LodTierConfig cfg{};

    // ========================================================================
    // TEST 1: MONOTONIC — sweep distance outward, LOD must never decrease.
    // ========================================================================
    // Walk every distance from 0 out past the last threshold and assert that the
    // LOD this column gets is always >= the LOD at the previous (nearer) step.
    // This is the core promise: farther away is never MORE detailed.
    {
        int prev = lod_for_distance(0, cfg);
        bool ok = true;
        for (int d = 0; d <= 80; ++d) {
            const int lod = lod_for_distance(d, cfg);
            if (lod < prev) ok = false;   // a decrease would break monotonicity
            CHECK(lod >= 0 && lod <= MAX_LOD, "monotonic: LOD stays within 0..3");
            prev = lod;
        }
        CHECK(ok, "monotonic: increasing distance never lowers the LOD");

        // Negative distance is treated as "on top of the focus" -> finest LOD.
        CHECK(lod_for_distance(-5, cfg) == 0, "negative distance clamps to LOD 0");
    }

    // ========================================================================
    // TEST 2: EXACT THRESHOLDS — boundaries map to the expected tier.
    // ========================================================================
    // "<= t0_max" is LOD 0, so distance == t0_max is still LOD 0 and t0_max+1
    // is the first LOD 1. We check each boundary and the step just past it,
    // reading the thresholds from cfg (no hardcoded 8/24/64 in the assertions).
    {
        // T0 / LOD 0 band.
        CHECK(lod_for_distance(0, cfg)               == 0, "dist 0 -> LOD 0");
        CHECK(lod_for_distance(cfg.t0_max, cfg)      == 0, "dist == t0_max -> LOD 0 (inclusive)");
        CHECK(lod_for_distance(cfg.t0_max + 1, cfg)  == 1, "dist == t0_max+1 -> LOD 1");

        // LOD 1 band.
        CHECK(lod_for_distance(cfg.t1_max, cfg)      == 1, "dist == t1_max -> LOD 1 (inclusive)");
        CHECK(lod_for_distance(cfg.t1_max + 1, cfg)  == 2, "dist == t1_max+1 -> LOD 2");

        // LOD 2 band, and the jump into the coarsest meshed LOD 3.
        CHECK(lod_for_distance(cfg.t2_max, cfg)      == 2, "dist == t2_max -> LOD 2 (inclusive)");
        CHECK(lod_for_distance(cfg.t2_max + 1, cfg)  == 3, "dist == t2_max+1 -> LOD 3");
        CHECK(lod_for_distance(10000, cfg)           == MAX_LOD, "very far -> clamps to MAX_LOD (3)");
    }

    // ========================================================================
    // TEST 3: HYSTERESIS — sticky near a boundary; flips only on a real crossing.
    // ========================================================================
    // Use the t0_max boundary (default 8) with a margin of 2. The sticky band is
    // [t0_max - margin .. t0_max + margin] = [6..10] for this boundary.
    {
        const int margin = 2;
        const int b      = cfg.t0_max; // the LOD 0 <-> LOD 1 boundary (8 by default)

        // --- Oscillating +/-1 chunk around the boundary while currently LOD 0:
        // the column should HOLD LOD 0 the whole time, even at b and b+1, because
        // it hasn't yet moved a full margin past b.
        {
            int cur = 0; // currently full-res
            // Jitter b-1, b, b+1, b, b-1, b+1 ... — none exceed b+margin.
            const int jitter[] = { b - 1, b, b + 1, b, b - 1, b + 1, b };
            bool held = true;
            for (int d : jitter) {
                cur = lod_for_distance_hys(d, cur, cfg, margin);
                if (cur != 0) held = false;
            }
            CHECK(held, "hysteresis: oscillating +/-1 around boundary keeps LOD 0 (no flip)");
        }

        // --- A FULL outward crossing past b+margin DOES step up to LOD 1.
        {
            int cur = 0;
            cur = lod_for_distance_hys(b + 1, cur, cfg, margin);
            CHECK(cur == 0, "hysteresis: just past boundary (b+1) still holds LOD 0");
            cur = lod_for_distance_hys(b + margin, cur, cfg, margin);
            CHECK(cur == 0, "hysteresis: at b+margin still holds (need to EXCEED it)");
            cur = lod_for_distance_hys(b + margin + 1, cur, cfg, margin);
            CHECK(cur == 1, "hysteresis: past b+margin commits the crossing -> LOD 1");
        }

        // --- Symmetric: coming back IN from LOD 1 must reach b-margin before
        // dropping back to LOD 0; sitting just inside the boundary holds LOD 1.
        {
            int cur = 1;
            cur = lod_for_distance_hys(b, cur, cfg, margin);
            CHECK(cur == 1, "hysteresis: returning to exactly b still holds LOD 1");
            cur = lod_for_distance_hys(b - margin + 1, cur, cfg, margin);
            CHECK(cur == 1, "hysteresis: at b-margin+1 still holds LOD 1");
            cur = lod_for_distance_hys(b - margin, cur, cfg, margin);
            CHECK(cur == 0, "hysteresis: reaching b-margin commits the return -> LOD 0");
        }

        // --- margin 0 must behave exactly like the plain rule (no stickiness).
        {
            CHECK(lod_for_distance_hys(b + 1, 0, cfg, 0) == lod_for_distance(b + 1, cfg),
                  "hysteresis: margin 0 matches the plain rule (coarser)");
            CHECK(lod_for_distance_hys(b, 1, cfg, 0) == lod_for_distance(b, cfg),
                  "hysteresis: margin 0 matches the plain rule (finer)");
        }

        // --- One step at a time: a huge outward jump from LOD 0 only advances
        // ONE level per call, so meshes pass through the in-between tiers.
        {
            int cur = 0;
            cur = lod_for_distance_hys(10000, cur, cfg, margin);
            CHECK(cur == 1, "hysteresis: giant jump advances only one level per call (0->1)");
        }
    }

    // ========================================================================
    // TEST 4: SANITY — downsample a 4x4x4 solid block -> 2x2x2 solid, same mat.
    // ========================================================================
    // This ties the tier DECISION to the tier RENDER path: when LodTier says
    // "LOD 1", the renderer calls downsample_half. A solid block must stay solid
    // (no holes at distance) and keep its material (majority rule, all-stone).
    {
        mira::DenseGrid src(4);
        src.fill_type(static_cast<uint8_t>(mira::mat::STONE));
        src.fill_water(0);

        mira::DenseGrid out = mira::lod::downsample_half(src);

        CHECK(out.side == 2, "sanity: 4x4x4 downsample_half -> side 2");
        bool all_stone = true;
        for (int z = 0; z < 2; ++z)
            for (int y = 0; y < 2; ++y)
                for (int x = 0; x < 2; ++x)
                    if (out.type_at(x, y, z) != mira::mat::STONE) all_stone = false;
        CHECK(all_stone, "sanity: solid 4^3 stays a solid 2^3 of the same material (stone)");
    }

    // ========================================================================
    // Final verdict
    // ========================================================================
    std::printf("[lodtier ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
