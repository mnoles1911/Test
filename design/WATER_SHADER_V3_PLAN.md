# Water Shader V3 — SEUS/Sildur-class look (research + plan)

Goal: water that reads clearly *better than Minecraft*, in the spirit of
SEUS / Sildur's Vibrant Minecraft shaderpacks, on the native Zylann
fluid surface. Replaces the v9 analytic `sin+cos` ripple, which is
mathematically a regular diamond lattice → the heavy tiling /
checkerboard the designer reported (2026-05-19).

## Licensing (must respect)
- **SEUS** — proprietary, all-rights-reserved (Sonic Ether). NOT open
  source. Technique study only; **no code**.
- **Sildur's Vibrant** — custom, redistribution-restricted license.
  Technique study only; **no code**.
- **Veloren** — GPLv3. Study only; copying code would force GPL on us.
- Usable references: `godot-shaders` (MIT), Godot docs/tutorials,
  published graphics papers. We implement everything ourselves.

## The OptiFine question — answered
OptiFine/Iris give Minecraft a programmable deferred pipeline it
otherwise lacks (shadow pass, GBuffer, composite). **Godot 4 Forward+
already provides that.** No extension framework is needed; we just turn
on / tune Godot-native features:
- Screen-Space Reflections (WorldEnvironment).
- Screen refraction in-shader (`hint_screen_texture`).
- Depth texture (already used for depth-fade).
- SSAO / SSIL, volumetric fog, glow (WorldEnvironment).
- ReflectionProbe (fallback reflection where SSR has no data).
These are the "shaderpack-quality" enablers, native and free.

## What SEUS/Sildur-class water actually IS (techniques to replicate)
1. **Wave normals** = sum of 3–4 octaves of flow-mapped, domain-warped
   noise at different scales / speeds / directions. No single frequency
   → no tiling. (Fixes the reported artifact at the root.)
2. **Reflection** of sky + terrain on the surface (SSR or planar) — the
   single biggest "this is water" cue.
3. **Refraction** — sample the screen behind, offset by the wave
   normal, absorb/tint by depth (Beer-Lambert). We already have the
   depth-fade half.
4. **Sun specular** with roughness driven by the wave normal.
5. **Edge foam** — depth-delta against terrain → a foam band at
   shorelines / around objects.
6. Later polish: caustics on the lakebed, underwater god-rays/fog.

## Phased plan (each phase = one designer visual check; GPU-only, no
headless validation possible — headless only confirms compile)

- **Phase 1 (this branch) — kill the tiling + real water surface.**
  Rewrite `water.gdshader` → v10: analytic ripple replaced with
  **domain-warped FBM value-noise normals** (asset-free, no texture,
  no tiling), flow-mapped along the Zylann fluid flow vector;
  **screen-texture refraction** offset by that normal; keep the v8/v9
  depth-fade, Fresnel sky tint, lit sun specular, distance-gated
  LOD-seam suppression, and all F6 debug modes 0–5. No `.tres`/scene
  change. Designer check: no checkerboard, water reads like water,
  flows along current.
- **Phase 2 — reflection. REWORKED (2026-05-19).** First attempt (a
  screen-Y-flip "planar" hack + runtime env SSR) was WRONG: it pasted
  the upside-down framebuffer onto the water and washed it white
  (designer screenshot). Both removed. Reflection is now a CLEAN,
  correctly-oriented Fresnel sky sheen, capped by `reflection_strength`
  so grazing angles never blow out. **Phase 2b (deferred, real work):**
  true mirror-of-terrain reflection = a planar-reflection pass (second
  Camera/Viewport rendering the world mirrored about the water plane
  into a texture the shader samples) — the only correct way; a screen
  hack cannot do it. Pick up here if the designer wants actual
  terrain/sky mirrored on the water.
