# Water Rendering Plan — good-looking water for the cubic voxel world

**Status:** PLAN / RESEARCH (2026-06-22). Companion to `design/UE5_RENDERING_STRATEGY.md` (bands +
per-face vertex color), `ue5/MiraThal/design/ATMOSPHERE_LIGHTING_SPEC.md` (the locked-exposure day/night
sky stack), `design/UE5_ART_ASSETS.md` (CC0 water normal + VFX), `design/UE5_VOXEL_MATERIAL_SETUP.md`
(the `M_VoxelWater` placeholder + sRGB/ProcMesh gotchas), and the legacy `design/WATER_SHADER_V3_PLAN.md`
(the Godot SEUS/Sildur-class look we are re-implementing in UE5).

> **Plain-English orientation (read first).** The game already *simulates* water correctly — a
> per-cell cellular fluid sim that conserves volume (`Core/FiniteWaterCore`), with 8 fill levels per
> cube and a flow direction baked into every water cell. It also already *meshes* that water into a
> sloped, translucent surface (`Core/WaterSurfaceMesher`). What it does **not** do yet is *draw* that
> surface well: today the water is a flat translucent blue with no reflection, no refraction, no ripples,
> no foam. **This document is the plan to make the water look good** — purely a rendering/material
> upgrade. We are NOT touching the simulation. We keep the blocky cubic identity: flat-ish cube-top
> water with animated *normals* and transparency, not tall rolling Gerstner waves.

> **Two hard project constraints carried in from the atmosphere spec (do not violate):**
>
> 1. **Auto-exposure is LOCKED** (Min=Max EV100 ≈ 11 on the unbound PostProcessVolume). The water
>    material must read correctly at that fixed exposure — we tune the water to the anchor, never the
>    other way around.
> 2. **The terrain reads its color as sRGB decoded by a Power(2.2) node** (`M_VoxelTerrainV2`). The
>    water vertices carry the same kind of baked sRGB color (`base_color(WATER_FULL) = {51,102,153}`),
>    so if the water material ever uses that vertex color it must decode it the same way, or pick its
>    color from material parameters instead (recommended — see §3).

---

## 1. Current state — how water is drawn TODAY (with file refs)

### 1.1 The sim (GOOD — stays untouched)

- **`Source/MiraThalVoxel/Public/Core/FiniteWaterCore.h/.cpp`** — the volume-conserving cellular fluid
  sim. Each water cell holds 1..8 units; units physically move down then sideways until level. The
  ledger is the single authority. **We do not touch this.**
- **`Source/MiraThalVoxel/Public/Core/WaterByteCodec.h`** — the 1-byte-per-cell water format:
  bits 0–3 = level (1..8), bit 4 = source flag, bits 5–7 = flow direction
  (`DIR_STILL / POS_X / NEG_X / POS_Z / NEG_Z / DOWN / UP`). This is the data the renderer reads.

### 1.2 The mesh (mostly GOOD — needs *additive* per-vertex data for foam/depth)

- **`Source/MiraThalVoxel/Public/Core/WaterSurfaceMesher.h`** — `append_water_surface()` builds the
  fluid surface into its own section, `out.section(FaceClass::Water)`. Key facts:
  - **Water is a separate mesh section with its own material** (`FaceClass::Water`, value 2), distinct
    from the opaque terrain section. Confirmed in `VoxelChunkActor.cpp` (`SetMaterial(FaceClass::Water,
    WaterMat)`) and `MeshTypes.h` (`enum class FaceClass { Opaque, Cutout, Water, Flora }`).
  - It emits a **sloped surface quad per surface cell** (not a full cube). Each of the 4 top corners
    takes a height blended from the up-to-4 water columns meeting at that corner, so neighbouring cells
    of different fill level **fuse into one continuous sloped sheet** (classic Minecraft-style fluid
    blend) rather than a staircase. Sides are emitted only against non-water neighbours; no bottom
    faces; no collision.
  - **Flow direction is ALREADY baked per vertex.** `flow_xz_of_byte()` decodes the cell's flow byte
    into a 2D world-XZ vector `(flow_x, flow_z)`, stored in `MeshVertex.flow_x/flow_z` (`MeshTypes.h`).
    Still/vertical/settled cells get `(0,0)`.
  - **That flow vector already reaches the GPU.** `MiraVoxelMesh.cpp` packs it into the water section's
    **second UV channel (UV1)** via the 4-UV-channel `CreateMeshSection` overload; UV0 is the plain
    per-cell tile UV. Every non-water vertex leaves UV1 at `(0,0)` = inert.

