# Forward+/Vulkan Migration — Follow-up To-Do

Landed in PR `feat/renderer-forward-plus` on 2026-05-13: desktop renderer
flipped from `gl_compatibility` to `forward_plus`, BloodVFX pools converted
from `PlaneMesh` to `Decal`. Baseline profiler captures live under
`design/captures/`.

These items were deferred from that PR. None are urgent; pick up whichever
gives the cleanest follow-up. Each entry includes the files involved, the
goal, the risk, and the acceptance check so a future session can land it
without re-discovery.

**Status post-investigation (2026-05-13):** items 1 and 2 below are
MOOT — the apparent proc_us regression they were chasing turned out
to be a `Performance.TIME_PROCESS` plateau artifact, fixed by the
`engine.real_us` measurement added in the migration PR. The actual
Forward+ frame time is healthy (1.88 ms median / 10.88 ms p99). Keep
items 3–9 as real follow-up work; items 1–2 can be deleted.

**Forward+ feature payoff (items 7–9 below) is the highest-value
remaining work.** With `engine.real_us` now telling the truth, you
can A/B SSIL / SSR / SDFGI / volumetric_fog one at a time and ship
whichever passes the visual-vs-cost bar. SDFGI is the most likely
visual win for a voxel world (bounced light into caves + onto
building undersides). BPTC textures (item 8) reclaim the +42 % VRAM
the migration costs.

---

## Tonight's investigation (2026-05-12 / 13) — TL;DR

**The "regression" was a measurement artifact.** The migration is healthy.

`Performance.TIME_PROCESS` caches the last sample and reports stale
values for many consecutive frames, polluting p99 with artifact data.
Observed: proc_us plateaued at 60 ms across 15+ consecutive frames
during walking. Histogram of exact common proc_us values showed 3.3 %
of frames hitting one identical value each — clear plateau pattern,
not real frame-time distribution.

Profiler.gd was patched mid-session to emit `engine.real_us` —
`Time.get_ticks_usec()` deltas between consecutive `frame_finalize()`
calls. That IS the real per-frame wall-clock time. Validation capture
(60 s World3D walk on Forward+ + shadow_q=2):

| metric | real_us reading | old proc_us reading |
|---|---:|---:|
| median | 1 876 µs (≈ 530 fps) | 11 421 µs |
| p95 | 4 837 µs | — |
| p99 | 10 878 µs (≈ 90 fps) | 40 704 µs (off by 4×) |
| p99.9 | 16 838 µs | — |
| max | 43 138 µs (3 frames / 21 390) | — |
| spike frames > 30 ms | 0.014 % | 3.78 % (artifact) |

**No tuning was needed.** Forward+ is healthy. The "tuning win" we
appeared to get from `soft_shadow_filter_quality 4 → 2` was largely
the same measurement artifact moving around. Real frame-time at
quality 4 was probably similar to quality 2; we just had no way to
see it clearly.

### Real per-renderer cost (the parts that ARE comparable)

`draws / prims / vram_mb` are hardware counters and reliable across
renderers. Forward+ migration costs:

| metric | gl_compat (lost capture, log-line numbers) | forward_plus shadow_q=2 |
|---|---:|---:|
| draws median | ~ 589 | 749 (+27 %) |
| prims median | ~ 1 448 226 | 1 713 712 (+18 %) |
| vram_mb median | ~ 376 | 535 (+42 %) |

Real cost of the migration: ~27 % more draws, ~18 % more prims,
~42 % more VRAM. Reasonable for unlocking Decals, SDFGI, SSR, BPTC,
and a real-shadow pipeline.

### Deferred from this session

- **Recapture gl_compat with the Profiler fix applied** for a real
  apples-to-apples real_us A/B. Skipped tonight because the auto-mode
  classifier blocked editing Profiler.gd on main without explicit
  authorization. Workflow: switch to main, apply the real_us diff
  from `feat/renderer-forward-plus`'s Profiler.gd as an uncommitted
  edit, capture 60 s World3D walk, copy out, revert.
