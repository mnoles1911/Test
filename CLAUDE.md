# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Game One — Project Bible

## What I'm building
A 3D voxel narrative RPG — Veloren meets Skyrim in atmosphere and open-world scale.
Real-time action combat (Witcher 3 / Dark Souls style), 1-vs-many, first person and third camera cameras, cooperative multiplayer with 1-4 friends.
Voxel world built in Godot 4.6.2 with Zylann's Voxel Tools plugin. GDScript only.
This is game one of a planned trilogy adapted from a 200-page source manuscript.

**Engine pivot confirmed (2026-04-30):** Switched from 2D pixel art to 3D voxel.
Full migration plan: `design/3D_VOXEL_MIGRATION.md`

## My background
I am a writer and game designer, not a programmer.
Always explain what code does in plain English before writing it.
Keep all scripts heavily commented.
Prefer simple, readable solutions over clever ones.

## Genre and tone
Epic fantasy with grounded emotional stakes — LOTR scale, single-protagonist intimacy. The world is Mira-Thal, third age. See `lore/WORLD.md` for setting canon and `lore/INDEX.md` for the directory map.

## Core systems (what we're building)
- Player: CharacterBody3D, 8-directional movement on 3D XZ plane
- World scenes: VoxelTerrain (Zylann plugin) + MagicaVoxel prop assets
- Camera: SpringArm3D third-person over-shoulder, ~15° elevation, player-rotatable; lock-on for 1-vs-many combat
- Dialogue: Dialogic 2 plugin handles all narrative content (unchanged)
- Combat: Real-time action in-world (Hades style), 1-vs-many, no separate scene
- Game state: Autoload singleton (GameState.gd) tracks all persistent data (unchanged)
- Scene transitions: TransitionManager autoload, fade-to-black/white/cut (unchanged)

## Folder structure
- /scenes — all .tscn files
- /scripts — all .gd files
- /addons/dialogic — Dialogic 2 plugin source (do not edit; manage via the Asset Library)
- /assets/portraits — character portrait images for dialogue (256×320 px)
- /assets/voxel, /assets/models, /assets/audio, /assets/npcs — referenced throughout the design docs but **not yet present on disk**; create as needed when content arrives
- /dialogue — Dialogic timelines (.dtl) plus `CHARACTER_VOICES.md` (voice IDs + ElevenLabs config), `PRONUNCIATION.md` (phonetic respellings for lore proper nouns — check before every TTS run), `STYLE.md` (line writing rules, mood tags, length targets)
- /lore — all narrative canon (start at lore/INDEX.md)
- /design — game implementation reference (systems, art direction)
- /tools — pipeline scripts run from the repo root (TTS rendering, draft stripping); see `tools/README.md`

