# CLAUDE.md

Navigation index for Claude Code in this repo. **This file is intentionally short.** Deep detail lives in the linked files; this just tells you where to look.

## Project

3D voxel narrative RPG, Veloren + Skyrim atmosphere. Godot 4.6.2 + Zylann Voxel Tools, Forward+ on desktop. Real-time action combat, 1-vs-many, co-op 1-4. Game one of a planned trilogy from a 200-page source manuscript. World is **Mira-Thal**, LOTR-scale fantasy.

I am a writer + game designer, not a programmer. Explain code in plain English; comment heavily; prefer simple readable solutions over clever ones.

## Where to look

| Need | File |
|---|---|
| Milestone history (one-liners) | `MILESTONES.md` |
| Lore (canon, characters, locations, factions) | `lore/INDEX.md` |
| System design (one .md per system) | `design/*.md` (combat, AI, skills, weather, audio, etc.) |
| Non-negotiable code rules + scene hierarchies + autoload load-order | **`design/PATTERNS_AND_GOTCHAS.md`** |
| Designer-side todo list (Godot editor work, assets) | `DESIGNER_TODO.md` |
| Perf workflow + capture recipes | `design/PROFILER_AND_DIAGNOSTICS.md` |
| C++ GDExtension code | `extensions/voxel_gen/` |
| Game scripts / scenes | `/scripts /scenes` |
| Headless test harness | `tools/headless/runner.gd` (selectors documented in `PATTERNS_AND_GOTCHAS.md` Workflow) |
| Per-PR receipts + agent memory | `/memory` |

**Lore wins when lore vs design conflict.**

## Non-negotiables (one-line summary; full detail in `design/PATTERNS_AND_GOTCHAS.md`)

- **Player input** must gate on `_can_take_input()` (MP authority check).
- **Voxel edits** must go through `VoxelEditManager.queue_*`, never raw `VoxelTool`.
- **Skill XP** must go through `SkillManager.add_xp`, never `GameState._skill_levels[…]`.
- **UI clicks** must use manual `_input` dispatch — `Button.pressed` does NOT fire in this project (Dialogic eats it).
- **Voxel material lookup** via `VoxelMaterialRegistry`, never decode alpha by hand.
- **Water type checks** via `WaterMaterial.is_water_type(t)`, never `== 5`.
- **`CHANNEL_COLOR` must be 32-bit** before chunks stream (set once in bootstrap).
- **`_generate_block` runs on a worker thread** — no SceneTree access.
- **Never flip `bake_tangents`** (breaks runtime-injected water meshes).
- **Never call `RenderingServer.global_shader_parameter_add / _get / _get_list`** (editor-only — errors in shipped builds). Declare globals in `[shader_globals]`; runtime only `_set`.
- **GDScript by default; C++ GDExtension proactively for perf** (don't gate behind profiler measurement).
- **No C#, ever.**
- **No systems built before I need them.**

## Workflow at a glance

- **Open in Godot 4.6.2**, run a scene (`World3D.tscn`, `scenes/_dev/CombatTest.tscn`, etc.), check Output. No CLI build/lint/test for the Godot side.
- **Headless data/parity checks**: `tools/headless/run.ps1 <selector>` (selectors in `PATTERNS_AND_GOTCHAS.md`). Visuals still need the editor.
- **C++ build**: `python -m SCons platform=windows target=template_debug use_mingw=yes -j8` from `extensions/voxel_gen/` (close Godot first).
- **Git**: one fix per branch; never amend published commits; push with `-u origin <branch>`.

## Maintenance: when in doubt, also update

- `lore/INDEX.md` + relevant lore file on any narrative change.
- The relevant `design/*.md` on any system change (1:1 doc per system).
- `MILESTONES.md` when a PR ships (one line).
- `design/PATTERNS_AND_GOTCHAS.md` when a new load-bearing pattern surfaces.
- `DESIGNER_TODO.md` for new editor / asset work.
- **`CLAUDE.md` only when a top-level navigation entry needs adding** — not for content.

## Current state

Godot 4.6.2; 3D voxel pivot complete (since 2026-04-30). VoxelLodTerrain streaming, edits by default, NoEditZones protect settlements, 12×10 km Mira. Combat v1 + Phase 5 gibs + entity streaming + weather rework framework all on disk. See `MILESTONES.md` for the arc; `DESIGNER_TODO.md` for outstanding manual setup + asset work.

**Not yet implemented:** Combat next phases (Mixamo rigs, melee foundation PR #239 awaiting review, group AI, Ashfallen), `SchematicLibrary`, `QuestManager`, `CompanionManager`.
