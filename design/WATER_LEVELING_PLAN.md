# Water Leveling — Sim Plan (2026-05-27, design only, no code yet)

> **Status:** DESIGN. Decision pending — choose Variant A or B (or
> reject). Implementation is queued behind: (1) designer testing the
> 2026-05-27 diagnostics bundle (F8 look-ray, F9 force-fill, shader
> modes 7+8) to confirm where the LOD-gap-bands originate, AND (2)
> designer green-lighting one of the variants below.

## The two interacting bugs in `WaterFlowManager`

Diagnosed from the 2026-05-27 in-engine session log:

```
[FlowDiag] frontier=72  filled=72  ...  lvl1-8=0/0/0/0/0/0/0/72
[FlowDiag] frontier=0   filled=0   ...  enqueued=1279
[FlowDiag] settle=on(y2147483647 found=0)
```

1. **Every fill writes level 8.** `lvl1-8=0/0/0/0/0/0/0/72` means every
   one of the 72 cells filled went in at full level. The connectivity
   fill (`_process_connectivity_fill`) pops a cell from `_fill_buckets`
   and calls `queue_set_water_voxel(pos, WaterByteCodec.SOURCE_BYTE)` —
   SOURCE_BYTE is `0x18` = level 8 | source bit. There is NO gradient
   produced. The histogram is unanimous because the algorithm is
   unanimous.

2. **Settle is mostly off-cursor.** `settle=on(y2147483647 found=0)`
   shows the sentinel state — `_settle_y = INT_MAX` is the "not started"
   marker. The settle pass only kicks in when `_settle_dirty == true`,
   which requires `_fill_buckets` to convert a cell INSIDE the tracked
   `_settle_min..max` AABB. The AABB grows by `_track_settle(pv)` which
   is called only when the fill itself converts something. So when a
   blast clears 1000 air voxels but the fill rate is 12/tick, only the
   ~12 cells converted per tick widen the AABB → settle thinks the
   dug volume is much smaller than reality → sweeps a tiny slice → 18
   found, done, sentinel. The surface stays bumpy because settle
   doesn't see the unfilled holes left behind in chunks the fill
   hasn't reached yet.

3. **Fill rate is the designer's deliberate trickle.** `WATER_FILL_CELLS_PER_TICK = 12`
   was chosen 2026-05-18 as "slow but complete." But "complete" requires
   the settle pass to actually re-sweep — which it doesn't because of
   issue (2). Result: a 4000-cell blast crater takes 4000/12/4 ≈ 83
   seconds to fully fill via the connectivity sim, and any cells dropped
   by async-write contention stay as visible surface holes.

The user's stated requirement: *"water flows, fills up the voxel hole
from the bottom, and then eventually levels out perfectly flat with
the global water plane."*

The current sim does fill bottom-up (Y-bucketed frontier), but slowly
and without a proper settle, so "eventually levels out perfectly flat"
is not happening.

---

## Variant A — Minecraft infinite-source (RECOMMENDED for "perfectly flat")

**Idea:** Drop the per-cell level gradient entirely. Every sub-sea-level
air voxel adjacent to existing water becomes full water immediately on
the next tick. Surface always reads as a perfect plane at `sea_voxY`.

**Behavior:**
- After a blast carves N sub-sea air voxels, ALL N are converted in a
  single flood-fill pass from the source (the ocean / lake the blast
  exposed to).
- Rate is bounded by the flood-fill work, not by an artificial
  per-tick cap. Even a 4000-voxel crater fills in 1-2 flow ticks
  (~250-500 ms).
- Surface is mathematically flat after settling: every water column
  ends at the topmost air-or-solid voxel ≤ sea level.

**Why this matches the design bible:** The existing v2 sim's docstring
already says "Minecraft-equivalent GAMEPLAY flow" — Minecraft itself
uses infinite-source bodies of water (a SOURCE block always re-creates
itself). Variant A is "be honest about Minecraft model" — drop the
sham gradient that no one is currently producing anyway.

**What changes in `WaterFlowManager.gd`:**
1. `_process_connectivity_fill` — replace the Y-bucketed dripper with
   a `_flood_fill_from_source(seed_chunks)` that does one BFS pass per
   seeded chunk and converts EVERY reachable sub-sea air voxel in one
   shot. Per-tick budget becomes a chunk-count cap (e.g. 16 chunks per
   tick) not a voxel-count cap.
2. `_process_water_settle` — repurpose as a "verify and self-heal" pass
   that walks the tracked AABB every tick (not gated on `_settle_dirty`)
   and re-bucket-pushes any sub-sea air voxel touching water. Runs
   until found=0 for a full pass, then idles.
