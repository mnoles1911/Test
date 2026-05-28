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
