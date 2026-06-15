# UE5 Custom Cubic Voxel Plugin — Build Plan

**Status:** APPROVED, in progress. Companion to `UE5_PORT_PLAN.md`, `UE5_RENDERING_STRATEGY.md`,
`UE5_VOXEL_BACKEND_EVALUATION.md`. This is the execution plan for the custom mesher/rendering/streaming
plugin we own (no third-party voxel backend — Voxel Plugin 2 dropped cubic; see the evaluation doc).

## Why custom

True blocky 10cm cubes are core visual identity, and no off-the-shelf cubic UE backend meets our bar
(10cm + Skyrim-scale + destructible + collision + multiplayer + Nanite/Lumen + maintained). The
load-bearing math is already done and harness-locked in the engine-agnostic `Core/` (11 systems, 8,955
clang checks). The plugin = **our Core + a few MIT building blocks + UE glue + our LOD/streaming/render-band
orchestration**.

## Locked decisions

- Mesh backend: **RealtimeMeshComponent (MIT)** behind our `IVoxelMeshSink` interface (swappable to a
  custom `FPrimitiveSceneProxy` later without touching the mesher).
- Streaming: **World Partition + data layers** (coarse) with our **sparse brickmap** paging near/edited bricks.
- Pure-logic-first: every voxel-shaped algorithm becomes a Core function with a harness selector; UE
  glue is the thin, build-machine-only boundary.

## MIT borrows (adapt/ship, legally clean)

- `binary-greedy-meshing` (cgerikj) → `Core/GreedyMesher`.
- `FastNoiseLite` (Auburn) → vendor into `Core/` (same lib Godot uses → fixes our noise divergence).
- `Zylann godot_voxel` → blocky-mesher/LOD/AO/region-streaming **algorithms** as reference (adapt, not copy).
- `RealtimeMeshComponent` (TriAxis) → dynamic chunk upload + async Chaos collision + LODs.
- `meshoptimizer` (zeux) → LOD simplification for the offline Nanite bake.

## Hard constraints

Nanite is offline-static only (dynamic world uses RMC + our LOD; Nanite reserved for offline-baked cold
chunks + static set-dressing). Skyrim-scale 10cm needs Large World Coordinates + tile-local origins
(float dies past ~1km; voxel indices stay int32 absolute). Multiplayer is server-authoritative.

## Modules

- `MiraThalVoxel` (existing) — voxel data, meshing Core, streaming, RMC glue (+`RealtimeMeshComponent`, `Chaos`).
- `MiraThalVoxelRender` (new, render-thread) — far-field ray-march `FSceneViewExtension`/RDG, GPU brickmap mirror, water material params.
- `MiraThalVoxelBake` (new, editor/commandlet) — cold→Nanite baker, offline far-base bake, `meshoptimizer`.
- `MiraThalCore` (gameplay), `MiraThalNet` (gains voxel edit-command + chunk-sync replication).

## Data model — brickmap is the single CPU truth

`type` uint8 = `MaterialIds` value (0=air); `water` uint8 = `WaterByteCodec`. `Brickmap` = sparse hash
of 8³ bricks, mutated by edits + `FiniteWaterCore` + `VoxelGravity`; shared by sim, collision, mesher,
GPU mirror. Mesh chunk = 32³ *view* (4³ bricks + 1-voxel apron). LWC: `ChunkCoords` splits world pos
into int32 voxel index + double tile origin. Persistence: baseline-from-seed + delta log.

## Rendering bands

HOT (near+edited): dynamic greedy mesh via RMC, LOD0–2, Chaos, Lumen. COLD (near, unedited): offline
Nanite static mesh, reverts to HOT on edit. FAR: ray-marched from brickmap, toggleable behind the
brickmap so Baseline (mesh+Lumen) ships the slice.

## New Core files (clang-verifiable; each ships `test_<name>.cpp` + selector)

In `MiraThalVoxel/Public/Core/` (+ `Private/Core/`), reading the authorities (`VoxelScale.h`,
`MaterialIds.h`, `WaterByteCodec.h`, `HeightmapGenerator.h`), never re-hardcoding:

`ChunkCoords` (`chunkcoords`), `VoxelChunk` (via `mesher`), `MeshTypes` (face classes/dirs/buffers),
`GreedyMesher` (`mesher`), `VoxelAO` (`ao`), `AtlasUV` (`atlas`), `LodDownsample` (`lod`),
`WaterSurfaceMesher` (`watersurf`), `FloraMesher` (`flora`), `Brickmap` (`brickmap`),
`RegionFormat` (`region`), `BandPolicy` (`bands`), `MeshBudget` (`meshbudget`), `NetVoxelCodec` (`netvoxel`).

UE glue (no Core): `UVoxelWorldSubsystem`, `AVoxelChunkActor`, `IVoxelMeshSink`/`FRealtimeMeshSink`,
`FVoxelMeshJobPool`, `UVoxelBrickmapGPUMirror`, `FVoxelRegionStore`, render/bake module classes.

## Milestones

`[H]` clang here · `[B]` UE build machine · `[OSS]` lib lands.

- **M0** Core meshing foundations: `ChunkCoords`, `VoxelChunk`, `MeshTypes`, `AtlasUV`, `GreedyMesher` (no AO). `chunkcoords`/`atlas`/`mesher`. `[OSS]` binary-greedy-meshing.
- **M1** AO + LOD + seams + first render: `VoxelAO`, `LodDownsample`, skirts; `FRealtimeMeshSink` + `AVoxelChunkActor`. `ao`/`lod`/`seams`. `[B]` chunk under Lumen = perf Baseline. `[OSS]` RealtimeMeshComponent.
- **M2** Brickmap + generation + carve loop: `Brickmap`, generator wire, `OnEditsApplied`→re-mesh, Chaos. `brickmap`/`meshbudget`. `[B]` dig-under-Lumen; perf gate. `[OSS]` FastNoiseLite.
- **M3** Water + flora + gravity: `WaterSurfaceMesher`, `FloraMesher`; wire `FiniteWaterCore`+`VoxelGravity`. `watersurf`/`flora`. `[B]` water shader, flora alpha-scissor.
- **M4** Streaming + persistence: `RegionFormat`, `BandPolicy`; World Partition + tile-local origins. `region`/`bands` + LWC tests. `[B]` World Partition, rebase soak.
- **M5** Multiplayer: `NetVoxelCodec`; server-authoritative, edit RPC + multicast, join-in-progress. `netvoxel`. `[B]` replication + late-join.
- **M6** Cold→Nanite bake: `MiraThalVoxelBake` + `meshoptimizer`. `[B]` perf spike B. `[OSS]` meshoptimizer.
- **M7** Far-field ray-march: `MiraThalVoxelRender`, GPU mirror, DDA HLSL (oracle = `Brickmap`). `brickmap_dda`. `[B]` perf spike C + voxel-AO spike D.
- **M8** GPU meshing + generation: compute re-mesh + world-gen. `gpu_mesh_oracle`/`gpu_gen_oracle`. `[B]` perf spike A + readback parity.

## Verification

1. Clang harness (`tests/standalone/build.sh`) — each Core selector green before "done"; a micro-gate
   asserts per-chunk quad/geometry budgets so perf regressions surface before the build machine.
2. UE PIE per milestone exit (build machine): M1 chunk renders; M2 dig loop; M3 water conserves; M5 co-op late-join.
3. Unreal Insights perf gate vs `UE5_RENDERING_STRATEGY.md` tiers + the canonical worst case (blow a hole
   under a lake mid-fight). Gate at M2, re-gate after M6/M7/M8.
