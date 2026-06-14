// test_gravity.cpp — SELF-CONTAINED parity harness for the engine-agnostic
// voxel gravity / sever flood-fill (Core/VoxelGravity.{h,cpp}).
//
// Compile + run (from this directory, tests/standalone/):
//   clang++ -std=c++17 -I ../../Source/MiraThalVoxel/Public test_gravity.cpp ../../Source/MiraThalVoxel/Private/Core/VoxelGravity.cpp -o /tmp/test_gravity && /tmp/test_gravity
//
// WHY THIS EXISTS (plain English):
// Unreal can't build in the dev container, but the Core gravity math is pure
// C++17 — so we prove it HERE under clang, exactly like the Godot `gravity`
// headless selector proves the GD reference. Each test builds a tiny synthetic
// world by hand (a lambda standing in for the real voxel buffer) and checks the
// flood-fill answers the one question that matters: "what is floating and how
// does it fall?"
//
// The four cases mirror the task brief:
//   1. A floating block detaches -> reported as a falling cluster.
//   2. A block touching the ground does NOT fall.
//   3. A chopped "tree" column severs as ONE connected cluster.
//   4. Flora/decoration (ids 24..28) does not anchor a cluster (pass-through air).
// A fifth case exercises the LOOSE column-fall and PICKUP partition, and a
// sixth drives sever_follow_bfs (the tree-follow extension BFS).
//
// Print style follows test_main.cpp: a "[gravity ] PASS"/"FAIL" line, exit 0 on
// success / non-zero on failure.

#include <cstdio>
#include <string>
#include <vector>
#include <unordered_map>
#include <functional>

#include "Core/VoxelGravity.h"

// ----------------------------------------------------------------------------
// Minimal assertion plumbing (same shape as test_main.cpp — zero-setup).
// ----------------------------------------------------------------------------
static int g_checks = 0;
static int g_fails  = 0;
static const char* g_current = "gravity";

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!(cond)) {                                                          \
            ++g_fails;                                                          \
            std::printf("  FAIL [%s] %s  (%s:%d)\n",                            \
                        g_current, (msg), __FILE__, __LINE__);                  \
        }                                                                       \
    } while (0)

#define CHECK_EQ(a, b, msg)                                                     \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!((a) == (b))) {                                                    \
            ++g_fails;                                                          \
            std::printf("  FAIL [%s] %s  expected=%lld got=%lld  (%s:%d)\n",    \
                        g_current, (msg),                                       \
                        (long long)(b), (long long)(a), __FILE__, __LINE__);    \
        }                                                                       \
    } while (0)

// ----------------------------------------------------------------------------
// Tiny synthetic-world helper: a sparse map from bubble-local coord -> packed
// TYPE value. Stands in for the real voxel buffer the predicate reads.
// ----------------------------------------------------------------------------
namespace {

// A couple of material ids for the tests. Low byte = material id; the gravity
// code only looks at the low byte (& 0xFF) for fall_behavior + flora checks.
constexpr int MAT_STONE = 1;   // SOLID-ish; cluster-bound
constexpr int MAT_DIRT  = 2;   // we'll mark this LOOSE
constexpr int MAT_GEM   = 3;   // we'll mark this PICKUP_DROP
constexpr int MAT_GRASS = 24;  // flora pass-through (R4)
constexpr int MAT_PEBBLE = 27; // surface-detail pass-through (D1)

struct World {
    std::unordered_map<mira::Vec3i, int32_t> cells;

    void set(int x, int y, int z, int32_t packed) {
        cells[mira::Vec3i(x, y, z)] = packed;
    }

