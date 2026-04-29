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
[Write 2-3 sentences describing your world's tone — dark, hopeful, epic, intimate?]
[Example: "Epic fantasy with grounded emotional stakes. Think LOTR's scale with 
a single protagonist's intimate perspective. The world feels ancient and real."]

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
