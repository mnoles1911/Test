# Swimming and Water — Design Spec

Water is a traversable terrain type in the open world. Rivers, lakes, coastal inlets, and the Aldwater are all swimmable. The player is never blocked by water — they wade and swim through it. **Water is voxel-based and dynamic** — flowing rivers, player-dug channels, bucket-placed sources are all real simulation. See "Voxel Water Architecture" below.

> Cross-reference: `design/SYSTEMS_DESIGN.md` → Exploration → Water and Swimming for the overview.
> `design/INPUT_AND_CONTROLS.md` for swim_up / swim_down input bindings.
> `design/ART_DIRECTION.md` for water visual palette per biome.

---

## Voxel Water Architecture

> **⚠ SUPERSEDED 2026-05-16 by the Minecraft-model rewrite (Water Voxel
> V2).** The `CHANNEL_DATA5` side-channel + `WaterChunkMesher` + horizon
> plane described in this section have been **deleted**. Water is now a
> normal transparent **`CHANNEL_TYPE` block (id 5)** drawn by the
> terrain blocky mesher, generated at all LODs. Player queries resolve
> TYPE-5 = full water. The flow cellular-automaton is temporarily inert
> (static water + bucket place/scoop work; dynamic spread is a
> validated follow-up). **Authoritative doc:
> `design/WATER_VOXEL_V2_PLAN.md`.** This section is kept for historical
> context and will be rewritten once the V2 implementation is validated
> in-engine. Everything below describes the OLD (removed) system.

### (historical) DATA5 side-channel model — canonical 2026-05-06, v14

Water lives **per-voxel in `VoxelBuffer.CHANNEL_DATA5`**, one byte per voxel. (DATA0–4 are reserved by Zylann for TYPE/SDF/COLOR/INDICES/WEIGHTS; DATA5 is the first user-defined channel.) The encoding is canonicalised in `scripts/WaterByteCodec.gd`: `level (4 bits) | source_bit (1) | tick (3 bits)`. Air-water = byte 0. `VoxelMesherCubes` reads only `CHANNEL_COLOR` and ignores DATA5, so terrain rendering is unaffected — water voxels are invisible to the cube mesher and get their own transparent surface from `WaterChunkMesher`.

This replaces the pre-v13 model that stored ocean as an AABB "source region" in `WaterFlowManager._source_regions`. The old model produced two bugs the new model removes by construction:
- **Tunnel flooding:** a tunnel carved into a hill above sea level used to read as water (the AABB said yes; the workaround `_has_clear_vertical_path_to_surface` patched queries but not the flow tick). Now: the tunnel column was solid at gen time, no water bytes were written, no flooding possible.
- **Wave plane through hills:** a single follow-player plane drew water across the visibility horizon ignoring terrain. Now: per-chunk greedy-rectangle meshing emits water surfaces only for columns that actually have water bytes; a single follow-player horizon plane covers the distant horizon at sea level Y.

**Generator emission rule** (`CubicHeightmapGenerator._generate_block`): for each column where `ground_y < SEA_LEVEL_VOXELS=72`, write `WaterByteCodec.SOURCE_BYTE` into `CHANNEL_DATA5` from `ground_y+1` up through `SEA_LEVEL_VOXELS`. Skip columns covered by a `NoEditZone` with `blocks_water_generation=true` (snapshot pushed to the generator on the main thread by `World3DBootstrap`; worker threads read from a thread-safe local Array). Water emission is LOD0-only — distant ocean is covered by the horizon plane, not by per-LOD water voxels.

**Per-cell sources** — buckets, river headwaters, story-event flood boxes — go through `VoxelEditManager.queue_set_water_voxel(voxel_pos, byte)` or `queue_set_water_box(min, max, byte)`. Same async queue + NoEditZone gate as terrain edits, but writes DATA5 and emits `water_changed_at` (distinct from the COLOR-channel `edit_applied` signal so subscribers don't double-fire). The edit manager guards each `do_box` with `tool.is_area_editable(box)` and re-queues failed writes (up to 60 retries) so writes don't silently drop while the streamer catches up.

**Flow tick** (every 15 physics frames, ~4 Hz, only inside ACTIVE_RADIUS_M=20m of the player):
1. **Decay**: non-source flow cells whose `last_fed_tick` is older than the previous tick decrement their level. Level 0 → cell removed.
2. **Gravity drop**: every air voxel with water (DATA5 byte > 0) directly above becomes a flow cell at MAX_LEVEL=8.
3. **Lateral spread**: cells with level>1 push to 4 horizontal neighbours at level-1, gated on (a) neighbour's voxel-below is solid or water, (b) neighbour isn't blocked by a `NoEditZone.blocks_water_flow=true` zone.

The simulator pre-copies each chunk's DATA5 + COLOR + chunk-above-DATA5 buffers ONCE per chunk per tick, then walks the in-memory bytes for all decay/drop/spread checks. Replaces an earlier per-voxel `tool.get_voxel` pattern that cost ~324k tool calls/sec at 4 Hz × 27 chunks/edit. The simulator keeps an in-memory `_cells` dict for transient flow cells (level<8 cells produced by spread); sources and ocean live in DATA5.

**Visuals:** `WaterChunkMesher` (child Node3D under `WaterFlowManager` autoload) reads DATA5 per chunk via `terrain.copy()`, finds the topmost-water voxel per (X, Z) column, groups columns by top-Y, and runs greedy 2D run-merge to produce as few quads as possible. Uniform-channel fast path: `VoxelBuffer.is_uniform` short-circuits the per-voxel scan for all-air or all-source chunks (the dominant case at sea level row). A fully-ocean chunk collapses to a single 16×16 quad. Coastline chunks split into a few rectangles. Render-radius cull at `MESH_RENDER_RADIUS_M=96 m` around the player; the per-frame build budget adapts to last frame's delta (16/frame at <18 ms, 1/frame at >50 ms) so the mesher yields to the terrain LOD streamer during initial load. Past the radius, a single follow-player horizon plane (CULL_BACK so it's invisible from below) at the configured sea level Y fills the visible distance — `render_priority=-1` on the horizon material so the chunked mesh wins z-fight wherever they overlap.

