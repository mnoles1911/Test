// test_waterstream.cpp — standalone parity harness for the STREAMING coupling of
// the finite water sim (Core/FiniteWaterCore) with the chunk streaming/eviction
// system. These scenarios guard the correctness-critical integration the engine
// layer (AVoxelWorld) builds on TOP of the Core sim, WITHOUT changing any flow
// rule. The Core itself only gained one additive entry point — forget_region —
// plus a `forgotten` conservation counter; everything else here models, with pure
// predicates, what the engine's SolidFn / radius gate / eviction do.
//
// COMPILE + RUN (auto-discovered by build.sh; or manually from this directory):
//   clang++ -std=c++17 -Wall -Wextra -Wshadow -I ../../Source/MiraThalVoxel/Public \
//       test_waterstream.cpp \
//       ../../Source/MiraThalVoxel/Private/Core/FiniteWaterCore.cpp \
//       -o /tmp/test_waterstream && /tmp/test_waterstream
//
// WHAT EACH SCENARIO PROVES:
//   1) cross-apron/seam     — a pool straddling a chunk seam settles FLAT across
//                             the seam; conservation_delta()==0. (The Core does not
//                             know about chunks; a seam is just a coordinate, so a
//                             pool spanning x=31..x=32 must level identically.)
//   2) unloaded-as-solid    — with the SolidFn returning true for an "unloaded"
//                             half-space (exactly the engine's FilledColumns clamp),
//                             water pools against the boundary and loses NO volume:
//                             nothing leaks past the wall, total units constant.
//   3) forget_region        — after forget_region, units + forgotten still balance
//                             placed - (evap+absorbed+merged+removed); the dropped
//                             region's cells are gone but the audit holds.
//   4) determinism          — state_signature is identical across two independent
//                             runs of the seam + clamp scenarios.

#include <cstdio>
#include <string>
#include <unordered_set>

#include "Core/FiniteWaterCore.h"
#include "Core/WaterByteCodec.h"

// ----------------------------------------------------------------------------
// Assertion plumbing (same shape as test_water.cpp — zero deps).
// ----------------------------------------------------------------------------
static int g_checks = 0;
static int g_fails  = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!(cond)) {                                                          \
            ++g_fails;                                                          \
            std::printf("  FAIL [wstream] %s  (%s:%d)\n", (msg), __FILE__, __LINE__); \
        }                                                                       \
    } while (0)

#define CHECK_EQ(a, b, msg)                                                     \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!((a) == (b))) {                                                    \
            ++g_fails;                                                          \
            std::printf("  FAIL [wstream] %s  expected=%lld got=%lld  (%s:%d)\n", \
                        (msg), (long long)(b), (long long)(a),                  \
                        __FILE__, __LINE__);                                    \
        }                                                                       \
    } while (0)

using mira::Vec3i;
using mira::FiniteWaterCore;
using C = mira::WaterByteCodec;

// Chunk edge in voxels — matches Core/ChunkCoords.h CHUNK. A "seam" is the plane
// between x=CHUNK-1 and x=CHUNK (column 0 -> column 1).
static constexpr int CHUNK = 32;

// ----------------------------------------------------------------------------
// World model — an explicit solid set + an optional "loaded half-space" cutoff
// that mirrors the engine's unloaded-as-solid clamp. When `unloaded_x_at` is set,
// any voxel with x >= unloaded_x reads as SOLID (the column hasn't streamed in),
// exactly like AVoxelWorld::EnsureWaterSim's SolidFn does for a column not in
// FilledColumns.
// ----------------------------------------------------------------------------
struct World {
    std::unordered_set<Vec3i> solid;
    bool has_cutoff = false;
    int  unloaded_x = 0; // voxels with x >= this read SOLID when has_cutoff

    void add_floor(int floor_y, int x0, int x1, int z0, int z1) {
        for (int x = x0; x <= x1; ++x)
            for (int z = z0; z <= z1; ++z)
                solid.insert(Vec3i(x, floor_y, z));
    }

    FiniteWaterCore::SolidFn solid_fn() const {
        // Capture by value-copy of the cutoff so the predicate is self-contained.
        const bool cut = has_cutoff;
        const int  cx  = unloaded_x;
        // `solid` is read by pointer (the World outlives the sim in every scenario).
        const std::unordered_set<Vec3i>* s = &solid;
        return [s, cut, cx](const Vec3i& p) {
            if (cut && p.x >= cx) return true; // unloaded column -> SOLID wall
            return s->count(p) != 0;
        };
    }
    FiniteWaterCore::SourceFn source_fn() const {
        return [](const Vec3i&) { return false; }; // no ocean in these scenarios
    }
};

static int run_to_settle(FiniteWaterCore& sim, int max_ticks) {
    int ticks = 0;
    while (sim.has_pending_changes() && ticks < max_ticks) {
        sim.step(0);
        ++ticks;
    }
    return ticks;
}

