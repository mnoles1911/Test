# Swimming and Water — Design Spec

Water is a traversable terrain type in the open world. Rivers, lakes, coastal inlets, and the Aldwater are all swimmable. The player is never blocked by water — they wade and swim through it.

> Cross-reference: `design/SYSTEMS_DESIGN.md` → Exploration → Water and Swimming for the overview.
> `design/INPUT_AND_CONTROLS.md` for swim_up / swim_down input bindings.
> `design/ART_DIRECTION.md` for water visual palette per biome.

---

## Water Body Structure

Each water body uses two nodes placed together in the scene:

```
WaterBody (Node3D)
├── WaterVisual (MeshInstance3D)   ← Boujie Water Shader
└── WaterVolume (Area3D)           ← physics detection
    └── CollisionShape3D           ← BoxShape3D spanning the water body
```

**WaterVisual:** Uses the **Boujie Water Shader** (Godot Asset Library #2070, compatible with Godot 4.1+, GDScript).
- LOD ring mesh — efficient single draw call even at ocean scale
- Supports animated surface, reflections, shoreline foam
- Works with `WorldEnvironment` fog for underwater transitions
- Tag: set `WaterVolume` metadata `water_depth: float` to indicate max depth (used for submersion detection)

**WaterVolume (`Area3D`):** Collision volume covering the full 3D extent of the water body — not just the surface.
- Connect `body_entered` and `body_exited` to `Player3D._on_water_volume_entered/exited()`
- Add to group `"water_volume"` so Player3D can query depth from metadata

**Scale notes:**
- Lakes and rivers: `CollisionShape3D` is a `BoxShape3D` sized to fit the body
- Ocean/sea (Shroud Sea): the Shroud Sea is a transition / skybox boundary — no swimming across it
- River currents: separate `Area3D` volumes with custom metadata (see River Currents section)

---

## Swimming State Machine

Managed in `Player3D.gd`. Three states:

### WALKING (default)
Normal ground movement. `motion_mode = MOTION_MODE_GROUNDED`.  
Sprint costs endurance. Gravity applied normally.

### SWIMMING_SURFACE
Entered when Player3D's Y position is above the water floor but the player's waist (Y - 0.85m) is below the water surface Y.

- `motion_mode = MOTION_MODE_FLOATING`
- XZ movement driven by camera-facing direction
- Y movement: Space = swim up, Ctrl = swim down
- Speed: ~3 m/s (slower than walking)
- Endurance is NOT drained by swimming (only by holding breath when submerged)
- Sprint key: ignored while swimming
- Camera: standard third-person, arm shortens slightly over water surface

```gdscript
# Player3D.gd — state detection on water_volume entry
func _on_water_volume_entered(body) -> void:
    if body == self:
        _water_surface_y = _current_water_volume.global_position.y + _current_water_volume.shape.size.y * 0.5
        _in_water = true

func _physics_process(delta: float) -> void:
    var player_waist_y: float = global_position.y + 0.0  # center of capsule
    if _in_water and player_waist_y < _water_surface_y:
        _swim_state = SwimState.SURFACE
        motion_mode = MOTION_MODE_FLOATING
    elif not _in_water:
        _swim_state = SwimState.WALKING
        motion_mode = MOTION_MODE_GROUNDED
```

### SWIMMING_SUBMERGED
Entered when the player's head (Y + 0.85m) drops below `_water_surface_y`.

- Same `MOTION_MODE_FLOATING`
- Breath timer begins counting down from 30 seconds
- Audio: muffled filter applied (AudioServer bus effect)
- Visual: underwater post-process overlay (WorldEnvironment environment blend or CanvasLayer shader)
- Camera: arm shortens to ~2.5m, slight blue tint overlay
- When breath reaches 0: drowning damage — `_health -= 5.0 * delta` per second until surface

**Surfacing:** When head Y rises above `_water_surface_y`, state returns to SURFACE and breath resets to 30s after a 2s recovery delay.

**Endurance and swimming:** Endurance is not affected by swimming at surface or submerged. Breath and endurance are separate meters. Both can be empty simultaneously.

---

## Breath System

```gdscript
const BREATH_MAX: float = 30.0
const DROWNING_DAMAGE_PER_SEC: float = 5.0
const BREATH_RECOVERY_DELAY: float = 2.0

var _breath: float = BREATH_MAX
var _drowning: bool = false

func _process_breath(delta: float) -> void:
    if _swim_state == SwimState.SUBMERGED:
        _breath = max(0.0, _breath - delta)
        if _breath == 0.0:
            _drowning = true
            _health -= DROWNING_DAMAGE_PER_SEC * delta
    elif _swim_state != SwimState.SUBMERGED and _drowning:
        _drowning = false
        # Brief delay before breath restores
        await get_tree().create_timer(BREATH_RECOVERY_DELAY).timeout
        _breath = BREATH_MAX
    elif _swim_state == SwimState.SURFACE:
        _breath = min(BREATH_MAX, _breath + (BREATH_MAX / 10.0) * delta)
```

**HUD:** Breath displays as a small bubble bar above the endurance bar, visible only when submerged. Disappears when breath is full and player is not in water.

---

## River Currents

Rivers have directional current volumes placed along their course. Each current `Area3D` has exported metadata:

```gdscript
# RiverCurrent.gd — attached to an Area3D along the river path
@export var current_direction: Vector3 = Vector3(1, 0, 0)  # normalized XZ vector
@export var current_strength: float = 2.0  # m/s push

func _on_body_entered(body: Node3D) -> void:
    if body.is_in_group("player"):
        body.set_river_current(current_direction, current_strength)

func _on_body_exited(body: Node3D) -> void:
    if body.is_in_group("player"):
        body.clear_river_current()
```

**In Player3D.gd** — current applied each physics frame:

```gdscript
var _river_current_dir: Vector3 = Vector3.ZERO
var _river_current_strength: float = 0.0

func set_river_current(dir: Vector3, strength: float) -> void:
    _river_current_dir = dir
    _river_current_strength = strength

func clear_river_current() -> void:
    _river_current_dir = Vector3.ZERO
    _river_current_strength = 0.0

func _physics_process(delta: float) -> void:
    # ... other movement ...
    if _in_water and _river_current_strength > 0.0:
        velocity += _river_current_dir * _river_current_strength * delta
```

> **Godot 4.4 note:** `CharacterBody3D.get_gravity()` does NOT respect Area3D gravity overrides — this is a confirmed engine bug. Do NOT use `Area3D.gravity` for river currents; always use manual velocity addition as shown above.

**Current strength guidelines:**
| Water type | Strength |
|---|---|
| Calm lake inlet | 0.0 (no current) |
| Slow river | 1.5 m/s |
| Aldwater main channel | 3.0 m/s |
| Flood spillway (scripted scene) | 6.0 m/s (can prevent upstream swimming) |

---

## Camera Behavior Underwater

- `SpringArm3D` arm shortens to ~2.5m when submerged (auto-handled by SpringArm collision against water surface geometry)
- `Camera3D` adds a `CameraAttributes` environment blend for slight blue tint and reduced fog distance
- No special underwater camera script needed — SpringArm collision handles the arm shortening naturally

**Do not** use a separate camera mode for underwater. The standard CameraRig handles it via SpringArm collision.

---

## Input Map Additions Required

Add to Project Settings → Input Map:
- `swim_up` — Space (same as jump; only active in SWIMMING state, no conflict)
- `swim_down` — Ctrl (same as crouch; only active in SWIMMING state, no conflict)

Both actions can share keys with jump/crouch because Player3D checks swim state before processing them.

---

## Water Bodies in Act I

| Water body | Location | Notes |
|---|---|---|
| Aldwater (river) | ~3800–4600m x, crosses z=5500–6200m | Main river through Aldenholt region; moderate current |
| Aldenholt harbor inlet | ~4200m x, ~6400m z | Coastal — shallow, no current |
| Greatwood forest pool | ~2000m x, ~1800m z | Deep, still; used in Aelorin lore scenes (Act II) |

Deeper ocean (Shroud Sea, Caer Brannoch approach) is handled as a transition boundary — no open-water swimming across it. The player boards a vessel for the Brotherhood voyage arc.
