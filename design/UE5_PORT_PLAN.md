# UE5 Port Plan — Mira-Thal (Godot 4.6 → Unreal Engine 5)

**Status:** PROPOSED (planning only — no engine work started). This is a strategy/scoping document,
not a record of shipped work. Claude Code is the intended lead developer for the port.

**Scope note:** This doc lives in the Godot repo as the canonical reference for the port decision and
sequencing. The actual UE5 project would live in a separate repository/module tree.

---

## Context

Mira-Thal is a production-grade 3D voxel narrative RPG built in Godot 4.6.2 (Veloren + Skyrim
atmosphere, LOTR-scale fantasy, game one of a planned trilogy from a 200-page manuscript). Today it
runs on Zylann Voxel Tools at **10 voxels/meter (10cm cubes)** with a mature feature set: fully
destructible terrain, native finite-volume water sim, biome-driven generation seeded by Gaea
heightmaps, voxel gravity/sever physics, directional melee combat, 12 skills × 300 perks, entity
streaming, a dormant host-authoritative multiplayer stack, weather, baked emissive lighting,
Dialogic dialogue + an ElevenLabs TTS pipeline. ~40k lines of GDScript across 232 files, ~1,350
lines of perf-critical C++ in a GDExtension, 28 scenes, 11 shaders, 338 `.tres` data assets.

**Why port:** Godot's renderer caps the visual ceiling. UE5's Nanite, Lumen, Niagara, Chaos
physics, and built-in dedicated-server replication let Mira-Thal hit the photoreal "voxel cube +
Skyrim atmosphere" target and a robust multiplayer foundation that the current engine can't reach.

**Decisions locked with the designer:**
- **Voxel tech:** Voxel Plugin Pro (Phyronnaz) — fastest path to a destructible runtime-editable world; we write gameplay C++ on its API.
- **Aesthetic:** True blocky 10cm cubes (crisp cubic faces, not smoothed/marching-cubes).
- **Code split:** C++-first for systems; Blueprints only for designer tuning, UI, VFX wiring. Mirrors the current GDScript+GDExtension discipline.
- **Sequencing:** Vertical slice first — prove the core loop end-to-end before porting all 12 skills / 300 perks / weather / dialogue.

**Intended outcome:** A UE5 vertical slice that proves the 10cm destructible-cube world under
Nanite/Lumen with mining, water, one enemy, Gaea-seeded terrain, and Chaos physics — then a
staged build-out to feature parity, keeping the gameplay layer engine-agnostic so the
hard-won design (scale discipline, edit routing, water conservation, combat feel) survives the move.

---

## Critical risk to resolve in the slice (read first)

**Nanite + frequently-edited blocky voxels are in tension.** Nanite excels at dense *static*
geometry; it does not love meshes that regenerate every time the player digs. The realistic
rendering split for "true blocky 10cm cubes" is:

- **Near / editable band (Voxel Plugin cubic mesher):** standard greedy-meshed chunk meshes with
  Lumen lighting + a triplanar material atlas. This is where mining/water/destruction live. **Not Nanite.**
- **Far / static band:** Nanite for baked distant terrain skirt, static props (trees that aren't
  being chopped, rocks, structures), and set dressing. Nanite + Lumen carry the photoreal horizon.
- **Lumen everywhere:** dynamic GI + reflections on both bands; this is the single biggest visual
  win over Godot and works regardless of the cube/Nanite split.

The slice must **measure** dig-edit mesh-rebuild cost at 10cm under Lumen before we commit the full
port. If cubic-mesh + Lumen can't hold framerate during heavy carving, the fallback is "cubes near,
smooth far" — so we keep the rendering layer swappable.

> **Full rendering decision record:** `design/UE5_RENDERING_STRATEGY.md` expands this into the chosen
> hybrid — mesh-near / ray-march-far / Nanite-cold-chunks over a shared GPU brickmap, the GPU-offload
> plan (compute meshing + GPU generation), and the Phase 0 perf-gate spikes (A–D) with pass criteria.

---

## Target UE5 architecture (maps Godot → UE5)

