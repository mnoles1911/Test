# Milestone Roadmap — Game One Development

Phases 1–4 are complete (2D systems infrastructure). The 3D open world pivot is confirmed.
This document covers all remaining phases in build order.

> For completed milestone details, see `CLAUDE.md` → Milestone history.
> For system design specifications, see the relevant `design/` docs.
> For world coordinates and landmark positions, see `CLAUDE.md` → World coordinate reference.
> For outstanding manual/editor/art tasks, see `DESIGNER_TODO.md`.

---

## Are We Ready to Build?

**Yes.** Systems design is complete enough to begin coding immediately. The open questions in
`DESIGNER_TODO.md` Section 8 are content design (quest briefs, recipe placement) — they do not
block the technical foundation. They can be resolved in parallel while Phases 4-3D through 7-3D
are being built.

The one content decision that WILL block Act I scene building (Phase 9-3D):
**The Iron Chalice debt** needs to be designed before Act I dialogue and flag work begins.
Everything before Phase 9-3D can proceed without it.

---

## Phase 4-3D — Camera + Movement + HUD + UI ← COMPLETE & VERIFIED

**Status:** Complete and verified in Godot (2026-05-01). All 13 in-Godot checks pass.  
**Goal:** Third-person camera, full movement (walk/sprint/crouch), health/endurance HUD,
and tabbed journal/inventory overlay — all working together in `World3D.tscn`.
Do not proceed to Phase 5-3D until the verification checklist in `DESIGNER_TODO.md` Section 2 passes.

### Deliverables (all complete)

- **`CameraRig.gd`** — Third-person over-shoulder, standard + freelook modes, scroll zoom (2m–10m),
  arrow key fallbacks, dialogue tween, lock-on API. Fixed: scroll wheel check precedes MouseMotion
  guard; freelook re-centers on both yaw and pitch after F2 release.

- **`Player3D.gd`** — Sprint (Left Shift, endurance drain + lock), crouch (C toggle), mass-based
  physics scaling (walk/sprint/accel/decel all scale via fractional exponent against REF_MASS=70 kg),
  health + endurance with drain/regen rates, `status_text` property for HUD.

- **`HUDOverlay.gd`** autoload — HP and endurance bars at bottom-center, status label (CROUCHING / EXHAUSTED).

- **`JournalUI.gd`** (rewritten) + **`Journal.tscn`** (stripped to bare CanvasLayer) — 6-tab overlay:
  Quests, Map, Items, Crafting, Codex, Skills. Tab key and click navigation. J/I/Escape to open/close.

- **`PauseMenu.gd`**, **`DebugOverlay.gd`**, **`SaveNotification.gd`** — All resized and re-fonted for 1080p.

- **`NPC.gd`** — Added `mass` export (default 72 kg) for future movement scaling.

- **Godot one-time setup still needed** (see `DESIGNER_TODO.md` Section 1):
  - Install Zylann's Voxel Tools plugin
  - Register BarkManager and WorldClock autoloads
  - Set up audio bus layout

### Verified when:
- WASD moves Roland placeholder (camera-relative), arrow keys rotate camera only
- Mouse drag: H rotates Roland + camera; scroll zooms; F2 freelook re-centers both axes on release
- Sprint drains endurance; locks at 0; EXHAUSTED label shows; re-enables after recovery threshold
- C key toggles crouch; CROUCHING label shows; sprint blocked while crouching
- HP + endurance bars visible bottom-center; values update live
- J opens journal (6 tabs); Tab cycles; clicking headers works; I opens Items tab directly
- Escape → pause menu; Resume closes it; cursor captured again
- No errors in Output panel

---

## Phase 5-3D — Open World Foundation + Roland Character

**Goal:** Walking through recognizable authored Mira geography as a real character.
The two foundations everything else stands on: the world and the protagonist.

### Code deliverables

