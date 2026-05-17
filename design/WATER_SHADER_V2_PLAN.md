# Water Shader V2 — calmer waves + depth-fade transparency

> **⚠ ARCHITECTURE SUPERSEDED 2026-05-16 by `design/WATER_VOXEL_V2_PLAN.md`
> (Minecraft-model water).** The chunked-mesher / horizon-plane split
> this doc iterates on is **deleted**. The *shader itself*
> (`water.gdshader` v8 + `water_material.tres`) is KEPT — it is now the
> material on the transparent water TYPE-block. The depth-fade tuning
> notes here (`depth_fade_distance` etc.) remain valid for that
> material. Ignore everything about WaterChunkMesher / horizon plane /
> chunked-vs-horizon unification — that system no longer exists.

**Status:** superseded-in-part, 2026-05-15. Successor sketch over `assets/shaders/water.gdshader` (75 lines) and `assets/shaders/water_material.tres`. Touches no GDScript except the bootstrap that hands the player chunk-bottom Y to `WaterChunkMesher`.

## Goals

1. **Vertical wave amplitude lower.** Current `wave_amplitude_a = 0.08` + wind multiplier `(1 + wind_strength × 0.5)` means HEAVY_RAIN (wind 3.5) bumps amplitude to **0.22 m** — about 1.3 voxels of vertical displacement. Reads as choppy chop, not a body of water. Target: peak displacement under 0.06 m even in heavy weather.
2. **Depth-tinted transparency.** Looking down into a shallow pond, you should see the bottom clearly. Looking into deep water, blue saturates and view fades to near-black at some maximum view-distance through the column. Roland looking out across a deep ocean from a beach should see horizon blue, not the seafloor 50 m below.
3. **Submerged player still sees the surface.** The current `cull_disabled` mode exists for this reason — keep it; the depth-fade math must handle "thickness < 0" (camera below surface) gracefully.

## How Minecraft / industry shaders do this

The technique is **Beer-Lambert absorption driven by screen-depth thickness**:

1. Sample `DEPTH_TEXTURE` at `SCREEN_UV` → raw NDC depth of whatever opaque surface is *behind* the water from the camera's POV (the pond bottom, seafloor, or distant terrain).
2. Reconstruct that pixel's view-space Z (linear depth) using `INV_PROJECTION_MATRIX`.
3. Compare against the fragment's own view-space Z (the water surface Z).
4. The difference (`thickness`) is **how far the camera ray travels through water** before hitting the bottom — which is what determines how much light gets absorbed.
5. Apply Beer-Lambert: `transmittance = exp(-thickness × absorption_per_meter)`.
6. Blend: `final_color = lerp(scene_color_below, deep_water_color, 1 − transmittance)`.

At `thickness = 0` (shoreline) → transmittance = 1 → full scene_color_below = bottom visible.
At `thickness = absorption_depth` → transmittance = small → deep_water_color dominates → near-black.

The shader does not need to know about per-cell water depth from `WaterFlowManager`. The screen depth-texture sample already captures "how thick is the water along this view ray," which is exactly the right physical quantity. This is identical to how Minecraft's water + most stylized water shaders work in Godot 4.

## Specific changes

### 1. Lower wave amplitudes

```glsl
uniform float wave_amplitude_a : hint_range(0.0, 0.5) = 0.035;  // was 0.08
uniform float wave_amplitude_b : hint_range(0.0, 0.5) = 0.018;  // was 0.04
```

Also reduce the wind amplitude multiplier so weather can't pump waves into chop:

```glsl
float wind_amp = 1.0 + wind_strength * 0.20;  // was * 0.5
```

At max wind (5.0) this gives `wind_amp = 2.0` → peak displacement (0.035 + 0.018) × 2.0 = **0.106 m** in the absolute worst case, vs 0.22 m today. In typical OVERCAST (wind 1.0): peak ~0.064 m. CLEAR (0.4): peak ~0.057 m. Calm.

Update `assets/shaders/water_material.tres` to match.

### 2. Add screen-depth-based absorption

New uniforms:

```glsl
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Tunables — designer-facing in the inspector
uniform vec3 absorption_color : source_color = vec3(0.0, 0.35, 0.5);
  // Color subtracted from scene-below as ray traverses water.
  // Higher G+B values = less attenuation in blue+green = water reads blue.
uniform vec3 deep_water_color : source_color = vec3(0.02, 0.07, 0.12);
  // The color the water blends toward at maximum absorption. Near-black-navy.
uniform float absorption_depth : hint_range(0.5, 30.0) = 15.0;
  // Meters of water at which transmittance ≈ 5%. Tune for "how clear is the water."
  // 15 m = clearer ocean (designer choice 2026-05-15). Lower = murkier; 4 m = bog.
uniform float view_max_distance : hint_range(2.0, 100.0) = 40.0;
  // Hard cap on the linear thickness used for Beer-Lambert. Past this we're
  // fully at deep_water_color regardless of where the depth texture says.
uniform float shore_softness : hint_range(0.0, 2.0) = 0.6;
  // Smooths the depth = 0 boundary so shorelines don't read as a hard edge
  // (a known Minecraft criticism — shoreline pixel-step is jarring).
```

