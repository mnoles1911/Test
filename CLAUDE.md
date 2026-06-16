# CLAUDE.md

Top-level navigator. **Each subdirectory has its own `CLAUDE.md` with detail for that area** — Claude Code loads the nearest one as you work.

> ## ⚙️ ENGINE: this branch is the **Unreal Engine 5 port** (active line of work)
>
> **This worktree/branch is the UE5 port of Mira-Thal.** The active engine is **Unreal Engine 5.7**
> (custom source build at `D:/UE5/UE_5.7`, GUID-registered), language is **C++** (no C#, no GDScript),
> rendering is **Lumen** (dynamic global illumination + reflections), **Nanite** (a cold-bake step,
> arriving in a later milestone), **Virtual Shadow Maps**, and **Chaos** physics. The world is built on
> our **own custom cubic voxel engine** (module `MiraThalVoxel`) at **10 voxels per metre** — i.e. each
> cube is **10 cm**. True blocky cubes are core visual identity, non-negotiable.
>
> **The original Godot build is heritage / legacy.** It still lives, intact, on the **`busy-cannon`
> branch** and is preserved as the trilogy's history — do **not** delete it. For *this* (UE5) line of
> work it is **superseded**: when a doc here describes "the engine," it means UE5. Godot detail is kept
> below and in the design docs for reference, clearly marked as the legacy line.
>
> **Start here for the current stack:** `design/UE5_TECH_STACK.md` (the canonical "what is the stack
> now" entry point — engine, modules, data model, verification, milestone status, tooling).
> **Current milestone status:** **M0 ✅, M1 ✅ (first chunk rendered under Lumen), M2 ✅ built tonight
> (brickmap + generated multi-chunk terrain + dig/carve loop)** — see `design/UE5_VOXEL_MESHER_PLAN.md`.

## Project

3D voxel narrative RPG (Veloren + Skyrim atmosphere). World is **Mira-Thal**, LOTR-scale fantasy. Game
one of a planned trilogy from a 200-page source manuscript. Real-time action combat, 1-vs-many, co-op 1-4.

**Engine (this branch): Unreal Engine 5.7, C++**, custom cubic voxel engine (`MiraThalVoxel`) at **10 cm
voxels**, rendered with **Lumen + Nanite (later) + Chaos** on a desktop target. The voxel world's
load-bearing logic lives in an **engine-agnostic C++ "Core"** (namespace `mira`, pure C++17, no engine
headers) so it can be unit-tested headlessly with a standalone clang harness before any Unreal build.

> **Legacy (Godot) — superseded by the UE5 port:** the previous build ran on **Godot 4.6.2 + Zylann
> Voxel Tools, Forward+**. That build is preserved on the `busy-cannon` branch as heritage. The "Legacy
> (Godot)" details further down this file describe how that build worked — keep them for reference, but
> new work on this branch targets UE5.

I am a writer + game designer, not a programmer. Explain code in plain English, comment heavily, prefer simple readable solutions.

## How this team works

**Fable** is the head game designer and coder. Fable owns the most complex, load-bearing work directly — architecture decisions, scale flips, water/gravity/parity invariants, shader fixes, sequencing, and all merge/commit decisions. Fable never commits subagent diffs blindly: every diff gets a review pass and the headless gate sweep before it lands.

Fable orchestrates subagents by relative task complexity to stay efficient:
- **Opus subagents** — meaty, self-contained chunks needing deep reasoning: new system builds, generator/LOD retunes, large framework restructures, complex cross-file refactors.
- **Sonnet subagents** — mechanical, well-specified multi-file work: constant de-duplication, documentation passes, headless gate sweeps, baseline re-bakes, straightforward pattern application across many files.

Subagents never commit or push. Each planned PR or task names its executor tier in its brief. When a subagent finishes, Fable reads the diff, runs the relevant headless selectors, then commits and pushes.

## Navigate

**UE5 port (active engine) — start here:**

| Going to work on... | Read |
|---|---|
| **The current tech stack (canonical entry point)** | **`design/UE5_TECH_STACK.md`** |
| UE5 voxel engine C++ (mesher, brickmap, chunk actors, Core) | `ue5/MiraThal/Source/MiraThalVoxel` (Core in `Public/Core/`) |
| Headless Core verification (the green gate) | `ue5/MiraThal/tests/standalone/build.sh` |
| UE5 port strategy / sequencing | `design/UE5_PORT_PLAN.md` |
| UE5 rendering decisions (Lumen / bands / per-face color) | `design/UE5_RENDERING_STRATEGY.md` |
| Why we own the mesher (cubic backend spike) | `design/UE5_VOXEL_BACKEND_EVALUATION.md` |
| UE5 mesher build plan + milestone ladder (M0–M8) | `design/UE5_VOXEL_MESHER_PLAN.md` |
| UE5 atmosphere art assets (CC0 sky/water/VFX) | `design/UE5_ART_ASSETS.md` |
| In-editor live bridge (spawn/inspect/screenshot via Claude) | `mcp-unreal` — see `design/UE5_TECH_STACK.md` §mcp-unreal |
| System design — combat, weather, skills, etc. (engine-agnostic) | `design/CLAUDE.md` |
| Narrative canon — world, characters, locations | `lore/CLAUDE.md` |
| "What shipped recently / what's in flight" | `MILESTONES.md` + the **Current state** block below |

**Legacy (Godot) — superseded; preserved on `busy-cannon`:**

| Going to work on... | Read |
|---|---|
| GDScript code / autoloads / gameplay (legacy) | `scripts/CLAUDE.md` |
| Godot scene files (.tscn) (legacy) | `scenes/CLAUDE.md` |
| Godot textures, models, audio, atlases (legacy) | `assets/CLAUDE.md` |
| Godot C++ GDExtension (legacy perf code) | `extensions/voxel_gen/CLAUDE.md` |
| Pipeline tools (TTS, headless harness, SFX gen) | `tools/CLAUDE.md` |
| Dialogic timelines, voice + style guides | `dialogue/CLAUDE.md` |
| "Non-negotiable Godot code rules" (legacy) | `design/PATTERNS_AND_GOTCHAS.md` |

## Current state (check before starting work)

> **UE5 port — current state (this branch):** **M0 ✅, M1 ✅, M2 ✅ (built tonight).** The UE5 voxel
> engine now generates multi-chunk terrain from a heightmap, renders it under Lumen, and supports a
> live dig/carve loop with Chaos collision. Texturing is **per-face solid color** (not an atlas) baked
> into vertex color — see `design/UE5_TECH_STACK.md` and `design/UE5_RENDERING_STRATEGY.md`. The
> milestone ladder (M0–M8) and what each gate proves live in `design/UE5_VOXEL_MESHER_PLAN.md`. For
> UE5 milestone history see `MILESTONES.md` (entries tagged **`[ue5]`**).

### Legacy (Godot) current-state snapshot — superseded by the UE5 port (kept for heritage)

The block below describes the **Godot** build's PR/feature state at the time of the port. It is the
state of the `busy-cannon` legacy line, **not** the UE5 branch. Read it for design intent / parity
reference, not as the live engine.

Update this block whenever a branch opens / closes. **Read it before assuming a feature is unbuilt.**

- **Open PRs / in-flight work:**
  - **PR #251 (10cm re-architecture — "Lay of the Land")** — world re-architected from 6 to **10 voxels/meter** (10cm voxels). Covers: `VoxelScale.gd` single source of truth; terrain scale flip; streaming/LOD retune (view_distance 864 vox, lod_count 5, collision to ~51.2m via `collision_lod_count=3`); mining rework (physical-volume anchor, S/M/F scroll-wheel presets, destroy preview); micro-voxel flora R4 (real destructible grass + flowers, ids 24–26, `FloraMaterial.gd`, `FloraMeshBuilder.gd`); far-grass impostors + wind sway (`FarGrassManager.gd`, `flora_sway.gdshader`); micro-detail D1–D4 (pebbles/twigs ids 27–28, dug-wall grain, grass trample, water foam `WaterFoamManager.gd`); distant skirt atlas-sampled color fix (no more pale seam); fog tune. See `design/VISION_VOXEL_10CM.md` + `MILESTONES.md`.
  - (Old multiplayer-stack drafts #182–#199 still exist but are dormant; ignore unless resuming MP.)
- **Default-OFF visual features (do not flip without designer direction):**
  - `GraphicsManager.rain_visuals_enabled = false` — rain shader + splash particles + wet-surface mod (PR #245, merged but gated).
  - `GraphicsManager.light_shafts_enabled = false` — per-state vol-fog god rays (PR #245, merged but gated).
  - `GraphicsManager.water_foam_enabled = false` — flowing-water foam particles on MOVING cells (PR #251, default OFF per new-visual-layer rule).
- **Default-ON visual features (exceptions to the default-OFF rule):**
  - `GraphicsManager.far_grass_enabled = true` — GPU-instanced far-grass impostor layer (~13–51 m). Defaults ON because it fixes a seam in the shipped default-ON voxel grass; designer-approved exception.
- **Recently merged:**
  - **PR #239 (Directional Melee v1, 2026-05-30)** — sword + shield, four-direction mouse-flick attacks (**flick TOWARD where the blow comes from** — UP=overhead, DOWN=thrust, LEFT/RIGHT=that-side sweep), charged 2× + feint, RMB tap=parry / hold=directional block + `auto_block` toggle, `ParryChainTracker`, `EnemyAttackPool` telegraphs, `HUDDirectionArrows` + `HUDCombatRadar`. **Lock-on was prototyped then removed — combat is pure free-aim.**
  - **PR #247 (Combat Phase 5 + entity streamer, 2026-05-30)** — charged-spear gibs + 0.15 s time-slow + camera kick + Phase 3 charge; `EntityRegistry`/`EntityStreamer` (folds in the closed #246). Gibs + melee coexist on `Goblin`/`Enemy3D`. CombatTest debug-kill is **F10** (F8 is the editor Stop shortcut).
  - PR #245 (weather rework framework — visuals default-off, audio envelope live), PR #244 (Phase K bundle — selection outline, cloud cohesion, lens flare, rainbow shader, DebugOverlay GRAPHICS sub-view).

## Deprecated / superseded (do NOT implement from these)

Files that still exist on disk but look canonical without being it.

- **`scripts/EmissiveLightManager.gd`** — v1 OmniLight3D-streaming emissive system. Still on disk as a fallback BUT parked at startup by `EmissiveBakedLightManager` (Phase J). New emissive work goes through the **baked** manager (3D-texture floodfill), not v1.

**Already deleted** (don't recreate; old design docs / comments may reference them but the files are gone):
- `scripts/WaterChunkMesher.gd` — deleted 2026-05-16 in the native-fluid pivot.
- `scripts/HorizonSkirt.gd`, `scripts/_dev/SkirtBaker.gd`, `assets/heightmaps/copper_isles_skirt.res` — retired 2026-05-22, replaced by streaming `DistantTerrainManager`.
- `design/WATER_VOXEL_V2_PLAN.md` — removed; `design/WATER_STAGE6_PLAN.md` is the actual record of the pivot.

## Directory conventions

- **`scripts/_dev/`** is production glue + dev tools — generator adapters (`CubicHeightmapGeneratorAdapter`), parity references (`GravityReference`, `EmissiveReference`), dev-scene bootstraps, F12 debug helpers. Actively used by `World3D.tscn` and the headless harness. **NOT throwaway.**
- **`scripts/_prototypes/`, `scenes/_prototypes/`** — actual throwaway / spike code. Don't pattern new work from here without checking it's current.

## Top-level reference files

- **`MILESTONES.md`** — one-line PR history (git log is source of truth).
- **`DESIGNER_TODO.md`** — manual setup + asset tasks for the designer.
- **`design/PATTERNS_AND_GOTCHAS.md`** — every non-negotiable code rule, scene hierarchy, autoload load order. Read before writing GDScript.
- **`design/PROFILER_AND_DIAGNOSTICS.md`** — read before guessing at perf issues.

## Non-negotiables — Legacy (Godot); see `design/UE5_TECH_STACK.md` for the UE5 rules

> These were the **Godot** build's non-negotiable code rules. On the UE5 branch the equivalents are:
> voxel writes go through the single edit gateway on `AVoxelWorld` (`CarveAtWorld`), the brickmap is the
> one authoritative store, and the engine-agnostic Core must pass the clang harness ("ALL HARNESSES
> GREEN") before any UE build. The Godot-specific rules below are kept for parity reference.

- Player input must gate on `_can_take_input()`. Voxel writes through `VoxelEditManager` only. Skill XP through `SkillManager` only. UI clicks via manual `_input` dispatch.
- Water type check via `WaterMaterial.is_water_type(t)`, never `== 5`. Voxel material lookup via `VoxelMaterialRegistry`.
- `CHANNEL_COLOR` must be 32-bit before chunks stream. `_generate_block` runs on worker thread (no SceneTree access). Never flip `bake_tangents`.
- Never call `RenderingServer.global_shader_parameter_add/_get/_get_list` (editor-only). Declare in `[shader_globals]`; runtime `_set` only.
- GDScript by default; **C++ GDExtension proactively for perf** (don't gate behind profiler). No C# ever. No systems built before needed.

## Maintenance

When adding a system / asset / lore / etc., update the relevant subdirectory's `CLAUDE.md` if a new top-level concept needs surfacing — most edits should NOT touch root. Update `MILESTONES.md` when a PR ships. Update `design/PATTERNS_AND_GOTCHAS.md` when a new load-bearing pattern surfaces.
