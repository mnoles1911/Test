# Swimming and Water — Design Spec

Water is a traversable terrain type in the open world. Rivers, lakes, coastal inlets, and the Aldwater are all swimmable. The player is never blocked by water — they wade and swim through it. **Water is voxel-based and dynamic** — flowing rivers, player-dug channels, bucket-placed sources are all real simulation. See "Voxel Water Architecture" below.

> Cross-reference: `design/SYSTEMS_DESIGN.md` → Exploration → Water and Swimming for the overview.
> `design/INPUT_AND_CONTROLS.md` for swim_up / swim_down input bindings.
> `design/ART_DIRECTION.md` for water visual palette per biome.

---

## Voxel Water Architecture (canonical, 2026-05-05)

Water lives in a `Dictionary<Vector3i, int>` of cells managed by the `WaterFlowManager` autoload, NOT in the voxel terrain's `CHANNEL_COLOR`. VoxelMesherCubes treats alpha-byte as binary opacity AND material-ID; per-voxel transparency is impossible without forking Zylann. The decoupled architecture sidesteps that constraint and adds dynamic flow.

**Two kinds of water source:**
1. **Source REGIONS** — designer-placed AABBs (oceans, lakes). Stored as a small list, never materialized as cells. `is_position_in_water` AABB-tests against them. A 200×200 m ocean costs O(1) memory.
2. **Per-cell sources** — single voxel marked is_source=true. Used for buckets, river headwaters, designer-placed pour points.

Both kinds count as `level=8` for the flow rules.

**Flow tick** (every 15 physics frames, ~4 Hz, only inside ACTIVE_RADIUS_M=20m of the player):
1. **Decay**: non-source cells whose `last_fed_tick` is older than the previous tick decrement their level. Level 0 → cell removed.
2. **Gravity drop**: every air voxel with water directly above becomes a flow cell at MAX_LEVEL=8.
3. **Lateral spread**: cells with level>1 push to 4 horizontal neighbors at level-1, gated on (a) neighbor's voxel-below is solid or water (gravity wins), (b) neighbor isn't blocked by a `NoEditZone.blocks_water_flow=true` zone.

**Visuals:** `WaterChunkMesher` (child Node3D under WaterFlowManager autoload) walks the dictionary + source regions per chunk and emits a transparent surface mesh. Reuses the existing sine-sum vertex-displacement shader (`assets/shaders/water.gdshader`). Render-radius cull at 64m around the player; FIFO dirty queue drains 2 chunks/frame. v1 emits source-region top-planes only; per-cell partial-height surfaces deferred.

**Player query API** (used by `Player3D._update_water_state` each physics frame):
- `is_position_in_water(world_pos: Vector3) -> bool`
- `get_water_level_at(world_pos: Vector3) -> int` (0–8)
- `get_flow_velocity_at(world_pos: Vector3) -> Vector3` — derived from the level gradient in 4 horizontal neighbors. Capped at FLOW_MAX_SPEED=3 m/s. Inside source-region interiors the gradient is zero (every neighbor is also level 8) so oceans don't push; rivers feeding oceans naturally produce a downstream pulse at the level transition.

**Edit integration:** `WaterFlowManager._on_edit_applied` listens to `VoxelEditManager.edit_applied` and dirty-marks the edited chunk + 1-chunk neighborhood. Carving voxels under or beside water → those chunks' next flow tick discovers new air-below-water voxels and propagates flow into them. This is what makes "dig a hole near a river → river fills it" work.

**Save format:** per-cell sources persist in the GameState save under `water_sources` (Array of `{x, y, z}` dicts). Source regions are scene data and re-added by `World3DBootstrap` on each load. Flowing cells aren't persisted — they regenerate from sources within a few flow ticks of load. `WORLD_GENERATOR_VERSION=11` after this refactor; pre-v11 saves invalidate.

**Boujie Water Shader** (Godot Asset Library #2070) remains an optional future upgrade for reflections, shoreline foam, and single-draw LOD ring mesh.

---

## Water Body Structure (legacy spec — superseded by Voxel Water Architecture above)

The Area3D-based "two nodes per water body" model documented below was the implementation through PR #130 (2026-05-04). **It was replaced by the voxel-based architecture in 2026-05-05.** This section is kept for context on why the refactor happened and what changed.

```
[LEGACY] WaterBody (Node3D)
├── WaterVisual (MeshInstance3D)   ← shader on a flat plane mesh
└── WaterVolume (Area3D)           ← physics detection
    └── CollisionShape3D           ← BoxShape3D spanning the water body
```

The legacy model worked but couldn't dynamically respond to terrain edits. Carving a voxel at the edge of a `WaterVolume` Area3D left a visible gap (water plane stops at volume edge; new air voxel below isn't filled). No flowing rivers, no player-dug channels, no bucket-placed sources. The voxel water refactor was prompted by needing all three for an open-world destructible-terrain game.

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
- **Underwater tint filter (implemented 2026-05-04):** `scripts/UnderwaterFilter.gd` is a `CanvasLayer` child of Player3D containing a translucent blue-green `ColorRect` (default `Color(0.18, 0.32, 0.42, 0.42)`) that fills the viewport. `Player3D._update_water_state()` calls `set_active(_is_submerged)` every frame; the filter only flips visibility when the state actually changes (idempotent).
- The `WorldEnvironment` fog approach was rejected: `DayNightCycle.gd` writes `env.fog_light_color` every frame, so any underwater fog tweak would be overwritten on the next tick. The `CanvasLayer` overlay decouples the underwater feel from the day/night system.
- Future polish: replace the flat `ColorRect` with a `ShaderMaterial` that adds screen-depth fog falloff and slight chromatic aberration. v1 ships with the flat tint — readable, zero shader maintenance.

---

## Wind & Weather Coupling

The water surface shader reads two uniforms (`wind_dir`, `wind_strength`) that bias wave direction and scale wave amplitude. Designers tune them per body via `WaterVolume.gd` `@export` sliders today; the future `WeatherManager` will write them programmatically.

**Public API:**

```gdscript
# WaterVolume.gd
func set_wind(direction: Vector3, strength: float) -> void
```

`direction` is a unit vector in world XZ (Y component ignored). `strength` is 0–5: `0` = dead calm, `1` = breezy, `3` = stormy chop, `5` = lethal storm. Calling this is equivalent to setting both `wind_direction` and `wind_strength` `@exports` at once but pushes the shader uniforms exactly once instead of twice.

**Future WeatherManager wiring:** when weather state changes, iterate every Area3D in the `water_volume` group, call `set_wind(weather.wind_direction, weather.wind_strength)` on each. Smoothing (lerp the values over a few seconds rather than snapping) is the WeatherManager's responsibility, not WaterVolume's.

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
