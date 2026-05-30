# GDScript patterns — project-specific gotchas

The four hard rules that will silently break your code if violated live in `CLAUDE.md` ("Critical GDScript patterns"). This doc holds the longer-form gotchas + reference recipes.

---

## Manual `_input` dispatch for UI (full recipe)

`Button.pressed` and `HSlider.value_changed` don't fire because Dialogic's input subsystem consumes `InputEventMouseButton` globally. Layout / anchors / `mouse_filter` are NOT the cause.

```gdscript
func _input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton): return
    var mb := event as InputEventMouseButton
    if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT: return
    _dispatch_click(mb.position)

func _dispatch_click(pos: Vector2) -> void:
    if _hits(_my_button, pos):
        _on_my_button_pressed()
        return
    if _my_slider.visible and _my_slider.get_global_rect().has_point(pos):
        var rect := _my_slider.get_global_rect()
        var t: float = clampf((pos.x - rect.position.x) / rect.size.x, 0.0, 1.0)
        _my_slider.value = _my_slider.min_value + t * (_my_slider.max_value - _my_slider.min_value)

func _hits(ctrl: Control, pos: Vector2) -> bool:
    if ctrl == null or not ctrl.visible: return false
    if ctrl is Button and (ctrl as Button).disabled: return false
    return ctrl.get_global_rect().has_point(pos)
```

Reference impl: `PauseMenu._input / _dispatch_click / _hits`. See `LESSONS_LEARNED.md` 2026-05-03 + 2026-05-09.

---

## Other essentials

```gdscript
# Autoload check before Dialogic:
if get_node_or_null("/root/Dialogic"):
    Dialogic.start("timeline_name")

# Frame-rate-independent deceleration:
velocity = velocity.move_toward(Vector3.ZERO, DECEL * delta)  # NOT * SPEED

# One-shot signal:
Dialogic.timeline_ended.connect(_on_done, CONNECT_ONE_SHOT)

# OmniLight3D property: .light_energy (NOT .energy — that's PointLight2D).

# Capsule CollisionShape3D: offset upward by half its height (Y = +0.85 for 1.7m).

# 2D input → 3D XZ:
var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
var direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
# Never map input_dir.y → velocity.y. Ground plane is XZ; Y is gravity only.

# Camera-relative movement (Player3D uses this):
var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
# CameraRig rotates the body to match camera yaw; transform.basis carries that.
```

---

## Voxel material lookup — registry only

```gdscript
# WRONG — hardcodes the encoding.
var material_id: int = packed_voxel & 0xFF

# RIGHT — registry owns encoding.
var material_id: int = VoxelMaterialRegistry.material_id_from_packed(packed_voxel)
var material: VoxelMaterial = VoxelMaterialRegistry.get_by_id(material_id)
```
Same for writes: `VoxelMaterialRegistry.pack_voxel(mat_id, color)`.

---

## Water = NATIVE Zylann fluid (since 2026-05-18 pivot)

Water is `VoxelBlockyModelFluid` at `CHANNEL_TYPE` ids 16–23. **NEVER hardcode the water id.** Single authority is `scripts/WaterMaterial.gd` (path-preload it — it has NO `class_name` so it stays headless-safe; do NOT add one):

```gdscript
const WaterMaterial := preload("res://scripts/WaterMaterial.gd")
WaterMaterial.is_water_type(t)                # replaces every `== 5`
WaterMaterial.render_id_for_level(level, dir) # sim level -> TYPE id
```

