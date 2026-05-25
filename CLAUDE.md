# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Game One — Project Bible

## What I'm building
A 3D voxel narrative RPG — Veloren meets Skyrim in atmosphere and open-world scale. Real-time action combat (Witcher 3 / Dark Souls style), 1-vs-many, first + third-person cameras, co-op multiplayer for 1-4 friends. Voxel world in Godot 4.6.2 with Zylann's Voxel Tools. **Renderer: Forward+ on desktop** (migrated 2026-05-13; `rendering_method.mobile` stays Compatibility). GDScript is the default for UI / glue / signals / one-shot setup; **C++ GDExtension is the perf escape hatch and is used proactively wherever it would meaningfully improve performance — don't wait for a profiler to mandate it.** The per-block voxel generator is the canonical port. Game one of a planned trilogy adapted from a 200-page source manuscript.

**Engine:** 3D voxel since 2026-04-30 (pivoted from 2D pixel art). Full migration plan in `design/3D_VOXEL_MIGRATION.md`.

## My background
I am a writer and game designer, not a programmer. Explain code in plain English before writing it. Keep scripts heavily commented. Prefer simple, readable solutions.

## Genre and tone
Epic fantasy, grounded emotional stakes — LOTR scale, single-protagonist intimacy. World is Mira-Thal, third age. See `lore/WORLD.md` + `lore/INDEX.md`.