| Godot construct | UE5 equivalent | Notes |
|---|---|---|
| Autoload singletons (24) | `UGameInstanceSubsystem` / `UWorldSubsystem` per manager | Load order → subsystem dependency + explicit init; signals → delegates |
| GDScript gameplay | UE5 **C++** classes | `UObject`/`AActor`/`UActorComponent` |
| `_can_take_input()` gate | `Role == ROLE_AutonomousProxy` / `IsLocallyControlled()` | UE replication gives this for free |
| Zylann VoxelLodTerrain | **Voxel Plugin Pro** `AVoxelWorld` (cubic mesher) | Runtime edit + LOD + collision built-in |
| `voxel_gen` GDExtension (gen/gravity/water/biome/emissive) | UE5 C++ inside our voxel module | Pure logic ports nearly 1:1 |
| `VoxelEditManager` (single write gateway + async budget + NoEditZone + MP RPC) | `UVoxelEditSubsystem` wrapping Voxel Plugin's edit API | Keep the single-gateway discipline; MP via UE RPCs |
| `VoxelScale.gd` (10 vox/m SSOT) | `UVoxelScaleSettings` (`UDeveloperSettings`) | Single source of truth, config-exposed |
| Material ids 1–28 (terrain/water/flora/detail) | `UDataAsset` registry + material-index table | Triplanar atlas material; keep id ranges (water 16–23, flora 24–26, detail 27–28) |
| Finite water sim (`FiniteWaterCore` ledger + `WaterByteCodec`) | C++ `FFiniteWaterCore` in voxel module | Pure, SceneTree-free already → ports cleanly; render via custom water surface material |
| Voxel gravity/sever (`VoxelGravityCpp`, `FallingVoxelCluster`) | C++ flood-fill + **Chaos** rigid clusters | Chaos replaces Godot RigidBody3D |
| Combat (MeleeHandler, EnemyAttackPool, ParryChainTracker, MouseDirectionSampler) | C++ `UActorComponent`s on player/enemy pawns | State machines port directly; free-aim, no lock-on |
| Skills/XP (`SkillManager`, 300 perks `.tres`) | `USkillSubsystem` + perk **DataAssets** (or GAS — see open question) | Data-driven; perks regenerated as DataAssets via ported Python tool |
| Entity streaming (4-tier AI demotion, chunk-ring) | `UEntityStreamSubsystem` + significance-based ticking | UE Significance Manager fits the ACTIVE/AWAKE/SLEEPING/OFFLOADED tiers |
| Multiplayer (NetTransport/MultiplayerManager, host-authoritative) | UE **dedicated-server replication** + Online Subsystem (Steam) | Far stronger than the dormant Godot stack; rebuild on UE replication, reuse the authority *design* |
| Weather/DayNight (`WeatherManager`) | C++ subsystem driving Sky Atmosphere + Volumetric Clouds + Niagara | Real sky/cloud/rain systems replace shader fakes |
| Emissive baked light (3D-texture floodfill) | Lumen emissive + (optional) baked volume | Lumen largely obviates the custom bake; keep floodfill only if Lumen emissive is too coarse |
| Far-grass impostors + flora_sway | Niagara / `UHierarchicalInstancedStaticMesh` + World Position Offset wind | Same hash-placement continuity trick |
| Dialogic `.dtl` + barks | Dialogue plugin (open-source) or custom C++ dialogue subsystem + DataTables | Convert `.dtl` mechanically; keep `drafts/*.md` → `scripts/*.txt` TTS pipeline |
| Headless parity harness (25 selectors) | **UE Automation Spec** tests in the voxel module | The parity gates are codec-agnostic — port them; they are our safety net |
| Shaders (`.gdshader`) | UE Material Graph / HLSL Custom nodes | Logic ports; Nanite/Lumen change the framing |

**Portable assets (carry over as-is):** PNG voxel textures + atlas, Gaea `.exr` heightmaps,
`.fbx` models (goblin + anims), `.ogg`/`.wav` audio (548 SFX + music), `.png` portraits/sky,
all 75 lore `.md` + dialogue drafts, the Python tools (logic reusable; re-target output formats).

**Rebuild (Godot-specific):** `.tscn` scenes → UE levels/Blueprints, `.tres` data → UE DataAssets,
`.gdshader` → UE materials, GDScript → C++.

---

## Phase 0 — Foundation & engine-bet de-risking (the vertical slice)

Goal: one biome, end-to-end core loop, proving the engine choices. Everything here is throwaway-tolerant.

1. **Project + module skeleton.** UE 5.x C++ project. Modules: `MiraThalCore` (gameplay),
   `MiraThalVoxel` (generation/water/gravity/edit), `MiraThalNet` (replication helpers). Source
   control + `.gitignore` for `Saved/`, `Intermediate/`, `DerivedDataCache/`.
2. **Voxel scale SSOT.** `UVoxelScaleSettings` (`UDeveloperSettings`) with `VoxelsPerMeter=10`,
   `VoxelSizeM=0.1`, helper conversions. Mirror the never-hardcode discipline from `VoxelScale.gd`.
3. **Voxel Plugin Pro install + cubic world.** Stand up `AVoxelWorld` with the cubic mesher at
   10cm, runtime editing, LOD, collision. Wire a triplanar material from the existing atlas PNG.