- 8 `VoxelBlockyModelFluid` models, level 1..8 → `CHANNEL_TYPE` id 16..23 (full = 23), one shared `VoxelBlockyFluid` (`dip_when_flowing_down` = waterfalls #12).
- Injected at RUNTIME by `World3DBootstrap` via `VoxelBlockyLibrary.add_model()` — `blocky_library.tres` is UNCHANGED (bootstrap is source of truth, dodges the `.tres`-doesn't-restore bug).
- Blocky mesher auto-slopes the surface between differing levels (smooth fill/flow front) and feeds flow to the shader via UV. NO custom mesher, NO horizon plane (`water_chunk_mesher` C++ deleted).
- Legacy cube id 5 retained only so pre-pivot saves still read as water. C++ generator emits id 23 + `WaterByteCodec.SOURCE_BYTE(24)` in `CHANNEL_DATA5` for infinite-source oceans.
- `DATA5/WaterByteCodec` is the SIM source of truth (level/source/dir); `CHANNEL_TYPE` is a pure render projection.
- Player water queries go through `WaterFlowManager.is_position_in_water / .get_water_level_at` (fluid-id aware).

Zylann reserves DATA0–4 for `TYPE / SDF / COLOR / INDICES / WEIGHTS`. Plan: `design/WATER_STAGE6_PLAN.md` + `design/WATER_NATIVE_FLUID_GATE0_RESULTS.md`.

---

## VoxelBuffer / VoxelLodTerrain quirks

**`VoxelBuffer CHANNEL_COLOR` must be 32-bit BEFORE chunks stream** — default 8-bit truncates the packed RGBA+mat_id to just the R byte (terrain renders near-black). Done once in `World3DBootstrap._ready()`:

```gdscript
if "format" in terrain:
    var fmt := VoxelFormat.new()
    fmt.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
    terrain.format = fmt
# NEVER call set_channel_depth() inside _generate_block — invalidates buffer storage.
```

**`VoxelGeneratorScript._generate_block` runs on a worker thread — no SceneTree access:**

```gdscript
# WRONG inside _generate_block — crashes / returns null on Zylann worker threads.
var registry = get_node_or_null("/root/NoEditZoneRegistry")

# RIGHT — cache a plain-data snapshot on main thread, push into generator,
# read from local Array inside _generate_block. See NoEditZoneRegistry.get_water_blocking_aabbs_snapshot().
```

**`Dictionary[int, PackedByteArray]` mutation requires read-modify-write** (indexing returns a copy in Godot 4):

```gdscript
var bmp: PackedByteArray = my_dict.get(key, PackedByteArray())
bmp[index] = value
my_dict[key] = bmp
```

**Some `VoxelLodTerrain` properties are INT — verify with read-back:**

```gdscript
# WRONG — collision_update_delay is INT; set() truncates 0.1 → 0, then every
# stream-in/out fires a main-thread collision rebuild (100+ ms frame spikes).
terrain.set("collision_update_delay", 0.1)

# RIGHT — pass integer milliseconds, ALWAYS read back.
terrain.set("collision_update_delay", 100)
print("actual=%s" % terrain.get("collision_update_delay"))
```

Generic rule: when configuring `VoxelLodTerrain` programmatically, read the value back. Some properties also clamp silently (`mesh_block_size = 32` was clamped to 16 in some scenes). Bootstraps print readbacks as policy.

**Zylann blocky-library properties: use the methods, NOT `.set()`, AND re-apply at runtime:**

```gdscript
# WRONG — silently no-ops. The property name appears in get_property_list() but
# Zylann routes actual storage through method pairs; .set() writes to a virtual
# bag the gdextension only reads for serialization. Result: all-white terrain.
model.set("tile_top", Vector2i(2, 0))
model.set("material_override_0", atlas_mat)

# RIGHT — call the method.
model.call("set_tile", 3, Vector2i(2, 0))   # 3 = SIDE_POSITIVE_Y
model.call("set_material_override", 0, atlas_mat)
```

Even with the methods, values WRITE to `.tres` but DO NOT RESTORE on load. **Re-apply at runtime** (see `World3DBootstrap._inject_atlas_materials_into_library`). The `.tres` is a build artifact; the bootstrap is source of truth.

SIDE enum: `NEG_X=0, POS_X=1, NEG_Y=2, POS_Y=3, NEG_Z=4, POS_Z=5`.

**`VoxelLodTerrain.material` overrides every per-cube `material_override_0`** — leave it null when using textured cube models. Per-cube `material_override_0` (set by `World3DBootstrap`) drives rendering.

**Probe a gdextension class before guessing its API:** write a probe EditorScript that prints `get_property_list()` AND `get_method_list()`. Property lists alone mislead — Zylann's `VoxelBlockyModelCube` exposes `tile_top` as a listed property but storage routes through `set_tile()`. See `tools/probe_zylann_blocky.gd`.

---

## Profiler attribution + diagnostics

**Per-autoload perf attribution via `Profiler.record` + `HUDOverlay.profile_record`:**

```gdscript
func _process(delta: float) -> void:
    var _t0 := Time.get_ticks_usec()
    _process_inner(delta)
    var _elapsed: int = Time.get_ticks_usec() - _t0
    HUDOverlay.profile_record("AutoloadName", _elapsed)
    var prof := get_node_or_null("/root/Profiler")
    if prof != null:
        prof.record("CATEGORY", "AutoloadName", _elapsed)

func _process_inner(delta: float) -> void:
    # original body
    ...
```

Categories: `WORLD`, `WATER`, `WEATHER`, `PHYS`, `COMBAT`, `OTHER`. Wrappers add ~1 µs. `Performance.TIME_PROCESS` correlates with `worst_ms` but doesn't attribute by script.

**Profiler overlay (F3):** `Tab` cycle pages, `P` pause, `C` capture JSON (auto-wipes prior; one file at most in `user://`), `S` save, `Q` clear, `← →` timeline cursor. Keyboard-only because `Button.pressed` doesn't fire.

**Water diagnostics (`WaterDiag` autoload — F4/F5/F6):** standing tool for water polish — read it before hand-bisecting water with shader tweaks.

- **F4** toggles the on-screen Water panel; while visible it also prints a consolidated `[WaterDiag]` line once/sec. Reports `in_water/submerged`, level, queried surface-Y + Δ to player, sea/horizon Y, flow-sim on/off, shader `debug_mode`, query µs, expected LOD.
- **F5** one-shot `[WaterInspect]` dump: 3×3 mesh-block-spaced columns under the camera with water-top voxelY, water count, and **Y-delta vs centre** — equal `top=` across neighbours = coplanar; differing `top=` at the block step = the distant dark-grid LOD-seam mismatch (root-caused 2026-05-17).
- **F6** cycles the water `water.gdshader` `debug_mode` live: **0** normal · **1** depth_t (white=deep) · **2** fresnel · **3** thickness (opaque grey, no blend) · **4** surface-facing (white=up-facing top, black=vertical side/riser). These four are permanent diagnostics — do not remove them. Full recipes in `design/PROFILER_AND_DIAGNOSTICS.md`.

**Profiler capture path:** `C:\Users\Matt Noles\AppData\Roaming\Godot\app_userdata\Game One\profile_capture_<msec>.json`. JSON includes per-frame `attribution`, `engine` (proc_us/real_us/draws/prims/vram_mb), `zylann` (detect_us/io_us/mesh_us/blocked_lods/dropped_loads/dropped_meshs). Capture-from-frame-1 via `scripts/Profiler.gd` `capture_on_startup: true` + `startup_capture_seconds` — **flip back to false after**.

**Diagnostic workflow:** when a capture JSON path + `[PERF]` / `[DIAG]` log lines are pasted, that's a complete packet. Use the recipes in `design/PROFILER_AND_DIAGNOSTICS.md` to correlate JSON spikes with `[PERF] worst=` and `[DIAG] time_detect_required_blocks=`, then propose ONE specific change.