    // The injected predicate: packed value at a coord, 0 = air.
    int32_t get(const mira::Vec3i& p) const {
        auto it = cells.find(p);
        return it == cells.end() ? 0 : it->second;
    }
};

// fall_table: most ids are unknown -> FALL_NEVER (cluster path). We make DIRT
// loose and GEM a pickup so the partition branches are all exercised.
int fall_of(int mat_id) {
    switch (mat_id) {
        case MAT_DIRT: return mira::FALL_LOOSE;
        case MAT_GEM:  return mira::FALL_PICKUP_DROP;
        default:       return mira::FALL_NEVER;   // STONE + anything else cluster
    }
}

// ----------------------------------------------------------------------------
// Case 1: a floating block detaches -> one falling cluster.
// A single stone voxel up at y=5 with NOTHING below it. Ground floor (y==0) is
// the only anchor seed, so the flood can't reach it.
// ----------------------------------------------------------------------------
void test_floating_block_falls() {
    const int side = 8;
    World w;
    w.set(3, 5, 3, MAT_STONE);   // lonely floating block

    auto result = mira::analyze_bubble(
        side,
        [&](const mira::Vec3i& p) { return w.get(p); },
        fall_of);

    CHECK_EQ(result.bubble_solid_count, 1, "one solid voxel in the bubble");
    CHECK_EQ((int)result.cluster_counts.size(), 1, "floating block = exactly one cluster");
    CHECK_EQ(result.unanchored_cluster_count, 1, "the one cluster has one voxel");
    if (result.cluster_counts.size() == 1) {
        CHECK_EQ(result.cluster_counts[0], 1, "cluster size is 1");
    }
    CHECK_EQ((int)result.loose.size(),  0, "nothing is loose");
    CHECK_EQ((int)result.pickup.size(), 0, "nothing is a pickup");
}

// ----------------------------------------------------------------------------
// Case 2: a block connected to ground does NOT fall.
// A vertical stone pillar from y=0 (the ground) up to y=5. Every cell floods
// "anchored" from the bottom face, so nothing detaches.
// ----------------------------------------------------------------------------
void test_grounded_block_stays() {
    const int side = 8;
    World w;
    for (int y = 0; y <= 5; ++y) {
        w.set(3, y, 3, MAT_STONE);
    }

    auto result = mira::analyze_bubble(
        side,
        [&](const mira::Vec3i& p) { return w.get(p); },
        fall_of);

    CHECK_EQ(result.bubble_solid_count, 6, "six solid voxels (y=0..5)");
    CHECK_EQ((int)result.cluster_counts.size(), 0, "grounded pillar = no falling clusters");
    CHECK_EQ(result.unanchored_cluster_count, 0, "nothing unanchored");
    CHECK_EQ((int)result.loose.size(),  0, "nothing loose");
    CHECK_EQ((int)result.pickup.size(), 0, "nothing picked up");
}

// ----------------------------------------------------------------------------
// Case 3: a chopped "tree" column severs as ONE cluster.
// A stone trunk from y=2 to y=6 — the base (y=0,1) was already chopped away, so
// the whole column floats free of the ground and must come down as a single
// connected lump, not five separate single-voxel clusters.
// ----------------------------------------------------------------------------
void test_chopped_tree_one_cluster() {
    const int side = 8;
    World w;
    for (int y = 2; y <= 6; ++y) {     // trunk floats above the chopped base
        w.set(4, y, 4, MAT_STONE);
    }

    auto result = mira::analyze_bubble(
        side,
        [&](const mira::Vec3i& p) { return w.get(p); },
        fall_of);

    CHECK_EQ(result.bubble_solid_count, 5, "five trunk voxels");
    CHECK_EQ((int)result.cluster_counts.size(), 1, "severed trunk = ONE cluster");
    if (result.cluster_counts.size() == 1) {
        CHECK_EQ(result.cluster_counts[0], 5, "the cluster carries all five trunk voxels");
    }
    CHECK_EQ(result.unanchored_cluster_count, 5, "five voxels accounted for in clusters");
}

// ----------------------------------------------------------------------------
// Case 4: flora/decoration does not anchor a cluster.
// Same floating stone block as case 1, but now we pile grass + a pebble UNDER it
// forming a "bridge" down to the ground floor. If flora anchored, the block
// would be considered grounded. It must NOT — flora is pass-through air, so the
// block still detaches as a cluster, and the flora itself never shows up as a
// solid, a cluster, or an anchor.
// ----------------------------------------------------------------------------
void test_flora_does_not_anchor() {
    const int side = 8;
    World w;
    w.set(3, 5, 3, MAT_STONE);            // the floating block
    // A column of decoration from the ground (y=0) up to just under the block.
    for (int y = 0; y <= 4; ++y) {
        w.set(3, y, 3, (y % 2 == 0) ? MAT_GRASS : MAT_PEBBLE);
    }

    auto result = mira::analyze_bubble(
        side,
        [&](const mira::Vec3i& p) { return w.get(p); },
        fall_of);

    // Only the stone counts as solid — the 5 decoration cells are skipped.
    CHECK_EQ(result.bubble_solid_count, 1, "flora/pebbles are not solid");
    CHECK_EQ((int)result.cluster_counts.size(), 1, "block still detaches despite the flora bridge");
    CHECK_EQ(result.unanchored_cluster_count, 1, "exactly the one stone voxel falls");
    if (result.cluster_counts.size() == 1) {
        CHECK_EQ(result.cluster_counts[0], 1, "no flora rode along in the cluster");
    }
}

// ----------------------------------------------------------------------------
// Case 5: LOOSE column-fall + PICKUP partition.
// A loose DIRT cell floating at y=4 (column otherwise empty) slides straight
// down to y=0. A GEM cell floating elsewhere becomes a pickup, not a cluster.
// ----------------------------------------------------------------------------
void test_loose_and_pickup() {
    const int side = 8;
    World w;
    w.set(2, 4, 2, MAT_DIRT);    // loose -> should fall to y=0
    w.set(6, 3, 6, MAT_GEM);     // pickup_drop -> pops out, no cluster

    auto result = mira::analyze_bubble(
        side,
        [&](const mira::Vec3i& p) { return w.get(p); },
        fall_of);

    CHECK_EQ(result.bubble_solid_count, 2, "two solids: one dirt, one gem");
    CHECK_EQ((int)result.cluster_counts.size(), 0, "loose + pickup never form clusters");
    CHECK_EQ((int)result.loose.size(),  1, "one loose move emitted");
    CHECK_EQ((int)result.pickup.size(), 1, "one pickup emitted");
    if (result.loose.size() == 1) {
        CHECK_EQ(result.loose[0].from.y, 4, "dirt started at y=4");
        CHECK_EQ(result.loose[0].to.y,   0, "dirt fell all the way to the ground");
        CHECK_EQ(result.loose[0].from.x, 2, "loose move stays in its column (x)");
        CHECK_EQ(result.loose[0].to.z,   2, "loose move stays in its column (z)");
    }
    if (result.pickup.size() == 1) {
        CHECK_EQ(result.pickup[0].pos.x, 6, "gem pickup at x=6");
        CHECK_EQ(result.pickup[0].packed & 0xFF, MAT_GEM, "pickup carries the gem id");
    }
}

// ----------------------------------------------------------------------------
// Case 6: sever_follow_bfs — chase a trunk upward as one piece.
// A tall stone trunk in a thin extension box. Seed just above the bubble roof
// (box-local y=0 here, at the trunk's x/z). The flood should carry the whole
// trunk without touching a wall (the trunk sits in the box interior and stops
// below the top), so neither abort flag fires.
// ----------------------------------------------------------------------------
void test_sever_follow() {
    // Box wider than the trunk so it doesn't hit the side walls, taller than the
    // trunk so it doesn't hit the top.
    const mira::Vec3i box_size(5, 10, 5);
    World w;
    // Trunk at box-local (2, y, 2) for y = 0..6. (Interior column.)
    for (int y = 0; y <= 6; ++y) {
        w.set(2, y, 2, MAT_STONE);
    }

    // is_solid_at: non-air, non-flora. (No water in this synthetic box.)
    auto is_solid_at = [&](const mira::Vec3i& p) {
        const int32_t v = w.get(p);
        if ((v & 0xFF) == 0)        return false;   // air
        if (mira::IsFloraType(v))   return false;   // flora pass-through
        return true;
    };

    std::vector<mira::Vec3i> seeds = { mira::Vec3i(2, 0, 2) };
    auto result = mira::sever_follow_bfs(
        box_size, seeds, is_solid_at,
        [&](const mira::Vec3i& p) { return w.get(p); },
        /*max_voxels=*/1000);

    CHECK_EQ((int)result.voxels.size(), 7, "sever-follow carried the whole 7-voxel trunk");
    CHECK(!result.touched_side, "trunk stays clear of the side walls");
    CHECK(!result.touched_top,  "trunk stops below the box top");

    // And the conservative abort: a trunk leaning into the side wall must flag
    // touched_side so the caller falls back to the safe salami behaviour.
    World w2;
    for (int y = 0; y <= 6; ++y) {
        w2.set(0, y, 2, MAT_STONE);   // x == 0 is a side wall
    }
    auto is_solid2 = [&](const mira::Vec3i& p) {
        const int32_t v = w2.get(p);
        if ((v & 0xFF) == 0)      return false;
        if (mira::IsFloraType(v)) return false;
        return true;
    };
    std::vector<mira::Vec3i> seeds2 = { mira::Vec3i(0, 0, 2) };
    auto result2 = mira::sever_follow_bfs(
        box_size, seeds2, is_solid2,
        [&](const mira::Vec3i& p) { return w2.get(p); },
        /*max_voxels=*/1000);
    CHECK(result2.touched_side, "wall-hugging trunk trips the conservative side abort");
}

} // namespace

// ----------------------------------------------------------------------------
// Driver — one "[gravity ] PASS/FAIL" line, exit code mirrors test_main.cpp.
// ----------------------------------------------------------------------------
int main() {
    const int before = g_fails;

    test_floating_block_falls();
    test_grounded_block_stays();
    test_chopped_tree_one_cluster();
    test_flora_does_not_anchor();
    test_loose_and_pickup();
    test_sever_follow();

    std::printf("[%-8s] %s\n", "gravity", (g_fails == before) ? "PASS" : "FAIL");
    std::printf("----\n1 selector(s), %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