**Player query API** (used by `Player3D._update_water_state` each physics frame):
- `is_position_in_water(world_pos: Vector3) -> bool` — single DATA5 byte read; `WaterByteCodec.is_water(byte)`.
- `get_water_level_at(world_pos: Vector3) -> int` (0–8) — single DATA5 byte read; `WaterByteCodec.level_of(byte)`.
- `get_flow_velocity_at(world_pos: Vector3) -> Vector3` — derived from the level gradient in 4 horizontal neighbours. Capped at FLOW_MAX_SPEED=3 m/s. Inside ocean interiors the gradient is zero (every neighbour is also level 8) so oceans don't push; rivers feeding oceans naturally produce a downstream pulse at the level transition.

**Edit integration:** `WaterFlowManager._on_edit_applied` listens to `VoxelEditManager.edit_applied` (terrain COLOR edits) and dirty-marks the edited chunk + 1-chunk neighbourhood for the flow tick. `WaterChunkMesher` listens to `water_changed_at` (DATA5 edits) and rebuilds affected chunks' surface meshes. Together: carving voxels under or beside water → next flow tick discovers new air-below-water voxels and propagates flow into them; pouring a bucket → mesher rebuild shows the water immediately.

**Save format:** water lives in the chunk SQLite stream alongside terrain edits via `VoxelStreamSQLite`. Nothing additional in the JSON save. `WORLD_GENERATOR_VERSION=14` after this refactor; pre-v14 saves are hard-rejected at load (the AABB-based ocean has no DATA5 equivalent and would read as fully dry).

**NoEditZone constraint:** zones with `blocks_water_generation=true` must be present in the scene tree at world load. Runtime-streamed zones (added later by `EntityStreamer`) cannot retroactively dry already-generated chunks — generator output is final once written. Settlements that need to be dry below sea level must be in-scene at load.

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
- Y movement: Space = swim up, Shift/Ctrl = swim down (dive)
- **Buoyancy (2026-05-18, #13):** with no vertical input Roland is
  lighter than water. SUBMERGED → drifts up toward the surface
  (`BUOYANT_RISE_SPEED` 1.2 m/s, ramp `BUOYANT_RISE_ACCEL` 3.0). At the
  SURFACE (in water, head clear) → vertical velocity eases to 0
  (`BUOYANT_SETTLE_ACCEL` 4.0) so he settles and bobs at the waterline.
  This **replaces** the earlier deliberate slow-sink ("game-y tension")
  model — letting go now surfaces you; *diving* (descend input) is the
  thing that takes effort and fights the buoyant rise. Drowning tension
  now comes from the breath timer + actively diving, not from passively
  sinking. Player3D constants `BUOYANT_RISE_SPEED` /
  `BUOYANT_RISE_ACCEL` / `BUOYANT_SETTLE_ACCEL`.
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

The water surface shader reads two uniforms (`wind_dir`, `wind_strength`) that bias wave direction and scale wave amplitude. Since the voxel-water refactor (PR #131), water is owned by the `WaterFlowManager` autoload — not per-body `WaterVolume` Area3Ds — and the wind is pushed globally to the shared `assets/shaders/water_material.tres` exactly once per frame.

**Public API (live as of 2026-05-04):**

```gdscript
# WaterFlowManager.gd (autoload)
func set_global_wind(direction: Vector3, strength: float) -> void
```

`direction` is a unit vector in world XZ (Y component ignored). `strength` is 0–5: `0` = dead calm, `1` = breezy, `3` = stormy chop, `5` = lethal storm.

**WeatherManager wiring (live):** `WeatherManager._process` writes the interpolated wind values every frame:

- `wind_strength` interpolates between state profiles during the 30 s state transition (LIGHT_RAIN = 1.5, HEAVY_RAIN = 3.5, FOG = 0.3, etc.).
- `wind_direction` is decoupled from state changes — `WeatherManager` resamples a new XZ heading every 90 s and lerps `wind_direction` toward it at 3°/s, so direction NEVER snaps when the state changes.

The water material is loaded lazily on the first `set_global_wind` call so cold worlds that never touch weather pay no overhead.

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
