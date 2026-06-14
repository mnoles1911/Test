// FiniteWaterCore.h — the finite, volume-conserving water simulation.
//
// Ported 1:1 from Godot scripts/FiniteWaterCore.gd (design intent +
// conservation audit: design/WATER_FINITE_SIM_PLAN.md). This is the
// engine-agnostic Core copy used by the UE5 port AND by the standalone
// clang parity harness — so it touches NO engine types at all.
//
// ----------------------------------------------------------------------------
// WHAT THIS IS, IN PLAIN ENGLISH:
//
// Every cell of "finite" water (player-placed buckets, inland pools) is one
// entry in `_ledger`: a map from a voxel position to how many UNITS of water
// sit in that cell (1..8; 8 = a completely full voxel). When the sim runs,
// units physically MOVE between cells — DOWN first, then SIDEWAYS toward lower
// neighbours — until everything is level. Because every move is literally
// "subtract 1 here, add 1 there", the total amount of water can never silently
// change. That total is auditable at any instant:
//
//   total_units() == placed - evaporated - absorbed - merged - removed
//
// and the headless `finite` selector (here: test_water.cpp) asserts it.
//
// THE ONE BIG LESSON from the previous two water sims (post-mortem in
// WATER_FINITE_SIM_PLAN.md): this class NEVER reads the voxel world to learn
// where its OWN water is. The ledger is the single authority; the voxel world
// (the DATA5 byte) is a write-only projection of it. That is why there is no
// TTL-retry machinery, no pending-write shadow map, no self-heal scan — none of
// it is needed when the sim trusts its own memory instead of an async buffer.
//
// PURITY: no engine globals, no scene tree, no I/O. The world is abstracted
// behind two predicates injected at construction:
//   - solid_at(pos)  -> true if terrain blocks water here
//   - source_at(pos) -> true if this cell is INFINITE water (the ocean)
// In the Godot build these were Callables; in C++ they are std::function. The
// clang harness passes simple lambdas; the UE wrapper passes snapshot-backed
// tests. The sim is deterministic: active cells are processed in ascending
// (y, x, z) order with sequential 1-unit transfers, so two runs with the same
// inputs produce byte-identical states every tick (the parity contract).

#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

#include "Core/MiraVec.h"
#include "Core/WaterByteCodec.h"

namespace mira {

class FiniteWaterCore {
public:
    // ========================================================================
    // Tunables (designer dials — see WATER_FINITE_SIM_PLAN.md). Values match
    // the Godot constants EXACTLY; do not change without a designer decision.
    // ========================================================================

    // How far water may CREEP ACROSS A LEVEL SURFACE from where it was
    // introduced, in voxels (30 vox = 3 m at 10 vox/m — the designer's locked
    // 3-metre reach). Each sideways step into fresh air increments a cell's
    // "distance budget"; at 30 the front stops advancing and the pool deepens
    // instead. Falling down a ledge RESETS the budget (a waterfall starts a
    // fresh pool at its base). Equalization between cells that are ALREADY
    // water ignores this — otherwise a pool could never flatten.
    static constexpr int SPREAD_REACH_VOXELS = 30;

    // Ticks (~10 s at 4 Hz) before an ORPHANED 1-unit cell evaporates.
    // Level-1 cells can never donate sideways (the donor rule needs >= 2
    // units), so thin films can't creep — but draining can strand a lone
    // 1-unit cell on a ledge. If such a cell has NO water in any of its 6
    // face-neighbours, it arms this countdown; any water arriving next to it
    // cancels the countdown. Evaporated units are ledgered so the conservation
    // audit still balances.
    static constexpr int EVAP_TTL = 40;

    // A full voxel of water. Matches WaterByteCodec::MAX_LEVEL — level and
    // units are the SAME number, which is what lets the renderer draw a 3-unit
    // cell as the existing level-3 fluid model with zero new code.
    static constexpr int MAX_UNITS_PER_CELL = 8;

    // Sentinel matching the GDScript "very low" sea_y default = "no ocean"
    // (pure inland behaviour). Equals GDScript's -0x7fffffff exactly.
    static constexpr int NO_SEA = -0x7fffffff;

    // ========================================================================
    // World plumbing — injected once at construction.
    // ========================================================================
    // SolidFn:  func(pos) -> bool. True = terrain blocks water here.
    // SourceFn: func(pos) -> bool. True = INFINITE water here (the ocean /
    //           designer headwaters). Source cells are immutable boundary
    //           conditions: they never change, never donate. Finite water that
    //           flows into one is swallowed (absorbed/merged, ledgered).
    using SolidFn  = std::function<bool(const Vec3i&)>;
    using SourceFn = std::function<bool(const Vec3i&)>;

    // sea_y defaults to NO_SEA ("no ocean"), matching the GDScript default.
    explicit FiniteWaterCore(SolidFn solid, SourceFn source, int sea_y = NO_SEA);