- **Phase 3 — edge foam. DONE (2026-05-19).** Shoreline foam from the
  depth delta (`thickness → 0` = water meets terrain/objects), tops-
  only (up_face), small `foam_edge_dist` so only true shore edges foam
  (not whole shallow ponds). Clean band (no crest-noise breakup yet —
  a later tuning option). Uniforms: `foam_color/edge_dist/strength`.
- **Phase 4a — underwater fog + god rays. DONE (2026-05-19).** Volumetric
  fog driven from `scripts/UnderwaterFilter.gd`: on submerge it tweens
  `WorldEnvironment.volumetric_fog_*` (density / albedo / emission) and
  the Sun `DirectionalLight3D.light_volumetric_fog_energy` between an
  at-rest atmospheric haze and an underwater preset, with the underwater
  values *lerped between `*_noon` and `*_night` anchors* every frame
  using `clamp(sun.light_energy / sun_noon_energy_ref, 0, 1)` as the mix
  factor (so visibility tracks `DayNightCycle.gd`'s sun-energy curve and
  god rays brighten/fade with the day). Co-exists safely with
  `DayNightCycle` — DNC only writes classic `fog_light_color` +
  `fog_density`, never `volumetric_fog_*`. Scene plumbing: WorldEnvironment
  in group `world_environment`, Sun in group `sun_light`,
  `volumetric_fog_enabled = true` in `scenes/World3D.tscn`. Tint
  `ColorRect` kept at alpha 0.10 as a cheap close-up colour grade.
- **Phase 4a-extended — back-face / variety / particulates / wobble.
  DONE (2026-05-19, PR #232 C1..C4).** Four layered improvements on top
  of the initial Phase 4a:
  - **C1 — water.gdshader back-face branch.** `if (!FRONT_FACING &&
    debug_mode == 0)` renders the underside as `deep_water_color` plus
    a sun-direction-driven bright spot (`pow(dot(view_world,
    -sun_direction_world), underside_sun_glint_power) *
    underside_sun_glint_strength`), modulated mildly by the wave-
    perturbed normal so the bright patch shimmers with the surface
    motion. Fixes the "looking up at the surface from below looks like
    a pale-blue ceiling with no motion" (designer screenshot
    2026-05-19). UnderwaterFilter pushes the live `sun_direction_world`
    each frame so the glint tracks day/night. Also: `underwater_fog_
    albedo_noon` set to `Color(0.02, 0.06, 0.11)` = `deep_water_color`,
    densities raised to 0.55/1.10, `volumetric_fog_length: 80 → 48`.
  - **C2 — animated noise FogVolume.** `assets/shaders/underwater_fog.
    gdshader` (`shader_type fog`) with 3 octaves of asset-free 3D value
    noise scrolling at different scales (1.0/1.9/3.7) and velocities,
    modulating `DENSITY` on top of the env baseline. Hosted by an
    `UnderwaterFogVolume` node (shape=WORLD, group
    `underwater_fog_volume`), toggled via `.visible` on submerge.
    Drifting denser/lighter patches → water feels alive.
  - **C3 — drifting particulates.** `GPUParticles3D
    UnderwaterParticulates` sibling of UnderwaterFilter under Player3D
    (group `underwater_particulates`). ~200 small unshaded billboards,
    slow upward drift, 8 s lifetime, mild turbulence. `local_coords =
    false` so the player swims THROUGH them (motes stay in world
    space). Toggled via `.emitting` (not `.visible`) so existing motes
    finish gracefully on surfacing.
  - **C4 — screen wobble + chromatic aberration.** `assets/shaders/
    underwater_overlay.gdshader` (`shader_type canvas_item`) on the
    TintRect. Noise-driven SCREEN_UV displacement (~6 px @ 1080p,
    0.6 Hz) + RGB sampled at tiny offsets in the wobble direction
    (~1.5 px CA). v1's `.color` remains as a fallback if the shader
    fails on a player's GPU.