4. **Edit gateway.** `UVoxelEditSubsystem` as the *only* write path (sphere/box/single, async
   budget, NoEditZone hook, edit-applied delegate) — the `VoxelEditManager` contract, on UE.
5. **Gaea-seeded generation.** Port `CubicHeightmapGeneratorCpp` + `BiomeFieldCpp` logic into
   `MiraThalVoxel` as the world generator; import one Gaea `.exr` (Copper Isles) as the heightmap
   source. One biome only (rolling hills) with material banding + flora ids.
6. **Mining loop + the dig-under-Lumen perf gate.** Port `EditToolHandler` carve math
   (physical-volume anchor, S/M/F presets, destroy preview, D2 wall-grain). Then run the perf gate —
   this is the engine-bet make-or-break, detailed in `UE5_RENDERING_STRATEGY.md` §6 (targets/budget
   in §5). Each spike is
   isolated and captured with **Unreal Insights** against a target frame budget:
   - **6.0 — Baseline.** Voxel Plugin greedy mesh + Lumen under heavy sustained carving. *Pass:* frame
     holds budget during the worst carve; record mesh-rebuild ms. **This single number gates the port.**
   - **6.A — GPU meshing.** Move re-mesh to a compute pass; re-mesh only the ~3³ affected bricks.
     *Pass:* edit stall drops vs baseline, no visual regression.
   - **6.B — Cold→Nanite bake.** Bake unedited near chunks to Nanite static meshes; revert to dynamic
     mesh on edit. *Pass:* draw-call/culling win on a static field, bake cost amortizes.
   - **6.C — Ray-marched horizon.** Brickmap + single-pass DDA far band (replaces distant-terrain
     rings/skirt). *Pass:* cheaper than a distant mesh, no seams, far edits free.
   - **6.D — Voxel AO ray-march.** Short DDA rays for AO/contact shadows on the meshed near band.
     *Pass:* look worth the ms, within budget.
   - **Decision rule:** if 6.0 holds the budget, ship the simple path for the slice and treat A–D as
     optimizations; if 6.0 fails, A + C become required; if cubic-mesh + Lumen still can't hold,
     fall back to "cubes near / smooth far" (kept swappable behind the brickmap).
7. **Water slice.** Port `FFiniteWaterCore` + `WaterByteCodec` (pure logic, ports cleanly); render
   one pool/stream with a UE water surface material. Prove volume conservation via a ported test.
8. **Gravity/sever slice.** Port flood-fill connectivity; spawn falling clusters as Chaos rigid
   bodies. One "dig out the support, it falls" demo.
9. **Combat slice.** Port `MeleeHandler` + `MouseDirectionSampler` + `ParryChainTracker` and one
   `Goblin` with `EnemyAttackPool` telegraphs (HUD arrows + radar). Free-aim, no lock-on.
10. **Lighting/atmosphere.** Lumen GI + reflections, Sky Atmosphere + Volumetric Clouds, one
    time-of-day. Nanite on the static distant skirt + a few static props.
11. **Parity harness.** Stand up UE Automation Specs porting the most load-bearing selectors first:
    `scale`, `gen`, `water_flow`/`finite`, `gravity`/`sever`, `flora`. Green = systems match design.

**Slice exit criteria:** walk a Gaea-seeded hill biome under Lumen; dig with S/M/F presets at stable
framerate; water fills a carved pit and conserves volume; undercut terrain falls via Chaos; fight one
goblin with directional melee + parry. If dig-under-Lumen fails the framerate gate, trigger the
"cubes near / smooth far" fallback before Phase 1.

---

## Phase 1 — World systems to parity

Generation: all 5 biomes (`BiomeProfile` → DataAssets), trees (8m lattice, destructible clusters),
flora R4 (ids 24–26) + micro-detail D1 (ids 27–28), ore/disk scatter, distant terrain rings +
Nanite skirt, far-grass impostors (hash-continuity handoff), sky panoramas/time-of-day, full water
(rivers `RiverFlowVolume`, biome water zones, foam D4, underwater filter). Port remaining C++:
`DistantTerrainMesher`, emissive (evaluate Lumen-emissive-only first). Save/load: Voxel Plugin save
format for terrain deltas + JSON sidecars for entities, mirroring `VoxelStreamSQLite` +
`entities.json`.

## Phase 2 — RPG & combat to parity

Full combat (charged/feint, directional block/parry chains, riposte, gibs + time-slow + camera
kick, throwable spear charge/embed/retrieve). Skills: all 12 + 300 perks regenerated as DataAssets
via ported `generate_perks.py`/`wire_active_perks.py`; XP routing subsystem + `CombatXPRouter`.
Entity streaming with UE Significance Manager (4 tiers). Inventory, minigames (lockpicking, dice via
Chaos). Weather subsystem (6 states) driving real sky/cloud/Niagara rain+snow.

