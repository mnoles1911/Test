# UE5 Nanite Crust — verification, perf diagnosis, and the 2026-06-20 build

Single-session handoff doc. Covers: the Nanite crust verified rendering for the first time, the
perf diagnosis from the profiler/logs, the four code changes built on top, and the editor-side
steps that remain. Read alongside `design/UE5_WORLD_STREAMING_PLAN.md` and the memory notes
`project_ue5_far_render_systems` / `project_ue5_nanite_bake_plan`.

## 1. Verified state (live PIE + bridge, 2026-06-20)

The P6 Nanite cold-bake **works and renders** — first runtime confirmation:

- Bake produced **289 tiles + `Manifest.uasset`** in `Content/VoxelBake/MiraStreamTest/` (no crash;
  the normals-recompute crash fix from `ccbc3ff` holds).
- In PIE the `AVoxelNaniteCrust` actor placed **285 StaticMeshComponents** (4 innermost tiles
  correctly skipped — covered by live voxels), each bound to its baked `Tile_X_Z` mesh, all visible.
- `bEnableNaniteCrust=true` and the crust **gates super-chunks OFF** at runtime (`superTotal=0` in the
  CSV; was ~1000 on the old path). Manifest wired: `/Game/VoxelBake/MiraStreamTest/Manifest`.

## 2. Perf diagnosis — the bottleneck is NOT the crust

Perf CSV (`Saved/MiraThalPerf.csv`) is **bimodal**:

| State | FPS | Evidence |
|---|---|---|
| Fully loaded, nothing meshing | **68–94** | `inFlightMesh=0, worstLoadMs=0` — all voxels + all 285 Nanite tiles on screen |
| Mesh pipeline active | **2–3** | `inFlightMesh=128, pendMesh=128, worstLoadMs=400` |

`worstLoadMs` (worst whole-frame ms on a loading tick) tracks FPS almost perfectly. Conclusions:

- **Rendering everything (voxels + Nanite) is cheap** — proven at 90 FPS. The crust is not the cost.
- **Live column (re)meshing/applying on the game thread is the cost.** Any streaming churn → 2–3 FPS.
- **The "holes" on movement** are the same root cause: a crust tile released on a blind distance ring
  while the live voxels that replace it take 400 ms+ to mesh → gap for those frames.
- **Collision cooking is already async** (`VoxelChunkActor.cpp:26` `bUseAsyncCooking=true`) — it is NOT
  the stall. Prime remaining suspects for the 400 ms: the 96-upload-per-tick batch (level override of
  `MaxColumnMeshUploadsPerTick`) and the **synchronous disk edit-replay** in `ApplyColumnResult`
  (`ApplyEditsToColumn`), which had no ms budget.
- **The far crust looks SMOOTH, not cubic,** because the bake downsamples to `coarse_side ≤ 32`
  (`stride ≥ 16` = 1.6 m cubes) — a holdover from the super-chunk math, not a Nanite limit.

## 3. What was built (2026-06-20) — all compile + Core harness GREEN + UBT `Result: Succeeded`

**#1 Per-phase loading attribution** (`VoxelWorld.h/.cpp`)
- New windowed timers `WorstGenMsWindow / WorstMeshMsWindow / WorstEvictMsWindow` wrap the gen
  harvest (`HarvestColumnGen`), mesh harvest (`HarvestColumnMesh`), and column eviction in
  `TickStreaming`. Reset with the existing 2 s frame window in `UpdateProfilerFrameWindow`.
- New perf-CSV columns: **`genMs,meshMs,evictMs`**. Next play session attributes the 400 ms exactly.
- Crust counter recovered: `AVoxelNaniteCrust::Tick` logs `[MiraThalCrust] tiles=N pendingLoads=M …`
  at ~1 Hz (the metric the forensics was missing).

**#2 Bound the per-frame streaming stall** (`VoxelWorld.h/.cpp`)
- Added gen-harvest time-slicing: `bTimeSliceGenHarvest` (default ON) + `GenHarvestBudgetMs` (4 ms),
  mirroring the existing mesh-upload slice — bounds the disk edit-replay cost that had no ceiling.
- Note: collision was already async, so the original "move collision off the thread" is moot.

**#3 Cubic-far readiness** (`Core/NaniteBakeTiling.h`)
- Documented the **smooth↔cubic = stride** tradeoff. Added `MAX_COARSE_SIDE = 96` guard so an
  over-fine "cubic" bake can't OOM (refuses the tile, empty slab). Cubic sweet spot: 20–40 cm cubes,
  e.g. `tileSpan 128 @ stride 4` or `tileSpan 64 @ stride 2`. Full 10 cm everywhere = millions of
  assets (not viable as one-uasset-per-tile). Harness tests added (`test_nanitebake.cpp`).

**#4 State-aware handoff — kills the transition holes** (`Core/NaniteBakeTiling.h`, `VoxelWorld.h/.cpp`,
`VoxelNaniteCrust.h/.cpp`)
- New `nanitebake::tile_chunk_bounds(tile, span)` (Core) + `AVoxelWorld::AreCoveredColumnsReady(...)`.
- The crust **won't release a tile until the live columns covering it are meshed** — harmless overlap
  (it's sunk below the surface) instead of a hole. Bounded to columns within the stream radius so a
  tile can't linger forever. Gated by `bHoldTilesUntilVoxelsReady` (default ON).

## 4. Remaining — needs a supervised EDITOR session (cannot be done headless)

1. **Runtime-verify the build.** Open editor → Play → move around. Confirm: holes gone on movement
   (#4); read the new `genMs/meshMs/evictMs` CSV columns to attribute the 400 ms (#1); confirm the
   gen slice reduced the loading-frame stall (#2).
2. **Attack the confirmed phase.** If `meshMs` dominates → lower `MaxColumnMeshUploadsPerTick` (the
   live level overrides it to 96) and/or enforce a harder ms ceiling. If `genMs` dominates → the disk
   edit-replay is the cost; the new gen slice should already help, tune `GenHarvestBudgetMs`.
3. **Cubic re-bake.** Re-run the bake at a low stride / small tile (e.g. tileSpan 128, stride 4) via
   the `VoxelCrustBakeTool` button for cubic far terrain. Then shrink the editable `StreamRadius`
   bubble and extend `NaniteOuterChunks` so the cubic crust covers all distance.
4. **Commit decision** for the bake assets: `Content/VoxelBake/` (≈17 MB of `.uasset`) + the modified
   `MiraStreamTest.umap` — plain git vs LFS (the 268 MB source EXR was gitignored as LFS territory).

## 5. Key file anchors

- Bimodal cost / mesh upload: `VoxelWorld.cpp` `HarvestColumnMesh` (~966), `MiraVoxelMesh.cpp:98`
  (`CreateMeshSection`), collision-for-LOD0 at `VoxelWorld.cpp:1036`.
- Async collision already on: `VoxelChunkActor.cpp:26`.
- Eviction throttle (fights holes): `VoxelWorld.h` `MaxEvictOpsPerTick`.
- Crust streamer ring + release gate: `VoxelNaniteCrust.cpp::Tick`.
- Tiling math + guard: `Core/NaniteBakeTiling.h`.
- Perf CSV writer: `VoxelWorld.cpp` `WritePerfCsvRow` (~3361).
