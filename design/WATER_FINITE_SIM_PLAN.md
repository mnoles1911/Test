# Water — Finite Volume-Conserving Sim (decided 2026-06-10)

> **Status: APPROVED, in implementation.** Designer decision 2026-06-10:
> water becomes a **finite, volume-conserving fluid**. Placing a 3×3×3
> bucket of water (27 cells × 8 units = 216 units) must visibly collapse
> and spread into a wider, shallower, LEVEL pool. Oceans stay
> infinite-source. This supersedes `WATER_LEVELING_PLAN.md` (rejected)
> and is the third-generation water sim after the `_flow_chunk`
> automaton (parked 2026-05-18, deleted 2026-06-10) and the
> connectivity-fill (kept — it becomes the OCEAN-only subsystem).

## Designer decisions (locked)

1. **Finite, volume-conserving.** Each 1×1×1 voxel cell holds 1–8
   units of water (the existing DATA5 level bits). Units physically
   TRANSFER between cells; total volume is conserved and auditable.
2. **Oceans stay infinite.** Blast a crater below sea level → the ocean
   refills it completely, exactly as today. The finite sim governs
   player-placed water and inland water above sea level.
3. **Spread reach: 18 voxels** (~3 m at 6 vox/m) max horizontal flow
   distance across a level surface before the front stops advancing.
   Tunable constant (`SPREAD_REACH_VOXELS`).

## Post-mortem: why the previous sims kept breaking

