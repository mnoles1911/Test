# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All commands run from inside `IsometricRPGMono/`.

```bash
# Build
dotnet build -c Release

# Run (Linux/dev)
dotnet run

# Publish self-contained Windows exe
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o ./publish/win-x64
```

There are no automated tests. Verification is manual: build must produce 0 errors (3 pre-existing nullable warnings in `GameScene.cs` and `AudioManager.cs` are expected and acceptable).

## Architecture

**Namespace:** `IsometricRPG` throughout. **Framework:** MonoGame.Framework.DesktopGL 3.8.2 / .NET 8. No content pipeline (`EnableMGCBItems=false`) — all textures are procedural and audio stubs are generated at runtime as silent RIFF/PCM WAV files written to `Content/Audio/` on first run.

### Game Loop

`Game1` → `GameScene` is the only delegation chain. `Game1.Update/Draw` call straight through to `GameScene`, which owns every subsystem. `Game1.WantsExit` is the only signal that flows back up.

`GameScene` drives a `GameState` enum (`MainMenu / Playing / Paused / Inventory / GameOver`) and routes `Update` logic accordingly. All subsystem references live on `GameScene` as fields.

### Coordinate System

**World space:** tile units (float). Player starts at `(8, 8)`. Chunks are 16×16 tiles.

**Screen space:** pixels, Y-down (MonoGame default). `IsometricMath.WorldToScreen` converts with **no Y negation** (this differs from the original Swift/SpriteKit source which negated Y).

`CameraPos` is a screen-space `Vector2` that all Draw calls subtract from entity screen positions. Camera lerps toward `WorldToScreen(Player.WorldPosition)` each frame.

### Rendering Pipeline (draw order each frame)

1. `PrimitiveRenderer` draws all world tiles as `VertexPositionColor` triangles via `BasicEffect` (no `SpriteBatch` involved — call `SpriteBatch.End()` before any `DrawUserPrimitives`).
2. First `SpriteBatch.Begin` pass: items, enemies, player, bullets.
3. Second `SpriteBatch.Begin` pass: HUD (`GameHUD` + `Minimap`).
4. Third `SpriteBatch.Begin` pass: `ScreenManager` overlays (menus, pause, inventory).

`SpriteManager` is a `Texture2D` cache — call `GetCircle(diameter, color)` or `GetRect(w, h, color)` instead of creating textures directly. Never allocate `Texture2D` in Draw hot paths.

### World Generation

`WorldManager` streams 16×16 `Chunk`s keyed by `ChunkCoord`. Load radius = 3, unload radius = 5 (Chebyshev distance). `UpdateAroundPlayer` returns `(loaded, unloaded)` coord lists each frame; callers are responsible for spawning items/enemies into newly loaded chunks and cleaning up unloaded ones.

Each `Chunk` is seeded deterministically via `ChunkSeed(coord)` so regenerating a chunk always produces the same result. Dungeon chunks (Mountain/HighMountain biomes or 10% random chance) use `DungeonGenerator`; all others use Perlin-based `FillTerrain`. `StructureGenerator.GenerateForChunk` runs after terrain fill for non-dungeon chunks.

### UI System

`UIElement` → concrete components (`Button`, `Label`, `Panel`, `StatBar`). Full screens subclass `UIScreen` and are pushed/popped on `ScreenManager`'s stack — the top screen receives input and is drawn last. `SpriteFont?` is nullable everywhere; all `DrawString` calls must null-check (font fails to load silently since there is no content pipeline).

### Input

`InputManager` wraps `KeyboardState`/`MouseState` each frame and exposes:
- `MovementDirection` — normalized `Vector2` from WASD (world-space, not screen-space)
- `AimDirection` — mouse position minus player screen position (screen-space); converted to world-space in `GameScene` via `IsometricMath.ScreenToWorld` before firing bullets
- `FireHeld`, `FirePressed` — LMB or Space
- `PausePressed`, `InventoryPressed` — edge-detected (rising edge only)

### Save / Load

`SaveManager` reads/writes JSON to `%LOCALAPPDATA%/IsometricRPG/` (`save.json` + `settings.json`). To restore player progress from a save, call `Player.RestoreProgress(level, partialXp)` — do **not** call `AddXP` in a loop, as that triggers level-up side effects (HP refill, MaxHealth increment) that overwrite the saved HP.

### Key Constants (`Engine/Constants.cs`)

`ChunkSize=16`, `TileWidth=64`, `TileHeight=32`, `PlayerSpeed=150`, `BulletSpeed=400`, `FireRate=0.25s`, `EnemySpeed=60`, `MaxLevel=50`, `EnemyMinSpawnDistance=4f tiles`.

### Extension Points

- **New enemy type:** subclass `Enemy`, override `UpdateAI` (pass `deltaTime` — do not hardcode `1/60f`).
- **New item effect:** add case to `WorldItem.ApplyEffect` and `ItemType` enum + `ItemTypeExtensions`.
- **New UI screen:** subclass `UIScreen`, push onto `ScreenManager` from `GameScene`.
- **New biome:** extend `Biome` enum, `BiomeExtensions.From`, `TileType.TileForBiome`, and `StructureTemplates.All`.
- **New structure:** add a `StructureTemplate` to `StructureTemplates.All` with `AllowedBiomes`, `Footprint`, and `SpawnWeight`.
