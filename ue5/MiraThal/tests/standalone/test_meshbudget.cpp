// test_meshbudget.cpp — parity harness for Core/MeshBudget.h.
//   cd tests/standalone && ./build.sh meshbudget
//
// Covers:
//   - Dedup: marking the same coord twice gives pending_count == 1.
//   - Tier merge: re-marking with a more urgent (smaller) tier keeps the
//     smaller tier; re-marking with a LESS urgent tier does NOT downgrade.
//   - Priority order: lower-tier chunks drain before higher-tier ones,
//     regardless of distance from camera.
//   - Distance order: within the same tier, nearer chunks drain first.
//   - Quad budget: several chunks each costing 100 quads against a 250-quad
//     budget drains exactly 2; the rest stay pending for the next call.
//   - At-least-one anti-deadlock: a single chunk whose est_quads exceeds
//     the budget still drains (returns 1 chunk, no infinite stall).
//   - is_dirty / clear / pending_count basic behaviour.
//   - Determinism: same marks + same camera → same drain order across two
//     independent MeshBudget instances.

#include <cstdio>
#include <vector>
#include <algorithm>

#include "Core/MeshBudget.h"

using namespace mira;

// ---------------------------------------------------------------------------
// Tiny test harness (matches the style in test_atlas.cpp)
// ---------------------------------------------------------------------------
static int g_checks = 0, g_fails = 0;

#define CHECK(cond, msg) do { \
    ++g_checks; \
    if (!(cond)) { \
        ++g_fails; \
        std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__); \
    } \
} while (0)

