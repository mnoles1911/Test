# 3D Voxel Migration Plan
## Pivoting Game One from 2D pixel art to 3D voxel

---

## What We're Building (The Target)

**Veloren meets Skyrim, built in Godot 4.6.2.**

The aesthetic goal: a world that feels ancient and handcrafted — stone cities with real mass, forests with depth, underground tunnels that feel claustrophobic. Characters and enemies are low-poly 3D or voxel-art models. Lighting is full 3D: dynamic shadows, ambient occlusion, volumetric fog.

**Visual references:**
- **Veloren** — open-world voxel RPG, closest reference for scale and feel
- **Cube World** — exploration RPG with voxel world, character style
- **The Witcher 3 / Dark Souls / Elden Ring** — third-person over-shoulder camera, 1-vs-many melee, lock-on system
- **Zelda: Link's Awakening (2019 remake)** — low-poly characters in a 3D world
- **The Skyrim reference** — scale, atmosphere, dramatic landscape lighting. The "Skyrim feel" is about how the world communicates weight and age, not camera perspective.

**What makes voxel work at this scale:**
- Blocks are **8 voxels per meter** — each cube is 12.5 cm, noticeably blocky but far finer than Minecraft's 1m cubes
- Terrain uses **blocky voxel meshing** (`VoxelMesherCubes`) — visible cube faces on terrain steps, consistent with MagicaVoxel building style
- Buildings are **hand-assembled voxel structures** — cubes are visible and intentional, like stonework. Terrain and buildings share the same block language.
- Characters are **low-poly 3D models** (Blender → GLTF) or **billboard sprites** (Sprite3D facing camera)
- Lighting is **real 3D** — DirectionalLight3D for sun/moon, PointLight3D for torches and fires, SDFGI for global illumination

---

## What This Changes (The Pivot)

### What Gets Replaced

| Old (2D) | New (3D) | Notes |
|---|---|---|
| `CharacterBody2D` | `CharacterBody3D` | Player.gd rewritten |
| `Camera2D` | `Camera3D` with fixed angle | New camera rig script |
| `TileMap` | VoxelTerrain (Zylann plugin) or GridMap | Terrain system |
| `PointLight2D` | `PointLight3D` | Minor adaptation |
| `CanvasModulate` | `WorldEnvironment` (fog, sky, SDFGI) | Much more powerful |
| `ColorRect` placeholders | `MeshInstance3D` box placeholders | Same idea, 3D |
| `CollisionShape2D` | `CollisionShape3D` | Physics unchanged conceptually |
| `Area2D` triggers | `Area3D` triggers | Minor port |
| `AnimatedSprite2D` | `AnimationPlayer` + GLTF skeleton | Character art change |
| `LightOccluder2D` | Not needed — 3D lighting handles this | Simpler |
| Godot viewport 320×180 | Godot viewport native (1920×1080 or similar) | No pixel resolution target |

### What Survives Unchanged

All the **game logic** autoloads work without modification. They are data and UI code, not rendering code:

| File | Status | Notes |
|---|---|---|
| `GameState.gd` | ✅ Unchanged | Pure data, no rendering |
| `TransitionManager.gd` | ✅ Unchanged | Scene loading, not scene content |
| `Zone.gd` | ⚠️ Interiors only | Outdoor world is open/streaming; Zone/Room survives for dungeon floors and building interiors |
| `Room.gd` | ⚠️ Interiors only | AABB bounds still valid for interior camera limits |
| `RoomTrigger.gd` | ⚠️ Port Area2D → Area3D | Survives for interior doors and scene transitions |
| `SpawnPoint.gd` | ⚠️ Minor adapt | Vector2 → Vector3 position |
| `JournalUI.gd` | ✅ Unchanged | Pure UI overlay, no world interaction |
| `PauseMenu.gd` | ✅ Unchanged | UI, no world interaction |
| `DebugOverlay.gd` | ✅ Unchanged | UI, no world interaction |
| `FlagScheduler.gd` | ✅ Unchanged | Pure timer/event logic |
| `InventoryManager.gd` | ✅ Unchanged | Pure data |
| `SaveNotification.gd` | ✅ Unchanged | UI overlay |
| `Settings.gd` | ✅ Unchanged | Audio + display settings |
| `MainMenu.gd` | ✅ Unchanged | Pure UI |
| `EnemyData.gd` | ✅ Unchanged | Data resource |
| `Combat.gd` | ⚠️ Full rewrite anyway | Already planned for real-time combat |
| `DialogueTrigger.gd` | ⚠️ Port Area2D → Area3D | Minor |
| `CampfireFlicker.gd` | ⚠️ PointLight2D → PointLight3D | Minor |

