# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Game One — Project Bible

## What I'm building
A 3D voxel narrative RPG — Veloren meets Skyrim in atmosphere, Hades in camera angle.
Single player. Real-time action combat (Hades/Hyper Light Drifter style), 1-vs-many.
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
- Camera: SpringArm3D follow camera, ~50° elevation (Hades-style), fixed angle
- Dialogue: Dialogic 2 plugin handles all narrative content (unchanged)
- Combat: Real-time action in-world (Hades style), 1-vs-many, no separate scene
- Game state: Autoload singleton (GameState.gd) tracks all persistent data (unchanged)
- Scene transitions: TransitionManager autoload, fade-to-black/white/cut (unchanged)

## Folder structure
- /scenes — all .tscn files
- /scripts — all .gd files
- /assets/voxel — MagicaVoxel exports (.glb): props, buildings, dungeon tiles, crown pieces
- /assets/models — Blender character exports (.glb): Roland, NPCs, enemies
- /assets/sprites — billboard sprite sheets (Aseprite, 32×48 px, if using Option A characters)
- /assets/portraits — character portrait images for dialogue (256×320 px)
- /assets/audio — music and sfx
- /dialogue — all Dialogic timeline (.dtl) files; also `dialogue/CHARACTER_VOICES.md` (voice IDs + ElevenLabs config per character), `dialogue/PRONUNCIATION.md` (phonetic respellings for lore proper nouns — check before every TTS run), `dialogue/STYLE.md` (line writing rules, mood tags, length targets)
- /lore — all narrative canon (start at lore/INDEX.md)
- /design — game implementation reference (systems, art direction)

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

MILESTONE 4-3D: IN PROGRESS — First 3D scene with follow camera
- [x] `scripts/Player3D.gd` — CharacterBody3D, 8-directional XZ-plane movement
- [x] `scripts/CameraRig.gd` — SpringArm3D follow camera at 50° elevation
- [x] `scripts/CampfireFlicker3D.gd` — OmniLight3D port of campfire flicker
- [x] `scripts/SpawnPoint3D.gd`, `RoomTrigger3D.gd` — 3D ports of Zone framework triggers
- [x] `scenes/Player3D.tscn` — capsule + box mesh placeholder + SpringArm3D rig
- [x] `scenes/World3D.tscn` — placeholder cave: floor, WorldEnvironment, DirectionalLight3D, campfire OmniLight3D
- [ ] Install Zylann's Voxel Tools plugin (manual step in Godot Asset Library)
- [ ] Verify in Godot 4.3: WASD moves the box on a flat floor, camera follows at fixed angle, campfire flickers

MILESTONE 5-3D: (not started) — First voxel terrain + MagicaVoxel assets
- VoxelTerrain node with cave generator script
- First MagicaVoxel exports: campfire prop, cave wall tile
- First billboard sprite: Roland walk cycle (Aseprite → Sprite3D)

## Current milestone
Milestones 1–4 complete; design docs for 3D pivot merged. Milestone 4-3D scripts and scenes drafted.
Next: open Godot, install Zylann Voxel Tools, verify Player3D moves on World3D, then begin Milestone 5-3D art assets.

## Art specification (confirmed — 3D VOXEL)
- **Engine approach**: Godot 4.3, 3D. Voxel world via Zylann's Voxel Tools plugin.
- **Voxel scale**: 6–8 voxels per meter (confirmed from concept art validation — NOT Minecraft 1-meter cubes)
- **Terrain**: VoxelMesherTransvoxel (smooth organic terrain) + VoxelMesherCubes (buildings)
- **Props/buildings**: MagicaVoxel → export .glb → Godot MeshInstance3D
- **Characters**: billboard sprites (Aseprite 32×48 px, Sprite3D) for Act I; transition to low-poly Blender models for Act II+
- **Camera**: SpringArm3D at ~50° elevation, fixed angle, follows Roland (Hades-style)
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
| dialogue/CHARACTER_VOICES.md | New voiced character is added, or a render contract changes (voice ID, seed, stability) |
| dialogue/PRONUNCIATION.md | Any new lore proper noun is introduced (place names, gods, titles) |
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

**Player systems:**
- design/HUD_AND_UI.md — minimal HUD, HP/endurance bars, quick slots, interaction prompt, bark overlay, menus
- design/INPUT_AND_CONTROLS.md — full KB/mouse and controller scheme, all Input Map actions, tap-vs-hold combat
- design/ACCESSIBILITY_AND_SETTINGS.md — display/audio/controls/accessibility settings, subtitle defaults, colorblind support
- design/WORLD_NAVIGATION.md — no-waypoint navigation, Roland's hand-drawn journal map, zone structure, landmarks

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
- design/AUDIO_DESIGN.md — music philosophy (location-driven, not action-driven), diegetic audio, SFX priorities

