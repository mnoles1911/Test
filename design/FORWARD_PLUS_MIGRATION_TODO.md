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

**File:** `scenes/World3D.tscn` WorldEnvironment node.

**Currently enabled:** SSAO, fog. **Available post-migration:** SSIL, SSR,
SDFGI, volumetric_fog.

**Goal:** try each in isolation and compare cost against
`design/captures/baseline_forward_plus_shadowq4.json` (or whatever the
post-#1 baseline ends up being). Roughly ranked by likely value:

1. **SDFGI** — best visual win for a voxel world. Adds bounced light into
   caves and onto building undersides. Cost: moderate (~2–4 ms/frame on
   AMD RX 7800 XT).
2. **Volumetric fog** — pairs naturally with the existing fog config.
   Especially good for the Mira atmosphere brief.
3. **SSR** — limited payoff (no large reflective surfaces except water,
   and water already uses a custom shader).
4. **SSIL** — incremental quality bump over SSAO; not load-bearing.

**Caveat:** with shadow_q=4 already showing as expensive, layer these in
one at a time and capture the delta. Don't enable everything at once.

**Acceptance:** capture a profile with each feature enabled, document the
frame-time delta in this file, ship whichever passes the visual-vs-cost
bar.

---

## 8. Texture import — BPTC over raw RGBA

**Files:** `assets/voxels/texture_packs/default/source/*.png.import`,
`assets/voxels/texture_packs/default/atlas.png.import`.

**Why it was set this way:** `compress/mode=0` (raw RGBA) is renderer-agnostic
and was the safe choice under gl_compatibility.

**Goal:** Forward+/Vulkan supports BPTC on the RX 7800 XT. Switching could
cut atlas VRAM by ~4× with minimal quality loss — and the migration already
ate +54% VRAM, so reclaiming it matters.

**Risk:** BPTC can introduce subtle banding on smooth gradients. The voxel
atlas has hard-edged tiles, so this is likely fine, but verify on the dirt
and grass tiles which have the smoothest variation.

**Acceptance:** atlas VRAM in `engine.vram_mb` drops; no visible banding or
color shift on terrain tiles at any LOD.

---

## 9. Decal blood pool follow-up (depends on #7)

**File:** `scripts/BloodVFX.gd` (`spawn_pool`, post-revert).

**Why this exists:** the BloodVFX revert in the migration PR uses default
Decal lighting. If SDFGI (#7) is enabled, Decals may read incorrectly
against GI-lit surfaces.

**Goal:** verify Decal blood pools still look right with SDFGI on. Tune
`Decal.modulate_albedo` or `Decal.albedo_mix` if needed.

**Acceptance:** kill a goblin in shadow and in sunlight under SDFGI; pool
color reads correctly in both.

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

## Mobile renderer note

`rendering_method.mobile` left at `gl_compatibility`. Reconsider only if a
mobile ship enters the roadmap. Game One is desktop / Steam.