- **`WorldGenerator` (VoxelGeneratorGraph)** — Node assigned to `VoxelLodTerrain`.
  **Not a GDScript subclass** — a VoxelGeneratorGraph node wired in the Godot editor.
  Pipeline: author terrain in **Gaea** → export 32-bit EXR heightmap + biome splatmap →
  import as Image resources → wire into graph (heightmap → surface SDF; 3D noise → caves;
  splatmap → `CHANNEL_INDICES`). Encodes Mira's geography: Spine ridge east (~5000–7000m x),
  Greatwood flat north (~0–2500m z), Aldwater valley, Ashfields, forced-flat settlement zones.
  This is the most important deliverable in the project. **The graph produces the procedural
  baseline only — it is the constant against which every player edit is diffed. Stamp a
  generator-version constant in code so save loads can detect mismatches.**

- **`VoxelLodTerrain` + `VoxelStreamSQLite` in `World3D.tscn`** — Replace the flat floor placeholder.
  6–8 LOD levels. Mandatory LOD0 radius 32m (collision floor). Default edit-detail radius 64m.
  Mesher: `VoxelMesherCubes` (blocky). Stream backend: `VoxelStreamSQLite` writing to
  `user://saves/slot_{N}/voxel_deltas.sqlite`.

- **`VoxelEditManager.gd` autoload** — Async edit queue (per-frame voxel budget cap),
  `EditedChunkRegistry` (in-memory `HashSet<Vector3i>` populated from SQLite on load),
  LOD-bake-on-eviction (generate LOD1/LOD2 mesh when an edited chunk leaves edit-detail
  radius; cache to `user://saves/slot_{N}/mesh_cache/`; regenerate if missing), NoEditZone
  enforcement (queries `NoEditZoneRegistry` before every `VoxelTool.do_*` call). Per
  `design/3D_VOXEL_MIGRATION.md` → "Destructible Terrain".

- **`NoEditZoneRegistry.gd` autoload** — Tracks Area3D volumes registered to the
  `no_edit_zone` group. `is_point_inside_no_edit_zone(world_pos: Vector3) -> bool`.

- **First edit verb wired in** — Pickaxe equipped → swing on rock voxel removes one voxel,
  yields raw stone into inventory, advances Mining sub-skill. Proves the full edit pipeline
  (input → VoxelEditManager → NoEditZone check → VoxelTool write → SQLite delta → inventory yield).

- **`EntityStreamer.gd` stub** — Node in `World3D.tscn`. Prints chunk enter/exit to
  Output as player moves. No actual entity loading yet — just proves the architecture.

### Art deliverables

- **Roland low-poly Blender model** — 200–400 tris, flat-shaded, vertex colors only.
  Rig ~25 bones. Export `.glb` to `assets/models/roland.glb`.

- **Roland Act I animation set** — idle, walk, run wired into `AnimationTree`.
  Attack, dodge, react, death added before Phase 7-3D begins.

- **Roland portrait** — 256×320 px painted. Unblocks Dialogic dialogue UI.

- **First campfire prop** — MagicaVoxel → `.glb`. Proves the prop pipeline.

### Verified when:
- Roland (real model) walks through generated terrain that reads as Mira's geography
- Spine ridge visible on the eastern horizon from Aldenholt coordinates
- LOD transitions invisible within mandatory LOD0 radius (32m)
- Walk/run cycle animates correctly from velocity
- Pickaxe-mined voxels persist across save/load (deltas survive in SQLite)
- A test NoEditZone (placed for verification) silently rejects pickaxe edits and triggers Roland's bark
- Walking far from a mined voxel and back: edited chunk renders LOD-baked at distance, snaps to LOD0 within edit-detail radius
- Saving and reloading: voxel_deltas.sqlite re-applies edits exactly, mesh_cache re-generates if cleared

---

## Phase 6-3D — World Population + NPC Pipeline