- **`Source/MiraThalVoxel/Private/MiraVoxelMesh.cpp`** — the upload glue. Uses
  `UProceduralMeshComponent::CreateMeshSection`. Per the header comment it **leaves Tangents empty so
  PMC derives them**. This matters: a tangent-space normal map needs a tangent basis (see §4).

### 1.3 The color + material (BASIC — this is what we are upgrading)

- **`Source/MiraThalVoxel/Public/Core/VoxelColor.h`** — `base_color()` returns a single flat blue
  `{51,102,153}` for the whole water id range. The mesher tags every water vertex with this as a
  fallback albedo. There is **no per-face shading** on water (it reads as one sheet).
- **`M_VoxelWater`** (per `design/UE5_VOXEL_MATERIAL_SETUP.md`) — currently a **plain translucent
  blue** material, explicitly earmarked: *"upgrade to Single Layer Water later."* That upgrade is this
  plan. No reflection, refraction, ripple, or foam today.

### 1.4 Legacy intent we are re-implementing (the Godot V3 plan)

`design/WATER_SHADER_V3_PLAN.md` is the Godot build's water look (SEUS/Sildur-class): domain-warped FBM
normal ripples flow-mapped along the fluid flow vector, screen refraction, Fresnel sky reflection, sun
specular, depth-fade tint, shoreline foam, caustics, underwater fog. **It shipped most of that in
Godot.** This plan ports the *above-water* surface look to UE5 primitives. (Underwater camera fog /
caustics-from-below / submerge transitions are a separate future doc — this plan is the **water
surface as seen from above**, which is 90% of the visual win.)

---

## 2. Recommended approach (and what is explicitly rejected)

### 2.1 Recommendation: **Single Layer Water shading model on our own water mesh section**

Author **`M_VoxelWater` as a `Shading Model = Single Layer Water`, `Blend Mode = Opaque` material**,
applied to the existing `FaceClass::Water` mesh section. We keep our mesh, our streaming, our sim — we
only change the material (plus a small additive mesh-data change in §4).

**Why Single Layer Water (SLW) for us:**

- It is Epic's **cost-effective, physically-based** water surface: one depth layer that does proper
  scattering, absorption, reflection, refraction, and shadowing in a custom pass that runs after the
  base pass / deferred lighting, reading the lit scene + depth buffers
  ([SLW docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/single-layer-water-shading-model-in-unreal-engine)).
- It is **Opaque/Masked blend**, not regular translucency — so it writes depth, behaves well under
  Lumen, and avoids the translucency-sorting and Lumen-translucency caveats that plague a normal
  Translucent material. This is the single biggest reason it beats a hand-rolled translucent surface
  for a large, streamed, dynamically-edited water body.