## Core systems
- Player: CharacterBody3D, 8-dir XZ movement
- World: VoxelLodTerrain (Zylann) + MagicaVoxel props
- Camera: SpringArm3D over-shoulder, ~15° elevation, free-aim (no lock-on; pure mouse-driven facing per the Bannerlord-style combat in PR #239)
- Dialogue: Dialogic 2 plugin
- Combat: real-time action in-world (Hades style), 1-vs-many
- Game state: GameState.gd autoload
- Transitions: TransitionManager autoload
- Audio: AudioManager.gd autoload — positional SFX (footsteps, dig, water, weather, fire); music + full design in `design/AUDIO_DESIGN.md`

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
Read `git log` for detail. One-line summaries; design-doc pointers carry the depth.

- **2026-04-30 (PR #43):** 2D → 3D voxel pivot. See `design/3D_VOXEL_MIGRATION.md`.
- **2026-05-03–11:** destructible voxel slice + Copper Isles demo + textured `VoxelMesherBlocky` tileset + six tiered voxel-generation rules + Voxel Combat v1 (Enemy3D/Goblin/ThrowableSpear/BloodVFX) + cubic generator C++ port. **Caveat:** delivered Copper Isles EXR is a single continent, not the lore-spec archipelago — re-source pending.
- **2026-05-12:** Copper Isles generator C++ port; Skill system (PR #201) — 12 skills, 300 perks, trainers, Speech checks; multiplayer MP-1/2/3 (PR #180) — transport, player presence, voxel edit replication.
- **2026-05-13–14:** `HeightmapGeneratorBase` extracted (PR #203); `Profiler` `real_us` reliable (PR #207); WaterChunkMesher C++ port + viewer-offset smoothing + thread-count Settings slider (PR #214).
- **2026-05-16–18 (water — native-fluid pivot):** Water Voxel V2 (PR #217/#222/#224) superseded by engine-native `VoxelBlockyFluid`/`VoxelBlockyModelFluid` (PR #225 closed, native pivot landed). Water = 8 per-level fluid models, `CHANNEL_TYPE` 16–23; `water_chunk_mesher` C++ deleted. Hybrid headless verification harness landed at `tools/headless/`. See `design/WATER_STAGE6_PLAN.md` + `design/WATER_NATIVE_FLUID_GATE0_RESULTS.md`.
- **2026-05-19–20 (PR #232 — underwater experience):** volumetric fog + god rays + back-face deep-water + screen wobble/CA + depth gradient + Minecraft-style instant snap + bubble burst. 18 sub-commits. `UnderwaterFilter.gd` drives env/sun vol-fog params + ripples + depth attenuation. Camera-triggered (not head-triggered). Scene groups: `world_environment`, `sun_light`, `underwater_fog_volume`, `underwater_particulates`, `underwater_bubble_burst`. Phase 4b–4f shader work deferred. See `design/WATER_SHADER_V3_PLAN.md`.
- **2026-05-20 (PR #234 — graphics pass):** AgX tonemap + Adjustments counter-grade, SSAO+SSIL, PSSM 4-split shadows, MSAA 3D 4×. Phase C (normal maps) SHELVED — `bake_tangents` is library-global and breaks runtime-injected fluid models. **Any future per-pixel surface detail must use a tangent-free custom `ShaderMaterial` with `dFdx/dFdy` or triplanar bump — never flip `bake_tangents`.** See `design/GRAPHICS_PASS_2026-05-19.md`.
- **2026-05-21 (audio/SFX system):** `AudioManager` autoload — single SFX API `play(id, world_pos)` / `play_loop(id) -> handle`, id-prefix folder + bus routing, no-op-safe until files are curated. 548 raw takes committed across 5 categories. Combat SFX (Cat 02) pending next billing cycle. See `design/SFX_LIBRARY.md` + `SFX_PROMPTS.md`.
- **2026-05-22 (PR #235 — graphics Phases F/H/K):** `GraphicsManager` autoload with POTATO/LOW/MEDIUM/HIGH/ULTRA tiers (HIGH = shipped look); procedural FBM clouds in `assets/shaders/sky_atmosphere.gdshader` with per-`WeatherManager`-state coverage; night-sky (procedural stars, aurora, nebula) + bright-night-sky fog-albedo fix in `DayNightCycle`. See `design/GRAPHICS_PASS_2026-05-19.md`.
- **2026-05-22 (graphics Phases G/I/J):** `AtmosphereProfile.gd` (Resource — 16 TOD anchors) for `DayNightCycle`; `assets/shaders/terrain_voxel.gdshader` (tangent-free per-pixel relief, no `bake_tangents` flip); `EmissiveLightManager` autoload casts coloured `OmniLight3D`s from emissive voxels (real lights via Forward+ clustered renderer, NOT a 3D-texture floodfill). See `design/GRAPHICS_PASS_2026-05-19.md`.
- **2026-05-25 (Directional Melee v1, PR #239):** Bannerlord-style directional combat. `MeleeHandler.gd` hold-flick-release with `MouseDirectionSampler` (4 quadrants ±50°, DIR_NONE sentinel; mouse-flick UP=THRUST, DOWN=OVERHEAD), direction-lock during hold + auto-alternating LRLR on no-flick, charged 2× damage, feint cancel. RMB tap=parry (300 ms, riposte sweep) / hold=directional block (matched=0 dmg, mismatched=60% chip — `is_blocking_against` consulted from `EnemyAttackPool._perform_strike`); `auto_block` difficulty toggle. `ParryChainTracker` decays 1.0→0.7→0.5 s. `EnemyAttackPool` composed into Goblin (READY/WINDUP/STRIKE/RECOVERY/STAGGERED, weighted pool, yellow/red telegraph). `Enemy3D` gains `state_changed` + `committed_attack` signals + `stagger(duration)`. Sword+shield loadout with `offhand` slot. HUD: `HUDDirectionArrows` + `HUDCombatRadar`. **Lock-on prototyped + removed within the PR** — pure free-aim is the 1-vs-many depth axis. See `design/COMBAT_NEXT_PHASES.md`.

Outstanding pickups: Blender Roland model, MagicaVoxel prop exports, surface decoration pass, ambient weather audio, region-boundary profile auto-swap. See `DESIGNER_TODO.md`.

## Art specification (3D VOXEL)
- **Voxel scale:** 6 voxels/m (locked 2026-05-03; ~16.7 cm/block, player ~11 voxels tall).
- **Terrain:** `VoxelLodTerrain` + `VoxelMesherBlocky` reading `CHANNEL_TYPE` (8-bit material id) backed by `VoxelBlockyLibrary`. Procedural baseline from `CubicHeightmapGenerator`. Atlas at `assets/voxels/texture_packs/default/` — 16 px tile × 64 cols (1024×1024). **Destructible by default**; `NoEditZone` Area3D volumes are the exception. Edits stored as deltas in `VoxelStreamSQLite`.
- **World scale:** Mira 12 km × 10 km (compression 125:1). Thal ~7 km × 5.5 km.
- **Props/buildings:** MagicaVoxel → .glb. Narratively load-bearing structures sit inside NoEditZones.
- **Player-built:** schematic props (Carpentry Bench) + per-voxel Build Mode.
- **Characters:** Blender low-poly .glb (200–500 tris). Portraits unchanged for dialogue.
- **Camera:** SpringArm3D over-shoulder, ~15° elevation, free-aim (no lock-on).
- **Lighting:** OmniLight3D + DirectionalLight3D + WorldEnvironment SSAO + fog.
- **Canonical refs:** `design/3D_VOXEL_MIGRATION.md`, `design/ART_PIPELINE.md`, `design/ART_DIRECTION.md`.

## What I never want
- Systems built before I need them.
- C# — never. GDScript is the default for non-perf code; C++ GDExtension is the perf escape hatch and should be used **proactively** wherever it would meaningfully improve performance, not gated behind a profiler measurement.

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
| design/GRAPHICS_PASS_2026-05-19.md | A graphics phase ships, a roadmap item (F+) completes or shifts, a deferred follow-up resolves |
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
| design/CPP_EXTENSION_PORT_QUEUE.md | New tier ported, new POD field, new C++ Resource, parity harness extended |
| design/PROFILER_AND_DIAGNOSTICS.md | New autoload wrapped, new category, new diagnostic pattern, capture-JSON schema |
| design/GDSCRIPT_PATTERNS.md | New project-specific gotcha discovered or worked around |
| design/SCENE_HIERARCHIES.md | Player3D / Enemy3D / VoxelLodTerrain hierarchies change in load-bearing ways |
| tools/headless/README.md | New harness selector added, scope of headless verification shifts |
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
- **Planning & ops:** MILESTONE_ROADMAP, ENDGAME_CHOICES, DIALOGIC_SETUP, TTS_PIPELINE, LESSONS_LEARNED, PROFILER_AND_DIAGNOSTICS, COPPER_ISLES_DEMO_HEIGHTMAP, COPPER_ISLES_BAKE_NOTES, WATER_STAGE6_PLAN (native-fluid pivot decision record), WATER_NATIVE_FLUID_GATE0_RESULTS (frozen probe results), WATER_SHADER_V3_PLAN (current shader spec + Phase 4b–4f deferred items).

`design/PROFILER_AND_DIAGNOSTICS.md` — **read this before guessing at perf issues**; the answer is usually in a recent capture.

## Current project state

Godot 4.6.2. 3D pivot complete. Open world plan confirmed: VoxelLodTerrain streaming, editable/destructible terrain by default, edits as deltas in `VoxelStreamSQLite`, NoEditZones protect settlements/landmarks, 12km × 10km Mira, third-person over-shoulder, low-poly Blender characters.

System design corpus complete (combat, AI, companions, factions, quests, economy, save, death, weather, HUD, input, accessibility, audio, navigation, lockpicking, destructible terrain — all in `/design`). Pipeline tooling in `tools/README.md` (requires `ELEVENLABS_API_KEY`).

**2D legacy on disk (retiring as 3D replaces):** `Player.gd`, `CampfireFlicker.gd`, `DialogueTrigger.gd`, `CombatTrigger.gd`, `Combat.gd`; `Player.tscn`, `World.tscn`, `Combat.tscn`.

**3D core in place:** `Player3D` (8-dir XZ + sprint/crouch + HP/endurance + `_melee_hyperarmor`), `CameraRig` (SpringArm3D over-shoulder + freelook F2 + zoom; **free-aim, no lock-on**), `HUDOverlay`, `JournalUI` (6-tab scene at `scenes/ui/Journal.tscn`), `CampfireFlicker3D`, `SpawnPoint3D` / `RoomTrigger3D` / `DialogueTrigger3D`, `World3D.tscn`, `World3DBootstrap.gd` (**all world-load wiring goes here**), `VoxelDrop.gd` (RigidBody3D pickup), `CopperIslesHeightmapGenerator.gd` (now C++ via adapter), `CopperIslesTestBootstrap.gd`, `HorizonSkirt.gd`.

**NPCs:** `NPC.gd` (Tier 1–3 base; bark + E-press dialogue + disposition + schedule), `NPCData.gd` (Resource: npc_id, Tier, disposition, barks, schedule), `NPCScheduleEntry.gd`.

**Combat v1 (Voxel + Directional Melee, May 2026):**
- `Enemy3D.gd` (base — IDLE/ALERT/COMBAT detection, `take_damage`, `die`, corpse loot, `state_changed` + `committed_attack` signals, `stagger(duration)`, `_contact_damage_suppressed`).
- `enemies/Goblin.gd` + composed `enemies/EnemyAttackPool.gd` (directional windups with yellow/red telegraphs; weighted attack pool jab/swing/leap).
- `MeleeHandler.gd` (LMB owner when `melee_weapon` equipped — hold-flick-release with `combat/MouseDirectionSampler.gd` (DIR_OVERHEAD/LEFT/RIGHT/THRUST/NONE), direction-lock during hold, auto-alternate LRLR on no flick, charged 2× damage, feint cancel, 3-stage sword tween; RMB parry tap / block hold; `is_blocking_against(dir)` API, `auto_block` flag; `combat/ParryChainTracker.gd` decaying chain refunds; riposte sweep).
- `throwables/ThrowableSpear.gd` (synchronous damage + `call_deferred` for freeze/reparent — Godot forbids those inside `body_entered`).
- `BloodVFX.gd` autoload (burst/dust/drip/pool — `Decal` on Forward+).
- HUD: `HUDDirectionArrows.gd` (over-head TTI-scaled arrows + screen-edge clamp) + `HUDCombatRadar.gd` (alert-state dots + bearing arc to closest committed attacker).
- Loadout: `iron_sword` (`melee_weapon`) + `iron_shield` (`shield`) registered in `InventoryManager.ITEM_REGISTRY`; `offhand` equipment slot.
- Scene: `Player3D.tscn` has `MeleeWeaponPivot`/`SwordVisual`/`MeleeWeaponHitbox` (right hand) + `ShieldPivot`/`ShieldVisual` (left hand); `EditToolHandler` short-circuits on `melee_weapon` / `throwable` equipped.
- Dev arena: `CombatTest.tscn` (3 goblins tight at z=-2 for sweep testing) + `CombatTestBootstrap.gd` debug keys F1/F8/F9/R/K/M/N/B/Q.
- **Lock-on system was removed 2026-05-25.** Pure free-aim. No `LockOnManager`, no MMB cycle, no CameraRig lock-on API.
- See `design/COMBAT_NEXT_PHASES.md` for what's next (v1.1 polish: finishers + audio + Spin-Parry perk + Settings UI; v1.2+: Bannerlord depth — per-weapon reach/speed, hit-zone damage, AI dodge/block).

**Voxel + world (autoloaded):**
- `VoxelEditManager` — async edit queue, NoEditZone gate, EditedChunkRegistry, `WORLD_GENERATOR_VERSION` stamping. **Always route writes through here.** Emits `edit_applied`. MP-aware (host validates + broadcasts; clients forward via RPC).
- `NoEditZoneRegistry` — registers `no_edit_zone` group Area3Ds.
- `CubicHeightmapGeneratorCpp` + `CubicHeightmapGeneratorAdapter.gd` — C++ generator (Mira) since 2026-05-11; adapter forwards `_generate_block` + `set_ore_materials` / `set_disk_materials` / `get_ground_voxel_y_at`.
- `WorldClock` — in-game time (240 real s = 1 game hour). Pauses during Dialogic.
- `BarkManager`, `WaterFlowManager` (flow tick **disabled** since native-fluid pivot — static water only; see `design/SWIMMING_AND_WATER.md`), ~~`WaterChunkMesher`~~ (**DELETED 2026-05-16** — water is now Zylann-native `VoxelBlockyModelFluid` at `CHANNEL_TYPE` ids 16–23 drawn by the terrain mesher; no separate water mesher, no horizon plane; see `design/WATER_STAGE6_PLAN.md` for the pivot record), `WaterByteCodec` (legacy DATA5 layout — only used by the deferred flow rewrite), `UnderwaterFilter` (PR #232 — Minecraft-style instant snap; drives `WorldEnvironment.volumetric_fog_*` + `Sun.light_volumetric_fog_energy` + depth gradient + bubble burst; resolves via groups `world_environment`, `sun_light`, `underwater_fog_volume`, `underwater_particulates`, `underwater_bubble_burst`), `NoEditZone.gd` (`blocks_water_flow=true` default), `DayNightCycle`, `EditToolHandler` (pickaxe/axe/shovel), `ThrowableHandler`, `PowderCharge`, `VoxelGravityManager` (16 m flood-fill on `edit_applied`), `EmissiveLightManager` (Phase J — emissive voxels cast coloured `OmniLight3D`s; edit-driven + periodic-sweep discovery, clustered + streamed around the player), `FallingVoxelCluster` + `VoxelClusterBuilder`, `VoxelMaterial.gd` + `VoxelMaterialRegistry`, `WeatherManager` (six-state, fog/wind/particles/lightning), `RainOverlay`, `WeatherLocationProfile`, `WeatherZone`.

**Dev tools (`scripts/_dev/`, `scenes/_dev/`):** `WorldBakeController` + `BakeWorld.tscn` (Copper Isles) + `BakeWorld3D.tscn` (Mira); `SkirtBaker`; `ParityProbe` (C++ math primitive parity shim, retained for next port); `CombatTestBootstrap` + `CombatTest.tscn`.

**Specified but not yet implemented:** Combat next phases (see COMBAT_NEXT_PHASES.md), `SchematicLibrary` autoload (player construction), `EntityRegistry` + `EntityStreamer` (stub on disk — only prints chunk-enter events; full logic deferred to Phase 6-3D), `QuestManager`, `CompanionManager`, LOD-bake-on-eviction caching (deferred until perf demands).

Manual setup still required: see `DESIGNER_TODO.md` Section 1.

---

## C++ GDExtension perf opportunities

C++ GDExtension at `extensions/voxel_gen/` is used **proactively** for any CPU work that benefits from native speed — voxel BFS/floodfills, per-frame grid math, large data marshalling, anything iterating thousands+ of items per frame. GDScript stays the default for UI, glue, signals, scene bootstrap, one-shot setup.

**Done:** `CubicHeightmapGeneratorCpp`, `CopperIslesHeightmapGeneratorCpp`, `HeightmapGeneratorBase` (PR #203), `WaterChunkMesherCpp` (PR #214).

Build, port pattern, payoff-ordered backlog, process for new ports, and "NOT worth porting" list: `design/CPP_EXTENSION_PORT_QUEUE.md`.

---

## Godot workflow

No CLI build / lint / test. Verify changes by opening Godot 4.6.2 and running the relevant scene:

- `World3D.tscn` — Mira (C++ generator via adapter)
- `CopperIslesTest.tscn` — Copper Isles; F7 cycles terrain scale
- `scenes/_dev/BakeWorld.tscn` / `BakeWorld3D.tscn` — UI-driven bake (must run in-game)
- `scenes/_dev/CombatTest.tscn` — directional-melee dev arena (sword+shield pre-equipped; F1 debug menu)

Check the Output panel. C++ extension build: see above. After build, reload Godot. Active C++ ports parity-check via `@tool` harness in `scripts/_dev/` (File → Run).

**Headless Godot harness** lives at `tools/headless/runner.gd` + `run.ps1` — data/logic/parity checks only (dummy renderer, no GPU). Selectors: `gate0`, `codec`, `wmat`, `phase2`, `phase7`, `gen`, `shader`, `spike`. Anything visual (shaders, F-key views, perf) still needs the editor. See `tools/headless/README.md`.

---

## Git workflow patterns

- **One fix per branch.** Small, focused branches review and cherry-pick cleanly.
- **One file per commit** for large .tscn / .gd files (avoids stream idle timeouts on push).
- **Cherry-pick over rebase** when a branch has conflicting squash-merged history.
- **Never amend published commits.** If a hook fails, fix it and create a new commit.
- Always push with `git push -u origin <branch-name>`.

---

## Critical GDScript patterns

Four hard rules — violate any of them and the code silently breaks. Longer recipes + voxel/profiler gotchas in `design/GDSCRIPT_PATTERNS.md`.

1. **Player input through `_can_take_input()` (MP-2).** Every `Input.*` site in `Player3D`, `EditToolHandler`, `ThrowableHandler`, `MeleeHandler` must guard with this. Returns true when `MultiplayerManager.is_offline()` OR `get_multiplayer_authority() == multiplayer.get_unique_id()`. Without the guard, remote replicas consume your local keyboard.
2. **Voxel edits through `VoxelEditManager.queue_*` — never raw `VoxelTool`.** Bypassing the queue skips the `NoEditZone` gate, async budget, `EditedChunkRegistry`, `VoxelGravityManager` flood-fill on carve, AND multiplayer routing.
3. **Skill XP through `SkillManager.add_xp(skill, amount)`** — never `GameState._skill_levels[...]` direct, never the deprecated `add_skill_xp(domain, sub_skill, amount)` shim. Single entry point owns level-ups, perk-point grants, active-perk dispatch, and the `level_up` signal `JournalUI` watches. Canonical skills: `sword`, `throwables`, `bow`, `mining`, `felling`, `excavation`, `demolition`, `lockpicking`, `alchemy`, `smithing`, `vitality`, `speech`.
4. **UI buttons / sliders need manual `_input` dispatch.** `Button.pressed` and `HSlider.value_changed` don't fire — Dialogic's input subsystem consumes `InputEventMouseButton` globally. Reference impl: `PauseMenu._input / _dispatch_click / _hits`. Recipe in `design/GDSCRIPT_PATTERNS.md`.

**Recipes + project-specific gotchas** (voxel material registry, Zylann fluid water, `VoxelBuffer CHANNEL_COLOR` 32-bit setup, `_generate_block` thread safety, `Dictionary[int, PackedByteArray]` mutation, Zylann `VoxelLodTerrain` INT property quirks, Zylann blocky-library `set_tile()` vs `.set()`, profiler attribution + diagnostics, F3/F4/F5/F6 overlays): see `design/GDSCRIPT_PATTERNS.md`.

---

## Critical scene hierarchies

Load-bearing — scripts use hardcoded `$NodeName` references. Don't reorganise without updating consumers. Full hierarchies + load-bearing notes for Player3D / NPC / Enemy3D+Goblin / VoxelLodTerrain / NoEditZone in `design/SCENE_HIERARCHIES.md`.

**One thing to keep in your head:** `CameraRig` walks `get_parent().get_parent()` from the `SpringArm3D` to reach the `CharacterBody3D` — don't add wrapper nodes between them.

---

## Autoload registration status

Registered in `project.godot`, in load order:
`GameState`, `Colors`, `TransitionManager`, `SaveNotification`, `PauseMenu`, `NetTransport`, `MultiplayerManager`, `GraphicsManager`, `Settings`, `DebugOverlay`, `FlagScheduler`, `InventoryManager`, `PerkRegistry`, `FactionManager`, `VoxelMaterialRegistry`, `SkillManager`, `JournalUI`, `HUDOverlay`, `Profiler`, `ProfilerOverlay`, `AudioManager`, `NoEditZoneRegistry`, `VoxelEditManager`, `VoxelGravityManager`, `EmissiveLightManager`, `WaterFlowManager`, `Dialogic`, `SpeechCheckBroker`, `BarkManager`, `WorldClock`, `WeatherManager`, `BloodVFX`, `WaterDiag`.

Key facts:
- **MultiplayerManager:** owns SceneTree's `multiplayer_peer`. **In OFFLINE mode `is_host()` returns true** so single-player authority gates work without modification. `PlayerSpawner` (not autoloaded; attached to dev/world scenes) parents one `RemotePlayer.tscn` per non-local peer. Local Player3D stays full-fat with `_can_take_input()` gating.
- **VoxelEditManager + WaterFlowManager** are MP-aware: VEM clients forward via 3 RPCs (`_rpc_request_edit` / `_rpc_replicate_edit` / `_rpc_edit_rejected`), host validates + broadcasts, 60 req/s per-peer rate limit. WFM `_physics_process` early-returns if not host; water byte changes ride VEM replication.
- **SkillManager** is the single entry point for XP grants, perk picks, Legendary reset, active-perk event dispatch. `PerkRegistry` walks `assets/skills/perks/` at startup (300 PerkData). `FactionManager.is_friendly(faction)` is the `≥75` gate trainers use. `SpeechCheckBroker` presents KCD2 visible-but-greyed Speech modal (also handles Dialogic Signal events `speech_check:DC:success:fail`).
- **Colors** + **UIStyles** — `Colors` (`assets/ui/Colors.gd`) is single source of truth for the Voxelmark palette (oak/parchment/iron/gold/HP/STAM + 5 rarity tiers). `UIStyles` (`assets/ui/UIStyles.gd`, `RefCounted`, not autoloaded — `UIStyles.foo()`) builds StyleBox/FontVariation from those constants. CSS source-of-truth: `assets/ui/css/menus_shared.css`.
- **JournalUI** autoload points at the **scene** `res://scenes/ui/Journal.tscn`, not the script directly.
- **AudioManager:** single SFX entry point — `play(id, world_pos)` / `play_loop(id) -> handle` / `stop_loop(handle)`. Resolves `assets/audio/sfx/<folder>/<id>[.ogg|_NN.ogg]`, random-picks variations, routes to the SFX bus by id-prefix, applies per-trigger pitch/volume jitter on one-shots, and **no-ops with a single warning until the file is placed** — so call sites can be wired before assets are curated. Subscribes to `WeatherManager` / `VoxelEditManager` signals **deferred + guarded**, so its early load slot (right after `ProfilerOverlay`, before those managers) is safe.
- **GraphicsManager:** owns the player-facing quality tier (`ShaderProfile` presets POTATO/LOW/MEDIUM/HIGH/ULTRA). Persists to `user://graphics.json`; `apply_current()` pushes the tier into the live `WorldEnvironment` + root `Viewport` + every `DirectionalLight3D`, each step null-guarded so it is menu- and headless-safe. HIGH is the default and mirrors `World3D.tscn` exactly. `World3DBootstrap` calls `apply_current()` at the end of `_ready()`. `ShaderProfile.gd` has no `class_name` on purpose (path-preloaded — headless-harness-safe, same rule as `WaterMaterial.gd`).

**Load-order rules to preserve:**
- `NetTransport` before `MultiplayerManager` (MM resolves NetTransport in `_ready`).
- `MultiplayerManager` before gameplay autoloads that read its API in `_ready` (today: `WaterFlowManager`).
- `Colors` before any UI autoload (`PauseMenu`, `HUDOverlay`, `JournalUI` reference `Colors.*` in `_ready`).
- `InventoryManager` before `VoxelMaterialRegistry` (registry validates `yield_item_id` against `ITEM_REGISTRY`).
- `VoxelMaterialRegistry` before `VoxelEditManager` (EditToolHandler queries on every swing).
- `NoEditZoneRegistry` before `VoxelEditManager` (manager queries on every edit).
- `VoxelEditManager` before `VoxelGravityManager` (subscribes to `edit_applied` in `_ready`).
- `VoxelEditManager` + `VoxelMaterialRegistry` before `EmissiveLightManager` (connects to `edit_applied` and reads the emissive-material set in `_ready`).
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