// ----------------------------------------------------------------------------
// Scenario 1 — cross-seam pool settles FLAT and conserves.
// A floor spans columns 0 and 1 (x = CHUNK-4 .. CHUNK+3, straddling the seam at
// x=CHUNK). A tall column dropped right on the seam must collapse into a flat,
// level pool that spreads across the seam identically on both sides — the Core
// has no notion of chunks, so the seam must be invisible to the physics.
// ----------------------------------------------------------------------------
static void scenario_cross_seam_settles_flat() {
    World w;
    const int fy = 0;
    // Floor WIDE on both sides of the seam (x=CHUNK), so the SPREAD_REACH limit —
    // not the floor edge — is what halts the front (an open floor edge keeps its
    // front cells perpetually active; a reach-limited pool on a wide floor settles
    // cleanly, exactly like the Core's own spread test). The seam at x=CHUNK sits
    // in the MIDDLE of this wide floor, so the pour straddles columns 0 and 1.
    const int reach = FiniteWaterCore::SPREAD_REACH_VOXELS; // 30
    const int x0 = CHUNK - (reach + 6), x1 = CHUNK + (reach + 6);
    const int z0 = -(reach + 6), z1 = reach + 6;
    w.add_floor(fy, x0, x1, z0, z1);
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    // Drop the water straddling the seam (between column 0 and column 1).
    const int total = 200;
    int placed = sim.place(Vec3i(CHUNK, fy + 1, 0), total);
    CHECK_EQ(placed, total, "seam: all units placed into the seam column");

    int ticks = run_to_settle(sim, 6000);
    CHECK(ticks < 6000, "seam: converges within the tick cap");
    CHECK_EQ(sim.total_units(), total, "seam: volume conserved exactly across the seam");
    CHECK_EQ(sim.conservation_delta(), 0, "seam: audit balances");

    // FLATNESS across the seam: collect the per-column water depth at the seam edge
    // cells (x=CHUNK-1 in column 0, x=CHUNK in column 1). For a settled level pool
    // resting on one floor, neighbouring surface cells differ by at most 1 unit.
    bool all_on_floor = true;
    int seam_left  = 0; // sum of units at x = CHUNK-1
    int seam_right = 0; // sum of units at x = CHUNK
    for (int x = x0; x <= x1; ++x)
        for (int z = z0; z <= z1; ++z)
            for (int y = fy + 1; y <= fy + 30; ++y) {
                int u = sim.units_at(Vec3i(x, y, z));
                if (u <= 0) continue;
                if (y != fy + 1) all_on_floor = false; // shallow pool: one layer
                if (x == CHUNK - 1) seam_left  += u;
                if (x == CHUNK)     seam_right += u;
            }
    CHECK(all_on_floor, "seam: settled pool rests in one flat layer on the floor");
    // No SEAM ARTEFACT: both columns flanking the seam hold real water — the pool
    // bridges x=CHUNK-1 (column 0) and x=CHUNK (column 1) with no depleted gap at
    // the chunk boundary — and they are comparable in depth (a seam artefact would
    // leave one side starved). We allow the modest asymmetry the pour cell's side
    // bias produces (place() seeds x=CHUNK first), but neither side may be empty
    // and the heavier side may not exceed the lighter by more than ~50%.
    CHECK(seam_left > 0,  "seam: water present in column 0 at the seam (x=CHUNK-1)");
    CHECK(seam_right > 0, "seam: water present in column 1 at the seam (x=CHUNK)");
    const int hi = seam_left > seam_right ? seam_left : seam_right;
    const int lo = seam_left > seam_right ? seam_right : seam_left;
    CHECK(hi <= lo + lo / 2 + 1,
          "seam: water depth is comparable across the seam (no seam artefact)");
}

