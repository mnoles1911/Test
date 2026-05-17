# Water Voxel V2 — Minecraft-model water (plan + migration)

**Status:** plan, 2026-05-16. Supersedes the `CHANNEL_DATA5` side-channel
water architecture in `design/SWIMMING_AND_WATER.md` ("Voxel Water
Architecture, v14") and retires `design/WATER_SHADER_V2_PLAN.md`'s
chunked-vs-horizon split. Decision approved by the designer after ~10
iterations proved the dual-system architecture is the root cause of the
seams/coverage/load problems.

---

## The decision in one sentence

**Water becomes a normal voxel block type, drawn by the same terrain
mesher as everything else (in its transparent pass) — exactly like
Minecraft — deleting `WaterChunkMesher` and the horizon plane entirely.**

## Why (plain English)

Minecraft water is fast, seamless, and reads depth correctly because it
is *one* system: water is a block, the chunk mesher draws it translucent,
done. Our project instead has **three** systems that must stay in sync:

1. `VoxelMesherBlocky` draws terrain but is told to **ignore** water.
2. `WaterChunkMesher` is a whole second mesher walking `CHANNEL_DATA5`
   on its own radius + per-frame budget.
3. A fake **horizon plane** paints "ocean" everywhere the second mesher
   doesn't reach.

Every bug in this saga — the chunked/horizon seam, water only near
spawn, LOD0-only emission, streaming-budget starvation, the
`is_area_editable` dropouts — is a *consequence of that split*. Minecraft
doesn't have these bugs because it doesn't have these systems. We adopt
its model.

## What we keep

- **The v8 depth-fade water shader.** It stops being a bolted-on screen
  trick and becomes the **material on the water block model**. Surface
  sheen + depth-graded transparency carry over unchanged. `.tres`
  tuning (`depth_fade_distance`, etc.) stays meaningful.
- `WaterByteCodec`'s *concepts* (level / source / flowing) — but moved,
  see "Flow metadata" below.
- The flow *rules* in `WaterFlowManager` (decay / gravity-drop / lateral
  spread) — reworked to operate on type-blocks, not DATA5 bytes.

## What gets deleted

- `scripts/WaterChunkMesher.gd` + `extensions/voxel_gen/src/
  water_chunk_mesher.{h,cpp}` (`WaterChunkMesherCpp`) — the entire
  separate water mesher.
- The follow-player horizon plane (built in the above) — gone; distant
  water now meshes with terrain at every LOD, like Minecraft.
- `assets/shaders/water_horizon.gdshader` + `water_horizon_material.tres`
  — no second surface to unify against anymore.
- All the diagnostic flags/logging added during the shader saga
  (`DIAG_WATER_COVERAGE`, `DIAG_DISABLE_HORIZON_PLANE`,
  `DIAG_DISABLE_CHUNKED_MESHES`, `DIAG_WATER_BUILD_REASONS`).

Net: this removes substantially more code than it adds.

---

## Target architecture

### Water is a TYPE block

- Water already exists as material id **5** in `VoxelMaterialRegistry`
  (`stone(1)…water(5)…`). The generator currently does *not* use it; it
  writes a `CHANNEL_DATA5` byte instead. **Change: the generator writes
  TYPE id 5 into `CHANNEL_TYPE`** for below-sea-level voxels, at **all
  LODs** (not LOD0-only) — so distant ocean meshes with terrain and the
  horizon plane is unnecessary.
- `VoxelBlockyLibrary` model #5 becomes a **transparent cube model**
  (`transparency_index` set, the same mechanism `leaves` already uses at
  `blocky_library.tres` line 22) with its `material_override` set to the
  v8 water shader material. Re-applied at runtime in
  `World3DBootstrap._inject_atlas_materials_into_library` (the `.tres`
  is a build artifact per the CLAUDE.md Zylann rule — bootstrap is
  source of truth).
- `VoxelMesherBlocky` already emits transparent models into a separate
  surface; no engine change needed. This is a supported Zylann pattern.

### Flow metadata (level / source) — recommended approach

Minecraft keeps flow level in block state. We have two clean options:

- **A (recommended for v1): source-only water as type-5; keep a SPARSE
  DATA5 level channel ONLY for actively-flowing cells near the player.**
  Static ocean/lakes = plain type-5 blocks (render everywhere via the
  terrain mesher, zero sim cost — exactly like MC, where ocean is just
  water blocks, not ticked). The flow sim places/removes type-5 blocks
  for rivers/bucket/dig-flood and uses DATA5 *only* for the transient
  partial levels of cells it is actively spreading. Smallest change,
  keeps rivers/scoop/flood, deletes the rendering split.
- **B (later, more MC-exact): partial-height water as extra blocky
  models** (water_l7…water_l1 as their own model ids with shorter cube
  geometry). Prettier flowing water; costs ~7 material ids and more
  generator/sim/library work. Defer to a polish pass.

v1 ships with **A**.

### Player/gameplay queries

`WaterFlowManager.is_position_in_water` / `get_water_level_at` /
`get_flow_velocity_at` (used by `Player3D._update_water_state`,
swimming, `UnderwaterFilter`) switch from reading a DATA5 byte to
reading `CHANNEL_TYPE == 5` (+ the sparse DATA5 level where present).
Public API signatures stay the same → Player3D, swimming, underwater
filter need no changes beyond what the manager returns.

---

## Per-area change list

| Area | Change |
|---|---|
| `extensions/voxel_gen/src/heightmap_generator_base.cpp` | Below-sea-level columns: write `TYPE=5` into `CHANNEL_TYPE` at **all LODs** instead of `WATER_SOURCE_BYTE` into DATA5 at LOD0. NoEditZone water-suppression snapshot logic unchanged. Rebuild the GDExtension. |
| `assets/voxels/blocky_library.tres` + `World3DBootstrap._inject_atlas_materials_into_library` | Model #5 = transparent cube, `material_override` = water shader material. Re-applied at runtime. |
| `assets/shaders/water.gdshader` / `water_material.tres` | Keep. Becomes the water block material. Drop the now-unused `screen`/horizon-era uniforms if any; verify it renders correctly as a blocky-model surface (normals/UVs come from the blocky mesher, not our hand-built quads). |
| `scripts/WaterFlowManager.gd` | Flow tick reworked: operate on `CHANNEL_TYPE==5` blocks (+ sparse DATA5 levels for active cells). `is_position_in_water` / `get_water_level_at` / `get_flow_velocity_at` read TYPE. Delete horizon-plane Y plumbing. Keep `water_changed` / sea-level API. |
| `scripts/VoxelEditManager.gd` | `queue_set_water_voxel`/`_box` write TYPE=5 (bucket place / dig-flood / authored ponds). Scoop = set TYPE back to air. `water_changed_at` still fires. The `is_area_editable` retry path stays (it's an edit-timing safeguard, unrelated to the deleted mesher). |
| `scripts/WaterChunkMesher.gd`, `water_chunk_mesher.{h,cpp}`, `water_horizon*.{gdshader,tres}` | **Deleted.** Remove the autoload child + C++ class registration in `register_types.cpp`. |
| `World3DBootstrap.gd` | Remove horizon-plane config + test-pond-via-WaterChunkMesher; test pond becomes a `queue_set_water_box` of TYPE=5. |
| Save format | `WORLD_GENERATOR_VERSION` bump. Pre-bump saves: DATA5 ocean has no TYPE equivalent → **hard-reject at load** (same policy used for the v14 refactor). Document in `SAVE_SYSTEM.md`. |
| Docs | Rewrite `SWIMMING_AND_WATER.md` "Voxel Water Architecture" to the type-block model; mark `WATER_SHADER_V2_PLAN.md` superseded; update CLAUDE.md autoload list (WaterChunkMesher gone) + the DATA5 critical-pattern note. |

---

## Staged rollout (each stage independently runnable/shippable)

1. **Blocky water model + shader as material (no gameplay change).**
   Make model #5 a transparent cube wearing the water shader. Hand-place
   a small block of TYPE=5 (debug) and confirm the terrain mesher draws
   it with depth-fade transparency, no separate system. *Acceptance:* a
   placed water cube reads as proper water; FPS unchanged. This proves
   the renderer half before touching the generator.
2. **Generator emits TYPE=5 at all LODs.** Flip the C++ generator;
   rebuild extension. *Acceptance:* walk the world — basins are full of
   water to the horizon with correct depth-fade, no seam, no horizon
   plane, fast load. (Static water only; no flow yet.)
3. **Delete the old systems.** Remove `WaterChunkMesher`, horizon
   shader/material, C++ water mesher, diagnostic flags, autoload wiring.
   *Acceptance:* world looks the same as stage 2; less code, no
   regressions.
4. **Flow sim on type-blocks.** Rework `WaterFlowManager` decay/drop/
   spread to place/remove TYPE=5 (+ sparse DATA5 levels). *Acceptance:*
   dig a trench beside a lake → it floods; bucket scoop removes a source
   and places it elsewhere; river headwater spreads downhill.
5. **Player/swim/underwater requery + save bump + docs.** Point queries
   at TYPE, bump generator version, hard-reject old saves, rewrite the
   canonical doc. *Acceptance:* swim/wade/underwater filter all behave;
   fresh world loads clean; docs accurate.
6. **(Optional, later) Partial-height flowing water models** (approach B)
   for prettier rivers. Not required to ship.

Stages 1–3 deliver the headline win (correct, fast, seamless water)
with **no gameplay regression risk** because flow is untouched until
stage 4 and static ocean needs no sim.

## Risks / open questions

- **Blocky transparent-surface sort order** vs. the player being
  submerged (looking out through water from inside). MC handles this;
  Zylann's transparent surface should too — verify in stage 1, this is
  the main technical unknown.
- **Greedy meshing of huge flat oceans** — Zylann's blocky mesher
  performance on large uniform water expanses. Expected fine (it's the
  same mesher already handling huge uniform terrain), confirm in stage 2
  with a profiler capture.
- **256 type-id budget** — water=5 already reserved; approach A spends
  no extra ids. Approach B (later) would spend ~7.
- **Underwater fog / `UnderwaterFilter`** still works on a type read;
  the deferred "real underwater volumetric" remains a separate later
  item, not blocked by this.

## References

- `design/SWIMMING_AND_WATER.md` — current architecture (to be rewritten).
- `scripts/WaterByteCodec.gd` — level/source/tick concepts carried forward.
- `extensions/voxel_gen/src/heightmap_generator_base.cpp` — water emission rule (`write_water`, `emit_water_here`).
- `assets/voxels/blocky_library.tres` — `transparency_index` precedent (leaves).
- `scripts/World3DBootstrap.gd` `_inject_atlas_materials_into_library` — runtime model/material re-apply (Zylann `.tres`-is-a-build-artifact rule, CLAUDE.md).
- `assets/shaders/water.gdshader` v8 — kept as the water block material.
- Minecraft model: water = block + 0–7 level state, drawn in the chunk's translucent render layer; ocean = static water blocks (not ticked).
