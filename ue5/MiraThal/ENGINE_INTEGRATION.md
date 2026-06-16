# Engine Integration — the `[B]` build-machine phase

> **Read this first if you just opened the repo in a LOCAL Claude Code session on the UE5 machine.**
> The engine-agnostic **Core is finished and verified** (PR #253, all 25 clang harnesses green).
> Everything in this doc is the work that needs the actual Unreal Engine 5 build — it could not
> be done in the cloud Linux container, so it was handed off to you here.

Engine: **UE 5.7** at `D:\UE5\UE_5.7` (Windows). Plan of record: `design/UE5_VOXEL_MESHER_PLAN.md`.

---

## Where things stand

- The whole CPU brain of the custom cubic voxel plugin lives in
  `ue5/MiraThal/Source/MiraThalVoxel/{Public,Private}/Core/*` — pure C++17, **no engine types**.
- It is proven by a standalone clang harness: `ue5/MiraThal/tests/standalone/build.sh` (run with no
  args = all selectors; `./build.sh mesher watersurf …` = a subset). Keep this green; it is the
  safety net and it does NOT need Unreal.
- What is NOT done: turning `mira::MeshBuffers` into something on screen. That is this phase.

## First target (agreed): **render ONE chunk under Lumen** (Milestone M1 Baseline)

Generate a single chunk from the Core, greedy-mesh it, upload it through RealtimeMeshComponent,
and see it lit by Lumen in PIE. This is both the first proof the Core renders *and* the perf
**Baseline** capture the later milestones measure against.

---

## Step 0 — run Claude Code here, locally

You're doing this already. Point Claude Code at the repo root on the Windows box. The branch is
`claude/godot-ue5-port-planning-nrtgbu`. The cloud session can't reach `D:\`, so all
compile-iterate happens in THIS local session against the real engine.

## Step 1 — make it a UE project (no engine code yet)

The repo currently has only the `Source/MiraThalVoxel` module tree — there is no `.uproject` yet.
Create the minimal project so UE can open it:

- `ue5/MiraThal/MiraThal.uproject` — engine association to 5.7; modules: the primary game module +
  `MiraThalVoxel` (Runtime). Plugin: `RealtimeMeshComponent` (Enabled).
- `Source/MiraThal.Target.cs` and `Source/MiraThalEditor.Target.cs`.
- A primary game module (e.g. `Source/MiraThal/MiraThal.{Build.cs,h,cpp}`) with
  `IMPLEMENT_PRIMARY_GAME_MODULE`.
- `Source/MiraThalVoxel/MiraThalVoxel.Build.cs` — add the Core include path
  (`PublicIncludePaths.Add(.../MiraThalVoxel/Public)` so `#include "Core/..."` resolves) and
  `PublicDependencyModuleNames` += `Core`, `CoreUObject`, `Engine`, `RealtimeMeshComponent`.
  Set `CppStandard = CppStandardVersion.Cpp17;` (the Core is C++17). The Core headers are
  `#include`-only — they compile straight into this module, no separate build of `Private/Core/*`
  beyond adding `GreedyMesher.cpp` to the module.

> The local session should WRITE these against real 5.7 headers and fix compiler output — don't
> trust hand-written UE boilerplate from memory. Generate VS project files, build, confirm an
> empty editor opens before adding any voxel code.

## Step 2 — install RealtimeMeshComponent for 5.7

`IVoxelMeshSink` is the seam (plan §"borrows"), with RealtimeMeshComponent as the first backend.
Install the **5.7-compatible** RealtimeMeshComponent (TriAxis Games, MIT) into
`ue5/MiraThal/Plugins/RealtimeMeshComponent/`. Verify it builds + the sample loads before wiring
ours. If the public release lags 5.7, note it and fall back to `UProceduralMeshComponent` behind
the same `IVoxelMeshSink` so M1 isn't blocked — swap later.

## Step 3 — the mesh sink: `MeshBuffers` → RealtimeMesh

Define `IVoxelMeshSink` (the engine-agnostic seam) and a `FRealtimeMeshSink` implementing it.
For each populated `MeshSection` in `MeshBuffers` (one per `FaceClass`: Opaque, Cutout, Water,
Flora), build a RealtimeMesh stream set and assign a material slot per class.

Per-vertex mapping (`mira::MeshVertex` → RealtimeMesh vertex):
- position: `(px, py, pz)` are in **voxel units** → multiply by **10** to get UE units
  (1 voxel = 10 cm = 10 UU, since 10 voxels/m and UE = cm). See the `VoxelScale` constant — keep
  ONE source of truth for this factor on the UE side.
- normal: `(nx, ny, nz)`.
- UV0: `(u, v)` — already atlas-mapped by `AtlasUV` for solids; flora/water carry their own UVs.
- color: pack `ao` (0..1) into vertex color (the Core already baked AO into the merge).
- indices: each section's `indices` (CCW, triangle list).
- **Never enable `bake_tangents`** (project non-negotiable) — let the material handle tangents.

> **Two gotchas to settle here, with eyes open (flag your choice in code comments):**
> 1. **Handedness / up-axis.** The Core is right-handed **Y-up** (Godot heritage); UE is
>    left-handed **Z-up**. Pick the Core→UE basis swap ONCE in the sink (e.g. Core (x,y,z) →
>    UE (x, z, y) with a winding flip to keep faces outward) and apply it uniformly to positions
>    AND normals. Getting this wrong = inside-out or sideways chunks. Verify against the
>    GreedyMesher's documented winding before committing the mapping.
> 2. **Winding after the swap.** A basis swap that flips handedness reverses front/back; if faces
>    render inside-out, reverse each triangle's index order (or flip cull), don't negate normals.

## Step 4 — `AVoxelChunkActor`: generate → mesh → upload

On `BeginPlay` (or a dev exec command), for ONE chunk at chunk-coord (0,0,0):

1. `mira::DenseGrid slab = mira::make_mesh_slab();` // 34³, APRON 1
2. Fill it from the generator. For each slab cell, convert to a **world voxel coord** (chunk
   origin + local − APRON), then:
   ```cpp
   mira::HeightmapGenerator gen; gen.set_seed(<seed>);
   // per column (x,z): mira::ColumnInfo col = gen.resolve_column(wx, wz);
   // per voxel (x,y,z): uint8_t id = (uint8_t)gen.material_at(wx, wy, wz, col);
   slab.type_at(sx,sy,sz) = id;   // material_at returns AIR above ground
   // layer water/flora per the column flags (col carries water flag + flora ids)
   ```
   (Read `HeightmapGenerator.h` §"CORE API" + `ColumnInfo` for the exact column fields.)
3. Mesh it:
   ```cpp
   mira::MeshBuffers mb = mira::greedy_mesh(slab);   // Opaque + Cutout, AO baked
   mira::append_water_surface(slab, mb);             // sloped Water section
   mira::append_flora(slab, mb);                     // billboard Flora section
   ```
4. Push `mb` through `FRealtimeMeshSink` onto the actor's RealtimeMeshComponent.

## Step 5 — see it, and capture the Baseline

Empty Lumen level (Lumen GI + reflections on), drop `AVoxelChunkActor`, hit PIE. Expect one
blocky 32³ chunk, correctly culled (no interior faces), atlas-textured, lit by Lumen.

Then capture the **perf Baseline** (`stat unit`, `stat GPU`, a `ProfileGPU` snapshot) — the M2
dig-under-Lumen gate and everything after is measured against this number. Record it in
`MILESTONES.md` / this doc.

---

## Acceptance for M1
- [ ] Project opens + builds in UE 5.7; `MiraThalVoxel` module links the Core.
- [ ] RealtimeMeshComponent (or PMC fallback) installed and rendering.
- [ ] One generated chunk visible under Lumen — right side out, right scale (≈3.2 m cube),
      atlas UVs correct, AO visible in the vertex shading.
- [ ] Standalone clang harness still green (you didn't have to touch Core; if you did, re-run it).
- [ ] Baseline perf numbers recorded.

## Core entry points (so you don't have to dig)
| Need | Call | Header |
|---|---|---|
| empty 34³ apron'd slab | `mira::make_mesh_slab()` | `Core/VoxelChunk.h` |
| read/write a cell | `slab.type_at(x,y,z)`, `slab.water_at(x,y,z)` | `Core/VoxelChunk.h` |
| terrain column | `gen.resolve_column(wx,wz) -> ColumnInfo` | `Core/HeightmapGenerator.h` |
| terrain voxel | `gen.material_at(wx,wy,wz,col) -> int` | `Core/HeightmapGenerator.h` |
| greedy mesh (opaque+cutout, AO baked) | `mira::greedy_mesh(slab) -> MeshBuffers` | `Core/GreedyMesher.h` |
| water surface | `mira::append_water_surface(slab, mb)` | `Core/WaterSurfaceMesher.h` |
| flora | `mira::append_flora(slab, mb)` | `Core/FloraMesher.h` |
| mesh data | `mb.section(FaceClass::X).{vertices,indices}` | `Core/MeshTypes.h` |
| sparse world store + ray-march | `mira::Brickmap` | `Core/Brickmap.h` |
| save / net wire formats | `mira::region::*`, `mira::net::*` | `Core/RegionFormat.h`, `Core/NetVoxelCodec.h` |

`MeshVertex` = `{px,py,pz, nx,ny,nz, u,v, ao}`. `FaceClass` = `{Opaque, Cutout, Water, Flora}`.

## After M1 (sequence per the plan)
M2 dig-under-Lumen perf gate (Brickmap + edit→re-mesh via `MeshBudget`) → M3 water/flora shaders →
M4 World Partition streaming + save (`RegionFormat`, `BandPolicy`) → M5 MP replication
(`NetVoxelCodec`) → M6 Nanite cold-bake → M7 far-field ray-march (Brickmap is the oracle) →
M8 GPU meshing. Each gated `[B]` step is in `design/UE5_VOXEL_MESHER_PLAN.md`.