Fragment math (new, replacing the current crest-color-only output):

```glsl
void fragment() {
    // 1. Sample scene depth at this pixel's screen position.
    float scene_ndc_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;

    // 2. Reconstruct view-space Z for the scene pixel behind us.
    vec4 scene_ndc = vec4(SCREEN_UV * 2.0 - 1.0, scene_ndc_depth, 1.0);
    vec4 scene_view_pos = INV_PROJECTION_MATRIX * scene_ndc;
    float scene_view_z = -scene_view_pos.z / scene_view_pos.w;

    // 3. This fragment's own view-space Z.
    float water_view_z = -VERTEX.z;  // VERTEX is in view space in fragment

    // 4. Thickness = how far the camera ray travels through water before
    //    hitting an opaque surface. Negative thickness happens when this
    //    fragment is behind another transparent water surface — clamp.
    float thickness = max(scene_view_z - water_view_z, 0.0);
    thickness = min(thickness, view_max_distance);

    // 5. Soft shore: at very small thickness, blend out the wave-crest tint
    //    so shoreline reads as a smooth fade rather than a hard line.
    float shore_t = smoothstep(0.0, shore_softness, thickness);

    // 6. Beer-Lambert per channel.
    vec3 transmittance = exp(-absorption_color * thickness);

    // 7. Sample the scene color behind us (the pond bottom / seafloor as
    //    the camera sees it without water).
    vec3 scene_color = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

    // 8. Blend: scene_color attenuated toward deep_water_color by 1 - transmittance.
    vec3 absorbed = mix(deep_water_color, scene_color, transmittance);

    // 9. Surface wave-crest tint additive on top (already in vertex pass via COLOR.r).
    float crest_t = smoothstep(crest_threshold, 1.0, COLOR.r) * shore_t;
    vec3 surface_tint = mix(vec3(0.0), crest_color.rgb - absorbed, crest_t * 0.4);

    ALBEDO = absorbed + surface_tint;
    ALPHA = 1.0;  // we're doing manual blending via screen_texture sample
    METALLIC = metallic_amount;
    ROUGHNESS = roughness_amount;
}
```

Notes:
- `ALPHA = 1.0` because we're compositing the scene-below color ourselves via `screen_texture`. No depth_draw issues; no transparency sorting bugs.
- This requires `render_mode` to drop `blend_mix`. New: `render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;` — the shader is now technically opaque-blend even though it composites a transparent look.

### 3. Cull mode + sorting

Keep `cull_disabled` for the submerged-player-looking-up case. The depth-fade math handles thickness = 0 (camera below surface looking up) gracefully because `scene_view_z` (sky / underwater geometry) is always behind the surface.

### 4. Underwater fog (existing UnderwaterFilter improvement)

`UnderwaterFilter.gd` currently does a flat CanvasLayer tint. Recommend keeping it, but driving its **alpha** from water column depth at the player's position:

```
underwater_alpha = clamp(player_depth_into_water / 10.0, 0.2, 0.85)
```

Where `player_depth_into_water` = `surface_y_at_player_xz - player_y`. So head-just-under-the-surface reads as a 0.2 alpha tint (light), and 10 m down reads as a deep 0.85 tint (oppressive). Optional Phase B — does not block the surface shader changes.

### 5. Performance

The new fragment shader adds:
- 2 texture lookups (`depth_texture`, `screen_texture`) per fragment.
- 1 matrix-multiply (`INV_PROJECTION_MATRIX * vec4`) per fragment.

Both are standard cost in modern transparent water shaders. The bigger consideration is **fillrate**: every water-surface pixel pays this cost, and our `WaterChunkMesher` + horizon plane covers a lot of pixels. For Forward+ on the dev machine, this is well within budget — Godot's `glTF Water` demo uses the same pattern at 60 FPS on integrated GPUs.

The horizon plane (huge follow-player sheet visible at the world horizon) does NOT need the depth-fade machinery — depth at horizon is always near infinity, i.e. always "deep". It uses a separate `water_horizon.gdshader` that runs only the deep-water collapse of the main shader (`mix(deep_water_color, water_tint_color, fresnel)`, no `depth_texture`/`screen_texture` sample). This is both cheaper AND visually identical to the near shader for deep water — see the revised Phase 3 for why a flat tint here was rejected.

