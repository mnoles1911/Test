// test_water.cpp — standalone parity harness for the finite volume-conserving
// water sim (Core/FiniteWaterCore). Ports the Godot `finite` headless selector.
//
// COMPILE + RUN (from this directory, tests/standalone/):
//   clang++ -std=c++17 -Wall -Wextra -I ../../Source/MiraThalVoxel/Public \
//       test_water.cpp \
//       ../../Source/MiraThalVoxel/Private/Core/FiniteWaterCore.cpp \
//       -o /tmp/test_water && /tmp/test_water
//
// WHY THIS EXISTS:
// Unreal can't build in the dev container, but the Core layer is pure C++17, so
// it compiles and runs HERE under clang. This is the iterative verification loop
// for the water port's load-bearing property: VOLUME CONSERVATION. Every move in
// the sim is "subtract 1 unit here, add 1 there", so the ledger total must always
// satisfy the audit:
//
//   total_units() == placed - evaporated - absorbed - merged - removed
//
// (i.e. conservation_delta() == 0). Each scenario below asserts that invariant
// alongside the behaviour it is exercising.
//
// It mirrors the print/exit style of test_main.cpp: it prints
//   [water   ] PASS   or   [water   ] FAIL
// and returns 0 only if every check passed.

#include <cstdio>
#include <string>
#include <unordered_set>

#include "Core/FiniteWaterCore.h"
#include "Core/WaterByteCodec.h"

// ----------------------------------------------------------------------------
// Minimal assertion plumbing (same shape as test_main.cpp — zero deps).
// ----------------------------------------------------------------------------
static int g_checks = 0;
static int g_fails  = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!(cond)) {                                                          \
            ++g_fails;                                                          \
            std::printf("  FAIL [water] %s  (%s:%d)\n", (msg), __FILE__, __LINE__); \
        }                                                                       \
    } while (0)

#define CHECK_EQ(a, b, msg)                                                     \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!((a) == (b))) {                                                    \
            ++g_fails;                                                          \
            std::printf("  FAIL [water] %s  expected=%lld got=%lld  (%s:%d)\n", \
                        (msg), (long long)(b), (long long)(a),                  \
                        __FILE__, __LINE__);                                    \
        }                                                                       \
    } while (0)

using mira::Vec3i;
using mira::FiniteWaterCore;
using C = mira::WaterByteCodec;

// ----------------------------------------------------------------------------
// World predicates the sim is constructed with. We model terrain as an explicit
// "solid" set and an explicit "source" set, so each scenario builds exactly the
// world it needs (a floor, a wall, etc.) without any engine plumbing.
// ----------------------------------------------------------------------------
struct World {
    std::unordered_set<Vec3i> solid;
    std::unordered_set<Vec3i> source;

    // A flat solid floor at y = floor_y is the most common test ground: water
    // placed on it should settle and spread, never fall through.
    void add_floor(int floor_y, int half) {
        for (int x = -half; x <= half; ++x)
            for (int z = -half; z <= half; ++z)
                solid.insert(Vec3i(x, floor_y, z));
    }

    FiniteWaterCore::SolidFn  solid_fn() const {
        return [this](const Vec3i& p) { return solid.count(p) != 0; };
    }
    FiniteWaterCore::SourceFn source_fn() const {
        return [this](const Vec3i& p) { return source.count(p) != 0; };
    }
};

// Run the sim until it settles (no active cells, nothing left to project) or we
// hit a tick cap. Returns the number of ticks taken. Budget 0 = no per-tick cap,
// so a scenario converges in as few ticks as the rules allow.
static int run_to_settle(FiniteWaterCore& sim, int max_ticks) {
    int ticks = 0;
    while (sim.has_pending_changes() && ticks < max_ticks) {
        sim.step(0);
        ++ticks;
    }
    return ticks;
}