## Milestone history
Completed milestones (see git log for full PR detail; the autoload section below documents what's currently live in-engine):
- **Milestones 1–4 (2D):** walkable cave, opening dialogue, combat prototype, full UI/state framework.
- **3D pivot (2026-04-30, PR #43):** all art/camera/migration design docs rewritten for voxel.
- **Milestone 4-3D (2026-05-01):** Player3D, CameraRig, HUDOverlay, JournalUI, triggers, World3D placeholder.
- **Milestone 5-3D (2026-05-03):** destructible-voxel slice — VoxelLodTerrain + SQLite deltas, CubicHeightmapGenerator, edit/gravity/water managers, NoEditZones, pickaxe + explosives, swimming, day/night.
- **Milestone 6-3D Weather (2026-05-04):** WeatherManager — six-state machine, 30 s transitions, fog/wind/particles/lightning, location profiles, proximity zones.
- **Voxel water refactor (2026-05-05):** Area3D water replaced with voxel-cell flow sim (`WaterFlowManager` 4 Hz tick, `WaterChunkMesher` transparent surfaces, `WORLD_GENERATOR_VERSION = 11`).
- **Copper Isles demo (2026-05-06):** Heightmap-driven generator (`CopperIslesHeightmapGenerator.gd`) for the 5 km × 5 km Copper Isles archipelago; per-voxel water bytes written into `CHANNEL_DATA5` at gen time (no AABB flood heuristic); `WORLD_GENERATOR_VERSION = 13`; bake pipeline (`scenes/_dev/BakeWorld.tscn` + `WorldBakeController.gd` + `SkirtBaker.gd`) for streaming the full map into a baseline SQLite; `HorizonSkirt.gd` draws distant peaks beyond the 250 m view distance. Test scene: `scenes/CopperIslesTest.tscn`.

Outstanding pickups: low-poly Blender Roland model (still placeholder green box), MagicaVoxel prop exports (campfire, cave walls), surface decoration pass, ambient weather audio OGGs, region-boundary profile auto-swap. See `DESIGNER_TODO.md` and `design/LESSONS_LEARNED.md`.

## Art specification (3D VOXEL)
- **Voxel scale**: 6 voxels/m (locked 2026-05-03; ~16.7 cm/block, player ~11 voxels tall).
- **Terrain**: `VoxelLodTerrain` + `VoxelMesherCubes`. Procedural baseline from `CubicHeightmapGenerator`. **Destructible by default** — `NoEditZone` Area3D volumes are the exception. Edits stored as deltas in `VoxelStreamSQLite`, persist forever.
- **World scale**: Playable Mira 12 km × 10 km (compression 125:1). Thal ~7 km × 5.5 km.
- **Props/buildings**: MagicaVoxel → .glb. Narratively load-bearing structures sit inside NoEditZones, never carved.
- **Player-built**: schematic props (Carpentry Bench) + per-voxel detailing (Build Mode).
- **Characters**: Blender low-poly .glb (200–500 tris). Portraits unchanged for dialogue.
- **Camera**: SpringArm3D third-person, ~15° above horizontal, lock-on for 1-vs-many.
- **Lighting**: OmniLight3D + DirectionalLight3D + WorldEnvironment SSAO + fog.
- **Canonical refs**: `design/3D_VOXEL_MIGRATION.md` (full spec), `design/ART_PIPELINE.md`, `design/ART_DIRECTION.md`.

## What I never want
- Systems built before I need them
- C# — GDScript only

## Files requiring regular maintenance

These files go stale as lore and game design evolve. Review and update them whenever making significant additions or changes:

| File | Update when... |
|---|---|
| lore/INDEX.md | Any new lore file is added or an existing file's scope changes |
| lore/REFERENCE.md | New characters, locations, factions, or timeline events are added |
| lore/CHARACTERS_COMPANIONS.md | Companion arcs, abilities, or backstory details change |
| lore/CHARACTERS_NPCS.md | New NPCs added or villain details revised |
| lore/WORLD_GEOGRAPHY.md | New locations, terrain, or settlements established |
| lore/MAP_GENERATION_GUIDE.md + sibling map files | New settlements, terrain, or geographic features added |
| design/3D_VOXEL_MIGRATION.md | Canonical destructible-terrain spec — update when edit verbs, NoEditZone rules, mesh-bake behavior, or LOD radii change |
| design/MINING_TIME_SCALING.md | New voxel material added, baseline `mining_time_seconds` values tuned, volume-scaling formula changed, or tool-tier multipliers wired in |
| design/SYSTEMS_DESIGN.md | Companion roster changes, faction triggers updated, new game systems added |
| design/ART_DIRECTION.md | New locations added to the game, palette or shader decisions finalized |
| design/ITEM_LIBRARY.md | New craftable items, recipes, or input materials added to any section |
| design/SKILLS_AND_PROGRESSION.md | New perks, sub-skills, or trainer NPCs added; XP values tuned |
| design/TTS_PIPELINE.md | Render tooling lands, voice IDs lock for a new character, manifest schema changes |
| design/FACTION_SYSTEM.md | Factions added/removed, disposition triggers tuned, lockout thresholds change |
| design/QUEST_SYSTEM.md | New quest patterns, resolution outcomes, or timed-event rules added |
| design/INPUT_AND_CONTROLS.md | New Input Map action added (must also update DESIGNER_TODO.md Section 1) |
| design/NPC_SYSTEM.md | NPC tier rules, schedule mechanics, or WorldClock integration changes |
| design/LOCKPICKING.md | Lock tiers, pick types, or skill-tier hold-timer values change |
| dialogue/CHARACTER_VOICES.md | New voiced character is added, or a render contract changes (voice ID, seed, stability) |
| dialogue/PRONUNCIATION.md | Any new lore proper noun is introduced (place names, gods, titles) |
| DESIGNER_TODO.md | New design doc lands that requires editor or asset work; tasks completed |
| design/COPPER_ISLES_BAKE_NOTES.md | Zylann GDExtension probe results change, or new bake-pipeline decisions are made |
| design/COPPER_ISLES_DEMO_HEIGHTMAP.md | Copper Isles island layout, heightmap spec, or import notes change |
| CLAUDE.md (this file) | Milestone completed; new canonical naming contradictions found; new systems or design docs added |

---

## Lore reference
All world-building canon lives in /lore. Start at /lore/INDEX.md for a directory map. Key entry points:
- lore/WORLD.md — three ages, magic, religion, peoples overview
- lore/WORLD_GEOGRAPHY.md — terrain, scale, rivers, coastlines
- lore/MAP_GENERATION_GUIDE.md — Tolkien-style map prompt and layout rules
- lore/CHARACTERS_PROTAGONIST.md, CHARACTERS_COMPANIONS.md, CHARACTERS_NPCS.md, BACKSTORY_*.md
- lore/GAME1_PART1.md / GAME1_PART2.md — full Game One plot (GAME2_* and GAME3_* files also present for trilogy planning)
- lore/PEOPLES.md — races and cultures
- lore/GUILDS_*.md — knight orders, shadow bands, trade and scholar guilds
- lore/HISTORY_*.md — Eldermark and Shroud Sea deep history
- lore/SIDE_QUESTS_GAME*.md — side quest rosters per game
- lore/LEVEL_LAYOUTS_ACT*.md — room-by-room scene specs for each act (cross-ref design/MILESTONE_ROADMAP.md)
- lore/locations/ — individual location files (25+ entries: cities, dungeons, regions)
- lore/REFERENCE.md — quick-reference tables

Always check INDEX.md before adding new lore files to avoid duplication.

## Design reference
Game implementation docs live in /design. When lore and design conflict, lore wins.

**World and systems:**
- design/SYSTEMS_DESIGN.md — combat, dialogue, exploration, faction, save systems (overview)
- design/COMBAT_DESIGN_3D.md — real-time 3D combat: click-duration power system, dodge, parry, lock-on
- design/ENEMY_AI.md — enemy detection states, attack token system, per-type specs (Goblin/Ashfallen/Wolf/Bear)
- design/SKILLS_AND_PROGRESSION.md — learn-by-doing skill domains, sub-skills, perk trees, Charisma, Lethe's Draught
- design/INVENTORY_AND_EQUIPMENT_SYSTEM.md — equipment slots, weight, condition, smithing tiers (mechanics)
- design/ITEM_LIBRARY.md — master recipe reference: 40 potions, 40 smithable items, 15 meals, 30 assembly items
- design/CRAFTING.md — crafting station mechanics, intent-based quality, Wanderer's Seal
- design/MINING_TIME_SCALING.md — per-material `mining_time_seconds` baselines, the `(N³)/8` volume multiplier, planned tool-tier scaling
- design/REST_AND_CAMP.md — rest mechanics, camp setup, sleep effects, time advancement
- design/INVESTIGATION_SYSTEM.md — examine system, investigation points, Roland's deduction mechanic
- design/LOCKPICKING.md — resonance pick radial dial system, lock tiers, pick consumption, skill advancement
- design/WEATHER_AND_ENVIRONMENT.md — authored weather, six time-of-day periods, WorldClock lighting, environmental hazards
- design/SAVE_SYSTEM.md — diegetic saves (rest autosave + Wanderer's Seal), three slots, backup rotation
- design/DEATH_AND_RESPAWN.md — death sequence, authored Roland death lines, Second Wind, no permanent loss
- design/SWIMMING_AND_WATER.md — water body setup, swimming state machine, breath/drowning, Boujie water shader
- design/MULTIPLAYER.md — co-op architecture (client-server, ENet, Netfox rollback), terrain sync, narrative canon rule

**Player systems:**
- design/HUD_AND_UI.md — minimal HUD, HP/endurance bars, quick slots, interaction prompt, bark overlay, menus
- design/INPUT_AND_CONTROLS.md — full KB/mouse and controller scheme, all Input Map actions, tap-vs-hold combat
- design/ACCESSIBILITY_AND_SETTINGS.md — display/audio/controls/accessibility settings, subtitle defaults, colorblind support
- design/WORLD_NAVIGATION.md — no-waypoint navigation, Roland's hand-drawn journal map, zone structure, landmarks
- design/AUDIO_DESIGN.md — audio bus layout, music/SFX/voice routing, spatial 3D audio, settings volume sliders

**Companion and NPC systems:**
- design/COMPANION_SYSTEM.md — Orion and Dagna mechanics, combat orders, downed/revive, pack management
- design/CONVERSATION_SYSTEM.md — four-tier conversation system (barks → illustrated keyframes), TTS pipeline
- design/NPC_SYSTEM.md — NPC tier system, disposition, WorldClock, schedules
- design/BARK_LIBRARY.md — bark trigger IDs, line counts, cooldown rules
- design/NPC_DIALOGUE_LIBRARY.md — conversation structure for Tier 2 and 3 NPCs
- design/JOURNAL_UI.md — five-tab journal UI: Quests, Map, Items, Crafting, Codex

**World and narrative systems:**
- design/FACTION_SYSTEM.md — six Game One factions, disposition scale, rival effects, lockouts, Game Three seeding
- design/QUEST_SYSTEM.md — situation-based quests, multi-resolution outcomes, timed events, authoring guidelines
- design/ECONOMY_AND_VENDORS.md — lean economy, vendor types with named vendors, faction price modifiers, haggling

**Art and pipeline:**
- design/ART_DIRECTION.md — palette, location visual identity, architecture by region, shaders
- design/CAMERA_AND_PERSPECTIVE.md — why the 3/4 view is an art style, not a camera transform
- design/TECH_STACK.md — full technology stack: every tool, plugin, and pipeline; current generator (`CubicHeightmapGenerator`); autoload status table (kept in sync with `project.godot`)
- design/ART_PIPELINE.md — MagicaVoxel, Zylann plugin, Blender. Note: the Gaea → EXR → VoxelGeneratorGraph pipeline section is aspirational (planned for v1 Mira authoring); current implementation uses `CubicHeightmapGenerator`
- design/3D_VOXEL_MIGRATION.md — full pivot plan: what changes, what survives, 3D milestones

**Planning and ops:**
- design/MILESTONE_ROADMAP.md — Act I scene breakdown and ordered deliverables for Phases 4+
- design/ENDGAME_CHOICES.md — Game Three endgame and trilogy-spanning choice consequences
- design/DIALOGIC_SETUP.md — step-by-step Dialogic 2 installation and character setup
- design/TTS_PIPELINE.md — AI-assisted draft → ElevenLabs render → Dialogic handoff (bulk vs craft pipelines, filename + manifest contract)
- design/LESSONS_LEARNED.md — running log of bugs and fixes
- design/COPPER_ISLES_DEMO_HEIGHTMAP.md — AI prompt + per-island terrain spec for the 5 km × 5 km Copper Isles archipelago heightmap; Godot import notes
- design/COPPER_ISLES_BAKE_NOTES.md — Zylann GDExtension probe results (API behaviors verified at runtime), bake-pipeline design decisions and gotchas

## Current project state
Godot 4.6.2. 3D pivot complete. Open world plan confirmed: VoxelLodTerrain streaming, **editable / destructible terrain by default** (LOD0-clamped + LOD-baked at distance, edits stored as deltas in `VoxelStreamSQLite`, NoEditZones protect settlements and lore landmarks, no world healing), 12km × 10km playable Mira, third-person over-shoulder camera, low-poly Blender character models from Act I.

The system design corpus is complete (combat, AI, companions, factions, quests, economy, save, death, weather, HUD, input, accessibility, audio, navigation, lockpicking, destructible terrain — all in `/design`). Pipeline tooling (`tools/strip_draft.py`, `tools/render_bulk.py`) is documented in `tools/README.md` and requires `ELEVENLABS_API_KEY`.

**2D legacy (still on disk, will be retired as 3D scenes replace them):**
`scripts/Player.gd`, `CampfireFlicker.gd`, `DialogueTrigger.gd`, `CombatTrigger.gd`, `Combat.gd`; `scenes/Player.tscn`, `World.tscn`, `Combat.tscn`.

**3D core (in place):**
- `Player3D.gd` / `Player3D.tscn` — CharacterBody3D, 8-directional XZ movement, sprint/crouch, health/endurance, mass-based physics scaling
- `CameraRig.gd` — SpringArm3D over-shoulder; standard + freelook (F2); scroll zoom 2m–10m; lock-on API
- `HUDOverlay.gd` — Layer-5 CanvasLayer; HP + endurance bars; CROUCHING / EXHAUSTED status label
- `JournalUI.gd` + `scenes/ui/Journal.tscn` — 6-tab overlay (Quests/Map/Items/Crafting/Codex/Skills); all layout built programmatically
- `CampfireFlicker3D.gd` — OmniLight3D flicker
- `SpawnPoint3D.gd`, `RoomTrigger3D.gd`, `DialogueTrigger3D.gd` — Vector3 / Area3D ports of the Zone framework triggers
- `World3D.tscn` — placeholder cave: WorldEnvironment (SSAO + fog), DirectionalLight3D, ground StaticBody3D, OmniLight3D campfire, Player3D instance
- `World3DBootstrap.gd` — attached to World3D.tscn root; hands the `VoxelLodTerrain` to autoloads on `_ready`, configures `CHANNEL_COLOR` to 32-bit depth on `terrain.format`, and enables `threaded_update_enabled` + `collision_update_delay`. **All world-load wiring goes here.**
- `VoxelDrop.gd` — RigidBody3D pickup spawned by `EditToolHandler` when a voxel is mined. Falls under gravity, auto-collects when Roland walks within `PICKUP_RADIUS_M`, despawns after `DESPAWN_SECONDS`. Not saved across sessions (v1 scope).
- `CopperIslesHeightmapGenerator.gd` — `@tool` `VoxelGeneratorScript` for the Copper Isles demo. Reads a Gaea EXR heightmap; emits terrain into `CHANNEL_COLOR` (32-bit) and water source bytes into `CHANNEL_DATA5`. Attached to the `VoxelLodTerrain` in `CopperIslesTest.tscn`.
- `CopperIslesTestBootstrap.gd` — slimmed sibling of `World3DBootstrap.gd` for `CopperIslesTest.tscn`; seeds the working SQLite from a baked baseline if present; snaps the player above peak elevation on spawn and after F7 scale changes.
- `HorizonSkirt.gd` — `MeshInstance3D` child of `VoxelLodTerrain`. Loads the baked low-LOD skirt mesh from `assets/voxel/copper_isles_skirt.res` so distant peaks are visible beyond the 250 m stream radius. Hides silently if mesh isn't baked yet. Bake via `scenes/_dev/BakeWorld.tscn`.

**NPC system (in place):**
- `NPC.gd` — CharacterBody3D base script for Tier 1–3 NPCs; bark firing, E-press dialogue, disposition, schedule dispatch
- `NPCData.gd` — Resource: npc_id, Tier enum, disposition, bark_triggers, schedule entries (one .tres per character, expected in `/assets/npcs/` once that directory exists)
- `NPCScheduleEntry.gd` — Resource: hour_start, hour_end, location_id, animation

**Voxel + world systems (in place, autoloaded):**

For deep mechanics, read the script header in each `.gd` file. This is a quick reference for what's wired and what its public surface looks like.

- `VoxelEditManager.gd` — async edit queue, NoEditZone gate, EditedChunkRegistry, `WORLD_GENERATOR_VERSION` stamping. **Always route voxel writes through this autoload.** Emits `edit_applied` signal.
- `NoEditZoneRegistry.gd` — registers `no_edit_zone` group Area3Ds. API: `is_point_inside_no_edit_zone(world_pos)`.
- `CubicHeightmapGenerator.gd` — `@tool` `VoxelGeneratorScript` attached to `VoxelLodTerrain` in `World3D.tscn` (NOT autoloaded). Layered noise + per-voxel jitter + Preset enum.
- `WorldClock.gd` — in-game time (240 real s = 1 game hour). Signals: `hour_changed`, `time_of_day_changed`, `day_changed`. Pauses during Dialogic.
- `BarkManager.gd` — bark pools from `dialogue/scripts/barks/{category}/{npc_id}.txt`, spatial audio from `assets/audio/barks/`.
- `WaterFlowManager.gd` — water query + flow sim. Queries (`is_position_in_water`, `get_water_level_at`, `get_flow_velocity_at`) read `CHANNEL_DATA5` directly via `VoxelTool` (DATA5 because Zylann reserves DATA0–4 for TYPE/SDF/COLOR/INDICES/WEIGHTS). Flow tick at 4 Hz within 20 m of player; pre-copies DATA5 + COLOR + chunk-above-DATA5 buffers once per chunk. Subscribes to `VoxelEditManager.edit_applied`. API: queries above, `add_source` (routes through `VoxelEditManager.queue_set_water_voxel`), `set_horizon_plane_y` / `get_horizon_plane_y`, `set_global_wind`. Flow rules: gravity drop, lateral spread (level-1 to 4 neighbours), monotone decay; NoEditZones with `blocks_water_flow=true` act as walls. Water persists via the chunk SQLite stream — no extra save key.
- `WaterChunkMesher.gd` — child of WaterFlowManager. Greedy 2D run-merge of per-column water tops in `CHANNEL_DATA5` per chunk → transparent surface meshes via `water_material.tres`. `is_uniform` fast path skips per-voxel scan for all-air or all-source chunks. 96 m render cull. Adaptive per-frame build budget (16 → 1 as frame delta climbs from <18 ms to >50 ms) so the mesher yields to the terrain LOD streamer during initial load. One follow-player horizon plane (CULL_BACK, `render_priority=-1`) covers the distant horizon at the configured sea level Y.
- `WaterByteCodec.gd` — static class. Single source of truth for the `CHANNEL_DATA5` water byte layout (`level | source_bit | tick`) plus `pack`, `level_of`, `is_source`, `is_water`, `tick_of`, and the canonical `SOURCE_BYTE` / `AIR_BYTE` constants.
- `VoxelEditManager` water API: `queue_set_water_voxel(voxel_pos, byte)` and `queue_set_water_box(voxel_min, voxel_max, byte)` write `CHANNEL_DATA5` through the same async queue and NoEditZone gate as terrain edits, with an `is_area_editable` retry guard (re-queue up to 60 retries if the chunk isn't streamed yet), then emit `water_changed_at` (distinct from `edit_applied`).
- `assets/shaders/water.gdshader` + `water_material.tres` — sine-sum vertex-displacement, wind-biased, world-space XZ phase-aligned.
- `UnderwaterFilter.gd` — CanvasLayer on Player3D, blue-green tint when submerged. `set_active(bool)` idempotent.
- `NoEditZone.gd` — optional Area3D companion script. `@export blocks_water_flow: bool = true`. Auto-joins `no_edit_zone` group.
- `DayNightCycle.gd` — Node on `World3D`. Drives Sun/Moon DirectionalLight3D + sky/fog colour from WorldClock. Has `set_fog_override` for weather.
- `EditToolHandler.gd` — Player3D child. Pickaxe/axe/shovel raycast → `VoxelEditManager` → `InventoryManager` yield.
- `ThrowableHandler.gd` — Player3D child. Throw input spawns `voxel_aoe_radius`/`combat_damage` RigidBody3D with camera-aimed velocity.
- `PowderCharge.gd` — impact-detonating RigidBody3D throwable. Sphere carve via VoxelEditManager + flash.
- `VoxelGravityManager.gd` — subscribes to `edit_applied`. Local 16 m flood-fill finds unsupported voxels → spawns `FallingVoxelCluster`. Caps: 4096 voxels/cluster, 32 active clusters, 1 bubble/physics frame.
- `FallingVoxelCluster.gd` + `scenes/voxel/FallingVoxelCluster.tscn` — RigidBody3D for airborne chunks. Voxel-weighted centroid as COM, tip impulse for tall clusters, re-deposits via `queue_set_voxels_bulk` on sleep. Damages bodies with `health` property: `voxel_count × fall_height × 0.05`.
- `VoxelClusterBuilder.gd` — static utility. ArrayMesh build with face culling, AABB/centroid/COM offset compute, shared StandardMaterial3D cache.
- `VoxelMaterial.gd` + `assets/voxels/materials/*.tres` — Resource subclass. Fields: `id_string`, `material_id` (1–254), `color_low/high/jitter`, `mining_time_seconds`, `allowed_tools`, `yield_item_id`, `yield_quantity`, `fall_behavior` (NEVER/SOLID/LOOSE), `gravity_scale`, `damage_multiplier`. Add materials by inspector — no code edits.
- `VoxelMaterialRegistry.gd` — recursive scan of `assets/voxels/materials/` at startup. API: `get_by_id`, `get_by_string`, `pack_voxel`, `material_id_from_packed`, `is_air`. Canonical home for alpha-byte-as-material-id encoding.
- `WeatherManager.gd` — six-state machine (CLEAR/OVERCAST/LIGHT_RAIN/HEAVY_RAIN/FOG/SNOW), 30 s transitions. Trigger priority: `set_weather_override(state, hours)` > proximity zone stack > scheduled rolls at `[6, 12, 18]`. Pushes fog via `DayNightCycle.set_fog_override`, wind to `WaterFlowManager.set_global_wind`, ambient dim to WorldEnvironment. GPUParticles3D rain/snow follow camera. RainOverlay tint + voxel terrain wet `material_override`. Lightning during HEAVY_RAIN: OmniLight3D flash + delayed thunder via `distance / 343 m·s⁻¹`. API: `trigger_lightning_strike(pos)`, `push_proximity_zone`, `pop_proximity_zone`, `set_location_profile`. Save/load via GameState.
- `RainOverlay.gd` — CanvasLayer child of WeatherManager. Blue-grey ColorRect, `set_intensity(0..1)`.
- `WeatherLocationProfile.gd` + `assets/profiles/*.tres` — Resource. Fields: `profile_id`, `authored_sequence`, `random_distribution`, `transition_hours`. v1: `mira_temperate.tres`. Region auto-swap deferred — call `set_location_profile` manually.
- `WeatherZone.gd` — Area3D. `@export weather_state: String`, `@export priority: int`. Pushes to WeatherManager stack on entry/exit.

**Dev tools (not shipped, live in `scripts/_dev/` and `scenes/_dev/`):**
- `WorldBakeController.gd` + `scenes/_dev/BakeWorld.tscn` — UI-driven bake that walks a `VoxelViewer` across the whole Copper Isles grid, streams + persists every chunk into a baseline SQLite at `user://baked_baseline.sqlite`, then copies it to `assets/voxel/`. Run in-game (F5 on BakeWorld.tscn) — the bake requires live terrain streaming and does nothing in the editor.
- `SkirtBaker.gd` — builds the horizon-skirt ArrayMesh from the EXR at 64 m × 64 m quad resolution (~12 800 tris for a 5 km map). Called by `WorldBakeController` and saves `assets/voxel/copper_isles_skirt.res`.

**Specified in design docs but not yet implemented** (build in dependency order):
- `SchematicLibrary.gd` — autoload. Registry of placeable building schematics (`.glb` props with placement metadata in `assets/voxel/schematics/`). Player crafts schematics at the Carpentry Bench; placements saved to `user://saves/slot_{N}/placed_schematics.json`.
- `EntityRegistry.gd` — spatial dictionary of every world entity keyed by chunk; lightweight `EntityRecord` data objects; does not instantiate nodes itself.
- `EntityStreamer.gd` — **stub on disk** (`scripts/EntityStreamer.gd`). Currently only prints chunk-enter events in Output. Full load/unload logic deferred to Phase 6-3D.
- `FactionManager.gd` — wraps GameState faction disposition flags (design/FACTION_SYSTEM.md).
- `QuestManager.gd` — quest flag management (design/QUEST_SYSTEM.md).
- `CompanionManager.gd` — companion active state, HP, save serialization (design/COMPANION_SYSTEM.md).
- LOD-bake-on-eviction caching under `user://saves/slot_{N}/mesh_cache/` — render optimization for edited chunks far from the player. **Deferred** until perf becomes an issue; current LOD streaming is sufficient.

Manual setup still required: see `DESIGNER_TODO.md` → Section 1 (Zylann Voxel Tools install, audio bus layout per `design/AUDIO_DESIGN.md`).






## Godot workflow

There is no CLI build, lint, or test command for this project. To verify changes work:
1. Open the project in Godot 4.6.2
2. Run the relevant scene:
   - `World3D.tscn` — 3D movement, lighting, weather, voxel editing on Mira
   - `CopperIslesTest.tscn` — Copper Isles heightmap terrain; press F7 to cycle terrain scale
   - `scenes/_dev/BakeWorld.tscn` — world-bake tool (must run in-game, not editor)
   - `Combat.tscn` — legacy 2D combat prototype
3. Check the Output panel for errors and print statements
4. Test the specific feature manually

Do not write shell commands that try to run Godot headlessly — there is no such setup here.

---

## Git workflow patterns

- **One fix per branch.** Small, focused branches are easier to review and easier to cherry-pick if something goes wrong.
- **One file per commit** when creating large .tscn or .gd files, to avoid stream idle timeouts during push.
- **Cherry-pick over rebase** when a branch has conflicting squash-merged history. Close the bad PR, create a fresh branch from main, cherry-pick only the new commits, open a new PR.
- **Never amend published commits.** If a hook fails or a push fails, fix the issue and create a new commit.
- Always push with `git push -u origin <branch-name>`.

---

## Critical GDScript patterns

**Autoload check before calling Dialogic:**
```gdscript
if get_node_or_null("/root/Dialogic"):
    Dialogic.start("timeline_name")
```

**Frame-rate-independent deceleration:**
```gdscript
const DECEL: float = 400.0
velocity = velocity.move_toward(Vector3.ZERO, DECEL * delta)
# NOT: velocity.move_toward(Vector3.ZERO, SPEED) — that stops in one frame
```

**One-shot signal connection (e.g. dialogue end):**
```gdscript
Dialogic.timeline_ended.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
```

**OmniLight3D property name:**
```gdscript
omni_light.light_energy = value  # NOT .energy (that's the 2D PointLight2D property)
```

**Capsule CollisionShape3D must be offset upward by half its height:**
```
# A 1.7 m capsule's origin is its center. Set CollisionShape3D local Y = +0.85
# so the bottom of the capsule sits on Y=0. Same offset for the visual mesh.
# Without this, the character sinks into the floor by half its height.
```

**2D input mapped to 3D XZ movement:**
```gdscript
var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
var direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
# Never map input_dir.y → velocity.y — that launches the player into the air.
# The ground plane is XZ; Y is always gravity only.
```

**Camera-relative movement (Player3D.gd uses this):**
```gdscript
var local_dir := Vector3(input_dir.x, 0.0, input_dir.y)
var direction := (transform.basis * local_dir).normalized()
# Multiplying by transform.basis rotates the input vector by the player body's
# current facing. CameraRig rotates the player body to match camera yaw, so
# W always moves toward where the camera is looking. Do NOT use a global
# direction here — that breaks camera-relative movement.
```

**Voxel material lookup — never decode the alpha byte by hand:**
```gdscript
# WRONG — hardcodes the encoding scheme. If we change how material IDs
# get packed, every site that does this manually breaks silently.
var material_id: int = packed_voxel & 0xFF

# RIGHT — go through the registry. The encoding lives in one place.
var material_id: int = VoxelMaterialRegistry.material_id_from_packed(packed_voxel)
var material: VoxelMaterial = VoxelMaterialRegistry.get_by_id(material_id)
if material == null:
    return  # voxel is air, or registry isn't loaded yet
# Now use material.mining_time_seconds, material.yield_item_id,
# material.fall_behavior, etc.
```
Same rule for writes: use `VoxelMaterialRegistry.pack_voxel(mat_id, color)` rather than
`color.to_rgba32()` whenever you're writing a non-air voxel of a known material.

**Voxel edits MUST go through VoxelEditManager — never raw VoxelTool:**
```gdscript
# WRONG — bypasses NoEditZone check, async budget, EditedChunkRegistry update,
# AND VoxelGravityManager (carved support won't trigger falling-voxel scans)
var tool := voxel_terrain.get_voxel_tool()
tool.do_sphere(world_pos, radius)

# RIGHT — VoxelEditManager handles NoEditZone rejection, async queueing,
# EditedChunkRegistry tracking, LOD-bake invalidation, and emits the
# edit_applied signal that VoxelGravityManager subscribes to for gravity scans.
VoxelEditManager.queue_edit_sphere(world_pos, radius, voxel_value)
# Returns true if accepted, false if rejected by NoEditZone (caller may bark
# Roland's "This place doesn't yield to me." line on false).
```
This is non-negotiable. A direct `VoxelTool.do_*` call inside a NoEditZone or
during heavy edit traffic will desync the EditedChunkRegistry, corrupt the LOD
cache, violate the per-frame voxel budget, OR (with gravity now wired) leave
unsupported voxels floating in midair. Always route through the manager.

**User-defined voxel data channel is CHANNEL_DATA5, not CHANNEL_DATA:**
```gdscript
# WRONG — CHANNEL_DATA doesn't exist in Zylann's enum.
buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_DATA)

# RIGHT — Zylann reserves DATA0–4 for TYPE/SDF/COLOR/INDICES/WEIGHTS.
# DATA5 is the first user-defined channel. WaterByteCodec and
# WaterFlowManager both use CHANNEL_DATA5 for water bytes.
buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_DATA5)
```

**VoxelBuffer CHANNEL_COLOR must be 32-bit before any chunks stream:**
```gdscript
# WRONG — default 8-bit storage truncates the packed RGBA+mat_id value
# to just the R byte (~0.01 on screen → terrain renders black).
# Nothing to do here — this is the silent default, which is the bug.

# RIGHT — configure the VoxelFormat resource on the terrain BEFORE
# the first chunk streams. Done once in World3DBootstrap._ready():
if "format" in terrain:
    var fmt := VoxelFormat.new()
    fmt.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
    terrain.format = fmt
# NEVER call set_channel_depth() inside _generate_block — that
# invalidates the buffer's channel storage even on fresh buffers and
# causes chunks to disappear entirely.
```

**VoxelGeneratorScript._generate_block runs on a worker thread — no SceneTree access:**
```gdscript
# WRONG inside _generate_block — crashes or silently returns null on
# Zylann's worker threads.
var registry = get_node_or_null("/root/NoEditZoneRegistry")

# RIGHT — cache a plain data snapshot on the main thread, push it into
# the generator resource, read from local Array inside _generate_block.
# See NoEditZoneRegistry.get_water_blocking_aabbs_snapshot() pattern.
```

**Dictionary[int, PackedByteArray] mutation requires explicit read-modify-write:**
```gdscript
# WRONG — indexes into a Dictionary return a copy in Godot 4.
# This writes to the copy and discards it.
(my_dict[key] as PackedByteArray)[index] = value

# RIGHT — pull, mutate, store back.
var bmp: PackedByteArray = my_dict.get(key, PackedByteArray())
bmp[index] = value
my_dict[key] = bmp
```

---

## Critical scene hierarchies

These node structures are load-bearing. Scripts use hardcoded `$NodeName` references
and will throw errors if the hierarchy differs.

**Player3D / CameraRig:**
```
Player3D (CharacterBody3D + Player3D.gd)
└── CameraTarget (Node3D)
    └── SpringArm3D (+ CameraRig.gd)   ← arm_length, elevation_degrees set here
        └── Camera3D
```
CameraRig walks up the tree with `get_parent().get_parent()` to get the
CharacterBody3D. If you add a wrapper node between them, the camera breaks.

**NPC (NPC.gd):**
```
NPCNode (CharacterBody3D + NPC.gd)
├── MeshInstance3D
├── CollisionShape3D
├── BarkArea (Area3D)          ← must be named exactly "BarkArea"
│   └── CollisionShape3D
└── InteractArea (Area3D)      ← must be named exactly "InteractArea"
    └── CollisionShape3D
```
Assign an `NPCData` resource (.tres file from `/assets/npcs/`) in the Inspector.
Tier 0 background NPCs do NOT use NPC.gd — plain Node3D only.

**Two camera modes in CameraRig:**
- **Standard** (default): mouse horizontal rotates the Player3D body so Roland
  faces the camera's forward. W always moves toward the camera.
- **Freelook** (hold `freelook_camera` action, default F2): mouse orbits the
  camera arm without rotating Roland. On release, arm re-centers behind Roland.
  Used to look around without changing facing direction.

**VoxelLodTerrain (in World3D.tscn — wired and active):**
```
World3D (Node3D)
├── VoxelLodTerrain
│   ├── CubicHeightmapGenerator   ← custom GDScript noise generator (CHANNEL_COLOR + macro/mid/detail noise + per-voxel jitter)
│   └── VoxelStreamSQLite           ← per-save-slot delta DB
├── VoxelViewer (child of Player3D)
├── EntityStreamer
└── ...
```

**NoEditZone authoring pattern (interior or settlement scenes):**
```
SettlementRoot (Node3D)
├── NoEditZone (Area3D, group: "no_edit_zone")
│   └── CollisionShape3D (BoxShape3D or ConvexShape3D, ~50–100m buffer around structure)
├── BuildingProp (MeshInstance3D)   ← MagicaVoxel .glb export
├── BuildingProp_2 (MeshInstance3D)
└── ...
```
Every settlement, dungeon entrance, and lore landmark sits under a NoEditZone.
The `VoxelEditManager` autoload queries `NoEditZoneRegistry` before any voxel
write — writes inside a NoEditZone are silently rejected and trigger Roland's
bark *"This place doesn't yield to me."*

---

## Autoload registration status

Registered in `project.godot` (active now), in load order:
`GameState`, `TransitionManager`, `SaveNotification`, `PauseMenu`,
`DebugOverlay`, `FlagScheduler`, `InventoryManager`, `VoxelMaterialRegistry`,
`JournalUI`, `HUDOverlay`, `NoEditZoneRegistry`, `VoxelEditManager`,
`VoxelGravityManager`, `WaterFlowManager`, `Dialogic`, `BarkManager`, `WorldClock`,
`WeatherManager`

Load-order rules to preserve:
- `InventoryManager` MUST load before `VoxelMaterialRegistry` (the registry validates `yield_item_id` against `ITEM_REGISTRY` at startup).
- `VoxelMaterialRegistry` MUST load before `VoxelEditManager` (`EditToolHandler` queries the registry on every swing for material lookup).
- `NoEditZoneRegistry` MUST load before `VoxelEditManager` (the manager queries the registry on every edit).
- `VoxelEditManager` MUST load before `VoxelGravityManager` (the gravity manager subscribes to `edit_applied` in `_ready`).
- `VoxelEditManager` and `NoEditZoneRegistry` MUST load before `WaterFlowManager` (the flow manager subscribes to `edit_applied` and queries `is_water_flow_blocked_at` every flow tick).
- `WorldClock` MUST load before `WeatherManager` (the weather manager subscribes to `hour_changed` in `_ready`).
- `WaterFlowManager` MUST load before `WeatherManager` (the weather manager pushes wind into the water shader every frame via `set_global_wind`).

Note: the `JournalUI` autoload entry points at the **scene** `res://scenes/ui/Journal.tscn`, not at `scripts/JournalUI.gd` directly — the script is attached to the scene's root node. Every other autoload above points at a `.gd` file.

**NOT yet registered — must be added in Project Settings → Autoload when those systems land:**
- `scripts/SchematicLibrary.gd` → node name `SchematicLibrary` (built when player construction lands)

Scripts that reference these autoloads must guard with `get_node_or_null`
until they are registered, or they will crash on startup.

---