The deleted `_flow_chunk` automaton (see git history of
`scripts/WaterFlowManager.gd` before 2026-06-10, or PR W1's diff) had
three documented failure modes, all patched with layered band-aids:

1. **Async readback lag** — sim writes go through VoxelEditManager's
   async queue, so the automaton couldn't see its own just-written
   water on the next tick (`rej_unfed` in the hundreds). Band-aid: the
   `_pending_water` shadow dict + confirm-on-read + TTL + retry caps.
2. **TTL-based carve permission** (`_edit_cell_ttl`) — a time window
   used as a spatial gate. Slow fronts arrived after permission
   expired → permanently unfillable cells ("blast again to fix it").
   Band-aid: TTL raised 4 → 600.
3. **Per-chunk dirty granularity** — fronts stalled at chunk seams
   because the neighbouring chunk was never dirtied.

**Root cause, shared by all three: the simulation used the
asynchronously-written voxel world as its own memory.** Every fix
compensated for not being able to trust a read-back.

**First principle of the finite sim:** the sim owns an **in-memory
ledger** as the single authority. DATA5/TYPE writes are *projections*
of the ledger for rendering/persistence — re-queued until they land,
never read back during stepping. With that, no TTL, no pending-shadow,
no retry caps are needed, and conservation is checkable in pure memory.

## State layout

DATA5 byte (persisted, `scripts/WaterByteCodec.gd` — layout unchanged):

| Bits | Meaning |
|---|---|
| 0–3 | **level = units 1..8** (the conserved quantity; 0 = air) |
| 4 | **SOURCE = infinite** (ocean / designer headwaters / legacy water). The finite sim never simulates source cells. |
| 5–7 | **dir** — written by the finite sim as it flows (real flow direction); reset to `DIR_STILL` when a cell settles. |

Spread-distance (0..18) and evaporation TTL do **not** fit in DATA5 —
they live only in the sim's in-memory records for *moving* fronts.
**Not persisted:** after save/load, water is dormant until an edit or
placement disturbs it; the disturbance grants a fresh reach budget.
Documented behaviour, not a bug.

Authority model (`scripts/FiniteWaterCore.gd`, PR W3):

- `_ledger: Dictionary<Vector3i, int>` — units per finite cell. **The truth.**
- `_meta: Dictionary<Vector3i, int>` — packed `dist | evap_ttl | dir`. Transient.
- `_active: Dictionary<Vector3i, true>` — cells to step next tick.
- `_unprojected: Dictionary<Vector3i, true>` — cells whose
  `queue_set_water_voxel` write was rejected (queue full); re-queued
  every tick until accepted. No TTL, no retry cap — the ledger knows
  the truth, so a dropped write can never become a hole.

## Sim rules (per tick, 4 Hz, host-only, deterministic)

Active cells are sorted ascending **(y, x, z)** each tick (the repo's
cross-language total-ordering rule) and stepped sequentially with
1-unit integer transfers — conservation is exact by construction, and
each move strictly reduces potential, so the sim provably terminates.

Per non-source active cell `c` with `u(c) ≥ 1`:

1. **DOWN first.** Below solid or NoEditZone-blocked → no drop. Below
   SOURCE → units absorbed into the ocean (ledgered). Below air or
   partial finite water → move `min(u(c), 8 − u(below))` units down;
   `dist(below) = 0` (a vertical drop starts a fresh reach budget).
2. **Lateral equalization** (only if `u(c) ≥ 2` after step 1 and `c`
   is supported by solid / source / full finite water below). Eligible
   neighbours among ±X/±Z:
   - finite water with `u(n) ≤ u(c) − 2` — **no reach check**
     (equalization inside an existing body must always be allowed or
     pools can't flatten);
   - air, only if `dist(c) < SPREAD_REACH_VOXELS = 18` — new cell gets
     `u = 1`, `dist = dist(c) + 1`;
   - SOURCE at `y ≤ sea_y` → 1 unit absorbed per move.
   Move **1 unit** to the lowest-`u` eligible neighbour; fixed
   tie-break `+X, −X, +Z, −Z`; loop until no eligible neighbour or
   `u(c) < 2`. `dir(c)` = direction of largest net transfer this tick,
   else `DIR_STILL`.
3. **Activity propagation.** Any cell whose units changed re-activates
   itself + its 6 neighbours that hold water or are air below water.
   Quiet cells go dormant and their final projection writes
   `DIR_STILL`. A 3×3×3 dump touches ~27 cells plus a growing ring —
   never the whole world.
4. **Thin film.** Units are integers, so sub-1-unit films can't exist;
   and level-1 cells can never donate laterally (rule 2 needs u ≥ 2),
   so films can't advance — they can only be left behind (e.g. water
   drained off a ledge leaving a lone 1-unit cell). Rule: a non-source
   `u == 1` cell with **no water in its 6-neighbourhood** arms
   `EVAP_TTL = 40` ticks (~10 s); any adjacent water cancels it; on
   expiry the cell evaporates (ledgered).
5. **Ocean merge.** A finite cell at `y ≤ sea_y` face-adjacent to a
   SOURCE cell converts to SOURCE (ledgered as merged) — it has joined
   the ocean; its units leave the finite ledger.

**Budget:** `FINITE_CELL_UPDATES_PER_TICK = 256` (tunable dial, same
philosophy as `WATER_FILL_CELLS_PER_TICK`), clamped under the existing
`_MAX_FLOW_BUDGET_PER_TICK = 4096` write ceiling. Spill keeps cells
active; sorted processing means the lowest cells settle first.

**Terrain reads:** solidity comes from one bulk `tool.copy()`
CHANNEL_TYPE snapshot of the active body's AABB per tick. The sim
**never reads DATA5 back during stepping** — DATA5 is read exactly once
per cell at *activation* (ingesting saved/dormant water the player just
disturbed).

**Conservation invariant (the testable property):**

```
Σ ledger.units == placed − evaporated − absorbed_to_ocean − merged_to_ocean
```

Asserted exactly in the headless gates (`finite` selector); surfaced
live in `[FlowDiag]` with a `push_warning` + red DebugOverlay line on
violation.

## Ocean boundary rule (precise)

- **bit 4 SOURCE = infinite.** The generator's ocean already writes
  `SOURCE_BYTE`. The connectivity fill + settle pass (which work) stay
  as the OCEAN subsystem, gated to `y ≤ sea_y` as today — but their
  write changes to `SOURCE_BYTE`: **ocean refill never creates finite
  water** (PR W2; reverses the Stage-6 "sim water must be drainable"
  note).
- **Fill seeding requires a SOURCE feed** (PR W2): `_seed_fill_from_aabb`
  and the fill's water-terminal check must test the feeding water's
  source bit — otherwise digging beside a finite pond below sea
  elevation would trigger an infinite ocean-fill *from finite water*.
  Legacy water (TYPE water, DATA5 == 0) conservatively counts as source.
- **Finite → ocean:** transfer into a source cell = absorbed (units
  destroyed, ledgered). Finite cell adjacent to source at `y ≤ sea_y`
  = merged to source (ledgered).
- **Ocean → finite: never.** Source cells are immutable boundary
  conditions to the finite sim — they never donate units, never change.
- `sea_y` only gates the ocean subsystem and the merge/absorb rules.
  Finite water is governed by the source bit, not by Y — a player
  puddle in a sealed cave below sea elevation stays finite.

## Implementation sequence (PR track; statuses updated as PRs land)

| PR | Scope | Status |
|---|---|---|
| W1 | Post-mortem + delete the dead `_flow_chunk` automaton (~1000 LOC); this doc | **SHIPPED** |
| W2 | Ocean boundary: fill writes `SOURCE_BYTE`; seeding requires SOURCE feed; settle requires SOURCE neighbour (GD ref + C++ parity) | pending |
| W3 | `FiniteWaterCore.gd` pure reference + `finite` headless gate (conservation / levelness / reach / evap / absorption / determinism) | **SHIPPED** |
| W4 | Engine integration: bucket places finite water; `_step_finite()` in the tick; `[FlowDiag]` ledger line | pending |
| W5 | Height-aware `is_position_in_water` (partial levels = wading); WaterDiag units + body totals | pending |
| W6 | C++ port of the step inner loop (`FiniteWaterCpp`) + tick-by-tick bit-exact parity gate | pending |
| W7 | Currents: `get_flow_velocity_at` reads sim-written DIR (+ fixed water-pair gradient fallback); `RiverFlowVolume` stamping for permanent rivers | pending |

## Headless gate scenarios (`finite` selector, PR W3)

1. **Collapse:** 3×3×3 dump (216 units) on a flat floor → converges in
   < 400 ticks; Σ units == 216; every adjacent connected water pair
   differs ≤ 1 level; max horizontal distance from the dump footprint
   ≤ 18; no cell > 8.
2. **Pit:** dump beside a pit → pit fills bottom-up, then levels.
3. **Evaporation:** ledge-drain leaves an isolated u==1 cell →
   evaporates after exactly `EVAP_TTL` ticks; ledger balances.
4. **Ocean wall:** inflow into a SOURCE wall at `y ≤ sea_y` is absorbed;
   ledger.absorbed matches; source cells unchanged.
5. **Reach:** 1000-unit column on an infinite plane → front halts at
   exactly 18; the pool deepens instead.
6. **Determinism:** identical run twice → byte-identical state every tick.

## Constants (all tunable, one place)

`SPREAD_REACH_VOXELS = 18` (~3 m) · `EVAP_TTL = 40` ticks (~10 s) ·
`FINITE_CELL_UPDATES_PER_TICK = 256` · tick = existing 4 Hz ·
write ceiling = existing `_MAX_FLOW_BUDGET_PER_TICK = 4096`.
