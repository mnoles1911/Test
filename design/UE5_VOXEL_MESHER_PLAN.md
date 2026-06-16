# UE5 Custom Cubic Voxel Plugin — Build Plan

**Status:** APPROVED, **in progress — M0 ✅, M1 ✅, M2 ✅ (built 2026-06-16).** Companion to
`UE5_TECH_STACK.md` (the canonical stack overview), `UE5_PORT_PLAN.md`, `UE5_RENDERING_STRATEGY.md`,
`UE5_VOXEL_BACKEND_EVALUATION.md`. This is the execution plan for the custom mesher/rendering/streaming
plugin we own (no third-party voxel backend — Voxel Plugin 2 dropped cubic; see the evaluation doc).

> **Status note (2026-06-16):** the foundation is real, not just planned. **M0** (mesher foundations),
> **M1** (AO/LOD/seams + first chunk rendered under Lumen, perf baseline ≈ 6.4 ms GPU on a 7800 XT in an
> empty Lumen scene), and **M2** (brickmap + generation + the dig/carve loop, with multi-chunk generated
> terrain and Chaos collision) are **built**. M3 (water/flora/gravity) is next. The headless gate is the
> standalone clang Core harness — **"ALL HARNESSES GREEN"** in `ue5/MiraThal/tests/standalone/build.sh`.
>
> **Texturing changed since this plan was written:** the "AtlasUV" / texture-atlas approach below is
> **superseded** by **per-face solid color baked into vertex color** (top-brightest..bottom-darkest
> directional shade × per-material base color from `Core/VoxelColor.h`; AO in vertex alpha; UE material
> `M_VoxelTerrain` = VertexColor→BaseColor). See `UE5_RENDERING_STRATEGY.md` and `UE5_TECH_STACK.md` §6.
> `AtlasUV`/`atlas` below is retained only as the historical plan; the shipped path needs no atlas.

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
GPU mirror. Mesh chunk = 32³ *view* (4³ bricks + 1-voxel apron) — built as M2's `AVoxelWorld`/
`BrickmapMeshing` path, where `BrickmapMeshing` computes the edit-affected chunks so only those re-mesh.
LWC: `ChunkCoords` splits world pos into int32 voxel index + double tile origin. Persistence:
baseline-from-seed + delta log. **Texturing:** no atlas — the mesher bakes a **per-face solid color**
(`VoxelColor` = per-material base × per-direction shade) into vertex color, AO into vertex alpha.

## Rendering bands

HOT (near+edited): dynamic greedy mesh via RMC, LOD0–2, Chaos, Lumen. COLD (near, unedited): offline
Nanite static mesh, reverts to HOT on edit. FAR: ray-marched from brickmap, toggleable behind the
brickmap so Baseline (mesh+Lumen) ships the slice.

## New Core files (clang-verifiable; each ships `test_<name>.cpp` + selector)

In `MiraThalVoxel/Public/Core/` (+ `Private/Core/`), reading the authorities (`VoxelScale.h`,
`MaterialIds.h`, `WaterByteCodec.h`, `HeightmapGenerator.h`), never re-hardcoding:

`ChunkCoords` (`chunkcoords`), `VoxelChunk` (via `mesher`), `MeshTypes` (face classes/dirs/buffers),
`GreedyMesher` (`mesher`), `VoxelAO` (`ao`), `VoxelColor` (per-face solid color — replaces `AtlasUV`), `LodDownsample` (`lod`),
`WaterSurfaceMesher` (`watersurf`), `FloraMesher` (`flora`), `Brickmap` (`brickmap`),
`RegionFormat` (`region`), `BandPolicy` (`bands`), `MeshBudget` (`meshbudget`), `NetVoxelCodec` (`netvoxel`).

UE glue (no Core): `UVoxelWorldSubsystem`, `AVoxelChunkActor`, `IVoxelMeshSink`/`FRealtimeMeshSink`,
`FVoxelMeshJobPool`, `UVoxelBrickmapGPUMirror`, `FVoxelRegionStore`, render/bake module classes.

## Milestones

`[H]` clang here · `[B]` UE build machine · `[OSS]` lib lands.

- **M0 ✅** Core meshing foundations: `ChunkCoords`, `VoxelChunk`, `MeshTypes`, ~~`AtlasUV`~~ **per-face `VoxelColor`**, `GreedyMesher`. `chunkcoords`/`mesher` (color baked in mesher). `[OSS]` binary-greedy-meshing. *(Atlas dropped → per-face solid color, see header note.)*
- **M1 ✅** AO + LOD + seams + first render: `VoxelAO`, `LodDownsample`, skirts; `AVoxelChunkActor` (ProceduralMeshComponent for now; `FRealtimeMeshSink` planned). `ao`/`lod`/`seams`. `[B]` **chunk rendered under Lumen — perf Baseline ≈ 6.4 ms GPU (7800 XT, empty Lumen scene).** `[OSS]` RealtimeMeshComponent.
- **M2 ✅** Brickmap + generation + carve loop: `Brickmap`, generator wire (`HeightmapGenerator`), `BrickmapMeshing` edit-affected-chunk compute, `AVoxelWorld` manager, `CarveAtWorld`/`CarveTestHole` → re-mesh → Chaos. `brickmap`/`meshbudget`. `[B]` **dig-under-Lumen built: multi-chunk generated terrain + live dig.** `[OSS]` FastNoiseLite.
- **M3 ⏳** Water + flora + gravity: `WaterSurfaceMesher`, `FloraMesher`; wire `FiniteWaterCore`+`VoxelGravity`. `watersurf`/`flora`. `[B]` water shader, flora alpha-scissor. *(next milestone)*
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