- **Land the Profiler real_us fix on main as its own PR.** The fix
  is renderer-agnostic and should be available to everyone. The
  feat PR includes the diff; carry it forward when this branch
  merges, or split into its own PR first.

---

## 1. Verify shadow-filter tuning closed the gap

**File:** `project.godot` line ~270, `lights_and_shadows/directional_shadow/soft_shadow_filter_quality`.

**Why this exists:** the migration PR dropped this from 4 → 2 on the
guess that Forward+ executes the high-quality PCF for real where
gl_compat approximated it cheaply. Whether 2 is enough to recover the
proc_us p99 regression, or whether SSAO / clustered-light overhead is
the bigger contributor, is still open.

**Goal:** capture a 30 s World3D run at `quality = 2`; compare against
`baseline_forward_plus_shadowq4.json`. If draws drop substantially and
proc_us p99 improves, the migration's net perf claim is back on track.

**Risk:** sharper / blockier shadow edges. Visual-only — easy to revert
to `3` if `2` looks bad.

**Acceptance:** new capture's median draws drop toward the gl_compat
baseline (589); proc_us p99 drops below the gl_compat value (42 ms).

---

## 2. Investigate `detect_us +178%` regression

**File:** Zylann `VoxelLodTerrain` integration (`scripts/World3DBootstrap.gd`).

**Why this is surprising:** `detect_us` is Zylann's CPU-side octree walk
deciding which chunks need loading. Renderer choice should not affect
it. Yet the mean went from 176 µs to 489 µs. Hypothesis: with Forward+
pulling more LOD detail into view (clustered renderer effects), the
octree refinement runs more nodes per frame.

**Goal:** confirm or rule out by capturing with `terrain.view_distance`
explicitly clamped to the same value gl_compat naturally hit. If
`detect_us` normalizes, the regression is downstream of LOD selection.

**Risk:** none — pure investigation.

