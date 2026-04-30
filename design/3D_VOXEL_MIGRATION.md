# 3D Voxel Migration Plan
## Pivoting Game One from 2D pixel art to 3D voxel

---

## What We're Building (The Target)

**Veloren meets Skyrim, built in Godot 4.3.**

The aesthetic goal: a world that feels ancient and handcrafted — stone cities with real mass, forests with depth, underground tunnels that feel claustrophobic. Characters and enemies are low-poly 3D or voxel-art models. Lighting is full 3D: dynamic shadows, ambient occlusion, volumetric fog.

**Visual references:**
- **Veloren** — open-world voxel RPG, closest reference for scale and feel
- **Cube World** — exploration RPG with voxel world, character style
- **Hades / Diablo 3** — camera angle (not voxel, but the fixed-elevation follow camera is exactly right)
- **Zelda: Link's Awakening (2019 remake)** — low-poly characters in a 3D world, diorama feel
- **The Skyrim reference** — scale, atmosphere, dramatic landscape lighting. NOT first-person. The "Skyrim feel" is about how the world communicates weight and age, not camera perspective.

**What makes voxel work at this scale:**
- Blocks are **8–16 units** per voxel, not 1-meter Minecraft cubes
- Terrain uses **smooth voxel meshing** (Transvoxel algorithm) — no visible cube edges on rolling hills
- Buildings are **hand-assembled voxel structures** — cubes are visible and intentional, like stonework
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
| `Zone.gd` | ⚠️ Minor adapt | Change Vector2 → Vector3 for player placement |
| `Room.gd` | ⚠️ Minor adapt | Rect2 bounds → AABB (3D box) for camera limits |
| `RoomTrigger.gd` | ⚠️ Port Area2D → Area3D | Same logic, different node type |
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
**Source:** https://github.com/Voxel-And-Module-Tools/godot_voxel  
**Godot 4 compatible:** Yes

This is the premier voxel terrain plugin for Godot 4. It powers Veloren-adjacent projects and supports:
- `VoxelTerrain` — infinite streaming terrain with LOD
- `VoxelMesherTransvoxel` — smooth voxel meshing (no visible cube edges on terrain)
- `VoxelMesherCubes` — blocky Minecraft-style meshing (for buildings and structures)
- `VoxelInstancer` — scatter props (trees, rocks) across terrain efficiently
- Custom voxel generators via GDScript or C++

**For this project:**
- Terrain: `VoxelMesherTransvoxel` (smooth hills, cave mouths, cliff edges)
- Buildings: `VoxelMesherCubes` (stone walls, towers, archways — the visible-cube look is intentional here, like hand-laid stone)
- Scope: zone-sized chunks, not infinite world

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

**Alternative:** Billboard sprites (`Sprite3D` in Godot) — draw the character in 2D (Aseprite), display as a 3D billboard that always faces the camera. This is the classic approach for indie voxel games and easier to produce.

**Decision point:** billboard sprites for Act I, transition to full 3D models for Act II+ when the pipeline is proven.

### Camera Rig

Fixed-elevation follow camera, not free-look:
- `Camera3D` mounted on an arm offset above and behind the player
- Elevation angle: ~45–55° (Hades-style, reveals depth without obscuring ceiling)
- Horizontal rotation: locked (the world turns, not the camera) for Act I
- Optional: allow horizontal rotation for exploration in open areas (Khorumzad descent)

```gdscript
# CameraRig.gd — attach to player or to a separate SpringArm3D node
extends Node3D

@export var target: Node3D         # The player node
@export var elevation_angle: float = 50.0   # Degrees above horizontal
@export var arm_length: float      = 12.0   # Distance from target
@export var lerp_speed: float      = 8.0    # Smoothing

func _process(delta: float) -> void:
    if not target:
        return
    var goal: Vector3 = target.global_position
    global_position = global_position.lerp(goal, lerp_speed * delta)
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

### Milestone 5-3D: First Voxel Terrain

**Goal:** Walking on actual voxel terrain.

- [ ] Set up `VoxelTerrain` node in `World3D.tscn`
- [ ] Write a simple `VoxelGeneratorScript` — flat cave floor + rock walls
- [ ] Add `PointLight3D` campfire with `CampfireFlicker.gd` (adapted for 3D)
- [ ] Add `Area3D` + `CollisionShape3D` for dialogue trigger (port of `DialogueTrigger.gd`)
- [ ] Verify: character walks on voxel surface, campfire glows, trigger fires

### Milestone 6-3D: First MagicaVoxel Assets

**Goal:** Replace placeholder boxes with real voxel art.

- [ ] Build cave wall tile in MagicaVoxel (export .glb)
- [ ] Build campfire prop in MagicaVoxel (export .glb)
- [ ] Import to Godot, assign to MeshInstance3D nodes in World3D.tscn
- [ ] Verify: scene looks like a voxel cave with warm campfire light

### Milestone 7-3D: First Character Model

**Goal:** Roland has a real appearance.

**Option A (faster):** Billboard sprite  
- Draw Roland walk cycle in Aseprite (32×48, 4 directions)
- Add as `Sprite3D` with `billboard = BILLBOARD_ENABLED`
- Sprite3D always faces camera — same pipeline as old 2D sprites

**Option B (full 3D):**  
- Build Roland in Blender (200–400 tris, flat-shaded, rigged)
- Animate: walk cycle, idle, interact
- Export .glb, import to Godot, set up `AnimationTree`

Decision: start with Option A for Act I speed, assess before Act II.

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
- **Do not use a free first-person camera.** The lore and narrative require the player to see Roland at all times. This is not Skyrim's camera; it's Skyrim's atmosphere.
- **Do not rebuild the logic autoloads.** GameState, FlagScheduler, InventoryManager, JournalUI, PauseMenu — all of this works in 3D without changes. Do not touch it.
- **Do not buy or subscribe to voxel middleware.** Zylann's plugin is free, open source, and proven. Anything paid adds lock-in with no benefit at this scale.

---

## File Structure (3D)

```
/scenes/
  World3D.tscn          ← replaces World.tscn
  Player3D.tscn         ← replaces Player.tscn
  ui/                   ← all unchanged (Journal, PauseMenu, etc.)
/scripts/
  Player3D.gd           ← replaces Player.gd
  CameraRig.gd          ← new
  CampfireFlicker3D.gd  ← minor adaptation
  Zone.gd               ← minor adapt (Vector3)
  Room.gd               ← minor adapt (AABB bounds)
  RoomTrigger3D.gd      ← port of RoomTrigger.gd
  SpawnPoint3D.gd       ← port of SpawnPoint.gd
  [all logic autoloads] ← unchanged
/assets/
  voxel/                ← NEW: .vox and .glb voxel assets (MagicaVoxel exports)
    cave_wall.glb
    campfire.glb
    archway.glb
  models/               ← NEW: .glb character models (Blender exports)
    roland.glb
    henrietta.glb
  sprites/              ← Optional: billboard sprites if using Option A
  portraits/            ← Unchanged (dialogue UI art)
  audio/                ← Unchanged
```