**Goal:** The open world has real entities in it. NPCs exist at world coordinates,
load as you approach, bark as you pass. Aldenholt reads as a city from a distance.

### Code deliverables

- **`EntityRegistry.gd`** — Autoload singleton. Spatial dictionary keyed by chunk ID.
  Stores `EntityRecord` objects: `{ entity_type, world_position, scene_path, saved_state }`.
  No scene nodes — pure data. Populated from entity definition files or inline for early milestones.

- **`EntityStreamer.gd` full implementation** — Replaces the Phase 5 stub. Instantiates
  entity nodes when player enters load radius; saves state and `queue_free()`s on exit.
  Load radii: buildings ~150m, NPCs ~80m, enemies ~60m.

- **`NPC_Template.tscn`** — Master template for all NPCs (see `DESIGNER_TODO.md` Section 2).

### Art/content deliverables

- **Aldenholt building cluster** — 4–6 MagicaVoxel building exports placed at Aldenholt
  world coordinates (4400m x, 5800m z). Not detailed interiors — exterior silhouettes only.
  The city must be identifiable from 500m away.

- **First Tier 1 NPC in world** — Test NPC at Aldenholt with `PLAYER_NEARBY` bark pool.
  Walks close → bark fires → Output confirms end-to-end pipeline.

- **Tomlin as Tier 2 NPC** — `NPCData.tres` at Aldenholt coordinates. Press E → Dialogic
  opens `act1_scene_sorting_room` timeline. Proves NPC + Dialogic integration in open world.

### Verified when:
- Walking toward Aldenholt: buildings load in at ~150m, NPC loads at ~80m
- Walking away: nodes unload cleanly, no memory leak
- Pressing E near Tomlin opens Dialogic timeline
- Test NPC fires bark on approach

---

## Phase 7-3D — Real-Time Combat

**Goal:** Roland fights. Lock-on, attack, dodge, block. One real enemy type.
The combat system is what makes Act I's Archive and chapel encounters playable.

### Code deliverables

- **`CombatManager.gd`** — Manages combat state: active enemies, lock-on target, attack
  token queue, hit detection. Not turn-based. Real-time with `_physics_process`.
  Full spec: `design/COMBAT_DESIGN_3D.md`.

- **Lock-on system** — `lock_on` input finds nearest enemy in forward arc. Camera drifts
  to keep target in right frame half. Cycles with `camera_left` / `camera_right`.

- **`EnemyAI.gd`** — Base class for enemy behavior: detection states (patrol → alert →
  combat), attack token system, telegraph → attack sequence. Per `design/ENEMY_AI.md`.

- **`DeathHandler.gd`** — Roland death: authored line, screen fade, respawn at last rest
  point. Per `design/DEATH_AND_RESPAWN.md`.

### Art deliverables

- **Roland combat animations** — attack_light, attack_heavy, dodge, react/flinch, death.
  These may be partially done in Phase 5 — complete here if not.

- **Ashfallen soldier model** — First enemy. Low-poly Blender, ~300 tris. Rig + idle,
  walk, attack animations. The recognition-hesitation mechanic requires visually worn
  Eldermark gear.

### Verified when:
- Lock-on snaps to Ashfallen, camera frames correctly
- Light attack → hit reaction on enemy
- Dodge roll clears an enemy attack
- Roland death → authored line → respawn at rest point
- 1-vs-2 encounter playable without camera chaos

---

## Phase 8-3D — Interior Pipeline + Dialogic Integration

**Goal:** Interiors load from the open world. Act I locations feel like real spaces.
Dialogue, flags, investigation points all wired and working.

### Code deliverables

- **Interior loading system** — When player enters a door `Area3D`, `TransitionManager`
  loads the interior `.tscn` additively (or replaces scene), stores return position.
  On exit door, unloads interior and returns player to open world at entry point.