- It gives **depth-based color (shallow→deep)** for free via its absorption/scattering inputs plus the
  **`SceneDepthWithoutWater`** node — the SLW-specific depth read that, unlike normal SceneDepth, works
  correctly because SLW is an opaque material
  ([80.lv stylized water](https://80.lv/articles/how-to-build-stylized-water-shader-design-implementation-for-nimue)).
- It works on **any mesh** — it is a *shading model*, not the Water plugin. Our procedural water
  section just needs the material assigned (and `Used with Water` usage flag if the compiler asks; see
  §3.7). It does **not** require Water Body actors.
- It is exactly what both `design/UE5_ART_ASSETS.md` §3b and `ATMOSPHERE_LIGHTING_SPEC.md` already
  earmark, and it ties cleanly into the day/night MPC and the locked exposure.

### 2.2 Explicitly REJECTED: the UE5 **Water plugin** (Water Body actors / Gerstner / spline bodies)

The Water plugin's `Water Body Ocean/Lake/River` actors define water via **splines + a Water Zone**
that meshes a heightfield surface with Gerstner waves
([Water System docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/water-system-in-unreal-engine),
[Water Body Actors](https://dev.epicgames.com/documentation/en-us/unreal-engine/water-body-actors-in-unreal-engine)).
**This does not fit us, honestly assessed:**

- Our water is **per-voxel simulated and streams in/out with chunks**. A spline-bounded body actor
  cannot represent a pond that fills, drains, and reshapes every sim tick across a 5 km streamed map.
  We'd be fighting the plugin's whole authoring model.
- Gerstner waves give **tall rolling displacement** — the opposite of our **flat-topped cubic**
  identity. We want flat cube-tops with animated *normals*, not vertical wave crests.
- The plugin owns its own meshing/LOD/streaming, which would collide with our chunk streamer and
  brickmap. Two streaming systems, one of them irrelevant to a voxel sim.
- **We keep the plugin's *shading model* (Single Layer Water) and throw away its *actors/meshing*.**
  That is the clean split: SLW is engine-core, usable standalone.

### 2.3 Also rejected (for the surface): a plain **Translucent** custom material

A `Blend Mode = Translucent` surface *can* do depth-fade + Fresnel + refraction, and it is what the
legacy Godot shader effectively was. But in UE5 translucency has real downsides for a big water body:
sorting artifacts, weaker/again-special-cased Lumen interaction, no clean depth write, and the
refraction-on-large-flat-surfaces artifacts. SLW exists precisely to give "water look" without those.
**Reserve a small Translucent variant only if** we later need tiny, close, see-all-the-way-through
puddles where SLW's single-layer absorption reads too opaque — a niche, not the default.

### 2.4 Substrate note (UE5.7-specific, important)

UE5.7 makes **Substrate production-ready and default for NEW projects**, but **existing projects
upgrading to 5.7 keep the legacy (non-Substrate) material path** unless they explicitly opt in under
Project Settings → Rendering
([5.7 release notes / Substrate overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-substrate-materials-in-unreal-engine),
[Sprintermax confirmation](https://x.com/Sprintermax/status/1988647594902671809)). **MiraThal is an
existing project**, so this plan targets the **classic Single Layer Water shading-model** node path
described above — that is what we get by default and it is fully production-ready. If/when we opt into
Substrate later, the equivalent is the **Substrate Single Layer Water BSDF**; the *feature* design
(depth color, normals, foam) ports 1:1, only the node wiring changes. **Decision: stay non-Substrate
for water v1** to match the rest of the project's materials and avoid a project-wide material migration.

---

## 3. The water MATERIAL design (`M_VoxelWater`, Single Layer Water)

Each visual feature below lists the UE material nodes/inputs and any engine/material settings. Wire
the obvious ones first (§6 phases the rollout).

### 3.1 Material-level settings (set these on the material first)

| Setting | Value | Why |
|---|---|---|
| **Shading Model** | **Single Layer Water** | The whole approach (§2.1) |
| **Blend Mode** | **Opaque** | SLW runs as a custom opaque pass; cleanest under Lumen ([SLW docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/single-layer-water-shading-model-in-unreal-engine)) |
| **Two Sided** | **ON** | Our mesher emits sides + a single-faced top; two-sided avoids holes when the camera dips to water level. (A dedicated underside look is a later polish item, cf. legacy V3 C1.) |
| **Used with Water** (usage flag) | ON if the compiler requests | Some SLW/water paths require it; harmless to enable |
| **Tangent Space Normal** | **OFF**, OR ensure ProcMesh tangents exist | See §4 — ProceduralMeshComponent tangent caveat |

### 3.2 Transparency + depth-based color (shallow → deep)  — *MVP*

The headline "this is water" cue after reflection. Two cooperating mechanisms:

- **SLW absorption/scattering** gives physically-based depth tint inherently: the deeper the water
  column the camera looks through, the more light is absorbed → deep water darkens/saturates. Drive via
  the SLW node's **Scattering Coefficients** (higher = thicker/milkier) and **Absorption Coefficients**
  (per-channel; tune so red absorbs fastest → the classic blue-green deep tint)
  ([SLW docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/single-layer-water-shading-model-in-unreal-engine)).
- **Explicit shallow→deep gradient** for art control: compute water depth as
  **`SceneDepthWithoutWater` − PixelDepth**, normalize through a `Divide` + `Saturate`, and `Lerp` a
  **ShallowColor → DeepColor** parameter pair into BaseColor / the scatter tint. Use
  **`SceneDepthWithoutWater`, NOT SceneDepth** — required for SLW because SLW is opaque and normal
  SceneDepth would read the water's own surface
  ([80.lv stylized water](https://80.lv/articles/how-to-build-stylized-water-shader-design-implementation-for-nimue),
  [Depth Material Expressions docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/depth-material-expressions-in-unreal-engine)).
- **Parameterize ShallowColor/DeepColor** as material params (not vertex color) so they're tunable and
  can be driven per-biome later. This sidesteps the sRGB-vertex-color decode issue entirely for water.

### 3.3 Reflection (Fresnel + Lumen)  — *MVP*

The single biggest "this is water" cue (legacy V3 §30.2).

- **Fresnel**: a `Fresnel` node (or `1 - dot(N,V)`) drives reflection strength up at grazing angles.
  Use it to blend reflection in, and **cap it** with a `ReflectionStrength` param so grazing angles
  never blow out (the exact mistake the Godot V3 plan called out in its Phase 2).
- **Lumen reflections** provide the actual reflected sky+terrain automatically — SLW is supported by
  Lumen reflections. **KNOWN CONSTRAINT (cite + design around it):** as of UE5.4+, SLW's roughness does
  **not** drive Lumen reflection blur — Lumen forces **mirror reflections** regardless of the Roughness
  input; roughness only offsets reflection *brightness*
  ([Epic forum: SLW + Lumen reflections](https://forums.unrealengine.com/t/single-layer-water-material-does-not-seem-to-support-ue5-lumen-reflections/244571),
  [worldofleveldesign SLW problems](https://www.worldofleveldesign.com/categories/ue5/single-layer-water-problems-solutions.php)).
  - **Design implication:** we get crisp mirror reflections on water. For our *flat-topped cubic*
    water that is largely fine and even on-brand (calm, glassy ponds). The wave **normal map (§3.5)**
    is what breaks the perfect mirror into believable ripple — i.e. ripple comes from perturbing the
    reflection vector via normals, not from roughness blur. This is the correct lever for us anyway.
  - If a large lake's mirror reflection ever looks wrong, the documented fallbacks are a **planar
    reflection** actor or a screen-space reflection pass — defer unless a beauty-shot demands it.

### 3.4 Refraction (distortion of what's under the surface)  — *Phase 2*

- Set **Refraction Mode = Pixel Normal Offset** (not Index of Refraction). PNO is the correct choice
  for **large flat water surfaces**: it offsets refraction by how much the per-pixel (normal-map)
  normal differs from the vertex normal, giving wave-like distortion **without** the off-screen-read
  artifacts that IOR produces on big flat planes
  ([Refraction using Pixel Normal Offset docs](https://dev.epicgames.com/documentation/unreal-engine/refraction-using-pixel-normal-offset-in-unreal-engine),
  [Using Refraction docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-refraction-in-unreal-engine)).
- Feed the **same wave normal (§3.5)** that drives ripple. Keep the refraction scale tiny (≈1.02–1.06)
  — subtle is realistic; large values smear. **Note:** with PNO, no normal map = no refraction, so this
  feature is gated on §3.5 landing.

### 3.5 Animated normals + flow (ripples that move with the current)  — *Phase 2*

This is what makes cube-top water read as living water while staying flat (the cubic-identity lever).

- **Wave normals = sum of 2–4 octaves** of a water normal map, each panned at a different
  scale/speed/direction, blended (`BlendAngleCorrectedNormals`). Different frequencies → **no single
  tiling frequency → no checkerboard** (the exact artifact the Godot V3 Phase 1 fixed). Two `Panner`
  nodes, one with +speed and one with −speed, is the standard minimum
  ([2-layer panner pattern](https://www.worldofleveldesign.com/categories/ue4/materials-starter-content-water-instance.php),
  [Maxime Marier water formula](https://medium.com/@m.marier/the-formula-for-a-good-water-shader-for-games-in-unreal-4-ac72e5e86d49)).
- **CC0 normal source:** `design/UE5_ART_ASSETS.md` already earmarks Poly Haven `rocky_terrain_02`
  `nor_gl` 4K as a CC0 wave-detail normal (import sRGB OFF, BC5 Normalmap, Flip Green OFF). One texture,
  panned at multiple scales. Procedural FBM noise (the Godot route) is the asset-free alternative if we
  want zero downloads.
- **Drive the pan direction from the SIM FLOW, not just procedural noise.** Our mesher already feeds
  the per-cell flow vector into **UV1** (§1.2). In the material, read `TexCoord[1]` → that is
  `(flow_x, flow_z)` per vertex; use it to **bias the Panner direction** so a river's ripples scroll
  downstream and a still pond's don't move. Still cells carry `(0,0)` → fall back to a gentle default
  ambient ripple so calm water still shimmers. This is a real differentiator most voxel games lack and
  it is **already plumbed end-to-end** — only the material side is missing.
- **Wave intensity** via a `FlattenNormal` node + `WaveStrength` scalar param (calm vs choppy), wired
  to the weather/wind MPC later.

### 3.6 Shoreline + edge foam  — *Phase 3*

- **Depth-intersection foam:** reuse the depth value from §3.2 (`SceneDepthWithoutWater − PixelDepth`).
  Where it → 0, water meets terrain/objects → draw a **foam band**: `1 - saturate(depth / FoamWidth)`,
  multiplied by a panning foam noise texture, `Lerp`ed as a bright `FoamColor` into BaseColor/Emissive
  ([single-layer-water foam thread](https://forums.unrealengine.com/t/single-layer-water-foam/148602),
  [Maxime Marier shore edge](https://medium.com/@m.marier/water-shader-update-01-shore-edge-fade-with-pixel-depth-offset-4fa7a61a4d69)).
  Keep `FoamWidth` small so only true shore edges foam, not whole shallow ponds (the V3 Phase 3 lesson).
- **Optional sim-driven foam (better, Phase 3b):** the sim *knows* which cells are moving (flow ≠
  STILL) and which are shallow (level 1–2). We can pass a per-vertex **"foam/edge weight"** in a free
  vertex channel (§4) so foam appears on *flowing* water and at the *advancing front*, not just on a
  depth heuristic. This matches the Godot `WaterFoamManager` intent (foam on moving cells). Start with
  the pure-material depth foam; add the sim-driven channel only if the depth version reads weak.

### 3.7 Caustics on the lakebed  — *Phase 3*

- **Recommended (cheap, on-brand): SLW `Color Scale Behind Water` input.** SLW multiplies the luminance
  of surfaces below the water by this input — feed it a **panning caustic pattern** (two panning noise
  textures at different scales, blended with a `Sine`/`Min`) so the lakebed gets the dappled bright/dark
  caustic look directly from the water material, no extra lights
  ([SLW caustics via ColorScaleBehindWater](https://80.lv/articles/working-with-underwater-caustics-in-real-time),
  [cheap water caustics](https://medium.com/hri-tech/cheap-water-caustics-in-ue4-ee1d3ac0cae1)).
- **Alternative: a Light Function on the Sun** (UE5 Light Function Atlas bakes animated caustic tiles
  projected through the world) — more global but couples caustics to the directional light and is
  heavier ([Using Light Functions docs](https://dev.epicgames.com/documentation/unreal-engine/using-light-functions-in-unreal-engine),
  [underwater lighting UE5](https://80.lv/articles/look-how-you-can-set-up-underwater-lighting-in-unreal-engine-5)).
  **Recommend the `ColorScaleBehindWater` route** for v1 — local to the water material, cheaper,
  matches the legacy V3 recommendation (option (a), projected animated texture).

### 3.8 Sun specular / sparkle  — *Phase 2 (rides on the normals)*

- The wave **normal (§3.5)** + a **low Roughness** + the **Specular** input give a moving sun glint
  across the ripples automatically under the day/night sun. Because Lumen forces mirror reflection
  (§3.3), the *sharp* sun sparkle here comes from the **normal perturbation**, which is exactly what we
  want for a lively-but-flat cube-top surface. Tie roughness/specular to the weather MPC so water dulls
  in fog and sharpens after rain (per `UE5_ART_ASSETS.md` §3b).

### 3.9 Vertex-color fallback (the sRGB gotcha)

If BaseColor ever uses the mesher's baked water vertex color `{51,102,153}`, decode it sRGB→linear with
`Power(2.2)` like `M_VoxelTerrainV2` does — **or** (recommended) drive water color from
ShallowColor/DeepColor **material parameters** and ignore vertex color entirely. The parameter route is
cleaner and biome-tunable; vertex color stays a harmless fallback for the default material.

---

## 4. What CODE / MESH changes are needed vs what is pure material

**Good news: almost everything above is PURE MATERIAL.** The sim, the mesher's geometry, and the flow
plumbing already exist. Concretely:

### 4.1 Already done — no code needed (reuse as-is)

- **Flow direction per vertex → UV1.** Done (`WaterSurfaceMesher.h` `flow_xz_of_byte` +
  `MiraVoxelMesh.cpp` UV1 upload). The material reads `TexCoord[1]` for §3.5. **Zero new code.**
- **Separate water section + its own material slot.** Done (`FaceClass::Water` → `WaterMat`).
- **Sloped, fused surface geometry.** Done (corner-height blend).
- **Depth-based color & foam** — pure material (`SceneDepthWithoutWater`), **no mesh data needed.**
- **Refraction, reflection, normals, caustics, specular** — all pure material.

### 4.2 Tangent basis for the normal map (the one real mesh/upload caveat) — *needed for Phase 2*

A **tangent-space** normal map needs a tangent basis. `MiraVoxelMesh.cpp` currently leaves Tangents
empty and lets `ProceduralMeshComponent` derive them. Procedurally-generated meshes often have weak or
missing tangents, which breaks tangent-space normals
([ProcMesh tangent/normal-map notes](https://forums.unrealengine.com/t/recompute-tangents-and-normal-maps-i-have-found-a-solution/132852)).
**Two options, pick at Phase 2:**

- **(A) Supply explicit tangents for the water section.** Our water tops are predominantly +Y-facing
  flat quads, so a constant world tangent (e.g. +X) is trivial to emit per water vertex in the upload.
  Cheapest correct fix, water-section-only.
- **(B) Author the normals in WORLD space.** Set material **Tangent Space Normal = OFF** and use
  `DeriveTangentBasis` / world-space normal wiring — works regardless of mesh tangents
  ([world-space normal route](https://forums.unrealengine.com/t/tangent-space-normals-in-material-editor/420695)).
  Good fit because water is flat and world-aligned. **Recommend (B)** — no upload change at all, and it
  dodges the ProcMesh tangent fragility entirely. (Keep (A) in reserve.)

> Legacy note: the Godot rule was "never flip `bake_tangents`." The UE analogue is the same caution —
> don't fight the mesh's tangents; author water normals in world space (B) and the issue disappears.

### 4.3 Optional additive vertex channel for sim-driven foam — *only if Phase 3b is pursued*

If pure-material depth foam (§3.6) reads weak, add a per-vertex **foam/edge weight** float written by
the water mesher (the sim already knows flow≠STILL and level 1–2 = shallow front). Carry it in a spare
component of an existing vertex channel (e.g. UV1's unused capacity is full at 2 floats — use UV2, or
pack into vertex-color alpha which water doesn't otherwise use for AO). This is **additive and opt-in**,
mirrors the existing flow-vector pattern, and is the only place new Core mesher code might be warranted.
**Default plan: skip it; revisit after seeing depth foam in-engine.**

### 4.4 Summary table

| Feature | Pure material? | Code/mesh change? |
|---|---|---|
| Transparency / depth color | ✅ | none (`SceneDepthWithoutWater`) |
| Fresnel + Lumen reflection | ✅ | none |
| Refraction (Pixel Normal Offset) | ✅ | needs normals (§4.2) |
| Animated normals + flow scroll | ✅ | **none** — flow already in UV1; world-space normals (4.2-B) |
| Shoreline foam (depth) | ✅ | none |
| Sim-driven foam (optional) | ✘ | small additive mesher channel (§4.3) |
| Caustics (ColorScaleBehindWater) | ✅ | none |
| Sun specular/sparkle | ✅ | rides on normals |
| Tangents for normal map | — | world-space normals = none; or emit tangents (§4.2) |

---

## 5. Integration with day/night + atmosphere + the cubic aesthetic

### 5.1 Day/night + atmosphere (from `ATMOSPHERE_LIGHTING_SPEC.md`)

- **Reflection & color shift with the sun automatically.** SkyLight Real-Time Capture + Lumen mean the
  water's reflected sky and ambient tint track the moving sun/moon with **no per-frame water code** —
  golden-hour water goes warm, night water goes cool-blue, for free.
- **Locked exposure:** tune all water brightness (foam, specular, shallow/deep colors) at the fixed
  EV100≈11 anchor. Don't add bloom-bait bright foam that only reads at a different exposure.
- **Weather MPC hook:** drive **Roughness/Specular + wave-pan speed + WaveStrength** from the same
  Material Parameter Collection the weather/day-night controller writes (wind vector, wetness). Calm
  fog = duller, slower water; post-rain = sharper, choppier. Matches `UE5_ART_ASSETS.md` §3b.
- **Fog/aerial perspective** already hazes distant water cohesively with the terrain — nothing special
  needed; just confirm distant water doesn't fight the ExponentialHeightFog tint.

### 5.2 Keeping the cubic identity (non-negotiable)

- **No vertical wave displacement.** All surface motion is in the **normal map**, never in geometry —
  cube tops stay flat-ish (just the mesher's existing fill-level slope). This is the explicit reason we
  reject Gerstner/Water-plugin waves (§2.2).
- **Ripple = perturbed reflection + refraction**, foam = thin shore band, caustics = lakebed dapple.
  Together they read as "real water sitting in a blocky world," not "smooth AAA ocean" that would clash
  with the 10 cm cubes.
- **Sharp mirror reflection (Lumen's forced behaviour, §3.3) is on-brand**: calm voxel ponds looking
  glassy is correct; the normal map adds just enough break-up.

---

## 6. Phased rollout (MVP → polish), with effort + risk

Every phase is a **designer in-engine visual check** — water look is GPU-only; the headless clang
harness only proves Core (mesher) still compiles. No phase changes the sim. Phases are independently
shippable; stop whenever the look is "good enough."

### Phase 0 — Material scaffold + assign (prep)
Create `M_VoxelWater` as Single Layer Water / Opaque / Two-Sided, assign to `FaceClass::Water`, set the
Lumen-friendly defaults (§3.1). Confirm it still renders (flat for now). **Effort: S. Risk: low.**

### Phase 1 — MVP: transparency + depth color + Fresnel reflection
- Depth-based ShallowColor→DeepColor via `SceneDepthWithoutWater` (§3.2).
- SLW scattering/absorption tuned for blue-green deep tint.
- Fresnel-blended, capped Lumen mirror reflection (§3.3).
- **This alone transforms the water** from flat blue to readable, reflective, depth-tinted water.
- **Effort: M. Risk: low–med** (depth read must use `SceneDepthWithoutWater`; the Lumen-mirror
  constraint is known and accepted). **No code changes.**

### Phase 2 — Living surface: animated normals (flow-driven) + refraction + sun sparkle
- Multi-octave panned water normal, **flow direction from UV1** (§3.5), world-space normals (4.2-B).
- Pixel-Normal-Offset refraction fed by that normal (§3.4).
- Low roughness + specular → moving sun glint (§3.8).
- **Decide §4.2 here**: world-space normals (recommended, no code) vs emitting tangents.
- **Effort: M–L. Risk: med** (normal authoring + the tangent decision; non-tiling tuning to avoid the
  checkerboard the legacy plan fought). Likely **no code** if we take 4.2-B.

### Phase 3 — Polish: shoreline foam + lakebed caustics
- Depth-intersection foam band (§3.6) with panning foam noise.
- Caustics via SLW `ColorScaleBehindWater` (§3.7).
- **Effort: M. Risk: low–med.** **No code** for the depth/caustics route. (Phase 3b sim-driven foam is
  optional and is the only part that touches the mesher — defer unless needed.)

### Later / out of scope for this plan
- Underwater **camera** look (submerge fog, god-rays, screen wobble, caustics-from-below) — a separate
  doc; this plan is the **above-water surface**.
- Planar/SSR reflection fallback if mirror-only ever looks wrong on a big lake (§3.3).
- Substrate migration of the water BSDF (only if the whole project opts into Substrate).
- Weather-MPC fine coupling (lands with the weather state machine).

### Risk register (top items)
1. **Lumen forces mirror reflection on SLW (roughness ignored).** *Known, cited, designed around* —
   ripple comes from normals, not roughness blur. Accept for v1.
2. **ProcMesh tangents for normal maps.** Mitigated by world-space normals (4.2-B) — no upload change.
3. **Depth read on SLW.** Must use `SceneDepthWithoutWater`, not SceneDepth — easy once known.
4. **Normal tiling/checkerboard.** Mitigated by multi-octave panning at different scales (the legacy
   fix), not a single frequency.
5. **Translucency vs Lumen caveats** — sidestepped entirely by choosing SLW (Opaque) over a Translucent
   surface.

---

## 7. Sources

UE5 docs:
- [Single Layer Water Shading Model — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/single-layer-water-shading-model-in-unreal-engine)
- [Water System — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/water-system-in-unreal-engine)
- [Water Body Actors — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/water-body-actors-in-unreal-engine)
- [Water Meshing System and Surface Rendering — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/water-meshing-system-and-surface-rendering-in-unreal-engine)
- [Refraction Using Pixel Normal Offset — UE5.7 docs](https://dev.epicgames.com/documentation/unreal-engine/refraction-using-pixel-normal-offset-in-unreal-engine)
- [Using Refraction — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-refraction-in-unreal-engine)
- [Depth Material Expressions — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/depth-material-expressions-in-unreal-engine)
- [Using Light Functions — UE5.7 docs](https://dev.epicgames.com/documentation/unreal-engine/using-light-functions-in-unreal-engine)
- [Overview of Substrate Materials — UE5.7/5.8 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-substrate-materials-in-unreal-engine)
- [Shading Models — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/shading-models-in-unreal-engine)

Community / technique:
- [SLW does NOT support Lumen rough reflections (forces mirror) — Epic forum](https://forums.unrealengine.com/t/single-layer-water-material-does-not-seem-to-support-ue5-lumen-reflections/244571)
- [SLW directional-light hard-shadow fix — World of Level Design](https://www.worldofleveldesign.com/categories/ue5/single-layer-water-problems-solutions.php)
- [SLW pool water material walkthrough — World of Level Design](https://www.worldofleveldesign.com/categories/ue5/single-layer-water-pool-still.php)
- [Stylized water shader (SceneDepthWithoutWater, foam) — 80.lv](https://80.lv/articles/how-to-build-stylized-water-shader-design-implementation-for-nimue)
- [Single-layer water foam — Epic forum](https://forums.unrealengine.com/t/single-layer-water-foam/148602)
- [Shore edge fade with pixel depth offset — Maxime Marier](https://medium.com/@m.marier/water-shader-update-01-shore-edge-fade-with-pixel-depth-offset-4fa7a61a4d69)
- [The formula for a good water shader — Maxime Marier](https://medium.com/@m.marier/the-formula-for-a-good-water-shader-for-games-in-unreal-4-ac72e5e86d49)
- [2-layer panner water material — World of Level Design](https://www.worldofleveldesign.com/categories/ue4/materials-starter-content-water-instance.php)
- [Working with underwater caustics in real-time (ColorScaleBehindWater) — 80.lv](https://80.lv/articles/working-with-underwater-caustics-in-real-time)
- [Cheap water caustics — Hristo Enchev / Medium](https://medium.com/hri-tech/cheap-water-caustics-in-ue4-ee1d3ac0cae1)
- [Underwater lighting in UE5 — 80.lv](https://80.lv/articles/look-how-you-can-set-up-underwater-lighting-in-unreal-engine-5)
- [ProcMesh tangents / normal maps — Epic forum](https://forums.unrealengine.com/t/recompute-tangents-and-normal-maps-i-have-found-a-solution/132852)
- [Tangent vs world-space normals in the material editor — Epic forum](https://forums.unrealengine.com/t/tangent-space-normals-in-material-editor/420695)
- [Substrate production-ready/default in 5.7 (new projects) — Sprintermax / X](https://x.com/Sprintermax/status/1988647594902671809)

Project-internal:
- `Source/MiraThalVoxel/Public/Core/WaterSurfaceMesher.h` (surface mesh + flow→UV1)
- `Source/MiraThalVoxel/Public/Core/WaterByteCodec.h` (level + flow byte)
- `Source/MiraThalVoxel/Public/Core/FiniteWaterCore.h` (the sim — untouched)
- `Source/MiraThalVoxel/Public/Core/VoxelColor.h` (flat water base_color)
- `Source/MiraThalVoxel/Public/Core/MeshTypes.h` (`FaceClass::Water`, `MeshVertex.flow_x/flow_z`)
- `Source/MiraThalVoxel/Private/MiraVoxelMesh.cpp` (UV1 flow upload; empty tangents → PMC derives)
- `Source/MiraThalVoxel/Private/VoxelChunkActor.cpp` (per-section material binding)
- `design/UE5_VOXEL_MATERIAL_SETUP.md` (`M_VoxelWater` placeholder; sRGB/ProcMesh gotchas)
- `design/UE5_ART_ASSETS.md` (CC0 water normal; SLW recommendation)
- `ue5/MiraThal/design/ATMOSPHERE_LIGHTING_SPEC.md` (locked exposure, day/night, Lumen settings)
- `design/UE5_RENDERING_STRATEGY.md` (bands, per-face color, Lumen budget)
- `design/WATER_SHADER_V3_PLAN.md` (legacy Godot water look being ported)
</content>
</invoke>
