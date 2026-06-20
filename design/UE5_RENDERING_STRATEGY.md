# UE5 Rendering Strategy — the cubic voxel world at high performance

**Status:** PARTLY REALIZED (decision record for the UE5 port). Companion to `UE5_TECH_STACK.md`,
`UE5_PORT_PLAN.md`, `UE5_VOXEL_MESHER_PLAN.md`. Drives the Phase 0 "dig-under-Lumen perf gate" — the
spikes and measurement criteria below are the gate's content. **As of 2026-06-17, M0/M1 (first chunk under
Lumen, baseline ≈ 6.4 ms GPU on a 7800 XT for an empty Lumen scene) and M2 (brickmap + generation + dig
loop) are built; M3 (water/flora/gravity wiring) + EXR heightmap import + the production streaming phases
(P1–P4) are in active build right now;** the Baseline render path (greedy mesh + Lumen) is the shipped
near-band, with the ray-march far band (spike C) and Nanite cold-bake (spike B) still ahead (M6/M7).

> ### Texturing decision (NEW, 2026-06-16): per-face SOLID COLOR — supersedes the atlas
>
> This doc originally referenced a **triplanar material atlas / Runtime Virtual Texture** for the voxel
> surface. **That is dropped.** The shipped look is **per-face solid color**: each voxel face is one flat
> color = `base_color(material)` × `face_shade(direction)` (six fixed directional shades — top brightest,
> bottom darkest — so cubes read as 3D before any dynamic light). The mesher **bakes that color into
> vertex color**; AO rides in vertex **alpha**. The UE material **`M_VoxelTerrainV2`** (canonical) is
> essentially **VertexColor → BaseColor** (with an sRGB-decode; see `UE5_VOXEL_MATERIAL_SETUP.md`) — no
> textures, no UVs, no atlas. At 10 cm a face is tiny on screen, flat
> color reads cleaner, and it lets **Lumen** do all the dynamic lighting. Palette = the old Godot
> per-material colors, in `Core/VoxelColor.h`. Wherever "atlas" / "triplanar" / "Runtime Virtual Texture
> (terrain)" appears below, read it as **the superseded plan**. See `UE5_TECH_STACK.md` §6.

**Aesthetic target (locked):** true blocky 10cm cubes, fully destructible, photoreal lighting
(Nanite/Lumen), Skyrim-scale streamed world, multiplayer. Voxel runtime: **custom cubic greedy mesher**
(Voxel Plugin 2 dropped cubic; see `UE5_VOXEL_BACKEND_EVALUATION.md`). **Surface = per-face solid color**
(above), not a textured atlas.

---

## 1. Framing — where the cost actually is

A blocky voxel world has three separable costs people conflate:

