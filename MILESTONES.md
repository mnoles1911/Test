# Milestones

Concise one-liners. **`git log` is the source of truth.** This file exists so a new collaborator can scan the arc without diving into 300+ commits.

## 2026 (active development)

- **04-30 PR#43:** 2D → 3D voxel pivot.
- **05-03 to 12:** destructible voxel slice; Copper Isles demo; Combat v1 (Goblin/Spear/BloodVFX); Skills (PR#201); MP (PR#180); cubic generator C++.
- **05-13 to 16:** `HeightmapGeneratorBase` (#203); `Profiler.real_us` reliable (#207); `WaterChunkMesher` C++ (#214, later deleted).
- **05-18 native-fluid pivot:** water = `VoxelBlockyModelFluid` ids 16–23, 8 levels, mesher auto-slopes. Legacy id 5 kept for old saves. Plan: `design/WATER_STAGE6_PLAN.md`.
- **05-19/20:** UnderwaterFilter (instant-snap submerge, vol fog, god rays); AgX tonemap + SSAO/SSIL/PSSM/MSAA. **Never flip `bake_tangents`** (breaks water meshes).
- **05-21/22:** AudioManager + 548 SFX takes; GraphicsManager 5 tiers; procedural sky/clouds/stars; `AtmosphereProfile`; tangent-free `terrain_voxel.gdshader`.
- **05-22/26 PR#240:** DistantTerrain streaming heightmesh replaces baked HorizonSkirt. LOD outrun fixed. F11/F12 debug overlays.
- **05-27 PR#241:** Four C++ ports — `VoxelGravityCpp` (131→2.8 ms, **46× win**), `EmissiveLightCpp` v1, `EmissiveBakedCpp` (Phase J), `WaterFlowCpp`. All parity-gated. **Zylann byte layout is Y-fastest.**
- **05-27 PR#243:** LOD1+ water surface line FIX (horizon plane + UnderwaterFilter group-toggle + WaterDiag backtick / Shift+backtick / debug_mode 7-8).
- **05-27 PR#244:** Phase K bundle — selection outline, cloud-phase accumulator, DebugOverlay GRAPHICS sub-view, lens flare, rainbow (all toggle-gated).
- **05-27 PR#245 Weather rework (MERGED 2026-05-28):** designer playtest deferred all visuals — rain shader / wet terrain / splashes / god rays gated OFF by default; audio envelope crossfade live. Needs multi-session iteration. `design/WEATHER_REWORK_2026-05.md`.
- **05-27 PR#246 EntityStreamer (CLOSED — folded into #247):** `EntityRegistry` (per-chunk + JSON save/load) + 4-tier AI sleep (ACTIVE/AWAKE/SLEEPING/OFFLOADED). Goblin/NPC/VoxelDrop retrofitted. Headless `entity` gate 66 checks. Shipped to main via #247. `design/ENTITY_STREAMING.md`.
- **05-28 PR#247 Combat Phase 5 (MERGED 2026-05-30, squash `bc0d895`):** charged-spear (hold LMB ≥50 dmg) → gib explosion (12 GibChunks, radial impulse) + 0.15 s time-slow + camera kick + spear reparents to chunk. ThrowableHandler charge mechanic added (Phase 3 finish). Overkill threshold = 50 (re-raise once charged dmg passes 80 via perks). Includes the #246 EntityStreamer work. CombatTest debug-kill key is **F10** (F8 = editor Stop).
- **05-28 PR#239 Directional Melee v1 (MERGED 2026-05-30, squash `3936e94`):** sword + shield, four-direction mouse-flick attacks (**flick toward the blow's origin** — UP=overhead, DOWN=thrust, LEFT/RIGHT=that-side sweep; inverted from the first "sword moves where I flick" model on 2026-05-29), charged 2× + feint, RMB tap=parry / hold=directional block + `auto_block` toggle, `ParryChainTracker`, `EnemyAttackPool` telegraphs, `HUDDirectionArrows` + `HUDCombatRadar`. **Lock-on prototyped then removed — pure free-aim.** Phases 0-6. Gibs (#247) + melee coexist on `Goblin`/`Enemy3D`.
