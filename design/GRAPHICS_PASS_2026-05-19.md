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

## Deferred follow-ups (flagged, not done)

- **LOD terracing / hard LOD seams** — the screenshot's single biggest visual
  problem; you deferred it this pass. `lod_distance` capped 128, `lod_fade_duration`
  Zylann-capped, 6 LODs, hard radial transitions. Cross-ref `memory`
  project_lod_pop_tiers. Deserves a dedicated pass.
- **Normal maps via tangent-free shader** — the only water-safe route to
  per-pixel surface detail (derivative/triplanar bump in a custom terrain
  ShaderMaterial preserving NEAREST + alpha-scissor). Non-trivial; own pass.
- **CLAUDE.md / ART_DIRECTION updates** — pending: apply the maintenance-table
  updates (palette/shader decision = AgX+lighting; milestone line) only AFTER you
  verify + this merges. Not claiming "done" pre-verification.
