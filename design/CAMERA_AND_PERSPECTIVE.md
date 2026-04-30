# Camera and Perspective — Design Note

## The Camera in a 3D Voxel Game

Game One uses a **fixed-elevation follow camera** in 3D. This is distinct from:
- Skyrim's first-person camera (not this)
- A true isometric orthographic camera (not this — we use perspective)
- A free-look 3D camera the player rotates (not this — Act I locks horizontal angle)

The camera sits above and behind Roland, at approximately **50° above horizontal**, and follows him through the world. This is the same camera style as **Hades**, **Diablo 3**, and **Grim Dawn** — games where the player sees their character at all times but the world feels three-dimensional.

---

## Why This Camera

- **Narrative:** Roland must always be visible. This is his story. The camera serves that.
- **Voxel depth:** A 50° angle reveals the height and depth of voxel structures — cave ceilings feel present, towers feel tall, tunnels feel claustrophobic.
- **Lighting drama:** Real 3D directional light from above-behind creates natural shadow drama on voxel surfaces without designer intervention.
- **Familiar to players:** This angle is well-understood. Players navigate it intuitively.

---

## Camera Setup in Godot 4.3

Use a `SpringArm3D` node as the camera arm. `SpringArm3D` automatically handles camera collision — if a wall comes between the camera and Roland, the camera pulls in toward Roland rather than clipping through.

```
Player3D (CharacterBody3D)
└── CameraTarget (Node3D) ← offset upward to Roland's chest height
    └── SpringArm3D       ← sets arm length and elevation angle
        └── Camera3D      ← the actual camera, at the end of the arm
```

### CameraRig.gd (attaches to SpringArm3D or Player3D):

```gdscript
extends Node3D
# CameraRig — fixed-elevation follow camera for 3D voxel world.
#
# The SpringArm3D parent handles collision avoidance automatically.
# This script only needs to set the initial rotation and optionally
# allow slow horizontal rotation for exploration scenes.

@export var elevation_degrees: float = 50.0
# Degrees above horizontal. 50° is Hades-ish. 45° is more top-down.
# Lower = closer to ground-level = more dramatic. Higher = more overview.

@export var arm_length: float = 12.0
# How far the camera sits from Roland (in meters).
# 8–10 for tight indoor spaces. 12–15 for outdoor zones.

@export var allow_horizontal_rotation: bool = false
# Set true for outdoor exploration zones (Ashfields, Greatwood).
# Keep false for indoor spaces (Archive, Iron Chalice chapel).

func _ready() -> void:
    var spring_arm: SpringArm3D = get_parent()
    spring_arm.spring_length = arm_length
    rotation_degrees.x = -elevation_degrees
```

### SpringArm3D Inspector settings:
- `Spring Length`: 12.0 (adjust per zone)
- `Collision Mask`: same layer as terrain/walls
- `Shape`: leave default (sphere)

---

## Per-Location Camera Notes

| Location | Arm Length | Elevation | Horizontal Rotation |
|---|---|---|---|
| Cave (Milestone 4-3D) | 10 | 50° | No |
| Aldenholt streets | 12 | 48° | No |
| Archive interior | 8 | 55° | No — tight ceiling |
| Iron Chalice chapel | 9 | 52° | No |
| Ashfields (Act IV open) | 16 | 42° | Optional |
| Khorumzad descent (levels 1–3) | 10 | 50° | No |
| Khorumzad deep (levels 7–9) | 8 | 58° | No — oppressive ceiling |
| Greatwood canopy walk | 14 | 38° | Optional |

The camera getting closer and higher-angled as the player descends into Khorumzad is intentional — the world should feel like it's pressing in.

---

## Orthographic vs. Perspective

**Use perspective** (Godot's default `Camera3D` mode).

Orthographic (parallel projection) makes the world look flat and removes depth cues. Perspective projection is what makes voxel surfaces read as three-dimensional — you can see the depth of a cave tunnel, the height of a tower, the recession of a stone corridor.

If a diorama/toy-box aesthetic is desired later (see Zelda: Link's Awakening 2019), orthographic can be revisited. For Act I, perspective.

---

## Room-to-Room Camera Transitions (Zone Framework)

When `RoomTrigger3D` fires and `Zone.gd` calls `enter_room()`, the camera limits update to the new room's bounds. In 3D, `Room3D.gd` exports an `AABB` (axis-aligned bounding box) instead of a `Rect2`. Zone.gd uses this to update the camera arm:

```gdscript
# In Zone.gd enter_room():
var cam_arm: SpringArm3D = player.get_node("CameraTarget/SpringArm3D")
cam_arm.spring_length = room.camera_arm_length
```

---

## What Changed from the 2D Plan

| 2D plan | 3D reality |
|---|---|
| Camera2D follows player in screen space | Camera3D on SpringArm3D in world space |
| camera.limit_left/right/top/bottom | SpringArm3D.spring_length + AABB room bounds |
| 3/4 perspective is art style only | 3D perspective is real — depth is actual geometry |
| No camera transform for angle | Camera3D elevated 50°, real angle |
| CanvasModulate for darkness | WorldEnvironment ambient + fog |
| PointLight2D for torches | OmniLight3D for torches |
