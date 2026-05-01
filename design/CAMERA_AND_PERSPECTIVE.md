# Camera and Perspective — Design Note

## The Camera in a 3D Open World

Game One uses a **third-person over-shoulder follow camera** in 3D. The player sees Roland from behind and slightly above, at approximately 15–20° above horizontal. This is the same camera convention as **The Witcher 3**, **Dark Souls**, and **Elden Ring** — the player navigates through the world as Roland, with full spatial awareness of the environment ahead and the horizon beyond.

This is distinct from:
- Skyrim's first-person camera (not this)
- A fixed-elevation isometric camera like Hades or Diablo (was considered; changed when scope moved to open world)
- A free-look camera with no character visible (not this — Roland must always be present in frame)

---

## Why Third-Person Over-Shoulder

**Open world demands a horizon.** With a playable Mira of 12km × 10km, the player needs to feel the world at scale — the Spine mountains visible as a distant ridgeline from Aldenholt, the Greatwood canopy rising as they approach from the south, Drûn-Khazad's ash cloud present on the Thal horizon before arrival. A fixed 50° elevation camera compresses vertical terrain and hides distances. Third-person over-shoulder reveals the horizon and lets geography communicate scale.

**1-vs-many melee requires spatial awareness.** The combat design is real-time, 1-vs-many. The player needs to read enemy positions around Roland, track telegraph animations, and manage flanking threats. Third-person over-shoulder — combined with the lock-on system — provides this awareness. The Hades camera provided spatial awareness via overhead view; this camera provides it via player-controlled rotation and lock-on targeting.

**Roland must be visible.** This is his story. His silhouette, his armor under torchlight, his posture at rest or under pressure — these are part of the narrative language. Third-person keeps Roland in frame and readable at all times.

---

## Camera Setup in Godot 4.3

`SpringArm3D` is the right node. It handles camera collision automatically — when terrain or a wall comes between the camera and Roland, the arm shortens rather than clipping through geometry.

```
Player3D (CharacterBody3D)
└── CameraTarget (Node3D)    ← offset upward to Roland's shoulder height (~1.5m)
    └── SpringArm3D          ← player-rotatable arm
        └── Camera3D         ← at the end of the arm
```

### CameraRig.gd key exports:

```gdscript
@export var arm_length: float = 5.0
# Standard third-person distance. SpringArm3D shortens this automatically
# when walls or terrain block the camera — no manual per-room configuration needed.

@export var elevation_degrees: float = 15.0
# Degrees above horizontal. 10–20 for standard over-shoulder.
# Player can tilt within vertical_min/max range below.

@export var horizontal_sensitivity: float = 0.3
@export var vertical_min_degrees: float = -20.0
@export var vertical_max_degrees: float = 45.0

@export var dialogue_arm_length: float = 3.5
# Arm length to tween to when Dialogic opens a Tier 2/3 conversation.
# Pulls camera in and drifts slightly to profile framing.
```

### Input map additions required:
- `camera_left` / `camera_right` — Q/E or right stick horizontal
- `camera_up` / `camera_down` — right stick vertical (gamepad) or mouse Y
- `lock_on` — middle mouse button or right stick click

---

## Lock-On System

Lock-on is essential for 1-vs-many melee at third-person. Without it the camera drifts during multi-enemy encounters and the player loses target clarity.

**Behavior:**
- Press `lock_on` to target the nearest enemy in the forward arc within range
- Camera pivots to keep the locked enemy in the right 60% of frame; Roland occupies the left foreground — standard Souls framing
- Roland's attacks, dodge direction, and block facing are relative to the locked target
- Cycle targets with `camera_left` / `camera_right` while locked
- Lock-on disengages automatically when the target dies or exits range
- Press `lock_on` again to disengage manually

**Reference:** `design/COMBAT_DESIGN_3D.md` specifies the lock-on detection radius, token system, and target priority logic.

---

## Dialogue Camera

For Tier 2 and Tier 3 conversations, a subtle camera shift without a full cinematic cut system:

- When Dialogic opens a conversation, tween `SpringArm3D.spring_length` to `dialogue_arm_length` (~3.5m) and drift the horizontal angle slightly so Roland's profile and the NPC's face are both in frame
- On dialogue close: tween back to gameplay arm length and angle
- This lives entirely in `CameraRig.gd` as a mode flag — two or three lines to enter and exit

The Dialogic portrait system handles character expression. The world-space camera just needs to not be directly behind Roland's head when he's talking to someone.

---

## Indoor and Confined Space Behavior

`SpringArm3D` collision is the primary tool. As Roland moves into a building, cave, or dungeon corridor, the arm shortens automatically. The camera gets tighter in confined spaces — more claustrophobic underground, more open on a hillside. This is the correct behavior and requires no per-location camera scripting.

| Context | Arm Length Target | Notes |
|---|---|---|
| Open world — plains, road | 5.5m | Full view, horizon visible |
| City streets — Aldenholt | 4.5m | SpringArm clips against buildings |
| Cave / dungeon entrance | 3.0–4.0m | Auto-shortened by SpringArm |
| Khorumzad deep levels | 2.0–3.0m | Increasingly tight — intentional |
| Dialogue moment | 3.5m (tweened) | Drift to slight profile framing |
| Combat lock-on | 5.0m + offset | Locked enemy in right frame half |

These are targets. `SpringArm3D` modulates dynamically from the desired arm length. Do not hardcode per-room values — let the physics do it.

---

## What Changed from the Prior Design

The original design used a fixed-elevation camera at ~50° above horizontal (Hades-style). That camera was designed for a zone-based RPG with discrete scenes. The open-world scope change made it the wrong choice.

| Previous (Hades fixed) | Current (third-person over-shoulder) |
|---|---|
| Fixed 50° elevation, never rotates | ~15° elevation, player-rotatable |
| World read from above | World read at eye level, horizon visible |
| Horizon and distant landmarks not visible | Geography communicates scale |
| Combat: overhead view shows all enemies | Combat: lock-on system provides target clarity |
| `allow_horizontal_rotation: bool` export | Always rotatable |
| Per-room arm length configuration | SpringArm3D handles this via physics collision |

The `SpringArm3D` node structure and `CameraRig.gd` architecture survive. The exported values and input handling change.
