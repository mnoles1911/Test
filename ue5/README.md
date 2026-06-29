# Mira-Thal — Unreal Engine 5 port

UE5 port of the Godot 3D voxel narrative RPG. See `../design/UE5_PORT_PLAN.md` for the full
strategy, phasing, and Godot→UE5 system mapping. This README is the practical "how the code is laid
out and how to build/test it" guide.

## The core idea: an engine-agnostic core + a thin UE wrapper

The load-bearing voxel math (water sim, gravity flood-fill, terrain generation, scale) is ported
from the Godot build into **`Source/MiraThalVoxel/Public/Core/`** as **pure C++17 with no Unreal
headers**. That layer compiles in two places:

1. Inside the Unreal module (the real game), and
2. **Standalone under clang** for the headless parity harness (`tests/standalone/`).

This is deliberate. Unreal cannot build in CI / the dev container (no engine, no .NET, limited
disk/RAM, Epic download gated). The pure Core can — so the math that the Godot project guarded with
its 25-selector headless gate is verified the same way here, on every change, with zero Unreal setup.
The UE wrapper layer (`UVoxelEditSubsystem`, `UVoxelScaleSettings`, the future world/combat/skill
subsystems) converts `FVector`/`FIntVector` ↔ `mira::Vec3` at the boundary and drives the custom cubic
greedy mesher (no third-party voxel plugin — see `../design/UE5_VOXEL_BACKEND_EVALUATION.md`).

```
Source/
  MiraThal.Target.cs / MiraThalEditor.Target.cs   build targets
  MiraThalVoxel/                                   generation / water / gravity / edit routing
    Public/Core/        <-- PURE C++17, no Unreal, clang-testable  (the ported math)
    Public/*.h          <-- UE wrappers (subsystems, settings)
    Private/*.cpp
  MiraThalCore/                                     gameplay (player, combat, skills, entities, UI)
  MiraThalNet/                                      multiplayer / replication (Phase 4)
Config/                                             engine + game ini (Nanite/Lumen/net)
tests/standalone/                                   clang headless parity harness
```

## Headless test loop (runs anywhere clang exists — no Unreal needed)

```bash
cd ue5/MiraThal/tests/standalone
./build.sh                 # build + run every selector
./build.sh scale codec     # run only the named selectors
```

Exit 0 = green. Selectors mirror the Godot `tools/headless/` gates (`scale`, `codec`, and — as the
heavier systems land — `finite`/`water_flow`, `gravity`/`sever`, `gen`). Each ported Core system is
"done" only when its selector is green, exactly like the Godot discipline.

## Full Unreal build (on the build machine — Phase 0 target: a local Windows/Linux box with UE5)

Prerequisites: **Unreal Engine 5.4** (no third-party voxel plugin — the cubic mesher is ours,
in `MiraThalVoxel`). The cubic-backend decision and why we don't use Voxel Plugin are in
`../design/UE5_VOXEL_BACKEND_EVALUATION.md`.

```bash
# Generate project files, then build the editor target:
<UE5>/Engine/Build/BatchFiles/RunUAT.sh BuildTarget -project=MiraThal.uproject -target=MiraThalEditor -platform=Win64 -configuration=Development

# Headless in-engine Automation Specs (Phase 0+ parity, once added):
<UE5>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe MiraThal.uproject -ExecCmds="Automation RunTests MiraThal." -unattended -nopause -nullrhi -log
```

## Status

**Phase 0 Core ports — all green (8,955 checks, 0 failures via `./build.sh`):**

| System | Core files | Godot source | Harness (checks) |
|---|---|---|---|
| Voxel scale (SSOT) | `Core/VoxelScale.h` | `VoxelScale.gd` | `scale` |
| Water byte codec | `Core/WaterByteCodec.h` | `WaterByteCodec.gd` | `codec` (608 w/ scale) |
| Material id authority | `Core/MaterialIds.h` | `WaterMaterial.gd` + `FloraMaterial.gd` | `materials` (45) |
| Finite water sim | `Core/FiniteWaterCore.{h,cpp}` | `FiniteWaterCore.gd` | `water` (47) |
| Voxel gravity / sever | `Core/VoxelGravity.{h,cpp}` | `GravityReference.gd` + `SeverFollowLib.gd` | `gravity` (33) |
| Heightmap + biome gen | `Core/HeightmapGenerator.{h,cpp}`, `Core/Noise.h` | `cubic_heightmap_generator` + `biome_field` + base | `gen` (7732) |
| Mining carve geometry | `Core/MiningCarve.h` | `EditToolHandler.gd` | `mining` (166) |
| Directional combat | `Core/MouseDirectionSampler.h`, `Core/ParryChainTracker.h`, `Core/EnemyAttackPool.h` | `combat/*` + `enemies/EnemyAttackPool.gd` | `combat` (54) |
| Throwable charge | `Core/ThrowableCharge.h` | `ThrowableHandler.gd` | `throwable` (22) |
| Skill XP progression | `Core/SkillProgression.h`, `Core/CombatXPRouter.h` | `SkillCurve.gd` + `SkillManager.gd` + `CombatXPRouter.gd` | `skills` (190) |
| Entity registry + streaming | `Core/EntityRegistry.h`, `Core/EntityStreaming.h` | `EntityRegistry.gd` + `EntityStreamer.gd` | `entities` (58) |
| Deterministic RNG | `Core/Rng.h` | (new; SplitMix64 for reproducible tests) | (used by `combat`) |

UE wrapper layer (compiles on the build machine): `UVoxelScaleSettings`, `UVoxelEditSubsystem`
(the `VoxelEditManager` single-gateway contract). Remaining wrappers (skill subsystem, melee/mining/
enemy components, entity-stream subsystem) bind the verified Core into UE classes — written against
the Core APIs during Phase 0 world bring-up.

**Known divergence (documented):** `Core/Noise.h` is a self-contained deterministic value-noise, NOT
bit-exact with Godot's FastNoiseLite (vendoring FNL was out of scope). Procedural hill *heights* won't
match a Godot-baked world voxel-for-voxel; the algorithm structure, hash3 scatter, banding, sea-level,
biome blend, and material ids are all faithful. Low impact: the shipped world is seeded from baked
**Gaea heightmaps** (`.exr`), not procedural noise — the noise is fill/variation only.

**Next (needs the build machine — UE5):** stand up the custom cubic greedy mesher (10cm,
triplanar atlas material) + chunk streaming, wire `UVoxelEditSubsystem` + the mining component to the
mesher, drive `UEnemyAttackComponent`/`USkillSubsystem`/`UEntityStreamSubsystem` from the verified Core,
and run the **dig-under-Lumen perf gate (Phase 0 step 6)** — the make-or-break test for the blocky-cube
+ Lumen bet. The Core math is done and locked by the harness; this is the engine-integration half.
