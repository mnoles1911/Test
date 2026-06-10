# design/CLAUDE.md

System implementation docs. **One `.md` per system; lore wins when lore vs design conflict.**

## Find your system

### Combat
- `COMBAT_DESIGN_3D.md` — overall combat vision (Witcher 3 + Dark Souls flavour).
- `COMBAT_NEXT_PHASES.md` — priority-ordered list of unfinished phases (gibs ✓, charge ✓, Mixamo, Ashfallen, melee, group AI, wolves/bears, companions).
- `ENEMY_AI.md` — attack tokens, fleeing, swarms (queued).

### Skills + progression
- `SKILLS_AND_PROGRESSION.md` — 12 skills × 300 perks. `SkillManager` is the single XP entry point.
- `INVENTORY_AND_EQUIPMENT_SYSTEM.md`, `ITEM_LIBRARY.md`, `CRAFTING.md` — items / recipes / stations.
- `MINING_TIME_SCALING.md` — per-material mining time + tool tier scaling.

### World systems
- `WEATHER_AND_ENVIRONMENT.md`, `WEATHER_REWORK_2026-05.md` (current rework status).
- `SWIMMING_AND_WATER.md`, `WATER_STAGE6_PLAN.md` (native-fluid pivot record), `WATER_SHADER_V3_PLAN.md`, **`WATER_FINITE_SIM_PLAN.md`** (current water sim — finite volume-conserving model, 2026-06-10), `WATER_LEVELING_PLAN.md` (rejected/superseded).
- `DAY_NIGHT_CYCLE.md` (if present), `LIGHTING.md`.
- `SAVE_SYSTEM.md`, `DEATH_AND_RESPAWN.md`, `REST_AND_CAMP.md`.
- `WORLD_NAVIGATION.md`.
- `ENTITY_STREAMING.md` — `EntityRegistry` + 4-tier AI sleep spec.

### Player + UI
- `HUD_AND_UI.md`, `JOURNAL_UI.md`, `INPUT_AND_CONTROLS.md`, `ACCESSIBILITY_AND_SETTINGS.md`.
- `CAMERA_AND_PERSPECTIVE.md`.

### Social systems
- `NPC_SYSTEM.md`, `COMPANION_SYSTEM.md`, `CONVERSATION_SYSTEM.md`, `BARK_LIBRARY.md`, `NPC_DIALOGUE_LIBRARY.md`.
- `FACTION_SYSTEM.md`, `QUEST_SYSTEM.md`, `ECONOMY_AND_VENDORS.md`.
- `LOCKPICKING.md`, `INVESTIGATION_SYSTEM.md`, `MINI_GAMES.md`.

### Art + pipeline
- `ART_DIRECTION.md`, `ART_PIPELINE.md`, `ASSET_PIPELINE_AI.md`.
- `3D_VOXEL_MIGRATION.md` — voxel scale (6/m), atlas, NoEditZones, edit deltas.
- `GRAPHICS_PASS_2026-05-19.md` — graphics phase record + roadmap.
- `COPPER_ISLES_DEMO_HEIGHTMAP.md`, `COPPER_ISLES_BAKE_NOTES.md`.

### Audio
- `AUDIO_DESIGN.md`, `SFX_LIBRARY.md`, `SFX_PROMPTS.md`, `MUSIC_PROMPTS.md` (in `tools/` or here per file location).

### Multiplayer
- `MULTIPLAYER.md` — MP-1/2/3/etc. record.

### Process + ops
- **`PATTERNS_AND_GOTCHAS.md`** — non-negotiable code rules, scene hierarchies, autoload load order. **READ BEFORE WRITING CODE.**
- **`PROFILER_AND_DIAGNOSTICS.md`** — read before guessing at perf.
- `LESSONS_LEARNED.md` — chronological retrospectives. Cite the relevant entry when wiring a fix that touches a prior gotcha.
- `MILESTONE_ROADMAP.md`, `ENDGAME_CHOICES.md`, `DIALOGIC_SETUP.md`, `TTS_PIPELINE.md`.
- `FORWARD_PLUS_MIGRATION_TODO.md` — graphics migration follow-ups.

## When adding a new doc

1. One file per system. Don't expand an existing doc to cover a different concept.
2. Update the relevant section above (this file) with a one-line pointer.
3. If the doc establishes a new non-negotiable code rule, ALSO add a line to `PATTERNS_AND_GOTCHAS.md`.
4. If a designer-side task falls out (editor work, asset request), append to `../DESIGNER_TODO.md`.

## Captures

`design/captures/` — profiler JSON dumps + screenshots used as evidence in lessons-learned entries.
