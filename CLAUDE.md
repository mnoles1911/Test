# CLAUDE.md

Guidance for Claude Code when working in this repository.

# Game One — Project Bible

## What I'm building
A 3D voxel narrative RPG — Veloren meets Skyrim in atmosphere and open-world scale. Real-time action combat (Witcher 3 / Dark Souls style), 1-vs-many, first + third-person cameras, co-op multiplayer for 1-4 friends. Voxel world in Godot 4.6.2 with Zylann's Voxel Tools. **Renderer: Forward+ on desktop**; `rendering_method.mobile` stays Compatibility. GDScript is the default for UI / glue / signals / one-shot setup; **C++ GDExtension is the perf escape hatch and is used proactively wherever it would meaningfully improve performance — don't wait for a profiler to mandate it.** Game one of a planned trilogy adapted from a 200-page source manuscript.

**Engine:** 3D voxel since 2026-04-30 (pivoted from 2D pixel art). Migration plan in `design/3D_VOXEL_MIGRATION.md`.

## My background
I am a writer and game designer, not a programmer. Explain code in plain English before writing it. Keep scripts heavily commented. Prefer simple, readable solutions.

## Genre and tone
Epic fantasy, grounded emotional stakes — LOTR scale, single-protagonist intimacy. World is Mira-Thal, third age. See `lore/WORLD.md` + `lore/INDEX.md`.

## Core systems
- Player: CharacterBody3D, 8-dir XZ movement
- World: VoxelLodTerrain (Zylann) + MagicaVoxel props
- Camera: SpringArm3D over-shoulder, ~15° elevation, lock-on
- Dialogue: Dialogic 2
- Combat: real-time action, 1-vs-many (Hades style)
- Autoloads for game state, transitions, audio (see registration list below)

## Folder structure
- `/scenes` — .tscn files
- `/scripts` — .gd files
- `/addons/dialogic` — Dialogic 2 (do not edit; manage via Asset Library)
- `/assets/{portraits,voxel,models,audio,npcs}` — content
- `/dialogue` — Dialogic timelines + `CHARACTER_VOICES.md`, `PRONUNCIATION.md`, `STYLE.md`
- `/lore` — narrative canon (start at `lore/INDEX.md`)
- `/design` — implementation reference
- `/tools` — pipeline scripts (`tools/README.md`)
- `/extensions/voxel_gen` — C++ GDExtension

## Milestone history

Read `git log` for detail. One-liners of the load-bearing milestones:

