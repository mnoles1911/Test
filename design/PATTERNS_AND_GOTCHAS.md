# Patterns and Gotchas

Hard-won rules. Violating any of these breaks things in non-obvious ways. Each one is here because we paid for it with a debugging session.

---

## Non-negotiable GDScript patterns

### Player input → `_can_take_input()` (MP-2)

```gdscript
var input_dir: Vector2 = Vector2.ZERO
if _can_take_input():
    input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
```

True in OFFLINE or when local peer owns this body. Raw `Input.*` lets remote replicas eat the local keyboard. Every `Input.*` site in Player3D / EditToolHandler / ThrowableHandler must guard.

### Voxel edits → `VoxelEditManager`, never raw `VoxelTool`

```gdscript
VoxelEditManager.queue_edit_sphere(world_pos, radius, voxel_value)  # false if NoEditZone rejected
```

Raw `VoxelTool` bypasses NoEditZone, async budget, EditedChunkRegistry, gravity, `edit_applied`, MP-3 RPC routing. MP routing is at the bottom of `VoxelEditManager.gd`; OFFLINE short-circuits.

### Skill XP → `SkillManager`

```gdscript
SkillManager.add_xp("mining", 5.0)
SkillManager.dispatch("on_voxel_broken", {"skill": "mining", "tool_id": "iron_pickaxe"})
```

Direct `GameState._skill_levels[...] = N` bypasses level-up, perks, signals. Skills: `sword throwables bow mining felling excavation demolition lockpicking alchemy smithing vitality speech`.

### UI: manual `_input` dispatch only

`Button.pressed` and `HSlider.value_changed` **do NOT fire** in this project — Dialogic consumes `InputEventMouseButton` globally. Reference: `PauseMenu._input / _dispatch_click / _hits`. Implement manual dispatch from commit 1 of any new UI. See `design/LESSONS_LEARNED.md` 2026-05-03 / 09.

### Voxel material lookup via the registry

```gdscript
var mat_id := VoxelMaterialRegistry.material_id_from_packed(packed_voxel)
var mat := VoxelMaterialRegistry.get_by_id(mat_id)
# write: VoxelMaterialRegistry.pack_voxel(mat_id, color)
```

Never decode alpha by hand (`packed & 0xFF`).

### Voxel scale comes from `scripts/VoxelScale.gd` — never hardcode

```gdscript
const VoxelScale := preload("res://scripts/VoxelScale.gd")  # NO class_name (headless-safe)
VoxelScale.VOXELS_PER_METER   # 10.0 — voxels that fit in one world metre (was 6.0 pre-2026-06-12)
VoxelScale.VOXEL_SIZE_M       # 1.0 / VOXELS_PER_METER — VoxelLodTerrain transform scale
```

**Never write** the scale as a literal (`10.0`, `0.1`, the old `6.0` / `0.166667`) anywhere near voxel math. The VoxelLodTerrain in `World3D.tscn` must have `transform.scale = Vector3.ONE * VoxelScale.VOXEL_SIZE_M` — `World3DBootstrap` asserts this at boot and corrects + logs it via `push_error` if the .tscn value drifts. Local constants that mirror VoxelScale are fine (keep the local name, update the value to read from VoxelScale). Pattern: `const VOXELS_PER_METER: float = VoxelScale.VOXELS_PER_METER`. The `scale` headless selector verifies the contract every run.

### Water is native Zylann fluid

```gdscript
const WaterMaterial := preload("res://scripts/WaterMaterial.gd")  # NO class_name (headless-safe)
WaterMaterial.is_water_type(t)                  # replaces every `== 5`
WaterMaterial.render_id_for_level(level, dir)   # sim level → CHANNEL_TYPE id
```

8 fluid models, levels 1..8 → ids 16..23 (full=23). Injected at runtime in `World3DBootstrap.add_model()` — `.tres` doesn't restore on load; **bootstrap is source of truth**. Legacy id 5 retained for pre-pivot saves. `WaterByteCodec`/`DATA5` is sim truth; `CHANNEL_TYPE` is render projection. Player queries: `WaterFlowManager.is_position_in_water / get_water_level_at`.

### Micro-voxel flora + surface detail — `FloraMaterial`, never a raw `== 24`

```gdscript
const FloraMaterial := preload("res://scripts/FloraMaterial.gd")  # NO class_name (headless-safe)
FloraMaterial.is_flora(t)           # VEGETATION: grass_blade=24, flower_red=25, flower_blue=26
FloraMaterial.is_surface_detail(t)  # SURFACE DETAIL: pebble=27, twig=28 (D1)
FloraMaterial.is_passthrough(t)     # EITHER (24..28) — use this at physics/sim exclusion sites
```

