// test_entities.cpp — standalone parity harness for the ported entity-streaming
// Core: EntityRegistry (chunk + id index) and EntityStreaming (4-tier AI sleep,
// load ring, hysteresis).
//
// COMPILE + RUN (either works):
//   cd /home/user/Test/ue5/MiraThal/tests/standalone && ./build.sh entities
// or directly:
//   clang++ -std=c++17 -O2 -Wall -Wextra -Wshadow \
//     -I /home/user/Test/ue5/MiraThal/Source/MiraThalCore/Public \
//     -I /home/user/Test/ue5/MiraThal/Source/MiraThalVoxel/Public \
//     test_entities.cpp -o test_entities.run && ./test_entities.run
//
// This is one self-contained program (its own main). It mirrors the print style
// of tests/standalone/test_main.cpp: each part runs checks, then main prints a
// single [entities] PASS / FAIL line and returns 0 only if every check passed.

#include <cstdio>
#include <string>
#include <vector>
#include <algorithm>

#include "Core/EntityRegistry.h"
#include "Core/EntityStreaming.h"

// ---------------------------------------------------------------------------
// Minimal assertion plumbing (matches test_main.cpp's CHECK macro / counters).
// ---------------------------------------------------------------------------
static int g_checks = 0;
static int g_fails  = 0;
static std::string g_current;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!(cond)) {                                                          \
            ++g_fails;                                                          \
            std::printf("  FAIL [%s] %s  (%s:%d)\n",                            \
                        g_current.c_str(), (msg), __FILE__, __LINE__);          \
        }                                                                       \
    } while (0)

#define CHECK_EQ(a, b, msg)                                                     \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!((a) == (b))) {                                                    \
            ++g_fails;                                                          \
            std::printf("  FAIL [%s] %s  expected=%lld got=%lld  (%s:%d)\n",    \
                        g_current.c_str(), (msg),                               \
                        (long long)(b), (long long)(a), __FILE__, __LINE__);    \
        }                                                                       \
    } while (0)

using mira::AITier;
using mira::EntityRecord;
using mira::EntityRegistry;
using mira::EntityStreamConfig;
using mira::Vec3;
using mira::Vec3i;

// Helper: is `id` listed among the records the registry files under `chunk`?
static bool chunk_lists(const EntityRegistry& reg, const Vec3i& chunk,
                        const std::string& id) {
    const std::vector<EntityRecord> recs = reg.records_in_chunk(chunk);
    return std::any_of(recs.begin(), recs.end(),
                       [&](const EntityRecord& r) { return r.id == id; });
}

// Helper: make a record at a world position with a given id/type.
static EntityRecord makeRec(const std::string& id, float x, float y, float z,
                            const std::string& type = "goblin") {
    EntityRecord r;
    r.id = id;
    r.position = Vec3(x, y, z);
    r.type = type;
    return r;
}

