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
- /assets/tilesets — environment tiles
- /assets/audio — music and sfx
- /dialogue — all Dialogic timeline files

## Current milestone
MILESTONE 1: First walkable scene with lighting
- Player moves in a cave-like environment
- One campfire light source, warm orange glow
- Camera follows player at 3/4 angle
- One area trigger that will eventually fire dialogue
- No art yet — placeholder shapes only
- DONE WHEN: It vibes like the reference image in lighting and camera angle

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
| CLAUDE.md (this file) | Godot project initialized; milestone completed; new canonical naming contradictions found |

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

## Current project state
The repository is currently in lore-development phase. No Godot project, scenes, or scripts exist yet. Milestone 1 (first walkable scene) has not begun. Build/test commands will be added once the Godot project is initialized.

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
