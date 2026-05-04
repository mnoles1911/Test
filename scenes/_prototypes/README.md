# Prototypes

Throwaway scenes / scripts used to validate risky assumptions before building production code. Safe to delete after the relevant validation is complete.

## water_phase0.tscn

Validates two assumptions before the voxel water refactor (Phase 1+):

1. **Wave shader phase continuity across multiple meshes.** The scene is a 4×4 grid of independent `PlaneMesh` instances at 5 m spacing, all sharing `assets/shaders/water_material.tres`. Open the scene and run. Walk the camera around the grid. Look at the seams between tiles — wave crests should pass through without visible discontinuity. The shader at `assets/shaders/water.gdshader` uses `world_pos = MODEL_MATRIX * vec4(VERTEX, 1.0)` (lines 34–37) which puts the wave domain in world space — phase should hold. This scene proves it empirically.

   **What to look for:**
   - Pass: crests appear continuous across mesh boundaries; you cannot tell where one tile ends and the next begins.
   - Fail: visible seams or "waves restart" lines along tile boundaries.
   - Fail action: WaterChunkMesher in Phase 2 must emit one large mesh per voxel chunk (16 m × 16 m) instead of per-cell quads. Cap face count by collapsing adjacent same-level cells.

2. **Bulk `VoxelTool.get_voxel` cost at the design tick rate.** The scene's root node runs `scripts/_prototypes/water_phase0_bulk_read_test.gd`, which performs 30,000 random `get_voxel` reads every 15 physics frames (~4 Hz) and prints rolling averages to the Output panel.

   **Note:** for this measurement to be meaningful, you need a loaded VoxelLodTerrain. The simplest path is to run `World3D.tscn` first to build the disk cache, then drop `WaterPhase0` as a child node of that scene (or instance the prototype scene from `World3D.tscn`'s root and disable the camera). If the test runs in `water_phase0.tscn` standalone with no VoxelEditManager autoload, the script will print "no ticks run yet" and report no cost — that's expected.

   **What to look for:**
   - Pass: avg under 2 ms per tick.
   - Fail: anything over 4 ms — Phase 1 must add a per-chunk packed-cache that mirrors the dirty water cells once per tick instead of re-reading from VoxelTool.
   - Fail action: add a `_chunk_voxel_cache: Dictionary` to WaterFlowManager that snapshots a chunk's voxel-below state on first dirty mark, invalidated by `edit_applied` for that chunk.

## After validation

Capture the pass/fail outcomes and any measured numbers in `design/LESSONS_LEARNED.md` under a "Phase 0 — voxel water bring-up" subsection. Once both checks pass, delete this directory and the matching `scripts/_prototypes/` directory.