// ---------------------------------------------------------------------------
// Part 1: EntityRegistry — chunk indexing, id lookup, re-index on move,
//         idempotent unregister.
// ---------------------------------------------------------------------------
static void part_registry() {
    g_current = "registry";
    EntityRegistry reg;

    // CHUNK_M = 16. A point at (5, 0, 5) floors into chunk (0,0,0); a point at
    // (20, 0, 5) floors into chunk (1,0,0); a point at (-1, 0, -1) floors to
    // (-1,0,-1) (negative floors toward -infinity, not toward zero).
    CHECK(EntityRegistry::chunk_key_for_position(Vec3(5, 0, 5))  == Vec3i(0, 0, 0),   "(5,5) -> chunk (0,0)");
    CHECK(EntityRegistry::chunk_key_for_position(Vec3(20, 0, 5)) == Vec3i(1, 0, 0),   "(20,5) -> chunk (1,0)");
    CHECK(EntityRegistry::chunk_key_for_position(Vec3(-1, 0, -1)) == Vec3i(-1, 0, -1), "(-1,-1) -> chunk (-1,-1)");

    // Register a record at (5,5) -> chunk (0,0). It must be findable by id AND
    // listed in chunk (0,0).
    CHECK(reg.register_record(makeRec("g1", 5, 0, 5)), "register g1 takes");
    CHECK_EQ((long long)reg.record_count(), 1ll, "one record after register");
    const EntityRecord* got = reg.get_record("g1");
    CHECK(got != nullptr, "g1 findable by id");
    CHECK(chunk_lists(reg, Vec3i(0, 0, 0), "g1"), "g1 listed in chunk (0,0)");
    CHECK(!chunk_lists(reg, Vec3i(1, 0, 0), "g1"), "g1 NOT in chunk (1,0)");

    // Empty-id register is ignored.
    CHECK(!reg.register_record(makeRec("", 5, 0, 5)), "empty-id register ignored");
    CHECK_EQ((long long)reg.record_count(), 1ll, "empty register did not add");

    // Move g1 across a chunk boundary: (5,5) -> (20,5) is chunk (0,0) -> (1,0).
    // After update the OLD chunk must no longer list it; the NEW one must.
    EntityRecord moved = makeRec("g1", 20, 0, 5);
    reg.update(moved);
    CHECK(!chunk_lists(reg, Vec3i(0, 0, 0), "g1"), "after move: g1 gone from old chunk (0,0)");
    CHECK(chunk_lists(reg, Vec3i(1, 0, 0), "g1"), "after move: g1 now in new chunk (1,0)");
    CHECK_EQ((long long)reg.record_count(), 1ll, "move did not duplicate record");
    // The old chunk bucket should have been pruned (it is now empty).
    CHECK_EQ((long long)reg.chunk_count(), 1ll, "empty old-chunk bucket pruned");

    // A second record in a different chunk; chunk_count rises to 2.
    CHECK(reg.register_record(makeRec("g2", -1, 0, -1)), "register g2 in (-1,-1)");
    CHECK_EQ((long long)reg.chunk_count(), 2ll, "two non-empty chunks");
    CHECK(chunk_lists(reg, Vec3i(-1, 0, -1), "g2"), "g2 in chunk (-1,-1)");

    // unregister removes the record and prunes its (now empty) chunk bucket.
    reg.unregister("g1");
    CHECK(reg.get_record("g1") == nullptr, "g1 gone after unregister");
    CHECK(!chunk_lists(reg, Vec3i(1, 0, 0), "g1"), "g1 not in chunk after unregister");
    CHECK_EQ((long long)reg.record_count(), 1ll, "one record left after unregister");

    // unregister is IDEMPOTENT — calling it again (and on an unknown id) is a
    // no-op, not a crash or a count change.
    reg.unregister("g1");
    reg.unregister("never_existed");
    CHECK_EQ((long long)reg.record_count(), 1ll, "idempotent unregister leaves count");
    CHECK_EQ((long long)reg.chunk_count(), 1ll, "idempotent unregister leaves chunks");

    // update() on an unknown id falls through to a register (GDScript contract).
    reg.update(makeRec("g3", 100, 0, 100));
    CHECK(reg.get_record("g3") != nullptr, "update of unknown id registers it");
    CHECK_EQ((long long)reg.record_count(), 2ll, "g3 registered via update");
}

