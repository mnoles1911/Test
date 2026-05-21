# Water Stage 6 — Partial-Height + Directional Flow (PLAN)

> ## ⚠ SUPERSEDED 2026-05-18 — NATIVE-FLUID PIVOT
> The Stage-6 **smooth-only custom-surface-mesher** approach below
> (esp. §5 / §6 / §9 / §11 — the Phase-2 spike + STOP gate) was
> **superseded by the engine-native Zylann fluid pivot.** The smooth
> goal is unchanged; the *means* changed: water is now 8 per-level
> `VoxelBlockyModelFluid` models (`CHANNEL_TYPE` 16–23) via
> `scripts/WaterMaterial.gd`; the Zylann blocky mesher auto-slopes the
> surface and feeds flow to the shader via UV — **no custom mesher**
> (the `water_chunk_mesher` C++ was deleted). The custom-mesher risk
> the §11 spike existed to test no longer applies.
>
> **What shipped (branch `water-native-fluid-pivot`, phase-by-phase,
> headless-parity-validated, NOT merged — one designer visual review
> pending):** H0 hybrid headless harness · GATE 0 (fluid API probed,
> `design/WATER_NATIVE_FLUID_GATE0_RESULTS.md`) · WaterMaterial
> identity authority · runtime fluid-model injection · sim→per-level
> TYPE projection · C++ generator (id 23 + DATA5 source byte for
> infinite-source oceans #14) · shader v9 (foam removed, flow
> animation, F6 +mode 5) · player/MP/save audit (non-destructive;
> `design/SAVE_SYSTEM.md`) · waterfalls #12 via
> `dip_when_flowing_down`. #11 gradual fill + #13 buoyancy were
> already on `main` (PR #224).
>
> Sections below are retained for history. Where they describe a
> custom surface mesher / stair-step rejection / Phase-2 spike STOP
> gate, read them as **context, not the implementation.** §8 (source
> rules) is still accurate and was delivered as Phase 8a.

Status: **SUPERSEDED — see the banner above. Original draft follows.**

V2 CONTEXT (formerly in `WATER_VOXEL_V2_PLAN.md`, since deleted as a
fully-superseded plan file): the pre-Stage-6 architecture was a
transparent `CHANNEL_TYPE == 5` blocky cube water block drawn by the
terrain mesher; the flow tick was a gravity-drop + carve-gated flood
that filled cells **all-or-nothing**. Stage 6 set out to add partial
heights + directional flow on top of that cube water; the native-fluid
pivot then replaced ALL of it with `VoxelBlockyModelFluid` at
`CHANNEL_TYPE` ids 16–23. Current architecture lives in
`design/SWIMMING_AND_WATER.md`.

---

## 1. What we're fixing (plain English)

Today every water voxel is either a **full cube** or **nothing**. That
causes three of your backlog items at once:

- **Fill is instant + blocky.** A dug pit snaps from empty to full
  cubes. There is no "rising water line."
- **No flowing look.** Water can't slope, so a river or a fill front is
  a wall of full cubes, not a moving surface.
- **No waterfalls.** Water dropping off a ledge is just a vertical
  column of full cubes — no thin falling sheet.

Stage 6 adds two things to every water voxel:

1. **A level, 1–8** (how full the cell is — like Minecraft). 8 = full,
   1 = a thin film. Fill becomes *gradual*: a pit fills 1→8 over time.
2. **A flow direction** (which way this cell is draining toward). This
   is what lets the surface *slope* and *animate* in the flow
   direction, and what tells a waterfall it's falling.

Everything else you asked for (gradual fill #11, waterfalls #12) falls
out of these two. "Make it look a lot better" is the rendering half
(Section 5) plus the later normal-map polish (#15, separate).

**Non-goals for Stage 6:** buoyancy/swimming (#13, independent),
source/infinite-source rules (#14, independent — though Stage 6 makes
them *easy*, see §8), ocean wave displacement (intentionally dropped in
V2, stays dropped).

---

## 2. The hard constraint (why this isn't just a tweak)

`VoxelMesherBlocky` (Zylann, C++, not ours) only draws **full cubes**,
one model per `CHANNEL_TYPE` id. It physically cannot draw a
7/8-height block or a sloped surface. So partial-height water is **not
a texture problem and not a one-shader-line problem** — it needs a
decision about *how the water surface gets geometry*. That decision is
the spine of this plan (§5) and is the main thing I need you to weigh
in on.

The good news: the **data substrate already exists**. `WaterByteCodec`
(currently dormant, legacy since V2) already encodes, per voxel, into
`CHANNEL_DATA5`:

- bits 0–3: **level 0–8** (0 = air, 8 = full) — exactly what we need.
- a **source bit** (this cell is an infinite source) — gives us §8 free.
- tick bits (flow bookkeeping).

So we keep `CHANNEL_TYPE == 5` as the cheap "is this water?" flag
(collision, culling, all the existing `== 5` queries, the depth-fade
shader keep working untouched) **and** light up `CHANNEL_DATA5` as the
level + flow side-channel. We need to **add a flow-direction field**
(3 bits = 6 cardinal dirs + up + still) to `WaterByteCodec`; there is
room by trimming the tick field or moving to a 2-byte layout — a Phase
0 decision, low risk.

---

## 3. Architecture at a glance

```
WaterFlowManager (4 Hz tick, exists)
  ├─ v2 today:   per-cell full/empty flood        → CHANNEL_TYPE 5
  └─ Stage 6:    per-cell LEVEL 1–8 + FLOW DIR     → CHANNEL_DATA5 (WaterByteCodec)
                 (TYPE 5 still written: "≥1 = water" for collision/culling/queries)

Rendering of the surface  ── DECIDED 2026-05-18: SMOOTH-ONLY ──
  Dedicated per-chunk water SURFACE MESHER built from the DATA5
  level+dir grid, drawn with the v8 depth-fade shader, per-vertex
  height (sloped between neighbours) + flow vector for animation.
  Option A (8 stair-step level-models) was considered and REJECTED
  by designer decision — no stepped interim ships, no fallback (§5).

Queries (exist, light edits)
  WaterFlowManager.is_position_in_water / get_water_level_at
     → resolve against DATA5 level instead of "TYPE==5 means full"
  Player3D water state, UnderwaterFilter: read true surface height from level
```

Key property: until the surface mesher exists (Phase 2), water keeps
rendering as the **current V2 full cubes** (level ≥ 1 → TYPE 5). That
is a *diagnostic fallback while we prove the sim in isolation* — it is
the existing look, NOT a new stepped look we built and not shipped as
the answer. **#11 (gradual fill) becomes visible when the smooth
surface mesher first renders levels (Phase 2);** #12 (waterfalls)
follows in Phase 4.

---

## 4. Flow-sim changes (`WaterFlowManager`)

Builds directly on the existing `_run_flow_tick_v2` / `_flow_chunk` and
the `_pending_water` async-readback fix (don't re-derive those — they
work). Changes, smallest-first:

1. **Track level, not boolean.** The flood/gravity step computes a
   target level per cell from neighbours (standard cellular water:
   a cell's level = max(neighbour-fed level − 1, vertical inflow)).
   Write `WaterByteCodec.pack(level, source, tick)` to DATA5; write
   `TYPE = 5` whenever level ≥ 1 (so all existing "is water" logic and
   the depth-fade shader are unaffected), `TYPE = air` at level 0.
2. **Derive flow direction** from the level gradient (flow points from
   higher level toward the lowest open neighbour; straight down if the
   cell below is open). Pack into the new DATA5 dir field.
3. **Rate = the gradual-fill dial.** Level rises at most +1 per cell
   per tick (already 4 Hz). That alone makes fill visibly progressive.
   Expose the per-tick level delta + tick interval as tunables (the
   "slower / faster fill" knob you asked for) — same live-tune pattern
   as the shader uniforms.
4. **Settling.** A cell whose neighbours are all ≥ its level and which
   has no downward outlet marks itself *still* (dir = still) and stops
   re-evaluating until a neighbour changes — this is what stops the
   "powder-spam never settles" class of churn and keeps PERF sane.

PERF note: per-level sim is more work than the boolean flood.
`WaterFlowManager`'s flow tick is **already the #1 C++-port candidate**
in CLAUDE.md. Plan: build Stage 6 in GDScript, keep the parity-harness
discipline, and if `[PERF]` shows it in the top-3 after Phase 2, port
`_flow_chunk` to the C++ extension (the escape hatch is expected here,
not a surprise).

---

## 5. Rendering — DECIDED: smooth-only surface mesher

**Designer decision 2026-05-18: smooth-only. No stair-step interim
ships; no Option-A fallback.** The cheap path is recorded below only so
the rejection is documented and not re-litigated.

### 5.1 Rejected: Option A — eight blocky level-models
Register water as 8 type ids (cube per level), mesher picks by level.
Cheap and reuses the C++ mesher, but the surface is **stair-stepped**
(terraced rice-paddy look for any river/fill front), burns 8 type ids,
and turns every `== 5` check into a range check. **Rejected** — the
explicit goals are "rendered in a flowing way" and "look a lot
better"; a permanently terraced surface fails both. Not built, not
shipped as an interim.

### 5.2 Chosen: dedicated water surface mesher
Water stays the single `TYPE == 5` model for body / collision /
culling / existing queries / the v8 depth-fade shader (all untouched).
A **second render pass** builds, per chunk, a water-surface `ArrayMesh`
from the DATA5 level+dir grid:
- **per-vertex height** = partial level, **interpolated/sloped**
  against neighbour levels so the surface is continuous, not stepped;
- **per-vertex flow vector** (from the dir field) handed to the v8
  shader for directional surface animation (Phase 3);
- vertical faces where `dir == down && level < 8` → the thin falling
  sheet that makes **waterfalls (#12)** in Phase 4.

This is, deliberately, **reviving a water surface mesher** — V2 *did
delete* `WaterChunkMesher` (2026-05-16). We are knowingly reversing
that, building a *different, better* one (greedy smooth surface from
the level grid, not the old DATA5-shell). The designer has accepted
this architectural reversal and the up-front risk.

### 5.3 Consequence of smooth-only (accepted)
- The riskiest unknown — a custom surface mesher coexisting with
  Zylann's LOD streaming — moves **up front (Phase 2)** instead of
  being a late, isolated, behind-a-flag phase.
- There is **no stepped fallback**. While Phases 0–1 prove the sim,
  water renders as the *existing* V2 full cubes (diagnostic only).
  First *new* visible result = Phase 2 (smooth surface). Longer wait
  to first playable improvement; the designer chose this for a better
  first impression.
- Phase 2 therefore **opens with a spike, not a commit** (§6, §9): if
  the spike shows the mesher cannot meet the LOD/perf bar, we
  **re-convene and re-decide** — we do *not* silently fall back to
  stair-step (there is no stair-step path in the tree).

---

## 6. Phasing (each phase ends in a green in-game test)

No headless Godot — every phase is validated by you running a scene and
pasting `[FlowDiag]` / `[WaterDiag]` lines, same loop as the V2 work.

- **Phase 0 — codec.** Add the 3-bit flow-dir field to
  `WaterByteCodec`; bit-exact parity check via a `@tool` EditorScript
  in `scripts/_dev/`. No behaviour change yet. (S)
- **Phase 1 — sim writes levels.** `WaterFlowManager` tracks level
  1–8, writes DATA5 + TYPE. Rendering is the **existing V2 full cubes**
  (level ≥ 1 → TYPE 5) — diagnostic only, no new look. `[FlowDiag]`
  gains a `level` histogram. Test: dig a pit, watch levels climb 1→8
  in the logs (sim proven in isolation before any mesher work). (M)
- **Phase 2 — surface mesher: SPIKE → minimal smooth surface.**
  *Starts as a throw-away spike* answering the §9.1 risk: can a custom
  per-chunk water-surface mesh coexist with Zylann LOD
  streaming/eviction at acceptable perf? **Gate:** if the spike fails
  the LOD/perf bar we STOP and re-convene (no stair-step fallback
  exists by design). If it passes, promote to a minimal mesher: flat
  per-cell height (no slope yet), behind a flag. **This is where #11
  gradual fill becomes visible** — a smooth rising surface. Tunable
  fill-rate. Test: pit/trench/cave fills slowly with a smooth surface. (L)
- **Phase 3 — slope + flow direction + animation + settling.**
  Interpolate vertex height against neighbour levels (continuous, not
  stepped); dir field from the level gradient; still-cell settling;
  feed the flow vector to the v8 shader for directional surface
  animation; add the `WaterDiag` flow-vector `debug_mode`. Test: a
  river slopes downhill and visibly flows; ponds settle and stop
  churning; `[FlowDiag]` dir/still counts sane. (M)
- **Phase 4 — waterfalls (#12).** Vertical falling-sheet rendering +
  particle/audio hooks, driven by `dir == down && level < 8`. (M)

Phase 0–1 are pure sim/data and can start immediately. **Phase 2 is
the project's pivot point** — it front-loads the single biggest
unknown by designer choice (smooth-only, no fallback).

---

## 7. Diagnostics (extend, don't reinvent)

- `[FlowDiag]`: add per-level cell counts + flow-dir distribution +
  "still" count (proves settling works, catches churn regressions).
- `WaterDiag` F4 panel: show level + dir at the player's cell.
- New `water.gdshader` `debug_mode` value: **flow vectors** (hue =
  direction, brightness = level) — the Phase 3/4 inspection tool.
  (Keep the existing 0–4 modes; this is additive, like the others.)
- `design/PROFILER_AND_DIAGNOSTICS.md` gets the new fields documented
  (it's in the CLAUDE.md maintenance table — update on landing).

---

## 8. Free side-effect: source rules (#14)

`WaterByteCodec` already has a **source bit**. A "source" cell is
pinned at level 8 and never decremented; flow propagates *away* from
it. That is exactly the finite-vs-infinite mechanic in #14: ocean/lake
generator cells = source; a dug pool of moved water = non-source and
drains. So #14 becomes mostly "decide which cells get the source bit"
rather than new machinery — note it, do it after Stage 6 lands.

---

## 9. Risks / open questions

1. **(BIGGEST) Surface mesher × Zylann LOD streaming.** A custom
   per-chunk water-surface mesh must respect chunk load/unload + LOD
   like the old `WaterChunkMesher` had to — and there is **no
   stair-step fallback** (smooth-only decision). This is the project's
   pivot risk. Mitigation: **Phase 2 opens as a throw-away spike with
   an explicit STOP/re-convene gate** — we do not commit to the mesher
   until the spike clears the LOD/perf bar.
2. **§5 look decision: RESOLVED** — smooth-only, Option A rejected,
   2026-05-18. No longer open.
3. **Perf of per-level sim** — more work than the boolean flood;
   `WaterFlowManager` is already CLAUDE.md's #1 C++-port candidate.
   Mitigated by that escape hatch; tracked via `[PERF]`, not assumed.
4. **Save/migration** — DATA5 levels are new save data. Existing
   `VoxelStreamSQLite` deltas are TYPE-only; old saves load as "all
   full (level 8)" which is correct and safe. No migration needed,
   but call it out in `SAVE_SYSTEM`.

---

## 10. Status / next action

The one blocking decision (§5) is **made: smooth-only**. Nothing else
is blocking. Phase 0 (codec) + Phase 1 (sim writes levels) are pure
sim/data and can start immediately. Phase 2 is the pivot — it begins
with the spike + STOP-gate in §6/§9.1. I'll proceed on the plan above
unless you flag something in this doc.
