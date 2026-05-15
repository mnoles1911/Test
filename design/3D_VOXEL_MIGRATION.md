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

Game One switched from `CharacterBody2D` + `Camera2D` + 2D scene tiles to `CharacterBody3D` + `SpringArm3D` over-shoulder + `VoxelLodTerrain` (Zylann's Voxel Tools, GDExtension edition) at 6 voxels/m, with destructible terrain by default (edits stored as deltas in `VoxelStreamSQLite`), `NoEditZone` Area3Ds protecting settlements/landmarks, MagicaVoxel-authored props (`.glb`), low-poly Blender characters (200–500 tris), and a real-time 1-vs-many action combat system. Dialogic 2 + GameState + TransitionManager survived the pivot unchanged.

Voxel scale is locked at **6 voxels/m** (~16.7 cm/block). Playable Mira is 12 km × 10 km (compression 125:1). Sea level is Y=125.

## Destructible terrain — short version

- **Mesher:** `VoxelMesherBlocky` reading `CHANNEL_TYPE` (8-bit material id), backed by `VoxelBlockyLibrary` (per-cube atlas tiles + alpha-scissor `StandardMaterial3D`).
- **Generator:** `CubicHeightmapGeneratorCpp` (C++ GDExtension) via `CubicHeightmapGeneratorAdapter.gd`.
- **Stream:** `VoxelStreamSQLite` — per-save-slot delta DB.
- **Edit routing:** every voxel write goes through `VoxelEditManager.queue_*` (NoEditZone gate + async queue + EditedChunkRegistry + LOD-bake invalidation + `edit_applied` signal + MP-3 RPC routing). **Never call raw `VoxelTool` directly.**
- **Water:** `WaterFlowManager` (host-only 4 Hz sim) + `WaterChunkMesher` (C++ since PR #214, transparent surface meshes) reading `CHANNEL_DATA5` water bytes via `WaterByteCodec`.

Full details in `CLAUDE.md` → "Voxel + world systems" and `design/TECH_STACK.md` → "Voxel Terrain".
