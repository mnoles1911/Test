# CLAUDE.md

Guidance for Claude Code in this repo. **Read `git log` for milestone detail; this file is for rules + load-bearing facts only.**

# Game One

3D voxel narrative RPG (Veloren + Skyrim atmosphere). Godot 4.6.2, Zylann Voxel Tools, Forward+ on desktop. Real-time action combat, 1-vs-many, co-op for 1-4. **GDScript default; C++ GDExtension proactively for perf** (don't gate behind profiler measurement). Game one of a planned trilogy from a 200-page source manuscript. Migration plan: `design/3D_VOXEL_MIGRATION.md`.

I am a writer + game designer, not a programmer — explain code in plain English, comment heavily. World is Mira-Thal (LOTR-scale fantasy); `lore/INDEX.md` is the canon directory.

**Folders:** `/scenes /scripts /addons/dialogic /assets /dialogue /lore /design /tools /extensions/voxel_gen /memory`.

## Milestone history (one-liners; details in `git log`)

- **04-30 PR#43:** 2D → 3D voxel pivot.
- **05-03 to 12:** destructible voxel slice; Copper Isles demo; Combat v1 (Goblin/Spear/BloodVFX); Skills (PR#201); MP (PR#180); cubic generator C++.
- **05-13 to 16:** HeightmapGeneratorBase (#203); Profiler.real_us (#207); WaterChunkMesher C++ (#214, later deleted).
- **05-18 native-fluid pivot:** water = `VoxelBlockyModelFluid` ids 16–23, 8 levels, mesher auto-slopes. Legacy id 5 kept for old saves. Plan: `design/WATER_STAGE6_PLAN.md`.
- **05-19/20:** UnderwaterFilter (instant-snap submerge, vol fog, god rays); AgX tonemap + SSAO/SSIL/PSSM/MSAA. **Never flip `bake_tangents`** (breaks water meshes).
- **05-21/22:** AudioManager + 548 SFX takes; GraphicsManager 5 tiers; procedural sky/clouds/stars (`sky_atmosphere.gdshader`); `AtmosphereProfile`; tangent-free `terrain_voxel.gdshader`.
- **05-22/26 PR#240:** DistantTerrain streaming heightmesh replaces baked HorizonSkirt. LOD outrun fixed (PrefetchViewer deleted, `VIEWER_LOOKAHEAD_MAX_OFFSET_M=0`). F11/F12 debug.
- **05-27 PR#241:** Four C++ ports — `VoxelGravityCpp` (131→2.8 ms, 46× win), `EmissiveLightCpp` v1, `EmissiveBakedCpp` (Phase J), `WaterFlowCpp`. All parity-gated. Y-fastest byte layout.
- **05-27 PR#243:** LOD1+ water surface line FIX (horizon plane + UnderwaterFilter group-toggle + WaterDiag backtick / Shift+backtick / debug_mode 7-8).
- **05-27 PR#244:** Phase K bundle — selection outline, cloud-phase accumulator, DebugOverlay GRAPHICS sub-view, lens flare, rainbow (all gated).
- **05-27 PR#245 Weather rework:** designer playtest deferred all visuals — rain shader / wet terrain / splashes / god rays gated OFF by default; audio envelope crossfade stays live. Multi-session iteration needed. `design/WEATHER_REWORK_2026-05.md`.
- **05-27 PR#246 EntityStreamer:** `EntityRegistry` (per-chunk + JSON save/load) + 4-tier AI sleep (ACTIVE/AWAKE/SLEEPING/OFFLOADED). Goblin/NPC/VoxelDrop retrofitted. Headless `entity` gate 66 checks. `design/ENTITY_STREAMING.md`.
- **05-28 PR#247 Combat Phase 5:** charged-spear (hold LMB ≥50 dmg) → gib explosion (12 GibChunks, radial impulse) + 0.15 s time-slow + camera kick + spear reparents to chunk. ThrowableHandler charge mechanic added (Phase 3 finish). Overkill threshold = 50 (re-raise once charged dmg passes 80 via perks).

**Outstanding pickups** (see `DESIGNER_TODO.md`): Blender Roland model, MagicaVoxel props, surface decoration, region-boundary profile auto-swap, 5 PHOTO-flagged voxel textures, Zylann `ShaderMaterialPool::recycle` assertion on F11 toggle path, water leveling sim variant choice.

## Art spec
6 voxels/m (~16.7 cm/block). `VoxelLodTerrain` + `VoxelMesherBlocky` reading `CHANNEL_TYPE` (8-bit material id) via `VoxelBlockyLibrary`. Atlas 16 px × 64 cols (1024²). **Destructible by default**; `NoEditZone` Area3Ds are the exception. Edits → `VoxelStreamSQLite`. Mira 12×10 km; Thal 7×5.5 km. Props MagicaVoxel→.glb. Characters Blender low-poly .glb (200–500 tris). Canonical: `design/3D_VOXEL_MIGRATION.md`, `ART_PIPELINE.md`, `ART_DIRECTION.md`.

## What I never want
- Systems built before I need them.
- C# — never. GDScript by default; C++ GDExtension proactively for perf.

## Maintenance: when in doubt, also update
- `lore/INDEX.md` + relevant lore on any narrative change.
- The relevant `design/*.md` on any system change (1:1 doc per system).
- `DESIGNER_TODO.md` for new editor/asset work.
- `CLAUDE.md` only for: milestone completes; canonical contradictions; new load-bearing rule.

## Lore + design refs
Canon in `/lore`, start `INDEX.md`. **Lore wins when lore vs design conflict.** Implementation in `/design` (one .md per system: COMBAT_DESIGN_3D, ENEMY_AI, SKILLS_AND_PROGRESSION, INVENTORY_AND_EQUIPMENT_SYSTEM, ITEM_LIBRARY, CRAFTING, MINING_TIME_SCALING, WEATHER_AND_ENVIRONMENT, SAVE_SYSTEM, SWIMMING_AND_WATER, MULTIPLAYER, HUD_AND_UI, INPUT_AND_CONTROLS, FACTION_SYSTEM, QUEST_SYSTEM, NPC_SYSTEM, COMPANION_SYSTEM, AUDIO_DESIGN, ENTITY_STREAMING, …). **`design/PROFILER_AND_DIAGNOSTICS.md` — read before guessing at perf.**

## Current state
Godot 4.6.2. 3D voxel open world: VoxelLodTerrain streaming, edits by default, NoEditZones protect settlements, 12×10 km Mira. **3D core scripts:** `Player3D`, `CameraRig`, `HUDOverlay`, `JournalUI`, `World3DBootstrap` (**all world-load wiring goes here**), `VoxelDrop`, `DistantTerrainManager`. **Combat v1:** `Enemy3D` base + `enemies/Goblin.gd` + `ThrowableSpear` + `BloodVFX` autoload + `GibChunk` (Phase 5). See `design/COMBAT_NEXT_PHASES.md` for what's next.

**2D legacy still on disk (retiring):** `Player.gd`, `World.tscn`, `Combat.tscn`, etc.

**Not yet implemented:** Combat next phases (Mixamo rigs, melee foundation, group AI, Ashfallen), `SchematicLibrary` (player construction), `QuestManager`, `CompanionManager`, LOD-bake-on-eviction.

**Manual setup:** `DESIGNER_TODO.md` Section 1.

---

## C++ GDExtension perf

`extensions/voxel_gen/` — used **proactively** for CPU work iterating thousands+/frame. Build: `python -m SCons platform=windows target=template_debug use_mingw=yes -j8` from `extensions/voxel_gen/` (close Godot first). Reload Godot after.

**Port pattern:** godot-cpp can't subclass Zylann → C++ extends `godot::Resource` + thin GDScript adapter extends `VoxelGeneratorScript` and forwards via Variant call.

**Profiler:** `engine.real_us` (PR#207), not `proc_us`.

**Done:** `CubicHeightmapGeneratorCpp`, `CopperIslesHeightmapGeneratorCpp`, `HeightmapGeneratorBase`, `VoxelGravityCpp`, `EmissiveLightCpp` v1, `EmissiveBakedCpp` (Phase J — supersedes v1), `WaterFlowCpp`. All have GD fallback when DLL missing.

**Reusable patterns (PR #241):**
1. Bulk-read Zylann channels via `get_channel_as_byte_array` (one Variant call). Per-voxel `Variant::call` from C++ is slower than GDScript-native.
2. Byte layout is **Y-fastest**: `byte_index = (y + x*sy + z*sx*sy) * bytes_per_voxel`.
3. Return per-voxel results as `PackedInt32Array` streams (not `Dictionary[Vector3i, int]`).
4. Cross-language sort: pick a total ordering — never rely on unstable sorts agreeing across languages.

**Next targets:** WaterFlowManager `_flow_chunk` + `_process_connectivity_fill` (only if a capture spikes); Zylann `ShaderMaterialPool::recycle` assertion on F11 (correctness, not perf).

**NOT worth porting:** Zylann internals (mesher, streaming, LOD octree), VEM queue, LOD-bake-on-eviction.

**Port process:** parity harness FIRST (`@tool` EditorScript in `scripts/_dev/`, bit-exact), POD snapshot for Resource data, sub-phases each ending green. Receipt: `memory/project_voxel_gen_cpp_port.md`.

---

## Workflow

**No CLI build/lint/test** for the Godot side — open in Godot 4.6.2, run a scene, check Output. Key scenes: `World3D.tscn` (Mira), `CopperIslesTest.tscn` (F7 cycles scale), `scenes/_dev/CombatTest.tscn` (combat dev arena, spear pre-equipped), `scenes/_dev/BakeWorld{3D,}.tscn`.

**Headless harness:** `tools/headless/run.ps1 <selector>` runs Godot's `_console.exe` (plain win64 exe = GUI-subsystem, won't pipe stdout) with `tools/headless/runner.gd` as a SceneTree script. Selectors: `gate0 codec wmat shader phase7 spike phase2 gen distant gravity emissive baked_light water_flow entity`. Exit 0 = pass. **Scope: data/logic/parity only** — dummy renderer, no GPU. Visuals need designer in editor.

**Git:** one fix per branch; one file per commit for large `.tscn/.gd` (avoids stream timeouts); cherry-pick over rebase when squash-merged history conflicts; never amend published commits (fix-then-new-commit if hook fails); push with `git push -u origin <branch>`.

---

## Critical GDScript patterns (non-negotiable)

### Player input → `_can_take_input()` (MP-2)
```gdscript
var input_dir: Vector2 = Vector2.ZERO
if _can_take_input():
    input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
```
True in OFFLINE or when local peer owns this body. Raw `Input.*` lets remote replicas eat the local keyboard. Every `Input.*` in Player3D / EditToolHandler / ThrowableHandler must guard.

### Voxel edits → `VoxelEditManager`, never raw `VoxelTool`
```gdscript
VoxelEditManager.queue_edit_sphere(world_pos, radius, voxel_value)  # false if NoEditZone rejected
```
Raw VoxelTool bypasses NoEditZone, async budget, EditedChunkRegistry, gravity, `edit_applied`, MP-3 RPC. MP routing at bottom of `VoxelEditManager.gd`; OFFLINE short-circuits.

### Skill XP → `SkillManager`
```gdscript
SkillManager.add_xp("mining", 5.0)
SkillManager.dispatch("on_voxel_broken", {"skill": "mining", "tool_id": "iron_pickaxe"})
```
Direct `GameState._skill_levels[...] = N` bypasses level-up, perks, signals. Skills: `sword throwables bow mining felling excavation demolition lockpicking alchemy smithing vitality speech`.

### UI: manual `_input` dispatch only
`Button.pressed` and `HSlider.value_changed` **do NOT fire** — Dialogic consumes `InputEventMouseButton` globally. Reference: `PauseMenu._input / _dispatch_click / _hits`. Implement manual dispatch from commit 1 of any new UI. See LESSONS_LEARNED 2026-05-03/09.

### Voxel material lookup via the registry
```gdscript
var mat_id := VoxelMaterialRegistry.material_id_from_packed(packed_voxel)
var mat := VoxelMaterialRegistry.get_by_id(mat_id)
# write: VoxelMaterialRegistry.pack_voxel(mat_id, color)
```
Never decode alpha by hand (`packed & 0xFF`).

### Water is native Zylann fluid
```gdscript
const WaterMaterial := preload("res://scripts/WaterMaterial.gd")  # NO class_name (headless-safe)
WaterMaterial.is_water_type(t)                  # replaces every `== 5`
WaterMaterial.render_id_for_level(level, dir)   # sim level → CHANNEL_TYPE id
```
8 fluid models, levels 1..8 → ids 16..23 (full=23). Injected at runtime in `World3DBootstrap.add_model()` — `.tres` doesn't restore on load; bootstrap is source of truth. Legacy id 5 retained for pre-pivot saves. **`WaterByteCodec`/`DATA5` is sim truth; `CHANNEL_TYPE` is render projection.** Player queries: `WaterFlowManager.is_position_in_water / get_water_level_at`.

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

### Diagnostic hotkeys
- **F3** Profiler: Tab cycle, P pause, C capture JSON, S save, Q clear, ←/→ timeline. (Keyboard-only — `Button.pressed` doesn't fire.)
- **F4/F5/F6** WaterDiag: panel + 1Hz `[WaterDiag]` line / `[WaterInspect]` 3×3 dump / cycle `water.gdshader debug_mode` (0 normal · 1 depth · 2 fresnel · 3 thickness · 4 surface-facing). Recipes in `design/PROFILER_AND_DIAGNOSTICS.md`.
- **Capture JSON:** `%APPDATA%\Godot\app_userdata\Game One\profile_capture_<msec>.json`. Capture-from-frame-1 via `Profiler.gd capture_on_startup: true` → flip back after.

### Zylann blocky-library: methods, NOT `.set()`
```gdscript
model.call("set_tile", 3, Vector2i(2, 0))            # 3 = SIDE_POSITIVE_Y
model.call("set_material_override", 0, atlas_mat)
```
`.set("tile_top", ...)` silently no-ops (Zylann routes through method pairs; `.set` writes a virtual bag only used for serialization → all-white terrain). Values WRITE to `.tres` but DO NOT RESTORE on load — re-apply at runtime in `World3DBootstrap._inject_atlas_materials_into_library`. SIDE: NEG_X=0, POS_X=1, NEG_Y=2, POS_Y=3, NEG_Z=4, POS_Z=5.

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
- **GDSL: no `return` inside `fragment()`**; restructure as if/else.
- **GDSL function-scope arrays:** use constructor `vec3[6](...)` or open-code, not C-style `vec3 arr[6] = {...}`.
- **`func` is a module-scope boundary** — when inserting helper functions mid-file via Edit, place AFTER the parent function's last line (not between its branches), or following code becomes orphaned inside the new function's body.

---

## Critical scene hierarchies

Load-bearing — scripts use hardcoded `$NodeName`.

**Player3D / CameraRig:**
```
Player3D (CharacterBody3D)
└── CameraTarget (Node3D)
    └── SpringArm3D (CameraRig.gd)
        └── Camera3D
```
CameraRig walks `get_parent().get_parent()` to reach body — don't add wrappers. Two modes: **Standard** (mouse rotates body; W → camera) and **Freelook** (hold F2 — orbits arm, re-centers on release).

**NPC:**
```
NPCNode (CharacterBody3D + NPC.gd)
├── MeshInstance3D + CollisionShape3D
├── BarkArea (Area3D)          ← name MUST be "BarkArea"
└── InteractArea (Area3D)      ← name MUST be "InteractArea"
```
Assign `NPCData` resource in Inspector. Tier 0 NPCs = plain Node3D, no script.

**World3D.tscn terrain:**
```
World3D
├── VoxelLodTerrain
│   ├── generator: CubicHeightmapGeneratorAdapter → cpp_impl: CubicHeightmapGeneratorCpp
│   ├── stream: VoxelStreamSQLite
│   └── mesher: VoxelMesherBlocky
├── VoxelViewer (child of Player3D)
└── EntityStreamer
```

**NoEditZone:** `NoEditZone` Area3D in group `no_edit_zone` with ~50–100m buffer CollisionShape3D, under any settlement/dungeon/landmark root. Writes inside silently rejected → Roland barks *"This place doesn't yield to me."*

---

## Autoloads

Load order in `project.godot`:
`GameState`, `Colors`, `TransitionManager`, `SaveNotification`, `PauseMenu`, `NetTransport`, `MultiplayerManager`, `GraphicsManager`, `Settings`, `DebugOverlay`, `FlagScheduler`, `InventoryManager`, `PerkRegistry`, `FactionManager`, `VoxelMaterialRegistry`, `SkillManager`, `JournalUI`, `HUDOverlay`, `Profiler`, `ProfilerOverlay`, `AudioManager`, `NoEditZoneRegistry`, `VoxelEditManager`, `VoxelGravityManager`, `EmissiveLightManager`, `EmissiveBakedLightManager`, `WaterFlowManager`, `Dialogic`, `SpeechCheckBroker`, `BarkManager`, `WorldClock`, `WeatherManager`, `BloodVFX`, `WaterDiag`, `EntityRegistry`.

**Key behaviours:**
- `MultiplayerManager`: in OFFLINE mode `is_host() == true` (single-player gates work unmodified). `VoxelEditManager` + `WaterFlowManager` MP-aware (host validates + broadcasts, 60 req/s/peer; non-host early-returns).
- `SkillManager`: single XP entry point + perk events. `PerkRegistry` loads 300 perks. `FactionManager.is_friendly()` = `≥75` gate. `SpeechCheckBroker` = KCD2-style Speech modal.
- `Colors` (`assets/ui/Colors.gd`) = Voxelmark palette. `UIStyles` (`assets/ui/UIStyles.gd`, RefCounted, not autoloaded) builds StyleBox/FontVariation. CSS at `assets/ui/css/menus_shared.css`.
- `JournalUI` autoload → scene `res://scenes/ui/Journal.tscn`.
- `AudioManager`: `play(id, world_pos)` / `play_loop(id)→handle` / `stop_loop(handle)`. Resolves `assets/audio/sfx/<folder>/<id>[.ogg|_NN.ogg]`. No-ops with one warning until file present — safe to wire call sites before assets land.
- `GraphicsManager`: 5-tier presets (HIGH = `World3D.tscn` baseline). Persists `user://graphics.json`. Per-effect toggles for outline/lens flare/rainbow/light shafts/rain visuals (rain + light_shafts default OFF per 2026-05-27 designer playtest).
- `EmissiveBakedLightManager`: reads globals from `project.godot [shader_globals]` (`baked_light_tex / _origin_world / _inv_volume_m / _strength`). **NEVER call `RenderingServer.global_shader_parameter_add/_get/_get_list`** — editor-only, errors in shipped builds. Declare in `[shader_globals]`; runtime only `_set`.

**Load-order rules (violations break things):**
- `NetTransport` < `MultiplayerManager` < gameplay autoloads reading MM in `_ready` (today: `WaterFlowManager`).
- `Colors` < any UI autoload.
- `InventoryManager` < `VoxelMaterialRegistry` (validates `yield_item_id`).
- `VoxelMaterialRegistry` + `NoEditZoneRegistry` < `VoxelEditManager`.
- `VoxelEditManager` < `VoxelGravityManager` / `EmissiveLightManager` / `WaterFlowManager` (they subscribe to `edit_applied`).
- `EmissiveLightManager` < `EmissiveBakedLightManager` (baked disables v1 in `_ready`).
- `WorldClock` < `WeatherManager` (subscribes to `hour_changed`).
- `WaterFlowManager` < `WeatherManager` (pushes wind).

**Not yet registered:** `SchematicLibrary`. Unregistered-autoload refs MUST guard with `get_node_or_null`.

**Dev scenes opt out of gameplay UI:**
```gdscript
add_to_group("dev_scene")  # in scene's bootstrap _ready()
```
HUDOverlay / PauseMenu / JournalUI / SaveNotification check `GameState.is_dev_scene()` and stay dormant.
