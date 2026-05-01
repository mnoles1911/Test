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
- /dialogue — all Dialogic timeline (.dtl) files
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
- **Voxel scale**: 8 voxels per meter (fine-grain — NOT Minecraft 1-meter cubes)
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
| lore/CITY_DESCRIPTIONS.md | City details expanded or corrected |
| lore/MAP_GENERATION_GUIDE.md + sibling map files | New settlements, terrain, or geographic features added |
| design/SYSTEMS_DESIGN.md | Companion roster changes, faction triggers updated, new game systems added |
| design/ART_DIRECTION.md | New locations added to the game, palette or shader decisions finalized |
| CLAUDE.md (this file) | Milestone completed; new canonical naming contradictions found; new systems built |

---

## Lore reference
All world-building canon lives in /lore. Start at /lore/INDEX.md for a directory map. Key entry points:
- lore/WORLD.md — three ages, magic, religion, peoples overview
- lore/WORLD_GEOGRAPHY.md — terrain, scale, rivers, coastlines
- lore/CITY_DESCRIPTIONS.md — physical descriptions of major settlements
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
- design/SYSTEMS_DESIGN.md — combat, dialogue, exploration, faction, save systems
- design/ART_DIRECTION.md — palette, pixel resolution, location visual identity, shaders, animation priority
- design/CAMERA_AND_PERSPECTIVE.md — why the 3/4 view is an art style, not a camera transform
- design/ART_PIPELINE.md — MagicaVoxel, Zylann plugin, Blender, billboard sprites
- design/3D_VOXEL_MIGRATION.md — full pivot plan: what changes, what survives, 3D milestones
- design/COMBAT_DESIGN_3D.md — real-time 3D combat spec: click-duration power system, dodge, parry, lock-on
- design/MILESTONE_ROADMAP.md — Act I scene breakdown and ordered deliverables for Phases 4+
- design/DIALOGIC_SETUP.md — step-by-step Dialogic 2 installation and character setup
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

Logic autoloads (unchanged from 2D, all survive the 3D pivot):
- `GameState.gd`, `TransitionManager.gd`, `SaveNotification.gd`, `PauseMenu.gd`, `DebugOverlay.gd`,
  `FlagScheduler.gd`, `InventoryManager.gd`, `JournalUI.gd`, `Settings.gd`, `MainMenu.gd`, `EnemyData.gd`

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
