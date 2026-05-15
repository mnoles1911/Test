# Forward+/Vulkan Migration — Status

**Migration complete.** Landed in PR `feat/renderer-forward-plus` on 2026-05-13: desktop renderer flipped from `gl_compatibility` to `forward_plus`, BloodVFX pools converted from `PlaneMesh` to `Decal`. Tier 1 / 2 / 3 environment features (decals, SDFGI, SSR, BPTC textures, real-shadow pipeline) all enabled.

`Performance.TIME_PROCESS` (proc_us) is unreliable for p99 work — plateaus across many frames. **Use `engine.real_us` instead** (PR #207 fix). Forward+ baseline: 1.88 ms median / 10.88 ms p99 on World3D walk-test.

Migration cost (hardware counters — reliable across renderers): ~27 % more draws, ~18 % more prims, ~42 % more VRAM. Reasonable trade for the unlocked features.

## Captures available

- `design/captures/baseline_forward_plus_shadowq4.json` — post-flip baseline with `soft_shadow_filter_quality = 4`.
- gl_compat baseline JSON was lost mid-session. Re-capture from `main` if needed; recipe in `design/PROFILER_AND_DIAGNOSTICS.md`.

All captures from World3D scene running the same scenario: spawn → walk forward ~20 s → idle ~10 s. Analysis recipes in `design/PROFILER_AND_DIAGNOSTICS.md` → "Analyzing captures — Python recipes".

## Forward-looking

### Generator note — rock overhangs / arches not produced

Heightmap generators (cubic + copper isles) emit a strict 2D heightmap per XZ column — no negative-Y features, no overhangs, no arches. SDFGI has very little non-trivial GI to bounce through as a result; caves bounce light, but rock overhangs (which would give the most dramatic visual return from SDFGI) don't exist in the world.

Future generator tier (T7? T8?): a 3D Worley/perlin pass that removes voxels in plausible arch / overhang shapes, gated on slope and material. Most natural for stone material above a certain elevation.

Documented 2026-05-13 during Tier 2 acceptance check.

### Mobile renderer note

`rendering_method.mobile` left at `gl_compatibility`. Reconsider only if a mobile ship enters the roadmap. Game One is desktop / Steam.
