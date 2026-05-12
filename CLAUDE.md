# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Game One — Project Bible

## What I'm building
A 3D voxel narrative RPG — Veloren meets Skyrim in atmosphere and open-world scale.
Real-time action combat (Witcher 3 / Dark Souls style), 1-vs-many, first person and third camera cameras, cooperative multiplayer with 1-4 friends.
Voxel world built in Godot 4.6.2 with Zylann's Voxel Tools plugin. GDScript by default; C++ GDExtension is allowed for hot voxel paths when measured GDScript cost is the bottleneck (e.g. the per-block voxel generator).
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
One-line history; see git log for detail. The autoload + voxel-systems sections below document what's live now.
- **Milestones 1–4 (2D):** walkable cave, opening dialogue, combat prototype, UI/state framework.
- **3D pivot (2026-04-30, PR #43):** all art/camera/migration design docs rewritten for voxel.
- **Milestone 4-3D (2026-05-01):** Player3D, CameraRig, HUDOverlay, JournalUI, triggers, World3D placeholder.
- **Milestone 5-3D (2026-05-03):** destructible voxel slice — VoxelLodTerrain + SQLite deltas, CubicHeightmapGenerator, edit/gravity/water managers, NoEditZones, pickaxe + explosives, swimming, day/night.
- **Milestone 6-3D Weather (2026-05-04):** WeatherManager six-state machine + fog/wind/particles/lightning + location profiles.
- **Voxel water refactor (2026-05-05):** Area3D water → voxel-cell flow sim (`WaterFlowManager` 4 Hz, `WaterChunkMesher` transparent surfaces, `CHANNEL_DATA5` byte storage).
- **Copper Isles demo + textured tileset (2026-05-06 → 05-10):** `CopperIslesHeightmapGenerator.gd` reads a 5 km Gaea EXR; bake pipeline at `scenes/_dev/BakeWorld.tscn` writes the SQLite baseline; `HorizonSkirt.gd` covers distant peaks. Mesher migrated `VoxelMesherCubes` → `VoxelMesherBlocky` (material id in `CHANNEL_TYPE` + `VoxelBlockyLibrary`); 12 textured materials via `tools/build_texture_atlas.py`. World-scale refactor: sea level Y=125, spawn (-61, 185, 732). Bootstraps re-apply per-cube `tile_*` + `material_override_0` at runtime (Zylann gdextension drops them on `.tres` load). Caches bumped to `*_v13.sqlite`. **Caveat:** delivered EXR is a single continent, not the lore-spec archipelago — re-source pending.
- **Tiered voxel-generation rules (2026-05-10 → 05-11):** Six tiers on top of the depth-only band rule, all driven by `VoxelMaterial.gd` per-material fields + `VoxelGenerationMath.hash3`. Order: T1 cliff slope (4-neighbour `ground_y` drop ≥ threshold → bare stone), T2 snow line (altitude + jitter, id 13), T3 marble/stone_dark jitter on plain stone, T4 ore veins (per-ore 3D-noise gate, parent-material match), T5 clay/gravel disks (Worley anchor grid near water), T6 cliff outcrops (composes T1 + T4 ore list). `VoxelMaterialRegistry` pre-builds filtered ore/disk arrays; bootstraps push them to the generator on the main thread. Cache paths bumped to `*_v14.sqlite`.
- **Voxel Combat v1 (2026-05-10 → 05-11):** `Enemy3D` base + `Goblin` (IDLE/ALERT/COMBAT eye-glow); `ThrowableSpear` (sticks on impact, pivots with corpse, auto-collects); `BloodVFX` autoload (burst/dust/drip/pool — `PlaneMesh` not `Decal` because gl_compatibility); `CombatTest.tscn` dev arena with F1 menu. Phase 3 (charge) + Phase 5 (gibs + time-slow) deferred — see `design/COMBAT_NEXT_PHASES.md`.
- **C++ generator port (2026-05-11):** `CubicHeightmapGenerator.gd` ported to a C++ GDExtension under `extensions/voxel_gen/`. All 6 tiers + bedrock + water-byte emission bit-exact verified by `scripts/_dev/GeneratorParityHarness.gd` (389k voxel comparisons). `World3D.tscn` uses `CubicHeightmapGeneratorAdapter` (GD VoxelGeneratorScript) → `CubicHeightmapGeneratorCpp` (godot::Resource); the adapter forwards `set_ore_materials`/`set_disk_materials` so the existing bootstrap call sites work unchanged. NoEditZone water-generation suppression dropped. Bake controller (`WorldBakeController.gd`) gained `wait_per_position_s` / `bake_y_min_voxels` / `bake_y_max_voxels` `@export`s, dynamic time-estimate labels, and a `cpp_impl` drill-through for sea_level reads. `CopperIslesHeightmapGenerator.gd` is **not** ported. See "C++ perf opportunities" section below for next targets.

Outstanding content pickups: low-poly Blender Roland model, MagicaVoxel prop exports (campfire, cave walls), surface decoration pass, ambient weather audio, region-boundary profile auto-swap. See `DESIGNER_TODO.md`.

## Art specification (3D VOXEL)
- **Voxel scale**: 6 voxels/m (locked 2026-05-03; ~16.7 cm/block, player ~11 voxels tall).
- **Terrain**: `VoxelLodTerrain` + `VoxelMesherBlocky` reading `CHANNEL_TYPE` (8-bit material id), backed by `VoxelBlockyLibrary` (per-cube atlas tiles + alpha-scissor `StandardMaterial3D`). Procedural baseline from `CubicHeightmapGenerator`. Default texture pack lives in `assets/voxels/texture_packs/default/` — atlas at 32 px tile × 64 cols/rows. **Destructible by default** — `NoEditZone` Area3D volumes are the exception. Edits stored as deltas in `VoxelStreamSQLite`, persist forever.
- **World scale**: Playable Mira 12 km × 10 km (compression 125:1). Thal ~7 km × 5.5 km.
- **Props/buildings**: MagicaVoxel → .glb. Narratively load-bearing structures sit inside NoEditZones, never carved.
- **Player-built**: schematic props (Carpentry Bench) + per-voxel detailing (Build Mode).
- **Characters**: Blender low-poly .glb (200–500 tris). Portraits unchanged for dialogue.
- **Camera**: SpringArm3D third-person, ~15° above horizontal, lock-on for 1-vs-many.
- **Lighting**: OmniLight3D + DirectionalLight3D + WorldEnvironment SSAO + fog.
- **Canonical refs**: `design/3D_VOXEL_MIGRATION.md` (full spec), `design/ART_PIPELINE.md`, `design/ART_DIRECTION.md`.

## What I never want
- Systems built before I need them
- C# — never. GDScript is the default language; C++ GDExtension is the only other allowed escape hatch, and only for measured hot paths (the voxel generator is the canonical example). Don't reach for it speculatively.

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
| design/ASSET_PIPELINE_AI.md | New AI tool replaces a recommended one, character voxel scale changes, new asset class added, or a pipeline workaround needs documenting |
| design/COMBAT_NEXT_PHASES.md | Combat / physics / enemy roadmap item completes or shifts priority; new enemy type or combat mechanic added |
| design/ITEM_LIBRARY.md | New craftable items, recipes, or input materials added to any section |
| design/SKILLS_AND_PROGRESSION.md | New perks, sub-skills, or trainer NPCs added; XP values tuned |
| design/TTS_PIPELINE.md | Render tooling lands, voice IDs lock for a new character, manifest schema changes |
| design/FACTION_SYSTEM.md | Factions added/removed, disposition triggers tuned, lockout thresholds change |
| design/QUEST_SYSTEM.md | New quest patterns, resolution outcomes, or timed-event rules added |
| design/MINI_GAMES.md | New mini-game added, or mechanics / stakes / skill integration revised |
| design/INPUT_AND_CONTROLS.md | New Input Map action added (must also update DESIGNER_TODO.md Section 1) |
| design/NPC_SYSTEM.md | NPC tier rules, schedule mechanics, or WorldClock integration changes |
| design/LOCKPICKING.md | Lock tiers, pick types, or skill-tier hold-timer values change |
| dialogue/CHARACTER_VOICES.md | New voiced character is added, or a render contract changes (voice ID, seed, stability) |
| dialogue/PRONUNCIATION.md | Any new lore proper noun is introduced (place names, gods, titles) |
| DESIGNER_TODO.md | New design doc lands that requires editor or asset work; tasks completed |
| design/COPPER_ISLES_BAKE_NOTES.md | Zylann GDExtension probe results change, new bake-pipeline decisions, or bake controller `@export`s added |
| design/COPPER_ISLES_DEMO_HEIGHTMAP.md | Copper Isles island layout, heightmap spec, or import notes change |
| extensions/voxel_gen/ + memory/project_voxel_gen_cpp_port.md | New tier ported, new POD snapshot field added, new C++ Resource registered, parity harness extended |
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
- design/MINI_GAMES.md — all skill-based activities: smithing forge phase, fishing, Bones (dice), The Fold (cards), axe throwing, archery, herbalism, arm wrestling, sculpture contest; each covers visuals, loop, skill integration, and stakes

**Art and pipeline:**
- design/ART_DIRECTION.md — palette, location visual identity, architecture by region, shaders
- design/CAMERA_AND_PERSPECTIVE.md — why the 3/4 view is an art style, not a camera transform
- design/TECH_STACK.md — full technology stack: every tool, plugin, and pipeline; current generator (`CubicHeightmapGenerator`); autoload status table (kept in sync with `project.godot`)
- design/ART_PIPELINE.md — MagicaVoxel, Zylann plugin, Blender. Note: the Gaea → EXR → VoxelGeneratorGraph pipeline section is aspirational (planned for v1 Mira authoring); current implementation uses `CubicHeightmapGenerator`
- design/ASSET_PIPELINE_AI.md — AI-heavy pipeline for 3D characters/enemies (Nano Banana → Meshy → Blender voxelize → Mixamo + Cascadeur), with two prompts per asset (3D-conversion ready vs. concept/mood), Blender bridge steps, and 18 SFX prompts for ElevenLabs Audio. Companion to ART_PIPELINE.md; together they cover manual + AI workflows.
- design/3D_VOXEL_MIGRATION.md — full pivot plan: what changes, what survives, 3D milestones

**Planning and ops:**
- design/MILESTONE_ROADMAP.md — Act I scene breakdown and ordered deliverables for Phases 4+
- design/ENDGAME_CHOICES.md — Game Three endgame and trilogy-spanning choice consequences
- design/DIALOGIC_SETUP.md — step-by-step Dialogic 2 installation and character setup
- design/TTS_PIPELINE.md — AI-assisted draft → ElevenLabs render → Dialogic handoff (bulk vs craft pipelines, filename + manifest contract)
- design/LESSONS_LEARNED.md — running log of bugs and fixes
- design/COPPER_ISLES_DEMO_HEIGHTMAP.md — AI prompt + per-island terrain spec for the 5 km × 5 km Copper Isles heightmap (specifies an archipelago; current EXR delivers a single continent — see "Heightmap divergence from lore" in milestone history); Godot import notes
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

**Combat system (in place — v1 slice, see `design/COMBAT_NEXT_PHASES.md` for what's next):**
- `Enemy3D.gd` — base CharacterBody3D for all enemies; `health` / `max_health`, `take_damage(amount, hit_dir, hit_point)`, `die(damage_at_kill, ...)`. IDLE / ALERT / COMBAT state machine driven by distance to player (group `player`). Spawns a 2 m sphere `Area3D` on death for E-press corpse looting; `_loot_corpse()` virtual hook for subclasses. Corpse auto-frees after `corpse_lifetime_seconds` (default 300). Subclass override hooks: `_enemy_physics_step`, `_on_state_changed`, `_on_damaged`, `_on_died`, `_loot_corpse`.
- `enemies/Goblin.gd` + `scenes/enemies/Goblin.tscn` — v1 enemy. Walk-toward-player in COMBAT, contact damage on overlap. Eye glow material `emission_energy_multiplier` 0/2/6 by state (eyes at -Z = front per Godot convention). On death: lays placeholder visual flat (-90° X rotation) and rotates `ChestSocket` with it so embedded spears pivot like an arrow buried in a fallen body. Loot: returns embedded spears to inventory.
- `throwables/ThrowableSpear.gd` + `scenes/throwables/throwable_spear.tscn` — RigidBody3D projectile. Orients along velocity in flight; on impact, the synchronous path runs damage + VFX, the deferred path (`call_deferred`) handles freeze + collision-layer changes + reparent (Godot forbids these inside body_entered physics callbacks). Ignores bodies in group `player`. Terrain: auto-collects within 1.5 m. Enemy: reparents to `ChestSocket`, rides corpse rotation. Registered in `InventoryManager.ITEM_REGISTRY` as `spear` (combat_damage 30).
- `BloodVFX.gd` autoload — pooled `GPUParticles3D`. API: `spawn_burst(pos, dir, intensity)` (12-pool), `spawn_dust(pos, normal)` (8-pool), `start_drip(target, socket)` / `stop_drip(target)` (per-target instance reparented to `ChestSocket`, `local_coords = false` so particles drip in world space even when host is stationary), `spawn_pool(pos, max_size, grow_seconds)` (flat `PlaneMesh` quad with procedural radial-gradient texture; was `Decal` until renderer compatibility forced the swap). All particle scenes ship with `StandardMaterial3D { vertex_color_use_as_albedo = true, shading_mode = unshaded, transparency = alpha }` so per-particle gradient colors actually render.

**Voxel + world systems (in place, autoloaded):**

For deep mechanics, read the script header in each `.gd` file. This is a quick reference for what's wired and what its public surface looks like.

- `VoxelEditManager.gd` — async edit queue, NoEditZone gate, EditedChunkRegistry, `WORLD_GENERATOR_VERSION` stamping. **Always route voxel writes through this autoload.** Emits `edit_applied` signal.
- `NoEditZoneRegistry.gd` — registers `no_edit_zone` group Area3Ds. API: `is_point_inside_no_edit_zone(world_pos)`.
- `CubicHeightmapGeneratorCpp` (C++) + `CubicHeightmapGeneratorAdapter.gd` — the World3D terrain generator (Mira) since 2026-05-11. C++ Resource holds the inner loop (`extensions/voxel_gen/src/cubic_heightmap_generator.cpp`); a thin GDScript adapter extends `VoxelGeneratorScript` and forwards `_generate_block` + `set_ore_materials` / `set_disk_materials` / `get_ground_voxel_y_at` to it. The legacy GDScript `CubicHeightmapGenerator.gd` and its parity harness were retired in Phase 6 (2026-05-12); the C++ class is the canonical source for the cubic generator's tier rules.
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
- `WorldBakeController.gd` + `scenes/_dev/BakeWorld.tscn` (Copper Isles) + `scenes/_dev/BakeWorld3D.tscn` (Mira / C++ generator) — UI-driven bake that walks a `VoxelViewer` across the XZ grid, streams + persists every chunk to a baseline SQLite. Controller is generator-agnostic; `@export`s on the scene node tune `wait_per_position_s` (1 s for C++, 6 s for the GD heightmap), Y-clip range, etc. Run in-game; tile-classifier skips DEEP_OCEAN; LAND uses a single ground-anchored stop.
- `SkirtBaker.gd` — builds the horizon-skirt ArrayMesh from the Copper Isles EXR (~12 800 tris for 5 km map). Saves `assets/voxel/copper_isles_skirt.res`. Copper Isles only.
- `ParityProbe` (C++ class in `extensions/voxel_gen/`) — exposes `hash3` + `cliff_threshold_for_angle_voxels` from the C++ math layer so GDScript-side parity harnesses can verify bit-exact agreement with the GD `VoxelGenerationMath` originals. Retained between ports as scaffolding for the next C++ port. The cubic-era harness `GeneratorParityHarness.gd` was retired in Phase 6 along with the GD generator it was comparing against; rebuild a parity harness scoped to the new port when porting `CopperIslesHeightmapGenerator.gd` (or any future GD→C++ migration).
- `CombatTestBootstrap.gd` + `scenes/_dev/CombatTest.tscn` — flat dev arena with three placeholder goblins. F1 debug panel: R reset, Q quit, F8 kill nearest, F9 wound nearest. Spear pre-equipped.

**Specified in design docs but not yet implemented** (build in dependency order):
- **Combat / physics / enemy next phases** — see `design/COMBAT_NEXT_PHASES.md` for the full roadmap (Phase 3 charge mechanic, Phase 5 gib clusters + time-slow + spear-stick polish, melee combat from `design/COMBAT_DESIGN_3D.md`, Ashfallen / Wolf / Bear enemy types from `design/ENEMY_AI.md`, group AI / attack tokens / fleeing).
- `SchematicLibrary.gd` — autoload. Registry of placeable building schematics (`.glb` props with placement metadata in `assets/voxel/schematics/`). Player crafts schematics at the Carpentry Bench; placements saved to `user://saves/slot_{N}/placed_schematics.json`.
- `EntityRegistry.gd` — spatial dictionary of every world entity keyed by chunk; lightweight `EntityRecord` data objects; does not instantiate nodes itself.
- `EntityStreamer.gd` — **stub on disk** (`scripts/EntityStreamer.gd`). Currently only prints chunk-enter events in Output. Full load/unload logic deferred to Phase 6-3D.
- `FactionManager.gd` — wraps GameState faction disposition flags (design/FACTION_SYSTEM.md).
- `QuestManager.gd` — quest flag management (design/QUEST_SYSTEM.md).
- `CompanionManager.gd` — companion active state, HP, save serialization (design/COMPANION_SYSTEM.md).
- LOD-bake-on-eviction caching under `user://saves/slot_{N}/mesh_cache/` — render optimization for edited chunks far from the player. **Deferred** until perf becomes an issue; current LOD streaming is sufficient.

Manual setup still required: see `DESIGNER_TODO.md` → Section 1 (Zylann Voxel Tools install, audio bus layout per `design/AUDIO_DESIGN.md`).






## C++ GDExtension perf opportunities

Game One is GDScript-first; the C++ GDExtension at `extensions/voxel_gen/` is the
escape hatch for measured hot paths. One generator is ported (2026-05-11). The
build chain is locked: LLVM-MinGW UCRT + `python -m SCons platform=windows
target=template_debug use_mingw=yes -j8` from `extensions/voxel_gen/`.
godot-cpp only auto-wraps engine-core classes — Zylann classes can't be
subclassed directly, so the port pattern is **C++ extends `godot::Resource` +
thin GDScript adapter extends `VoxelGeneratorScript`** and forwards by Variant
call. Mirror this for any future port.

**Done:**
- `CubicHeightmapGeneratorCpp` — all 6 tier rules + bedrock + water byte +
  ore/disk POD snapshots. Was parity-verified by a cubic-era `GeneratorParityHarness.gd`
  that has since been retired (Phase 6); the C++ class is the canonical source now.

**Likely-worthwhile next targets**, in rough order of payoff vs. effort:

1. **`CopperIslesHeightmapGenerator.gd`** (M, big win if Copper Isles bakes stay
   in the loop). Reads an EXR `Image`, samples bilinearly, layers the same Tier
   1-6 rules. Port pattern transfers verbatim from cubic; only difference is the
   noise sample becomes an `Image::get_pixel` lookup. Without this, the
   Copper Isles bake still runs the GD inner loop.

2. **`WaterChunkMesher.gd`** (M). Greedy 2D run-merge across `CHANNEL_DATA5`
   columns per chunk, ArrayMesh build. Currently runs in GDScript on the main
   thread with an adaptive frame budget that throttles to 1 chunk/frame under
   load — visible as water mesh pop when terrain is streaming. Porting moves
   the per-chunk scan + ArrayMesh construction off the main thread (or at
   least into native code) and removes the throttle pressure.

3. **`WaterFlowManager.gd`** flow tick (M). 4 Hz scan over chunks within 20 m
   of the player, per-voxel level/source/tick byte reads and writes. Currently
   sits in the per-second `[PERF]` top-3 contributors. The `WaterByteCodec`
   layout is already a pure POD (`level | source_bit | tick`) so the port is
   mostly buffer iteration. Pushing this to C++ would let the tick rate climb
   without main-thread cost.

4. **`VoxelGravityManager.gd`** flood-fill (S-M). Subscribes to `edit_applied`,
   does a 16 m local BFS for unsupported voxels, spawns `FallingVoxelCluster`.
   The BFS itself is pure neighbour walking; a clean port. Worth doing only if
   gravity scans start showing up in PERF — currently not load-bearing.

5. **Generic chunk-bytes scratch buffers** (S). Several GD systems
   (`WaterFlowManager`, `WaterChunkMesher`, `VoxelGravityManager`) each do their
   own per-chunk `VoxelBuffer.get_voxel` × N copy into a `PackedByteArray`
   before scanning. A shared C++ "snapshot a chunk's CHANNEL_TYPE + DATA5 into
   a flat buffer" helper amortises that across systems.

**Probably NOT worth porting** (Zylann does the heavy work, or the cost is
elsewhere):
- Voxel mesh build (`VoxelMesherBlocky` is already Zylann C++).
- Chunk streaming / LOD octree scheduling (`time_detect_required_blocks` in
  the `[DIAG]` line is Zylann's main-thread work — we can't optimise their
  code from outside it).
- `VoxelEditManager` queue management — already cheap; bound by Zylann's
  `VoxelTool` write path, not the GD wrapper.
- The MILESTONE_ROADMAP item "LOD-bake-on-eviction caching" deferred until perf
  becomes an issue — the C++ generator already shrinks the cost that motivated
  that idea. Reconsider only if streaming gaps persist after #1 and #2 above.

**Process for any future port:**
1. Pick a target with a clearly-bounded function surface; prefer pure-math hot
   loops over anything that touches the SceneTree (worker threads can't).
2. Write the parity harness FIRST as a `@tool` EditorScript in `scripts/_dev/`.
   Use `ParityProbe` to compare C++ math primitives against `VoxelGenerationMath`,
   and per-chunk byte diffs to compare generated `VoxelBuffer`s. Bit-exact output
   on the same inputs is the only acceptable gate.
3. Set up POD snapshot infra if the C++ side needs Resource data that lives in
   GDScript (mirror the `set_ore_materials(Array[Dictionary])` adapter pattern).
4. Land the port in sub-phases each ending in a green parity harness — never
   commit a phase that breaks parity, even if you "know" the diff is benign.
5. Adapter forwards every public method the bootstrap calls; check
   `has_method` gates in production callers won't silently skip.

See `memory/project_voxel_gen_cpp_port.md` for the full Phase 0-5 receipt of
how the cubic generator port was done.

---

## Godot workflow

There is no CLI build, lint, or test command for the Godot side. To verify changes:
1. Open the project in Godot 4.6.2.
2. Run the relevant scene:
   - `World3D.tscn` — Mira; uses the C++ generator via adapter.
   - `CopperIslesTest.tscn` — Copper Isles heightmap (still on GDScript generator); F7 cycles terrain scale.
   - `scenes/_dev/BakeWorld.tscn` (Copper Isles bake) / `scenes/_dev/BakeWorld3D.tscn` (Mira bake) — UI-driven bake; must run in-game.
   - `scenes/_dev/CombatTest.tscn` — combat dev arena, F1 debug menu, spear pre-equipped.
3. Check the Output panel.

The C++ GDExtension has its own build: `python -m SCons platform=windows target=template_debug use_mingw=yes -j8` from `extensions/voxel_gen/`. Godot must be closed or scons may fail on DLL replacement. After build, reload the Godot editor. When a port is in flight, parity-check via the port's own `@tool` harness in `scripts/_dev/` (File → Run).

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

**UI buttons / sliders need MANUAL `_input` dispatch — do NOT rely on `Button.pressed` or `HSlider` drag:**
```gdscript
# WRONG — these signals never fire in this project. Godot's GUI input
# dispatch is silently disabled (Dialogic's input subsystem consumes
# InputEventMouseButton globally). Layout, anchors, mouse_filter, even
# CanvasLayer-vs-Control roots are NOT the cause — events simply never
# enter the GUI input pipeline. See LESSONS_LEARNED.md 2026-05-03 + 2026-05-09.
my_button.pressed.connect(_on_pressed)
my_slider.value_changed.connect(_on_slider_changed)

# RIGHT — every UI scene in this project (PauseMenu, MainMenu, Settings,
# DiceGameUI) implements its own _input handler and routes clicks via
# get_global_rect().has_point(pos). Reference impl: PauseMenu._input /
# _dispatch_click / _hits.
func _input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton):
        return
    var mb: InputEventMouseButton = event
    if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
        return
    _dispatch_click(mb.position)

func _dispatch_click(pos: Vector2) -> void:
    if _hits(_my_button, pos):
        _on_my_button_pressed()
        return
    # Slider: translate click X into value
    if _my_slider.visible and _my_slider.get_global_rect().has_point(pos):
        var rect := _my_slider.get_global_rect()
        var t: float = clampf((pos.x - rect.position.x) / rect.size.x, 0.0, 1.0)
        _my_slider.value = _my_slider.min_value + t * (_my_slider.max_value - _my_slider.min_value)
        return

func _hits(ctrl: Control, pos: Vector2) -> bool:
    if ctrl == null or not ctrl.visible:
        return false
    if ctrl is Button and (ctrl as Button).disabled:
        return false
    return ctrl.get_global_rect().has_point(pos)
```
This is non-negotiable. Don't spend a single commit debugging "why doesn't `Button.pressed` fire" — that ship sailed in May 2026. Implement manual dispatch from the first commit on any new UI.

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

**Some Zylann `VoxelLodTerrain` properties are INT — verify with read-back:**
```gdscript
# WRONG — collision_update_delay is INT in this Zylann build. set()
# silently truncates 0.1 to 0; every chunk stream-in/out then fires
# an immediate main-thread collision rebuild → 100+ ms frame spikes.
terrain.set("collision_update_delay", 0.1)

# RIGHT — pass integer milliseconds. Always read back to confirm
# Zylann actually stored the value (some properties also clamp
# silently — `mesh_block_size = 32` was clamped to 16 in some scenes
# until verified via the dump).
terrain.set("collision_update_delay", 100)
print("actual=%s" % terrain.get("collision_update_delay"))
```
This is a generic gotcha: when configuring `VoxelLodTerrain` properties
programmatically, always read the value back. The bootstrap scripts
(`World3DBootstrap.gd`, `CopperIslesTestBootstrap.gd`, `WorldBakeController.gd`)
print readback values as a matter of policy.

**Per-autoload performance attribution via `HUDOverlay.profile_record`:**
```gdscript
# When you need to know which script is eating frame time, wrap the
# autoload's _process / _physics_process body in a renamed _inner
# function and time around it. HUDOverlay accumulates per-second and
# the [PERF] line dumps the top 3 contributors. Pattern handles early
# returns naturally (the inner can `return` anywhere; the outer wrapper
# always records the elapsed time).
func _process(delta: float) -> void:
    var _t0 := Time.get_ticks_usec()
    _process_inner(delta)
    HUDOverlay.profile_record("AutoloadName", Time.get_ticks_usec() - _t0)

func _process_inner(delta: float) -> void:
    # original body, unchanged
    ...
```
Wrappers add ~1 µs per call. Flip `HUDOverlay.PERF_DIAG` to `false` to
silence the per-second print without removing the wrappers. Note:
`Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` are per-frame
snapshots, NOT script attribution — they correlate with `worst_ms` but
don't tell you which autoload is slow.

>**Zylann blocky-library properties: use the methods, not `.set()`, AND re-apply at runtime:**
```gdscript
# WRONG — silently no-ops. The property name appears in
# get_property_list() but Zylann routes the actual storage through
# method pairs, and .set() writes to a virtual property bag the
# gdextension only reads for serialization. The mesh build sees default
# values (tile (0,0), null material) and you get all-white terrain
# with full-atlas UVs.
model.set("tile_top", Vector2i(2, 0))
model.set("material_override_0", atlas_mat)

# RIGHT — call the method directly.
model.call("set_tile", 3, Vector2i(2, 0))   # 3 = SIDE_POSITIVE_Y
model.call("set_material_override", 0, atlas_mat)

# AND: even when the methods are used, those values WRITE to .tres but
# DO NOT RESTORE on load. Always re-apply at runtime (see
# World3DBootstrap._inject_atlas_materials_into_library). The .tres is
# a build artifact; the bootstrap is the source of truth.
```
SIDE enum (Zylann Cube): NEG_X=0, POS_X=1, NEG_Y=2, POS_Y=3, NEG_Z=4, POS_Z=5.

**`VoxelLodTerrain.material` overrides every per-cube `material_override_0`:**
```gdscript
# WRONG — sets a single empty StandardMaterial3D on the terrain.
# Even if your library's cubes have correct atlas materials, this
# overrides them all globally and every face renders white.
[node name="VoxelLodTerrain" type="VoxelLodTerrain"]
material = SubResource("VoxelTerrainMat")   # ← don't do this

# RIGHT — leave terrain.material null when using textured cube
# models. Per-cube material_override_0 (set at runtime by
# World3DBootstrap) drives rendering.
[node name="VoxelLodTerrain" type="VoxelLodTerrain"]
# (no material line)
```

**Probe a gdextension class before guessing its API:**
```gdscript
# When working with Zylann (or any gdextension) classes, write a
# probe EditorScript that prints get_property_list() AND
# get_method_list() before you commit to property names. Property
# lists alone mislead — Zylann's VoxelBlockyModelCube exposes
# tile_top/tile_bottom/etc. as listed properties, but storage actually
# routes through set_tile()/get_tile(). See tools/probe_zylann_blocky.gd.
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
│   ├── generator: VoxelGeneratorScript (CubicHeightmapGeneratorAdapter.gd)
│   │   └── cpp_impl: CubicHeightmapGeneratorCpp  ← C++ GDExtension; runs on Zylann worker threads
│   ├── stream: VoxelStreamSQLite                  ← per-save-slot delta DB
│   └── mesher: VoxelMesherBlocky
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
`GameState`, `Colors`, `TransitionManager`, `SaveNotification`, `PauseMenu`,
`DebugOverlay`, `FlagScheduler`, `InventoryManager`, `VoxelMaterialRegistry`,
`JournalUI`, `HUDOverlay`, `NoEditZoneRegistry`, `VoxelEditManager`,
`VoxelGravityManager`, `WaterFlowManager`, `Dialogic`, `BarkManager`, `WorldClock`,
`WeatherManager`, `BloodVFX`

`Colors` (`assets/ui/Colors.gd`) is the single source of truth for the Voxelmark
UI palette (oak / parchment / iron / gold / HP / STAM, plus 5 rarity tiers).
The companion `UIStyles` helper class (`assets/ui/UIStyles.gd`, `RefCounted`,
not autoloaded — accessed as `UIStyles.foo()`) builds StyleBox / FontVariation
resources from those palette constants and is the canonical way to apply
chrome to Buttons, Panels, Labels, Sliders, and LineEdits in this project.
Every programmatic UI scene (`HUDOverlay`, `PauseMenu`, `MainMenu`,
`Settings`, `SaveSlotPicker`, `TransitionManager`'s loading screen) consumes
both. CSS source-of-truth: `assets/ui/css/menus_shared.css`.

Load-order rules to preserve:
- `Colors` MUST load before any UI autoload (`PauseMenu`, `HUDOverlay`, `JournalUI`) — those scripts reference `Colors.PANEL_OAK_1` / `Colors.HP` / etc. directly in `_ready()`.
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

### Dev-scene group convention

Developer test scenes (`scenes/_dev/BakeWorld.tscn`,
`scenes/CopperIslesTest.tscn`, future siblings) opt out of the gameplay
UI by joining the `dev_scene` group in their bootstrap script's
`_ready()`:

```gdscript
add_to_group("dev_scene")
```

The autoloads that render gameplay chrome — **HUDOverlay, PauseMenu,
JournalUI, SaveNotification** — check `GameState.is_dev_scene()` and
skip rendering / input / animation when the current scene is in that
group. Other autoloads (TransitionManager, Settings, DebugOverlay,
voxel/water/weather systems) keep working normally — they're either
infrastructure or actively useful during development. To add a new
dev scene, attach a script that calls `add_to_group("dev_scene")` in
its `_ready()` and the gameplay UI will stay dormant for the duration
of that scene.

---
