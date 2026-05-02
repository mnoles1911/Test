# Designer Action List

Running list of tasks that require work in Godot, external tools, or creative
production — things that cannot be done by writing code or design documents alone.

This file is the single source of truth for outstanding manual work. Check it
before starting a session and mark items done as they are completed.

Format: `- [ ]` = outstanding, `- [x]` = done. Add new items at the bottom of
their section with a brief note of what it unlocks.

---

## Section 1 — Godot Editor: One-Time Project Setup

These are settings and installs that survive across all future work. Do them once.

- [ ] **Install Zylann's Voxel Tools plugin (GDExtension edition)**
  This plugin is NOT in Godot's Asset Library — it ships native binaries.
  Download from GitHub Releases instead:
  1. Go to https://github.com/Zylann/godot_voxel/releases
  2. Download the latest "GDExtension" asset matching your platform (Win/Mac/Linux). Requires Godot 4.4.1+; we are on 4.6.2 stable.
  3. Extract the ZIP and move the resulting `zylann.voxel/` folder into the project's `addons/` directory so the path is `addons/zylann.voxel/`.
  4. Restart Godot. Project Settings → Plugins → confirm "Voxel Tools" is enabled.
  5. Verify: a `VoxelLodTerrain` node should appear in the Add Node dialog.
  Reference: `design/ART_PIPELINE.md` → "Tool 2: Zylann's Voxel Tools" for the full install detail.
  Required for Milestone 5-3D (terrain generation + destructible terrain core).

- [x] **Configure the core Input Map per `design/INPUT_AND_CONTROLS.md`** (mostly done — see below)
  All core actions are now in `project.godot`. Remaining items marked [ ] below.
  **KB+M defaults (confirmed and live):**
  - [x] `interact` — E
  - [x] `sprint` — Left Shift
  - [x] `attack` — Left Mouse Button (tap = light, hold ≥0.20s = power)
  - [x] `block` — Right Mouse Button (hold = block, tap = parry)
  - [x] `dodge` — Space
  - [x] `lock_on` — Middle Mouse Button
  - [x] `quick_slot_prev` — Q
  - [x] `camera_left` — Left Arrow / `camera_right` — Right Arrow (keyboard fallback)
  - [x] `camera_up` — Up Arrow / `camera_down` — Down Arrow (keyboard fallback)
  - [x] `freelook_camera` — F2 (hold to orbit camera without rotating Roland; release re-centers)
  - [x] `open_journal` — J
  - [x] `open_inventory` — I
  - [x] `pause` — Escape
  - [x] `debug_overlay` — F1
  - [x] `crouch` — C (toggle press; blocks sprint while active)
  - [ ] `quick_slot_next` — E (context-sensitive; use F as dev placeholder until context logic is in place)
  - [ ] `next_target` / `prev_target` — optional; scroll wheel zoom takes priority
  **Movement is WASD-only. Arrow keys = camera rotation only. Mouse drag = camera in standard mode; F2 hold = freelook.**

- [x] **`HUDOverlay` registered as an Autoload** (done — in `project.godot`)
  Layer 5 CanvasLayer. HP bar (red) and endurance bar (green) at bottom-center. Status label shows CROUCHING / EXHAUSTED.
  Reads `health`, `max_health`, `endurance`, `max_endurance`, `status_text` from the player each frame via group lookup.

- [ ] **Register `BarkManager` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/BarkManager.gd` → node name: `BarkManager`.
  Required for all bark lines to fire in-game. Reference: `design/NPC_SYSTEM.md`

- [ ] **Register `WorldClock` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/WorldClock.gd` → node name: `WorldClock`.
  Required for NPC daily schedules and time-of-day bark triggers. Reference: `design/NPC_SYSTEM.md`

- [x] **Configure lock-on input action** (done — `lock_on` = Middle Mouse Button in project.godot)
  Camera rotation does NOT need Input Map actions for KB+M — `CameraRig.gd` reads
  `InputEventMouseMotion` directly. Arrow key fallbacks (`camera_left/right/up/down`)
  are live. Freelook (`freelook_camera` = F2) is also live. Reference: `design/CAMERA_AND_PERSPECTIVE.md`

- [ ] **Register `EntityRegistry` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/EntityRegistry.gd` → node name: `EntityRegistry`.
  Required before `EntityStreamer` can load/unload world entities. Build after `WorldGenerator`.

- [ ] **Register `VoxelEditManager` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/VoxelEditManager.gd` → node name: `VoxelEditManager`.
  Required for any voxel edit (axe / pickaxe / shovel / explosive / spell) to function correctly. Handles async edit queue, EditedChunkRegistry, LOD-bake-on-eviction, NoEditZone enforcement, per-frame voxel budget. Build during Milestone 5-3D. Reference: `design/3D_VOXEL_MIGRATION.md` → "Destructible Terrain".