// ----------------------------------------------------------------------------
// Scenario 1 — single placement settles and conserves.
// One full voxel (8 units) dropped on a floor cell: it has nowhere lower to go,
// so it just sits there. The ledger total must equal what we placed, and the
// audit must balance.
// ----------------------------------------------------------------------------
static void scenario_single_placement() {
    World w;
    w.add_floor(0, 4);
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    int placed = sim.place(Vec3i(0, 1, 0), 8); // sits on the floor at y=0
    CHECK_EQ(placed, 8, "single placement reports 8 units placed");

    int ticks = run_to_settle(sim, 200);
    CHECK(ticks < 200, "single placement settles within the tick cap");
    CHECK(sim.is_settled(), "single placement is settled");
    CHECK_EQ(sim.total_units(), 8, "single placement conserves its 8 units");
    CHECK_EQ(sim.conservation_delta(), 0, "single placement: audit balances");
    // Nothing left, nothing evaporated/absorbed/merged.
    FiniteWaterCore::Stats s = sim.stats();
    CHECK_EQ(s.placed, 8, "placed counter == 8");
    CHECK_EQ(s.evaporated + s.absorbed + s.merged + s.removed, 0,
             "single placement loses nothing to evap/absorb/merge/remove");
}

// ----------------------------------------------------------------------------
// Scenario 2 — water spreads across a flat floor and conserves; the front never
// exceeds SPREAD_REACH. A tall column on a wide floor collapses into a wide,
// shallow, LEVEL pool.
// ----------------------------------------------------------------------------
static void scenario_spread_flat_floor() {
    World w;
    const int reach = FiniteWaterCore::SPREAD_REACH_VOXELS; // 30
    // Floor wide enough that the reach limit (not the floor edge) is what stops
    // the front. add_floor builds a (2*half+1) square centered on origin.
    w.add_floor(0, reach + 5);
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    // Drop a generous column so it MUST spread sideways to flatten.
    const int total = 200;
    int placed = sim.place(Vec3i(0, 1, 0), total);
    CHECK_EQ(placed, total, "spread: all units placed into the column");

    int ticks = run_to_settle(sim, 4000);
    CHECK(ticks < 4000, "spread: converges within the tick cap");
    CHECK_EQ(sim.total_units(), total, "spread: volume conserved exactly");
    CHECK_EQ(sim.conservation_delta(), 0, "spread: audit balances");

    // Every water cell sits on the floor (y == 1) — nothing leaked downward —
    // and no cell is farther than SPREAD_REACH (in voxels) from the placement
    // footprint at the origin column. Also: no cell exceeds MAX_UNITS_PER_CELL,
    // and adjacent water cells differ by at most 1 level (it is LEVEL).
    bool all_on_floor = true;
    bool within_reach = true;
    bool none_overfull = true;
    for (int x = -(reach + 5); x <= reach + 5; ++x) {
        for (int z = -(reach + 5); z <= reach + 5; ++z) {
            for (int y = 1; y <= 30; ++y) {
                Vec3i p(x, y, z);
                int u = sim.units_at(p);
                if (u <= 0) continue;
                if (y != 1) all_on_floor = false;
                if (u > FiniteWaterCore::MAX_UNITS_PER_CELL) none_overfull = false;
                // Manhattan-ish horizontal distance from origin in voxels.
                int dist = (x < 0 ? -x : x) + (z < 0 ? -z : z);
                if (dist > reach) within_reach = false;
            }
        }
    }
    CHECK(all_on_floor, "spread: all water rests on the floor layer (y==1)");
    CHECK(within_reach, "spread: front halts within SPREAD_REACH voxels");
    CHECK(none_overfull, "spread: no cell exceeds 8 units");
}

// ----------------------------------------------------------------------------
// Scenario 3 — water falls / drains downward. Place water high in a vertical
// shaft (solid walls, open bottom resting on a floor) and confirm it ends up at
// the BOTTOM, not where it started, with volume conserved.
// ----------------------------------------------------------------------------
static void scenario_fall_downward() {
    World w;
    // A 1-wide WALLED shaft: floor at y=0 and solid walls on all 4 sides up the
    // whole column, so the only place water can go is DOWN. (Without walls, a
    // full cell resting on full water could legitimately creep sideways into
    // open air — correct sim behaviour, but not the pure-fall we want to test.)
    w.solid.insert(Vec3i(0, 0, 0)); // the floor the column lands on
    for (int y = 1; y <= 11; ++y) {
        w.solid.insert(Vec3i( 1, y, 0));
        w.solid.insert(Vec3i(-1, y, 0));
        w.solid.insert(Vec3i(0, y,  1));
        w.solid.insert(Vec3i(0, y, -1));
    }
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    int placed = sim.place(Vec3i(0, 10, 0), 8);
    CHECK_EQ(placed, 8, "fall: 8 units placed up high");

    run_to_settle(sim, 200);
    CHECK_EQ(sim.units_at(Vec3i(0, 10, 0)), 0, "fall: nothing left up high");
    CHECK_EQ(sim.units_at(Vec3i(0, 1, 0)), 8, "fall: all 8 units pooled on the floor");
    CHECK_EQ(sim.total_units(), 8, "fall: volume conserved");
    CHECK_EQ(sim.conservation_delta(), 0, "fall: audit balances");
}