---

## Technology Stack (3D)

### Voxel Terrain — Zylann's Voxel Tools

**Plugin:** `godot_voxel` by Zylann  
**Source:** https://github.com/Zylann/godot_voxel  
**Godot 4 compatible:** Yes

This is the premier voxel terrain plugin for Godot 4. It powers Veloren-adjacent projects and supports:
- `VoxelTerrain` — infinite streaming terrain with LOD
- `VoxelMesherCubes` — blocky cube-face meshing; used for all terrain and structures in this project
- `VoxelMesherTransvoxel` — smooth voxel meshing (not used — eliminates the blocky aesthetic we want)
- `VoxelInstancer` — scatter props (trees, rocks) across terrain efficiently
- Custom voxel generators via GDScript or C++

**For this project:**
- Node: `VoxelLodTerrain` (LOD streaming — required for 12km × 10km open world)
- Terrain mesher: `VoxelMesherCubes` (smooth hills, cliff edges, river banks)
- Buildings: MagicaVoxel `.glb` exports placed as `MeshInstance3D` on top of terrain. `VoxelMesherCubes` for any terrain-carved structures (rare).
- Terrain is **editable / destructible by default**. The procedural `VoxelGeneratorGraph` is the *baseline*; player edits are stored as deltas in `VoxelStreamSQLite` per save slot. See **"Destructible Terrain"** below.
- Scope: full open world — 12km × 10km playable Mira, 125:1 linear compression

---

## Destructible Terrain

**Default rule:** every voxel in the world is destructible. Non-destructible regions and entities are the exception, declared explicitly via `NoEditZone` Area3D volumes or implemented as `MeshInstance3D` props (not voxel terrain).

This is the canonical spec. Other docs (`SAVE_SYSTEM.md`, `MULTIPLAYER.md`, `ART_PIPELINE.md`, etc.) defer to this section for terrain mutation behavior.

### Edit Model — LOD0-Clamped + LOD-Baked at Distance

The hard constraint: voxel edits and rendered geometry must agree wherever the player can interact with terrain (collision, pathfinding, placement). The cheap optimization: most edits are sparse and small, so we don't need to keep edited chunks at full resolution forever.

**Three radii control the model. All three are independent:**

| Radius | Default | Range | Controls |
|---|---|---|---|
| **Mandatory LOD0** | 32m | fixed | Edited chunks within this radius are always rendered + collided at LOD0. Floor for safety. |
| **Edit detail radius** | 64m (8 chunks) | 32m–256m | Player setting. How far out edited chunks render at LOD0 (full block-precision). |
| **View distance** | 600m | 200m–2km | Player setting. LOD streaming horizon for procedural (un-edited) terrain. |

**Render decision per chunk per frame:**

```
for each chunk in view-distance radius:
    if chunk is within edit-detail radius:
        load + render at LOD0 with deltas applied (full crispness)
    else if chunk is in EditedChunkRegistry:
        load + render from LOD-bake cache (regenerate from edited state if missing)
    else:
        load + render procedural baseline at appropriate LOD
```

The LOD bake is the key trick. When an edited chunk first leaves the edit-detail radius, generate its LOD1/LOD2 meshes from the *edited* voxel state and cache them under `user://saves/slot_{N}/mesh_cache/`. Subsequent renders at distance use the cached mesh, not the procedural baseline. A house the player built remains visible (chunky) from across the valley. The cache is regeneratable — exclude from save backups, regenerate on demand if missing.

