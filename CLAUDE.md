# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Game One — Project Bible

## What I'm building
A 2.5D narrative RPG in the style of Sea of Stars.
Single player. Active turn-based combat with timing inputs.
Pixel art sprites with 3D-ish environments and dynamic 2D lighting.
Built in Godot 4.3 using GDScript.
This is game one of a planned trilogy adapted from a 200-page source manuscript.

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
- Player: CharacterBody2D, 8-directional movement, interacts with world
- World scenes: Tilemap-based environments with 2D dynamic lighting
- Dialogue: Dialogic 2 plugin handles all narrative content
- Combat: Separate scene, active turn-based with timing inputs
- Game state: Autoload singleton (GameState.gd) tracks all persistent data
- Scene transitions: Fade to black between zones

## Folder structure
- /scenes — all .tscn files
- /scripts — all .gd files  
- /assets/sprites — character and prop sprites
- /assets/portraits — character portrait images for dialogue boxes
- /assets/tilesets — environment tiles
- /assets/audio — music and sfx
- /dialogue — all Dialogic timeline (.dtl) files
- /dialogue/characters — Dialogic character definition (.dch) files
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

MILESTONE 4: IN PROGRESS — Systems infrastructure (Phases 4–7)
See PR on branch `claude/expand-game-lore-i0k2g`. Systems built (not yet merged to main):
- TransitionManager (fade-black/white/cut, scene history, go_back())
- GameState expanded (multi-slot save, flag history, play time tracking)
- Zone framework (Zone.gd, Room.gd, RoomTrigger.gd, SpawnPoint.gd)
- SaveNotification autoload toast, PauseMenu (ESC), MainMenu, Settings screen
- SaveSlotPicker (3 slots), DebugOverlay (F1), FlagScheduler (timed/deferred)
- InventoryManager (items, equipment, crafting recipes)
- JournalUI expanded (5-tab KCD2 style: Quests, Map, Items, Crafting, Codex)
- EnemyData Resource class, Combat.gd updated with Analyze action

MILESTONE 5: (not started) — Art pass
- Aseprite + AI-assisted workflow
- 32×32 tiles, 32×48 character sprites
- AnimationTree for character animation
- Normal maps on tiles and character sprites
- Begin with cave tiles → Roland walk cycle → Aldenholt tileset

## Current milestone
Milestone 3 complete. Milestone 4 systems built, PR open. Next: merge M4, then start art pass.

## Art specification (confirmed)
- **Engine approach**: 2D Godot — NOT 3D. The 2.5D look is an art style, not a camera setting.
- **Tile size**: 32×32 pixels
- **Character sprites**: 32×48 pixels
- **Backgrounds**: hand-painted single assets (not tiled)
- **Tool**: Aseprite + AI-assisted generation (hand-paint over AI output before shipping)
- **Animation**: AnimationTree + BlendSpace2D (not AnimatedSprite2D)
- **Lighting depth**: PointLight2D + normal maps on tiles and sprites
- **Pipeline reference**: `design/ART_PIPELINE.md`

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
- lore/CHARACTERS_COMPANIONS.md, CHARACTERS_NPCS.md, BACKSTORY_*.md
- lore/GAME1_PART1.md / GAME1_PART2.md — full Game One plot
- lore/REFERENCE.md — quick-reference tables

Always check INDEX.md before adding new lore files to avoid duplication.

## Design reference
Game implementation docs live in /design. When lore and design conflict, lore wins.
- design/SYSTEMS_DESIGN.md — combat, dialogue, exploration, faction, save systems
- design/ART_DIRECTION.md — palette, pixel resolution, location visual identity, shaders, animation priority
- design/CAMERA_AND_PERSPECTIVE.md — why the 3/4 view is an art style, not a camera transform
- design/ART_PIPELINE.md — Aseprite workflow, tile specs, AnimationTree, normal maps
- design/DIALOGIC_SETUP.md — step-by-step Dialogic 2 installation and character setup
- design/LESSONS_LEARNED.md — running log of bugs and fixes

## Current project state
Godot 4.3 project initialized. Milestones 1–3 complete.

Key files:
- `project.godot` — 320x180 viewport, integer scaling, pixel snap, GameState + Dialogic autoloads
- `scripts/GameState.gd` — autoload singleton stub
- `scripts/Player.gd` — 8-directional movement
- `scripts/CampfireFlicker.gd` — sine wave light energy animation
- `scripts/DialogueTrigger.gd` — press-E area trigger, calls Dialogic.start()
- `scripts/CombatTrigger.gd` — walk-in trigger that loads Combat.tscn
- `scripts/Combat.gd` — full combat state machine (player turn, attack timing, block timing, win/lose)
- `scenes/Player.tscn` — CharacterBody2D with ColorRect placeholder, CollisionShape2D, Camera2D
- `scenes/World.tscn` — cave scene with campfire, blue dialogue trigger (right), red combat trigger (left)
- `scenes/Combat.tscn` — combat scene: HP panels, timing bar, action menu, enemy flash
- `dialogue/henrietta_archive.dtl` — Henrietta at the Archive door, 7-line opening scene
- `assets/portraits/henrietta_placeholder.svg` — archive scholar portrait placeholder

To run: Open project in Godot 4.3, run World.tscn.
- Walk LEFT into red zone → combat starts
- Walk RIGHT into blue zone + press E → Henrietta dialogue

## Canonical naming (frequent contradictions)
- Eldermark royal house: Castrove (NOT Vane)
- Aldric the blacksmith: Aldric Vane (Mordvar bloodline, not the investigator)
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
2. Run the relevant scene (World.tscn for movement/lighting, Combat.tscn for combat)
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
