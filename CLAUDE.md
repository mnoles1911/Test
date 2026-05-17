# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Game One — Project Bible

## What I'm building
A 3D voxel narrative RPG — Veloren meets Skyrim in atmosphere and open-world scale. Real-time action combat (Witcher 3 / Dark Souls style), 1-vs-many, first + third-person cameras, co-op multiplayer for 1-4 friends. Voxel world in Godot 4.6.2 with Zylann's Voxel Tools. GDScript by default; C++ GDExtension only for measured hot paths (per-block voxel generator is the canonical example). Game one of a planned trilogy adapted from a 200-page source manuscript.

**Engine:** 3D voxel since 2026-04-30 (pivoted from 2D pixel art). Full migration plan in `design/3D_VOXEL_MIGRATION.md`.

## My background
I am a writer and game designer, not a programmer. Explain code in plain English before writing it. Keep scripts heavily commented. Prefer simple, readable solutions.

## Genre and tone
Epic fantasy, grounded emotional stakes — LOTR scale, single-protagonist intimacy. World is Mira-Thal, third age. See `lore/WORLD.md` + `lore/INDEX.md`.

## Core systems
- Player: CharacterBody3D, 8-dir XZ movement
- World: VoxelLodTerrain (Zylann) + MagicaVoxel props
- Camera: SpringArm3D over-shoulder, ~15° elevation, lock-on for 1-vs-many
- Dialogue: Dialogic 2 plugin
- Combat: real-time action in-world (Hades style), 1-vs-many
- Game state: GameState.gd autoload
- Transitions: TransitionManager autoload

## Folder structure
- /scenes — .tscn files
- /scripts — .gd files
- /addons/dialogic — Dialogic 2 plugin (do not edit; manage via Asset Library)
- /assets/portraits — 256×320 dialogue portraits
- /assets/voxel, /assets/models, /assets/audio, /assets/npcs — referenced in design docs, **not yet on disk**; create as needed
- /dialogue — Dialogic timelines (.dtl) + `CHARACTER_VOICES.md`, `PRONUNCIATION.md`, `STYLE.md`
- /lore — narrative canon (start at lore/INDEX.md)
- /design — implementation reference
- /tools — pipeline scripts (TTS, draft stripping); see `tools/README.md`