1. **Visibility** — which voxel faces a pixel sees (rasterize a mesh vs ray-march a volume).
2. **Shading / lighting** — GI, shadows, reflections (Lumen's job).
3. **Editing** — updating the world when the player digs / destroys.

"Ray marching vs meshing" is only a debate about **#1 and #3**. The decision is forced by one
load-bearing constraint:

> **Lumen wants meshes (or mesh distance fields). Chaos wants meshes (or heightfields). Skeletal
> characters, foliage, and particles composite against a depth buffer that meshes fill.**

Therefore, in UE5, the **interactive near band must be meshed** regardless of how we'd prefer to
render it — otherwise it is invisible to global illumination, has no collision, and characters clip
through it. **Ray marching only buys freedom where we need neither Lumen nor Chaos — i.e., the far
field.** That principle drives the whole architecture in §4.

---

## 2. Technique rundown (ranked for THIS project)

| # | Technique | For us | Verdict |
|---|---|---|---|
| 1 | **Greedy polygon meshing** (our custom cubic mesher) | ✅ native Lumen/Nanite/Chaos/shadows, standard meshes ❌ re-mesh on edit, vertex memory, LOD seams | **Near-band backbone** |
| 2 | **Ray marching a voxel volume** (DDA / Amanatides–Woo) | ✅ no meshing, ✅ destruction = a texture write, ✅ perfect cubes, constant geometry ❌ a *parallel renderer* in UE (custom RDG pass + manual depth); **Lumen can't see it**; secondary rays costly | **Hybrid: far field only** |
| 3 | **Sparse Voxel Octree / DAG (SVDAG)** | great static compression ❌ destruction shatters node-sharing | Reject (not destructible-friendly) |
| 4 | **Brickmap** (sparse flat grid of 8³ bricks; cf. NanoVDB) | O(1) edits, GPU-friendly, two-level DDA | **The shared data structure** |
| 5 | **SDF point/splat** (à la Dreams) | gorgeous; total renderer rewrite | Research only |
| 6 | **Nanite per-chunk** | hates per-frame rebuilds; **loves dense static meshes** w/ auto LOD+culling | **Exploit for *cold* chunks** |
| 7 | **Hardware ray tracing / Lumen HWRT** | traces against mesh BVH; dynamic edits = BVH rebuild cost | Optional quality tier later |

**Reality check on "no-triangle" voxel games:** Teardown, Dreams, Atomontage, John Lin's engine — every
one shipped its **own renderer**. Teardown is bounded scenes with a bespoke path tracer, *not* UE +
Lumen. Going full ray-march as the main path means fighting UE5 end-to-end. We don't; we layer.

---

## 3. "Can we do a lot on the GPU?" — yes, concretely

Most wins keep mesh-based rendering and just move the expensive part to the GPU:

- **GPU greedy meshing.** Re-mesh runs as a compute shader emitting vertex/index buffers; an edit
  re-meshes only the ~3³ affected bricks on-GPU, never stalling the game thread. **Single biggest
  lever, and it keeps Lumen/Nanite/Chaos.**
- **GPU world generation.** The deterministic `Core/HeightmapGenerator` + `Core/Noise` + `hash3` math
  (already ported, harness-locked) is plain arithmetic → transpiles to **HLSL compute**. Generate
  fresh chunks directly on the GPU; CPU never touches voxels. Keep the C++ Core as the parity oracle.
- **GPU-resident edit pipeline.** Authoritative voxel data lives in a **GPU brickmap**; one compute
  pass updates both the meshed hot chunks and the volume texture used by the far ray-march. One
  coherent source of truth.
- **Niagara GPU particles** for far grass, dig debris, water foam, weather (replaces the Godot
  `FarGrassManager` / `WaterFoamManager` impostor layers).
- **Inherited GPU work:** UE already GPU-drives culling, GPU Scene, mesh-draw commands; ~~the texture
  atlas becomes a **Runtime Virtual Texture**~~ *(superseded — surface is per-face vertex color, no
  texture; see header)*; Lumen (GI/reflections) + Virtual Shadow Maps run on GPU.

---

## 4. Recommended architecture

**One shared GPU brickmap. Three render bands. Lumen near, ray-march far, Niagara detail.**

```
        AUTHORITATIVE VOXEL DATA = sparse brickmap (CPU truth + GPU mirror)
                 │
   ┌─────────────┼───────────────────────────────┐
   ▼             ▼                                ▼
 HOT chunks    COLD chunks                      FAR field
 (near +       (near, unedited                  (beyond interaction +
  recently      for N seconds)                   collision range)
  edited)
 dynamic       baked to NANITE static mesh      RAY-MARCHED from the brickmap
 greedy mesh   (great culling/LOD,              in one pass: no mesh, no vertex
 (GPU),        no per-frame cost)               memory, no LOD seams, far edits
 Chaos                                          are free → replaces the Godot
 collision,    Lumen + Nanite                   distant-terrain rings + skirt
 Lumen
```

Three ideas this buys us:

1. **"Nanite for cold chunks, dynamic mesh for hot chunks."** A chunk untouched for N seconds bakes
   to a Nanite static mesh (Nanite's sweet spot: dense static geo); the instant it's dug, it drops
   back to a dynamic greedy mesh. Nanite culling/LOD covers ~95% of the world; dynamic-mesh cost is
   paid only where the player is actively destroying.
2. **Ray-marched horizon instead of a distant-terrain mesh.** The far band needs neither Chaos nor
   Lumen (it's scenery) — exactly ray marching's comfort zone. March it straight from the brickmap:
   no skirt, no LOD-ring seams, far-chunk edits cost nothing. **Deletes a whole subsystem** we
   maintained in Godot (`DistantTerrainManager` + skirt).
3. **Ray-marched voxel AO / contact shadows as a cheap *effect* on the meshed near band.** The data
   is already on the GPU; a few short DDA rays give crisp per-voxel ambient occlusion + contact
   shadows — a "voxel look" enhancement that's cheap because no extra storage is needed.

**Streaming:** at 10cm over a Skyrim-scale world nothing is fully resident — **World Partition + data
layers** for level streaming; the brickmap is sparse; only near bricks are GPU-resident for mesh +
ray-march. Mirrors the Godot streaming model (SQLite deltas + octree), upgraded.

**Water & multiplayer:** the finite water sim is a cellular automaton (natural compute workload) **but
multiplayer is server-authoritative** — the server simulates water on CPU via `Core/FiniteWaterCore`
(the truth); clients may run a GPU visual approximation corrected by server state. Render technique is
otherwise orthogonal to netcode; what must be shared is the **voxel data structure** across sim,
collision, and renderer.

---

## 5. Performance targets & budget

Estimates to be **validated by the step-6 gate**, not benchmarks — grounded in how Lumen/Nanite/Chaos
cost out and in the game design (over-shoulder 3rd person, 1-vs-many action combat, co-op 1–4,
destructible 10cm world, Skyrim atmosphere). These tiers + the worst-case scenario are **acceptance
criteria** for the gate.

### Hardware tiers

| Tier | Hardware | Resolution / FPS | Settings |
|---|---|---|---|
| **Recommended** | RTX 4070 / RX 7800 XT, 32 GB RAM | 1440p **60 fps** | Software Lumen, TSR/DLSS Quality, hybrid renderer |
| **Min spec** | RTX 3060 / RX 6600, 16 GB RAM | 1080p **60 fps** | Lumen low, upscaling, reduced view distance |
| **High-end** | RTX 4080 / 4090 | 1440p high-refresh or 4K60 | Hardware Lumen, higher far-field detail |

**Upscaling (TSR/DLSS/FSR) is a hard requirement, not a toggle** — native-res full-Lumen 60 fps is not
a target. Normal for a UE5 Lumen title.

### Frame budget — 60 fps = 16.6 ms (1440p, software Lumen, mid-high GPU, rough)

| Slice | Budget | Note |
|---|---|---|
| Lumen GI + reflections | 4–7 ms | biggest single cost; the price of the atmosphere look |
| Geometry (Nanite cold chunks + meshed near band) | 3–5 ms | what 6.B / 6.C claw back |
| Virtual Shadow Maps | 2–4 ms | |
| Post / TSR upscale | 2–3 ms | |
| Game thread (gen, water sim, AI, edit queue) | **< ~8 ms** | must not become the bottleneck |

The budget is tight by design — that's *why* cold→Nanite (6.B) and ray-marched far (6.C) exist: to
leave Lumen room.

### The real battle: frame-time consistency (1% lows), not average FPS

Average 60 is the easy half. The design stresses the lows. Watch, in priority order:

1. **Destruction hitches** — dig/explosion → mesh rebuild. Mitigated by GPU meshing (6.A) + the ported
   edit budget (926k voxels/frame). **The #1 thing the gate must prove.**
2. **Lumen relighting large holes** — blowing open a cavern forces GI/surface-cache re-converge; brief
   cost spike + possible GI lag on big topology changes. Tunable, real.
3. **Chaos cluster storms** — gibs + collapses spawn many rigid bodies → physics + draw-call spikes.
   Needs pooling + island-merging (the Godot `FallingVoxelCluster` pooling discipline, ported).
4. **Combined worst case (the canonical stress test):** *blow a hole under a lake while fighting a
   group* — re-mesh + water-flow sim + falling clusters + Lumen relight + multiple skeletal enemies in
   one frame. The gate must hold playable frame time through this, not just an idle vista.

### What the design buys us

- Over-shoulder 3rd person (narrow frustum) beats open vistas for on-screen load.
- Co-op 1–4 is trivial for replication; the load is the server-authoritative voxel sim, not client render.
- 1-vs-many is dozens, not hundreds — fine with skeletal LOD + the ported 4-tier entity streaming.
- **10cm is nearly free in the far band** (ray marching is resolution-bound, not voxel-count-bound);
  near-band cost is bounded by *surface area* (greedy meshing), not volume — so 10cm vs 6cm mainly
  raises the *edit* budget (already scaled), not triangle count.

### Memory

VRAM is the quiet constraint (brickmap + near meshes + Nanite + Lumen + virtual textures): comfortable
at 12 GB+, tight on 8 GB — likely the true min-spec gate, mitigated by World Partition streaming +
sparse storage.

### Confidence

Medium-high on hitting **1440p60 on recommended hardware** with the hybrid + upscaling. Medium on
**holding frame time through worst-case destruction** — which is precisely what step 6 measures, and
why it gates the rest of the port.

---

## 6. Phase 0 spikes (this IS the dig-under-Lumen perf gate)

Run each as an isolated experiment, capture with **Unreal Insights** against a target frame budget
(the UE analogue of the Godot F3 profiler + `_analyze_capture.py` flow):

| Spike | What | Pass criterion |
|---|---|---|
| **Baseline** | Custom cubic greedy mesh + Lumen, heavy sustained carving | Frame holds budget during the worst carve; record mesh-rebuild ms |
| **A — GPU meshing** | Move re-mesh to compute; re-mesh only affected bricks | Edit stall drops vs baseline; no visual regression |
| **B — Cold→Nanite bake** | Bake unedited near chunks to Nanite static meshes | Draw-call / culling win on a static field; bake cost amortizes |
| **C — Ray-marched horizon** | Brickmap + single-pass DDA far band | Cheaper than a distant mesh; no seams; far edits free |
| **D — Voxel AO ray-march** | Short DDA rays for AO/contact shadows on meshed near band | Look worth the ms; within budget |

**Decision rule:** if Baseline alone holds the frame budget under heavy carving, ship the simple path
(greedy mesh + Lumen) for the vertical slice and treat A–D as optimizations. If Baseline fails the
gate, A (GPU meshing) and C (ray-march far) become required, not optional — and if cubic-mesh + Lumen
still can't hold up, fall back to the `UE5_PORT_PLAN.md` "cubes near / smooth far" rendering option.
Keep the render layer swappable behind the brickmap so this stays a config decision, not a rewrite.

---

## 7. What this means for the modules

- `MiraThalVoxel` owns the brickmap (CPU authority + GPU mirror), the meshing path (the custom cubic
  greedy mesher + the GPU-meshing compute spike), the cold→Nanite baker, and the far ray-march pass.
- The ray-march pass is a custom render pass (`FSceneViewExtension` / RDG) — clearly isolated so it
  can be toggled and so it never blocks the meshed-near-band path that everything else depends on.
- `Core/` stays render-agnostic: it's the voxel *data + math* (generation, water, gravity, carve),
  consumed identically by the CPU game and (transpiled) by GPU compute. The renderer reads the
  brickmap; it never dictates Core.

---

## 8. References (for the spikes)

- **NanoVDB** — GPU-friendly sparse voxel structure with built-in DDA (brickmap model).
- **Teardown / John Lin / Gabe Rundlett** — ray-marched brickmap voxel renderers (note: all bespoke
  engines, not UE — cited for the *technique*, as cautionary tales for UE integration).
- **Media Molecule "Dreams"** — SDF splat rendering (creative alternative; research only).
- **UE5:** Nanite (programmable raster, 5.3+), Lumen (surface cache / HWRT), Virtual Shadow Maps,
  Runtime Virtual Textures, World Partition + data layers, Niagara, RDG / SceneViewExtension.
