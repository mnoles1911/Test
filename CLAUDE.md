# CLAUDE.md

Top-level navigator. **Each subdirectory has its own `CLAUDE.md` with detail for that area** — Claude Code loads the nearest one as you work.

## Project

3D voxel narrative RPG (Veloren + Skyrim atmosphere), Godot 4.6.2 + Zylann Voxel Tools, Forward+ desktop. Real-time action combat, 1-vs-many, co-op 1-4. World is **Mira-Thal**, LOTR-scale fantasy. Game one of a planned trilogy from a 200-page source manuscript.

I am a writer + game designer, not a programmer. Explain code in plain English, comment heavily, prefer simple readable solutions.

## Navigate

| Going to work on... | Read |
|---|---|
| GDScript code / autoloads / gameplay | `scripts/CLAUDE.md` |
| Godot scene files (.tscn) | `scenes/CLAUDE.md` |
| System design — combat, weather, skills, etc. | `design/CLAUDE.md` |
| Narrative canon — world, characters, locations | `lore/CLAUDE.md` |
| Textures, models, audio, profiles, atlases | `assets/CLAUDE.md` |
| C++ GDExtension (perf code) | `extensions/voxel_gen/CLAUDE.md` |
| Pipeline tools (TTS, headless harness, SFX gen) | `tools/CLAUDE.md` |
| Dialogic timelines, voice + style guides | `dialogue/CLAUDE.md` |
| "What shipped recently / what's in flight" | `MILESTONES.md` + the **Current state** block below |
| "Non-negotiable code rules" | `design/PATTERNS_AND_GOTCHAS.md` |

## Current state (check before starting work)

Update this block whenever a branch opens / closes. **Read it before assuming a feature is unbuilt.**

- **Open PRs:** none in the combat / gameplay track — the whole combat slice shipped 2026-05-30. (Old multiplayer-stack drafts #182–#199 still exist but are dormant; ignore unless resuming MP.)
- **Default-OFF features (do not flip without designer direction):**
  - `GraphicsManager.rain_visuals_enabled = false` — rain shader + splash particles + wet-surface mod (PR #245, merged but gated).
  - `GraphicsManager.light_shafts_enabled = false` — per-state vol-fog god rays (PR #245, merged but gated).
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

## Non-negotiables (one-line summary; details in `design/PATTERNS_AND_GOTCHAS.md`)

- Player input must gate on `_can_take_input()`. Voxel writes through `VoxelEditManager` only. Skill XP through `SkillManager` only. UI clicks via manual `_input` dispatch.
- Water type check via `WaterMaterial.is_water_type(t)`, never `== 5`. Voxel material lookup via `VoxelMaterialRegistry`.
- `CHANNEL_COLOR` must be 32-bit before chunks stream. `_generate_block` runs on worker thread (no SceneTree access). Never flip `bake_tangents`.
- Never call `RenderingServer.global_shader_parameter_add/_get/_get_list` (editor-only). Declare in `[shader_globals]`; runtime `_set` only.
- GDScript by default; **C++ GDExtension proactively for perf** (don't gate behind profiler). No C# ever. No systems built before needed.

## Maintenance

When adding a system / asset / lore / etc., update the relevant subdirectory's `CLAUDE.md` if a new top-level concept needs surfacing — most edits should NOT touch root. Update `MILESTONES.md` when a PR ships. Update `design/PATTERNS_AND_GOTCHAS.md` when a new load-bearing pattern surfaces.