## Milestone history
Read `git log` for detail. Highest-impact milestones to know about:
- **2026-04-30 (PR #43):** 2D → 3D voxel pivot.
- **2026-05-03–05:** destructible voxel slice — VoxelLodTerrain + SQLite deltas, edit/gravity/water managers, NoEditZones, swimming, day/night, weather, voxel-cell flow sim.
- **2026-05-06–10:** Copper Isles demo + textured tileset; mesher migrated to `VoxelMesherBlocky`; sea level Y=125. **Caveat:** delivered EXR is a single continent, not the lore-spec archipelago — re-source pending.
- **2026-05-10–11:** six tiered voxel-generation rules; Voxel Combat v1 (Enemy3D/Goblin/ThrowableSpear/BloodVFX); cubic generator ported to C++.
- **2026-05-12:** Copper Isles generator ported to C++; Skill system (PR #201) — 12 skills, 300 perks, trainers, Speech checks; multiplayer MP-1/2/3 (PR #180) — transport, player presence, voxel edit replication.
- **2026-05-13:** `HeightmapGeneratorBase` extracted (PR #203); Profiler real_us measurement reliable (PR #207).
- **2026-05-14:** WaterChunkMesher C++ port + viewer-offset smoothing + thread-count Settings slider (PR #214).

Outstanding pickups: Blender Roland model, MagicaVoxel prop exports, surface decoration pass, ambient weather audio, region-boundary profile auto-swap. See `DESIGNER_TODO.md`.

## Art specification (3D VOXEL)
- **Voxel scale:** 6 voxels/m (locked 2026-05-03; ~16.7 cm/block, player ~11 voxels tall).
- **Terrain:** `VoxelLodTerrain` + `VoxelMesherBlocky` reading `CHANNEL_TYPE` (8-bit material id) backed by `VoxelBlockyLibrary`. Procedural baseline from `CubicHeightmapGenerator`. Atlas at `assets/voxels/texture_packs/default/` — 16 px tile × 64 cols (1024×1024). **Destructible by default**; `NoEditZone` Area3D volumes are the exception. Edits stored as deltas in `VoxelStreamSQLite`.
- **World scale:** Mira 12 km × 10 km (compression 125:1). Thal ~7 km × 5.5 km.
- **Props/buildings:** MagicaVoxel → .glb. Narratively load-bearing structures sit inside NoEditZones.
- **Player-built:** schematic props (Carpentry Bench) + per-voxel Build Mode.
- **Characters:** Blender low-poly .glb (200–500 tris). Portraits unchanged for dialogue.
- **Camera:** SpringArm3D over-shoulder, ~15° elevation, lock-on.
- **Lighting:** OmniLight3D + DirectionalLight3D + WorldEnvironment SSAO + fog.
- **Canonical refs:** `design/3D_VOXEL_MIGRATION.md`, `design/ART_PIPELINE.md`, `design/ART_DIRECTION.md`.

## What I never want
- Systems built before I need them.
- C# — never. GDScript is the default; C++ GDExtension only for measured hot paths.

## Files requiring regular maintenance

Review and update whenever making significant additions or changes:

| File | Update when... |
|---|---|
| lore/INDEX.md | Any new lore file added or scope changes |
| lore/REFERENCE.md | New characters, locations, factions, timeline events |
| lore/CHARACTERS_COMPANIONS.md / CHARACTERS_NPCS.md | Companion/NPC details change |
| lore/WORLD_GEOGRAPHY.md + MAP_GENERATION_GUIDE.md | New locations, terrain, settlements |
| design/3D_VOXEL_MIGRATION.md | Edit verbs, NoEditZone rules, mesh-bake, LOD radii change |
| design/MINING_TIME_SCALING.md | New voxel material, baselines tuned, tool-tier scaling |
| design/SYSTEMS_DESIGN.md | Companion roster, factions, new systems |
| design/ART_DIRECTION.md / ART_PIPELINE.md / ASSET_PIPELINE_AI.md | New locations, palette/shader decisions, pipeline tools |
| design/COMBAT_NEXT_PHASES.md | Combat/enemy roadmap item completes or shifts |
| design/ITEM_LIBRARY.md / CRAFTING.md | New recipes, items, stations |
| design/SKILLS_AND_PROGRESSION.md | New perks, sub-skills, trainers, XP tuning |
| design/TTS_PIPELINE.md | Render tooling lands, voice IDs lock, schema changes |
| design/FACTION_SYSTEM.md / QUEST_SYSTEM.md / MINI_GAMES.md | System rules change |
| design/INPUT_AND_CONTROLS.md | New Input Map action (also update DESIGNER_TODO Section 1) |
| design/NPC_SYSTEM.md / LOCKPICKING.md | Tier rules, mechanics change |
| dialogue/CHARACTER_VOICES.md / PRONUNCIATION.md | New voiced character or proper noun |
| DESIGNER_TODO.md | New doc requires editor/asset work; tasks complete |
| design/COPPER_ISLES_BAKE_NOTES.md / COPPER_ISLES_DEMO_HEIGHTMAP.md | Zylann probe results, bake decisions, island layout |
| extensions/voxel_gen/ + memory/project_voxel_gen_cpp_port.md | New tier ported, new POD field, new C++ Resource, parity harness extended |
| design/PROFILER_AND_DIAGNOSTICS.md | New autoload wrapped, new category, new diagnostic pattern, capture-JSON schema |
| CLAUDE.md (this file) | Milestone complete; canonical contradictions; new systems/design docs |

---

## Lore reference
All canon lives in /lore. Start at `lore/INDEX.md` for the directory map. Key files: `WORLD.md`, `WORLD_GEOGRAPHY.md`, `MAP_GENERATION_GUIDE.md`, `CHARACTERS_*.md`, `BACKSTORY_*.md`, `GAME1_PART1.md` / `GAME1_PART2.md`, `PEOPLES.md`, `GUILDS_*.md`, `HISTORY_*.md`, `SIDE_QUESTS_GAME*.md`, `LEVEL_LAYOUTS_ACT*.md`, `locations/` (25+ entries), `REFERENCE.md`. **Always check INDEX.md before adding new lore files to avoid duplication.**

## Design reference
Implementation docs live in /design. When lore and design conflict, lore wins. Index:

- **World & systems:** SYSTEMS_DESIGN, COMBAT_DESIGN_3D, ENEMY_AI, SKILLS_AND_PROGRESSION, INVENTORY_AND_EQUIPMENT_SYSTEM, ITEM_LIBRARY, CRAFTING, MINING_TIME_SCALING, REST_AND_CAMP, INVESTIGATION_SYSTEM, LOCKPICKING, WEATHER_AND_ENVIRONMENT, SAVE_SYSTEM, DEATH_AND_RESPAWN, SWIMMING_AND_WATER, MULTIPLAYER.
- **Player systems:** HUD_AND_UI, INPUT_AND_CONTROLS, ACCESSIBILITY_AND_SETTINGS, WORLD_NAVIGATION, AUDIO_DESIGN.
- **Companion & NPC:** COMPANION_SYSTEM, CONVERSATION_SYSTEM, NPC_SYSTEM, BARK_LIBRARY, NPC_DIALOGUE_LIBRARY, JOURNAL_UI.
- **World & narrative:** FACTION_SYSTEM, QUEST_SYSTEM, ECONOMY_AND_VENDORS, MINI_GAMES.
- **Art & pipeline:** ART_DIRECTION, CAMERA_AND_PERSPECTIVE, TECH_STACK, ART_PIPELINE, ASSET_PIPELINE_AI, 3D_VOXEL_MIGRATION.
- **Planning & ops:** MILESTONE_ROADMAP, ENDGAME_CHOICES, DIALOGIC_SETUP, TTS_PIPELINE, LESSONS_LEARNED, PROFILER_AND_DIAGNOSTICS, COPPER_ISLES_DEMO_HEIGHTMAP, COPPER_ISLES_BAKE_NOTES.

`design/PROFILER_AND_DIAGNOSTICS.md` — **read this before guessing at perf issues**; the answer is usually in a recent capture.

## Current project state

Godot 4.6.2. 3D pivot complete. Open world plan confirmed: VoxelLodTerrain streaming, editable/destructible terrain by default, edits as deltas in `VoxelStreamSQLite`, NoEditZones protect settlements/landmarks, 12km × 10km Mira, third-person over-shoulder, low-poly Blender characters.

System design corpus complete (combat, AI, companions, factions, quests, economy, save, death, weather, HUD, input, accessibility, audio, navigation, lockpicking, destructible terrain — all in `/design`). Pipeline tooling in `tools/README.md` (requires `ELEVENLABS_API_KEY`).

**2D legacy on disk (retiring as 3D replaces):** `Player.gd`, `CampfireFlicker.gd`, `DialogueTrigger.gd`, `CombatTrigger.gd`, `Combat.gd`; `Player.tscn`, `World.tscn`, `Combat.tscn`.

**3D core in place:** `Player3D` (8-dir XZ + sprint/crouch + HP/endurance), `CameraRig` (SpringArm3D over-shoulder + freelook F2 + zoom + lock-on), `HUDOverlay`, `JournalUI` (6-tab scene at `scenes/ui/Journal.tscn`), `CampfireFlicker3D`, `SpawnPoint3D` / `RoomTrigger3D` / `DialogueTrigger3D`, `World3D.tscn`, `World3DBootstrap.gd` (**all world-load wiring goes here**), `VoxelDrop.gd` (RigidBody3D pickup), `CopperIslesHeightmapGenerator.gd` (now C++ via adapter), `CopperIslesTestBootstrap.gd`, `HorizonSkirt.gd`.

**NPCs:** `NPC.gd` (Tier 1–3 base; bark + E-press dialogue + disposition + schedule), `NPCData.gd` (Resource: npc_id, Tier, disposition, barks, schedule), `NPCScheduleEntry.gd`.

**Combat v1:** `Enemy3D.gd` (base, IDLE/ALERT/COMBAT, take_damage, die, corpse loot), `enemies/Goblin.gd`, `throwables/ThrowableSpear.gd` (synchronous damage path + `call_deferred` for freeze/reparent — Godot forbids those inside `body_entered`), `BloodVFX.gd` autoload (burst/dust/drip/pool — `PlaneMesh` not `Decal` for renderer compat). See `design/COMBAT_NEXT_PHASES.md` for what's next.

**Voxel + world (autoloaded):**
- `VoxelEditManager` — async edit queue, NoEditZone gate, EditedChunkRegistry, `WORLD_GENERATOR_VERSION` stamping. **Always route writes through here.** Emits `edit_applied`. MP-aware (host validates + broadcasts; clients forward via RPC).
- `NoEditZoneRegistry` — registers `no_edit_zone` group Area3Ds.
- `CubicHeightmapGeneratorCpp` + `CubicHeightmapGeneratorAdapter.gd` — C++ generator (Mira) since 2026-05-11; adapter forwards `_generate_block` + `set_ore_materials` / `set_disk_materials` / `get_ground_voxel_y_at`.
- `WorldClock` — in-game time (240 real s = 1 game hour). Pauses during Dialogic.
- `BarkManager`, `WaterFlowManager` (flow tick **disabled** since Water Voxel V2 — static water only; see below), ~~`WaterChunkMesher`~~ (**DELETED 2026-05-16, Water Voxel V2** — water is now a transparent `CHANNEL_TYPE=5` blocky block drawn by the terrain mesher; no separate water mesher, no horizon plane; see `design/WATER_VOXEL_V2_PLAN.md`), `WaterByteCodec` (legacy DATA5 layout — now only used by the deferred flow rewrite), `UnderwaterFilter`, `NoEditZone.gd` (`blocks_water_flow=true` default), `DayNightCycle`, `EditToolHandler` (pickaxe/axe/shovel), `ThrowableHandler`, `PowderCharge`, `VoxelGravityManager` (16 m flood-fill on `edit_applied`), `FallingVoxelCluster` + `VoxelClusterBuilder`, `VoxelMaterial.gd` + `VoxelMaterialRegistry`, `WeatherManager` (six-state, fog/wind/particles/lightning), `RainOverlay`, `WeatherLocationProfile`, `WeatherZone`.

**Dev tools (`scripts/_dev/`, `scenes/_dev/`):** `WorldBakeController` + `BakeWorld.tscn` (Copper Isles) + `BakeWorld3D.tscn` (Mira); `SkirtBaker`; `ParityProbe` (C++ math primitive parity shim, retained for next port); `CombatTestBootstrap` + `CombatTest.tscn`.

**Specified but not yet implemented:** Combat next phases (see COMBAT_NEXT_PHASES.md), `SchematicLibrary` autoload (player construction), `EntityRegistry` + `EntityStreamer` (stub on disk — only prints chunk-enter events; full logic deferred to Phase 6-3D), `QuestManager`, `CompanionManager`, LOD-bake-on-eviction caching (deferred until perf demands).

Manual setup still required: see `DESIGNER_TODO.md` Section 1.

---

## C++ GDExtension perf opportunities

GDScript-first; C++ extension at `extensions/voxel_gen/` is the escape hatch for measured hot paths. Build: `python -m SCons platform=windows target=template_debug use_mingw=yes -j8` from `extensions/voxel_gen/` (close Godot first or scons fails on DLL replace).

godot-cpp can't subclass Zylann classes → port pattern is **C++ extends `godot::Resource` + thin GDScript adapter extends `VoxelGeneratorScript`** and forwards by Variant call. Mirror this for any future port.

**Profiler measurement:** use `engine.real_us` from PR #207, not `proc_us` (the latter plateaus across many frames and is unreliable for p99 work).

**Done:** `CubicHeightmapGeneratorCpp`, `CopperIslesHeightmapGeneratorCpp`, `HeightmapGeneratorBase` (PR #203 — extracted ~500 shared lines), `WaterChunkMesherCpp` (PR #214 — greedy 2D run-merge + ArrayMesh build).

**Next targets, payoff-vs-effort order:**

1. **`WaterFlowManager.gd`** flow tick (M). 4 Hz scan over chunks within 20 m, per-voxel byte read/write. Sits in `[PERF]` top-3 already. `WaterByteCodec` is POD → mostly buffer iteration.
2. **`VoxelGravityManager.gd`** flood-fill (S-M). 16 m local BFS for unsupported voxels. Clean port; worth it only if gravity scans surface in PERF.
3. **Generic chunk-bytes scratch helper** (S). Several GD systems each `VoxelBuffer.get_voxel × N` into `PackedByteArray`. A shared C++ "snapshot CHANNEL_TYPE + DATA5 to flat buffer" helper amortises that.

**NOT worth porting:** `VoxelMesherBlocky` (already Zylann C++); chunk streaming / LOD octree (Zylann main-thread work, not optimisable from outside); `VoxelEditManager` queue (already cheap; bound by Zylann's VoxelTool write path); LOD-bake-on-eviction caching (C++ generator already shrunk the motivating cost).

**Process for any future port:**
1. Pick a target with a clearly-bounded function surface; prefer pure-math hot loops over anything touching the SceneTree (worker threads can't).
2. Write the parity harness FIRST as a `@tool` EditorScript in `scripts/_dev/`. Use `ParityProbe` for math primitives; per-chunk byte diffs for VoxelBuffers. Bit-exact output is the only acceptable gate.
3. POD snapshot infra if C++ needs Resource data from GDScript (mirror `set_ore_materials(Array[Dictionary])`).
4. Land in sub-phases each ending in a green parity harness — never commit a phase that breaks parity, even if you "know" the diff is benign.
5. Adapter forwards every public method the bootstrap calls.

See `memory/project_voxel_gen_cpp_port.md` for the full receipt of the cubic generator port.

---

## Godot workflow

No CLI build, lint, or test for the Godot side. To verify changes:
1. Open project in Godot 4.6.2.
2. Run the relevant scene:
   - `World3D.tscn` — Mira (C++ generator via adapter).
   - `CopperIslesTest.tscn` — Copper Isles; F7 cycles terrain scale.
   - `scenes/_dev/BakeWorld.tscn` / `BakeWorld3D.tscn` — UI-driven bake; must run in-game.
   - `scenes/_dev/CombatTest.tscn` — combat dev arena, F1 debug menu, spear pre-equipped.
3. Check Output panel.

C++ extension build: see above. After build, reload Godot. When a port is in flight, parity-check via the port's `@tool` harness in `scripts/_dev/` (File → Run).

**Do not write shell commands that try to run Godot headlessly — there is no such setup here.**

---

## Git workflow patterns

- **One fix per branch.** Small, focused branches review and cherry-pick cleanly.
- **One file per commit** for large .tscn / .gd files (avoids stream idle timeouts on push).
- **Cherry-pick over rebase** when a branch has conflicting squash-merged history.
- **Never amend published commits.** If a hook fails, fix it and create a new commit.
- Always push with `git push -u origin <branch-name>`.

---

## Critical GDScript patterns

**Player input MUST go through `_can_take_input()` (MP-2):**
```gdscript
# WRONG — remote replicas of other players will consume our local keyboard.
var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

# RIGHT — gate first. In OFFLINE mode _can_take_input() returns true.
var input_dir: Vector2 = Vector2.ZERO
if _can_take_input():
    input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
```
`_can_take_input()` is `true` when `MultiplayerManager.is_offline()` OR `get_multiplayer_authority() == multiplayer.get_unique_id()`. Every `Input.*` site in Player3D, EditToolHandler, ThrowableHandler must guard.

**Voxel edits MUST go through `VoxelEditManager` — never raw `VoxelTool`:**
```gdscript
# WRONG — bypasses NoEditZone check, async budget, EditedChunkRegistry,
# VoxelGravityManager (carved support won't trigger falling scans), AND
# MP routing (clients no-op, host doesn't broadcast).
var tool := voxel_terrain.get_voxel_tool()
tool.do_sphere(world_pos, radius)

# RIGHT — public queue_* functions handle NoEditZone gate, async queueing,
# registry tracking, LOD-bake invalidation, edit_applied emission, and
# MP-3 RPC routing (clients forward to host; host validates + broadcasts).
VoxelEditManager.queue_edit_sphere(world_pos, radius, voxel_value)
# Returns false if NoEditZone rejected (caller may bark "This place doesn't yield to me.").
```
MP-3 routing lives at the bottom of `VoxelEditManager.gd`. In OFFLINE mode the MP gates short-circuit.

**Skill XP MUST go through `SkillManager.add_xp(skill, amount)`:**
```gdscript
# WRONG — bypasses level-up, perk-point grants, active-perk event dispatch,
# and the level_up signal JournalUI watches.
GameState._skill_levels["sword"] = 50

# WRONG — deprecated domain-prefixed shim.
GameState.add_skill_xp(GameState.SkillDomain.CRAFTING, "mining", 5)

# RIGHT — single entry point.
SkillManager.add_xp("mining", 5.0)

# Dispatch perk-mutable events explicitly:
SkillManager.dispatch("on_voxel_broken", {"skill": "mining", "tool_id": "iron_pickaxe"})
```
Canonical skills in `SkillManager.SKILLS`: `sword`, `throwables`, `bow`, `mining`, `felling`, `excavation`, `demolition`, `lockpicking`, `alchemy`, `smithing`, `vitality`, `speech`.

**UI buttons / sliders need MANUAL `_input` dispatch — `Button.pressed` and `HSlider.value_changed` do NOT fire in this project:**
```gdscript
# WRONG — silently never fires. Dialogic's input subsystem consumes
# InputEventMouseButton globally; layout/anchors/mouse_filter are NOT the cause.
my_button.pressed.connect(_on_pressed)
my_slider.value_changed.connect(_on_slider_changed)

# RIGHT — manual dispatch. Reference impl: PauseMenu._input / _dispatch_click / _hits.
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
Non-negotiable. Implement manual dispatch from the first commit on any new UI. See LESSONS_LEARNED 2026-05-03 + 2026-05-09.

**Other essentials:**
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

**Voxel material lookup — go through the registry, never decode alpha by hand:**
```gdscript
# WRONG — hardcodes the encoding.
var material_id: int = packed_voxel & 0xFF

# RIGHT — registry owns encoding.
var material_id: int = VoxelMaterialRegistry.material_id_from_packed(packed_voxel)
var material: VoxelMaterial = VoxelMaterialRegistry.get_by_id(material_id)
```
Same for writes: `VoxelMaterialRegistry.pack_voxel(mat_id, color)`.

**Water is a `CHANNEL_TYPE` block (id 5), NOT `CHANNEL_DATA5` (since Water Voxel V2, 2026-05-16):**
```gdscript
# Water is now a normal transparent blocky block: CHANNEL_TYPE == 5.
# The terrain VoxelMesherBlocky draws it (model 5 = transparent cube
# wearing water_material.tres). Generator emits it at all LODs.
# Player water queries go through WaterFlowManager.is_position_in_water
# / get_water_level_at (these resolve TYPE-5 → full water).
buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE) == 5  # is this water?
# CHANNEL_DATA5 / WaterByteCodec are LEGACY — only the deferred flow-sim
# rewrite (WaterFlowManager._FLOW_SIM_ENABLED) will use DATA5 again.
# Zylann still reserves DATA0–4 for TYPE/SDF/COLOR/INDICES/WEIGHTS.
```

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

**Some Zylann `VoxelLodTerrain` properties are INT — verify with read-back:**
```gdscript
# WRONG — collision_update_delay is INT; set() truncates 0.1 → 0, then every
# stream-in/out fires a main-thread collision rebuild (100+ ms frame spikes).
terrain.set("collision_update_delay", 0.1)

# RIGHT — pass integer milliseconds, ALWAYS read back.
terrain.set("collision_update_delay", 100)
print("actual=%s" % terrain.get("collision_update_delay"))
```
Generic rule: when configuring `VoxelLodTerrain` programmatically, read the value back. Some properties also clamp silently (`mesh_block_size = 32` was clamped to 16 in some scenes until verified). Bootstraps print readbacks as policy.

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
Categories: `WORLD`, `WATER`, `WEATHER`, `PHYS`, `OTHER`. Wrappers add ~1 µs. `Performance.TIME_PROCESS` correlates with `worst_ms` but doesn't attribute by script.

**Profiler overlay (F3):** `Tab` cycle pages, `P` pause, `C` capture JSON (auto-wipes prior; one file at most in `user://`), `S` save, `Q` clear, `← →` timeline cursor. Keyboard-only because `Button.pressed` doesn't fire.

**Water diagnostics (`WaterDiag` autoload — F4/F5/F6):** the standing tool for all water polish — read it before hand-bisecting water with shader tweaks.
- **F4** toggles the on-screen Water panel; while visible it also prints a consolidated `[WaterDiag]` line once/sec (pasteable). Reports in_water/submerged, level, queried surface-Y + Δ to player, sea/horizon Y, flow-sim on/off, current shader debug_mode, query µs, expected LOD.
- **F5** one-shot `[WaterInspect]` dump: 3×3 mesh-block-spaced columns under the camera with water-top voxelY, water count, and **Y-delta vs centre** — equal `top=` across neighbours = coplanar; differing `top=` at the block step = the distant dark-grid LOD-seam mismatch (root-caused 2026-05-17).
- **F6** cycles the water `water.gdshader` `debug_mode` live: **0** normal · **1** depth_t (white=deep) · **2** fresnel · **3** thickness (opaque grey, no blend) · **4** surface-facing (white=up-facing top, black=vertical side/riser). These four are permanent diagnostics — do not remove them. Full recipes in `design/PROFILER_AND_DIAGNOSTICS.md`.

**Profiler capture path:** `C:\Users\Matt Noles\AppData\Roaming\Godot\app_userdata\Game One\profile_capture_<msec>.json`. JSON includes per-frame `attribution`, `engine` (proc_us/real_us/draws/prims/vram_mb), `zylann` (detect_us/io_us/mesh_us/blocked_lods/dropped_loads/dropped_meshs). Capture-from-frame-1 via `scripts/Profiler.gd` `capture_on_startup: true` + `startup_capture_seconds` — **flip back to false after**.

**Diagnostic workflow:** if the user pastes a capture JSON path + `[PERF]` / `[DIAG]` log lines, that's a complete packet. Use the recipes in `design/PROFILER_AND_DIAGNOSTICS.md` to correlate JSON spikes with `[PERF] worst=` and `[DIAG] time_detect_required_blocks=`, then propose ONE specific change.

**Zylann blocky-library properties: use the methods, NOT `.set()`, AND re-apply at runtime:**
```gdscript
# WRONG — silently no-ops. The property name appears in get_property_list()
# but Zylann routes actual storage through method pairs; .set() writes to a
# virtual bag the gdextension only reads for serialization. Result: all-white
# terrain with full-atlas UVs.
model.set("tile_top", Vector2i(2, 0))
model.set("material_override_0", atlas_mat)

# RIGHT — call the method.
model.call("set_tile", 3, Vector2i(2, 0))   # 3 = SIDE_POSITIVE_Y
model.call("set_material_override", 0, atlas_mat)
```
And: even with the methods, values WRITE to `.tres` but DO NOT RESTORE on load. **Re-apply at runtime** (see `World3DBootstrap._inject_atlas_materials_into_library`). The `.tres` is a build artifact; the bootstrap is source of truth. SIDE enum: NEG_X=0, POS_X=1, NEG_Y=2, POS_Y=3, NEG_Z=4, POS_Z=5.

**`VoxelLodTerrain.material` overrides every per-cube `material_override_0`** — leave it null when using textured cube models. Per-cube material_override_0 (set by `World3DBootstrap`) drives rendering.

**Probe a gdextension class before guessing its API:** write a probe EditorScript that prints `get_property_list()` AND `get_method_list()`. Property lists alone mislead — Zylann's `VoxelBlockyModelCube` exposes `tile_top` as a listed property but storage routes through `set_tile()`. See `tools/probe_zylann_blocky.gd`.

---

## Critical scene hierarchies

Load-bearing — scripts use hardcoded `$NodeName` references.

**Player3D / CameraRig:**
```
Player3D (CharacterBody3D + Player3D.gd)
└── CameraTarget (Node3D)
    └── SpringArm3D (+ CameraRig.gd)
        └── Camera3D
```
CameraRig walks `get_parent().get_parent()` to reach the CharacterBody3D. Don't add wrapper nodes.

Two camera modes: **Standard** (mouse rotates Player3D body — W always toward camera) and **Freelook** (hold `freelook_camera`, default F2 — orbits arm without rotating Roland; re-centers on release).

**NPC (NPC.gd):**
```
NPCNode (CharacterBody3D + NPC.gd)
├── MeshInstance3D
├── CollisionShape3D
├── BarkArea (Area3D)          ← must be named exactly "BarkArea"
│   └── CollisionShape3D
└── InteractArea (Area3D)      ← must be named exactly "InteractArea"
    └── CollisionShape3D
```
Assign an `NPCData` resource from `/assets/npcs/` in the Inspector. Tier 0 background NPCs are plain Node3D, no NPC.gd.

**VoxelLodTerrain (World3D.tscn):**
```
World3D (Node3D)
├── VoxelLodTerrain
│   ├── generator: VoxelGeneratorScript (CubicHeightmapGeneratorAdapter.gd)
│   │   └── cpp_impl: CubicHeightmapGeneratorCpp
│   ├── stream: VoxelStreamSQLite
│   └── mesher: VoxelMesherBlocky
├── VoxelViewer (child of Player3D)
├── EntityStreamer
└── ...
```

**NoEditZone authoring (settlement / interior):**
```
SettlementRoot (Node3D)
├── NoEditZone (Area3D, group: "no_edit_zone")
│   └── CollisionShape3D (Box/Convex, ~50–100m buffer)
├── BuildingProp (MeshInstance3D — MagicaVoxel .glb)
└── ...
```
Every settlement, dungeon entrance, and lore landmark sits under a NoEditZone. Writes inside are silently rejected and trigger Roland's bark *"This place doesn't yield to me."*

---

## Autoload registration status

Registered in `project.godot`, in load order:
`GameState`, `Colors`, `TransitionManager`, `SaveNotification`, `PauseMenu`, `NetTransport`, `MultiplayerManager`, `DebugOverlay`, `FlagScheduler`, `InventoryManager`, `PerkRegistry`, `FactionManager`, `VoxelMaterialRegistry`, `SkillManager`, `JournalUI`, `HUDOverlay`, `Profiler`, `ProfilerOverlay`, `NoEditZoneRegistry`, `VoxelEditManager`, `VoxelGravityManager`, `WaterFlowManager`, `Dialogic`, `SpeechCheckBroker`, `BarkManager`, `WorldClock`, `WeatherManager`, `BloodVFX`, `WaterDiag`.

Key facts:
- **MultiplayerManager:** owns SceneTree's `multiplayer_peer`. **In OFFLINE mode `is_host()` returns true** so single-player authority gates work without modification. `PlayerSpawner` (not autoloaded; attached to dev/world scenes) parents one `RemotePlayer.tscn` per non-local peer. Local Player3D stays full-fat with `_can_take_input()` gating.
- **VoxelEditManager + WaterFlowManager** are MP-aware: VEM clients forward via 3 RPCs (`_rpc_request_edit` / `_rpc_replicate_edit` / `_rpc_edit_rejected`), host validates + broadcasts, 60 req/s per-peer rate limit. WFM `_physics_process` early-returns if not host; water byte changes ride VEM replication.
- **SkillManager** is the single entry point for XP grants, perk picks, Legendary reset, active-perk event dispatch. `PerkRegistry` walks `assets/skills/perks/` at startup (300 PerkData). `FactionManager.is_friendly(faction)` is the `≥75` gate trainers use. `SpeechCheckBroker` presents KCD2 visible-but-greyed Speech modal (also handles Dialogic Signal events `speech_check:DC:success:fail`).
- **Colors** + **UIStyles** — `Colors` (`assets/ui/Colors.gd`) is single source of truth for the Voxelmark palette (oak/parchment/iron/gold/HP/STAM + 5 rarity tiers). `UIStyles` (`assets/ui/UIStyles.gd`, `RefCounted`, not autoloaded — `UIStyles.foo()`) builds StyleBox/FontVariation from those constants. CSS source-of-truth: `assets/ui/css/menus_shared.css`.
- **JournalUI** autoload points at the **scene** `res://scenes/ui/Journal.tscn`, not the script directly.

**Load-order rules to preserve:**
- `NetTransport` before `MultiplayerManager` (MM resolves NetTransport in `_ready`).
- `MultiplayerManager` before gameplay autoloads that read its API in `_ready` (today: `WaterFlowManager`).
- `Colors` before any UI autoload (`PauseMenu`, `HUDOverlay`, `JournalUI` reference `Colors.*` in `_ready`).
- `InventoryManager` before `VoxelMaterialRegistry` (registry validates `yield_item_id` against `ITEM_REGISTRY`).
- `VoxelMaterialRegistry` before `VoxelEditManager` (EditToolHandler queries on every swing).
- `NoEditZoneRegistry` before `VoxelEditManager` (manager queries on every edit).
- `VoxelEditManager` before `VoxelGravityManager` (subscribes to `edit_applied` in `_ready`).
- `VoxelEditManager` + `NoEditZoneRegistry` before `WaterFlowManager` (subscribes + queries every flow tick).
- `WorldClock` before `WeatherManager` (subscribes to `hour_changed`).
- `WaterFlowManager` before `WeatherManager` (pushes wind into water shader every frame).

**NOT yet registered (add in Project Settings → Autoload when those land):**
- `scripts/SchematicLibrary.gd` → `SchematicLibrary` (built when player construction lands).

Scripts that reference unregistered autoloads must guard with `get_node_or_null`.

### Dev-scene group convention

Dev test scenes opt out of gameplay UI via:
```gdscript
add_to_group("dev_scene")
```
**HUDOverlay, PauseMenu, JournalUI, SaveNotification** check `GameState.is_dev_scene()` and stay dormant. Other autoloads (TransitionManager, Settings, DebugOverlay, voxel/water/weather) keep running. Add the group call to any new dev scene's bootstrap `_ready()`.

---
