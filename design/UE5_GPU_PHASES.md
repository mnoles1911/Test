# UE5 GPU phases (M6 Nanite bake · M7 far-field ray-march · M8 GPU meshing)

**Status:** PLAN + groundwork (2026-06-16). The three late milestones that move work to the GPU. M5
(multiplayer) is deferred to the very end by direction, so these come first after the M3 sim. This doc
captures the approach and what's **already in place** so each can be picked up cleanly. Build detail and
the module scoping live in `design/UE5_VOXEL_MESHER_PLAN.md`; this is the focused state-of-play.

---

## What already exists (the shared substrate)

- **`Brickmap` is GPU-friendly by design.** Sparse 8³ bricks with a per-brick `solid_count` and a brick
  index (`has_brick` / `brick_solid_count` / `brick_has_solid`). That index is exactly the coarse
  "skip whole empty bricks" acceleration structure a GPU ray-march or mesher keys off.
- **`Brickmap::raycast_solid` is the CPU oracle for M7.** Amanatides–Woo voxel DDA returning first-solid
  voxel + face normal + entry distance + material. **Its contract is now pinned by
  `tests/standalone/test_raymarch.cpp` (21 checks)** — the GPU HLSL march must reproduce these results
  voxel-for-voxel. Treat that test as the M7 spec.
- **The greedy mesher + per-face color is a pure function of a slab** (`GreedyMesher` + `VoxelColor`),
  which is what makes an M8 GPU port tractable: the same logic, re-expressed in a compute shader.
- **Per-face SOLID COLOR** (vertex color, no atlas) means no texture sampling on the GPU paths — the
  far-field march and the Nanite bake both just need the palette + face shade, already in `VoxelColor.h`.

---

## M6 — Nanite cold-bake (static, unedited geometry)

**Goal:** distant *static* chunks that nobody is editing get baked once into a Nanite mesh, so the
mid-field renders at Nanite's cost (sub-pixel triangle culling) instead of holding full PMC meshes.

- **Trigger:** a chunk that has been resident and **unedited** for N seconds (no carve writes touching
  it) is a bake candidate. Edits invalidate the bake and fall back to the live PMC mesh.
- **Build:** feed the chunk's greedy-mesh vertex/index/colors into a Nanite-enabled static mesh
  (`UStaticMesh` with `NaniteSettings.bEnabled = true`, built via `FStaticMeshRenderData` /
  `UStaticMesh::Build`), swap the PMC actor for a `UStaticMeshComponent`.
- **Gotcha:** Nanite wants reasonably large static batches — bake at the chunk or super-chunk level, not
  per voxel. Vertex color carries through Nanite, so the material is unchanged (`M_VoxelTerrainV2`).
- **Groundwork next:** a `MiraThalVoxelBake` module + an `bUneditedSince` timestamp on the chunk actor.

## M7 — far-field ray-march horizon

**Goal:** beyond the meshed/baked rings, render the world by ray-marching the brickmap on the GPU — no
geometry at all for the horizon, just a screen-space march against a GPU mirror of the bricks.

- **GPU mirror:** upload the resident bricks as a structured buffer + a brick-index texture/buffer (the
  `has_brick`/`solid_count` data). The march steps bricks (skip empty) then voxels inside occupied bricks
  — the same two-level walk the CPU oracle does.
- **Shader:** a post-process / custom pass that, per pixel, marches from the camera and shades the first
  solid using `base_color × face_shade` (matching `VoxelColor.h`) with Lumen-consistent sky light.
- **Correctness gate:** must match `Brickmap::raycast_solid`. `test_raymarch.cpp` is the reference — port
  those cases to a GPU readback test. Normals, first-hit voxel, and entry distance must agree.
- **Groundwork next:** a `MiraThalVoxelRender` module + the brick-buffer upload + an HLSL DDA seeded from
  the oracle's exact stepping (axis tMax/tDelta, `<=` tie-break order matters — see the CPU code).

## M8 — GPU meshing + GPU world generation

**Goal:** move the greedy mesher (and eventually `HeightmapGenerator`) onto the GPU so streaming a huge
map doesn't bottleneck on CPU meshing.

- **GPU greedy mesh:** a compute shader consumes a slab (from the GPU brick mirror) and emits the same
  quads + per-face color the CPU mesher does. The CPU `GreedyMesher` output is the parity oracle.
- **GPU generation:** `HeightmapGenerator`'s per-column math (and the **EXR `ImageHeightmap` sampling**,
  which is already a simple bilinear lookup) port to a compute pass so columns can be filled GPU-side —
  the EXR import (M3a) was deliberately written as a plain georeferenced grid sample to make this easy.
- **Correctness gate:** GPU mesh vs CPU `GreedyMesher` on the same slab; GPU column fill vs
  `resolve_column`/`material_at`. Reuse the existing `test_mesher` / `test_gen` cases as the spec.

---

## Sequencing note

M6 is the lowest-risk visual win (reuses the existing mesh, just rehouses it in Nanite). M7 is the
biggest renderer change (new pass + GPU brick mirror) but has the cleanest spec (the oracle test). M8 is
the largest and should come last of the three — once the GPU brick mirror from M7 exists, GPU meshing
and GPU generation build on the same upload. All three keep the Core CPU path as the parity oracle, the
same discipline that carried M0–M4.