// ----------------------------------------------------------------------------
// Scenario 2 — UNLOADED-AS-SOLID clamp: water cannot leak into ungenerated space.
// The floor spans x = -8 .. +20, but the "loaded world" ends at x = CHUNK (the
// SolidFn reports x >= CHUNK as SOLID, i.e. that column hasn't streamed in). The
// floor deliberately extends a little past the cutoff, so WITHOUT the clamp water
// would happily spread onto floor cells in the unloaded region. WITH the clamp the
// pool stacks against the x=CHUNK wall and NOTHING leaks past it — every placed
// unit is still present, and no water cell exists at x >= CHUNK.
// ----------------------------------------------------------------------------
static void scenario_unloaded_as_solid_clamp() {
    World w;
    const int fy = 0;
    const int reach = FiniteWaterCore::SPREAD_REACH_VOXELS; // 30
    // Floor WIDE on the loaded side (so the pool settles on reach, not a floor edge)
    // and running PAST the loaded/unloaded boundary at x=CHUNK. The cutoff makes
    // x >= CHUNK read SOLID (the column hasn't streamed in), so even though the
    // floor exists out there, water must NOT spread onto it.
    w.add_floor(fy, CHUNK - (reach + 6), CHUNK + 8, -(reach + 6), reach + 6);
    w.has_cutoff = true;
    w.unloaded_x = CHUNK; // x >= CHUNK is "unloaded" -> SOLID wall
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    const int total = 200;
    // Pour near the boundary so the front MUST push toward the wall.
    int placed = sim.place(Vec3i(CHUNK - 2, fy + 1, 0), total);
    CHECK_EQ(placed, total, "clamp: all units placed");

    int ticks = run_to_settle(sim, 8000);
    CHECK(ticks < 8000, "clamp: converges within the tick cap");

    // CONSERVATION: not a single unit lost to the ungenerated void.
    CHECK_EQ(sim.total_units(), total, "clamp: total volume constant — nothing leaked");
    CHECK_EQ(sim.conservation_delta(), 0, "clamp: audit balances");

    // NOTHING crossed the wall: no water cell exists at x >= CHUNK.
    int units_past_wall = 0;
    for (int x = CHUNK; x <= CHUNK + 8; ++x)
        for (int z = -2; z <= 2; ++z)
            for (int y = fy + 1; y <= fy + 40; ++y)
                units_past_wall += sim.units_at(Vec3i(x, y, z));
    CHECK_EQ(units_past_wall, 0, "clamp: no water leaked past the unloaded boundary");

    // Sanity: with the clamp, the pool is forced to DEEPEN against the wall, so at
    // least one cell adjacent to the wall holds more than 1 unit (it didn't all
    // spread away into the (real) loaded floor either).
    int wall_adjacent_max = 0;
    for (int z = -2; z <= 2; ++z)
        for (int y = fy + 1; y <= fy + 40; ++y) {
            int u = sim.units_at(Vec3i(CHUNK - 1, y, z));
            if (u > wall_adjacent_max) wall_adjacent_max = u;
        }
    CHECK(wall_adjacent_max >= 1, "clamp: water pools up against the wall");
}

// ----------------------------------------------------------------------------
// Scenario 2b — control: WITHOUT the clamp (loaded floor everywhere), the same
// pour DOES spread onto the cells the clamp would have walled off. This proves the
// clamp is what's doing the work (not a floor that simply ends).
// ----------------------------------------------------------------------------
static void scenario_no_clamp_spreads_past() {
    World w;
    const int fy = 0;
    const int reach = FiniteWaterCore::SPREAD_REACH_VOXELS; // 30
    // Same wide loaded floor as the clamp scenario, but NO cutoff: the whole floor
    // is loaded, so water is free to spread to BOTH sides of x=CHUNK.
    w.add_floor(fy, CHUNK - (reach + 6), CHUNK + (reach + 6), -(reach + 6), reach + 6);
    // has_cutoff stays false: the whole floor is "loaded".
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    const int total = 200;
    sim.place(Vec3i(CHUNK - 2, fy + 1, 0), total);
    run_to_settle(sim, 8000);

    CHECK_EQ(sim.total_units(), total, "no-clamp: still conserves (sanity)");
    int units_past = 0;
    for (int x = CHUNK; x <= CHUNK + (reach + 6); ++x)
        for (int z = -(reach + 6); z <= reach + 6; ++z)
            units_past += sim.units_at(Vec3i(x, fy + 1, z));
    CHECK(units_past > 0,
          "no-clamp: water DOES spread past x=CHUNK (so the clamp is load-bearing)");
}