// Shorthand: does the drain result vector contain this coord?
static bool contains(const std::vector<Vec3i>& v, Vec3i c) {
    for (auto& x : v) if (x == c) return true;
    return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Test 1: Marking the same coord twice leaves only one entry pending.
static void test_dedup() {
    MeshBudget b;
    Vec3i c = {1, 0, 0};
    b.mark_dirty(c, 1, 100);
    b.mark_dirty(c, 1, 100);
    CHECK(b.pending_count() == 1, "dedup: marking same coord twice -> pending_count==1");
    CHECK(b.is_dirty(c),          "dedup: coord is still dirty after second mark");
}

// Test 2: Re-marking with a MORE urgent (smaller) tier updates the tier.
//         Re-marking with a LESS urgent (larger) tier does NOT downgrade.
static void test_tier_merge() {
    // Sub-test A: urgent mark wins over stale mark (smaller tier kept).
    {
        MeshBudget b;
        // Mark at tier 3 (cold) first.
        Vec3i hot = {0, 0, 0};
        Vec3i cold = {100, 0, 0};
        b.mark_dirty(hot,  3, 50);   // start cold
        b.mark_dirty(hot,  0, 50);   // remark as hot — tier should become 0
        b.mark_dirty(cold, 3, 50);   // another chunk stays at tier 3

        // drain with huge budget so everything comes out
        auto result = b.drain({0,0,0}, 999999);
        // hot chunk must drain BEFORE cold chunk (tier 0 < tier 3)
        CHECK(result.size() == 2, "tier-merge: both chunks drain");
        CHECK(result[0] == hot,   "tier-merge: hot chunk (tier 0) drains first after upgrade");
    }
    // Sub-test B: a downgrade attempt (less urgent re-mark) is ignored.
    {
        MeshBudget b;
        Vec3i c = {0, 0, 0};
        b.mark_dirty(c, 0, 50);   // mark as very hot (tier 0)
        b.mark_dirty(c, 5, 50);   // try to downgrade to tier 5 — must be rejected
        // Place another chunk at tier 1 to give the sort something to compare against.
        b.mark_dirty({1,0,0}, 1, 50);

        auto result = b.drain({0,0,0}, 999999);
        CHECK(result.size() == 2, "tier-no-downgrade: both chunks drain");
        // If the downgrade was wrongly accepted, {0,0,0} would be at tier 5
        // and {1,0,0} at tier 1 would come first. With correct behaviour,
        // {0,0,0} is still tier 0 and must drain first.
        CHECK(result[0] == c, "tier-no-downgrade: original tier 0 still wins");
    }
}

// Test 3: Lower tier drains before higher tier, regardless of distance.
static void test_priority_over_distance() {
    MeshBudget b;
    Vec3i camera = {0, 0, 0};

    // high_tier is RIGHT next to the camera (distance 1) but has tier 3.
    // low_tier is FAR from the camera (distance 1000) but has tier 0.
    Vec3i high_tier_near = {1, 0, 0};
    Vec3i low_tier_far   = {1000, 0, 0};
    b.mark_dirty(high_tier_near, 3, 50);
    b.mark_dirty(low_tier_far,   0, 50);

    auto result = b.drain(camera, 999999);
    CHECK(result.size() == 2,              "priority>distance: both chunks drain");
    CHECK(result[0] == low_tier_far,       "priority>distance: tier 0 (far) drains before tier 3 (near)");
    CHECK(result[1] == high_tier_near,     "priority>distance: tier 3 (near) drains second");
}

// Test 4: Within the same tier, nearer chunk drains first.
static void test_distance_tiebreak() {
    MeshBudget b;
    Vec3i camera = {0, 0, 0};

    Vec3i near  = {2, 0, 0};   // dist² = 4
    Vec3i far   = {10, 0, 0};  // dist² = 100
    Vec3i vfar  = {50, 0, 0};  // dist² = 2500
    b.mark_dirty(vfar,  1, 50);
    b.mark_dirty(near,  1, 50);
    b.mark_dirty(far,   1, 50);

    auto result = b.drain(camera, 999999);
    CHECK(result.size() == 3,    "distance-tiebreak: all three drain");
    CHECK(result[0] == near,     "distance-tiebreak: nearest drains first");
    CHECK(result[1] == far,      "distance-tiebreak: middle distance second");
    CHECK(result[2] == vfar,     "distance-tiebreak: farthest drains last");
}

// Test 5: Quad budget — chunks each costing 100 quads against a 250-quad
//         budget. Expect exactly 2 per drain; the remainder queues for next.
static void test_quad_budget() {
    MeshBudget b;
    Vec3i camera = {0, 0, 0};

    // Five chunks, all tier 1, 100 quads each.  Distance increases so they
    // have a predictable drain order: c1 nearest, c5 farthest.
    Vec3i c1 = {1, 0, 0};
    Vec3i c2 = {2, 0, 0};
    Vec3i c3 = {3, 0, 0};
    Vec3i c4 = {4, 0, 0};
    Vec3i c5 = {5, 0, 0};
    b.mark_dirty(c1, 1, 100);
    b.mark_dirty(c2, 1, 100);
    b.mark_dirty(c3, 1, 100);
    b.mark_dirty(c4, 1, 100);
    b.mark_dirty(c5, 1, 100);

    // Budget = 250. c1 (100) fits; c2 (100+100=200) fits; c3 (300) would
    // exceed — stop. So we should get exactly [c1, c2].
    auto first_drain = b.drain(camera, 250);
    CHECK(first_drain.size() == 2,          "budget: first drain returns exactly 2");
    CHECK(first_drain[0] == c1,             "budget: c1 (nearest) drains first");
    CHECK(first_drain[1] == c2,             "budget: c2 drains second");
    CHECK(b.pending_count() == 3,           "budget: 3 chunks remain after first drain");

    // Second drain at same budget: c3, c4 fit (200 ≤ 250); c5 would take us
    // to 300 → stop. Expect [c3, c4].
    auto second_drain = b.drain(camera, 250);
    CHECK(second_drain.size() == 2,         "budget: second drain returns 2 more");
    CHECK(second_drain[0] == c3,            "budget: c3 drains in second frame");
    CHECK(second_drain[1] == c4,            "budget: c4 drains in second frame");
    CHECK(b.pending_count() == 1,           "budget: 1 chunk remains after second drain");

    // Third drain: only c5 left, it fits (100 ≤ 250).
    auto third_drain = b.drain(camera, 250);
    CHECK(third_drain.size() == 1,          "budget: third drain returns last chunk");
    CHECK(third_drain[0] == c5,             "budget: c5 drains last");
    CHECK(b.pending_count() == 0,           "budget: nothing left after third drain");
}

// Test 6: At-least-one anti-deadlock guarantee.
//         A chunk with est_quads FAR above budget must still drain.
static void test_at_least_one() {
    MeshBudget b;
    Vec3i c = {0, 0, 0};
    b.mark_dirty(c, 0, 1000000);  // enormous cost

    // Budget is tiny (10 quads). Without the anti-deadlock rule this chunk
    // would never drain and the queue would grow forever.
    auto result = b.drain({0,0,0}, 10);
    CHECK(result.size() == 1,    "at-least-one: huge chunk still drains (no deadlock)");
    CHECK(result[0] == c,        "at-least-one: correct coord returned");
    CHECK(b.pending_count() == 0,"at-least-one: queue empty after draining the only chunk");
}

// Test 7: is_dirty and pending_count basics.
static void test_basic_state() {
    MeshBudget b;
    Vec3i a = {0, 0, 0};
    Vec3i absent = {99, 99, 99};

    CHECK(!b.is_dirty(a),        "basic: not dirty before mark");
    CHECK(b.pending_count() == 0,"basic: count 0 before any marks");

    b.mark_dirty(a, 0, 50);
    CHECK(b.is_dirty(a),         "basic: dirty after mark");
    CHECK(!b.is_dirty(absent),   "basic: unmarked coord not dirty");
    CHECK(b.pending_count() == 1,"basic: count 1 after one mark");

    b.drain({0,0,0}, 999999);
    CHECK(!b.is_dirty(a),        "basic: not dirty after drain");
    CHECK(b.pending_count() == 0,"basic: count 0 after drain");
}

// Test 8: clear() empties the queue entirely.
static void test_clear() {
    MeshBudget b;
    b.mark_dirty({0,0,0}, 0, 50);
    b.mark_dirty({1,0,0}, 0, 50);
    b.mark_dirty({2,0,0}, 0, 50);
    CHECK(b.pending_count() == 3, "clear: 3 chunks before clear");
    b.clear();
    CHECK(b.pending_count() == 0, "clear: 0 chunks after clear");
    CHECK(!b.is_dirty({0,0,0}),   "clear: is_dirty false after clear");
    CHECK(!b.is_dirty({1,0,0}),   "clear: second coord also gone");
}

// Test 9: Determinism — two MeshBudget instances with identical marks and
//         the same camera produce identical drain results.
static void test_determinism() {
    auto setup = [](MeshBudget& b) {
        // Scatter several chunks with varying tiers and positions so the sort
        // has real work to do. Order of insertion is intentionally mixed to
        // stress the hash-map → sort pipeline.
        b.mark_dirty({  5,  0,  0}, 2, 80);
        b.mark_dirty({  1,  0,  0}, 1, 40);
        b.mark_dirty({  3,  0,  0}, 2, 60);
        b.mark_dirty({  0,  0,  2}, 1, 40);
        b.mark_dirty({  7,  7,  7}, 0, 20);
        b.mark_dirty({ -1,  0,  0}, 2, 30);
        b.mark_dirty({  0, -3,  0}, 1, 55);
    };

    MeshBudget b1, b2;
    setup(b1);
    setup(b2);

    Vec3i camera = {2, 1, 0};
    auto r1 = b1.drain(camera, 999999);
    auto r2 = b2.drain(camera, 999999);

    CHECK(r1.size() == r2.size(), "determinism: both instances drain same count");
    bool same_order = true;
    for (size_t i = 0; i < r1.size() && i < r2.size(); ++i) {
        if (r1[i] != r2[i]) { same_order = false; break; }
    }
    CHECK(same_order, "determinism: drain order identical across instances");
}

// Test 10: Drain on an empty budget returns an empty vector (no crash).
static void test_drain_empty() {
    MeshBudget b;
    auto result = b.drain({0,0,0}, 1000);
    CHECK(result.empty(), "drain-empty: empty queue returns empty vector");
}

// Test 11: Budget of 0 still returns the first (mandatory) chunk.
static void test_zero_budget() {
    MeshBudget b;
    b.mark_dirty({0,0,0}, 0, 50);
    b.mark_dirty({1,0,0}, 0, 50);
    // Budget = 0 means even the first chunk "doesn't fit", but the
    // at-least-one rule forces us to return it anyway.
    auto result = b.drain({0,0,0}, 0);
    CHECK(result.size() == 1,      "zero-budget: at-least-one still fires");
    CHECK(b.pending_count() == 1,  "zero-budget: second chunk remains pending");
}

// Test 12: Negative-coordinate chunks pack and retrieve correctly.
//          (Validates the 21-bit bias in pack_key.)
static void test_negative_coords() {
    MeshBudget b;
    Vec3i neg = {-5, -3, -1};
    Vec3i pos = { 5,  3,  1};
    b.mark_dirty(neg, 0, 100);
    b.mark_dirty(pos, 0, 100);
    CHECK(b.is_dirty(neg),          "negative-coords: neg coord is dirty");
    CHECK(b.is_dirty(pos),          "negative-coords: pos coord is dirty");
    CHECK(b.pending_count() == 2,   "negative-coords: two distinct entries");

    // Make sure they're not aliased to each other.
    auto result = b.drain({0,0,0}, 999999);
    CHECK(result.size() == 2,       "negative-coords: both drain (no key collision)");
    CHECK(contains(result, neg),    "negative-coords: neg coord present in result");
    CHECK(contains(result, pos),    "negative-coords: pos coord present in result");
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main() {
    test_dedup();
    test_tier_merge();
    test_priority_over_distance();
    test_distance_tiebreak();
    test_quad_budget();
    test_at_least_one();
    test_basic_state();
    test_clear();
    test_determinism();
    test_drain_empty();
    test_zero_budget();
    test_negative_coords();

    std::printf("[meshbudget] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