// ---------------------------------------------------------------------------
// Part 2: EntityStreaming — tier classification at the distance thresholds.
//
// Defaults: awake_radius_m = 30, sleep_radius_m = 80. Source uses <=, so a
// distance EXACTLY on a threshold reads the closer tier. We place the player at
// the origin and the entity straight out along +x so distance == x.
// ---------------------------------------------------------------------------
static void part_tiers() {
    g_current = "tiers";
    EntityStreamConfig cfg;  // stock designer defaults
    const Vec3 player(0, 0, 0);

    // ACTIVE band: d <= 30.
    CHECK(mira::classify_tier(player, Vec3(10, 0, 0), cfg) == AITier::ACTIVE, "10 m -> ACTIVE");
    CHECK(mira::classify_tier(player, Vec3(30, 0, 0), cfg) == AITier::ACTIVE, "30 m (boundary, <=) -> ACTIVE");

    // AWAKE band: 30 < d <= 80.
    CHECK(mira::classify_tier(player, Vec3(30.001f, 0, 0), cfg) == AITier::AWAKE, "just past 30 m -> AWAKE");
    CHECK(mira::classify_tier(player, Vec3(50, 0, 0), cfg) == AITier::AWAKE, "50 m -> AWAKE");
    CHECK(mira::classify_tier(player, Vec3(80, 0, 0), cfg) == AITier::AWAKE, "80 m (boundary, <=) -> AWAKE");

    // SLEEPING band: d > 80 but still inside the unload ring (6 chunks = 96 m
    // Chebyshev). 90 m along +x is chunk floor(90/16)=5, player chunk 0 ->
    // Chebyshev 5 <= 6, so it is loaded (SLEEPING), not OFFLOADED.
    CHECK(mira::classify_tier(player, Vec3(90, 0, 0), cfg) == AITier::SLEEPING, "90 m (in unload ring) -> SLEEPING");

    // OFFLOADED: past the unload ring. unload_radius_chunks = 6, so a chunk
    // distance of 7 offloads. 7 chunks * 16 m = 112 m -> chunk floor(112/16)=7.
    CHECK(mira::classify_tier(player, Vec3(112, 0, 0), cfg) == AITier::OFFLOADED, "112 m (chunk 7 > 6) -> OFFLOADED");

    // tier_for_distance (distance-only, never OFFLOADED) sanity.
    CHECK(mira::tier_for_distance(0.0f, cfg)   == AITier::ACTIVE,   "0 m -> ACTIVE");
    CHECK(mira::tier_for_distance(45.0f, cfg)  == AITier::AWAKE,    "45 m -> AWAKE");
    CHECK(mira::tier_for_distance(200.0f, cfg) == AITier::SLEEPING, "200 m -> SLEEPING (distance-only)");

    // Per-tier tick-rate table: the documented 60 / 10 / 1 / 0 cadence.
    CHECK(mira::tier_tick_hz(AITier::ACTIVE)    == 60.0f, "ACTIVE ticks at 60 Hz");
    CHECK(mira::tier_tick_hz(AITier::AWAKE)     == 10.0f, "AWAKE ticks at 10 Hz");
    CHECK(mira::tier_tick_hz(AITier::SLEEPING)  == 1.0f,  "SLEEPING ticks at 1 Hz");
    CHECK(mira::tier_tick_hz(AITier::OFFLOADED) == 0.0f,  "OFFLOADED has no tick");
}

