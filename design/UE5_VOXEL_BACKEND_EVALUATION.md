# UE5 Voxel Backend Evaluation (cubic spike)

**Status:** SPIKE COMPLETE — decision record. **Outcome realized:** we built the custom cubic mesher on
our Core, and as of **2026-06-16** it has shipped **M0/M1/M2** (foundations → first chunk under Lumen →
brickmap + generation + dig loop). Triggered because the originally-chosen Voxel Plugin Pro turned out
**not to support cubic terrain** (see below). Designer constraint reaffirmed: **true blocky 10cm cubes
are core visual identity, non-negotiable.** Companion to `UE5_TECH_STACK.md` (canonical stack) and
`UE5_VOXEL_MESHER_PLAN.md` (the build plan this spike fed into).

> **Texturing note (2026-06-16):** requirement #7 below ("per-voxel materials via a triplanar atlas")
> is **superseded** — the shipped surface is **per-face solid color** baked into vertex color (no atlas;
> see `UE5_RENDERING_STRATEGY.md`). It doesn't change the verdict: the custom mesher is still the only
> backend that meets the bar, and per-face color is *easier* than atlas UVs, not harder.

## Why this spike happened

The port plan assumed "Voxel Plugin Pro cubic mesher." Verification against the official docs found
that **Voxel Plugin 2 (the current Pro product) explicitly does not support cubic terrain** — and the
cubic + MagicaVoxel workflows that existed in Voxel Plugin 1 were **removed** in the v2 rewrite. VP2 is
a smooth/SDF, Nanite-targeted terrain toolkit. That invalidates it as our primary backend, so we
evaluated the actual cubic options for UE5.

## Requirements bar (what "everything we need" means here)

1. **True blocky cubes** at **10cm** voxels.
2. **Skyrim-scale** streamed world (sparse, persistent edits).
3. **Runtime destructible editing** (mining/explosions) at interactive frame rates.
4. **Collision** (Chaos) on the near band.
5. **Server-authoritative multiplayer** edits (co-op 1–4).
6. **Nanite/Lumen**-compatible rendering (standard meshes are fine).
7. **Per-voxel materials** via a triplanar atlas (per-face UVs not required).
8. **Actively maintained** on UE 5.4+ (this is a multi-year trilogy).
9. Can **consume our engine-agnostic `Core/`** (generation, edit routing, water, gravity, mining).

## Candidates

| Option | Cubic? | Scale/stream | Destruct edit | Collision | Multiplayer | Nanite/Lumen | Maintained | Verdict |
|---|---|---|---|---|---|---|---|---|
| **Voxel Plugin 2 (Pro)** | ❌ **no cubic** (removed in v2) | ✅ | ✅ | ✅ (invokers) | ✅ server-auth (RPC / Pro TCP) | ✅ Nanite-first | ✅ active, $349 | **Rejected** — wrong aesthetic |
| **Easy Voxels: Cubic** | ✅ cubic, greedy mesh, LOD, culling | ~ chunked, no stated limits | ✅ (density data) | ❓ not documented | ❓ none documented | ❓ not mentioned | ❌ **last update 2021**, UE5 unconfirmed | **Reference only** — meshing helper, stale, no collision/MP |
| **VoxelWeaver / "Infinite Voxel Terrain"** | ❌ smooth (marching cubes) | ✅ infinite, GPU | ✅ GPU destruction | ✅ | ✅ | ✅ Lumen/Nanite | ✅ new (2025) | **Rejected** — smooth, not cubic |
| **CubicVoxels (3lioss, OSS)** | ✅ block-based infinite | ~ early | ~ basic | ❓ | ❌ | ❓ | ⚠️ hobby/early, MIT-ish | **Reference only** — not production-grade |
| **Voxel Plugin 1 (legacy)** | ✅ had a cubic mode | ✅ | ✅ | ✅ | ⚠️ limited | ⚠️ pre-Nanite | ❌ **deprecated** | **Rejected** — dead-ended branch |
| **Custom cubic mesher on our `Core/`** | ✅ exactly our spec | ✅ (we own streaming) | ✅ (our edit subsystem) | ✅ (standard mesh → Chaos) | ✅ (UE replication, our design) | ✅ (standard meshes) | ✅ we maintain it | **RECOMMENDED** |

