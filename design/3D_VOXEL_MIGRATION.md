# 3D Voxel Migration — Historical Pivot Plan

**Status:** migration complete (2026-04-30 → 2026-05-03). This file was the original pivot plan from 2D pixel art to 3D voxel. It is retained as a redirect because ~13 other design docs link to it as canonical reference for terrain / voxel / destructible-terrain rules.

**Current canonical sources:**
- **`CLAUDE.md`** — single source of truth for live systems, autoloads, scene hierarchies, critical patterns, and load-order rules.
- **`design/TECH_STACK.md`** — every tool, plugin, and pipeline in use; the voxel terrain section is the canonical mesher / generator / stream / format description.
- **`design/SYSTEMS_DESIGN.md`** — gameplay system overview.
- **`design/COPPER_ISLES_BAKE_NOTES.md`** — Zylann GDExtension probe results, bake-pipeline design decisions and gotchas.
- **`design/LESSONS_LEARNED.md`** — running log of bugs and fixes encountered during and after the pivot.

If a design doc still says "see `design/3D_VOXEL_MIGRATION.md` for canonical terrain spec," update it to point at the relevant canonical source above when you next touch that doc.

## Pivot summary (one-paragraph)

Game One switched from `CharacterBody2D` + `Camera2D` + 2D scene tiles to `CharacterBody3D` + `SpringArm3D` over-shoulder + `VoxelLodTerrain` (Zylann's Voxel Tools, GDExtension edition) at 10 voxels/m, with destructible terrain by default (edits stored as deltas in `VoxelStreamSQLite`), `NoEditZone` Area3Ds protecting settlements/landmarks, MagicaVoxel-authored props (`.glb`), low-poly Blender characters (200–500 tris), and a real-time 1-vs-many action combat system. Dialogic 2 + GameState + TransitionManager survived the pivot unchanged.

Voxel scale is **10 voxels/m** (10 cm/block) since 2026-06-12 — the Lay-of-the-Land re-architecture (`VISION_VOXEL_10CM.md`; was 6 voxels/m from the original pivot until then; the authority is `scripts/VoxelScale.gd`). Playable Mira is 12 km × 10 km (compression 125:1). Sea level is Y=125.

> **10 vox/m collision reality:** Zylann caps `lod_distance` at 128 voxels per LOD shell (12.8 m/shell at 10 vox/m; was 21.3 m at 6 vox/m). **Terrain collision extends to ~51.2 m** via `collision_lod_count = 3` (LOD0+LOD1+LOD2; set in `World3DBootstrap.gd`, 2026-06-12 designer decision). Beyond LOD0 the collision shapes are coarser (LOD1 = 2-voxel blocks, LOD2 = 4-voxel blocks). Nothing beyond ~51.2 m: projectiles/AI past that ring still have no terrain collision; long-lived projectile raycast-vs-generator fallback is a logged follow-up, not yet built.

## Destructible terrain — short version

- **Mesher:** `VoxelMesherBlocky` reading `CHANNEL_TYPE` (8-bit material id), backed by `VoxelBlockyLibrary` (per-cube atlas tiles + alpha-scissor `StandardMaterial3D`).
- **Generator:** `CubicHeightmapGeneratorCpp` (C++ GDExtension) via `CubicHeightmapGeneratorAdapter.gd`.
- **Stream:** `VoxelStreamSQLite` — per-save-slot delta DB.
- **Edit routing:** every voxel write goes through `VoxelEditManager.queue_*` (NoEditZone gate + async queue + EditedChunkRegistry + LOD-bake invalidation + `edit_applied` signal + MP-3 RPC routing). **Never call raw `VoxelTool` directly.**
- **Water:** `WaterFlowManager` (host-only 4 Hz sim) + `WaterChunkMesher` (C++ since PR #214, transparent surface meshes) reading `CHANNEL_DATA5` water bytes via `WaterByteCodec`.

Full details in `CLAUDE.md` → "Voxel + world systems" and `design/TECH_STACK.md` → "Voxel Terrain".


## Tree-sever follow-up (PR 6, 2026-06-10)

Severed clusters that touch the gravity analysis bubble's roof now
FOLLOW the connected solids upward (footprint+2 box,
`sever_follow_max_height_m` = 12 m cap) so a chopped tree detaches as
ONE falling cluster instead of bubble-height salami slices. Pure BFS in
`scripts/_dev/SeverFollowLib.gd` (headless `sever` selector).
Conservative aborts keep the old behaviour: extension touches the box
side walls (possible anchored arch), exceeds the height cap, or blows
`max_cluster_voxels`. Water never rides a cluster. Known pre-existing
mismatch (recorded, unchanged): leaves with `fall_behavior = NEVER`
still cluster via the partition comment at VoxelGravityManager.gd:533.