- **`InvestigationPoint.gd`** — `Area3D` script. E-press delivers observation overlay,
  sets journal flags, checks deduction conditions. Per `design/INVESTIGATION_SYSTEM.md`.

- **`InvestigationUI.gd`** — Text overlay for Roland's examination lines. Fades in/out.

- **GameState first real flags:**
  - `henrietta_dead: bool`
  - `pommel_piece_1_acquired: bool`
  - `aldric_vane_name_logged: bool`
  - `tomlin_helped: bool`

### Art/content deliverables

- **Iron Chalice chapel interior** — `.tscn` scene. MagicaVoxel assets. Dame Calla NPC,
  pommel placement, investigation points on altar and floor. Combat trigger zone.

- **Archive interior** — `.tscn` scene. Tomlin (already wired from Phase 6). Henrietta's
  desk investigation point. Restricted section door.

- **Henrietta NPC model + portrait** — Low-poly Blender, portrait 256×320 px.

### Verified when:
- Enter door in Aldenholt → Archive interior loads, correct spawn point
- Exit door → back to open world at correct position, no duplicate player
- Press E on Henrietta's desk → investigation line displays, flag sets
- Flag from Archive carries into chapel Dialogic condition

---

## Phase 9-3D — Act I Playable ← First Shippable Sequence

**Goal:** Act I is playable end-to-end. Night chase through Aldenholt, Archive,
Henrietta's quarters, Iron Chalice chapel, pommel acquired. The game's opening
sequence is something you can actually play.

**Prerequisite design work** (from `DESIGNER_TODO.md` Section 8 — must be complete
before this phase begins):
- The Iron Chalice debt quest designed
- Act I side quest briefs written (at least 2)

### Deliverables

- **Night chase sequence** — Roland runs through Aldenholt streets at night. Implied
  pursuit (no enemy entity required for Act I — sound design and NPCs reacting is enough).

- **Roland's journal** — Basic UI. Active quest, known people, Crown pieces. Written in
  Roland's voice. Does not need to be the full 5-tab journal — a readable panel suffices.

- **All Act I NPCs** — Tomlin (Phase 6), Henrietta (Phase 8), Dame Calla, Roland's
  lodgings innkeeper. Bark pools written. Portraits painted. Dialogic timelines complete.

- **Act I quest flags** — All flags that carry into Act II set and tested.

- **First TTS audio** — Roland voiced observation lines and at least one full NPC
  voice track (`act1_scene_sorting_room`) rendered and wired into Dialogic.

### Verified when:
- Play from opening night chase to pommel acquisition without hitting a dead end
- All Dialogic branches reachable and correct
- Journal reflects Roland's actual knowledge state at each story beat
- Autosave fires at correct moments

---

## Phase 10-3D onward — Act II Zones

Act II introduces the Four Kingdoms (player-determined order). Each kingdom is a
multi-session phase: open world approach, city exterior, key interiors, companion join.

**Orion joins at Caer Brannoch** — first companion. Multi-party combat begins here.
**Dagna joins in the Underway** — structural analysis, seismic investigation unlocked.

Act II phases will be scoped once Act I is content-complete and the Act II zone
design decisions (trainer NPCs, recipe placement, side quest briefs) are resolved.

---

## Phase Dependencies at a Glance

```
Phase 4-3D  Camera + Godot setup            ← START HERE
    │
Phase 5-3D  WorldGenerator + Roland model   ← code + art in parallel
    │
Phase 6-3D  EntityStreamer + NPC pipeline   ← populates the world
    │
Phase 7-3D  Real-time combat                ← makes encounters playable
    │
Phase 8-3D  Interior loading + Dialogic     ← makes Act I locations exist
    │
Phase 9-3D  Act I playable                  ← first shippable sequence
    │
Phase 10+   Act II zones                    ← per-kingdom phases
```

Phases 5 and 6 have parallel art/code tracks. Roland Blender work and WorldGenerator
coding do not depend on each other and can run simultaneously.
