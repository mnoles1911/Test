# scripts/CLAUDE.md

GDScript code. **Read `../design/PATTERNS_AND_GOTCHAS.md` before writing new code** — every non-negotiable rule lives there.

## Layout

| Subdir | What's in it |
|---|---|
| `enemies/` | `Goblin.gd` and future enemy types extending `Enemy3D` |
| `entities/` | `EntityRecord`, `EntityRegistry` (per-chunk + JSON save/load) |
| `graphics/` | `GraphicsManager` autoload, `ShaderProfile` tier resource, `AtmosphereProfile` |
| `skills/` | `SkillManager`, `PerkRegistry`, 300 `PerkData` resources, `CombatXPRouter` |
| `throwables/` | `ThrowableSpear`, future bombs |
| `net/` | Multiplayer transport + backends (`NetTransport`, ENet impl) |
| `dice/`, `minigames/` | Dice + mini-game logic |
| `ui/` | UI controller scripts |
| `_dev/` | Dev-only EditorScript probes + parity harnesses |
| `_prototypes/` | Throwaway experiments |

## Core files (top-level scripts)

- **`World3DBootstrap.gd`** — ALL world-load wiring goes here. Adds materials, configures terrain, spawns dev helpers, applies graphics tier.
- **`Player3D.gd`** + **`CameraRig.gd`** — character + over-shoulder/first-person camera. See scene hierarchy in `../design/PATTERNS_AND_GOTCHAS.md`.
- **`VoxelEditManager.gd`** — single gateway for ALL voxel writes (NoEditZone gate, async budget, MP RPC routing). Never use raw `VoxelTool`.
- **`VoxelGravityManager.gd`**, **`EmissiveBakedLightManager.gd`**, **`WaterFlowManager.gd`** — autoloads delegating per-voxel hot loops to C++ (`extensions/voxel_gen/`) with GD fallback.
- **`WeatherManager.gd`**, **`DayNightCycle.gd`**, **`WorldClock.gd`** — atmosphere + time.
- **`UnderwaterFilter.gd`** — instant-snap submerge, vol fog, god rays.
- **`DistantTerrainManager.gd`** — streaming smooth heightmesh past Zylann's near-LOD ring.
- **`Enemy3D.gd`** — combat base class (HP, state machine, contact damage, corpse loot, Phase 5 gib explosion).
- **`HUDOverlay.gd`**, **`JournalUI.gd`**, **`PauseMenu.gd`**, **`DebugOverlay.gd`** — UI autoloads.
- **`AudioManager.gd`** — single SFX entry point (`play(id, world_pos)`, `play_loop(id) -> handle`, `stop_loop(handle)`).
- **`WaterMaterial.gd`** — water type checks; **no `class_name`** (path-preload only — headless-safe).
- **`WaterByteCodec.gd`** — sim source of truth for water (level/source/dir bits in DATA5).

## Autoload load order

See `../design/PATTERNS_AND_GOTCHAS.md` for the full list + 8 ordering rules. **Violating order silently breaks signal subscriptions and `_ready` references.**

## When adding a script

- Subclass an existing base if one fits (`Enemy3D`, `Resource`, etc.).
- New autoloads: register in `project.godot` + place in the load order respecting existing dependencies.
- Always guard cross-autoload refs with `get_node_or_null("/root/Foo")` — script may be running in a dev scene where Foo isn't loaded.
- Profile-attribute via `HUDOverlay.profile_record + Profiler.record` (recipe in PATTERNS_AND_GOTCHAS).

## When perf becomes the question

Read `../design/PROFILER_AND_DIAGNOSTICS.md` first; the answer is usually in a recent capture, not a guess. If a per-voxel inner loop is the spike, see `../extensions/voxel_gen/CLAUDE.md` for the C++ port pattern.