- [ ] **Register `NoEditZoneRegistry` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/NoEditZoneRegistry.gd` → node name: `NoEditZoneRegistry`.
  Tracks Area3D volumes assigned to the `no_edit_zone` group. Queried by `VoxelEditManager` before every voxel write. Build during Milestone 5-3D. Reference: `design/3D_VOXEL_MIGRATION.md` → "NoEditZones".

- [ ] **Register `SchematicLibrary` as an Autoload** (later — when player construction lands)
  Project Settings → Autoload → path: `res://scripts/SchematicLibrary.gd` → node name: `SchematicLibrary`.
  Loads `.tres` schematic resources from `assets/voxel/schematics/`; maps schematic IDs to `.glb` props with placement metadata. Reference: `design/CRAFTING.md` → Carpentry Bench.

- [ ] **Set up VoxelLodTerrain in `World3D.tscn`**
  Add `VoxelLodTerrain` node to `World3D.tscn`. Add `VoxelGeneratorGraph` as a child (this is `WorldGenerator` — wired in the editor, not GDScript). Add `VoxelStreamSQLite` as a child with stream path `user://saves/slot_{N}/voxel_deltas.sqlite` (the path is set in code at save-load time).
  Configure: `lod_count` 6–8, mandatory LOD0 radius 32m, default edit-detail radius 64m, mesher = `VoxelMesherCubes` (NOT Transvoxel), `streaming_system` = `STREAMING_SYSTEM_CLIPBOX`.
  Reference: `design/ART_PIPELINE.md` → Tool 2, `design/3D_VOXEL_MIGRATION.md` → "Destructible Terrain", `design/TECH_STACK.md` → Voxel Terrain.

- [ ] **Wire WorldGenerator (VoxelGeneratorGraph)**
  Open the VoxelGeneratorGraph node → wire it visually:
  - Heightmap EXR → `Image` input → `Remap` (0–1 → 0–200m) → `SdfPlane` → base SDF
  - 3D `FastNoiseLite` node → `SdfSmoothSubtract` (carves caves where Y < surface − 8m)
  - Splatmap EXR → `Image` input → `OutputType: CHANNEL_INDICES` (biome material assignment)
  - Connect to `OutputSDF`.
  This produces the procedural baseline only. Player edits live as deltas in `VoxelStreamSQLite`. Stamp a `WORLD_GENERATOR_VERSION` constant in code so save loads can detect mismatches.

- [ ] **Set up the audio bus layout per `design/AUDIO_DESIGN.md`**
  Bottom panel → Audio → add buses: `Music`, `SFX` (with children `Combat`, `Ambient`),
  `Voice` (with children `NPC`, `Roland`), `UI`. Save as `default_bus_layout.tres`.
  Required before any music or voiced dialogue work — `Settings.gd` volume sliders
  target the bus names exactly as written above.

- [ ] **Clean up Godot editor cruft from version control**
  After opening the project in Godot, `git status` shows ~25 untracked `scripts/*.gd.uid`
  files plus modifications to `project.godot`, `scenes/Player3D.tscn`, `scenes/World.tscn`,
  and `scenes/World3D.tscn`. Two separate things to handle:
  - **`.uid` files** — Godot 4.4+ script UID cache. Decide: commit them (Godot's
    recommendation, keeps script references stable across renames) or add `*.uid` to
    `.gitignore` (treat as regenerable editor cache). For a solo project, ignoring is
    simpler. If we ignore: `echo "*.uid" >> .gitignore` then `git rm --cached scripts/*.gd.uid`
    if any are already tracked.
  - **Modified `.tscn` and `project.godot`** — open each in Godot and check if the
    diff reflects real authored changes (the 3D pivot work) or just noise from Godot
    re-saving on open. If real, commit them on a focused branch. If noise, `git checkout`
    to discard.
  Do this before the next feature branch so the working tree is clean.

---

## Section 2 — Godot Editor: Scene Work

Scene building and node configuration that has to be done in the editor.

