# Graphics Pass — 2026-05-19 (branch `worktree-graphics-improvements`)

Re-scoped from a blind "graphics overhaul" prompt that was written without code
access. Most of that prompt was already implemented (ACES tonemap, SSAO, glow,
two-stage fog, custom day/night sky, sun+moon). This pass keeps only the
non-redundant, high-ROI work and excludes water entirely (the parallel
`water-shader-v3-p23` session owns it). Built autonomously; **all visual
verification batched into the checklist below.**

## What shipped (one commit per phase — clean rollback points)

> **Rebased 2026-05-20** onto origin/main on top of #231 (Water V3 Phases 2+3
> reflections + foam) and #232 (Water Phase 4a underwater fog/god rays/snap/
> bubble). Single conflict on `World3D.tscn` `Environment_1` tonemap block —
> resolved in favor of AgX (this branch's reason for existing); main's
> volumetric_fog_enabled=true / length=48 / UnderwaterFogMat_1 sub-resource /
> UnderwaterFogVolume FogVolume node / group taxonomy / Sun
> light_volumetric_fog_energy=0 all preserved. Commit hashes below are post-rebase.

| Phase | Commit | Change |
|---|---|---|
| 0 | `4b09247` | Doc note: `config/features "GL Compatibility"` is correct, NOT stale (intentional mobile fallback; desktop is forward_plus). No config changed — premise was false. |
| A-1 | `b218f5a` | Tonemap ACES→**AgX**, exposure 0.85→1.0, white 6.0; Adjustments on (contrast 1.05, sat 1.10). |
| A-2 | `f7976f3` | AgX counter-grade: saturation 1.10→**1.15**. Deliberately did NOT blind-rewrite the hand-eye-tuned per-hour sun/sky colors or weather fog — countered at the grade stage instead. |
| B | `5cc3dcc` | **SSAO** strengthened to block scale (r2.0/i2.0/power1.5/detail0.5/horizon0.06); **SSIL** enabled (r5/i2/sharp.98); glow threshold 1.4→1.1. Sun+Moon shadows: Orthogonal→**PSSM 4-splits**, blur 3.0→1.5, +normal_bias 1.0. |
| D | `8aca069` | **MSAA 3D 4×** + screen-space roughness limiter (kills jagged block edges, zero blur). |
| E | `894ae9d` | This document. |
| (debug) | `23eedfe` | Jump-to-key-times buttons in DebugOverlay (Midnight/Dawn/Midday/Dusk). |
| C | — *(no commit)* | **SHELVED — see below.** |

## Shelved / deviations (with reasoning)

- **Phase C (normal maps) SHELVED.** `World3DBootstrap.gd:657-667` documents that
  `bake_tangents=true` forces a vertex×4 tangent array on every model incl. the
  runtime-injected `VoxelBlockyModelFluid` water models (which don't supply one)
  → Vulkan rejects **every water chunk mesh**. Library-global, no per-model
  opt-out, GPU-only (un-verifiable headless). Flipping it would deterministically
  break the native-fluid water the parallel session is polishing. The plan's own
  gate said shelve-if-regresses; it regresses with certainty. **Viable future
  path:** derivative (`dFdx/dFdy`) or triplanar bump mapping via a custom terrain
  ShaderMaterial — no vertex tangents, never touches the fluid path. Non-trivial;
  deserves its own focused pass (see Follow-ups).
- **SDFGI left OFF (Phase B).** `FORWARD_PLUS_MIGRATION_TODO.md` documents it as
  low-ROI on this overhang-less heightmap. Optional toggle, see checklist.
- **TAA kept ON (Phase D).** Blind plan wanted it off; but Phase B strengthened
  SSAO/SSIL which TAA denoises on Forward+. MSAA 4× already fixes edge jaggies
  without blur. FXAA not added (mushy stacked on TAA). A/B is on the checklist.
- **Camera FOV unchanged (75)** — matches `CameraRig` combat-pinch base (75→71);
  changing the base desyncs the pinch. **CameraAttributes (DOF/auto-exposure)
  not committed** — auto-exposure fights the Phase A AgX fixed exposure and would
  confound your end test of AgX. Opt-in checklist item instead.

## END-OF-BUILD VISUAL CHECKLIST (run World3D.tscn in the editor)

Headless validated: project loads, extensions register, terrain streams, all
resources resolve (atlas/sky/fonts), zero failed-resource-loads, no parse or
property-not-found errors (spike PASS, exit 0). The Phase B/D Environment +
AA property names are all valid (would show "property not found" headless if
not). Everything below is GPU/visual and needs your eyes.

> Worktree provisioning note: this is a fresh git worktree; Zylann
> (`addons/zylann.voxel`, junctioned), the `voxel_gen` DLL, and the full
> `.godot/imported/` cache were seeded from the main checkout (all gitignored,
> never come through git). First editor open will be clean. Full procedure in
> the `project-worktree-bootstrap` memory.

**1. AgX overall (noon).** Expect natural, slightly softer highlights vs old
ACES; should NOT look gray/washed (Adjustments counter that). *If too flat:*
raise `adjustment_saturation`/`adjustment_contrast` in `World3D.tscn`
`Environment_1`. *If too dark/bright:* `tonemap_exposure` (currently 1.0).
*Hate AgX entirely:* `git revert 917bd47 7aae831` → back to ACES.

**2. Day cycle — dawn / dusk / night.** Step WorldClock. The per-hour sun/sky
colors were ACES-tuned and only globally saturation-compensated. *Watch for:*
dawn/dusk under/over-saturated; night too milky (AgX lifts blacks) or fine.
*Knobs:* `scripts/DayNightCycle.gd` — `SUN_COLOR_DAWN/DUSK` (L78-80),
`MOON_ENERGY_NIGHT` (L69), `SKY_*` (L83-90). Report which time looks off and how.

**3. Weather (force Overcast + Fog + Heavy Rain).** Fog colors were ACES-tuned.
*Knob:* `scripts/WeatherManager.gd` `STATE_PROFILES` fog_color (L64-113).

**4. SSAO/SSIL depth (Phase B).** Crevices between terraced blocks should read
darker/deeper; subtle sun/sky color bleed on faces. *Too dark/halos:* lower
`ssao_intensity`/`ssao_power`. *Shimmer when moving (esp. if you disable TAA):*
that's the TAA tradeoff — see item 7.

**5. Shadows (Phase B).** PSSM 4-split = sharper near shadows. Check **grazing
sun (early/late)** for shadow acne on flat block faces. *Acne:* raise Sun
`shadow_normal_bias` (W3D.tscn, currently 1.0). *Detached/peter-pan:* lower it.

**6. Block edges (Phase D).** Silhouettes against sky should be clean, not
stair-jagged, with NO loss of texture crispness. This is the MSAA 4× win.

**7. (Optional A/B) TAA vs crispness.** If textures/edges feel slightly soft in
motion: set `anti_aliasing/quality/use_taa=false` in `project.godot` and compare.
Trade: crisper but SSAO/SSIL may shimmer. Pick your preference; tell me.

**8. Water sanity.** bake_tangents was NOT touched, so water should be
unaffected — but glance at a shoreline for any new `_surface_set_data` /
mesh-array spam in Output. None expected. If present, something unrelated regressed.

**9. (Optional) SDFGI.** To try it: `Environment_1` add `sdfgi_enabled = true`.
Watch FPS (F3 profiler). Low expected return on this terrain; revert if it costs.

**10. (Optional) CameraAttributes.** If you want subtle far-DOF + auto-exposure,
say so — but decide AgX exposure (item 1) FIRST; auto-exposure overrides it.

Per-phase rollback is one `git revert <commit>` from the table.

## Testing round 1 — designer feedback (2026-05-20)

Full 15-item checklist run. Items 2,4,6,11–15 PASS. Items 8,13,14 PASS.
Fixed this round:
- **#1a brightness** (`0d6ea3f`) — world ~13% too bright → `tonemap_exposure` 1.0→0.87.
- **#5 sun/moon orb through terrain** (`0d6ea3f`) — `no_depth_test` false on
  SunMat/MoonMat; terrain now occludes the orbs incrementally.
- **#9 shoreline foam** (`9be5f32`) — foam ran at bare shader defaults (no `.tres`
  overrides existed). Added foam params to `water_material.tres`, cranked
  `foam_edge_dist` 0.5→2.5 + `foam_strength`→1.0 for an unmistakable band.
  Production-taste value ~1.0–1.5; dial in the `.tres`.
- **#1b LOD3+ whitish-grey flicker** (`0b6293d`) — diagnosed as texture aliasing:
  atlas had `mipmaps/generate=false` + material used plain `NEAREST`. Enabled
  atlas mipmaps + `NEAREST_WITH_MIPMAPS_ANISOTROPIC`. Watch for atlas tile-bleed
  at extreme distance (→ tile-padding follow-up); if flicker persists, secondary
  suspect is `lod_fade_duration` cross-fade dither.

New follow-ups surfaced by testing (flagged, NOT fixed):
- **#3 weather audio latency** — rain SFX start ~20 s after forcing a weather
  state via F1, and ~15–20 s to revert on clear. Weather/audio system, not
  graphics. Also: weather states (particles/effects/sounds) need a full polish
  pass before production — known, out of scope here.
- **#5b sun-orb residual** — over open water (no terrain to depth-occlude) the
  orb still hard-pops at the geometric horizon. Plus: god-rays scaled to the
  sun's above-horizon *fraction* is a real unbuilt feature, not just the orb.
- **#8 water reflections** — no sun/terrain mirror on water; current water is a
  Fresnel sky-sheen only (#231 Phase 2). True planar/SSR reflection = #231
  Phase 2b, deferred by design. Cloud reflections need dynamic clouds first.
- **#10 underwater god rays** — only visible looking up at the sun; stylized
  light shafts penetrating horizontally would be a #232 underwater enhancement.
- **Atlas tile-padding** — if mipmaps (#1b fix) bleed tiles at distance, add
  per-tile edge-extrude padding in `tools/build_texture_atlas.py`.

## Deferred follow-ups (flagged, not done)

- **LOD terracing / hard LOD seams** — the screenshot's single biggest visual
  problem; you deferred it this pass. `lod_distance` capped 128, `lod_fade_duration`
  Zylann-capped, 6 LODs, hard radial transitions. Cross-ref `memory`
  project_lod_pop_tiers. Deserves a dedicated pass. **The #1b flicker likely
  belongs to this pass.**
- **Normal maps via tangent-free shader** — the only water-safe route to
  per-pixel surface detail (derivative/triplanar bump in a custom terrain
  ShaderMaterial preserving NEAREST + alpha-scissor). Non-trivial; own pass.
- **CLAUDE.md / ART_DIRECTION updates** — CLAUDE.md milestone line **DONE**
  (2026-05-20 graphics-pass entry, plus a 2026-05-22 entry for Phases F/H/K).
  ART_DIRECTION "Colour pipeline & sky — LOCKED" note **DONE** (2026-05-22).

---

## Phases F / H / K — SHIPPED 2026-05-22 (PR #235)

Built autonomously, headless-gated per commit, with one batched in-editor
designer review at the end. The roadmap further down is kept for history
but is superseded by this section for F, H, and the night-sky slice of K.
Docs follow-ups landed as PR #236; the audio import sidecars as PR #237.

| Phase | Change |
|---|---|
| F | `scripts/graphics/ShaderProfile.gd` (Resource — one tier's render knobs; **no `class_name`**, path-preloaded so the headless harness still parses it, same rule as `WaterMaterial.gd`) + `scripts/graphics/GraphicsManager.gd` **autoload** (registered before `Settings`). Five tiers POTATO/LOW/MEDIUM/HIGH/ULTRA built longhand in `_build_profiles()`; the chosen tier persists to `user://graphics.json`; `apply_current()` pushes MSAA/TAA/SSAO/SSIL/SDFGI/glow/shadow-split/vol-fog into the live `WorldEnvironment` + root `Viewport` + every `DirectionalLight3D` (each step null-guarded — menu/headless safe). **HIGH is the default and mirrors `World3D.tscn` exactly** — first-run look unchanged. ULTRA adds SDFGI + 8× MSAA. `World3DBootstrap._ready()` calls `apply_current()` once the scene is in the tree. Settings UI gained a GRAPHICS QUALITY cycle button (Mining-Anchor pattern, manual `_input` dispatch). |
| H | Procedural volumetric clouds. The old `sky_blend.gdshader` was **extended** (panorama cross-fade untouched) then **renamed to `assets/shaders/sky_atmosphere.gdshader`** — a stale-compiled-shader-cache workaround (see the bug note below) that was kept. Asset-free hash-FBM clouds on a flat ceiling, drifting via TIME with a bounded sine gust, lit by the scene sun through the shader's built-in `LIGHT0` (noon glow / dawn-dusk warm / night blue — zero time-of-day wiring). `cloud_coverage` + `cloud_speed` added to all six `WeatherManager` `STATE_PROFILES` (CLEAR = 0 coverage = a genuinely clear sky) and pushed each tick via `DayNightCycle.set_cloud_coverage` / `set_cloud_speed`. Clouds thicken and speed up with the weather. |
| K (night-sky slice) | Procedural stars + aurora + nebula, drawn behind the Phase H clouds. **Stars:** seamless 3D-direction hash, rotate across the sky with the day cycle. **Aurora:** a confined ribbon (lat 0.22–0.34, ~29–50° elevation — narrowed hard from a near-whole-sky band), with a smooth 7-in-game-day colour drift through three anchors teal → green → violet, then loop. **Nebula:** a localised billowy blob — a squared radial glow around an anchor direction, FBM-textured in the anchor's tangent plane so it reads as round isotropic billows, not curtain streaks; constant colour; drifts 30 % of the azimuth per 7 in-game days. All three scale by an explicit `night_factor` `DayNightCycle` pushes every tick. |

### The bright-night-sky bug (root-caused after several wrong turns)

The night sky rendered as bright as midday for most of this pass. The
fix that stuck was **not** in the sky shader:

- Early theories — the shader inferring day/night from `LIGHT0` energy,
  a stale *compiled* shader cache, the Moon blasting volumetric fog —
  were each instrumented and then either fixed-but-insufficient or
  reverted as unconfirmed guesses. The `LIGHT0` inference was genuinely
  wrong and was replaced with the explicit `night_factor` uniform; the
  stale-cache theory forced the `sky_blend` → `sky_atmosphere` rename
  (kept, harmless, guarantees a fresh compile).
- A flat-grey `sky_debug` probe proved the rendered sky output was
  correct greyscale yet still *looked* light blue → something was being
  composited **over** the sky.
- **Real cause:** the `WeatherManager` fog override colour and
  `Environment.volumetric_fog_albedo` were never day/night-aware, so a
  constant pale fog washed the sky via `fog_aerial_perspective` +
  `volumetric_fog_sky_affect`. `DayNightCycle` now lerps the override
  fog colour toward `FOG_COLOR_NIGHT` and drives `volumetric_fog_albedo`
  from a day/night palette, both by `night_factor`. Midnight now reads
  genuinely dark; midday unchanged. Designer-confirmed.

Lesson: when a sky looks wrong, rule out the fog layers compositing
over it **before** touching the sky shader — a flat-colour debug probe
settles it in a single run.

### Still open after this pass

- **Phase K remainder** — only the night-sky slice shipped. Lens flare,
  world/selection outline, rainbow-after-rain, and per-weather-state
  light-shaft intensity are still unbuilt; pick off opportunistically.
- **Phase F preset rebalance** — only HIGH (the default) was visually
  verified. POTATO / LOW / MEDIUM / ULTRA need an in-editor tier-by-tier
  pass for visual cohesion — each tier should look like a deliberate
  step, not just HIGH with effects toggled off. Tracked as a
  `DESIGNER_TODO.md` Section 2 item.
- **Wind ambience** — the gust modulation added alongside the cloud work
  (`WeatherManager._update_wind_gust`, summed slow sines biased toward
  lulls) is a stopgap; wind audio wants a proper rework.
- **Phases G, I, J** — SHIPPED 2026-05-22; see the section directly below.

---

## Phases G / I / J — SHIPPED 2026-05-22 (PR #238)

The remainder of the Phase F+ roadmap, built in one pass on top of the
F/H/K work. One commit per phase; headless-gated; one batched in-editor
designer review (the checklist below).

| Phase | Change |
|---|---|
| G | `scripts/graphics/AtmosphereProfile.gd` — a Resource holding the 16 time-of-day colour anchors (sun / moon / sky-top / sky-horizon / fog / vol-fog albedo). DayNightCycle's scattered colour `const`s are gone; `_apply()` reads `_atmo.<field>`, resolved in `_ready()` from a new `atmosphere` export (null → a default profile that reproduces the shipped look exactly — no `World3D.tscn` edit needed). New `DayNightCycle.set_atmosphere_profile()` swaps the whole palette at runtime. **Deviation:** the roadmap also floated folding `WeatherManager`'s per-state fog in — NOT done; `STATE_PROFILES` is already a clean designer table where fog sits with ambient/wind/cloud, and splitting it would break cohesion for no gain. |
| I | `assets/shaders/terrain_voxel.gdshader` — a `shader_type spatial` shader replacing the 14 solid voxel models' shared StandardMaterial3D. It reproduces that material exactly (atlas albedo, 0.5 alpha-scissor, nearest-mipmap-anisotropic, matte, no metal/specular) and adds **tangent-free** per-pixel surface relief — a 3D-noise height field, normal bumped from screen-space derivatives (Mikkelsen surface-gradient). No vertex tangents → never touches `bake_tangents` → water-safe. This is the shelved Phase C goal achieved the only way that doesn't break the native-fluid water meshes. `VoxelMaterial.gd` gained emission + roughness data fields; `World3DBootstrap` builds the shared shader material and gives a model its own variant only when its VoxelMaterial is emissive or sets a non-default roughness (batching preserved for the common case). |
| J | `scripts/EmissiveLightManager.gd` — new autoload. Emissive voxels cast coloured light: it discovers them edit-driven (bulk-reads the region around every `VoxelEditManager.edit_applied`) plus a periodic vicinity sweep, clusters them on a coarse grid, and streams a capped set of coloured `OmniLight3D`s around the player. `copper_ore` is flagged emissive as the showcase. **Architecture (designer-approved):** real `OmniLight3D`s, NOT the roadmap's C++ BFS-floodfill-into-3D-texture. Forward+'s clustered renderer makes engine-native lights the right call here — the Minecraft baked-light technique solves a problem (no real-time lighting) this engine does not have. Trade-off: light is line-of-sight and does not wrap around corners. |

### END-OF-BUILD VISUAL CHECKLIST — Phases G / I / J (run `World3D.tscn`)

Headless-validated: project loads, every script parses, all three
shaders compile, `GraphicsManager` applies, `EmissiveLightManager`
activates. Everything below is GPU/visual and needs your eyes.

**G1 — Day cycle unchanged.** Step WorldClock through dawn / noon /
dusk / night (DebugOverlay jump buttons). Sky / sun / fog colours
should look *exactly* as before — Phase G was a pure code refactor, so
zero visible change IS the pass criterion. *If anything shifted:* a
value in `scripts/graphics/AtmosphereProfile.gd` drifted from the
original `DayNightCycle` const.

**I1 — Terrain surface relief.** Look at a big flat stone / dirt face
up close. It should now carry subtle micro-relief that catches the sun
— no longer a dead-flat uniform wall — with NO loss of the crisp
pixel-art texture. *Too strong / noisy:* lower `detail_strength` in
`assets/shaders/terrain_voxel.gdshader` (default 0.3). *Want more:*
raise it; `detail_scale` sets the relief feature size.

**I2 — Terrain otherwise unchanged.** Texturing, per-face tile
mapping, leaf alpha-scissor transparency, distant-LOD sharpness — all
should be exactly as before. The shader reproduces the old
StandardMaterial3D; any difference *other than* the new relief is a bug.

**J1 — Glowing copper ore.** Dig down into stone and mine into a
copper-ore vein (copper sits 0–1500 voxels altitude). The ore surface
should glow warm amber (Phase I emission) AND the tunnel around it
should be lit copper-amber — floor and walls, with colour bleed via
SSIL (Phase J's `OmniLight3D`s). *Too bright / dim:* tune
`EmissiveLightManager.light_energy_scale`, or `emission_energy` /
`emission_color` on `copper_ore.tres`. *Don't want copper to glow:*
set `emission_enabled = false` in `copper_ore.tres`.

**J2 — Streaming + cap.** Mine a long copper vein — expect several
cluster lights (one per coarse cell), not one per voxel. Walk ~30 m
away — distant cluster lights stream out, no perf cliff. F3 profiler:
`EmissiveLightManager` should be cheap.

### Designer verification — 2026-05-22 (PASSED)

Run in-editor by the designer after merge. **G** day-cycle and **I**
terrain relief read correctly; **J** glowing copper ore confirmed. One
bug found and fixed: the first build lit emissive copper *buried in
solid rock* — cluster lights are shadowless, so that brightness bled
up through the terrain as a radius that followed the player. Fixed so
only voxels with an air-exposed face register a light
(`_has_air_neighbor` in `EmissiveLightManager`); re-tested, gone.
Global illumination — the dark-shadowed-blocks the designer flagged —
is the **SDFGI** enabled by the **ULTRA** graphics tier; confirmed
good on ULTRA.

Phases G/I/J landed as a single squash commit — PR #238 (`e8dfac9`);
revert that commit to roll back the whole pass.

### Still open after this pass

- **Phase K remainder** — lens flare, world/selection outline,
  rainbow-after-rain, per-weather light-shafts (unchanged).
- **Phase J comprehensive discovery** — emissive voxels are found
  edit-driven plus a modest vicinity sweep. A whole-world emissive
  index (deep-cave glow known before you approach) is the part that
  would want a C++ bulk-scan — a future option if it is ever wanted.
- **Phase F preset rebalance**, **wind-ambience rework** — unchanged.

---

## Next graphics passes — Complementary-inspired roadmap (Phase F+)

Phases A–E above tuned Godot's native post stack. This section is the
forward roadmap: a re-scoped port of techniques studied from the
**Complementary Reimagined** Minecraft shader pack. It supersedes an
earlier informal 6-phase sketch — Phases A/B/D already shipped the front
half of that sketch (tonemap, SSAO/SSIL, AA), so only the items below
remain. Keep this as the single graphics roadmap; do **not** open a
parallel `SHADER_PORT_PLAN.md`.

**Licensing:** Complementary Reimagined is a proprietary, all-rights-
reserved pack (same posture as SEUS / Sildur's — see
`WATER_SHADER_V3_PLAN.md` § Licensing). **Technique study only, no code.**
We implement everything ourselves from the published behaviour.

Every phase below is GPU/visual work → each ends in an in-editor designer
gate (headless only proves it compiles). Ordered by dependency, not pure
ROI — H unblocks later water/sky work; J is the biggest single payoff.

- **Phase F — Quality-tier `ShaderProfile` resource.** **SHIPPED 2026-05-22
  (PR #235)** — see the "Phases F / H / K — SHIPPED" section above; the
  original spec is kept below for reference. A `ShaderProfile`
  Resource (POTATO / LOW / MEDIUM / HIGH / ULTRA) wired to the `Settings`
  autoload, driving the knobs Phases A/B/D introduced: MSAA level,
  SSAO/SSIL on/off, SDFGI toggle, shadow split count, glow, vol-fog
  density. Mirrors Complementary's profile system. This is the *only*
  un-built piece of the post stack — everything else shipped in A/B/D.
  Pure GDScript. **Effort: small.**
- **Phase G — `AtmosphereProfile` resource.** **SHIPPED 2026-05-22** —
  see the "Phases G / I / J — SHIPPED" section above. Extract the hand-tuned
  per-hour sun/sky colours from `DayNightCycle.gd` and per-state fog from
  `WeatherManager.gd` into an `AtmosphereProfile` Resource (the analog of
  Complementary's `lib/colors/colorMultipliers.glsl`). Decouples art
  tuning from code and lets weather states swap colour anchors cleanly;
  also the prerequisite for Water Phase 4c (per-biome underwater fog).
  Pure GDScript. **Effort: small–medium.**
- **Phase H — Volumetric clouds.** **SHIPPED 2026-05-22 (PR #235)** — see
  the "Phases F / H / K — SHIPPED" section above. A `shader_type sky` shader with
  marched cheap noise clouds, time-of-day + weather driven (layers over
  or replaces `sky_blend.gdshader`). Dependency unlock: the deferred
  follow-ups "cloud reflections on water" and "#5b god-rays scaled to the
  sun's above-horizon fraction" both need real clouds first. Pure
  `.gdshader`. **Effort: medium.**
- **Phase I — IPBR-style voxel materials + tangent-free surface detail.**
  **SHIPPED 2026-05-22** — see the "Phases G / I / J — SHIPPED" section above.
  Extend `VoxelMaterial` with emission + roughness fields (glowing ores /
  emissive blocks fall out for free). Implements the **shelved Phase C**
  goal the water-safe way: per-pixel surface detail via a tangent-free
  custom terrain `ShaderMaterial` doing `dFdx/dFdy` derivative or
  triplanar bump — which is exactly how Complementary generates normals
  (`lib/util/dFdxdFdy.glsl`). Never touches `bake_tangents`. GDScript +
  `.gdshader`. **Effort: medium–large.**
- **Phase J — Colored lighting (voxel floodfill).** **SHIPPED 2026-05-22**
  — see the "Phases G / I / J — SHIPPED" section above; built with
  engine-native `OmniLight3D`s rather than the C++ floodfill sketched
  here (designer-approved architecture call). The biggest single
  visual jump and the one piece that genuinely needs C++: a BFS floodfill
  from emissive voxels into a 3D storage texture, triggered on
  `VoxelEditManager.edit_applied`, scoped to a radius around the edit —
  the same shape of work as `VoxelGravityManager`'s flood-fill. C++
  GDExtension in `extensions/voxel_gen/` + thin GDScript adapter + a
  manager autoload that uploads the storage texture to a shader global;
  the terrain shader samples it for indirect block light. Forward+
  storage textures. **Effort: large.**
- **Phase K — Atmospheric polish.** **PARTIAL — SHIPPED 2026-05-22 (PR #235):**
  the night-sky slice (stars / aurora / nebula) is done; see the
  "Phases F / H / K — SHIPPED" section above. **Still open:** lens flare,
  world/selection outline, rainbow after rain, light-shaft intensity per
  weather state. Each a small, independent `.gdshader` / `canvas_item`
  task — pick off opportunistically.

**LOD terracing / hard LOD seams** (top item in Deferred follow-ups
above) is *not* in this roadmap — it is a voxel-streaming problem, not a
shader-look problem, and deserves its own pass first; it is currently the
single biggest visual issue and will undercut any of F–K if left.
