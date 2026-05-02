# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

iOS isometric action-RPG written in Swift 5 / SpriteKit. Single Xcode app target (`IsometricRPG`) at `IsometricRPG/IsometricRPG.xcodeproj`. Deployment target iOS 16, landscape-only, runs on iPhone and iPad. There is no Swift Package, CocoaPods, Carthage, or test target — just the Xcode project. The repo `README.md` contains no useful content.

## Build / run

This project must be built on macOS with Xcode; the Linux container cannot produce an iOS binary.

```bash
# open in Xcode
open IsometricRPG/IsometricRPG.xcodeproj

# headless build for the simulator
xcodebuild -project IsometricRPG/IsometricRPG.xcodeproj \
  -scheme IsometricRPG \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

There is no lint config and no test suite, so don't invent `swiftlint` / `xcodebuild test` commands — they will fail.

## Adding files

The Xcode project uses the legacy `project.pbxproj` (not the modern file-system synced groups). Any new `.swift` file must be added to `project.pbxproj` to be compiled, otherwise the build silently ignores it. Prefer placing files into the existing folder that matches their concern (`World/`, `Entities/`, `UI/Screens/`, etc.) and follow the same pbxproj entries used by neighboring files.

## Architecture

Boot path: `AppDelegate` → `GameViewController` (sets up `SKView`) → `MainMenuScreen` → `GameScene`. `GameScene` (`Engine/GameScene.swift`) is the per-frame coordinator that owns the `WorldManager`, `Player`, `[Enemy]`, `CombatSystem`, `ItemSpawner`, `EnhancedHUD`, and `ScreenManager`, and dispatches the per-frame work in `update(_:)`.

### Coordinate spaces (critical)

There are two coordinate spaces and you must be deliberate about which one you use:

- **World space** — continuous Cartesian grid coordinates (a tile is 1×1). Every entity's authoritative position (`Player.worldPosition`, `Enemy.worldPosition`, `WorldItem.worldPosition`, `Bullet.worldPosition`) lives here. Walkability, collision, and AI all operate in world space.
- **Screen space** — SpriteKit node coordinates, computed by `IsometricMath.worldToScreen` / `gridToScreen`. Each entity calls `syncNodePosition()` to project its world position onto its `SKNode`. Tile diamonds are `Constants.tileWidth` × `Constants.tileHeight` (64×32) and elevation shifts the screen Y by `elevationHeightMultiplier` × elevation.

If you add a new entity, mirror the `Entity` base class pattern: store `worldPosition`, mutate it in `update`, then call `syncNodePosition()`. Never write screen-space positions directly into gameplay logic.

### Infinite world streaming

`WorldManager` keeps a `[ChunkCoord: Chunk]` dictionary and on every `updateAroundPlayer(worldPosition:)` loads chunks within `Constants.loadRadius` and unloads beyond `Constants.unloadRadius`. The check short-circuits if the player hasn't crossed a chunk boundary.

`Chunk` (16×16 tiles) is **deterministic**: terrain, elevation, biome, rooms, and structures are derived from `ChunkCoord.chunkSeed` (a hash of `Constants.worldSeed` plus chunk position) plus shared `PerlinNoise` instances. Same seed + same coord → byte-identical chunk. When you change generation logic, expect every chunk in an existing save to look different.

`GameScene.updateWorld()` is the only place that reacts to chunk load/unload deltas: it calls `ItemSpawner.spawnItems` for newly loaded chunks and `removeItems` / `removeEnemies` for unloaded ones. Enemies are spawned separately by `spawnEnemiesInChunks` on a timer (`Constants.enemySpawnInterval`), only in chunks 1–2 away from the player.

### Spawn-trigger / loot system

`Items/SpawnTrigger.swift` defines a `GameContext` snapshot (player level, health, kill count, biome, etc.) and a static registry of `SpawnTrigger`s. When `ItemSpawner` populates a chunk, it builds a base weight table from `ItemType.baseWeight`, then multiplies in `weightModifiers` from every trigger whose `condition(GameContext) -> Bool` fires. To add a new dynamic loot rule, append to `SpawnTriggerRegistry.allTriggers` — no other call sites need to change.

### UI state

`UI/Core/ScreenManager.swift` owns a stack of `ModalOverlay`s plus a `GameState` enum (`.playing`, `.paused`, `.inventory`, …). Pause/inventory/settings/character/codex are all modals layered on top of `GameScene` via `screenManager.showModal(...)`; only the main menu is a separate `SKScene` swap. `GameScene.update` early-returns unless `gameState == .playing`, so opening any modal pauses the simulation.

The main menu is its own `SKScene` (`MainMenuScreen`); to return to it from gameplay use `view.presentScene(MainMenuScreen(...))`, not the modal stack.

### Persistence and assets

- `Data/SaveManager.swift` is a singleton that JSON-encodes `PlayerData` / inventory / equipment / settings into `UserDefaults`. Anything you want persisted across launches must round-trip through `Codable` here.
- `Utils/SpriteManager.swift` is a singleton texture cache that loads from the asset catalog (`Assets.xcassets/*.atlas`) and falls back to procedurally generated shapes if a name is missing — so missing art doesn't crash the game, it just renders a placeholder.
- `Utils/AudioManager.swift` is a singleton SFX player; gameplay code calls `AudioManager.shared.playSound(.shoot)` etc. directly.

### Tuning constants

`Utils/Constants.swift` holds **all** gameplay/render magic numbers (chunk size, load radius, player/enemy stats, tile dimensions, z-positions, physics categories). Prefer adding new tunables here over hard-coding them in feature files; the game is balanced by editing this file.