// ---------------------------------------------------------------------------
// Part 3: EntityStreaming — the load ring contains the expected chunks.
// ---------------------------------------------------------------------------
static void part_load_ring() {
    g_current = "load_ring";
    EntityStreamConfig cfg;  // load_radius_chunks = 5
    const Vec3 player(8, 0, 8);  // inside chunk (0,0)

    const std::vector<Vec3i> ring = mira::chunks_in_load_ring(player, cfg);

    // A square ring of (2*5+1)^2 = 121 chunks centred on chunk (0,0).
    CHECK_EQ((long long)ring.size(), 121ll, "load ring is 11x11 = 121 chunks");

    // The center chunk is in the ring.
    auto in_ring = [&](const Vec3i& c) {
        return std::any_of(ring.begin(), ring.end(),
                           [&](const Vec3i& k) { return k == c; });
    };
    CHECK(in_ring(Vec3i(0, 0, 0)), "center chunk (0,0) in ring");
    // The four corners at radius 5 are present.
    CHECK(in_ring(Vec3i(5, 0, 5)),   "corner (+5,+5) in ring");
    CHECK(in_ring(Vec3i(-5, 0, -5)), "corner (-5,-5) in ring");
    CHECK(in_ring(Vec3i(5, 0, -5)),  "corner (+5,-5) in ring");
    CHECK(in_ring(Vec3i(-5, 0, 5)),  "corner (-5,+5) in ring");
    // One step past the radius is NOT in the ring.
    CHECK(!in_ring(Vec3i(6, 0, 0)), "chunk (+6,0) past radius NOT in ring");
    CHECK(!in_ring(Vec3i(0, 0, -6)), "chunk (0,-6) past radius NOT in ring");

    // should_be_loaded mirrors ring membership via Chebyshev distance.
    const Vec3i player_chunk = mira::world_to_chunk(player);
    CHECK(mira::should_be_loaded(player_chunk, Vec3i(5, 0, 0), cfg), "chunk at dist 5 loads");
    CHECK(!mira::should_be_loaded(player_chunk, Vec3i(6, 0, 0), cfg), "chunk at dist 6 does NOT load");
}

// ---------------------------------------------------------------------------
// Part 4: EntityStreaming — hysteresis. An entity in the band between the load
// ring (5) and the unload ring (6) must STAY loaded — it does not spawn fresh
// (outside load) but it must not be evicted either, so a player jittering on the
// boundary never thrashes spawn/despawn.
// ---------------------------------------------------------------------------
static void part_hysteresis() {
    g_current = "hysteresis";
    EntityStreamConfig cfg;  // load = 5, unload = 6
    const Vec3i player_chunk(0, 0, 0);

    // Inside the load ring (dist 4): loads, never evicts.
    CHECK(mira::should_be_loaded(player_chunk, Vec3i(4, 0, 0), cfg),  "dist 4 loads");
    CHECK(!mira::should_be_evicted(player_chunk, Vec3i(4, 0, 0), cfg), "dist 4 not evicted");

    // ON the load boundary (dist 5): loads, never evicts.
    CHECK(mira::should_be_loaded(player_chunk, Vec3i(5, 0, 0), cfg),  "dist 5 loads (<= load)");
    CHECK(!mira::should_be_evicted(player_chunk, Vec3i(5, 0, 0), cfg), "dist 5 not evicted");

    // THE HYSTERESIS BAND (dist 6): NOT freshly spawned (outside load ring) but
    // NOT evicted either (not yet past unload ring). A thing already live here
    // stays live — no thrash.
    CHECK(!mira::should_be_loaded(player_chunk, Vec3i(6, 0, 0), cfg),  "dist 6 NOT freshly loaded");
    CHECK(!mira::should_be_evicted(player_chunk, Vec3i(6, 0, 0), cfg), "dist 6 NOT evicted (sticky band)");

    // Past the unload ring (dist 7): finally evicted.
    CHECK(!mira::should_be_loaded(player_chunk, Vec3i(7, 0, 0), cfg), "dist 7 not loaded");
    CHECK(mira::should_be_evicted(player_chunk, Vec3i(7, 0, 0), cfg), "dist 7 evicted (> unload)");

    // The Chebyshev shape: a diagonal at (6,6) is distance 6, still sticky; at
    // (7,7) it is distance 7, evicted. (Confirms max(|dx|,|dz|), not euclidean.)
    CHECK(!mira::should_be_evicted(player_chunk, Vec3i(6, 0, 6), cfg), "diag (6,6) sticky");
    CHECK(mira::should_be_evicted(player_chunk, Vec3i(7, 0, 7), cfg),  "diag (7,7) evicted");
}

int main() {
    part_registry();
    part_tiers();
    part_load_ring();
    part_hysteresis();

    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    if (g_fails == 0) {
        std::printf("[entities] PASS\n");
        return 0;
    }
    std::printf("[entities] FAIL\n");
    return 1;
}