## Phase 3 — Narrative & content

Dialogue subsystem (convert `.dtl`, keep speech-check broker + bark system), NPCs + trainers +
disposition/faction flags, portraits, TTS pipeline re-targeted to UE audio import, all lore wired.

## Phase 4 — Multiplayer

Rebuild on UE dedicated-server replication (reuse the authority *design*, not the Godot code):
host/server-authoritative voxel edits (client request → server validate → multicast), replicated
water sim (server-only simulator), replicated entities/combat/throwables (the MP-4..8 work that was
deferred in Godot), Steam Online Subsystem for sessions. Per-peer skills/inventory.

## Phase 5 — Polish & optimization

Nanite/Lumen tuning, voxel LOD + streaming budgets at scale, Chaos cluster pooling, packaging,
graphics tiers (UE Scalability), final perf pass with Unreal Insights.

---

## Critical files to port (representative, not exhaustive)

Logic that ports near-1:1 (read these first — they're the load-bearing math):
- `scripts/VoxelScale.gd` → `UVoxelScaleSettings`
- `scripts/VoxelEditManager.gd` → `UVoxelEditSubsystem`
- `scripts/FiniteWaterCore.gd`, `scripts/WaterByteCodec.gd`, `scripts/WaterMaterial.gd` → `MiraThalVoxel` water
- `extensions/voxel_gen/src/cubic_heightmap_generator.*`, `biome_field.*`, `voxel_gravity_cpp.*`, `water_flow_cpp.*`, `distant_terrain_mesher.*` → `MiraThalVoxel` C++
- `scripts/EditToolHandler.gd` (carve math) → mining component
- `scripts/MeleeHandler.gd`, `scripts/combat/MouseDirectionSampler.gd`, `scripts/combat/ParryChainTracker.gd`, `scripts/enemies/EnemyAttackPool.gd` → combat components
- `scripts/skills/SkillManager.gd`, `scripts/skills/CombatXPRouter.gd` → skill subsystem
- `scripts/EntityStreamer.gd`, `scripts/entities/EntityRegistry.gd` → entity subsystem
- `tools/headless/runner.gd` selectors → UE Automation Specs
- `tools/generate_perks.py`, `wire_active_perks.py`, `build_texture_atlas.py`, `render_sfx.py` → re-target outputs

Design docs to honor (rules, not code): `design/PATTERNS_AND_GOTCHAS.md`,
`design/COMBAT_DESIGN_3D.md`, `design/WATER_FINITE_SIM_PLAN.md`, `design/BIOME_FRAMEWORK.md`,
`design/ENTITY_STREAMING.md`, `design/MULTIPLAYER.md`, `design/VISION_VOXEL_10CM.md`.

---

## Open questions to settle before/early in Phase 0

- **Skills system:** roll our own data-driven `USkillSubsystem` (closest to current design, full
  control) **vs** Unreal Gameplay Ability System (GAS) (powerful, replication-ready, steeper). Lean:
  custom subsystem for parity speed; revisit GAS if MP demands it.
- **Voxel Plugin licensing/seats** for a Claude-led + designer workflow — confirm terms before deep investment.
- **Dialogue plugin** choice (open-source UE dialogue plugin vs custom subsystem) — decide in Phase 3.
- **UE version pin** (latest 5.x at Phase 0 start) and whether to track or freeze.

---

## Verification

Per phase, the deliverable is verified three ways:

1. **Automation Specs (the parity harness, ported).** Each ported system lands with its selector
   test green before it's "done": `scale`, `gen`, `water_flow`/`finite` (volume conservation audit),
   `gravity`/`sever`, `flora`, `trees`, `distant`, `biome`. Run headless in CI on the dedicated-server
   target. This is the same safety net that guards the Godot build — it must come over early.
2. **In-editor PIE playtest per phase exit criterion** (e.g. Phase 0: the slice exit criteria above —
   dig at stable framerate under Lumen, water conserves, terrain falls, goblin fight works).
3. **Perf capture** with Unreal Insights on the heavy paths (dig-edit mesh rebuild, water tick,
   Chaos clusters, Lumen cost), compared against a target framerate budget — the UE analogue of the
   F3 profiler + `_analyze_capture.py` flow.

The single most important early verification is **Phase 0 step 6**: prove 10cm cubic-mesh dig
performance under Lumen, because it validates (or breaks) the whole engine bet before we invest in
porting 40k lines of gameplay.
