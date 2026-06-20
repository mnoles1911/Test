# GPU Parity Plan — verifying the M7 march and M8 mesh against the CPU oracles

**Status:** PLAN (2026-06-17). The `MiraThalVoxelRender` module is a SCAFFOLD: the HLSL
DDA + the greedy-mesh structure + the buffer layouts are real, but the RHI upload and
the render/compute dispatches are stubbed. This doc is the concrete test plan to run
ONCE the GPU paths are wired, so each GPU path is proven equal to its CPU oracle before
it ships. Nothing here is claimed as passing yet — these tests do not exist until the
dispatches are implemented.

The discipline mirrors the existing Core gate: the CPU is the source of truth, the GPU
must reproduce it. The oracles already exist and are pinned by clang tests:

- **M7 march oracle:** `mira::Brickmap::raycast_solid` — `tests/standalone/test_raymarch.cpp` (the exact stepping + tie-break + first-hit/normal/distance contract).
- **M8 mesh oracle:** `mira::greedy_mesh` — `tests/standalone/test_mesher.cpp` (cull + greedy-merge + per-face color + winding contract).

---

## Part A — M7 ray-march parity (GPU vs `Brickmap::raycast_solid`)

### What to build
A headless GPU readback harness (an Automation test under
`Source/MiraThalVoxelRender/Private/Tests/`, run via the editor/commandlet automation
runner — NOT the clang harness, which has no RHI). It:

1. **Builds a tiny brickmap on the CPU** identical to each `test_raymarch.cpp` case
   (e.g. case 1: a single STONE voxel at `(10,0,0)`; case 7: a wall plane at `x=12`).
2. **Mirrors it** via `FVoxelBrickGPUMirror::BuildPackedData` over a region that
   contains the case, then `UploadToGPU`.
3. **Dispatches a 1-thread-per-ray compute variant of `VoxelRaymarch.usf`** (a small
   compute entry that calls the SAME `raycast_solid()` HLSL function the pixel shader
   uses) over a fixed list of test rays — the exact origins/dirs/`max_dist` from
   `test_raymarch.cpp` — writing each ray's result (`hit, voxel.xyz, normal.xyz, t,
   type`) into an output structured buffer.
4. **Reads the buffer back** and asserts it equals what the CPU
   `Brickmap::raycast_solid` returns for the same ray.

### What to assert (per ray, mirroring the 21 CPU checks)
- `hit` flag matches (cases 5/6: empty world + past-`max_dist` are MISSES).
- `voxel.xyz` is the same first-solid voxel (case 4 gap, case 7 diagonal `x=12`,
  case 8 water-passthrough lands on `x=15`).
- `normal.xyz` matches the outward face normal (case 1 `-X`, case 2 the `+X/-Y/-Z`
  set, case 3 origin-inside => zero normal).
- `t` matches the entry distance within a tolerance. **NOTE:** the CPU oracle is
  `double`; the GPU is `float`. Use an epsilon of ~`1e-3` voxel units for `t`, and
  require `voxel`/`normal`/`type` to match EXACTLY (they are integers — no tolerance).
- `type` matches the material id at the hit.

### The load-bearing parity risks to watch
- **Tie-break order.** The CPU steps X-first on ties (`tMaxX <= tMaxY && tMaxX <= tMaxZ`),
  then Y (`tMaxY <= tMaxZ`), else Z, with `<=` (not `<`). The HLSL reproduces this verbatim.
  The diagonal `{1,1,0}` case (test 7) is the canary — if the tie-break drifts it lands
  on the wrong cell.
- **`float` vs `double` boundary crossings.** On a ray that grazes a voxel corner, float
  rounding could pick a different first cell than the double oracle. The readback test
  should include at least one axis-aligned-corner ray; if it diverges, the fix is to march
  in `double`-equivalent care (or accept the documented float epsilon for `t` only, never
  for the integer voxel/normal).
- **Brick-skip must not change results.** The scaffold deliberately keeps the per-voxel
  walk (consulting the brick index only via `type_at_global` returning air for empty
  bricks). If a faster "jump to brick boundary" skip is added later, re-run the SAME
  readback test — the quad/hit set must be byte-identical.
- **Packing order.** `BuildPackedData` writes voxels in `coords::flatten(local, BRICK)`
  order; the shader unpacks with the same `local_flatten`. A dedicated assert: read one
  resident brick's 512 bytes back and compare to `type_at` voxel-by-voxel.

---

## Part B — M8 GPU mesh parity (GPU vs `greedy_mesh`)

### What to build
Another readback Automation test that:

1. **Builds the same apron'd slabs `test_mesher.cpp` uses** (case 1 single voxel ->
   6 quads; case 3 flat `4x1x4` -> one merged `+Y` quad; case 4 solid `32^3` -> exactly
   6 quads, each `32x32`; case 5 leaves/cutout rules; case 7 atlas/UV — here per-face
   COLOR instead).
2. **Runs the CPU `greedy_mesh(slab)`** to get the oracle `MeshBuffers`.
3. **Dispatches `VoxelGreedyMesh.usf`** over the same slab (once the merge loop is
   implemented), reading back the `OutQuads` append buffer + its count.
4. **Compares the two quad sets.**

### What to assert
- **Quad count per face class** matches (`opaque_quads`, `cutout_quads`, etc.): single
  voxel -> 6; solid `32^3` -> 6; flat patch -> 1 merged `+Y`.
- **Compare as a SET, not a sequence.** The GPU merge may emit quads in a different
  order than the CPU's top-left-first scan (especially if a parallel merge is used).
  Canonicalize each quad to `(origin, du*w, dv*h, normal, material, color)` and sort
  both lists before comparing, so order differences are not false failures.
- **Per-face color** equals `shaded_color(id, dir)` from `VoxelColor.h` (the GPU packs
  the same `base_color * face_shade`, round-to-nearest, clamp). Exact byte match on
  the 3 channels.
- **Winding / normal:** an emitted `+Y` quad's geometric normal (edge cross product)
  points `+Y` (test_mesher case 8). Reproduce that check on the read-back quads.
- **Class routing:** water + flora voxels emit nothing (test_mesher case 6).

### The load-bearing parity risks to watch
- **AO is not yet in the GPU mask.** `test_mesher` case 9 splits a merged quad where AO
  differs. The GPU skeleton omits the per-cell AO levels, so it will OVER-MERGE there.
  Parity for case 9 requires adding the groupshared AO buffer first (flagged TODO in the
  .usf). Until then, run the mesh parity test WITHOUT case 9, and treat case 9 as a known
  gap, not a pass.
- **Merge determinism.** Start with the single-thread-per-group serial merge (approach
  (a) in the .usf) so the GPU emits the EXACT CPU quad set; only move to a parallel merge
  after the set-compare test is green, since parallel merging can change which rectangle
  decomposition is chosen (still a valid mesh, but not byte-identical to the oracle).
- **Triangulation diagonal.** The CPU flips the quad diagonal based on AO anisotropy
  (`should_flip_diagonal`). If the GPU readback compares QUADS (not triangles) this is
  moot; if it compares triangles, port the diagonal rule too.

---

## Running order
1. Land the M7 readback test first (smallest, cleanest spec — one shader function, a
   handful of rays). It also validates the brick mirror packing, which M8 reuses.
2. Land the M8 mesh readback test second, single-thread merge, without AO (case 9 gap).
3. Add AO to the GPU mask -> enable case 9.
4. Only then consider parallel merge / brick-boundary skip, re-running both readback
   tests as regression gates after each optimisation.