    // ========================================================================
    // A single emitted projection change: the DATA5 byte for `pos` is now
    // `byte` (0 = water gone; SOURCE_BYTE = joined the ocean; else pack()).
    // Mirrors the flat [x, y, z, byte, ...] PackedInt32Array stream the
    // GDScript step() returns, but as a typed list (cleaner in C++).
    // ========================================================================
    struct Change {
        Vec3i pos;
        int   byte;
    };

    // The conservation counters (the audit trail) — mirror of GDScript stats().
    struct Stats {
        int units      = 0; // current total in the ledger
        int active     = 0; // cells the next step() will look at
        int placed     = 0; // units ever introduced via place()/ingest()
        int evaporated = 0; // orphaned 1-unit cells that timed out
        int absorbed   = 0; // units that fell/flowed into source water
        int merged     = 0; // units in cells that joined the ocean
        int removed    = 0; // units scooped back out (bucket fill)
    };

    struct StepResult {
        std::vector<Change> changes; // every cell whose projected byte changed
        Stats               stats;
    };

    // ========================================================================
    // Public API (1:1 with the GDScript class).
    // ========================================================================

    // Introduce water. Fills `pos` up to 8 units, then stacks any excess into
    // the cells directly above (a 1000-unit "place" is a tall column that
    // immediately starts collapsing). Returns units actually placed (solid /
    // source cells block).
    int place(const Vec3i& pos, int units);

    // Poke a cell awake (e.g. terrain next to it was just carved). Safe on
    // anything; only ledger cells actually wake.
    void activate(const Vec3i& pos);

    // Adopt water that already exists in the world (dormant water the player
    // just disturbed). Unlike place() this does NOT stack upward, and DOES
    // count toward `placed` (from the ledger's view this water is newly
    // tracked). No-op if the cell is already tracked (avoids double-counting).
    void ingest(const Vec3i& pos, int units);

    // Scoop water back out (bucket fill). Takes up to max_units from this cell,
    // then from the cells stacked directly above it. Returns units removed
    // (ledgered so the audit still balances).
    int remove(const Vec3i& pos, int max_units);

    // The DATA5 byte the world should show for `pos` right now.
    int projected_byte(const Vec3i& pos) const;

    bool has_cell(const Vec3i& pos) const;
    int  total_units() const;
    bool is_settled() const;

    // True while anything still needs a tick: cells to simulate OR
    // externally-mutated cells whose projection hasn't been flushed.
    bool has_pending_changes() const;

    int units_at(const Vec3i& pos) const;

    // 0 when the books balance. Anything else is a bug.
    int conservation_delta() const;

    Stats stats() const;

    // Deterministic fingerprint of the full sim state (sorted y,x,z) for the
    // determinism + parity gates — identical across runs/languages regardless
    // of map iteration order.
    std::string state_signature() const;

    // Advance the sim one tick. Processes up to `budget` active cells in
    // ascending (y, x, z) order (lowest first). budget <= 0 = no cap.
    StepResult step(int budget);

private:
    // ---- world plumbing ----
    SolidFn  solid_cb;
    SourceFn source_cb;
    int      sea_y;

    // ---- sim state ( _ledger is the authority; everything else bookkeeping )
    std::unordered_map<Vec3i, int>  _ledger;          // pos -> units (1..8). THE TRUTH.
    std::unordered_map<Vec3i, int>  _dist;            // pos -> spread budget spent
    std::unordered_map<Vec3i, int>  _evap_ttl;        // pos -> armed countdown
    std::unordered_map<Vec3i, int>  _dir;             // pos -> DIR_* code
    std::unordered_map<Vec3i, bool> _active;          // pos -> needs a step()
    std::unordered_map<Vec3i, bool> _merged_sources;  // pos -> joined the ocean
    std::unordered_map<Vec3i, bool> _external_changed;// pos -> mutated outside step()

    // ---- conservation counters ----
    int placed     = 0;
    int evaporated = 0;
    int absorbed   = 0;
    int merged     = 0;
    int removed    = 0;

    // ---- per-cell rules ----
    void step_cell(const Vec3i& c, std::unordered_map<Vec3i, bool>& changed);

    // ---- small helpers ----
    bool is_solid(const Vec3i& p) const;
    bool is_source(const Vec3i& p) const;
    bool is_supported(const Vec3i& c) const;
    bool touches_source(const Vec3i& c) const;
    bool has_water_neighbour(const Vec3i& c) const;
    void clear_cell(const Vec3i& c);
    void activate_with_neighbours(const Vec3i& p);
    void wake_ledger_neighbours(const Vec3i& p);
    int  projected_byte_impl(const Vec3i& p) const;

    // map lookups with a default (mirror of GDScript Dictionary.get(k, def))
    int  ledger_get(const Vec3i& p) const;   // 0 if absent
    bool ledger_has(const Vec3i& p) const;

    // Ascending (y, x, z) total ordering — the cross-language determinism rule.
    static bool cell_order(const Vec3i& a, const Vec3i& b);
};

} // namespace mira