- **Phase 4b — caustics on the submerged lakebed. PENDING.** Animated
  sun-through-waves projection on submerged terrain — the iconic
  dappled-light underwater look. Options: (a) projected animated
  caustic texture (orthographic projector pointing down, single tiled
  noise texture animated over TIME, used by every modern game's
  underwater scenes — see [NVIDIA GPU Gems Ch 2](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-2-rendering-water-caustics)); (b) procedural caustics in a
  post-process compositor pass. (a) is cheaper and easier; (b) is more
  physically motivated but heavier. Recommend (a). Requires a single
  ~256-tile noise texture (or generate procedurally). Estimated effort:
  small. Deferred 2026-05-19 by designer to keep PR #232 focused.
- **Phase 4c — per-biome fog/extinction. PENDING.** Read water-body
  biome at player position (river / lake / ocean / swamp / glacial)
  and shift the `underwater_fog_albedo_*` / `underwater_fog_density_*`
  anchors to match — green murk for swamps, ice-blue for glacial,
  brown tint for muddy rivers. The exports on UnderwaterFilter are
  already named so a biome map just feeds different presets. Needs:
  biome lookup API (probably from `WeatherLocationProfile` or a new
  water-body classification autoload). Deferred 2026-05-19.
- **Phase 4d — planar terrain reflection. PENDING (longer-term).**
  True mirror-of-terrain reflection on the water surface (a second
  Camera/Viewport rendering the world mirrored about the water plane
  into a texture the water shader samples). Reserved as "Phase 2b" in
  the original V3 plan. Note: only correct above-water-surface
  reflection at the moment is the Fresnel sky sheen (capped by
  `reflection_strength`). True mirror is the only correct way to see
  trees/cliffs reflected — a screen hack cannot do it.
- **Phase 4e — audio coupling. NOT PLANNED YET.** Underwater muffled
  audio mix (low-pass filter on the master bus, dampened SFX) +
  ambient bubble/current loop. Pairs naturally with the visual murk.
- **Phase 4f — per-pixel screen-space water lerp. DEFERRED (long-term,
  big-budget bar).** Today's submerge transition is a "whole-screen
  state flip" the frame the camera POINT crosses the water plane —
  same model as Minecraft. The C18 bubble-burst + the existing splash
  SFX mask the snap perceptually. The next tier (Sea of Thieves /
  Subnautica / RDR2 swamps) renders a second screen-space pass that
  identifies the water-surface intersection per view ray, then
  applies above-water vs underwater rendering DIFFERENTIALLY across
  the screen. The visible result: at the exact moment the camera is
  half-submerged, the player sees the screen bisected — above-water
  rendering in the upper half, underwater rendering in the lower
  half, with a wet refractive band at the water line.

  Components required:
    - Extra render pass / compositor effect that produces a per-pixel
      "is this view ray's near-intersection above or below water"
      mask, plus a water-line distance for the wet-band blend.
    - Two post-process variants (above-water look, underwater look)
      composed by that mask.
    - Refraction/distortion at the water line itself (Snell's law
      bending, surface tension shimmer).
  Cost: significant — additional render pass, more bandwidth, harder
    to tune on integrated GPUs. Voxel/blocky games almost universally
    skip this; the bisected-view effect reads as more "realistic
    simulation" than "stylized voxel world".
  Acceptance: scope when project has a competitive water-visuals
    goal vs photoreal games. Not before a milestone where art
    direction explicitly demands it.

Phase 1 is the one that fixes the actual complaint and is the bulk of
the look. 2–4 are stacked enhancements, each independently shippable.

## Constraints carried forward
- Native Zylann fluid only (no custom mesher). Flow from `UV.y` code
  0–8 per `WaterMaterial`/the Zylann spec (already decoded in v9 fix).
- `transparency_index` ordering, collision-off, sink-swim model,
  bake_tangents-off — all unchanged.
- GPU-only validation → every phase is a designer in-engine gate;
  the headless harness only proves the shader compiles + structure.
