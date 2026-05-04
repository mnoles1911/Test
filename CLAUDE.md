# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Game One — Project Bible

## What I'm building
A 3D voxel narrative RPG — Veloren meets Skyrim in atmosphere and open-world scale.
Single player. Real-time action combat (Witcher 3 / Dark Souls style), 1-vs-many, third-person over-shoulder camera.
Voxel world built in Godot 4.6.2 with Zylann's Voxel Tools plugin. GDScript only.
This is game one of a planned trilogy adapted from a 200-page source manuscript.

**Engine pivot confirmed (2026-04-30):** Switched from 2D pixel art to 3D voxel.
Full migration plan: `design/3D_VOXEL_MIGRATION.md`

## My background
I am a writer and game designer, not a programmer.
Always explain what code does in plain English before writing it.
Keep all scripts heavily commented.
Prefer simple, readable solutions over clever ones.
When I ask for something, tell me if there's a simpler way to achieve it.

## Genre and tone
Epic fantasy with grounded emotional stakes. Think LOTR's scale with 
a single protagonist's intimate perspective. The world feels ancient and real. 
Mira-Thal is a world of two continents in the third age of its existence. The western continent Mira is the heartland of civilization: four human kingdoms clustered at its center, the ancient Aelorin forests to the north, three dwarven mountain-kingdoms threading the Spine of the World, and the wild eastern frontier where the ash-lands begin. The eastern continent Thal is wilderness — unmapped beyond its fringes, dominated by the Ash Throne's influence, and anchored at its heart by the volcano Drûn-Khazad. The age is paradox: men are more numerous than ever, cities grow, trade flows — but the world's deeper fabric frays. The Aelorin dwindle. Dwarven kings grow old or greedy. Something bound two thousand years ago beneath the volcano is learning, slowly, to breathe again.

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
- **Milestones 1–3 (2D):** complete — walkable cave + lighting, Henrietta opening dialogue, combat prototype.
- **Milestone 4 (2D, PR #42):** complete — TransitionManager, expanded GameState, Zone framework, MainMenu/Settings/SaveSlotPicker, DebugOverlay, FlagScheduler, InventoryManager, expanded JournalUI, EnemyData.
- **3D pivot (PR #43):** complete — `design/3D_VOXEL_MIGRATION.md`, ART_DIRECTION, ART_PIPELINE, CAMERA_AND_PERSPECTIVE all rewritten for 3D voxel.
- **Milestone 4-3D (2026-05-01):** complete and verified in Godot — Player3D + CameraRig (standard + freelook), HUDOverlay, JournalUI 6-tab rewrite, CampfireFlicker3D, SpawnPoint3D / RoomTrigger3D / DialogueTrigger3D, Player3D.tscn / World3D.tscn placeholders, all UI resized to 1080p. Outstanding manual step: install Zylann's Voxel Tools plugin (GDExtension edition) from GitHub Releases at https://github.com/Zylann/godot_voxel/releases — NOT distributed via Godot's Asset Library because it ships native binaries.
- **Milestone 5-3D (largely complete, 2026-05-03):** Core destructible-voxel slice is shipping and verified in-game.
  - VoxelLodTerrain + `VoxelStreamSQLite` per-edit deltas ✅
  - **`CubicHeightmapGenerator`** (custom GDScript subclass of `VoxelGeneratorScript`) — replaced the originally-planned `VoxelGeneratorGraph` + Gaea EXR pipeline. Produces the procedural baseline via macro + mid + detail noise layers + per-voxel colour jitter, writing `CHANNEL_COLOR` for `VoxelMesherCubes`. Live-tunable via `@export_range` sliders + Preset enum (`LAY_OF_THE_LAND`, `MINECRAFT_BLOCKY`, `SMOOTH_GRADIENT`, `CUSTOM`). The Gaea EXR pipeline may return for v1 Mira terrain authoring later.
  - `VoxelEditManager` autoload (queue, NoEditZone gate, world→voxel coord conversion, per-frame voxel budget) ✅
  - `NoEditZoneRegistry` autoload ✅
  - Pickaxe carve verb (`EditToolHandler` + `InventoryManager` material yields) ✅
  - Explosive carve (`PowderCharge` + `ThrowableHandler`, camera-aimed throws, visible detonation flash) ✅
  - Swimming + drowning state machine (`Player3D._update_water_state`, `WaterVolume.gd`) ✅
  - Day/night cycle (`DayNightCycle.gd` driven by `WorldClock`) ✅
  - Ocean (sea level Y=6) + test water volume ✅
  - Jump on Space (when grounded) + fly-mode debug toggle ✅
  - Settings UI fully functional (manual `_input` dispatch since Dialogic intercepts GUI events project-wide) ✅
  - Outstanding: low-poly Blender Roland model (still a 0.4×1.7×0.25 m green box placeholder), MagicaVoxel exports (campfire, cave wall props), surface decoration pass (grass/stone vertical pillars to break up bare cube fields). See `DESIGNER_TODO.md` Section 7 for next-batch work and `design/LESSONS_LEARNED.md` for the bring-up bug log.

## Art specification (confirmed — 3D VOXEL)
- **Engine approach**: Godot 4.6.2, 3D. Voxel world via Zylann's Voxel Tools plugin.
- **Voxel scale**: 6 voxels per meter (locked 2026-05-03 — each block is ~16.7 cm, chunky enough to read as cubic but finer than Minecraft's 1m cubes; player is ~11 voxels tall at 1.8 m)
- **Terrain**: `VoxelLodTerrain` + `VoxelMesherCubes` (blocky stepped terrain, matches MagicaVoxel building style). Procedural baseline produced by **`CubicHeightmapGenerator`** (custom `VoxelGeneratorScript` GDScript subclass — `scripts/CubicHeightmapGenerator.gd`) writing `CHANNEL_COLOR` per voxel via layered noise (macro 30 m relief + mid 2 m rolling hills + detail 50 cm grain) and per-voxel colour jitter (~±25 % brightness). Replaces the planned VoxelGeneratorGraph + Gaea EXR pipeline; Gaea may return for v1 Mira authoring later. **Editable / destructible by default** — every voxel can be modified by player edits (axe, pickaxe, shovel, explosive, spell). Non-destructible regions are the exception, declared via `NoEditZone` Area3D volumes. Edits stored as deltas in `VoxelStreamSQLite` (`user://voxel_deltas.sqlite`). Edits persist forever (no world healing). LOD-bake-on-eviction is **deferred** — edited chunks far from the player currently re-render from disk deltas via Zylann's standard streaming. Canonical spec: `design/3D_VOXEL_MIGRATION.md` → "Destructible Terrain".
- **World scale**: Playable Mira 12km × 10km, compression 125:1 linear (1 game meter ≈ 125 fictional meters). Playable Thal ~7km × 5.5km.
- **Props/buildings**: MagicaVoxel → export .glb → Godot MeshInstance3D. All narratively load-bearing structures (settlements, dungeon entrances, lore landmarks) sit on top of the voxel surface inside NoEditZones — never carved into voxels.
- **Player-built structures**: hybrid — schematic props (crafted at the Carpentry Bench: walls, roofs, doors, fences) for the bulk + per-voxel placement (Build Mode → Detail submode) for custom detailing.
- **Characters**: Low-poly Blender models from Act I onward (.glb, 200–500 tris named characters, flat-shaded, rigged). No billboard sprites for characters. Portraits (256×320 px) unchanged for dialogue UI.
- **Camera**: SpringArm3D third-person over-shoulder, ~15° above horizontal, player-rotatable. Lock-on system for 1-vs-many melee combat.
- **Lighting**: OmniLight3D (torches/fire) + DirectionalLight3D (sun/moon) + WorldEnvironment SSAO + fog
- **Pipeline reference**: `design/ART_PIPELINE.md`
- **Migration plan**: `design/3D_VOXEL_MIGRATION.md`

## What I never want
- Complex code I can't understand
- Systems built before I need them
- C# — GDScript only
- Any advice to switch engines

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

**NPC system (in place):**
- `NPC.gd` — CharacterBody3D base script for Tier 1–3 NPCs; bark firing, E-press dialogue, disposition, schedule dispatch
- `NPCData.gd` — Resource: npc_id, Tier enum, disposition, bark_triggers, schedule entries (one .tres per character, expected in `/assets/npcs/` once that directory exists)
- `NPCScheduleEntry.gd` — Resource: hour_start, hour_end, location_id, animation

**Voxel + world systems (in place, autoloaded):**
- `VoxelEditManager.gd` — autoload. Async edit queue (per-frame voxel budget cap), `EditedChunkRegistry` (`Dictionary<Vector3i, bool>` of chunks with deltas), NoEditZone enforcement before every `VoxelTool.do_*` call, `WORLD_GENERATOR_VERSION` constant (currently 8) stamped into saves. Coord conversion handles `terrain.transform.scale = 0.166667` (6 vox/m) → voxel-grid space. **Always route voxel writes through this autoload.** See `design/3D_VOXEL_MIGRATION.md` → "Destructible Terrain".
- `NoEditZoneRegistry.gd` — autoload. Registers Area3D volumes by group `no_edit_zone`. Provides `is_point_inside_no_edit_zone(world_pos: Vector3) -> bool`. Queried by `VoxelEditManager` before any voxel write.
- `CubicHeightmapGenerator.gd` — `@tool` `VoxelGeneratorScript` subclass attached to the `VoxelLodTerrain` node in `World3D.tscn` (NOT an autoload). Live-tunable via `@export_range` sliders + Preset enum (LAY_OF_THE_LAND / MINECRAFT_BLOCKY / SMOOTH_GRADIENT / CUSTOM). Replaces the originally-planned VoxelGeneratorGraph + Gaea EXR pipeline.
- `WorldClock.gd` — autoload. Ticks in-game time (240 real s = 1 game hour); emits `hour_changed`, `time_of_day_changed`, `day_changed`; calls `update_schedule(hour)` on `scheduled_npcs` group; pauses during Dialogic timelines; `set_time()` / `advance_hours()` for debug/rest. Save/load includes the wall-clock state.
- `BarkManager.gd` — autoload. Loads bark pools from `dialogue/scripts/barks/{category}/{npc_id}.txt`; picks random non-repeating line; plays spatial audio from `assets/audio/barks/`; falls back to Output print if BarkOverlay UI is absent.
- `WaterVolume.gd` — script attached to any Area3D in the `water_volume` group. Exposes `surface_y` (world-space) and `get_current_velocity()` for river flow. Player3D polls overlapping volumes per-frame for swim physics.
- `DayNightCycle.gd` — Node script on `World3D` driving Sun + Moon `DirectionalLight3D` rotation and sky/fog colour from `WorldClock`'s continuous hour float.
- `EditToolHandler.gd` — child of Player3D. Pickaxe/axe/shovel swing detection: raycast from camera, NoEditZone-gated voxel removal via `VoxelEditManager`, material yield to `InventoryManager`.
- `ThrowableHandler.gd` — child of Player3D. Throw input (default key 1) instances throwables, copies `voxel_aoe_radius` + `combat_damage` from `ITEM_REGISTRY` onto the spawned RigidBody3D, applies camera-aimed velocity (carries pitch).
- `PowderCharge.gd` (and the throwable scene) — RigidBody3D explosive. Impact-only detonation, sphere carve via `VoxelEditManager`, visible OmniLight3D + emissive sphere flash that animates and self-frees via Tween.
- `VoxelGravityManager.gd` — autoload. Subscribes to `VoxelEditManager.edit_applied`. After every edit, runs a local 16 m flood-fill (capped 32 m) to find voxels that lost support, carves them from terrain via bulk write, and spawns `FallingVoxelCluster` `RigidBody3D` instances per disconnected island. Local detection — anything connected to the analysis bubble's edge is treated as anchored. Caps: max cluster size 4096 voxels, max active clusters 32, one bubble processed per physics frame.
- `FallingVoxelCluster.gd` + `scenes/voxel/FallingVoxelCluster.tscn` — `RigidBody3D` representing one airborne voxel chunk. Custom centre of mass at the voxel-weighted centroid (so L-shapes tumble correctly). Tall thin clusters (height ≥ 3× horizontal) get a directional tip impulse pointing away from the edit origin (felled trees fall toward the cut). Tiny random angular nudge breaks perfect-vertical equilibrium. Re-deposits as terrain via `VoxelEditManager.queue_set_voxels_bulk` when the body sleeps (or after a 10 s failsafe). Damages bodies with a `health` property: `voxel_count × fall_height × 0.05`, with a 1.5 m minimum fall.
- `VoxelClusterBuilder.gd` — static utility (no state). Builds an `ArrayMesh` from a cluster Dictionary (`Vector3i → packed RGBA`), with per-face culling so interior cube faces are skipped. Also computes the cluster's local AABB, voxel-weighted centroid, and the centre-offset that the mesh build needs to make the rigid body pivot around its true centre of mass. Caches a single shared `StandardMaterial3D` (`vertex_color_use_as_albedo = true`) used by every cluster.

**Specified in design docs but not yet implemented** (build in dependency order):
- `SchematicLibrary.gd` — autoload. Registry of placeable building schematics (`.glb` props with placement metadata in `assets/voxel/schematics/`). Player crafts schematics at the Carpentry Bench; placements saved to `user://saves/slot_{N}/placed_schematics.json`.
- `EntityRegistry.gd` — spatial dictionary of every world entity keyed by chunk; lightweight `EntityRecord` data objects; does not instantiate nodes itself.
- `EntityStreamer.gd` — node in `World3D.tscn`; instantiates / saves / `queue_free()`s entities by player range.
- `FactionManager.gd` — wraps GameState faction disposition flags (design/FACTION_SYSTEM.md).
- `QuestManager.gd` — quest flag management (design/QUEST_SYSTEM.md).
- `WeatherManager.gd` — weather state, WorldEnvironment tweening, weather overrides (design/WEATHER_AND_ENVIRONMENT.md).
- `CompanionManager.gd` — companion active state, HP, save serialization (design/COMPANION_SYSTEM.md).
- LOD-bake-on-eviction caching under `user://saves/slot_{N}/mesh_cache/` — render optimization for edited chunks far from the player. **Deferred** until perf becomes an issue; current LOD streaming is sufficient.

Manual setup still required: see `DESIGNER_TODO.md` → Section 1 (Zylann Voxel Tools install, audio bus layout per `design/AUDIO_DESIGN.md`).

## World coordinate reference (playable Mira, origin = NW corner)
| Location | Game x | Game z |
|---|---|---|
| Caer Brannoch | 880m | 2,200m |
| Lirien-Thal | 1,950m | 2,800m |
| Karaz-Dûn | 5,200m | 2,300m |
| Aldenholt | 4,400m | 5,800m |
| Brightwatch | 5,200m | 4,600m |
| Khorumzad | 5,200m | 5,800m |
| Solgrade | 4,000m | 7,400m |
| Kazaad-Brak | 5,200m | 9,000m |
| Mor-Vethrin | 6,700m | 2,200m |

## Canonical naming (frequent contradictions)
- Eldermark royal house: Castrove (NOT Vane)
- Aldric the blacksmith: Aldric Vane (Caelborn line / Aescryd-blooded, not the investigator)
- The Caelborn investigator: Edran Vane
- Dagna's surname: Irontrack (NOT Ironkeep)
- Corvus's surname: Tane (NOT Aldenmere)
- Vault of Aen-Vael location: below Khorumzad in the Spine of Mira (NOT below Drûn-Khazad)
- The third dwarven god: Kradir the Unmoving

## Legacy files
IsometricRPGMono/ and title_screen.svg are leftovers from a prior MonoGame prototype. They are not part of Game One and should not be referenced or extended. They can be deleted when convenient.

---

## Godot workflow

There is no CLI build, lint, or test command for this project. To verify changes work:
1. Open the project in Godot 4.6.2
2. Run the relevant scene (World3D.tscn for 3D movement/lighting, Combat.tscn for legacy 2D combat)
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
`DebugOverlay`, `FlagScheduler`, `InventoryManager`, `JournalUI`, `HUDOverlay`,
`NoEditZoneRegistry`, `VoxelEditManager`, `VoxelGravityManager`, `Dialogic`,
`BarkManager`, `WorldClock`

Load-order rules to preserve:
- `NoEditZoneRegistry` MUST load before `VoxelEditManager` (the manager queries the registry on every edit).
- `VoxelEditManager` MUST load before `VoxelGravityManager` (the gravity manager subscribes to `edit_applied` in `_ready`).

Note: the `JournalUI` autoload entry points at the **scene** `res://scenes/ui/Journal.tscn`, not at `scripts/JournalUI.gd` directly — the script is attached to the scene's root node. Every other autoload above points at a `.gd` file.

**NOT yet registered — must be added in Project Settings → Autoload when those systems land:**
- `scripts/SchematicLibrary.gd` → node name `SchematicLibrary` (built when player construction lands)

Scripts that reference these autoloads must guard with `get_node_or_null`
until they are registered, or they will crash on startup.

---

## Pipeline tools (run from repo root)

**strip_draft.py** — converts a human-readable dialogue draft to a clean TTS script:
```bash
python3 tools/strip_draft.py dialogue/drafts/act1_scene_sorting_room.md
# writes → dialogue/scripts/act1_scene_sorting_room.txt
```
Extracts only spoken lines from the `## Script (Prose)` section. Deterministic —
same draft always produces the same output. Does NOT invent performance tags.

**render_bulk.py** — renders a TTS script to audio via ElevenLabs:
```bash
ELEVENLABS_API_KEY=<key> python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt
# writes → assets/audio/dialogue/act1_scene_sorting_room/*.ogg
# writes → assets/audio/dialogue/act1_scene_sorting_room/manifest.json
```
Idempotent — reruns skip lines whose text hash is unchanged. Shows cost estimate
before any network call. Default hard cap: $5 per run (`--cost-cap` to change).
Requires `dialogue/CHARACTER_VOICES.md` to have voice IDs for every character in the script.
