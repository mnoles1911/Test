// test_gravityfall.cpp — integration harness for "loose materials fall when you
// dig out their support" (M3c gravity-on-dig), at the Core level so it validates
// the EXACT logic AVoxelWorld runs after a carve — without Unreal.
//   cd tests/standalone && ./build.sh gravityfall
//
// Scenario: a stone floor (anchored ground) with a SAND column floating above it,
// the supporting stone beneath the sand already dug away. We run analyze_bubble
// over the brickmap, then apply its LOOSE column-fall moves back into the brickmap
// and assert the sand dropped down to rest on the floor (and only sand moved —
// stone is FALL_NEVER, so it stays put even when unsupported, Minecraft-style).
//
// Prints "[gravityfall] PASS/FAIL"; returns 0 on success, 1 on any failure.

#include <cstdio>
#include <vector>
#include <functional>

#include "Core/VoxelGravity.h"
#include "Core/Brickmap.h"
#include "Core/MaterialIds.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;

int main() {
    const int SIDE = 8;

    Brickmap bm;
    // Anchored stone floor: y = 0,1 across the whole bubble footprint.
    for (int z = 0; z < SIDE; ++z)
    for (int x = 0; x < SIDE; ++x) {
        bm.set_type(Vec3i(x, 0, z), mat::STONE);
        bm.set_type(Vec3i(x, 1, z), mat::STONE);
    }
    // A floating SAND column at (4, *, 4): y = 4,5,6. Air at y=2,3 below it (the
    // support was dug out), so it's disconnected from the anchored floor.
    bm.set_type(Vec3i(4, 4, 4), mat::SAND);
    bm.set_type(Vec3i(4, 5, 4), mat::SAND);
    bm.set_type(Vec3i(4, 6, 4), mat::SAND);

    // Precondition.
    CHECK(bm.type_at(Vec3i(4, 6, 4)) == mat::SAND, "precondition: sand floats at y=6");
    CHECK(bm.type_at(Vec3i(4, 2, 4)) == mat::AIR,  "precondition: air under the sand");

    // ---- Run the gravity analysis over the bubble (reads the brickmap) ----
    auto get_packed = [&bm](const Vec3i& local) -> int32_t {
        return static_cast<int32_t>(bm.type_at(local)); // bubble-local == world here
    };
    auto fall_of = [](int id) -> int {
        if (id == mat::SAND) return FALL_LOOSE;  // sand/gravel slides down
        return FALL_NEVER;                       // everything else stays (no rigid collapse v1)
    };

    GravityResult res = analyze_bubble(SIDE, get_packed, fall_of);

    CHECK(!res.loose.empty(), "analysis found loose voxels to drop");
    CHECK(res.unanchored_cluster_count == 0, "no FALL_NEVER clusters reported (only sand is loose)");

    // ---- Apply the LOOSE moves back into the brickmap (what AVoxelWorld does) ----
    // Two passes so a cell that is both a source and a destination resolves right:
    // clear every 'from', then write every 'to'.
    for (const LooseMove& m : res.loose) {
        bm.set_type(m.from, mat::AIR);
    }
    for (const LooseMove& m : res.loose) {
        bm.set_type(m.to, static_cast<uint8_t>(m.packed & 0xFF));
    }

    // ---- The sand should now rest on the floor: y = 2,3,4 sand; 5,6 air ----
    CHECK(bm.type_at(Vec3i(4, 2, 4)) == mat::SAND, "sand fell to y=2 (on the floor)");
    CHECK(bm.type_at(Vec3i(4, 3, 4)) == mat::SAND, "sand stacked at y=3");
    CHECK(bm.type_at(Vec3i(4, 4, 4)) == mat::SAND, "sand stacked at y=4");
    CHECK(bm.type_at(Vec3i(4, 5, 4)) == mat::AIR,  "y=5 now empty (sand left)");
    CHECK(bm.type_at(Vec3i(4, 6, 4)) == mat::AIR,  "y=6 now empty (sand left)");

    // Floor untouched, and total sand conserved (3 in, 3 out).
    CHECK(bm.type_at(Vec3i(4, 1, 4)) == mat::STONE, "anchored floor unchanged");
    int sand_count = 0;
    for (int y = 0; y < SIDE; ++y) if (bm.type_at(Vec3i(4, y, 4)) == mat::SAND) ++sand_count;
    CHECK(sand_count == 3, "sand voxels conserved (3)");

    std::printf("[gravityfall] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