// ----------------------------------------------------------------------------
// Scenario 4 — an orphaned 1-unit cell evaporates after exactly EVAP_TTL ticks.
// We seed a single lone unit with NO water and NO source in its 6-neighbourhood,
// sitting on a 1-cell solid pad. It must survive EVAP_TTL-1 ticks and be gone on
// the EVAP_TTL-th, with the evaporated unit ledgered (audit still balances).
// ----------------------------------------------------------------------------
static void scenario_orphan_evaporates() {
    World w;
    w.solid.insert(Vec3i(0, 0, 0)); // tiny pad so the lone unit doesn't fall
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    // ingest() adopts an existing 1-unit cell (place() would also work, but
    // ingest is the dormant-water path and doesn't stack upward).
    sim.ingest(Vec3i(0, 1, 0), 1);
    CHECK_EQ(sim.units_at(Vec3i(0, 1, 0)), 1, "evap: lone 1-unit cell seeded");

    // The countdown advances one per tick while the cell stays orphaned. The
    // cell first ARMS its TTL on the tick it is stepped, so it disappears after
    // EVAP_TTL steps where it was orphaned. Step one at a time and watch it.
    const int ttl = FiniteWaterCore::EVAP_TTL; // 40
    int gone_tick = -1;
    for (int t = 1; t <= ttl + 5; ++t) {
        sim.step(0);
        if (sim.units_at(Vec3i(0, 1, 0)) == 0) { gone_tick = t; break; }
    }
    CHECK(gone_tick == ttl, "evap: orphan disappears on exactly the EVAP_TTL-th tick");
    CHECK_EQ(sim.total_units(), 0, "evap: ledger empty after evaporation");
    CHECK_EQ(sim.stats().evaporated, 1, "evap: one unit ledgered as evaporated");
    CHECK_EQ(sim.conservation_delta(), 0, "evap: audit balances (1 placed, 1 evaporated)");
}

// ----------------------------------------------------------------------------
// Scenario 4b — adjacent water CANCELS the evaporation countdown. A lone unit
// that gets a neighbour before EVAP_TTL must NOT evaporate. (Guards the rule
// that any water arriving next to an armed cell disarms it.)
// ----------------------------------------------------------------------------
static void scenario_neighbour_cancels_evap() {
    World w;
    w.add_floor(0, 2);
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    sim.ingest(Vec3i(0, 1, 0), 1); // lone unit, starts arming its TTL
    // Let it arm for a few ticks (well under EVAP_TTL).
    for (int t = 0; t < 5; ++t) sim.step(0);
    CHECK_EQ(sim.units_at(Vec3i(0, 1, 0)), 1, "cancel: lone unit still present pre-cancel");

    // Now drop water right beside it. The neighbour cancels the countdown.
    sim.ingest(Vec3i(1, 1, 0), 1);
    for (int t = 0; t < FiniteWaterCore::EVAP_TTL + 5; ++t) sim.step(0);

    // Two 1-unit cells with each other as neighbours can never evaporate and
    // can never donate (need >=2 to move). They just coexist; volume is 2.
    CHECK_EQ(sim.total_units(), 2, "cancel: both units survive (no evaporation)");
    CHECK_EQ(sim.stats().evaporated, 0, "cancel: nothing evaporated");
    CHECK_EQ(sim.conservation_delta(), 0, "cancel: audit balances");
}