**Planning and ops:**
- design/MILESTONE_ROADMAP.md — Act I scene breakdown and ordered deliverables for Phases 4+
- design/ENDGAME_CHOICES.md — Game Three endgame and trilogy-spanning choice consequences
- design/DIALOGIC_SETUP.md — step-by-step Dialogic 2 installation and character setup
- design/TTS_PIPELINE.md — AI-assisted draft → ElevenLabs render → Dialogic handoff (bulk vs craft pipelines, filename + manifest contract)
- design/LESSONS_LEARNED.md — running log of bugs and fixes

## Current project state
Godot 4.3 project. Milestones 1–4 complete (2D). 3D pivot design docs merged. Milestone 4-3D in progress (first 3D scripts + placeholder scene).

2D legacy (still present, will be retired as 3D scenes replace them):
- `scripts/Player.gd`, `CampfireFlicker.gd`, `DialogueTrigger.gd`, `CombatTrigger.gd`, `Combat.gd`
- `scenes/Player.tscn`, `World.tscn`, `Combat.tscn`

3D Milestone 4-3D files (new):
- `scripts/Player3D.gd` — CharacterBody3D, 8-directional XZ movement, gravity
- `scripts/CameraRig.gd` — SpringArm3D follow camera at 50° elevation
- `scripts/CampfireFlicker3D.gd` — OmniLight3D flicker
- `scripts/SpawnPoint3D.gd`, `RoomTrigger3D.gd` — Vector3 / Area3D ports of the Zone framework
- `scripts/DialogueTrigger3D.gd` — Area3D trigger zone; press E (interact action) to start a Dialogic timeline
- `scenes/Player3D.tscn` — capsule + box mesh placeholder, with SpringArm3D camera rig
- `scenes/World3D.tscn` — placeholder cave: WorldEnvironment (SSAO + fog), DirectionalLight3D, ground StaticBody3D, OmniLight3D campfire, Player3D instance

NPC system (implemented):
- `scripts/NPC.gd` — CharacterBody3D base script for all Tier 1–3 NPCs; bark firing, E-press dialogue, disposition, schedule dispatch
- `scripts/NPCData.gd` — Resource class: npc_id, Tier enum, disposition, bark_triggers, schedule entries; one .tres per character in `/assets/npcs/`
- `scripts/NPCScheduleEntry.gd` — Resource class: hour_start, hour_end, location_id, animation; used by NPCData.schedule array

Logic autoloads (unchanged from 2D, all survive the 3D pivot):
- `GameState.gd`, `TransitionManager.gd`, `SaveNotification.gd`, `PauseMenu.gd`, `DebugOverlay.gd`,
  `FlagScheduler.gd`, `InventoryManager.gd`, `JournalUI.gd`, `Settings.gd`, `MainMenu.gd`, `EnemyData.gd`

New autoloads (implemented — must still be registered in Project Settings → Autoload):
- `BarkManager.gd` — loads bark pools from `dialogue/scripts/barks/{category}/{npc_id}.txt`; picks random non-repeating line; plays spatial audio from `assets/audio/barks/`; falls back to Output print if BarkOverlay UI is absent
- `WorldClock.gd` — ticks in-game time (default 240 real s = 1 game hour); emits `hour_changed`, `time_of_day_changed`, `day_changed`; calls `update_schedule(hour)` on `scheduled_npcs` group; pauses during Dialogic timelines; `set_time()` and `advance_hours()` for debug/rest

New autoloads specified in design docs (not yet implemented — build in dependency order):
- `FactionManager.gd` — wraps GameState faction disposition flags (design/FACTION_SYSTEM.md)
- `QuestManager.gd` — quest flag management: advance_quest(), complete_quest() (design/QUEST_SYSTEM.md)
- `WeatherManager.gd` — weather state, WorldEnvironment tweening, weather overrides (design/WEATHER_AND_ENVIRONMENT.md)
- `CompanionManager.gd` — companion active state, HP, serialize/deserialize for save (design/COMPANION_SYSTEM.md)

To verify Milestone 4-3D in Godot 4.3:
1. Open the project, run `scenes/World3D.tscn`
2. WASD/arrow keys move the green box around the floor
3. Camera follows at a fixed 50° elevation, never tilts or rotates
4. Campfire glows orange and flickers
5. No clipping through the floor or walls

Manual setup still required:
- Install **Zylann's Voxel Tools** plugin from the Godot Asset Library (for Milestone 5-3D)
- Add input action **`interact`** (bound to E key) in Project Settings → Input Map — required by `DialogueTrigger3D.gd`
- Configure input actions `camera_left` / `camera_right` if `allow_horizontal_rotation` is enabled later

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
