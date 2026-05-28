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

- **Open PRs:**
  - **#247 `combat/phase-5-gibs`** — charged-spear gibs + 0.15 s time-slow + camera kick + Phase 3 charge mechanic. Awaiting designer playtest.
  - **#246 `gameplay/entity-streamer`** — `EntityRegistry` + 4-tier AI sleep + Goblin/NPC/VoxelDrop retrofit. Headless 66 checks green; awaiting merge.
  - **#245 `weather/rain-rework`** — rain shader + audio envelope + god ray framework. **Designer deferred all visuals; gated OFF by default.** Has CLAUDE.md conflict from this reorg — rebase needed before merge.
  - **#239 `claude/game-combat-design-Z5oLa`** — Directional Melee Combat v1 (sword + shield, parry/block, lock-on, HUD). **Awaiting review — do NOT build melee work on a different branch without checking this first.**
- **Default-OFF features (do not flip without designer direction):**
  - `GraphicsManager.rain_visuals_enabled = false` (PR #245 — rain shader + splash particles + wet-surface mod).
  - `GraphicsManager.light_shafts_enabled = false` (PR #245 — per-state vol-fog god rays).
- **Last merged:** PR #244 (Phase K bundle — selection outline, cloud cohesion, lens flare, rainbow shader, DebugOverlay GRAPHICS sub-view).

## Deprecated / superseded (do NOT implement from these)

Files that still exist but look canonical without being it. Always check this list before implementing against an older-looking plan.

- **`design/WATER_VOXEL_V2_PLAN.md`** — superseded by the **native-fluid pivot** (`WATER_STAGE6_PLAN.md` is the actual record). Water is now Zylann `VoxelBlockyModelFluid` at ids 16–23, not the V2 transparent voxel scheme.
- **`scripts/WaterChunkMesher.gd`** — **DELETED 2026-05-16**. Any doc / comment referencing it is stale.
- **`scripts/EmissiveLightManager.gd` v1 OmniLight3D streaming** — kept on disk as fallback but **parked at startup by `EmissiveBakedLightManager`** (Phase J). New emissive work goes through the baked manager, not v1.
- **`scripts/HorizonSkirt.gd` / `scripts/_dev/SkirtBaker.gd`** — retired 2026-05-22 by `DistantTerrainManager` streaming heightmesh. Any doc referencing the baked skirt is stale.
- **`scripts/_dev/`, `scripts/_prototypes/`, `scenes/_prototypes/`** — throwaway / parity / experimental code. Don't pattern new work after files in these directories without checking they're current.

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