- **2026-04-30 PR #43:** 2D → 3D voxel pivot.
- **2026-05-03 to 12:** destructible voxel slice, Copper Isles demo, Combat v1, Skill system (PR #201), Multiplayer MP-1/2/3 (PR #180), Cubic generator C++ port.
- **2026-05-13–14:** `HeightmapGeneratorBase` extracted (PR #203); `Profiler.real_us` reliable (PR #207); `WaterChunkMesherCpp` (PR #214, later deleted in the native-fluid pivot).
- **2026-05-16–18 (native-fluid pivot):** PR #224/#227/#230 — water became Zylann-native `VoxelBlockyModelFluid` at `CHANNEL_TYPE` ids 16–23 (8 levels). Mesher auto-slopes; legacy id 5 retained for old saves; `WaterChunkMesher` C++ deleted. Plan: `design/WATER_STAGE6_PLAN.md`.
- **2026-05-19–20 (PR #232 underwater + PR #234 graphics):** UnderwaterFilter (instant-snap submerge + depth gradient + vol fog + god rays + bubble burst); AgX tonemap, SSAO/SSIL, PSSM 4-split shadows, MSAA 4×. Tangent-free terrain relief landed later — **never flip `bake_tangents`** (breaks water meshes). Records: `design/WATER_SHADER_V3_PLAN.md`, `design/GRAPHICS_PASS_2026-05-19.md`.
- **2026-05-21–22 (PR #235/#236/#237/#238):** AudioManager + 548 raw SFX takes; GraphicsManager 5-tier quality presets; procedural sky + clouds + stars/aurora/nebula (sky_atmosphere.gdshader); `AtmosphereProfile` resource; `terrain_voxel.gdshader` with tangent-free relief; `EmissiveLightManager` v1 OmniLight3D streaming.
- **2026-05-22–26 (PR #240 DistantTerrain):** streaming smooth heightmesh replaces baked HorizonSkirt. LOD outrun fixed (PrefetchViewer deleted; `VIEWER_LOOKAHEAD_MAX_OFFSET_M=0`). F11 LOD-debug shader + F12 viewer cubes shipped.
- **2026-05-27 (PR #241 4 C++ ports):** `VoxelGravityCpp` (131 ms → 2.8 ms max, 46× win), `EmissiveLightCpp` v1, `EmissiveBakedCpp` Phase J 3D-texture floodfill (supersedes v1), `WaterFlowCpp.scan_settle_region`. All four parity-gated. Y-fastest byte layout for Zylann channel bulk reads.
- **2026-05-27 (PR #243):** LOD1+ water surface line FIX — horizon backdrop plane re-enabled with `water_material.tres` + UnderwaterFilter group-toggle; WaterDiag probes on backtick / Shift+backtick / shader debug_mode 7-8.
- **2026-05-27 (PR #244 Phase K bundle):** Selection outline (object-space edges), cloud-phase accumulator (cures speed jerk), DebugOverlay GRAPHICS sub-view with per-effect toggles. Lens flare + rainbow shipped behind their toggles.
- **2026-05-27 (PR #245 Weather rework):** Designer playtest deferred all visuals to multi-session iteration. Rain shader / wet terrain / splash particles / god rays gated behind GraphicsManager toggles **defaulting OFF**; framework on disk. Audio envelope crossfade stays live. See `design/WEATHER_REWORK_2026-05.md`.
- **2026-05-27 (PR #246 EntityStreamer):** Full `EntityRegistry` (per-chunk store + JSON save/load) + 4-tier AI sleep system. Goblin/NPC/VoxelDrop retrofitted to `set_ai_tier` + `to/from_entity_record` protocol. Headless `entity` gate green (66 checks). Spec: `design/ENTITY_STREAMING.md`.

**Outstanding pickups:** Blender Roland model, MagicaVoxel prop exports, surface decoration pass, region-boundary profile auto-swap, regen 5 PHOTO-flagged voxel textures, Zylann `ShaderMaterialPool::recycle` assertion on F11 LOD-debug toggle, water leveling sim (`design/WATER_LEVELING_PLAN.md`). See `DESIGNER_TODO.md`.

## Art specification (3D VOXEL)
- **Voxel scale:** 6 voxels/m (~16.7 cm/block, player ~11 voxels tall).
- **Terrain:** `VoxelLodTerrain` + `VoxelMesherBlocky` reading `CHANNEL_TYPE` (8-bit material id) backed by `VoxelBlockyLibrary`. Atlas at `assets/voxels/texture_packs/default/` — 16 px tile × 64 cols (1024×1024). **Destructible by default**; `NoEditZone` Area3D volumes are the exception. Edits stored as deltas in `VoxelStreamSQLite`.
- **World scale:** Mira 12 km × 10 km (compression 125:1). Thal ~7 km × 5.5 km.
- **Props/buildings:** MagicaVoxel → .glb. Load-bearing structures sit inside NoEditZones.
- **Characters:** Blender low-poly .glb (200–500 tris).
- **Canonical refs:** `design/3D_VOXEL_MIGRATION.md`, `design/ART_PIPELINE.md`, `design/ART_DIRECTION.md`.

## What I never want
- Systems built before I need them.
- C# — never. GDScript by default; C++ GDExtension proactively for perf.

## Files requiring regular maintenance

Update when making related changes:

| File | Update when... |
|---|---|
| `lore/INDEX.md` + lore/* | New lore file / character / location / faction / timeline event |
| `design/3D_VOXEL_MIGRATION.md` | Edit verbs / NoEditZone rules / LOD radii change |
| `design/SYSTEMS_DESIGN.md` + per-system docs | New system or roster changes |
| `design/ART_DIRECTION.md` / `ART_PIPELINE.md` | Palette / shader / pipeline tool changes |
| `design/GRAPHICS_PASS_2026-05-19.md` | A graphics phase ships or shifts |
| `design/COMBAT_NEXT_PHASES.md` | Combat/enemy roadmap item completes |
| `design/MINING_TIME_SCALING.md` | New voxel material / tool-tier scaling |
| `design/INPUT_AND_CONTROLS.md` | New Input Map action (also update DESIGNER_TODO §1) |
| `design/PROFILER_AND_DIAGNOSTICS.md` | New autoload wrapped / new diagnostic pattern |
| `design/ENTITY_STREAMING.md` | EntityRecord schema / new entity type adopts the protocol |
| `dialogue/CHARACTER_VOICES.md` / `PRONUNCIATION.md` | New voiced character / proper noun |
| `DESIGNER_TODO.md` | New doc requires editor/asset work; tasks complete |
| `extensions/voxel_gen/` + `memory/project_voxel_gen_cpp_port.md` | New C++ port / new POD field |
| `CLAUDE.md` (this file) | Milestone completes; canonical contradictions; new systems |

---

## Lore reference
Start at `lore/INDEX.md`. Key: `WORLD.md`, `WORLD_GEOGRAPHY.md`, `CHARACTERS_*.md`, `BACKSTORY_*.md`, `GAME1_PART{1,2}.md`, `PEOPLES.md`, `GUILDS_*.md`, `HISTORY_*.md`, `SIDE_QUESTS_*.md`, `LEVEL_LAYOUTS_*.md`, `locations/` (25+), `REFERENCE.md`. **Always check `INDEX.md` before adding new lore files.**

## Design reference
Implementation docs live in `/design`. **When lore and design conflict, lore wins.** Categories:
- **World & systems:** SYSTEMS_DESIGN, COMBAT_DESIGN_3D, ENEMY_AI, SKILLS_AND_PROGRESSION, INVENTORY_AND_EQUIPMENT_SYSTEM, ITEM_LIBRARY, CRAFTING, MINING_TIME_SCALING, REST_AND_CAMP, INVESTIGATION_SYSTEM, LOCKPICKING, WEATHER_AND_ENVIRONMENT, SAVE_SYSTEM, DEATH_AND_RESPAWN, SWIMMING_AND_WATER, MULTIPLAYER.
- **Player systems:** HUD_AND_UI, INPUT_AND_CONTROLS, ACCESSIBILITY_AND_SETTINGS, WORLD_NAVIGATION, AUDIO_DESIGN.
- **Companion & NPC:** COMPANION_SYSTEM, CONVERSATION_SYSTEM, NPC_SYSTEM, BARK_LIBRARY, NPC_DIALOGUE_LIBRARY, JOURNAL_UI.
- **World & narrative:** FACTION_SYSTEM, QUEST_SYSTEM, ECONOMY_AND_VENDORS, MINI_GAMES.
- **Art & pipeline:** ART_DIRECTION, CAMERA_AND_PERSPECTIVE, TECH_STACK, ART_PIPELINE, ASSET_PIPELINE_AI, 3D_VOXEL_MIGRATION.
- **Ops:** MILESTONE_ROADMAP, ENDGAME_CHOICES, DIALOGIC_SETUP, TTS_PIPELINE, LESSONS_LEARNED, PROFILER_AND_DIAGNOSTICS, WATER_STAGE6_PLAN, WATER_SHADER_V3_PLAN, GRAPHICS_PASS_2026-05-19, WEATHER_REWORK_2026-05, ENTITY_STREAMING.

**`design/PROFILER_AND_DIAGNOSTICS.md` — read before guessing at perf issues.**

## Current project state

Godot 4.6.2. 3D voxel open world: VoxelLodTerrain streaming, editable terrain by default, NoEditZones protect settlements, 12 km × 10 km Mira.

**2D legacy on disk (retiring):** `Player.gd`, `World.tscn`, `Combat.tscn`, etc.

**3D core scripts:** `Player3D`, `CameraRig`, `HUDOverlay`, `JournalUI`, `World3DBootstrap` (**all world-load wiring goes here**), `VoxelDrop`, `DistantTerrainManager`.

**Combat v1:** `Enemy3D` base, `enemies/Goblin.gd`, `ThrowableSpear`, `BloodVFX` autoload. See `design/COMBAT_NEXT_PHASES.md`.

**Voxel + world autoloads:** `VoxelEditManager` (async edit queue, NoEditZone gate, MP-aware — **always route writes through here**), `NoEditZoneRegistry`, `CubicHeightmapGeneratorCpp` + adapter, `WorldClock` (240 real s = 1 game hour), `BarkManager`, `WaterFlowManager` (flow tick disabled since native-fluid pivot — static water only), `UnderwaterFilter`, `DayNightCycle`, `EditToolHandler`, `ThrowableHandler`, `PowderCharge`, `VoxelGravityManager` (C++ via `VoxelGravityCpp`), `EmissiveLightManager` (v1, parked by baked manager but kept as fallback), `EmissiveBakedLightManager` (Phase J 3D-texture floodfill), `WeatherManager`, `RainOverlay`, `WeatherLocationProfile`, `WeatherZone`, `EntityRegistry`.

**Specified but not yet implemented:** Combat next phases, `SchematicLibrary` (player construction), `QuestManager`, `CompanionManager`, LOD-bake-on-eviction caching.

Manual setup still required: see `DESIGNER_TODO.md` Section 1.

---

## C++ GDExtension perf opportunities

`extensions/voxel_gen/` — used **proactively** for CPU work that would benefit from native speed (voxel BFS/floodfills, per-frame grid math, large data marshalling, anything iterating thousands+ items/frame). Build: `python -m SCons platform=windows target=template_debug use_mingw=yes -j8` from `extensions/voxel_gen/` (close Godot first or scons fails on DLL replace). Reload Godot after.

**Port pattern:** godot-cpp can't subclass Zylann classes → C++ extends `godot::Resource` + thin GDScript adapter extends `VoxelGeneratorScript` and forwards by Variant call. Mirror this for any future port.

**Profiler measurement:** use `engine.real_us` from PR #207, not `proc_us`.

**Done:** `CubicHeightmapGeneratorCpp`, `CopperIslesHeightmapGeneratorCpp`, `HeightmapGeneratorBase`, `VoxelGravityCpp`, `EmissiveLightCpp` (v1), `EmissiveBakedCpp` (Phase J), `WaterFlowCpp` (settle scan). All autoloads have a GD fallback for when the DLL is missing.

**Reusable patterns (PR #241 lessons):**
1. Bulk-read Zylann channels via `get_channel_as_byte_array` (one Variant call); per-voxel `Variant::call` from C++ is slower than GDScript-native.
2. Byte layout is **Y-fastest**: `byte_index = (y + x*sy + z*sx*sy) * bytes_per_voxel`.
3. Return per-voxel results as `PackedInt32Array` streams, not `Dictionary[Vector3i, int]`.
4. Cross-language sort: pick a total ordering (`(y, x, z)` lex) — never rely on unstable sorts agreeing.

**Next targets (post #246):**
1. `WaterFlowManager._flow_chunk` + `_process_connectivity_fill` — only if a future capture shows them spike.
2. Zylann `ShaderMaterialPool::recycle` assertion in F11 LOD-debug toggle path (correctness, not perf).

**NOT worth porting:** `VoxelMesherBlocky` (Zylann C++), chunk streaming / LOD octree (Zylann main-thread), `VoxelEditManager` queue (cheap), LOD-bake-on-eviction caching (C++ generator already shrunk the motivating cost).

**Process for any future port:** parity harness FIRST (`@tool` EditorScript in `scripts/_dev/`, bit-exact), POD snapshot infra for Resource data, land in sub-phases each ending in a green harness, adapter forwards every public method. Full receipt: `memory/project_voxel_gen_cpp_port.md`.

---

## Godot workflow

No CLI build, lint, or test. To verify changes:
1. Open project in Godot 4.6.2.
2. Run the scene: `World3D.tscn` (Mira), `CopperIslesTest.tscn` (F7 cycles terrain scale), `scenes/_dev/CombatTest.tscn` (combat dev arena, F1 debug menu, spear pre-equipped), `scenes/_dev/BakeWorld{3D,}.tscn` (UI bake — must run in-game).
3. Check Output panel.

**Headless harness:** `tools/headless/run.ps1 <selector>` runs Godot's `_console.exe` (plain win64 exe is GUI-subsystem, won't pipe stdout) with `tools/headless/runner.gd` as a SceneTree script. Selectors: `gate0 codec wmat shader phase7 spike phase2 gen distant gravity emissive baked_light water_flow entity`. Exit 0 = pass. **Scope: data/logic/parity ONLY** — dummy renderer, no GPU. Visuals still need the designer running the editor.

---

## Git workflow patterns
- One fix per branch (small, focused).
- One file per commit for large `.tscn` / `.gd` (avoids stream-idle timeouts).
- Cherry-pick over rebase when a branch has conflicting squash-merged history.
- Never amend published commits; fix-then-new-commit if a hook fails.
- Push with `git push -u origin <branch-name>`.

---

## Critical GDScript patterns

These rules are non-negotiable — violating them breaks things in non-obvious ways.

### Player input MUST go through `_can_take_input()` (MP-2)
```gdscript
var input_dir: Vector2 = Vector2.ZERO
if _can_take_input():
    input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
```
True in OFFLINE mode OR when local peer owns this body. Every `Input.*` site in Player3D / EditToolHandler / ThrowableHandler must guard. Raw `Input.get_vector(...)` lets remote replicas eat the local keyboard.

### Voxel edits MUST go through `VoxelEditManager`
```gdscript
VoxelEditManager.queue_edit_sphere(world_pos, radius, voxel_value)
# Returns false if NoEditZone rejected.
```
Raw `VoxelTool.do_*` bypasses NoEditZone, async budget, EditedChunkRegistry, gravity scans, LOD-bake invalidation, `edit_applied` emission, and MP-3 RPC routing (clients no-op, host doesn't broadcast). MP routing at bottom of `VoxelEditManager.gd`; OFFLINE short-circuits.

### Skill XP MUST go through `SkillManager.add_xp(skill, amount)`
```gdscript
SkillManager.add_xp("mining", 5.0)
SkillManager.dispatch("on_voxel_broken", {"skill": "mining", "tool_id": "iron_pickaxe"})
```
Direct `GameState._skill_levels[...] = N` bypasses level-up, perk-point grants, active-perk events, JournalUI `level_up` signal. Skills: `sword throwables bow mining felling excavation demolition lockpicking alchemy smithing vitality speech`.

### UI buttons / sliders need MANUAL `_input` dispatch
`Button.pressed` and `HSlider.value_changed` **do NOT fire** in this project — Dialogic's input subsystem consumes `InputEventMouseButton` globally. Reference impl: `PauseMenu._input / _dispatch_click / _hits`. Implement manual dispatch from the first commit on any new UI. See LESSONS_LEARNED 2026-05-03 + 2026-05-09.

### Voxel material lookup via the registry
```gdscript
var mat_id := VoxelMaterialRegistry.material_id_from_packed(packed_voxel)
var mat := VoxelMaterialRegistry.get_by_id(mat_id)
# Writes: VoxelMaterialRegistry.pack_voxel(mat_id, color)
```
Never decode alpha by hand (`packed & 0xFF`).

### Water is NATIVE Zylann fluid (`VoxelBlockyModelFluid`)
```gdscript
const WaterMaterial := preload("res://scripts/WaterMaterial.gd")  # NO class_name
WaterMaterial.is_water_type(t)                # replaces every `== 5`
WaterMaterial.render_id_for_level(level, dir) # sim level -> CHANNEL_TYPE id
```
8 fluid models, levels 1..8 → ids 16..23 (full = 23). Injected at runtime by `World3DBootstrap.add_model()` (the .tres doesn't restore on load — bootstrap is source of truth). Legacy cube id 5 retained for pre-pivot saves. **`WaterByteCodec`/`DATA5` is sim source of truth; `CHANNEL_TYPE` is render projection.** Player water queries: `WaterFlowManager.is_position_in_water / get_water_level_at`. Plan: `design/WATER_STAGE6_PLAN.md`.

### `VoxelBuffer CHANNEL_COLOR` must be 32-bit BEFORE chunks stream
Done once in `World3DBootstrap._ready()`:
```gdscript
if "format" in terrain:
    var fmt := VoxelFormat.new()
    fmt.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
    terrain.format = fmt
```
Default 8-bit truncates packed RGBA+mat_id to just R (terrain renders near-black). **NEVER call `set_channel_depth()` inside `_generate_block`** — invalidates buffer storage.

### `VoxelGeneratorScript._generate_block` runs on a worker thread
No SceneTree access (autoloads, signals, get_node). Cache a plain-data snapshot on main thread, push into generator, read locally inside `_generate_block`. See `NoEditZoneRegistry.get_water_blocking_aabbs_snapshot()`.

### `Dictionary[int, PackedByteArray]` mutation needs read-modify-write
Godot 4 indexing returns a copy:
```gdscript
var bmp: PackedByteArray = my_dict.get(key, PackedByteArray())
bmp[index] = value
my_dict[key] = bmp
```

### Some Zylann `VoxelLodTerrain` properties are INT — read back to verify
```gdscript
terrain.set("collision_update_delay", 100)   # ms; 0.1 truncates to 0 → per-frame collision rebuild
print("actual=%s" % terrain.get("collision_update_delay"))
```
Properties also clamp silently (`mesh_block_size = 32` was clamped to 16 in some scenes). Bootstraps print readbacks as policy.

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
Categories: `WORLD WATER WEATHER PHYS OTHER`. Wrappers add ~1 µs.

### Profiler / WaterDiag hotkeys
- **F3** Profiler overlay: Tab cycle, P pause, C capture JSON, S save, Q clear, ←/→ timeline. Keyboard-only (Button.pressed doesn't fire).
- **F4/F5/F6** WaterDiag: F4 panel + 1Hz `[WaterDiag]` line, F5 one-shot `[WaterInspect]` 3×3 columns dump, F6 cycles `water.gdshader debug_mode` (0 normal · 1 depth · 2 fresnel · 3 thickness · 4 surface-facing). Full recipes in `design/PROFILER_AND_DIAGNOSTICS.md`.
- **Capture JSON path:** `%APPDATA%\Godot\app_userdata\Game One\profile_capture_<msec>.json`. Capture-from-frame-1 via `scripts/Profiler.gd capture_on_startup: true` — flip back to false after.

### Zylann blocky-library properties: methods, not `.set()`
```gdscript
model.call("set_tile", 3, Vector2i(2, 0))            # 3 = SIDE_POSITIVE_Y
model.call("set_material_override", 0, atlas_mat)
```
`.set("tile_top", ...)` silently no-ops (Zylann routes storage through method pairs; `.set()` writes a virtual bag only used for serialization → all-white terrain). Values written via methods WRITE to `.tres` but DO NOT RESTORE on load — re-apply at runtime in `World3DBootstrap._inject_atlas_materials_into_library`. SIDE enum: NEG_X=0, POS_X=1, NEG_Y=2, POS_Y=3, NEG_Z=4, POS_Z=5.

### Other essentials
- **`VoxelLodTerrain.material` overrides every per-cube `material_override_0`** — leave it null when using textured cube models.
- **`OmniLight3D.light_energy`** (NOT `.energy` — that's PointLight2D).
- **Capsule CollisionShape3D:** offset upward by half height (Y = +0.85 for 1.7m).
- **2D input → 3D XZ:** `Vector3(input.x, 0, input.y)`. Never map `input.y → velocity.y`.
- **Camera-relative movement:** `(transform.basis * Vector3(input.x, 0, input.y)).normalized()`. CameraRig rotates the body to match camera yaw.
- **Frame-rate-independent deceleration:** `velocity = velocity.move_toward(Vector3.ZERO, DECEL * delta)`.
- **Dialogic autoload check:** `if get_node_or_null("/root/Dialogic"): Dialogic.start(...)`.
- **One-shot signal:** `sig.connect(fn, CONNECT_ONE_SHOT)`.
- **Probe gdextension classes before guessing API:** print `get_property_list()` AND `get_method_list()`. Property lists alone mislead (Zylann `VoxelBlockyModelCube.tile_top` is listed but storage goes through `set_tile()`).

---

## Critical scene hierarchies

Load-bearing — scripts use hardcoded `$NodeName` references.

**Player3D / CameraRig:**
```
Player3D (CharacterBody3D)
└── CameraTarget (Node3D)
    └── SpringArm3D (CameraRig.gd)
        └── Camera3D
```
CameraRig walks `get_parent().get_parent()` to reach the body — don't add wrapper nodes. Two camera modes: **Standard** (mouse rotates body; W toward camera) and **Freelook** (hold F2 — orbits arm, re-centers on release).

**NPC:**
```
NPCNode (CharacterBody3D + NPC.gd)
├── MeshInstance3D
├── CollisionShape3D
├── BarkArea (Area3D)          ← name must be exactly "BarkArea"
│   └── CollisionShape3D
└── InteractArea (Area3D)      ← name must be exactly "InteractArea"
    └── CollisionShape3D
```
Assign an `NPCData` resource in the Inspector. Tier 0 background NPCs are plain Node3D, no script.

**World3D.tscn (terrain):**
```
World3D (Node3D)
├── VoxelLodTerrain
│   ├── generator: CubicHeightmapGeneratorAdapter.gd
│   │   └── cpp_impl: CubicHeightmapGeneratorCpp
│   ├── stream: VoxelStreamSQLite
│   └── mesher: VoxelMesherBlocky
├── VoxelViewer (child of Player3D)
├── EntityStreamer
└── ...
```

**NoEditZone authoring:**
```
SettlementRoot (Node3D)
├── NoEditZone (Area3D, group: "no_edit_zone")
│   └── CollisionShape3D (~50–100m buffer)
└── BuildingProp (MeshInstance3D — .glb)
```
Every settlement, dungeon entrance, and lore landmark sits under a NoEditZone. Writes inside silently rejected → Roland barks *"This place doesn't yield to me."*

---

## Autoload registration

Registered in `project.godot`, load order:
`GameState`, `Colors`, `TransitionManager`, `SaveNotification`, `PauseMenu`, `NetTransport`, `MultiplayerManager`, `GraphicsManager`, `Settings`, `DebugOverlay`, `FlagScheduler`, `InventoryManager`, `PerkRegistry`, `FactionManager`, `VoxelMaterialRegistry`, `SkillManager`, `JournalUI`, `HUDOverlay`, `Profiler`, `ProfilerOverlay`, `AudioManager`, `NoEditZoneRegistry`, `VoxelEditManager`, `VoxelGravityManager`, `EmissiveLightManager`, `EmissiveBakedLightManager`, `WaterFlowManager`, `Dialogic`, `SpeechCheckBroker`, `BarkManager`, `WorldClock`, `WeatherManager`, `BloodVFX`, `WaterDiag`, `EntityRegistry`.

**Key behaviours:**
- `MultiplayerManager`: owns `multiplayer_peer`. **OFFLINE mode `is_host() == true`** so single-player authority gates work unmodified.
- `VoxelEditManager` + `WaterFlowManager` MP-aware: VEM clients forward via 3 RPCs, host validates + broadcasts (60 req/s/peer limit); WFM `_physics_process` early-returns if not host.
- `SkillManager`: single entry point for XP / perk picks / active-perk events. `PerkRegistry` loads 300 perks. `FactionManager.is_friendly(faction)` is the `≥75` gate trainers use. `SpeechCheckBroker` presents KCD2-style Speech modal.
- `Colors` + `UIStyles`: `Colors` (`assets/ui/Colors.gd`) is the Voxelmark palette source. `UIStyles` (`assets/ui/UIStyles.gd`, `RefCounted`, not autoloaded) builds StyleBox/FontVariation. CSS at `assets/ui/css/menus_shared.css`.
- `JournalUI` autoload points at the **scene** `res://scenes/ui/Journal.tscn`.
- `AudioManager`: `play(id, world_pos) / play_loop(id) -> handle / stop_loop(handle)`. Resolves `assets/audio/sfx/<folder>/<id>[.ogg|_NN.ogg]`. No-ops with one warning until file placed — wire call sites before assets land. Signal subscriptions are deferred + guarded so its early load slot is safe.
- `GraphicsManager`: 5-tier quality presets (HIGH = default = `World3D.tscn` baseline). Persists to `user://graphics.json`. `apply_current()` is null-guarded per step (menu-safe). `ShaderProfile.gd` has **no `class_name`** (headless-harness-safe).
- `EmissiveBakedLightManager`: reads shader globals declared in `project.godot [shader_globals]` (`baked_light_tex / _origin_world / _inv_volume_m / _strength`). **NEVER call `RenderingServer.global_shader_parameter_add/_get/_get_list`** — editor-only APIs that error in shipped builds. Declare globals in `[shader_globals]`; runtime only `_set`.

**Load-order rules:**
- `NetTransport` before `MultiplayerManager`.
- `MultiplayerManager` before any gameplay autoload that reads its API in `_ready` (currently `WaterFlowManager`).
- `Colors` before any UI autoload.
- `InventoryManager` before `VoxelMaterialRegistry` (registry validates `yield_item_id`).
- `VoxelMaterialRegistry` before `VoxelEditManager`.
- `NoEditZoneRegistry` before `VoxelEditManager`.
- `VoxelEditManager` before `VoxelGravityManager` / `EmissiveLightManager` / `WaterFlowManager` (they subscribe to `edit_applied`).
- `EmissiveLightManager` before `EmissiveBakedLightManager` (baked autoload disables v1 in `_ready`).
- `WorldClock` before `WeatherManager` (subscribes to `hour_changed`).
- `WaterFlowManager` before `WeatherManager` (pushes wind into water shader).

**NOT yet registered:** `SchematicLibrary` (player construction). Scripts that reference unregistered autoloads must guard with `get_node_or_null`.

### Dev-scene group convention
```gdscript
add_to_group("dev_scene")
```
**HUDOverlay, PauseMenu, JournalUI, SaveNotification** check `GameState.is_dev_scene()` and stay dormant. Other autoloads keep running. Add the group call to any new dev scene's bootstrap `_ready()`.

---
