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
- **`FarGrassManager.gd`** — far-grass impostor layer (2026-06-12). GPU-instanced, non-interactive grass filling the LOD1/LOD2 bands (~13–51 m) so the REAL LOD0 voxel grass no longer ends in a visible bald ring at ~12.8 m. Impostor blades replay the C++ generator's exact flora `hash3` so they sit where real grass will appear when the player walks closer (seamless handoff). Chunk-ring follows the player (DistantTerrain pattern); blades use `flora_sway.gdshader`. Gated by `GraphicsManager.far_grass_enabled` (**default ON** — exception to the new-visual-layers-default-OFF rule because it fixes a seam in shipped default-ON grass; designer-approved). NO `class_name` (path-preload, headless-safe). Far-grass continuity is in the `flora` selector; sway shader compile is in the `shader` selector.
- **`FloraMeshBuilder.gd`** — single source of truth for the flora cross-quad blade mesh, shared by the real LOD0 flora (`World3DBootstrap`) and the far-grass impostor (`FarGrassManager`) so near and far blades look identical. `build_cross_quad(..., world_space)`: `false` = Zylann cube-local voxel units; `true` = world metres for MultiMesh. NO `class_name`.
- **`Enemy3D.gd`** — combat base class (HP, state machine, contact damage, corpse loot, Phase 5 gib explosion).
- **`HUDOverlay.gd`**, **`JournalUI.gd`**, **`PauseMenu.gd`**, **`DebugOverlay.gd`** — UI autoloads.
- **`AudioManager.gd`** — single SFX entry point (`play(id, world_pos)`, `play_loop(id) -> handle`, `stop_loop(handle)`).
- **`VoxelScale.gd`** — THE single authority for voxel grid scale (`VOXELS_PER_METER`, `VOXEL_SIZE_M`, helpers). **No `class_name`** (path-preload only — headless-safe). Never hardcode `6.0`/`0.166667`; read from here.
- **`WaterMaterial.gd`** — water type checks; **no `class_name`** (path-preload only — headless-safe).
- **`FloraMaterial.gd`** — micro-voxel decoration id authority; **no `class_name`** (path-preload — headless-safe), same pattern as `WaterMaterial.gd`. `is_flora()` = R4 vegetation (grass_blade=24 / flower_red=25 / flower_blue=26); `is_surface_detail()` = D1 pebble=27 / twig=28; **`is_passthrough()`** = either (contiguous 24..28) — every physics/sim site that skips water skips decoration via `is_passthrough()` (NOT `is_flora()`, which is vegetation-only). Gated by the `flora` selector.
- **`WaterFoamManager.gd`** — pooled flowing-water foam particles (D4 micro-detail pass, 2026-06-12). Repositions ONE pooled GPU-particle node across up to ~8 MOVING water cells near the player per tick (never one node per cell). Gated by `GraphicsManager.water_foam_enabled` (**default OFF** per new-visual-layer rule). Never built under `--headless`. NO `class_name`.
- **`WaterByteCodec.gd`** — sim source of truth for water (level/source/dir bits in DATA5).
- **`FiniteWaterCore.gd`** — finite volume-conserving water sim (pure, SceneTree-free, ledger-authority; **no `class_name`** — path-preload). Gated by the headless `finite` + `finite_world` selectors. Design: `../design/WATER_FINITE_SIM_PLAN.md`.
- **`RiverFlowVolume.gd`** — designer-authored steady river current (stamps DATA5 DIR bits via `VoxelEditManager.queue_set_water_dir_box`; bootstrap calls `stamp()` on the `river_flow_volume` group at load).
- **`WaterBiomeZone.gd`** — per-biome underwater fog/tint override box (group `water_biome_zone`; resolved by `UnderwaterFilter.set_active` at submerge).

## Autoload load order

See `../design/PATTERNS_AND_GOTCHAS.md` for the full list + 8 ordering rules. **Violating order silently breaks signal subscriptions and `_ready` references.**

## When adding a script

- Subclass an existing base if one fits (`Enemy3D`, `Resource`, etc.).
- New autoloads: register in `project.godot` + place in the load order respecting existing dependencies.
- Always guard cross-autoload refs with `get_node_or_null("/root/Foo")` — script may be running in a dev scene where Foo isn't loaded.
- Profile-attribute via `HUDOverlay.profile_record + Profiler.record` (recipe in PATTERNS_AND_GOTCHAS).

## When perf becomes the question

Read `../design/PROFILER_AND_DIAGNOSTICS.md` first; the answer is usually in a recent capture, not a guess. If a per-voxel inner loop is the spike, see `../extensions/voxel_gen/CLAUDE.md` for the C++ port pattern.