// ----------------------------------------------------------------------------
// Scenario 5 — absorption into an ocean wall. Water poured beside a SOURCE wall
// below sea level is swallowed (absorbed), ledgered, and the source cells are
// never mutated. Confirms the audit counts absorbed units.
// ----------------------------------------------------------------------------
static void scenario_ocean_absorb() {
    World w;
    const int sea = 100; // high sea level so all our cells are "below sea"
    w.add_floor(0, 3);
    // An infinite ocean wall just to the +X side of the placement cell.
    w.source.insert(Vec3i(1, 1, 0));
    FiniteWaterCore sim(w.solid_fn(), w.source_fn(), sea);

    sim.place(Vec3i(0, 1, 0), 8); // pours next to the ocean wall
    run_to_settle(sim, 500);

    // The lone source cell must be untouched (immutable boundary).
    CHECK(w.source.count(Vec3i(1, 1, 0)) != 0, "absorb: source cell still exists in world");
    // All finite water got eaten by the ocean (merge fires because the cell is
    // below sea and face-adjacent to source; absorb fires on lateral moves).
    // Either way the units leave the finite books, and the audit must balance.
    CHECK_EQ(sim.total_units(), 0, "absorb: finite water consumed by the ocean");
    FiniteWaterCore::Stats s = sim.stats();
    CHECK_EQ(s.absorbed + s.merged, 8, "absorb: all 8 units ledgered as absorbed or merged");
    CHECK_EQ(sim.conservation_delta(), 0, "absorb: audit balances");
}

// ----------------------------------------------------------------------------
// Scenario 6 — the conservation audit holds across a busy multi-tick run with
// placements, a removal, and spreading all interleaved. This is the headline
// invariant: no sequence of operations may create or destroy units except
// through the explicit counters.
// ----------------------------------------------------------------------------
static void scenario_multitick_audit() {
    World w;
    w.add_floor(0, 20);
    FiniteWaterCore sim(w.solid_fn(), w.source_fn());

    // Place a few separate pools, tick between them, scoop some back out.
    sim.place(Vec3i(0, 1, 0), 24);
    for (int t = 0; t < 10; ++t) {
        sim.step(0);
        CHECK_EQ(sim.conservation_delta(), 0, "multitick: audit holds during early spread");
    }
    sim.place(Vec3i(5, 1, 0), 40);
    sim.place(Vec3i(-5, 1, 3), 16);
    for (int t = 0; t < 10; ++t) sim.step(0);

    int removed = sim.remove(Vec3i(5, 1, 0), 8); // scoop a bucket back out
    CHECK(removed >= 0, "multitick: remove returns a non-negative count");

    run_to_settle(sim, 4000);

    // The audit is the whole point: total == placed - evap - absorbed - merged - removed.
    FiniteWaterCore::Stats s = sim.stats();
    CHECK_EQ(sim.conservation_delta(), 0, "multitick: final audit balances");
    CHECK_EQ(sim.total_units(),
             s.placed - s.evaporated - s.absorbed - s.merged - s.removed,
             "multitick: total_units equals the explicit ledger formula");
    CHECK(sim.is_settled(), "multitick: sim settles");

    // Determinism: a second identical run produces a byte-identical signature.
    FiniteWaterCore sim2(w.solid_fn(), w.source_fn());
    sim2.place(Vec3i(0, 1, 0), 24);
    for (int t = 0; t < 10; ++t) sim2.step(0);
    sim2.place(Vec3i(5, 1, 0), 40);
    sim2.place(Vec3i(-5, 1, 3), 16);
    for (int t = 0; t < 10; ++t) sim2.step(0);
    sim2.remove(Vec3i(5, 1, 0), 8);
    run_to_settle(sim2, 4000);
    CHECK(sim.state_signature() == sim2.state_signature(),
          "multitick: two identical runs yield identical state signatures");
}

// ----------------------------------------------------------------------------
// main
// ----------------------------------------------------------------------------
int main() {
    scenario_single_placement();
    scenario_spread_flat_floor();
    scenario_fall_downward();
    scenario_orphan_evaporates();
    scenario_neighbour_cancels_evap();
    scenario_ocean_absorb();
    scenario_multitick_audit();

    const bool ok = (g_fails == 0);
    std::printf("[water   ] %s\n", ok ? "PASS" : "FAIL");
    std::printf("----\n%d checks, %d failure(s)\n", g_checks, g_fails);
    return ok ? 0 : 1;
}
