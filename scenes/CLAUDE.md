# scenes/CLAUDE.md

Godot scene files (`.tscn`). The script behind each scene lives in `/scripts/<matching_name>.gd`.

## Play scenes

- **`World3D.tscn`** — the main Mira world. C++ generator via `CubicHeightmapGeneratorAdapter`. **Run this for full-stack testing.**
- **`Player3D.tscn`** — Roland's CharacterBody3D + camera rig + handlers. Hierarchy is load-bearing (see `../design/PATTERNS_AND_GOTCHAS.md` → "Critical scene hierarchies").
- **`CopperIslesTest.tscn`** — Copper Isles biome test. F7 cycles terrain scale.

## Dev / test scenes (`_dev/`)

- **`CombatTest.tscn`** — combat dev arena. 3 Goblins pre-placed, spear pre-equipped, F1 debug menu. Use this for Enemy3D / ThrowableSpear / GibChunk testing.
- **`BakeWorld.tscn`** / **`BakeWorld3D.tscn`** — UI-driven world bake (Copper Isles + Mira). Must run in-game.
- Dev scenes opt out of gameplay UI via `add_to_group("dev_scene")` in their bootstrap — HUD/Pause/Journal stay dormant.

## Subdirectories

| Subdir | Contents |
|---|---|
| `enemies/` | `Goblin.tscn` (placeholder green box + ChestSocket + EyeGlow) |
| `player/` | Player3D + camera rig sub-scenes |
| `throwables/` | `throwable_spear.tscn`, `powder_charge.tscn` |
| `ui/` | `Journal.tscn`, HUD components (in `ui/components/`) |
| `vfx/` | Blood pool, drip, burst — `PlaneMesh`-based (NOT Decal — renderer compat) |
| `voxel/` | `FallingVoxelCluster.tscn` (used by `VoxelGravityManager`) |
| `dice/` | Dice opponents + table |
| `_prototypes/` | Throwaway test scenes |

## Authoring

- **Hardcoded `$NodeName` references** — see `../design/PATTERNS_AND_GOTCHAS.md` "Critical scene hierarchies". Renaming a child node = breaking the script.
- **NoEditZone** Area3Ds: group `no_edit_zone`, ~50–100m buffer CollisionShape3D, under any settlement / dungeon / landmark root.
- **NPC scenes** need a `BarkArea` + `InteractArea` Area3D (names MUST match exactly) + an assigned `NPCData` resource.

## Adding a new scene

1. Create the .tscn under the appropriate subdir.
2. Author the matching script in `/scripts/<same_path>.gd`.
3. If load-bearing (other scripts will `$NodeChild` into it), document the hierarchy in `../design/PATTERNS_AND_GOTCHAS.md`.
4. If it's a dev scene, add `add_to_group("dev_scene")` to its bootstrap `_ready()`.