R4 grass + flowers are REAL destructible CHANNEL_TYPE voxels (ids 24..26): ground-cover grass (24) is a **solid full-cube** model (flat `GRASS_COVER_GREEN`; the C++ generator stacks 3 cubes ground+1..+3 → a 1×3-voxel green column — 2026-06-12 designer simplification), flowers (25/26) are cross-quad `VoxelBlockyModelMesh`; the D1 micro-detail pass adds pebbles + twigs (low-profile walk-through models, ids 27..28). All five are injected at runtime in `World3DBootstrap` right after the water fluids — **bootstrap is source of truth** (`.tres` doesn't restore the models). They are **pass-through air for the physics/sim**: every place that already skips water (gravity flood-fill in `VoxelGravityManager` + `GravityReference` + `voxel_gravity_cpp.cpp`, the sever BFS in `SeverFollowLib`, the finite-water solid callback `WaterFlowManager._finite_is_solid`) must skip decoration via **`is_passthrough()`** — NOT `is_flora()` (which is the vegetation-only subset, for call sites like trample that genuinely mean grass). Never raw-compare a decoration id — the id sets grow in `FloraMaterial.gd` only. The C++ gravity/sever ports + `GravityReference.gd` hardcode the **identical contiguous 24..28 range** by value so parity holds (the `gravity` + `sever` + `flora` selectors enforce it; keep flora 24..26 and surface detail 27..28 contiguous so the one pass-through range covers both). Generator scatter ids are plumbed through settable properties (`grass_blade_material_id` / `pebble_material_id` etc., default 0 = disabled, different seeds) and wired at startup by the bootstrap — all decoration is LOD0-only.

### `VoxelBuffer CHANNEL_COLOR` must be 32-bit before chunks stream

```gdscript
if "format" in terrain:
    var fmt := VoxelFormat.new()
    fmt.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
    terrain.format = fmt
```

8-bit truncates packed RGBA+mat_id to just R (near-black terrain). **NEVER call `set_channel_depth()` inside `_generate_block`** — invalidates buffer storage.

### `_generate_block` runs on a worker thread

No SceneTree access. Cache plain-data snapshot on main thread, push into generator, read locally inside `_generate_block`. See `NoEditZoneRegistry.get_water_blocking_aabbs_snapshot()`.

### `Dictionary[int, PackedByteArray]` → read-modify-write

```gdscript
var bmp: PackedByteArray = my_dict.get(key, PackedByteArray())
bmp[index] = value
my_dict[key] = bmp
```

Godot 4 indexing returns a copy.

### Zylann `VoxelLodTerrain` properties: read-back after `.set()`

```gdscript
terrain.set("collision_update_delay", 100)  # int ms; 0.1 truncates to 0 → per-frame rebuild
print("actual=%s" % terrain.get("collision_update_delay"))
```

Properties also silently clamp (`mesh_block_size=32` was clamped to 16 in some scenes). Bootstraps print readbacks as policy.

### Zylann blocky-library: methods, NOT `.set()`

```gdscript
model.call("set_tile", 3, Vector2i(2, 0))            # 3 = SIDE_POSITIVE_Y
model.call("set_material_override", 0, atlas_mat)
```

`.set("tile_top", ...)` silently no-ops (Zylann routes through method pairs; `.set` writes a virtual bag only used for serialization → all-white terrain). Values WRITE to `.tres` but DO NOT RESTORE on load — re-apply at runtime in `World3DBootstrap._inject_atlas_materials_into_library`. SIDE enum: NEG_X=0, POS_X=1, NEG_Y=2, POS_Y=3, NEG_Z=4, POS_Z=5.

### Per-autoload perf attribution

```gdscript
func _process(delta: float) -> void:
    var _t0 := Time.get_ticks_usec()
    _process_inner(delta)
    var _us := Time.get_ticks_usec() - _t0
    HUDOverlay.profile_record("AutoloadName", _us)
    var prof := get_node_or_null("/root/Profiler")
    if prof != null: prof.record("CATEGORY", "AutoloadName", _us)
```

Categories: `WORLD WATER WEATHER PHYS OTHER`.

### Terrain collision extends to ~51.2 m (10 vox/m, LOD0+LOD1+LOD2)

`collision_lod_count = 3` gives collision on the first three LOD rings (2026-06-12 designer decision):

| LOD | Range | Collision | Mesh resolution |
|---|---|---|---|
| LOD0 | 0 – 12.8 m | yes | full detail (1-voxel blocks) |
| LOD1 | 12.8 – 25.6 m | yes | coarser (2-voxel blocks) |
| LOD2 | 25.6 – 51.2 m | yes | coarser (4-voxel blocks) |
| LOD3+ | 51.2 m+ | **no** | mesh-only |

**Zylann semantics (probed + docs-confirmed 2026-06-12):** `collision_lod_count = 0` means *all* LODs get collision (NOT "LOD0-only" — the old comments were wrong). `collision_lod_count = N` (N > 0) = first N LOD levels. Value 3 = LOD0, LOD1, LOD2.

**Accuracy caveat:** beyond ~12.8 m collision shapes are built from coarser LOD meshes — far entities stand on approximate ground (stairs round to 2–4 voxel steps; small overhangs may be invisible to physics). Acceptable for AI/spear/falling-cluster collision; the player always stands in LOD0.

**Perf caveat:** more LODs = more StaticBody3D shapes to build while streaming. `collision_update_delay = 100 ms` batches the builds. If physics spikes return, the retreat is `collision_lod_count = 1` (LOD0-only, 12.8 m). Set in `World3DBootstrap.gd`.

**Nothing beyond ~51.2 m:** projectiles/AI past that ring still have no terrain collision. A `VoxelViewer` or raycast-vs-generator fallback for long-lived projectiles is a **logged follow-up — do NOT build it** as part of unrelated work.

### Other essentials

- `VoxelLodTerrain.material` overrides every per-cube `material_override_0` — leave null for textured cubes.
- `OmniLight3D.light_energy` (NOT `.energy` — that's PointLight2D).
- Capsule CollisionShape3D offset upward by half-height (Y=+0.85 for 1.7m).
- 2D→3D XZ: `Vector3(input.x, 0, input.y)`. Never `input.y → velocity.y`.
- Camera-relative: `(transform.basis * Vector3(input.x, 0, input.y)).normalized()`.
- Frame-rate-independent decel: `velocity = velocity.move_toward(Vector3.ZERO, DECEL * delta)`.
- Dialogic check: `if get_node_or_null("/root/Dialogic"): Dialogic.start(...)`.
- One-shot signal: `sig.connect(fn, CONNECT_ONE_SHOT)`.
- **Probe gdextension API before guessing** — `get_property_list()` AND `get_method_list()`. Property lists alone mislead.
- **Static funcs** can't use bare `new()` — `load(path).new()`.
- **`Time.get_unix_time_from_system()` returns float** — `int(...) % N` for modulo.
- **No `class_name` on Resources path-preloaded by autoloads** (`WaterMaterial.gd`, `ShaderProfile.gd`, `EntityRecord.gd`) — headless harness doesn't rescan globals; autoload fails with "script does not inherit from Node" otherwise.
- **GDSL: no `return` inside `fragment()`** — restructure as if/else.
- **GDSL function-scope arrays:** use constructor `vec3[6](...)` or open-code, not C-style `vec3 arr[6] = {...}`.
- **Flora sway shader — use `fract(VERTEX.y)` for blade-local height, NOT `VERTEX.y`:** Zylann bakes blocky flora models into chunk meshes at each voxel's world altitude, so `VERTEX.y` in the sway shader is the voxel's absolute world Y (which may be large), not the blade's local height. Using raw `VERTEX.y` as the sway bend weight flings blades metres sideways. Correct: `float blade_t = fract(VERTEX.y)` gives a 0..1 value local to each voxel's 1-unit block (0 = base, ~1 = tip). This applies to both the real LOD0 flora quads AND the far-grass `MultiMesh` impostors that share `assets/shaders/flora_sway.gdshader`. (Fixed in PR #251 — do NOT revert to absolute `VERTEX.y`.).
- **`func` is a module-scope boundary** — when inserting helper functions mid-file via Edit, place AFTER the parent function's last line (not between its branches), or following code becomes orphaned inside the new function's body.

### `RenderingServer` global shader parameters — editor-only setters

**NEVER call `RenderingServer.global_shader_parameter_add` / `_get` / `_get_list`** — these are editor-only APIs and will error in shipped builds. Declare globals in `project.godot [shader_globals]`; runtime code only ever calls `_set`.

---

## Critical scene hierarchies (load-bearing — scripts use hardcoded `$NodeName`)

### Player3D / CameraRig

```
Player3D (CharacterBody3D)
└── CameraTarget (Node3D)
    └── SpringArm3D (CameraRig.gd)
        └── Camera3D
```

CameraRig walks `get_parent().get_parent()` to reach body — don't add wrappers. Two modes: **Standard** (mouse rotates body; W → camera) and **Freelook** (hold F2 — orbits arm, re-centers on release).

### NPC

```
NPCNode (CharacterBody3D + NPC.gd)
├── MeshInstance3D + CollisionShape3D
├── BarkArea (Area3D)          ← name MUST be "BarkArea"
└── InteractArea (Area3D)      ← name MUST be "InteractArea"
```

Assign `NPCData` resource in Inspector. Tier 0 NPCs = plain Node3D, no script.

### World3D.tscn terrain

```
World3D
├── VoxelLodTerrain
│   ├── generator: CubicHeightmapGeneratorAdapter → cpp_impl: CubicHeightmapGeneratorCpp
│   ├── stream: VoxelStreamSQLite
│   └── mesher: VoxelMesherBlocky
├── VoxelViewer (child of Player3D)
└── EntityStreamer
```

### NoEditZone

`NoEditZone` Area3D in group `no_edit_zone` with ~50–100m buffer `CollisionShape3D`, under any settlement / dungeon / landmark root. Writes inside silently rejected → Roland barks *"This place doesn't yield to me."*

---

## Autoload load order

Registered in `project.godot`, in order:

`GameState`, `Colors`, `TransitionManager`, `SaveNotification`, `PauseMenu`, `NetTransport`, `MultiplayerManager`, `GraphicsManager`, `Settings`, `DebugOverlay`, `FlagScheduler`, `InventoryManager`, `PerkRegistry`, `FactionManager`, `VoxelMaterialRegistry`, `SkillManager`, `JournalUI`, `HUDOverlay`, `Profiler`, `ProfilerOverlay`, `AudioManager`, `NoEditZoneRegistry`, `VoxelEditManager`, `VoxelGravityManager`, `EmissiveLightManager`, `EmissiveBakedLightManager`, `WaterFlowManager`, `Dialogic`, `SpeechCheckBroker`, `BarkManager`, `WorldClock`, `WeatherManager`, `BloodVFX`, `WaterDiag`, `EntityRegistry`.

### Load-order rules (violations break things)

- `NetTransport` < `MultiplayerManager` < gameplay autoloads reading MM in `_ready` (today: `WaterFlowManager`).
- `Colors` < any UI autoload.
- `InventoryManager` < `VoxelMaterialRegistry` (validates `yield_item_id`).
- `VoxelMaterialRegistry` + `NoEditZoneRegistry` < `VoxelEditManager`.
- `VoxelEditManager` < `VoxelGravityManager` / `EmissiveLightManager` / `WaterFlowManager` (they subscribe to `edit_applied`).
- `EmissiveLightManager` < `EmissiveBakedLightManager` (baked disables v1 in `_ready`).
- `WorldClock` < `WeatherManager` (subscribes to `hour_changed`).
- `WaterFlowManager` < `WeatherManager` (pushes wind).

### Key behaviours

- `MultiplayerManager`: in OFFLINE mode `is_host() == true` (single-player gates work unmodified). `VoxelEditManager` + `WaterFlowManager` MP-aware (host validates + broadcasts at 60 req/s/peer; non-host early-returns).
- `SkillManager`: single XP entry point + perk events. `PerkRegistry` loads 300 perks. `FactionManager.is_friendly()` = `≥75` gate. `SpeechCheckBroker` = KCD2-style Speech modal.
- `Colors` (`assets/ui/Colors.gd`) = Voxelmark palette. `UIStyles` (`assets/ui/UIStyles.gd`, RefCounted, not autoloaded) builds StyleBox/FontVariation. CSS at `assets/ui/css/menus_shared.css`.
- `JournalUI` autoload → scene `res://scenes/ui/Journal.tscn`.
- `AudioManager`: `play(id, world_pos)` / `play_loop(id)→handle` / `stop_loop(handle)`. Resolves `assets/audio/sfx/<folder>/<id>[.ogg|_NN.ogg]`. No-ops with one warning until file present — safe to wire call sites before assets land.
- `GraphicsManager`: 5-tier presets (HIGH = `World3D.tscn` baseline). Persists `user://graphics.json`. Per-effect toggles for outline / lens flare / rainbow / light shafts / rain visuals (rain + light_shafts default OFF per 2026-05-27 designer playtest).
- `EmissiveBakedLightManager`: reads globals from `[shader_globals]` (`baked_light_tex / _origin_world / _inv_volume_m / _strength`).

**Not yet registered:** `SchematicLibrary`. Unregistered-autoload refs MUST guard with `get_node_or_null`.

### Dev scenes opt out of gameplay UI

```gdscript
add_to_group("dev_scene")  # in scene's bootstrap _ready()
```

HUDOverlay / PauseMenu / JournalUI / SaveNotification check `GameState.is_dev_scene()` and stay dormant.

---

## Diagnostic hotkeys

- **F3** Profiler overlay: Tab cycle, P pause, C capture JSON, S save, Q clear, ←/→ timeline. Keyboard-only (`Button.pressed` doesn't fire).
- **F4/F5/F6** WaterDiag: F4 panel + 1Hz `[WaterDiag]` line · F5 `[WaterInspect]` 3×3 dump · F6 cycles `water.gdshader debug_mode` (0 normal · 1 depth · 2 fresnel · 3 thickness · 4 surface-facing).
- **F11** terrain LOD-band debug shader; **F12** Zylann viewer cubes + clipbox overlay.
- **Capture JSON path:** `%APPDATA%\Godot\app_userdata\Game One\profile_capture_<msec>.json`. Capture-from-frame-1 via `Profiler.gd capture_on_startup: true` → flip back after.

Full recipes: `design/PROFILER_AND_DIAGNOSTICS.md`.

---

## C++ GDExtension perf

`extensions/voxel_gen/` — used **proactively** for CPU work iterating thousands+/frame. Build: `python -m SCons platform=windows target=template_debug use_mingw=yes -j8` from `extensions/voxel_gen/` (close Godot first). Reload Godot after.

### Port pattern

godot-cpp can't subclass Zylann → C++ extends `godot::Resource` + thin GDScript adapter extends `VoxelGeneratorScript` and forwards via Variant call.

Profiler measurement: `engine.real_us` (PR#207), not `proc_us`.

### Done

`CubicHeightmapGeneratorCpp`, `CopperIslesHeightmapGeneratorCpp`, `HeightmapGeneratorBase`, `VoxelGravityCpp`, `EmissiveLightCpp` v1, `EmissiveBakedCpp` (Phase J — supersedes v1), `WaterFlowCpp`. All have GD fallback when DLL missing.

### Reusable patterns (PR #241)

1. Bulk-read Zylann channels via `get_channel_as_byte_array` (one Variant call). Per-voxel `Variant::call` from C++ is slower than GDScript-native.
2. Byte layout is **Y-fastest**: `byte_index = (y + x*sy + z*sx*sy) * bytes_per_voxel`.
3. Return per-voxel results as `PackedInt32Array` streams (not `Dictionary[Vector3i, int]`).
4. Cross-language sort: pick a total ordering — never rely on unstable sorts agreeing across languages.

### Next targets

- WaterFlowManager `_flow_chunk` + `_process_connectivity_fill` (only if a capture spikes).
- Zylann `ShaderMaterialPool::recycle` assertion on F11 LOD-debug path (correctness, not perf).

### NOT worth porting

Zylann internals (mesher, streaming, LOD octree), VEM queue, LOD-bake-on-eviction.

### Port process

Parity harness FIRST (`@tool` EditorScript in `scripts/_dev/`, bit-exact), POD snapshot for Resource data, sub-phases each ending green. Full receipt: `memory/project_voxel_gen_cpp_port.md`.

---

## Workflow

**No CLI build/lint/test** for the Godot side — open in Godot 4.6.2, run a scene, check Output. Key scenes:

- `World3D.tscn` — Mira
- `CopperIslesTest.tscn` — F7 cycles terrain scale
- `scenes/_dev/CombatTest.tscn` — combat dev arena, spear pre-equipped
- `scenes/_dev/BakeWorld{3D,}.tscn` — UI bake, must run in-game

### Headless harness

`tools/headless/run.ps1 <selector>` runs Godot's `_console.exe` (plain win64 exe = GUI-subsystem, won't pipe stdout) with `tools/headless/runner.gd` as a SceneTree script. Selectors:

`gate0 codec wmat shader phase7 spike phase2 gen distant gravity emissive baked_light water_flow finite finite_world sever entity scale flora mining`

Exit 0 = pass. **Scope: data/logic/parity only** — dummy renderer, no GPU. Visuals need designer in editor.

### Git

- One fix per branch.
- One file per commit for large `.tscn` / `.gd` (avoids stream timeouts).
- Cherry-pick over rebase when a branch has conflicting squash-merged history.
- Never amend published commits — fix-then-new-commit if a hook fails.
- Push with `git push -u origin <branch>`.
