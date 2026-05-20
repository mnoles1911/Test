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
- **Phase 4 — polish:** caustics on submerged terrain, underwater
  fog/god-rays, tuning pass. Optional.

Phase 1 is the one that fixes the actual complaint and is the bulk of
the look. 2–4 are stacked enhancements, each independently shippable.

## Constraints carried forward
- Native Zylann fluid only (no custom mesher). Flow from `UV.y` code
  0–8 per `WaterMaterial`/the Zylann spec (already decoded in v9 fix).
- `transparency_index` ordering, collision-off, sink-swim model,
  bake_tangents-off — all unchanged.
- GPU-only validation → every phase is a designer in-engine gate;
  the headless harness only proves the shader compiles + structure.
