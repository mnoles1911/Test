# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Game One — Project Bible

## What I'm building
A 3D voxel narrative RPG — Veloren meets Skyrim in atmosphere and open-world scale.
Single player. Real-time action combat (Witcher 3 / Dark Souls style), 1-vs-many, third-person over-shoulder camera.
Voxel world built in Godot 4.3 with Zylann's Voxel Tools plugin. GDScript only.
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
- /assets/voxel — MagicaVoxel exports (.glb): props, buildings, dungeon tiles, crown pieces
- /assets/models — Blender character exports (.glb): Roland, NPCs, enemies
- /assets/portraits — character portrait images for dialogue (256×320 px)
- /assets/audio — music and sfx
- /dialogue — all Dialogic timeline (.dtl) files; also `dialogue/CHARACTER_VOICES.md` (voice IDs + ElevenLabs config per character), `dialogue/PRONUNCIATION.md` (phonetic respellings for lore proper nouns — check before every TTS run), `dialogue/STYLE.md` (line writing rules, mood tags, length targets)
- /lore — all narrative canon (start at lore/INDEX.md)
- /design — game implementation reference (systems, art direction)
- /tools — pipeline scripts run from the repo root (TTS rendering, draft stripping); see `tools/README.md`

## Milestone history

MILESTONE 1: COMPLETE — First walkable scene with lighting
- [x] Player moves in a cave-like environment (CharacterBody2D, 8-directional, move_and_slide)
- [x] One campfire light source, warm orange glow (PointLight2D #E8873A, energy 1.3, flicker script)
- [x] Camera follows player (Camera2D child of Player node)
- [x] One area trigger that fires on press-E (Area2D + DialogueTrigger.gd)
- [x] Placeholder shapes only (ColorRect for all visuals)
- [x] GameState.gd autoload singleton stub
- [x] Cave wall collision (4x StaticBody2D)

MILESTONE 2: COMPLETE — First dialogue with Dialogic 2
- [x] Dialogic 2 plugin installed and configured
- [x] Henrietta opening scene (7-line dialogue at the Archive door)
- [x] Press-E trigger wired to Dialogic.start()
- [x] Portrait placeholder for Henrietta

MILESTONE 3: COMPLETE — Combat prototype
- [x] Separate combat scene (scenes/Combat.tscn)
- [x] Red trigger zone in World.tscn — walk left into it to enter combat
- [x] Player (Roland) and enemy (Ashfallen), each with HP displayed
- [x] Action menu: ATTACK [SPACE] and ITEM (placeholder/locked)
- [x] Attack timing bar: indicator sweeps left→right, Space in green zone = bonus damage
- [x] Enemy telegraph + block timing: Space in window = reduced damage
- [x] Win/lose conditions with message and auto-return to World.tscn

MILESTONE 4: COMPLETE — Systems infrastructure (Phases 4–7) [merged via PR #42]
- TransitionManager (fade-black/white/cut, scene history, go_back())
- GameState expanded (multi-slot save, flag history, play time tracking)
- Zone framework (Zone.gd, Room.gd, RoomTrigger.gd, SpawnPoint.gd)
- SaveNotification autoload toast, PauseMenu (ESC), MainMenu, Settings screen
- SaveSlotPicker (3 slots), DebugOverlay (F1), FlagScheduler (timed/deferred)
- InventoryManager (items, equipment, crafting recipes)
- JournalUI expanded (5-tab KCD2 style: Quests, Map, Items, Crafting, Codex)
- EnemyData Resource class, Combat.gd updated with Analyze action

3D PIVOT: design docs merged via PR #43
- `design/3D_VOXEL_MIGRATION.md`, ART_DIRECTION, ART_PIPELINE, CAMERA_AND_PERSPECTIVE all rewritten for 3D voxel.

MILESTONE 4-3D: COMPLETE & VERIFIED IN GODOT (2026-05-01) — First 3D scene with follow camera, movement, HUD, overlays
- [x] `scripts/Player3D.gd` — CharacterBody3D, 8-directional XZ-plane movement, sprint (Left Shift), crouch (C),
  mass-based physics scaling, health + endurance with drain/regen, `status_text` property for HUD
- [x] `scripts/CameraRig.gd` — SpringArm3D third-person over-shoulder; standard + freelook (F2) modes;
  scroll wheel zoom 2m–10m; arrow key fallbacks; dialogue tween; lock-on API; both yaw + pitch re-center on F2 release
- [x] `scripts/HUDOverlay.gd` — Layer-5 CanvasLayer autoload; HP + endurance bars bottom-center; CROUCHING / EXHAUSTED status label
- [x] `scripts/JournalUI.gd` — Rewritten: 6-tab overlay (Quests/Map/Items/Crafting/Codex/Skills); Tab + click navigation; tree-paused while open; mouse VISIBLE while open
- [x] `scripts/CampfireFlicker3D.gd` — OmniLight3D port of campfire flicker
- [x] `scripts/SpawnPoint3D.gd`, `RoomTrigger3D.gd` — 3D ports of Zone framework triggers
- [x] `scenes/Player3D.tscn` — capsule + box mesh placeholder + SpringArm3D rig
- [x] `scenes/World3D.tscn` — placeholder cave: floor, WorldEnvironment, DirectionalLight3D, campfire OmniLight3D
- [x] `scenes/ui/Journal.tscn` — Stripped to bare CanvasLayer; all layout built programmatically in `JournalUI.gd`
- [x] `scripts/PauseMenu.gd`, `DebugOverlay.gd`, `SaveNotification.gd` — resized and re-fonted for 1080p
- [ ] Install Zylann's Voxel Tools plugin (manual step in Godot Asset Library)
- [x] Verified in Godot 4.3 (2026-05-01): all 13 checklist items pass

MILESTONE 5-3D: (not started) — VoxelLodTerrain + first Roland Blender model
- VoxelLodTerrain node with WorldGenerator (VoxelGeneratorGraph — Gaea EXR heightmap + 3D cave noise)
- First MagicaVoxel exports: campfire prop, cave wall tile
- Roland low-poly Blender model: base mesh + rig + idle/walk/run animations (no billboard sprites)

## Current milestone
Milestones 1–4 complete (2D). 3D pivot confirmed. **Milestone 4-3D complete and verified in Godot (2026-05-01):** camera (standard + freelook), sprint/crouch, health/endurance, HUD overlay, 6-tab journal/inventory overlay, all UI resized for 1080p. All 13 in-Godot verification checks pass.
The system design corpus is complete (combat, AI, companions, factions, quests, economy, save, death, weather, HUD, input, accessibility, audio, navigation, lockpicking — all authored in `/design`). Pipeline tooling has landed under `/tools`.
Next: **Phase 5-3D** — `WorldGenerator.gd` (Zylann Voxel Tools install required first) + first Roland Blender model + register `BarkManager` and `WorldClock` autoloads. See `DESIGNER_TODO.md` Section 7.

## Art specification (confirmed — 3D VOXEL)
- **Engine approach**: Godot 4.3, 3D. Voxel world via Zylann's Voxel Tools plugin.
- **Voxel scale**: 8 voxels per meter (confirmed — each block is 12.5 cm, noticeably blocky but finer than Minecraft's 1m cubes)
- **Terrain**: `VoxelLodTerrain` with `VoxelMesherCubes` (blocky stepped terrain, matches MagicaVoxel building style). Static, generated from a **3D density field** in `WorldGenerator.gd` — not a heightmap, so overhangs, caves, and cliff lips are supported. Not editable by player.
- **World scale**: Playable Mira 12km × 10km, compression 125:1 linear (1 game meter ≈ 125 fictional meters). Playable Thal ~7km × 5.5km.
- **Props/buildings**: MagicaVoxel → export .glb → Godot MeshInstance3D
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
- design/ART_PIPELINE.md — MagicaVoxel, Zylann plugin, Blender, billboard sprites
- design/3D_VOXEL_MIGRATION.md — full pivot plan: what changes, what survives, 3D milestones

**Planning and ops:**
- design/MILESTONE_ROADMAP.md — Act I scene breakdown and ordered deliverables for Phases 4+
- design/ENDGAME_CHOICES.md — Game Three endgame and trilogy-spanning choice consequences
- design/DIALOGIC_SETUP.md — step-by-step Dialogic 2 installation and character setup
- design/TTS_PIPELINE.md — AI-assisted draft → ElevenLabs render → Dialogic handoff (bulk vs craft pipelines, filename + manifest contract)
- design/LESSONS_LEARNED.md — running log of bugs and fixes

## Current project state
Godot 4.3 project. Milestones 1–4 complete (2D). 3D pivot confirmed. Open world confirmed (VoxelLodTerrain streaming, static generated terrain, 12km × 10km playable Mira). Third-person over-shoulder camera confirmed. Low-poly Blender character models from Act I confirmed. Milestone 4-3D in progress (first 3D scripts + placeholder scene).

System design corpus is now complete: combat, enemy AI, companions, factions, quests, economy, save, death/respawn, weather, HUD, input, accessibility, audio, and world navigation all have authored design docs in `/design`. Implementation work for the autoloads and UI nodes those docs specify is tracked in `DESIGNER_TODO.md`.

Pipeline tooling has landed in `/tools`: `strip_draft.py` (prose-draft → TTS-script extractor) and `render_bulk.py` (ElevenLabs batch renderer). Both are documented in `tools/README.md` and require an `ELEVENLABS_API_KEY` env var.

2D legacy (still present, will be retired as 3D scenes replace them):
- `scripts/Player.gd`, `CampfireFlicker.gd`, `DialogueTrigger.gd`, `CombatTrigger.gd`, `Combat.gd`
- `scenes/Player.tscn`, `World.tscn`, `Combat.tscn`

3D Milestone 4-3D files (complete):
- `scripts/Player3D.gd` — CharacterBody3D, 8-directional XZ movement, sprint/crouch, health/endurance, mass-based physics scaling
- `scripts/CameraRig.gd` — SpringArm3D third-person over-shoulder; standard + freelook (F2) modes; scroll zoom; re-centering fixed
- `scripts/HUDOverlay.gd` — Layer-5 CanvasLayer autoload; HP + endurance bars; status label; registered in `project.godot`
- `scripts/JournalUI.gd` — 6-tab overlay (Quests/Map/Items/Crafting/Codex/Skills); programmatic build; tree-paused while open
- `scripts/CampfireFlicker3D.gd` — OmniLight3D flicker
- `scripts/SpawnPoint3D.gd`, `RoomTrigger3D.gd` — Vector3 / Area3D ports of the Zone framework
- `scripts/DialogueTrigger3D.gd` — Area3D trigger zone; press E (interact action) to start a Dialogic timeline
- `scenes/Player3D.tscn` — capsule + box mesh placeholder, with SpringArm3D camera rig
- `scenes/World3D.tscn` — placeholder cave: WorldEnvironment (SSAO + fog), DirectionalLight3D, ground StaticBody3D, OmniLight3D campfire, Player3D instance
- `scenes/ui/Journal.tscn` — bare CanvasLayer; all layout built in `JournalUI.gd`

NPC system (implemented):
- `scripts/NPC.gd` — CharacterBody3D base script for all Tier 1–3 NPCs; bark firing, E-press dialogue, disposition, schedule dispatch
- `scripts/NPCData.gd` — Resource class: npc_id, Tier enum, disposition, bark_triggers, schedule entries; one .tres per character in `/assets/npcs/`
- `scripts/NPCScheduleEntry.gd` — Resource class: hour_start, hour_end, location_id, animation; used by NPCData.schedule array

Logic autoloads (unchanged from 2D, all survive the 3D pivot):
- `GameState.gd`, `TransitionManager.gd`, `SaveNotification.gd`, `PauseMenu.gd`, `DebugOverlay.gd`,
  `FlagScheduler.gd`, `InventoryManager.gd`, `JournalUI.gd`, `Settings.gd`, `MainMenu.gd`, `EnemyData.gd`

New autoloads added in Milestone 4-3D (registered in `project.godot`):
- `HUDOverlay.gd` — HP + endurance bars, status label; layer 5; reads from player group each frame

New autoloads (implemented — must still be registered in Project Settings → Autoload):
- `BarkManager.gd` — loads bark pools from `dialogue/scripts/barks/{category}/{npc_id}.txt`; picks random non-repeating line; plays spatial audio from `assets/audio/barks/`; falls back to Output print if BarkOverlay UI is absent
- `WorldClock.gd` — ticks in-game time (default 240 real s = 1 game hour); emits `hour_changed`, `time_of_day_changed`, `day_changed`; calls `update_schedule(hour)` on `scheduled_npcs` group; pauses during Dialogic timelines; `set_time()` and `advance_hours()` for debug/rest

New autoloads specified in design docs (not yet implemented — build in dependency order):
- `WorldGenerator.gd` — implemented as a **`VoxelGeneratorGraph`** node (not a GDScript subclass); authored world geography sourced from a **Gaea-exported 32-bit EXR heightmap** + biome splatmap; 3D cave noise layer added in the graph for overhangs and cave systems; encodes Spine ridge, Greatwood, Aldwater valley, Ashfields, settlement flat zones; foundation of the open world. See `design/ART_PIPELINE.md` → Tool 2.
- `EntityRegistry.gd` — spatial dictionary of every world entity (NPCs, props, triggers, enemies) keyed by chunk; stores lightweight `EntityRecord` data objects (type, world position, scene path, saved state); does not instantiate nodes itself
- `EntityStreamer.gd` — node in `World3D.tscn`; each frame checks player position against `EntityRegistry`, instantiates nodes when in range, saves state and `queue_free()`s them when out of range
- `FactionManager.gd` — wraps GameState faction disposition flags (design/FACTION_SYSTEM.md)
- `QuestManager.gd` — quest flag management: advance_quest(), complete_quest() (design/QUEST_SYSTEM.md)
- `WeatherManager.gd` — weather state, WorldEnvironment tweening, weather overrides (design/WEATHER_AND_ENVIRONMENT.md)
- `CompanionManager.gd` — companion active state, HP, serialize/deserialize for save (design/COMPANION_SYSTEM.md)

To verify Milestone 4-3D in Godot 4.3:
1. Open the project, run `scenes/World3D.tscn`
2. WASD moves the placeholder character; W always moves toward Roland's facing direction (camera-relative)
3. Arrow keys rotate camera only — character does NOT move
4. Mouse drag: horizontal rotates Roland + camera (standard mode); vertical tilts; F2 hold = freelook; release re-centers both axes
5. Mouse scroll wheel zooms in/out (arm length 2m–10m)
6. HP and endurance bars visible at bottom-center of screen
7. Hold Left Shift → sprint, endurance drains; at 0 sprint locks + EXHAUSTED shows; recovers above 20
8. Press C → crouch toggle; CROUCHING shows; speed drops; sprint blocked
9. Press Escape → pause menu, cursor visible; Resume → cursor hidden again
10. Press J → 6-tab journal overlay opens; Tab key cycles tabs; clicking tab headers works; I goes to Items tab
11. Campfire glows orange and flickers
12. No clipping through the floor or walls
13. No errors in Output panel

Manual setup still required: see `DESIGNER_TODO.md` → Section 1 for the full checklist
(Zylann Voxel Tools install, audio bus layout per `design/AUDIO_DESIGN.md`, Autoload
registration for `BarkManager` / `WorldClock` / `EntityRegistry`).

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
1. Open the project in Godot 4.3
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
velocity = velocity.move_toward(Vector2.ZERO, DECEL * delta)
# NOT: velocity.move_toward(Vector2.ZERO, SPEED) — that stops in one frame
```

**GradientTexture2D radial center (easy to get wrong):**
```gdscript
# fill_from defaults to (0,0) = top-left corner, NOT center
# Always set explicitly for a centered circular glow:
gradient_texture.fill_from = Vector2(0.5, 0.5)
gradient_texture.fill_to = Vector2(1.0, 0.5)
```

**Light containment — CollisionShape2D does NOT block light:**
```
PointLight2D requires LightOccluder2D + OccluderPolygon2D on walls.
CollisionShape2D only blocks physics, not 2D lighting.
```

**Control nodes vs Node2D for world-space objects:**
```
ColorRect / Label / Button = screen-space (UI layer, fixed to camera)
Polygon2D / Sprite2D        = world-space (moves with the scene)
Use Polygon2D when a visual element should stay attached to a world position.
```

**One-shot signal connection (e.g. dialogue end):**
```gdscript
Dialogic.timeline_ended.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
```

**OmniLight3D property name differs from PointLight2D:**
```gdscript
omni_light.light_energy = value  # 3D — NOT .energy (that's the 2D PointLight2D property)
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

---

## Autoload registration status

Registered in `project.godot` (active now):
`GameState`, `TransitionManager`, `SaveNotification`, `PauseMenu`,
`DebugOverlay`, `FlagScheduler`, `InventoryManager`, `JournalUI`, `Dialogic`

**NOT yet registered — must be added in Project Settings → Autoload:**
- `scripts/BarkManager.gd` → node name `BarkManager`
- `scripts/WorldClock.gd` → node name `WorldClock`

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