### What Persists, What Doesn't

- **Voxel deltas persist forever.** No world healing. A pit Roland dug in Act I is still there in Act IV.
- **LOD bake cache is disposable.** Lives next to the save; regenerated on demand.
- **`EditedChunkRegistry` (autoload)** holds the in-memory `HashSet<Vector3i>` of chunks with deltas. Populated from `VoxelStreamSQLite` on save load.

### NoEditZones — The Opt-Out Model

Settlements, named landmarks, quest sites, dungeon set-pieces, and any narratively load-bearing geometry are protected. Two layers:

1. **Major structures = `MeshInstance3D` props.** Buildings (Iron Chalice chapel, Khorumzad façade, Caer Brannoch towers) are MagicaVoxel exports placed on the terrain surface, not carved into voxels. Voxel edits cannot affect them by definition.
2. **Surrounding terrain protected by `NoEditZone` Area3D volumes.** Each settlement, dungeon entrance, and lore site sits inside an authored Area3D volume that buffers ~50–100m around the structure. The `VoxelEditManager` autoload queries `NoEditZoneRegistry` before applying any `VoxelTool.do_*` write. Writes inside a NoEditZone are silently rejected, with a Roland bark *"This place doesn't yield to me."* on player attempts.

**Authoring rule: if it's narratively load-bearing, it's a MeshInstance3D prop inside a NoEditZone.** The voxel ground/cliffs/forest underneath is the destructible surface. Settlements sit on top.

### Player Edit Verbs

Voxel edits are intentionally slow and cumbersome — far below Minecraft's pace. The number and velocity of edits per session is expected to be a small fraction of a Minecraft session. This shapes the entire system: rare edits = small deltas = small saves = cheap MP sync.