## Integration with WeatherManager v2

The water shader already has `wind_dir` + `wind_strength` uniforms. `WaterFlowManager.set_global_wind(...)` already drives them. With v2 weather + the reduced multiplier this naturally flows through:

- CLEAR (wind 0.4) → calm.
- HEAVY_RAIN (wind 3.0) → moderate chop, no pile-up into 0.22m peaks.
- ALPINE modifier adds +3.0 wind bonus → max wind 6.0 → `wind_amp = 1 + 6.0 × 0.20 = 2.2` → peak displacement ~0.117 m. Still under 1 voxel.

A future polish hook: WeatherManager could push a `surface_choppiness: 0..1` uniform that modulates the wave frequencies (higher = shorter, choppier waves), separate from amplitude. Not needed v1.

## Implementation phases

### Phase 1 — Calmer waves (15 minutes)

Edit `assets/shaders/water.gdshader` + `assets/shaders/water_material.tres`:

- `wave_amplitude_a` 0.08 → 0.035
- `wave_amplitude_b` 0.04 → 0.018
- Wind multiplier `* 0.5` → `* 0.20` in shader's vertex pass.

Acceptance: run `World3D.tscn` in CLEAR + HEAVY_RAIN, observe water surface — no visible 1-voxel-tall chop in heavy weather. The water reads as a moving surface, not pixel-art waves.

### Phase 2 — Depth-fade fragment

> **SUPERSEDED by v8 (2026-05-16).** The original Phase 2 math (and its
> v6/v7 implementation) was an `unshaded` shader that hand-composited
> the scene behind the water and lerped it toward a tint by depth. It
> had **no surface of its own** — no sky reflection, no sun specular,
> no base sheen — so tuned opaque it was a flat slab and tuned clear it
> was *invisible* (you saw straight through to the dry lakebed). A
> controlled experiment (horizon plane disabled: 250 chunked meshes
> present, zero visible water) proved this conclusively.
>
> **v8 is a proper lit transparent water shader** instead: a surface
> that always reads as water (base colour + Fresnel reflection toward
> `sky_reflection_color` + lit sun specular — shader is no longer
> `unshaded`), with real depth-driven `ALPHA` (Godot composites the
> bottom via normal alpha blending, not a manual `screen_texture`
> sample). Uniforms: `water_tint_color`, `deep_water_color`,
> `sky_reflection_color`, `fresnel_power`, `fresnel_strength`,
> `metallic_amount`, `roughness_amount`, `depth_fade_distance`,
> `shallow_alpha`. The first seven are the shared-look invariant with
> `water_horizon_material.tres`. `depth_fade_distance` is the headline
> "how clear is the water" dial.

Original Phase 2 test scenarios (still the acceptance bar for v8):

- Shallow pond carved into a hillside, ~2 m deep → can clearly see bottom.
- Mid-depth water 5 m deep → bottom visible but tinted blue.
- Deep ocean 30 m deep → near-black-navy, no bottom visible.
- Submerged player looking up → surface still visible, tinted like a ceiling.
- Looking across a deep ocean at a shoreline → fade smoothly from black-blue mid-water to opaque-blue at the shore (no hard shoreline line).

Acceptance: visually matches the user description ("very shallow ponds should be more transparent... deeper and deeper water bodies get darker and player vision only goes so far into eventually blackness").

### Phase 3 — Horizon plane: the PRIMARY depth-fade surface (REVISED again 2026-05-16, v6)

> **KEY FINDING (2026-05-16):** Mira's generator leaves sea-level basins
> *dry* — there are almost no water voxels. The chunked mesher only
> builds water where voxels exist, so it covers a tiny patch with hard
> chunk-aligned edges; ~95% of every visible "lake/ocean" is the horizon
> plane. The horizon plane is therefore **not** a distant backdrop — it
> is the main water surface for nearly the whole map.
>
> **Consequence:** the horizon plane must run the FULL depth-fade
> (`water_horizon.gdshader` v6 = byte-identical fragment to
> `water.gdshader` v8). It samples the scene depth and fades by the
> distance from sea level down to the dry basin floor — which visually
> *is* the lakebed. This gives depth-graded transparency across the
> entire map despite the absence of water voxels, and removes every
> seam because both meshes now run the same shader.
>
> Earlier Phase 3 revisions (flat tint; then "deep-water collapse")
> assumed the chunked meshes covered the near field. They never did —
> that assumption was the through-line error behind ~6 failed iterations.
>
> Superseded reasoning kept below for history:
>
> **Original Phase 3 (flat `deep_water_color` tint on the horizon plane)
> was implemented and rejected.** It produced a glaring proximity-based
> seam: near water rendered the rich depth-fade shader, distant water a
> flat dark-gray translucent sheet, and the boundary tracked the player
> at the chunked render radius. The designer requirement is explicit:
> *one water look, no player-visible split.* The flat-tint approach
> cannot satisfy that and is abandoned.

