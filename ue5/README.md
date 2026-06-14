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
subsystems) converts `FVector`/`FIntVector` ↔ `mira::Vec3` at the boundary and drives Voxel Plugin Pro.

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

Prerequisites: **Unreal Engine 5.4**, and **Voxel Plugin Pro** installed into `MiraThal/Plugins/Voxel/`
(licensed; not committed — see `.gitignore`). Then re-enable the `"Voxel"` dependency in
`Source/MiraThalVoxel/MiraThalVoxel.Build.cs` and the plugin in `MiraThal.uproject`.

```bash
# Generate project files, then build the editor target:
<UE5>/Engine/Build/BatchFiles/RunUAT.sh BuildTarget -project=MiraThal.uproject -target=MiraThalEditor -platform=Win64 -configuration=Development

# Headless in-engine Automation Specs (Phase 0+ parity, once added):
<UE5>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe MiraThal.uproject -ExecCmds="Automation RunTests MiraThal." -unattended -nopause -nullrhi -log
```

## Status

**Phase 0 Core ports — all green (8,420 checks, 0 failures via `./build.sh`):**

| System | Core files | Godot source | Harness |
|---|---|---|---|
| Voxel scale (SSOT) | `Core/VoxelScale.h` | `VoxelScale.gd` | `scale` |
| Water byte codec | `Core/WaterByteCodec.h` | `WaterByteCodec.gd` | `codec` |
| Finite water sim | `Core/FiniteWaterCore.{h,cpp}` | `FiniteWaterCore.gd` | `water` (47) |
| Voxel gravity / sever | `Core/VoxelGravity.{h,cpp}` | `GravityReference.gd` + `SeverFollowLib.gd` | `gravity` (33) |
| Heightmap + biome gen | `Core/HeightmapGenerator.{h,cpp}`, `Core/Noise.h` | `cubic_heightmap_generator` + `biome_field` + `heightmap_generator_base` | `gen` (7732) |

UE wrapper layer: `UVoxelScaleSettings`, `UVoxelEditSubsystem` (edit-gateway contract).

**Known divergence (documented):** `Core/Noise.h` is a self-contained deterministic value-noise, NOT
bit-exact with Godot's FastNoiseLite (vendoring FNL was out of scope). Procedural hill *heights* won't
match a Godot-baked world voxel-for-voxel; the algorithm structure, hash3 scatter, banding, sea-level,
biome blend, and material ids are all faithful. This matters little for the shipped world, which is
seeded from baked **Gaea heightmaps** (`.exr`), not procedural noise — the noise is fill/variation only.

**Next:** stand up the Voxel Plugin world + triplanar atlas material, wire `UVoxelEditSubsystem` to the
plugin edit API, port the mining carve math, and run the dig-under-Lumen perf gate (Phase 0 step 6).