| Tool | Voxel material | Notes |
|---|---|---|
| **Axe** | wood (trees, logs, planks) | Felling animation per tree; trunk falls as a directional event, then the tree resolves into voxel logs the player can pick up |
| **Pickaxe** | rock, stone, ore | Per-swing single-voxel removal at low tiers; multi-voxel at higher tiers. Yields material into inventory. |
| **Shovel** | dirt, sand, clay, ash | Same swing pattern as pickaxe but for soft materials |
| **Explosives** | stone walls, fortifications, dense rock | Crafted consumable; AOE 2–4m radius; significant voxel removal in one event. Loud, draws enemy attention. |
| **Spells** | varies by school | Earth spells dig; Fire spells fell trees + ignite; (Game Two onward, when magic comes online for Roland's allies) |

Tool material gating: each voxel material has a hardness tier. A wooden pickaxe cannot mine adamant ore. Tool tier comes from smithing tier — Common / Quality / Masterwork — same as weapons. Speed scales with the relevant skill (see `design/SKILLS_AND_PROGRESSION.md` → Crafting → Mining/Felling/Excavation/Demolition sub-skills).

All edit verbs share a per-swing voxel-budget cap to prevent stutter. Explosives queue their voxel writes across multiple frames via the `VoxelEditManager` async edit queue.

### Player-Built Structures — Voxel and Schematic

Players build with two mechanisms, used together:

1. **Schematic placement (props).** Crafted building pieces (wall section, door, roof panel, window frame, fence) are `.glb` props placed on the world surface. Stored as `PlacedSchematic` records (position, rotation, schematic_id) in the save. Cheap, fast, looks consistent. Used for the bulk of any structure.
2. **Voxel placement (per-block).** Player can place individual voxel blocks for detailing — chimney variation, custom stair runs, decorative carving. Stored as deltas in `VoxelStreamSQLite` like any other edit.

Both coexist on the same plot. Schematic walls form the shell; voxel placement tweaks the details. Save format keeps them in separate tables (see `design/SAVE_SYSTEM.md`).

A small player-built house = a few dozen schematic placements + perhaps a hundred voxel deltas. Total save cost: trivial.

**Forward-looking — Player Blueprint Capture** (post-Act-I idea, parked in `DESIGNER_TODO.md` Section 9): a third mechanism where the player captures any voxel arrangement they like — their own builds, ruined structures encountered in the world, settlements (read-only inside NoEditZones) — into a saved `PlayerBlueprint` resource. Captured blueprints can be re-placed elsewhere as ghost outlines that consume materials from inventory. This becomes the player-authored counterpart to crafted schematics: schematics are designer-supplied prefabs; blueprints are player-supplied prefabs. Implementation extends `SchematicLibrary`. Lore framing: Roland keeps a folio of sketches.

### Combat / AI Implications

- Navmesh chunked per voxel chunk. Async rebuild on edit. AI tolerates stale paths for ~1–2s post-edit; enemies stuck > 8s teleport-correct to nearest valid nav node with a small VFX so it doesn't read as a bug.
- Knockback into terrain that destroys voxels on impact is supported. Power-attack-into-rock dust events are good.
- Pit-trapping enemies is a viable player tactic. Embraced as a power moment.

### Multiplayer Implications

Sparse edits + MP-sync of `EditedChunkRegistry` deltas on join (typically a few hundred KB even on a long-running host save). Each client sets its own edit-detail radius locally — host doesn't care. Full spec: `design/MULTIPLAYER.md`.

### Save System Implications

Save slot becomes a directory: JSON state + `voxel_deltas.sqlite` + `placed_schematics.json` + `mesh_cache/`. Mesh cache excluded from backup rotation. Generator-version stamp inside the JSON; mismatch on load is a hard error (no silent migration). Full spec: `design/SAVE_SYSTEM.md`.

### Asset Creation — MagicaVoxel

**Tool:** MagicaVoxel (free)  
**Use for:** Buildings, props, dungeon tiles, set-pieces  
**Export:** `.obj` or `.glb` → import to Godot

MagicaVoxel is the standard tool for creating voxel art assets. It produces:
- Colored voxel models with palette control
- Export with vertex colors (no separate texture needed)
- Works directly with Godot's GLTF importer

### Characters — Blender (Low-poly 3D)

**Tool:** Blender (free)  
**Target:** 200–500 triangle characters, rigged and animated  
**Export:** `.glb` → Godot `AnimationPlayer` + skeleton  

The "low-poly" character style — flat-shaded faces, minimal geometry, bold silhouette — is achievable in Blender without professional 3D art skills. Think Zelda: Link's Awakening (2019) character proportions.

Billboard sprites are not used. The third-person over-shoulder camera is too close for flat sprites to read as 3D. Low-poly Blender models are used from Act I onward — see `design/ART_PIPELINE.md` for the full character pipeline and Act I animation minimum set.

### Camera Rig

Third-person over-shoulder camera, player-rotatable:
- `Camera3D` on a `SpringArm3D` arm behind and slightly above Roland (~15° elevation)
- Player controls horizontal and vertical aim with right stick / mouse
- `SpringArm3D` handles collision — arm shortens automatically in caves and corridors
- Lock-on system for 1-vs-many combat — keeps targeted enemy in right frame half
- Full spec: `design/CAMERA_AND_PERSPECTIVE.md`

```gdscript
# CameraRig.gd — key exports
@export var arm_length: float = 5.0          # SpringArm3D shortens via collision
@export var elevation_degrees: float = 15.0  # Above horizontal
@export var horizontal_sensitivity: float = 0.3
@export var vertical_min_degrees: float = -20.0
@export var vertical_max_degrees: float = 45.0
@export var dialogue_arm_length: float = 3.5  # Tween to for Dialogic conversations
```

### Lighting

| Source | Godot node | Notes |
|---|---|---|
| Sun / moon | `DirectionalLight3D` | Shadows enabled, soft edges |
| Torches, campfire | `PointLight3D` | Same CampfireFlicker.gd logic, adapted |
| Ambient fill | `WorldEnvironment` → sky | Keep darkness present, not black |
| Fog | `WorldEnvironment` → fog | Volumetric for underground |
| Ambient occlusion | `WorldEnvironment` → SSAO | Cheap, improves all surfaces |
| Global illumination | `WorldEnvironment` → SDFGI | Optional — looks excellent in caves |

**Performance note:** SDFGI is expensive. Enable in WorldEnvironment but allow disabling via Settings. SSAO is cheap and always on.

---

## Migration Milestones

### Milestone 4-3D: Project Setup and Camera

**Goal:** A 3D scene with a moving character and follow camera.

- [ ] Install `godot_voxel` plugin
- [ ] Add `WorldEnvironment` node with sky, SSAO, fog
- [ ] Add `DirectionalLight3D` (sun)
- [ ] Create `Player3D.tscn` — `CharacterBody3D` + `CollisionShape3D` (capsule) + `MeshInstance3D` (box placeholder)
- [ ] Write `Player3D.gd` — 8-directional movement using `Input.get_vector()` mapped to 3D XZ plane
- [ ] Create `CameraRig.gd` — fixed-elevation follow camera on a `SpringArm3D`
- [ ] Create placeholder `World3D.tscn` — flat `GridMap` floor, a few box walls, no voxel terrain yet
- [ ] Verify: WASD moves the box, camera follows at fixed angle, no clipping through floor

### Milestone 5-3D: Open World Terrain Foundation (Editable)

**Goal:** Walking on streaming VoxelLodTerrain that generates recognizable Mira geography, with destructible terrain wired in from the start.

- [ ] Set up `VoxelLodTerrain` node in `World3D.tscn` (replace placeholder floor)
- [ ] Wire `VoxelGeneratorGraph` (Gaea EXR heightmap + 3D cave noise) — Spine ridge east, Greatwood flat north, Aldwater valley center, forced-flat zones at settlement coordinates
- [ ] Configure LOD levels (6–8 levels for 12km extent; mandatory LOD0 radius 32m; default edit-detail radius 64m)
- [ ] Attach `VoxelStreamSQLite` to the terrain — voxel-delta storage path = `user://saves/slot_{N}/voxel_deltas.sqlite`
- [ ] Implement `VoxelEditManager` autoload — async edit queue, EditedChunkRegistry, NoEditZoneRegistry, LOD-bake-on-eviction, per-frame voxel budget cap
- [ ] Implement `NoEditZoneRegistry` — registers Area3D volumes by group `no_edit_zone`; `VoxelEditManager` queries before any write
- [ ] First test edit verb: pickaxe debug action — single-voxel removal at crosshair, yields material into inventory
- [ ] Add `EntityStreamer` node — stub that prints chunk load/unload to Output
- [ ] Verify: player walks on generated terrain, camera follows in third-person, distant terrain LODs are visible, pickaxe edits persist across save/load, edits inside a placed NoEditZone are rejected

### Milestone 6-3D: First MagicaVoxel Assets

**Goal:** Replace placeholder boxes with real voxel art.

- [ ] Build campfire prop in MagicaVoxel (export .glb) — first prop pipeline test
- [ ] Build cave wall tile in MagicaVoxel (export .glb)
- [ ] Import to Godot as MeshInstance3D nodes placed on terrain
- [ ] Verify: scene reads as a real location, not a grey box test

### Milestone 7-3D: First Character Model

**Goal:** Roland has a real low-poly appearance in the world.

- [ ] Build Roland base mesh in Blender (200–400 tris, flat-shaded)
- [ ] Rig skeleton (~25 bones)
- [ ] Animate: idle, walk, run (minimum to unblock scene testing)
- [ ] Export `.glb`, import to Godot, set up `AnimationTree` + `BlendSpace1D`
- [ ] Verify: Roland walks through the generated terrain with real character animation

Combat animations (attack, dodge) follow in Milestone 8-3D alongside first enemy model.

---

## GDScript Changes Required

### Player.gd → Player3D.gd

```gdscript
extends CharacterBody3D

const SPEED: float = 5.0
const DECEL: float = 20.0

func _physics_process(delta: float) -> void:
    # Read input in 2D, map to 3D XZ plane (Y is up in 3D)
    var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y).normalized()

    if direction != Vector3.ZERO:
        velocity.x = direction.x * SPEED
        velocity.z = direction.z * SPEED
    else:
        velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
        velocity.z = move_toward(velocity.z, 0.0, DECEL * delta)

    # Gravity
    if not is_on_floor():
        velocity.y -= 9.8 * delta

    move_and_slide()
```

### Zone.gd — SpawnPoint placement (minor adapt)

```gdscript
# Change: player_node.global_position = sp.global_position
# 3D SpawnPoint.gd uses Vector3, CharacterBody3D accepts it directly.
# No other changes needed.
```

### RoomTrigger.gd — Port Area2D → Area3D

```gdscript
# Change extends Area2D → extends Area3D
# body_entered signal works identically in 3D
# Vector2 velocity check → Vector3 velocity check
```

### CampfireFlicker.gd — Minor adapt

```gdscript
# Change: extends PointLight2D → extends OmniLight3D
# self.energy works the same in 3D
# All flicker math unchanged
```

---

## What NOT to Do

- **Do not use the Godot 4 CSG nodes for terrain.** CSGBox, CSGMesh etc. are for prototyping, not production — they can't be used with physics properly.
- **Do not use GridMap for the open world.** GridMap works for structured interior rooms; use Zylann's VoxelTerrain for anything organic (hillsides, cave walls).
- **Do not use a first-person camera.** The lore and narrative require Roland to be visible at all times. The camera is third-person over-shoulder — see `design/CAMERA_AND_PERSPECTIVE.md`.
- **Do not rebuild the logic autoloads.** GameState, FlagScheduler, InventoryManager, JournalUI, PauseMenu — all of this works in 3D without changes. Do not touch it.
- **Do not buy or subscribe to voxel middleware.** Zylann's plugin is free, open source, and proven. Anything paid adds lock-in with no benefit at this scale.

---

## File Structure (3D)

```
/scenes/
  World3D.tscn          ← persistent open world scene (VoxelLodTerrain + EntityStreamer)
  Player3D.tscn         ← replaces Player.tscn
  interiors/            ← discrete scenes for buildings and dungeon floors
    iron_chalice.tscn
    archive.tscn
    khorumzad_level1.tscn
    [...]
  ui/                   ← all unchanged (Journal, PauseMenu, etc.)
/scripts/
  Player3D.gd           ← replaces Player.gd
  CameraRig.gd          ← third-person over-shoulder, lock-on support
  CampfireFlicker3D.gd  ← minor adaptation
  WorldGenerator        ← VoxelGeneratorGraph (Godot editor node, NOT a .gd file) — procedural baseline only; player edits live as deltas in VoxelStreamSQLite
  VoxelEditManager.gd   ← NEW autoload: async edit queue, EditedChunkRegistry, LOD-bake cache management, NoEditZone enforcement, per-frame voxel budget
  NoEditZoneRegistry.gd ← NEW autoload: registry of Area3D no-edit volumes; queried before every VoxelTool write
  SchematicLibrary.gd   ← NEW autoload: registry of placeable building schematics (.glb props with placement metadata)
  EntityRegistry.gd     ← NEW: autoload, spatial dictionary of all world entities
  EntityStreamer.gd      ← NEW: node in World3D, loads/unloads entities by player proximity
  Zone.gd               ← interiors only (Vector3 adapt)
  Room.gd               ← interiors only (AABB bounds)
  RoomTrigger3D.gd      ← port of RoomTrigger.gd (interior doors)
  SpawnPoint3D.gd       ← port of SpawnPoint.gd
  [all logic autoloads] ← unchanged
/assets/
  voxel/                ← MagicaVoxel exports (.glb): props, buildings, dungeon tiles
    props/
    buildings/
    dungeon/
    crown_pieces/
  models/               ← Blender character exports (.glb) — all characters from Act I
    roland.glb
    henrietta.glb
    [...]
  portraits/            ← Unchanged (dialogue UI art, 256×320 px)
  audio/                ← Unchanged
```