**Acceptance:** writeup added back to this file explaining the cause
and the fix (or "no fix needed, it's noise from the lost gl_compat
baseline").

---

## 3. Water shader `cull_disabled` → `cull_back` revisit

**Files:** `assets/shaders/water.gdshader` (lines 17–24),
`scripts/WaterChunkMesher.gd` (`_build_debug_water_material`, lines 250–282).

**Why it was set this way:** under gl_compatibility, transparency sorting +
back-face culling interacted poorly. The submerged-camera case (player diving
and looking up at the water surface) showed blank space instead of a tinted
ceiling, because the *underside* of the surface plane was culled. Setting
`cull_disabled` made it visible from both sides. A separate horizon material
keeps `CULL_BACK` + `render_priority = -1` for the distant water plane.

**Goal:** test whether Forward+ transparency sorting handles `cull_back`
correctly for the submerged-camera case. If it does, drop the dual-material
hack and unify on a single surface material.

**Risk:** submerged player sees blank space looking up through the surface.

**Acceptance:** dive in `World3D.tscn` water body, look up — should see a
tinted ceiling, not void. Also verify the distant horizon plane still draws
correctly behind the foreground water.

---

## 4. Particle material simplification

**Files:** `scenes/vfx/BloodBurst.tscn` (lines 42–69),
`scenes/vfx/DustBurst.tscn` (lines 42–48). Optionally
`scenes/vfx/BloodDrip.tscn` if it uses the same pattern.

**Why it was set this way:** under gl_compatibility, GPUParticles3D's
per-instance color from `ParticleProcessMaterial.color_ramp` only reached the
fragment shader when the mesh material had
`vertex_color_use_as_albedo = true + shading_mode = UNSHADED + transparency = ALPHA`
AND `albedo_color = Color(1, 1, 1, 1)`. Without that exact combo, particles
rendered default white/grey. Documented in `LESSONS_LEARNED.md` 2026-05-05.

**Goal:** test whether Forward+ supports the same gradient with a default
lit `StandardMaterial3D`, or with just `vertex_color_use_as_albedo` alone
(no UNSHADED, no forced alpha).

**Risk:** regress to white/grey particles. Easy to spot, easy to revert.

**Acceptance:** run `CombatTest.tscn`, kill a goblin, blood burst shows the
red→dark gradient with alpha fade. Same for dust impact on terrain hits.

---

## 5. Loading-screen `visible = false` hack revisit

**File:** `scripts/TransitionManager.gd`.

**Why it was set this way:** per `LESSONS_LEARNED.md` 2026-05-06, the loading
screen ran at <10 FPS / 150 ms worst-frame on gl_compatibility while chunks
streamed behind the curtain. Root cause was that HUDOverlay + JournalUI
CanvasLayers were still issuing draw calls every frame even while hidden by
the loading curtain. Workaround was explicit `visible = false` on those
CanvasLayers during the loading hold.

**Goal:** Forward+ should batch off-screen draw calls better. Test whether
the explicit hide is still needed; if not, remove it for cleaner control flow.

**Hard invariant to preserve:** do NOT pause `VoxelLodTerrain` / heavy
autoloads during the loading hold — the Zylann main-thread polling +
chunk-mesh upload work is precisely what the hold exists for. Only the UI
draw-call elision is under review here.

**Acceptance:** trigger a save→load cycle in `World3D.tscn`; loading screen
remains responsive (≥30 FPS, worst-frame <50 ms) without the explicit
`visible = false` toggle.

---

## 6. LOD0 culling tuning in `MainMenu.gd`

**File:** `scripts/MainMenu.gd`.

**Why it was set this way:** comment mentions "gl_compatibility serial
pipeline" — the LOD0 visible-set strategy was tuned for the
single-threaded render queue.

**Goal:** re-evaluate under Forward+'s clustered rendering, which parallelizes
the visible-set evaluation. The current strategy may be overly conservative
now.

**Acceptance:** main menu loads with no visible LOD pop, frame time matches
or beats pre-migration baseline. No content regressions.

---

## 7. Enable Forward+-exclusive environment features

**File:** `scenes/World3D.tscn` and `scenes/CopperIslesTest.tscn` WorldEnvironment nodes.

**Update 2026-05-13 — Tier 1 + 2 + 3 all landed in one PR** (branch
`feat/forward-plus-tier-1-2-3`).

**Tier 1 — atmosphere + AA** (both World3D + CopperIslesTest envs):
- `tonemap_mode = 3` (AGX) — proper HDR rolloff replaces linear clip
- `glow_enabled = true` (intensity 0.6, bloom 0.1, blend 1 / SOFTLIGHT) —
  natural bloom on sun disc, campfire OmniLight, goblin eye-glow
- `volumetric_fog_enabled = true` — density 0.015 / 0.012, length 80 m /
  120 m, anisotropy 0.2 (slight forward scatter), ambient_inject 1.0
- `anti_aliasing/quality/use_taa = true` + `use_debanding = true` in
  project.godot — Forward+ proper TAA cleans up voxel-edge aliasing,
  debanding smooths the new volumetric-fog gradients.

**Tier 2 — GI + reflections + VRAM reclaim:**
- `sdfgi_enabled = true` on both envs. World3D: 4 cascades + min cell
  0.2 m (~50 m range, cave-tuned). CopperIslesTest: 6 cascades + min
  cell 0.3 m (~200 m range, archipelago-tuned). Both: `use_occlusion`
  + `read_sky_light = true` + `bounce_feedback = 0.5` so sky light
  bounces into caves and building undersides without going runaway.
- `ssr_enabled = true` on both envs (max_steps 48, defaults
  otherwise). Most visible payoff is the water surface — should now
  reflect terrain + sky on top of the existing custom-shader waves.
- Atlas BPTC: `assets/voxels/texture_packs/default/atlas.png.import`
  flipped to `compress/mode = 2` + `metadata.vram_texture = true`.
  Source-tile PNGs left at lossless — they're build inputs for
  `tools/build_texture_atlas.py`, not runtime assets.

**Tier 3 — per-instance culling + LOD survey:**
- `meshes/generate_lods = true` already set by Godot 4.6 default on
  every imported FBX (`assets/models/goblin.fbx` + 4 animation files).
  Nothing to flip — confirmed during survey.
- `visibility_range_end` on ephemeral world entities (hard-cull, no
  fade because voxel-clean look is better with hard pop than dithered
  stipple at distance):
  - `scenes/enemies/Goblin.tscn` — Visual mesh 80 m, EyeGlow 50 m
  - `scenes/throwables/throwable_spear.tscn` — Shaft/Head/ButtCap 60 m
  - `scenes/throwables/powder_charge.tscn` — Visual 50 m
  - `scenes/voxel/FallingVoxelCluster.tscn` — Mesh 80 m
  - `scenes/vfx/BloodBurst.tscn` — particle node 50 m
  - `scenes/vfx/BloodDrip.tscn` — particle node 40 m
  - `scenes/vfx/DustBurst.tscn` — particle node 40 m
- Reflection probes deferred. No interior hub scenes (shrines,
  cathedrals, settlements) exist on disk yet; revisit when the first
  one is authored.

**Interaction notes for future-Claude:**
- WeatherManager's `set_fog_override` only writes `fog_density` /
  `fog_light_color` (height fog). It does NOT fight `volumetric_fog_density`.
  Future polish: have weather states scale `volumetric_fog_density` during
  HEAVY_RAIN / FOG for dramatic light shafts.
- SDFGI runs on the screen-space SDF buffer, so VoxelLodTerrain's edits
  ARE visible to it — newly carved caves get GI updates automatically as
  the chunks remesh.
- BPTC atlas import skips mipmap generation (the existing `mipmaps/generate
  = false` setting is preserved). Voxel atlases must not generate mips —
  they bleed across tile boundaries. Godot 4.6 supports BPTC without mips
  on Vulkan/Forward+.

**Bugs discovered during Tier 2/3 acceptance:**
- ✅ **Sun/moon orb rendering through terrain at horizon** — fixed in
  `DayNightCycle.gd`. SunMat / MoonMat have `no_depth_test = true` so
  the orb always renders on top; visibility was gated only on light
  energy which stays positive during DUSK (h=17–20). Added a
  `basis.z.y > -0.05` gate so the mesh hides once the celestial body
  drops below the horizon line.
- 🐢 **WaterFlowManager runaway near coast** — partial fix.
  `_gather_lateral_sources_buffered` now short-circuits on uniform-water
  chunks (Zylann's O(1) `is_uniform()` check) so ocean-interior chunks
  marked dirty by the 3×3×3 dirty-propagation around mining don't run
  the 4096-voxel scan + ~1000 spurious chunk-boundary-source
  classifications. Each spurious source previously fired 4 per-voxel
  cross-chunk `tool.get_voxel` calls in the spread loop — the dominant
  cost in the 800–1000 µs/frame peak observed 2026-05-13. Expect
  WaterFlowManager to drop back into the low µs/frame range after this.
- 🐛 **Visible water elevation rises during mining at the coast** —
  NOT YET FIXED. Distinct from the perf bug above. User reported the
  whole pond surface visually rose. Mechanically, the simulator only
  writes water DOWN (gravity) or sideways (lateral) — never UP — so
  the cause is likely either in `WaterChunkMesher._gather_surface_quads`
  (mistaken top-water-Y per column after a flow cell is placed) or a
  truncation bug where the stored 8-bit water byte loses tick bits 8+
  on writeback (the in-memory `_cells` carries 8 bits of tick, the
  byte carries 3, so `fed_tick` round-trips wrong after tick 7). Needs
  reproduction with `Profiler.gd capture_on_startup = true` and the
  capture JSON inspected for any flow byte written at a Y above the
  source row.

**Acceptance status:**
- Tier 1 (vol fog / glow / AGX / TAA): **verified visually 2026-05-13** —
  user confirmed the look is good, no tuning needed.
- Tier 2 / 3 (SDFGI / SSR / BPTC / visibility ranges): visual + perf
  capture still pending. Run a 60 s World3D walk and compare against
  `baseline_forward_plus_shadowq4.json`. Expect +3–6 ms p99 from
  SDFGI (~2–4 ms) + SSR (~1–2 ms) on top of the Tier 1 baseline. If
  worse, dials in order of cheapest revert:
  1. `sdfgi_cascades = 4 → 2` (halves SDFGI cost on World3D)
  2. `ssr_enabled = false` (water alone usually doesn't justify SSR)
  3. Last resort: `sdfgi_enabled = false`.

---

## 8. Texture import — BPTC over raw RGBA  ✅ done (Tier 2)

`atlas.png.import` flipped to `compress/mode = 2` on 2026-05-13.
Godot's reimport produced `imported_formats: ["s3tc_bptc"]`, confirming
BPTC was selected on Vulkan/Forward+.

Source-tile PNGs (`source/*.png.import`) intentionally left at lossless —
they're build inputs for `tools/build_texture_atlas.py`, never loaded
into VRAM at runtime, so converting them is wasted work.

**Acceptance check pending:** capture vram_mb in `engine.*` and compare
against the pre-BPTC baseline. Visual verification needed: walk the
terrain and watch for banding on dirt and grass tiles (smoothest
gradients in the atlas).

---

## 9. Decal blood pool follow-up — newly load-bearing (SDFGI now on)

**File:** `scripts/BloodVFX.gd` (`spawn_pool`).

SDFGI landed in the Tier-2 batch above, so this is now a live concern
rather than hypothetical. Decals may read incorrectly against GI-lit
surfaces — sky bounce can blow out the red, or shadow caves can crush
it to black.

**Goal:** kill a goblin in `CombatTest.tscn` outdoors (sky bounce) and
again inside the campfire alcove in `World3D.tscn` (occluded GI). Pool
color should read as dark red in both. If it doesn't, tune
`Decal.modulate_albedo` or `Decal.albedo_mix` — the API is on the
Decal node BloodVFX builds in `spawn_pool`.

**Acceptance:** pool color reads correctly in shadow and sunlight under
SDFGI.

---

## Captures available for A/B work

- `design/captures/baseline_forward_plus_shadowq4.json` — post-flip on
  `feat/renderer-forward-plus`, `soft_shadow_filter_quality = 4`
  (the original gl_compat carryover value).
- The gl_compat baseline JSON was lost mid-session. Re-capture from `main`
  if needed; recipe in `design/PROFILER_AND_DIAGNOSTICS.md`. The summary
  numbers from the lost capture are preserved in the "Tonight's A/B
  findings" table above.

All captures from the World3D scene running the same scenario: spawn → walk
forward ~20 s → idle ~10 s. Analysis recipes in
`design/PROFILER_AND_DIAGNOSTICS.md` ("Analyzing captures — Python
recipes").

---

## Generator note — rock overhangs / arches not produced

Heightmap generators (cubic + copper isles) emit a strict 2D heightmap
per XZ column — no negative-Y features, no overhangs, no arches. SDFGI
landed in PR #213 has very little non-trivial GI to bounce through as a
result; caves are confirmed bouncing light, but rock overhangs (which
would give the most dramatic visual return from SDFGI) don't exist in
the world.

Future tier (T7? T8?) for the generators: a 3D Worley/perlin pass that
removes voxels in plausible arch / overhang shapes, gated on slope and
material so we don't carve random holes in flat ground. Most natural
for stone material above a certain elevation.

Documented 2026-05-13 during Tier 2 acceptance check.

---

## Mobile renderer note

`rendering_method.mobile` left at `gl_compatibility`. Reconsider only if a
mobile ship enters the roadmap. Game One is desktop / Steam.