**Revised approach — `water_horizon.gdshader` v4:** the horizon plane
runs the *exact* deep-water collapse of `water.gdshader`. For deep water
(`column_depth` large) the near-water shader's output reduces to
`mix(deep_water_color, water_tint_color, fresnel)` with no depth-texture,
screen-texture, or seafloor dependency. The horizon plane is always deep
water, so running just that formula — with **shared parameters identical
to `water_material.tres`** — makes the two shaders produce the same color
for the same world position + view angle. They diverge only in shallow
water where the bottom is visible, which only occurs at shorelines inside
the chunked radius (near the player). Result: zero visible seam, and the
horizon shader is *cheaper* than the flat-tint v3 (no texture samples).

Companion change: `MESH_RENDER_RADIUS_M` 32 → 64 m so the shallow/deep
transition (the only place the two shaders can differ) sits past where
the eye tracks it on a gently sloping shore. Safe post-#214 (C++ mesher
+ adaptive 3 ms/frame time budget cap any cost as slower streaming, not
a frame spike). Single revert knob if a weaker machine struggles.

**Invariant:** the shared look params (`deep_water_color`,
`water_tint_color`, `fresnel_power`, `fresnel_strength`) MUST be kept
identical between `water_material.tres` and `water_horizon_material.tres`.
Tuning the water look means editing BOTH .tres files together.

Acceptance: walk toward and around a large water body — the surface is
one continuous color/feel from your feet to the horizon, with no ring
that flips appearance as you move. Framerate unchanged or better on
`CopperIslesTest.tscn` (the horizon shader now does less per fragment).

### Phase 4 (optional) — Depth-tinted UnderwaterFilter

`UnderwaterFilter.gd` queries `WaterFlowManager.get_water_level_at(player_xz)` → computes `player_depth_into_water` → sets the CanvasLayer alpha. 20 lines of script. Defer if Phase 1–3 already deliver the requested feel.

## Tuning values to revisit in playtest

- `absorption_color` (proposed `(0.0, 0.35, 0.5)`): controls *which* color the water absorbs the most. Higher R = water reads more blue-green; lower G+B = water reads darker. Algae-ish swampy water might want `(0.15, 0.2, 0.4)`.
- `absorption_depth` (default 15 m — clearer-ocean target locked 2026-05-15): the headline knob for "how clear is the water." 4 m = murky pond, 8 m = lake, 15 m = clear ocean, 20+ m = tropical-shallow. Author per-water-body via shader_parameter overrides on individual `MeshInstance3D`s if a scene needs murky swamp variation.
- `deep_water_color` (proposed near-black navy): the asymptote at maximum depth. Could push slightly more blue for prettier deep oceans.

## What this is NOT

- Not a full SSR (screen-space reflection) water shader. Reflections come from the existing `metallic_amount` + `roughness_amount` PBR pipeline and the WorldEnvironment's reflection probe / SSR. Not adding screen-space reflection math in this pass.
- Not refraction (Snell's law). The scene texture is sampled at the same SCREEN_UV — no offset for view-ray bending. Adding refraction is a 5-line follow-up if we want it (offset SCREEN_UV by `NORMAL.xy * refraction_strength`).
- Not foam at shorelines. The soft-shore math fades the wave-crest tint near zero thickness but doesn't draw foam streaks. Foam is a separate later effect.

## References

- `assets/shaders/water.gdshader` — current 75-line shader, target of rewrite.
- `assets/shaders/water_material.tres` — current uniform defaults.
- `scripts/WaterChunkMesher.gd` — owner of the horizon plane MeshInstance3D + per-chunk water meshes.
- `scripts/UnderwaterFilter.gd` — flat CanvasLayer tint to upgrade later.
- Godot Shaders absorption shader: `godotshaders.com/shader/absorption-based-stylized-water/` — the closest published reference; uses the same `vec3 transmittance = exp(-thickness * absorption)` formula.
- Godot Shaders depth-fade shader: `godotshaders.com/shader/stylized-water-with-depthfade/` — depth-texture sampling pattern.
- Minecraft Java + Sodium discussions on transparency sorting (`github.com/CaffeineMC/sodium`): why we want `ALPHA = 1.0` + screen_texture composite rather than alpha-blend.