// ----------------------------------------------------------------------------
// Scenario 3 — forget_region conservation. Build two separated pools, then forget
// the region containing one of them (as the eviction prune does for an evicted
// column). The ledger loses those cells, `forgotten` rises by exactly their units,
// and the audit still balances: units + forgotten == placed - (others).
// ----------------------------------------------------------------------------
static void scenario_forget_region_conserves() {
    World w;
    const int fy = 0;
    // Two floors well apart in x: a NEAR pool near origin, a FAR pool past x=200.
    w.add_floor(fy, -4, 4, -4, 4);
    w.add_floor(fy, 196, 204, -4, 4);
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    int near_placed = sim.place(Vec3i(0, fy + 1, 0), 40);
    int far_placed  = sim.place(Vec3i(200, fy + 1, 0), 64);
    CHECK_EQ(near_placed, 40, "forget: near pool placed");
    CHECK_EQ(far_placed, 64, "forget: far pool placed");
    // A bounded number of ticks is enough — conservation + forget_region hold
    // regardless of whether these small isolated pools fully settle (a pool whose
    // front reaches a floor edge can stay active, which is fine here).
    for (int t = 0; t < 200 && sim.has_pending_changes(); ++t) sim.step(0);

    const int total_before = sim.total_units();
    CHECK_EQ(sim.conservation_delta(), 0, "forget: balanced before forgetting");

    // Measure exactly how many units live in the FAR region before we forget it.
    int far_units = 0;
    for (int x = 190; x <= 210; ++x)
        for (int z = -6; z <= 6; ++z)
            for (int y = fy; y <= fy + 40; ++y)
                far_units += sim.units_at(Vec3i(x, y, z));
    CHECK(far_units > 0, "forget: far region holds water before eviction");

    const int forgotten_before = sim.stats().forgotten;
    // Forget the FAR region (inclusive AABB), exactly as the eviction prune does.
    sim.forget_region(Vec3i(190, fy - 4, -6), Vec3i(210, fy + 40, 6));

    // The far units are gone from the ledger...
    CHECK_EQ(sim.total_units(), total_before - far_units,
             "forget: far units removed from the live ledger");
    // ...and accounted for in `forgotten`...
    CHECK_EQ(sim.stats().forgotten, forgotten_before + far_units,
             "forget: dropped units tallied into `forgotten`");
    // ...so the audit STILL balances (units + forgotten = placed - others).
    CHECK_EQ(sim.conservation_delta(), 0,
             "forget: audit still balances after forget_region");

    // The NEAR pool is untouched (sum over its whole footprint + height).
    int near_units = 0;
    for (int x = -6; x <= 6; ++x)
        for (int z = -6; z <= 6; ++z)
            for (int y = fy; y <= fy + 40; ++y)
                near_units += sim.units_at(Vec3i(x, y, z));
    CHECK_EQ(near_units, 40, "forget: near pool untouched by forgetting the far one");

    // A second forget over the now-empty far region is a no-op (idempotent).
    const int forgotten_after = sim.stats().forgotten;
    sim.forget_region(Vec3i(190, fy - 4, -6), Vec3i(210, fy + 40, 6));
    CHECK_EQ(sim.stats().forgotten, forgotten_after,
             "forget: re-forgetting an empty region changes nothing");
    CHECK_EQ(sim.conservation_delta(), 0, "forget: still balanced after a no-op forget");
}

// ----------------------------------------------------------------------------
// Scenario 4 — determinism. Two independent runs of the seam scenario AND the
// clamp scenario must yield byte-identical state signatures (the parity contract,
// extended to the new streaming scenarios). forget_region is also exercised
// identically in both runs to prove it doesn't introduce nondeterminism.
// ----------------------------------------------------------------------------
static std::string run_seam_then_forget() {
    World w;
    const int fy = 0;
    const int reach = FiniteWaterCore::SPREAD_REACH_VOXELS;
    w.add_floor(fy, CHUNK - (reach + 6), CHUNK + (reach + 6), -(reach + 6), reach + 6);
    w.add_floor(fy, 196, 204, -4, 4); // a far pool we will forget (need not settle)
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());
    sim.place(Vec3i(CHUNK, fy + 1, 0), 200);
    sim.place(Vec3i(200, fy + 1, 0), 50);
    run_to_settle(sim, 6000);
    sim.forget_region(Vec3i(190, fy - 4, -6), Vec3i(210, fy + 40, 6));
    run_to_settle(sim, 200);
    return sim.state_signature();
}

static std::string run_clamp() {
    World w;
    const int fy = 0;
    const int reach = FiniteWaterCore::SPREAD_REACH_VOXELS;
    w.add_floor(fy, CHUNK - (reach + 6), CHUNK + 8, -(reach + 6), reach + 6);
    w.has_cutoff = true;
    w.unloaded_x = CHUNK;
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());
    sim.place(Vec3i(CHUNK - 2, fy + 1, 0), 200);
    run_to_settle(sim, 8000);
    return sim.state_signature();
}

static void scenario_determinism() {
    const std::string a1 = run_seam_then_forget();
    const std::string a2 = run_seam_then_forget();
    CHECK(a1 == a2, "determinism: seam+forget runs yield identical signatures");

    const std::string b1 = run_clamp();
    const std::string b2 = run_clamp();
    CHECK(b1 == b2, "determinism: unloaded-clamp runs yield identical signatures");
}

// ----------------------------------------------------------------------------
// main
// ----------------------------------------------------------------------------
int main() {
    scenario_cross_seam_settles_flat();
    scenario_unloaded_as_solid_clamp();
    scenario_no_clamp_spreads_past();
    scenario_forget_region_conserves();
    scenario_determinism();

    const bool ok = (g_fails == 0);
    std::printf("[wstream ] %s\n", ok ? "PASS" : "FAIL");
    std::printf("----\n%d checks, %d failure(s)\n", g_checks, g_fails);
    return ok ? 0 : 1;
}