- [x] **Verify Milestone 4-3D in Godot** ✓ PASSED (2026-05-01) — all 13 checks confirmed in-engine.
  Open `scenes/World3D.tscn` and run it. Confirm:
  - WASD moves the placeholder character on the flat floor (camera-relative: W = toward Roland's facing)
  - Arrow keys rotate the camera only — they do NOT move the character
  - Mouse drag rotates camera left/right (and rotates Roland's body in standard mode) and tilts up/down
  - F2 hold enters freelook: mouse orbits camera without turning Roland; release re-centers on both axes
  - Mouse scroll wheel zooms in/out (arm length 2m–10m)
  - Camera follows in third-person over-shoulder at ~15° elevation
  - Hold Left Shift while moving → sprint; endurance bar drains. At 0, sprint locks until endurance > 20
  - Press C → crouch toggle; speed drops; sprint blocked; status label shows CROUCHING
  - HP and endurance bars visible bottom-center of screen; values update live
  - Status label shows EXHAUSTED when sprint is locked
  - Press Escape → pause menu appears, cursor becomes visible; Resume → cursor hides again
  - Press J → journal opens with 6 tabs; Tab key cycles tabs; clicking tab headers works; I also opens (to Items tab)
  - Press Escape or J or I while journal open → closes
  - Campfire glows orange and flickers
  - No clipping through the floor
  - F1 → debug overlay toggles
  This is the baseline 3D scene test. Nothing built on top of it is trustworthy
  until this passes.

- [ ] **Build `scenes/NPC_Template.tscn`**
  Create once; duplicate for every new NPC going forward.
  Required node structure:
  ```
  NPCNode (CharacterBody3D + NPC.gd)
  ├── MeshInstance3D
  ├── CollisionShape3D (CapsuleShape3D)
  ├── BarkArea (Area3D)
  │   └── CollisionShape3D (SphereShape3D, radius ~5m)
  └── InteractArea (Area3D)
      └── CollisionShape3D (SphereShape3D, radius ~2m)
  ```
  Reference: `design/NPC_SYSTEM.md` → "Godot Scene Setup"

- [ ] **Place a test Tier 1 NPC in `World3D.tscn`**
  Instance `NPC_Template.tscn`, create a test `NPCData.tres` with `tier = BARK`,
  create `dialogue/scripts/barks/idle/test_npc.txt` with a `PLAYER_NEARBY` trigger pool,
  run the scene, walk close — confirm the bark prints to the Output panel.
  This is the end-to-end test for the whole bark pipeline.

- [ ] **Place Tomlin as a Tier 2 NPC**
  Instance `NPC_Template.tscn` in the Archive scene. Create `assets/npcs/tomlin.tres`
  with `tier = CONVERSATIONAL` and `dialogue_timeline = "act1_scene_sorting_room"`.
  Confirm: press E near Tomlin → sorting room Dialogic timeline opens.

- [ ] **Add a campfire prop to `World3D.tscn` as a camp interact point**
  Give it an `InteractArea (Area3D)`. Press E → opens the camp menu (Section 8).
  The campfire is also the first cooking station. Reference: `design/REST_AND_CAMP.md`

- [ ] **Add investigation point nodes to Act I scenes**
  Once the Act I scenes are built, place `InvestigationPoint` nodes (Area3D) on
  key objects: Henrietta's desk, the Archive door lock, the chapel altar, etc.
  Minimum 6 ambient + 2 relevant per interior scene. Reference: `design/INVESTIGATION_SYSTEM.md`

- [ ] **Add NPC nodes to the `scheduled_npcs` group** (for any NPC with a schedule)
  Select the NPC node in the scene → Node panel → Groups tab → add `scheduled_npcs`.
  WorldClock will call `update_schedule(hour)` on all group members each game hour.

- [ ] **Add `SpawnPoint3D` nodes for each NPC schedule location**
  Each `NPCScheduleEntry.location_id` must match the exact name of a `SpawnPoint3D`
  node in the scene. Add each to the `spawn_points` group via Node panel → Groups tab.

---

## Section 3 — Art & Asset Production

Assets that require external tools (MagicaVoxel, Aseprite, Blender, etc.)

- [ ] **Character portraits for Dialogic — Roland, Tomlin, Calla**
  Size: 256×320 px. Save to `assets/portraits/{character}.png`.
  Only Henrietta has a placeholder (`henrietta_placeholder.svg`).
  Portraits are what carry emotional performance in Tier 2 and 3 conversations —
  this is high-priority for any scene that is playable.

- [ ] **First MagicaVoxel prop export: campfire**
  Model the campfire prop in MagicaVoxel → export as `.glb` → import to Godot as
  `MeshInstance3D`. Replace the `OmniLight3D`-only campfire placeholder in `World3D.tscn`.
  Reference: `design/ART_PIPELINE.md`

- [ ] **First MagicaVoxel prop export: cave wall tile**
  Used to build dungeon and cave environments modularly.
  Reference: `design/ART_PIPELINE.md`, `design/ART_DIRECTION.md`

- [ ] **Roland low-poly Blender model**
  200–400 triangles, flat-shaded. Proportions: chunky low-poly, readable silhouette.
  No texture — vertex colors only, using the game palette (`design/ART_DIRECTION.md`).
  Rig with ~25 bones. Export as `.glb` to `assets/models/roland.glb`.
  First animation: idle (weight shift). Second: walk cycle. Third: run.
  These three clips unblock all scene movement and camera testing.
  Reference: `design/ART_PIPELINE.md` → Tool 3

---

## Section 4 — TTS & Audio Production

Voice generation tasks for the text-to-speech pipeline.

- [x] **Create local `.env` file with your ElevenLabs API key**
  At the repo root, create a file named `.env` containing:
  ```
  ELEVENLABS_API_KEY=sk-your-key-here
  ```
  Replace with your real key from https://elevenlabs.io/app/settings/api-keys.
  The `.env` file is gitignored — it stays on your machine and is never
  committed. Before running `tools/render_bulk.py`, load the variable into
  your terminal session with:
  ```
  set -a && source .env && set +a
  ```
  Without the env var set, `render_bulk.py` aborts before any network call.
  See `tools/README.md` for the full workflow.

- [ ] **Generate calibration clips for Roland, Tomlin, and Calla**
  Before batch-generating any scene, render a ~30-second test clip per character:
  one line of each baseline mood + one extreme. Lock the voice/seed when it sounds
  right and save the clip as a permanent reference.
  This is the single most important TTS workflow step — prevents voice drift across
  hours of generated content. Reference: `dialogue/STYLE.md` → section 7.3

- [ ] **Generate voiced audio for `act1_scene_sorting_room`**
  Script is at `dialogue/scripts/act1_scene_sorting_room.txt`.
  Prose draft (context) is at `dialogue/drafts/act1_scene_sorting_room.md`.
  Output audio to `assets/audio/scenes/act1_sorting_room/`.
  Wire into the Dialogic timeline once generated.

- [ ] **Generate voiced audio for `act1_scene_forty_minutes`**
  Script: `dialogue/scripts/act1_scene_forty_minutes.txt`.
  Draft: `dialogue/drafts/act1_scene_forty_minutes.md`.
  Output to `assets/audio/scenes/act1_forty_minutes/`.

- [ ] **Check `dialogue/PRONUNCIATION.md` before each TTS generation run**
  Lore proper nouns (Drûn-Khazad, Khorumzad, Aelthurion, etc.) must use the
  phonetic respellings in that file inside the `.txt` scripts before generating.
  The TTS model will guess wrong pronunciations if you skip this.

---

## Section 5 — Dialogue Authoring

Conversations and bark lines that still need to be written.

- [ ] **Write bark lines for the first Aldenholt vendor (Tier 1 NPC)**
  File: `dialogue/scripts/barks/idle/aldenholt_vendor.txt`
  Minimum: 3–5 lines for trigger `PLAYER_NEARBY`.
  Format: follow `design/BARK_LIBRARY.md` → Category 4 (Idle/Ambient templates).

- [ ] **Write bark lines for Tomlin**
  File: `dialogue/scripts/barks/idle/tomlin.txt` (at minimum).
  Also consider: `exploration/tomlin.txt` for investigation barks.
  Reference: `design/BARK_LIBRARY.md`, volume targets table.

- [ ] **Add a voice notes entry for every voiced NPC to `dialogue/CHARACTER_VOICES.md`**
  Roland, Tomlin, and Calla have entries. Any new NPC given a voice profile in
  their `NPCData.tres` must have a matching entry in that file before TTS generation.

- [ ] **Write Roland's voiced observation lines for Act I investigation points**
  Every Type 1 and Type 2 investigation point needs a `roland_line` string and,
  if voiced, a corresponding entry in the TTS script. Draft these alongside the
  scene writing pass for Act I. Reference: `design/INVESTIGATION_SYSTEM.md`

---

## Section 6 — UI Nodes (To Be Built in Code + Editor)

These need both code and scene work. Listed here as designer-visible milestones.

- [ ] **`BarkOverlay` UI node — bark text display**
  Small portrait + text line, appears in a screen corner, auto-hides after ~3.5s.
  Must be added to the `bark_overlay` group so `BarkManager` can find it.
  Without this, barks only print to the Output panel (which is fine during testing).

- [ ] **"Press E to talk" world-space prompt**
  Appears above an NPC when the player is within interact range.
  Connected in `NPC.gd` (the two TODO comments at lines 149 and 154).

- [ ] **Extend `DebugOverlay` (F1) with NPC inspector**
  Show: active NPC name, current disposition, active schedule block, time of day.
  Useful for testing NPC schedules without guessing what WorldClock thinks it is.

---

## Section 7 — Code to Build (Design-Specified Systems)

Scripts and scenes that are now fully specified in design docs and ready to implement.
Organized by development phase. Build within each phase in the order listed.

---

### Phase 4-3D — Camera, Movement, Health/Endurance, HUD, UI (complete)

- [x] **Update `CameraRig.gd`** — Third-person over-shoulder camera, fully implemented.
  Two modes: standard (mouse H rotates the CharacterBody3D so Roland faces the camera direction)
  and freelook (F2 hold: mouse H orbits the camera arm without rotating Roland; release re-centers both axes).
  Scroll wheel zoom (2m–10m). Arrow key fallbacks. Dialogue mode (tween arm length to 3.5m).
  Lock-on tracking API (`set_lock_on_target`). Mouse mode managed: CAPTURED during play,
  VISIBLE when any menu opens.
  Reference: `design/CAMERA_AND_PERSPECTIVE.md`

- [x] **Rewrite `Player3D.gd`** — Sprint (Left Shift, drains endurance, locks on exhaustion until recovery),
  crouch (C toggle, blocks sprint, reduces speed to ~2 m/s), mass-based physics scaling
  (all movement stats — walk speed, sprint speed, accel, decel — scale via fractional-exponent
  ratio against `REF_MASS = 70 kg`). DECEL intentionally lower than ACCEL for natural momentum.
  Health (100 HP) and endurance (100) with drain/regen rates. `status_text` computed property
  returns "CROUCHING" / "EXHAUSTED" / "" for HUD display.

- [x] **New `HUDOverlay.gd` autoload** — Layer 5 CanvasLayer. HP bar (red, 26px tall) and
  endurance bar (green, 22px tall) in a 540×110px panel anchored bottom-center, 36px from bottom.
  Status label above bars (orange). Finds player by "player" group with cached reference.
  Hides itself cleanly when no player node exists. Registered in `project.godot`.

- [x] **Rewrite `JournalUI.gd` + strip `Journal.tscn`** — Programmatic 6-tab overlay
  (Quests, Map, Items, Crafting, Codex, Skills). Tab key cycles tabs; clicking tab headers
  switches tabs. J opens to Quests, I opens to Items. Escape/J/I closes. Mouse becomes
  visible when open; restores CAPTURED on close. Tree paused while open.

- [x] **Fix `PauseMenu.gd` for 1080p** — Panel 440×400px, title 28px, buttons 22px/44px.
  Resume button closes menu and resumes game. JournalUI coordination: PauseMenu checks
  `JournalUI.is_overlay_visible()` before opening; JournalUI handles Escape before PauseMenu.

- [x] **Fix `DebugOverlay.gd` for 1080p** — Tab label 18px, content 15px, scroll offset corrected.

- [x] **Fix `SaveNotification.gd` for 1080p** — Toast label 20px, position updated.

- [x] **Add `mass` export to `NPC.gd`** — Typical values: courier ~55 kg, villager ~72 kg,
  armoured guard ~110 kg. Documented for use when NPC movement systems are built.

---

### Phase 5-3D — Open World Foundation (Editable Terrain)

- [ ] **`WorldGenerator` (VoxelGeneratorGraph)** ← foundation; everything stands on this
  Implemented as a **`VoxelGeneratorGraph`** node (not a GDScript subclass) assigned to `VoxelLodTerrain`.
  **Produces the procedural baseline only — every player edit is diffed against this.**
  **Pipeline:** Author terrain in **Gaea** → export 32-bit EXR heightmap + RGB biome splatmap →
  import both as Image resources in Godot → wire into VoxelGeneratorGraph:
  - Image node (heightmap EXR) + XZ scale → surface SDF
  - 3D Noise nodes → cave/overhang SDF
  - `SdfSmoothSubtract` → combined → `CHANNEL_SDF`
  - Image node (biome splatmap) → `CHANNEL_INDICES`
  Must encode: Spine ridge (wx ~5000–7000), Greatwood flat (wz ~0–2500), Aldwater valley,
  Ashfields, forced-flat settlement zones (see CLAUDE.md → World coordinate reference).
  Stamp a `WORLD_GENERATOR_VERSION` constant in code so save loads detect mismatches.
  Reference: `design/ART_PIPELINE.md` → Tool 2

- [ ] **`VoxelEditManager.gd` autoload** — Core of the destructible terrain system. Async edit queue (per-frame voxel budget cap, ~256 voxels/frame default), `EditedChunkRegistry` (in-memory `HashSet[Vector3i]`, populated from `VoxelStreamSQLite` on save load), LOD-bake-on-eviction (one-time LOD1/LOD2 mesh generation when an edited chunk leaves edit-detail radius; cached to `user://saves/slot_{N}/mesh_cache/`; regenerate on demand if missing), NoEditZone enforcement before every `VoxelTool.do_*` call. Public API: `queue_edit_sphere(pos, radius, voxel_value) -> bool`, `queue_edit_box(...)`, `queue_set_voxel(...)`. Returns false if rejected by NoEditZone (caller may bark *"This place doesn't yield to me."* once per session per zone).
  Reference: `design/3D_VOXEL_MIGRATION.md` → "Destructible Terrain"

- [ ] **`NoEditZoneRegistry.gd` autoload** — Tracks Area3D volumes registered to the `no_edit_zone` group. `_ready()` walks the scene tree and connects to area `tree_entered` / `tree_exiting` signals so registry updates live as zones load/unload via EntityStreamer. Provides `is_point_inside_no_edit_zone(world_pos: Vector3) -> bool`. Queried by `VoxelEditManager` before every voxel write.
  Reference: `design/3D_VOXEL_MIGRATION.md` → "NoEditZones"

- [ ] **First edit verb wired in** — Equip a Pickaxe → swing connects with rock voxel → `VoxelEditManager.queue_edit_sphere(pos, 0.5, AIR_VOXEL)` → if accepted, remove voxels and yield "Raw stone" to inventory; advance Mining sub-skill. Proves the full edit pipeline end-to-end (input → manager → NoEditZone check → VoxelTool write → SQLite delta → mesh re-bake → inventory yield → skill XP).

- [ ] **Save / load wiring for editable terrain** — `GameState.save_game()` flushes `VoxelStreamSQLite` and `placed_schematics.json` to slot directory. `GameState.load_game()` validates `WORLD_GENERATOR_VERSION` stamp (hard error on mismatch — surface a clear UI error, do not load), populates `EditedChunkRegistry` from SQLite, hooks `VoxelStreamSQLite` to the slot's database path. Backup rotation per `design/SAVE_SYSTEM.md`.

- [ ] **Test NoEditZone in `World3D.tscn`** — Drop one Area3D registered to group `no_edit_zone` covering a small region (e.g., a 10m × 10m square). Verify pickaxe edits inside the zone are silently rejected and trigger Roland's bark; edits outside work normally.

- [ ] **`EntityStreamer.gd` stub** — Node in `World3D.tscn`. Phase 5 version just prints
  chunk coordinates to Output as player moves. Full entity loading in Phase 6.

---

### Phase 6-3D — World Population

- [ ] **`EntityRegistry.gd`** — Autoload singleton. Spatial dictionary keyed by chunk ID.
  Stores `EntityRecord` objects: `{ entity_type, world_position, scene_path, saved_state }`.
  No scene nodes — pure data. Populated from entity definition files or inline for early milestones.
  Reference: `design/3D_VOXEL_MIGRATION.md` → file structure

- [ ] **`EntityStreamer.gd` full implementation** — Replaces Phase 5 stub. Instantiates
  entity nodes within load radius; saves state and `queue_free()`s on exit. Radii: ~150m
  buildings/props, ~80m NPCs, ~60m enemies.

---

### Phase 7-3D — Real-Time Combat

- [ ] **`CombatManager.gd`** — Real-time combat state: active enemies, lock-on target,
  attack token queue (prevents all enemies attacking simultaneously), hit detection.
  Reference: `design/COMBAT_DESIGN_3D.md`

- [ ] **Bake combat tunable values into `CombatManager.gd` (and any helper scripts)**
  Hardcode the locked numbers from `design/COMBAT_DESIGN_3D.md` → Tunable Values
  as named constants (not magic numbers). Targets: parry window 300 ms; endurance
  costs light=8 / power=18 / block=12 / parry=5 / dodge=15 / sprint=8 per second;
  endurance recovery 20/s; stagger 1.5 s at 60 % movement; wound HP fraction 25 %
  of damage taken.

- [ ] **Torch implementation per `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md`**
  - `Torch.gd` script on the equipped-torch scene: parents an `OmniLight3D`
    (8m radius, warm) to Roland's off-hand bone/marker; ticks down a 4-in-game-hour
    burn timer via `WorldClock.hour_changed`; extinguishes silently and removes the
    item on burnout (no relighting).
  - Torch `ItemData` entry: 0.3 kg, occupies Off-Hand slot, incompatible with
    two-handed weapons and shields.
  - InventoryManager guard: refuse to equip a torch while a two-handed weapon or
    shield is in the relevant slot.

- [ ] **Lock-on system** — `lock_on` input finds nearest enemy in forward arc. Camera drifts
  to frame target in right 60% of screen. Cycles with `camera_left` / `camera_right`.
  Disengages on target death or out-of-range.

- [ ] **`EnemyAI.gd` base script + per-type subclasses**
  State machine (Idle / Suspicious / Alert / Combat / Fleeing), attack-token
  arbitration with sibling enemies, per-type specs for Goblin, Ashfallen, Wolf, Bear.
  Reference: `design/ENEMY_AI.md`

- [ ] **`DeathHandler.gd` + Roland death-line library**
  Triggers on Roland HP=0: plays authored death line, fades to black, offers
  Second Wind (if available) or reload-from-last-save. No XP loss, no item loss.
  Reference: `design/DEATH_AND_RESPAWN.md`

---

### Phase 8-3D — Interiors + Dialogic Integration

- [ ] **Interior loading system** — When player enters a door `Area3D`,
  `TransitionManager` loads interior `.tscn`, stores open-world return position.
  On exit, unloads interior and returns player to correct world position.

- [ ] **`InvestigationPoint.gd` node script**
  Area3D script: on E-press, delivers observation text overlay, sets journal flags,
  checks deduction conditions, fires companion observation if applicable.
  Reference: `design/INVESTIGATION_SYSTEM.md` → GDScript Implementation Notes

- [ ] **`InvestigationUI.gd`** — Observation text overlay. Fades in/out.
  Reference: `design/INVESTIGATION_SYSTEM.md` → The Examination Interface

- [ ] **Lockpicking system per `design/LOCKPICKING.md`**
  Four small scripts/scenes:
  - `LockData.gd` resource — tier (Simple/Standard/Complex/Masterwork), pin count,
    false-resonance count, contents reference.
  - `Lock.gd` Area3D node — proximity auto-examine label, E-press to start,
    consumes a lockpick from inventory on snap (not on attempt).
  - `LockpickingUI.gd` CanvasLayer overlay — radial dial, hold-timer driven by
    Lockpicking sub-skill tier (Novice 2.5s → Expert 5.0s); does not pause time.
  - Lockpick `ItemData` entries: Crude / Sturdy / Fine (Fine grants +1.5s hold bonus
    that stacks with skill tier).
  Pairs naturally with the interior-loading work in this phase: most lockable
  containers and doors live inside interiors. Reference: `design/LOCKPICKING.md`,
  `design/SKILLS_AND_PROGRESSION.md` → Lockpicking sub-skill,
  `design/ITEM_LIBRARY.md` for pick stats.

---

### Phase 9-3D — Act I Systems

- [ ] **`QuestManager.gd` autoload**
  `start_quest()`, `advance_quest()`, `complete_quest()`, `fail_quest()`. Quest flag
  namespace, journal entry creation, timed-event handoffs to `FlagScheduler`.
  Reference: `design/QUEST_SYSTEM.md`

- [ ] **`FactionManager.gd` autoload**
  Wraps GameState faction disposition flags; emits `disposition_changed` signal;
  applies rival-faction effects. Six Game One factions seed Game Three lockouts.
  Reference: `design/FACTION_SYSTEM.md`

- [ ] **Roland's journal panel** — Basic UI. Active quest, known people, Crown pieces.
  Written in Roland's voice. Does not need to be the full 5-tab journal for Act I.

- [ ] **`SaveSystem.gd` backup rotation update**
  Rest autosave hook, Wanderer's Seal manual save hook, three-deep backup rotation.
  Reference: `design/SAVE_SYSTEM.md`

---

### Post-Act I (Act II+)

- [ ] **`RecipeData.gd` resource class**
  Defines the data shape for a single crafting recipe (station type, ingredients,
  output, required flags). Must exist before CraftingUI or ItemData population.
  Reference: `design/CRAFTING.md` → GDScript Integration Notes

- [ ] **`ItemData.gd` additions: smithing_tier, condition, weight, item_category**
  Reference: `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` → GDScript Notes

- [ ] **`GameState.gd` additions: skill XP tracking and perk points**
  Reference: `design/SKILLS_AND_PROGRESSION.md` → GDScript section

- [ ] **`PlayerStats.gd` — wound HP tracking**
  Reference: `design/REST_AND_CAMP.md`

- [ ] **`CampMenuUI.tscn` + `CampMenu.gd`**
  Reference: `design/REST_AND_CAMP.md` → The Camp Menu

- [ ] **`CraftingUI.gd`**
  Reference: `design/CRAFTING.md`

- [ ] **Alchemy experimentation per `design/CRAFTING.md`**
  - `CraftingUI.gd` gains an Experiment path for the Alchemist's Still only.
    Unknown ingredient combinations produce either `Unfamiliar Potion` or
    `Foul Residue` ItemData.
  - `GameState.gd` additions: `failed_alchemy_combinations: Array` to prevent
    repeat attempts of known-bad combos.
  - Consumption discovery: when an Unfamiliar Potion is consumed, fire a 30–60s
    timer that surfaces effect, plays a Roland narration line, and either
    `unlock_recipe()` on benefit or sets a mild-nausea status on partial match.

- [ ] **Skills tab in `JournalUI.gd`**
  Reference: `design/SKILLS_AND_PROGRESSION.md` → Skill Screen Presentation

- [ ] **Populate `ItemData` resource files from ITEM_LIBRARY.md** — Act I subset first.
  Reference: `design/ITEM_LIBRARY.md`

- [ ] **`WeatherManager.gd` autoload**
  Reference: `design/WEATHER_AND_ENVIRONMENT.md`

- [ ] **`CompanionManager.gd` autoload**
  Reference: `design/COMPANION_SYSTEM.md`

- [ ] **HUD overhaul per `design/HUD_AND_UI.md`**

- [ ] **`Settings.gd` expansion per `design/ACCESSIBILITY_AND_SETTINGS.md`**

- [ ] **Vendor scripts per `design/ECONOMY_AND_VENDORS.md`**

---

## Section 8 — Design Decisions Still Needed

Open questions that need an answer before their dependent systems can be built.

- [ ] **Recipe placement map for Act I**
  Decide exactly which recipes Roland can find/learn in Act I. The Archive
  restricted section, Henrietta's quarters, and Old Mira the herbalist are the
  primary sources. Map each learnable recipe to a specific in-world source before
  building the Act I scenes. Reference: `design/CRAFTING.md` → Recipe Discovery

- [ ] **Trainer NPC placement confirmation**
  Ser Brenn (Solgrade), Fen the Duelist (Caer Brannoch), Old Mira (Aldenholt) —
  confirm each has a scene location, an NPC data entry, and a quest or disposition
  gate designed before Act II scene work begins.
  Reference: `design/SKILLS_AND_PROGRESSION.md` → Trainer NPCs

- [ ] **Camp upgrade delivery method for Acts I–II**
  Decide: is the portable Alchemist's Still a purchasable item, a quest reward,
  or found in the world? Same for the portable Assembly Table (currently "default
  from Act I safe-house"). Lock this down before building the camp upgrade system.
  Reference: `design/REST_AND_CAMP.md` → Camp Upgrades

- [ ] **The Iron Chalice debt — design the quest**
  Referenced throughout design docs as "Act I main quest" but the quest itself
  is not designed. What is the debt? To whom? How much? What are the 2–3 resolution
  paths? This is Act I's spine. Needs a quest brief before Act I scene work begins.

- [ ] **Act I side quest briefs**
  The quest system philosophy is complete but no actual Act I quests are documented
  beyond Old Mira's apprentice (which is a placeholder example). Write a brief
  (2–3 resolution paths) for each Act I side quest before scenes are built.
  Start from `lore/GAME1_PART1.md` story beats. Reference: `design/QUEST_SYSTEM.md`

- [ ] **Edran Vane — join scene and mechanical spec**
  Edran is confirmed as a companion. His join timing (after Aldenholt arc) and
  exact scene need to be designed. His mechanical role (investigation/dialogue
  specialist, non-combat) needs a full spec in `design/COMPANION_SYSTEM.md`
  before his scene is built. Reference: `lore/BACKSTORY_EDRAN.md`

- [x] **Lockpicking system — choose an approach** (resolved by `design/LOCKPICKING.md`)
  Resonance Pick radial dial system selected. Implementation tasks live in Section 7.

- [ ] **Endgame choices — resolve five open questions**
  ENDGAME_CHOICES.md is a working draft with five explicit open design questions
  (score visibility, reset points, save carryover, gating, path confirmation).
  Update companion roster (Edran is now confirmed). Not a Game One blocker but
  resolve before Game Two design begins.

---

## Section 9 — Verification Checklist (after each Godot session)

Run these after any session where you change scenes or scripts:

- [ ] World3D.tscn runs without errors in the Output panel
- [ ] WASD moves Roland (camera-relative); arrow keys rotate camera only
- [ ] Mouse drag: horizontal rotates Roland + camera; vertical tilts camera
- [ ] F2 hold = freelook (camera orbits without rotating Roland); release re-centers on both axes
- [ ] Scroll wheel zooms camera in/out (arm length 2m–10m)
- [ ] HP and endurance bars visible at bottom-center; values update live
- [ ] Hold Left Shift → sprint; endurance drains; sprint locks at 0; EXHAUSTED shows; sprint re-enables after recovery
- [ ] Press C → crouch toggle; speed drops; CROUCHING shows; sprint blocked while crouching
- [ ] Escape → pause menu (cursor visible); Resume → cursor hidden again
- [ ] J opens journal (6 tabs, Quests first); I opens inventory (Items tab); Tab key cycles tabs; clicking tab headers works
- [ ] Escape / J / I while journal open → closes overlay
- [ ] Press E near a dialogue trigger → Dialogic opens
- [ ] Campfire flickers (OmniLight3D energy varies)
- [ ] No "Autoload not found" warnings (means a required autoload isn't registered)
- [ ] (Post Milestone 5-3D) VoxelLodTerrain loads terrain chunks without errors; no "chunk generation" errors in Output
- [ ] No "Bus not found" errors when audio plays (means the audio bus layout from Section 1 is missing)
- [ ] No "InputMap action not found" errors (means an action from Section 1 isn't configured)