## Finding

**The cubic UE5 plugin market is thin and does not meet our bar.** The only dedicated cubic marketplace
plugin (Easy Voxels: Cubic) is a *meshing helper* — it lacks the two hardest pieces (collision,
multiplayer) and hasn't been updated since 2021. The mature, GPU-accelerated, infinite-world plugins
(VoxelWeaver, Infinite Voxel Terrain, Voxel Plugin 2) are all **smooth/marching-cubes**, not cubic. The
open-source cubic projects are hobby-grade references. The one cubic plugin we'd have leaned on (VP1)
is deprecated.

**There is no off-the-shelf cubic backend that gives us 10cm + Skyrim-scale + destructible + collision
+ multiplayer + Nanite/Lumen + active maintenance.** Owning the mesher is therefore not a preference —
it's the only path that satisfies the locked aesthetic.

## Recommendation: custom cubic mesher on our Core

Build a **cubic greedy mesher module** in UE5 C++ that consumes the engine-agnostic `Core/` we already
have. This is a *bounded* addition, not a from-scratch engine, because the hard half is done and
harness-locked:

- **Already built & verified (`Core/`, 8,955 clang checks):** generation/biome, edit routing contract,
  finite water sim, gravity/sever, mining carve, material ids, scale. These are backend-independent.
- **What the custom mesher adds:** (1) a **greedy meshing** pass (chunk of material ids → quad list)
  — *pure logic, so it's clang-testable in our headless harness like everything else*; (2) UE glue
  that uploads those quads as a `UProceduralMeshComponent`/`URealtimeMesh` (or a custom Nanite-cold
  bake), builds Chaos collision, and streams chunks via World Partition; (3) the rendering bands from
  `UE5_RENDERING_STRATEGY.md` (hot dynamic mesh / cold Nanite / far ray-march).
- **References (algorithm only, not dependencies):** Easy Voxels: Cubic and 3lioss/CubicVoxels for
  greedy-meshing/chunking patterns; well-trodden ground.

This keeps every UE5 feature we migrated for (Lumen/Nanite/Chaos/replication via standard meshes) and
makes the renderer swappable behind the brickmap (`UE5_RENDERING_STRATEGY.md`), exactly as planned.

## Impact on the plan

- **Voxel Plugin Pro dependency is dropped.** The `.uproject` "Voxel" plugin + the `MiraThalVoxel`
  Build.cs "Voxel" line are removed/avoided; a `MiraThalVoxel`-owned cubic mesher replaces them.
- Phase 0 step 3 changes from "install Voxel Plugin Pro" to "stand up the custom cubic mesher + chunk
  streaming"; the dig-under-Lumen perf gate (step 6) is unchanged in intent — it now measures *our*
  mesher instead of the plugin's.
- **No Core rework.** The 11 ported systems stand as-is. The greedy mesher is the next clang-verifiable
  Core addition.

## Sources

- Voxel Plugin docs — cubic not supported: https://docs.voxelplugin.com/getting-started/working-with-voxel-plugin/
- Voxel Plugin licensing/positioning: https://docs.voxelplugin.com/resources/licensing
- Voxel Plugin multiplayer (server-authoritative, RPC/TCP): https://docs.voxelplugin.com/knowledgebase/blueprints/multiplayer-support
- Easy Voxels: Cubic (marketplace + forum, 2021): https://www.unrealengine.com/marketplace/en-US/product/easy-voxels-cubic and https://forums.unrealengine.com/t/easy-voxels-cubic/136703
- CubicVoxels (OSS): https://github.com/3lioss/CubicVoxels
- VoxelWeaver (GPU, smooth, 2025): https://forums.unrealengine.com/t/voxelweaver-a-voxel-plugin-for-gpu-accelerated-biomes-caves-and-infinite-worlds/2277063