3. `WATER_FILL_CELLS_PER_TICK` — retired. The chunk-cap replaces it.
4. Level-byte histogram (`_diag_level_hist`) — kept but reduces to
   "lvl8=N" since gradients are gone.
5. `get_flow_velocity_at` — already returns 0 when every neighbour is
   level 8 (oceans don't push), so currents only happen at river-feed
   transitions. Unchanged behaviour for the player.

**What designer loses:** the (unimplemented) potential for visible
flow-tail levels 1-7 in a thin river or a draining waterfall. The
visual is "fluid voxels are full or empty" — same as Minecraft.

**Effort:** medium. Touches ~300 lines in WaterFlowManager. Two new
parity gates: `flood_fill` (BFS converges in one pass; converts
exactly the connected sub-sea air component) and `flood_settle` (no
air-touching-water remains after one settle sweep on a flat body).

---

## Variant B — Keep the gradient, fix the settle

**Idea:** Keep the per-level write the docstring promises. Make settle
aggressive enough that even at 12 cells/tick the surface levels out
in a few seconds.

**Behavior:**
- Fill still writes per-level (level N at distance N from source, up
  to MAX_LEVEL=8).
- Settle re-sweeps the WHOLE tracked AABB on EVERY tick, not gated on
  `_settle_dirty`. Re-bucket-pushes any air-touching-water cell.
- Surface levels out over more ticks but with a visible gradient on
  the edges (level-7 fringe around a level-8 body).

**Why this might be preferred:** the gradient could read nicer on
small features (a player-built canal would show flow direction in the
shader's flow-vector mode). But the current shader maps levels 1-7 to
auto-sloped fluid models (16..22), so the visible difference is just
SURFACE HEIGHT (level 7 = 7/8 voxel tall) — not great for a body
that's supposed to be flat.

**What changes:**
1. `_process_connectivity_fill` — track distance-from-source per cell
   in the frontier; write `WaterByteCodec.pack(8 - dist, ...)` at each
   pop. Settle still writes full level 8 to indicate "settled".
2. `_process_water_settle` — drop the `_settle_dirty` gate; always
   sweep when `_settle_min..max` is valid; re-bucket on any
   air-touching-water hit. Idle when a whole pass returns found=0.
3. `WATER_FILL_CELLS_PER_TICK` — raised to 48 (4× faster) so blast
   craters fill in seconds, not minutes. Designer keeps the dial.

**What designer keeps:** the gradient as a visual cue. Surface still
isn't perfectly flat (level-7 fringe always present at edges).

**Effort:** small-medium. ~120 lines touched in WaterFlowManager. One
new parity gate (`flow_settle_gradient`).

---

## Recommendation

**Ship Variant A.** The user said "perfectly flat with the global
water plane" — that's the contract. A gradient that no one currently
produces and no shader path currently visualizes is dead weight; the
"realistic-looking water flow" the user wants is visible in the
*surface motion* (the v9 shader's wave/flow normal, modulated by the
fluid mesher's auto-slope) and in *currents* (`get_flow_velocity_at`
gradient at river→ocean transitions), neither of which depends on
per-cell level. The honest call is to delete the unimplemented half
and harden the half we want.

If designer wants the level gradient for future river-tail visuals,
keep this doc for the day we add visible river meshes — Variant B is
restartable from here.

---

## Out-of-scope (not part of this plan)

- The LOD-gap-band visual (the wide pale stripes in the 2026-05-27
  screenshot). That's a fluid MESHER / GENERATOR layer issue, not a
  sim layer issue. The 2026-05-27 diagnostics bundle (F8 look-ray,
  F9 force-fill, shader modes 7+8) is built to bisect it. Fix lands
  in a separate change.
- Rivers / waterfalls / flowing fronts (the deferred VoxelBlockyFluid
  level-tracked refinement). Pre-existing deferred. Not blocked by
  the leveling fix.
- Per-biome water colour / muddy rivers / glacial cyan. Phase 4c of
  `design/WATER_SHADER_V3_PLAN.md`, still deferred.

---

## Implementation gates (when designer green-lights direction)

1. **Decision recorded here** (which variant; why).
2. **Headless parity gates added** for the new sim path BEFORE the
   code (per the established `tools/headless/run.ps1 <name>` pattern).
3. **Diff-only PR** — sim file + parity gates + this doc updated with
   "SHIPPED <SHA>". No other code touched.
4. **Designer in-engine acceptance test:** powder-charge a sub-sea
   crater 4×4×4 m, watch the surface — should be flush flat within 2
   seconds (Variant A) or 5 seconds (Variant B). `[FlowDiag]` should
   report `frontier=0 filled=0 settle=flat` once converged.
