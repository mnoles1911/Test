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

- [ ] **Verify Zylann `VoxelTool.get_voxel(Vector3i) → int` signature in-editor**
  The voxel-gravity system (`scripts/VoxelGravityManager.gd`) reads voxels via
  `tool.get_voxel(world_grid_pos)` to identify unsupported clusters after edits.
  This signature is documented in Zylann's reference but has churned across
  plugin versions, and the existing project code never called it before — so
  it's unverified against the version installed in `addons/zylann.voxel/`.
  How to verify:
  1. Open `World3D.tscn` in Godot 4.6.2 with the plugin installed.
  2. Run the scene. Pickaxe a single voxel out of the ground.
  3. Check the Output panel for `[VoxelGravityManager]` log lines reporting
     either "spawned cluster" / "scan complete" or a runtime error mentioning
     `get_voxel`.
  4. If you see an error like *"Invalid call. Nonexistent function 'get_voxel'..."*
     or a signature mismatch, the read loop in `VoxelGravityManager._process_bubble`
     needs the signature adjusted. Document the actual signature you see and ping
     for a follow-up commit.
  If gravity behaves as expected (carve a cliff overhang, watch it fall), the
  signature is correct and this task can be checked off.
  Reference: PR #127 (voxel gravity system).

- [ ] **Add a new voxel material (~10 minutes per material, no GDScript needed)**
  The voxel-type system shipped four pilot materials (stone, dirt, grass,
  sand). Adding more materials is the designer's job — anything from snow
  and marble to the 8 remaining materials specced in
  `design/ITEM_LIBRARY.md` lines 46–64 (clay, ash, raw log, hardwood log,
  iron ore, steel ore, adamant ore, coal). Process:
  1. In Godot's FileSystem dock, navigate to `assets/voxels/materials/`.
  2. Right-click → **New Resource** → search for `VoxelMaterial` → save as
     `<name>.tres` (e.g. `snow.tres`, `iron_ore.tres`).
  3. Click the new file. The Inspector now shows every field.
  4. Pick an unused `material_id` between 1 and 254. The registry prints
     used IDs to the Output panel at startup like
     `[VoxelMaterialRegistry] loaded 4 materials: stone(1), dirt(2),
     grass(3), sand(4)` — pick anything not in that list.
  5. Fill in: `id_string` (stable name), `display_name` (UI), color palette
     (`color_low` / `color_high` / `color_jitter`), `mining_time_seconds`,
     `allowed_tools` (array of tool item_ids — empty = any), `yield_item_id`
     + `yield_quantity`, `fall_behavior` (NEVER for solid like stone, SOLID
     for heavy clusters with custom gravity, LOOSE for sand/gravel),
     `gravity_scale` (multiplier — 1.0 default), `damage_multiplier`
     (multiplier on crush damage — 1.0 default).
  6. If `yield_item_id` references a new item, add it to
     `InventoryManager.ITEM_REGISTRY` following the existing pattern (see
     `raw_sand` for an example).
  7. Restart Godot. The registry validates and loads the new material.
  Reference: `design/3D_VOXEL_MIGRATION.md` → "Voxel Material System".

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

- [x] **Register `BarkManager` as an Autoload** (done — registered in `project.godot` `[autoload]` section)
  Path: `res://scripts/BarkManager.gd` → node name: `BarkManager`.
  Required for all bark lines to fire in-game; also unblocks NPC.gd which references the autoload directly.

- [x] **Register `WorldClock` as an Autoload** (done — registered in `project.godot` `[autoload]` section)
  Path: `res://scripts/WorldClock.gd` → node name: `WorldClock`.
  Required for NPC daily schedules and time-of-day bark triggers.

- [x] **Configure lock-on input action** (done — `lock_on` = Middle Mouse Button in project.godot)
  Camera rotation does NOT need Input Map actions for KB+M — `CameraRig.gd` reads
  `InputEventMouseMotion` directly. Arrow key fallbacks (`camera_left/right/up/down`)
  are live. Freelook (`freelook_camera` = F2) is also live. Reference: `design/CAMERA_AND_PERSPECTIVE.md`

- [ ] **Register `EntityRegistry` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/EntityRegistry.gd` → node name: `EntityRegistry`.
  Required before `EntityStreamer` can load/unload world entities. Build after `WorldGenerator`.

- [x] **Register `VoxelEditManager` as an Autoload** (done — registered in `project.godot` `[autoload]` section)
  Path: `res://scripts/VoxelEditManager.gd` → node name: `VoxelEditManager`.
  Handles async edit queue, EditedChunkRegistry, LOD-bake-on-eviction, NoEditZone enforcement, per-frame voxel budget. Reference: `design/3D_VOXEL_MIGRATION.md` → "Destructible Terrain".

- [x] **Register `NoEditZoneRegistry` as an Autoload** (done — registered in `project.godot` `[autoload]` section)
  Path: `res://scripts/NoEditZoneRegistry.gd` → node name: `NoEditZoneRegistry`.
  Tracks Area3D volumes assigned to the `no_edit_zone` group. Queried by `VoxelEditManager` before every voxel write. Listed before `VoxelEditManager` in autoload order so it initializes first (VoxelEditManager queries it on every edit).

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

- [x] **Set up the audio bus layout per `design/AUDIO_DESIGN.md`** (done — `default_bus_layout.tres` committed in PR #94)
  All 8 buses configured with correct routing: Master / Music / SFX (with Combat + Ambient children) / Voice (with NPC + Roland children) / UI.
  `Settings.gd` volume sliders target the bus names exactly as authored.

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

- [x] **`BarkOverlay` UI node — bark text display** *(2026-05-06)*
  Lives at `scripts/ui/BarkOverlay.gd`. Top-centre oak panel below the
  compass strip — 64×64 portrait placeholder (NPC's first initial in
  serif gold) + name (subtitle) + line (body). Joins the
  `bark_overlay` group in its own `_ready`; `BarkManager.fire` finds
  it via `get_first_node_in_group`. Built once at
  `HUDOverlay._build_bark_overlay()` so it's always present without a
  scene-tree edit; hidden by `_hide_all_chrome` in dev scenes.
  Followups: real portraits (`assets/portraits/{npc_id}.png`) once
  art lands; per-NPC display name (`NPCData.display_name` resource
  lookup is wired but the `.tres` files don't exist yet — falls back
  to `npc_id.capitalize()`).

- [ ] **"Press E to talk" world-space prompt**
  Appears above an NPC when the player is within interact range.
  Connected in `NPC.gd` (the two TODO comments at lines 149 and 154).

- [ ] **Extend `DebugOverlay` (F1) with NPC inspector**
  Show: active NPC name, current disposition, active schedule block, time of day.
  Useful for testing NPC schedules without guessing what WorldClock thinks it is.

- [x] **Quick-slot bar — Phase 1 (visual + number-key equip)** *(complete 2026-05-05)*
  4-slot HUD row bottom-centre, gold-bordered when equipped, number keys 1–4 swap
  to bound items. State lives in `InventoryManager._quick_slots` (`set_quick_slot` /
  `get_quick_slot` / `equip_quick_slot`). Default bindings seeded in
  `reset_for_new_game`: shovel / pickaxe / axe / powder_charge.
  LMB action is now equipment-aware via `ITEM_REGISTRY[item_id].type`:
    - `tool` → mine (held) via `EditToolHandler`
    - `throwable` → throw via `ThrowableHandler` (which short-circuits unless
      a throwable is currently equipped)
    - `bucket` / `bucket_filled` → fill / place via `EditToolHandler`

- [ ] **Quick-slot bar — Phase 2 (right-click rebind picker)**
  Right-click on any quick-slot panel → small modal lists every owned item with
  a clickable row → calls `InventoryManager.set_quick_slot(slot_idx, item_id)`.
  Stub already wired: `HUDOverlay._open_quick_slot_rebind_picker(slot_idx)` logs
  `Quick-slot N right-click — rebind picker not built yet` and the gui_input
  hookup on each slot panel routes RMB into it.
  Estimated work: ~60 lines in `HUDOverlay.gd` (panel layout + item list +
  click handler). Plus two-line addition to `InventoryManager.to_dict` /
  `from_dict` so chosen bindings persist across saves.
  Item-type filter to add at the same time: only show items with
  `type == "tool"` or `type == "throwable"` in the picker — raw materials
  (`raw_dirt`, `raw_stone`) shouldn't be slottable since they have no LMB
  action.

- [ ] **Quick-slot bar — Phase 3 (full inventory grid + drag-drop)**
  Press a hotkey (likely **I** or **Tab**) → opens a grid of all owned items.
  Drag-and-drop from the grid onto a quick-slot panel calls `set_quick_slot`.
  This is the "real" inventory UI per `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md`
  and obsoletes the Phase 2 right-click picker (or relegates it to a quick
  shortcut). Bigger build — half a day.
  Components ready to consume: `scripts/ui/Slot.gd` (UISlot,
  56×56 with drag-drop, rarity borders, durability bar, hotkey label),
  `scripts/ui/MenuTabBar.gd` (UIMenuTabBar with Inventory/Map/Journal/
  Codex/Skills tabs + close button). HTML mock at
  `assets/ui/html/Voxelmark Inventory.html` is the visual target.

---

### UI rework follow-ups (post 2026-05-06 retrofit)

The 2026-05-06 pass introduced `Colors` autoload + `UIStyles` helper +
`Slot` / `MenuTabBar` / `LoadingScreen` components, and retrofitted
`HUDOverlay`, `PauseMenu`, `MainMenu`, `Settings`, `SaveSlotPicker`, and
`TransitionManager`'s inline loading screen onto the Voxelmark palette.
The items below are what was deferred — visual targets all live in
`assets/ui/html/Voxelmark *.html`, the spec lives in
`assets/ui/css/menus_shared.css`.

- [ ] **Drop the missing fonts into `assets/fonts/`**
  Currently only `MacondoSwashCaps-Regular.ttf` is on disk. `UIStyles`
  silently falls back when these are missing — body text uses Godot's
  default font instead of VT323, and kbd chips use the default instead
  of Press Start 2P.
    - `VT323-Regular.ttf` (body / mono — wired at `UIStyles.FONT_MONO_PATH`)
    - `PressStart2P-Regular.ttf` (kbd chips — wired at `UIStyles.FONT_PIXEL_PATH`)
  Drop them in `assets/fonts/` and Godot's `_try_load_font` picks them up
  on next launch. No code change required.

- [x] **Loading screen rebuilt to match `Voxelmark Loading Screen.html`** *(2026-05-06)*
  Plus a perf fix landed the same day — see `design/LESSONS_LEARNED.md`
  entry for "Loading screen ran at <10 FPS". `TransitionManager._show_loading_screen`
  hides the `HUDOverlay` and `JournalUI` CanvasLayers (their compass /
  chrome `_draw` calls were the real cost on the single-threaded
  `gl_compatibility` renderer) and sets `viewport.disable_3d = true`.
  Restored in `_hide_loading_screen`. **Critically the destination
  scene + voxel autoloads are NOT paused** — Zylann's chunk loading
  is exactly what the 20 s – 1.5 min hold exists for, so we leave it
  ticking.
  `TransitionManager`'s inline loader is a faithful port of the mock:
    - **Hourglass** (`scripts/LoadingHourglass.gd`, rewritten): brass
      caps + 4 brass pillars (front bright, back dimmed) + asymmetric
      glass diamond outline + top sand triangle (drains as p→1) +
      bottom mound (grows as p→1) + 38-grain particle simulation with
      gravity + mound collision. Computes in mock-space (40×60) and
      scales to the Control's actual size. Driven from
      `TransitionManager._process` via `set_progress`.
    - **Bobbing animation**: sin-driven ±2 px Y translate on the
      hourglass over a 5.2 s cycle, runs every frame regardless of
      progress so the screen stays alive during chunk-stream pauses.
    - **Vignette + tint**: full-screen tint at 0.62 black + a radial
      darken vignette via inline canvas_item shader (matches the mock's
      `inset 0 0 240px rgba(0,0,0,0.7)` box-shadow).
    - **Title**: "L O A D I N G" in serif gold, 44 px with hard 3 px
      black shadow. Letter-spacing faked via spaces between letters.
    - **Centred message**: rotates every 2.5 s through the 24 quips
      (LOADING_QUIPS), 0.4 s fade-out → swap → fade-in transition.
    - **Progress bar**: 520×8 dark-leather track with a sand-gradient
      fill (deep → bright) drawn via a tiny canvas_item shader; trailing
      24 px white-fade highlight in the same shader. Percentage label
      below in serif gold.
    - **Bottom TIP footer**: gold "TIP" prefix (BBCode-coloured) +
      italic body, rotates through TIPS_GAMEPLAY (13 short useful
      tips, separate cadence — 8 s). Distinct from the centred quip.
  Followups for full mock parity (low priority polish):
    - Warm grain overlay (CSS `repeating-linear-gradient` + overlay
      blend) — could be a small canvas_item shader.
    - Hourglass elliptical drop-shadow below the diamond.
    - 3D-style rotateX/rotateY tilt on the hourglass — needs a Sprite2D
      with skew or a SubViewport, not viable on a flat Control.
    - 6 px letter-spacing on the percentage label — Godot Label has no
      native letter-spacing.

- [ ] **Swap `scripts/ui/LoadingScreen.gd` into `TransitionManager`
  (consolidate the loader)**
  `scripts/ui/LoadingScreen.gd` still exists as a parked alternative
  loader, but TransitionManager's inline implementation is now the
  authoritative one — and richer (background-art rotation, music
  adoption, quip + tip rotation). The standalone scene can either be
  retired (delete it) or fleshed out to match the inline loader so it
  becomes a clean drop-in. Lowest priority since the inline loader
  already does the job.

- [x] **Retrofit `JournalUI` / `Journal.tscn` onto `UIStyles`** *(2026-05-06)*
  The 6-tab journal overlay (Quests / Map / Items / Crafting / Codex /
  Skills) is now on the Voxelmark palette. `Journal.tscn` was already a
  bare CanvasLayer wrapper — all chrome is built in `JournalUI._build_ui`,
  so the retrofit was script-only:
    - Backdrop tinted with `Colors.BG_NIGHT`.
    - Frame uses `UIStyles.menu_body_panel()` (oak gradient + black border).
    - Title → `UIStyles.apply_title_label("ROLAND'S JOURNAL", 32)`.
    - Hint line → `UIStyles.apply_muted_label`.
    - Dividers → `Colors.PANEL_OAK_EDGE`.
    - Tab buttons → `UIStyles.apply_tab_button(active)` — gold-seam oak
      panel for the active tab, dim oak for inactive. Replaces the old
      modulate-tint approach.
    - Content → `UIStyles.apply_body_label`.
  Followups: the content area is still a single scrolling Label.
  When richer per-tab layouts are wanted (multi-column quest list,
  inventory grid via `UISlot`, parchment-styled codex pages), the
  Label-only fallback can be replaced tab-by-tab while keeping the
  shell.

- [ ] **Build the five tabbed panels** (Inventory grid, Map page, Journal
  page, Codex entries, Skills tree) using `UIMenuTabBar` + `UISlot`
  Each panel is its own scene that hosts a `UIMenuTabBar` instance at the
  top, listens for `tab_changed`, and swaps which content `Control` is
  visible below. Inventory consumes a grid of `UISlot` instances with
  drag-drop; Map renders Roland's hand-drawn world map; Codex is
  parchment text entries; Skills draws the perk tree per
  `design/SKILLS_AND_PROGRESSION.md`. Visual targets:
  `assets/ui/html/Voxelmark Inventory.html`, `Map.html`, `Journal.html`,
  `Codex.html`, `Skills.html`.

- [x] **HUD overhaul — chrome pass to match `Voxelmark HUD v1.html`** *(2026-05-06)*
  Added: crosshair, compass strip (rotating cardinal markers + degree
  ticks + red needle, driven by player heading), top-right clock strip
  (DAY / time / period band, driven by `WorldClock`), vital icons
  (♥ heart, ⚡ lightning) next to each bar, hotbar item tooltip that
  surfaces on equip-change, full-screen damage pulse on health drop,
  low-HP heartbeat pulse below 25 % HP. Vitals stack moved bottom-left
  to match the mock; FPS readout moved bottom-right to free the top-
  right corner for the clock.

- [ ] **HUD overhaul — followups not yet implemented**
  Mock elements that need underlying gameplay systems before they can be
  wired:
    - Hunger + Mana vital bars (no Hunger system; Mana arrives with the
      magic kit later in Game One)
    - Buff / debuff tray top-left (no buff system yet — see
      `design/SYSTEMS_DESIGN.md` for the planned shape)
    - Quest tracker right-side panel (waits for `QuestManager`)
    - XP bar above the hotbar (waits for the skills system to expose a
      currently-leveling sub-skill)
    - Floating damage numbers (needs an enemy-damage event signal)
    - Bark overlay portrait + text framing (the `BarkManager` autoload
      writes spatial audio today; the on-screen overlay belongs in
      `BarkOverlay` per Section 6 above)
    - Biome name in the clock strip (currently shows "★ MIRA-THAL ·
      <PERIOD>" as a placeholder — wire to the active region/zone
      tag once `WorldNavigation` ships region detection)

- [ ] **Visit the existing `assets/ui/css/menus_shared.css` against
      `Colors.gd` for drift**
  The CSS is the source of truth; the GDScript palette is a hand
  port. If the CSS gets edited (especially the `:root` custom-property
  block), re-port the changed lines into `assets/ui/Colors.gd`. There's
  no automated check — eyeball it whenever the CSS changes.

- [ ] **Theme.tres pass once the design stabilises**
  Right now every UI scene calls `UIStyles.apply_*` at runtime. Once
  the look is locked, bake the same StyleBox / FontVariation resources
  into a `Theme` resource that the project sets at
  `Project Settings → GUI → Theme → Custom`. Cuts the runtime overhead
  and lets the editor preview the actual chrome on `.tscn` nodes.

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

### Phase 5-3D — Open World Foundation (Editable Terrain) ✅ LARGELY COMPLETE (2026-05-03)

- [x] **`CubicHeightmapGenerator` (custom GDScript)** — replaces the originally-planned VoxelGeneratorGraph + Gaea EXR pipeline. `VoxelGeneratorScript` subclass in `scripts/CubicHeightmapGenerator.gd`, attached to the `VoxelLodTerrain` node in `World3D.tscn`. Writes `CHANNEL_COLOR` per voxel via macro + mid + detail noise layers + per-voxel colour jitter. Live-tunable in the Inspector via `@export_range` sliders + `Preset` enum (LAY_OF_THE_LAND / MINECRAFT_BLOCKY / SMOOTH_GRADIENT / CUSTOM). The Gaea pipeline may return for v1 Mira authoring; for now this generator is sufficient.

- [x] **`VoxelEditManager.gd` autoload** — registered in `project.godot`. Async edit queue (per-frame voxel budget 200000), `EditedChunkRegistry` (`Dictionary<Vector3i, bool>`), NoEditZone enforcement, world→voxel coord conversion (`terrain.to_local()` + `1/scale.x` for radii), `WORLD_GENERATOR_VERSION = 7` stamped into saves. Public API: `queue_edit_sphere(pos, radius, voxel_value) -> bool`, `queue_edit_box(...)`, `queue_set_voxel(...)`. Returns false on NoEditZone rejection.

- [x] **`NoEditZoneRegistry.gd` autoload** — registered in `project.godot`. Provides `is_point_inside_no_edit_zone(world_pos: Vector3) -> bool`. Queried by `VoxelEditManager` before every voxel write.

- [x] **First edit verb (pickaxe) wired in** — `EditToolHandler.gd` (child of Player3D). Camera raycast → `VoxelEditManager.queue_set_voxel` (carves a 0.5 m bite) → material yield to InventoryManager (`raw_stone` etc.) → Mining sub-skill XP via `GameState.add_skill_xp`.

- [x] **Test NoEditZone in `World3D.tscn`** — 10×10×10 m Area3D at world (8, 5, 0) registered to `no_edit_zone` group. Pickaxe + explosive carves inside it are silently rejected.

- [x] **Explosive throwables wired in** — `PowderCharge.gd` + `ThrowableHandler.gd`. Camera-aimed (carries pitch), inventory-driven AOE (`voxel_aoe_radius` in `ITEM_REGISTRY`), visible OmniLight3D + emissive sphere flash on detonation.

- [x] **Save / load wiring for editable terrain** — `GameState.save_game()` calls `VoxelEditManager.flush_pending_edits()` then writes JSON state including `WORLD_GENERATOR_VERSION` stamp + `WorldClock` time + `_skill_xp` + `InventoryManager` save data. Load validates the version stamp (hard error on mismatch).

- [x] **Swimming + drowning state machine** — `Player3D._update_water_state` polls `water_volume` group. `WaterVolume.gd` exposes `surface_y` (world-space) and `get_current_velocity()`. Ocean raised to Y=6 so water is accessible at average terrain elevation. Drowning ticks at 5 HP/s after 30 s submerged.

- [x] **Day/night cycle** — `DayNightCycle.gd` on `World3D` rotates Sun/Moon `DirectionalLight3D` and lerps sky/fog colours each frame from `WorldClock`'s continuous hour float.

- [x] **Movement mechanics** — Jump on Space (when grounded, 7 m/s velocity, ~1.22 m peak), debug fly mode (F1 toggle, teleports to 100 m, 10× walk speed, no gravity).

- [ ] **`EntityStreamer.gd` stub** — Node in `World3D.tscn`. Phase 5 version just prints
  chunk coordinates to Output as player moves. Full entity loading in Phase 6. **Not yet
  needed** — current world has no streamed entities beyond Player3D.

#### Outstanding for Phase 5-3D polish (defer to next batch):
- [ ] **Roland low-poly Blender model** — currently a 0.4×1.7×0.25 m green box placeholder.
- [ ] **MagicaVoxel exports** — campfire prop, cave wall props.
- [ ] **Surface decoration pass** — scatter 1-3 voxel vertical pillars (grass / stone / flowers, color-varied) on terrain top during generation. Biggest remaining visual gap vs. the Lay-of-the-Land reference look.
- [ ] **LOD-bake-on-eviction caching** — `user://saves/slot_{N}/mesh_cache/`. Render optimization, not correctness gate. Defer until perf becomes an issue.
- [ ] **Multi-slot voxel save directories** — currently `user://voxel_deltas.sqlite` is shared. Refactor to `user://saves/slot_{N}/voxel_deltas.sqlite` once save-slot UI is exercised.

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

## Section 9 — Future ideas (parking lot — not blocking any milestone)

Ideas captured during dev that aren't on the critical path. Each is
a short pitch; promote to a real section when scope is committed.

- **Player blueprint capture system** — let the player inspect any
  voxel arrangement they encounter or build (a hut they made, a
  cliffside watchtower they like, a settlement gatehouse they
  walked past in a NoEditZone) and capture it as a saved
  "blueprint". Mechanic sketch:
  - In Build Mode, a new "Capture" submode lets the player
    drag-select a 3D bounding box around the target structure.
  - The system reads voxel-delta data + placed schematics in the
    volume and writes them out as a `PlayerBlueprint` resource —
    name, dimensions, material manifest, voxel + schematic
    contents.
  - Blueprints live in `user://saves/slot_{N}/blueprints/` (or a
    shared `user://blueprints/` cross-save library) so they
    survive across playthroughs.
  - In Build Mode → Blueprint submode, the player picks a
    captured blueprint from a list. A translucent ghost previews
    placement; rotate / mirror options on the ghost. Materials
    from inventory are consumed on confirm (or the blueprint
    drops as a buildable outline that fills in over time as the
    player adds materials, à la Valheim build sites).
  - Capture from inside a NoEditZone is allowed (read-only); it's
    the *placement* that NoEditZone protection blocks.
  - Lore framing: Roland keeps a folio of sketches. Captured
    structures appear as journal entries with hand-drawn
    elevations.
  - Implementation surface: extends the existing Schematic
    system (`SchematicLibrary` autoload). Blueprints become a
    second category alongside crafted schematics.
  - Affects: `design/3D_VOXEL_MIGRATION.md` →
    "Player-Built Structures", `design/CRAFTING.md` →
    "Carpentry Bench", `design/JOURNAL_UI.md` (a Blueprints tab
    or sub-tab), `design/SAVE_SYSTEM.md` (per-slot blueprint
    folder vs. cross-save library — designer call).
  - Not blocking; pencil in for post-Act-I when player
    construction has been exercised.

- **WeatherManager polish — deferred from PR #132 code review (2026-05-04).**
  Self-review surfaced these. Each is functionally tolerable today; bundle
  for a future cleanup pass.
  - **Lightning arms on `current_state == HEAVY_RAIN`, not `_target_state`.**
    Means strikes don't start firing until the 30 s fade-in completes, and
    they keep firing for up to 30 s after target leaves HEAVY_RAIN. Slightly
    inconsistent with rain particles (which ramp via `_live_*` interpolated
    values). Fix: arm/disarm based on `_target_state == HEAVY_RAIN`, or on a
    `_live_rain_density > threshold` check so all rain visuals share one gate.
  - **`assets/profiles/mira_temperate.tres` uses raw int State values.**
    `authored_sequence = Array[int]([1, 0, 1, 2])` silently breaks if the
    `WeatherManager.State` enum is reordered. Fix options: (a) add a comment
    in `WeatherLocationProfile.gd` documenting that the ints must match
    enum positions, (b) switch `authored_sequence` to `Array[String]`
    ("overcast", "clear", ...) and resolve via `STATE_NAMES` at load time.
  - **`Vector3(NAN, NAN, NAN)` sentinel for `trigger_lightning_strike()`.**
    Code smell — relies on `is_nan()` checks. Cleaner: split into
    `trigger_lightning_strike()` (random) and `trigger_lightning_strike_at(pos)`,
    or use a separate `bool has_pos` flag.
  - **`_advance_wind_direction` early-returns on near-zero `wind_direction`.**
    Theoretical foot-gun: if external code sets `wind_direction` to zero,
    the lerp locks up forever. The field is private so it's defence-in-depth.
    One-line fix: fall back to `(1, 0, 0)` when zero.
  - **`_ambient_warned_missing` is reused for both ambient OGGs and
    `thunder_distant.ogg`.** Functionally fine (no key collisions), but the
    `_ambient_` prefix is semantically wrong for thunder. Rename or split.
  - **Tween callbacks may run after WeatherManager is freed on quit.**
    All callbacks check `is_instance_valid` so this is safe today, but
    shutdown ordering quirks could surface a write to a freed Tween.
    Low-risk; address if it ever shows up in the log.

- **HorizonSkirt — triplanar texturing for distant terrain (Copper Isles + future regions).**
  Today the baked skirt mesh (`assets/voxel/copper_isles_skirt.res`,
  `scripts/_dev/SkirtBaker.gd` + `scripts/HorizonSkirt.gd`) reads as
  vertex-colour bands with per-vertex noise. Lit by Cascaded Shadow
  Maps and shaded as 3-stop elevation gradient (forest → rock →
  snowcap), it's a clear upgrade over the original flat-grey, but it
  still reads as "low-LOD distant terrain" up close — uniformly tinted
  slopes without surface texture detail.
  
  Production open-worlds (Skyrim, BotW, Horizon, Witcher 3) push
  past this with **triplanar texturing**: project a small set of
  tileable rock / grass / snow / sand textures onto the mesh from
  three world axes simultaneously and blend by surface normal. Steep
  faces get rock; flat tops get grass/snow; slopes get a blend.
  Looks great at any distance and works for ANY mesh (no per-vertex
  UV unwrap needed — exactly what we want for a baked-from-heightmap
  skirt).
  
  Implementation surface:
  - Author or source 4 seamless tileable PBR textures: rock, grass,
    snow, sand. ~512×512 each, RGB albedo + R-channel roughness +
    optional normal map. Royalty-free options: ambientCG, Polyhaven.
  - Custom shader (`assets/shaders/horizon_skirt.gdshader`) doing
    three triplanar projections per texture, blended by normal.
    Texture selection per-pixel by world-Y (elevation) + slope
    angle (dot of normal with up).
  - Replace the StandardMaterial3D currently set up programmatically
    in `HorizonSkirt._ready()` with the shader material. Vertex
    colour can stay as a tint multiplier for biome variation.
  - Same shader will be useful when a "voxel terrain LOD2+" custom
    material lands — voxel mesher's vertex-colour-only output looks
    chunky at distance for the same reason. Triplanar over the
    LOD pyramid would close the visual gap to industry-standard.
  
  Effort estimate: ~1 day for the shader + texture sourcing + first
  tune; 1-2 more days to author per-region texture variants (Mira
  swamp, Thal coast, etc.) once Copper Isles is dialled in.
  Affects: `scripts/HorizonSkirt.gd`, `scripts/_dev/SkirtBaker.gd`
  (vertex-color tint role), new `assets/shaders/horizon_skirt.gdshader`,
  new `assets/textures/terrain/{rock,grass,snow,sand}_*` directories.
  Reference for technique: search "Godot 4 triplanar shader" or
  Catlike Coding's "Triplanar Mapping" tutorial.

- ~~**EditToolHandler: mining carve collapses to 1×1×1 on some voxels (FP bug, 2026-05-05).**~~
  **Fixed 2026-05-05.** Added `VoxelEditManager.queue_edit_box_voxels(min: Vector3i,
  max: Vector3i, value: int)` and updated `EditToolHandler._carve` to use it.
  Integer voxel-grid coords bypass `_terrain.to_local()` FP rounding entirely.

- ~~**EditToolHandler: right-click smooth fails on untouched terrain at first load (2026-05-05).**~~
  **Fixed 2026-05-05.** `_tick_held_action` now allows the smooth verb to proceed when
  material is null (Zylann first-load streaming gap). Falls back to 0.5 s hold time
  and "terrain" display label. `_do_smooth` reads its own cell data independently.

- ~~**CRITICAL: Voxel-color byte-order encoding mismatch — terrain renders
  nearly black instead of per-material colors (diagnosed 2026-05-05).**~~
  **Misdiagnosed and fixed differently 2026-05-05.** The actual bug was NOT
  byte order — the original `(c.to_rgba32() & 0xFFFFFF00) | mat_id` encoding
  was correct (Zylann reads bytes in the same order Godot's `to_rgba32`
  emits: R high, A low). The real bug was that
  `VoxelBuffer.CHANNEL_COLOR` defaults to **8-bit depth** (1 byte per
  voxel), which truncates 32-bit packed values down to just the low byte
  (the mat_id slot). The mesher then sees only the mat_id (1-4) as a tiny
  R value, producing the near-black render. The byte-order rewrite was
  reverted; the real fix sets `VoxelLodTerrain.format` to a `VoxelFormat`
  resource with `set_channel_depth(CHANNEL_COLOR, DEPTH_32_BIT)` —
  see `scripts/World3DBootstrap._configure_voxel_format`.

  **How we found it:** the `[ReadMat]` diagnostic showed
  `tool.get_voxel(...) → 0x00000061` (just the R byte) instead of the full
  `0x03388C61`. The `[World3D]` terrain dump revealed the format property
  and the available API on it. After turning the format depth to 32-bit, a
  bright-blue terrain confirmed the byte order was correct in the original
  encoding (the byte-order rewrite was emitting bytes such that mat_id
  ended up where the mesher reads R, which is what the test ruled out).


## Section 10 — Verification Checklist (after each Godot session)

### Per-session quick check

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

### Voxel gravity system (PR #127 — one-time)

Walks the gravity-system scenarios end-to-end. Run once after the
plugin is installed and the project launches without parse errors.
If any test fails, the first diagnostic is the Output panel — every
gravity-related script logs with a `[VoxelGravityManager]` /
`[FallingVoxelCluster]` / `[VoxelEditManager]` prefix.

- [ ] **Single-voxel collapse**: pickaxe a voxel out of a flat surface, then pickaxe the voxel directly above it. The exposed voxel above falls and re-deposits.
- [ ] **Cliff overhang collapse**: fly mode (F1 toggle in DebugOverlay) up to a cliff edge, carve the supporting wall with the pickaxe. Overhang detaches as one cluster, falls, lands, becomes terrain again.
- [ ] **Powder charge ceiling drop**: dig a small tunnel under flat terrain, throw a powder charge at the ceiling support. Disconnected ceiling chunk falls on Roland and deals damage proportional to size + fall height.
- [ ] **NoEditZone respect**: place a NoEditZone near a cliff. Carve under the cliff. Cluster falls but does NOT re-deposit any voxels inside the NoEditZone (boundary voxels vanish silently).
- [ ] **Tipping**: build a tall thin voxel column (1×8×1, ~1.3 m), carve the bottom from one side. Column tips toward the cut and re-deposits as a horizontal log. NOT a vertical column dropped one voxel down.
- [ ] **Boulder drop**: build a 4×4×4 voxel cube, remove its support. Drops more or less straight with minor wobble.
- [ ] **L-shaped overhang**: build an L-shape supported only at one end, carve the support. Rotates around its TRUE centroid (not its bounding box centre) as it falls.
- [ ] **Performance under stress**: detonate 5 powder charges in quick succession against a stepped cliff. Frame time stays under 33 ms; check Output for queue depth logs.
- [ ] **Save/load round-trip**: trigger a collapse, save (campfire interaction or Wanderer's Seal), quit, reload. Re-deposited voxels are present in their landing positions.

### Voxel material system (PR #129 — one-time)

Validates the type system end-to-end. Run once after PR #129 merges
and the project relaunches. The material system replaces a lot of the
generator + mining flow, so this list is more thorough than usual.

**Startup**

- [ ] **Registry load**: launch the project. Output panel shows `[VoxelMaterialRegistry] loaded 4 materials: stone(1), dirt(2), grass(3), sand(4)`. If you see "loaded 0 materials" the .tres files aren't in `assets/voxels/materials/` (check the FileSystem dock).
- [ ] **No autoload errors**: no `[VoxelMaterialRegistry]` push_error or push_warning lines on launch (other than the expected "InventoryManager not available" warning if InventoryManager loaded after — should NOT happen given the load order; flag if it does).
- [ ] **ID collision detection**: temporarily edit `dirt.tres` and set `material_id = 1` (collision with stone). Relaunch. Expect a loud `push_error` mentioning both `dirt.tres` and `stone.tres` and refusing to register the duplicate. Revert dirt.tres back to material_id=2.

**Visuals**

- [ ] **Surface colour bands**: open `World3D.tscn`. Surface should be visibly green (grass), beaches near the test water volume tan (sand), exposed cliff faces and underground grey (stone). Brown dirt visible as a thin layer between grass and stone wherever you cut into a hillside.
- [ ] **No uniform colouring**: each material has subtle per-voxel jitter — individual cubes should be readable as separate cubes, not a flat painted wall.

**Mining time per material**

- [ ] **Stone is slow**: equip iron_pickaxe, hold attack on a stone voxel. ~0.8 s should pass before the voxel breaks.
- [ ] **Dirt is fast**: equip iron_shovel, hold attack on a dirt voxel. ~0.3 s before break.
- [ ] **Grass is fast**: shovel on a grass voxel — also ~0.3 s.
- [ ] **Sand is fastest**: shovel on a sand voxel — ~0.2 s.
- [ ] **Held timer resets on target switch**: hold attack on a stone voxel for 0.5 s, then look at a different voxel before the first one breaks. The new voxel should require its FULL mining time from zero (the old swing time doesn't transfer).

**Yield per material**

- [ ] **Stone yield**: pickaxe a stone voxel → `raw_stone` count in inventory increments by 1.
- [ ] **Dirt yield**: shovel a dirt voxel → `raw_dirt` increments.
- [ ] **Grass yields dirt** (intentional): shovel a grass voxel → `raw_dirt` increments (NOT a separate "raw_grass").
- [ ] **Sand yield**: shovel a sand voxel → `raw_sand` increments.

**Tool gating**

- [ ] **Pickaxe on sand fails**: equip iron_pickaxe, hold attack on sand. Nothing breaks (sand's `allowed_tools = [iron_shovel]`).
- [ ] **Shovel on stone fails**: equip iron_shovel, hold attack on stone. Nothing breaks.
- [ ] **Right tool works**: equip iron_pickaxe on stone OR iron_shovel on dirt/grass/sand. Mining proceeds normally.

**LOOSE column-fall (sand)**

- [ ] **Single sand voxel falls**: dig out a single voxel from under a sand patch. The sand voxel directly above falls into the hole instantly (no rigid-body cluster, no tumble, just a one-voxel snap).
- [ ] **Sand stack pours**: stack 4–5 sand voxels above an air gap. Carve out the column underneath. The whole stack pours down to fill the gap.
- [ ] **Sand stops on solid**: dig out the support of a sand stack but leave a stone voxel underneath. Sand lands on the stone and stops there.

**Per-material gravity (rigid-body clusters)**

- [ ] **Stone falls slightly faster than dirt**: build a stone column and a dirt column side-by-side, both 4 voxels tall, both unsupported. Carve their supports. Stone (`gravity_scale = 1.0`) hits the ground slightly faster than dirt (`gravity_scale = 0.9`). Subtle but observable.
- [ ] **Stone hurts more than dirt**: stand under a stone ceiling and a dirt ceiling of the same size and fall height. The stone collapse deals more damage (`damage_multiplier = 1.2` vs `0.7`).

**Save / load**

- [ ] **Save preserves materials**: trigger a few edits (carve different materials), save, quit, reload. The world looks identical — every voxel still has the right material colour and you can still mine each one with the right tool. Yields are unchanged.
- [ ] **Old-save rejection**: launch with a save written before the version bump (any save file from PR #127 or earlier). Expect a `WORLD_GENERATOR_VERSION` mismatch error per documented policy. The error should be visible to the player, not a silent crash.

**Designer ergonomics (the headline test)**

- [ ] **Adding a new material under 15 minutes**: stop the project. In the FileSystem dock, navigate to `assets/voxels/materials/`. Right-click → New Resource → search for `VoxelMaterial` → save as `snow.tres`. In the Inspector, fill in:
  - id_string = "snow"
  - material_id = 5 (free per the registry's startup print)
  - display_name = "Snow"
  - color_low = white-tinted blue, color_high = pure white, color_jitter ≈ 0.05
  - mining_time_seconds = 0.2
  - allowed_tools = [iron_shovel]
  - yield_item_id = "raw_snow"
  - yield_quantity = 1
  - fall_behavior = LOOSE
  - damage_multiplier = 0.3

  Add `raw_snow` to `InventoryManager.ITEM_REGISTRY` (one line, follow the existing pattern). Restart Godot. Output panel should show `loaded 5 materials: stone(1), dirt(2), grass(3), sand(4), snow(5)`. **Total time goal: under 15 minutes from "decide to add snow" to "snow is in the registry."** If it takes longer, the system needs UX work — file a follow-up.

**Performance**

- [ ] **No frame stutter on common edits**: pickaxe rapidly through a hillside (mixed grass/dirt/stone). Frame time stays under 16 ms (60 FPS) on the dev machine.
- [ ] **No frame stutter on collapse**: detonate a powder charge against a cliff face (mixed materials, includes some sand for LOOSE-fall testing). Frame time stays under 33 ms.

### Water system upgrade (PR — one-time)

Validates the new wave shader, vertical swim, breath delay, and underwater filter end-to-end. Run once after PR merges.

**Visuals**

- [ ] **Animated waves**: open `World3D.tscn`, run. Both the test pond and the ocean surface show animated wave displacement (not flat planes). Crests visibly lighter than troughs.
- [ ] **No seam between adjacent water bodies**: if two volumes overlap or sit edge-to-edge, the wave pattern lines up (world-space XZ as wave domain ensures phase alignment).
- [ ] **Wave inspector tuning live**: while running, click the test `WaterVolume` in the editor. Drag `wind_strength` from 0 to 3 — waves grow taller in real time. Drag `wind_direction` from `(1, 0, 0)` to `(0, 0, 1)` — wave roll direction shifts.

**Vertical swim**

- [ ] **Ascend on Space**: walk into the test pond. Press and hold Space. Roland climbs at ~3 m/s.
- [ ] **Descend on Crouch**: in water, press and hold Crouch. Roland dives at ~3 m/s.
- [ ] **Float on release**: in water, release both. Vertical velocity decays to zero — Roland holds depth.
- [ ] **Crouch toggle suppressed in water**: pressing Crouch underwater does NOT toggle the standing crouch state. Surface, walk to dry land — Roland is upright (status text not "CROUCHING").

**Breath system**

- [ ] **Submerged drains breath**: dive head-fully under, watch HUD status text. Counts down `BREATH: 30s` → 0 over 30 seconds.
- [ ] **Drowning damage starts at 0 breath**: hold under for 35+ seconds. Status flips to "DROWNING", HP starts dropping at ~5 HP/s.
- [ ] **2 s recovery delay**: drain breath to ~10s, surface fully (status flips to "SWIMMING"). For ~2 seconds breath stays at 10s. Then it climbs back up at 8/s.
- [ ] **Recovery delay resets on re-submerge**: surface for 1 s (less than the 2 s delay), dive again. Submerge → resurface — the delay still pauses 2 s before refill, not 1 s.

**Underwater filter**

- [ ] **Tint visible when submerged**: dive head-fully under. Screen takes on a translucent blue-green tint.
- [ ] **Tint clears on surface**: surface — tint disappears immediately.
- [ ] **No tint when waist-deep but head dry**: walk in until waist is wet but head is above the surface. No tint.
- [ ] **Tint clears on fly mode**: dive, toggle fly mode (F1 debug overlay → TOGGLE FLY MODE). Tint clears.

**Designer ergonomics — adding a new water body**

- [ ] **Under 5 minutes from idea to swim**: stop the project. In the FileSystem dock, duplicate `scenes/water/water_volume.tscn` as `scenes/water/swamp_pool.tscn`. Drop one instance into World3D at a new location. Set `surface_y` and (optionally) `wind_direction` / `wind_strength` in the inspector. Run. Pool animates with its own wind values, swim physics works, breath/drowning gate as expected. Goal: under 5 minutes from "decide to add water" to "swimming in it." If longer, file a follow-up.

**Future WeatherManager smoke test**

- [ ] **set_wind() works at runtime**: from the editor's Remote inspector while running, call `WaterVolume_Test.set_wind(Vector3(0, 0, 1), 3.0)`. Waves shift direction and grow taller without restarting the scene.

### Voxel water refactor (PR — one-time)

Validates the voxel-based water sim that replaced the Area3D `WaterVolume` model. Run once after the PR merges. Supersedes most of the "Water system upgrade" checklist above — the underwater filter and breath system are unchanged, but everything else (wave shader, swim physics, water authoring) is now driven by `WaterFlowManager`.

**Sources & static water (Phase 1–2)**

- [ ] **Test pond appears**: load `World3D.tscn`. The `World3DBootstrap.add_source_region` call in the script seeds a 10×3×10m AABB at world (-18, 0, 4). A wavy animated water surface should render there (Phase 2 emits the top-plane mesh).
- [ ] **Ocean appears at sea level**: a 200×200m water surface should render at world Y=8. Walk the camera around — chunks within 64m of the player have meshes; beyond that they're culled.
- [ ] **Walk into pond → swim physics activate**: motion mode flips to FLOATING, status text "SWIMMING", vertical swim controls work.
- [ ] **Submerge head**: status text "BREATH: 30s" counts down. Underwater filter (blue-green tint) visible.
- [ ] **Bare shovel on bank does nothing visible**: we removed the WaterVolume Area3Ds; there's no scene-Tree water node to delete or move.

**Gravity drop (Phase 3)**

- [ ] **Pickaxe under the pond**: equip iron_pickaxe, swing at a stone voxel directly under the pond bank. Within 4 ticks (~1 s), water drops into the new air voxel. Continue carving downward — water cascades down the column.
- [ ] **Side-tunnel from the pond**: carve a horizontal tunnel out from the pond at sea level. Water doesn't flow yet (gravity-only Phase 3), but the air voxels stay dry. (Lateral spread is Phase 4 below.)

**Lateral spread + decay (Phase 4)**

- [ ] **Horizontal channel fills**: with the side-tunnel from the previous step, water now flows along it. Cells visibly thinner (lower level) the further from the source. Stops 7 cells out from the source (level 8 → 1 → 0).
- [ ] **Channel evaporates when source removed**: dig out the source-region edge so the channel no longer connects to the pond AABB. Within ~10 seconds the entire channel evaporates as monotone-decay drains it.
- [ ] **NoEditZone blocks water**: place a NoEditZone Area3D (with attached `NoEditZone.gd` script, `blocks_water_flow=true`) across a player-dug channel. Water dams against the boundary — no cells inside the zone.
- [ ] **NoEditZone with blocks_water_flow=false lets water through**: toggle the same zone to false. Water flows in.

**Save/load (Phase 5)**

- [ ] **Bucket placement persists**: equip the bucket, fill at the pond, place a water source on a hill. Save (`F5` or campfire). Quit. Reload. The placed source is still there; its downhill cascade is still flowing within a few ticks.
- [ ] **Pre-v11 saves invalidate**: try to load a save from before the refactor. Should log a version mismatch or refuse to load (per the existing `voxel_generator_version` gate in `GameState.load_save_file`).

**River currents (Phase 6)**

- [ ] **No current in still water**: float in the middle of the pond — no horizontal drift.
- [ ] **River pushes player downstream**: place a chain of bucket sources stepping down a slope (a river headwater above, terrain channel leading down). Swim into the channel — Roland drifts toward the lower end. Stronger drift where the level gradient is steeper.
- [ ] **Ocean interior calm**: swim into the middle of the ocean source region. No drift in any direction (every neighbor is also level 8).

**Bucket tool (Phase 7)**

- [ ] **Empty bucket fills at water**: equip the bucket. Click while in the pond (or aimed at any water cell within 2.5m). Bucket → bucket_filled. Inventory shows the swap.
- [ ] **Filled bucket places water**: equip bucket_filled. Aim at empty space (in air). Click. A water source appears at that voxel. Bucket → bucket. The source begins cascading downward.
- [ ] **Bucket place rejected by NoEditZone**: aim into a NoEditZone with `blocks_water_flow=true`. Click. Output panel logs "Bucket place rejected: NoEditZone." Bucket stays filled.
- [ ] **Bucket place rejected by solid voxel**: aim into a stone voxel. Click. Output logs "Bucket place rejected: voxel solid." Bucket stays filled.

**Performance**

- [ ] **No frame stutter on edits near water**: pickaxe rapidly through the pond bank for 10+ seconds. Frame time stays under 16 ms (60 FPS) on the dev machine. WaterFlowManager flow tick costs visible in the profiler — should be < 2 ms per 4 Hz tick.
- [ ] **Out-of-radius dirty chunks don't burn frames**: build a deep mineshaft 50m+ from any water. Dig rapidly. Flow tick should NOT process those chunks (they're outside ACTIVE_RADIUS_M=20m around the player).

---

## Section 11 — Verification: WeatherManager (2026-05-04)

### Audio assets needed (system runs silent without these)

WeatherManager logs a one-time warning per missing OGG and continues — it never crashes. Drop these files at the listed paths to unlock the corresponding audio bed.

- [ ] `assets/audio/ambient/wind_low.ogg` — quiet wind for FOG / SNOW
- [ ] `assets/audio/ambient/wind_med.ogg` — moderate wind for OVERCAST
- [ ] `assets/audio/ambient/rain_light.ogg` — gentle rain for LIGHT_RAIN
- [ ] `assets/audio/ambient/rain_heavy.ogg` — heavy rain for HEAVY_RAIN
- [ ] `assets/audio/ambient/thunder_distant.ogg` — single rumble, ~3 s, used per lightning strike

### In-Godot verification

**State machine**

- [ ] **Initial state**: open `World3D.tscn` → run. Sky / fog / ambient match a CLEAR or OVERCAST baseline (depends on whether a profile is set).
- [ ] **Force-set via debug overlay**: F1 → COMMANDS → WEATHER... → click each of the six state buttons. Within 30 s, fog density, sky tint, ambient brightness, and wind strength all transition smoothly to the new state.
- [ ] **Live readouts update**: while submenu open, `Current:` updates as the transition completes; `Wind:` updates every frame.
- [ ] **CLEAR OVERRIDE**: click during a forced state. Override clears; weather returns to schedule-driven state.

**Wind**

- [ ] **Direction is gradual**: open WEATHER submenu and watch the `Wind:` line for ~2 minutes. The (x, z) values lerp slowly — never snap, even when forcing rapid state changes.
- [ ] **Strength tracks state**: HEAVY_RAIN drives ocean wave amplitude visibly higher than CLEAR. Switch back to CLEAR — waves calm within 30 s.

**Particles**

- [ ] **Rain follows the camera**: HEAVY_RAIN, walk forward 30 m. Rain particles stay above and around the camera the whole time.
- [ ] **Rain slants in wind**: HEAVY_RAIN, watch the falling streaks. They slant in the current wind direction; angle shifts gradually as wind direction drifts.
- [ ] **Snow drifts slowly**: SNOW state. White flakes fall at ~1.5 m/s², visibly slower than rain.
- [ ] **CLEAR has no particles**: switch to CLEAR. No emission.

**Wet-terrain visual**

- [ ] **Layer A overlay**: HEAVY_RAIN. Screen has a subtle blue-grey tint (alpha ~0.18). Tint fades to transparent within 30 s when switching to CLEAR.
- [ ] **Layer B specular sheen**: walk to a stone outcrop during HEAVY_RAIN. Surface visibly darker; sun catches a wet sheen on highlights.
- [ ] **Layer B disengages**: switch to CLEAR. Terrain returns to dry vertex-color rendering within 30 s.
- [ ] **Phase 8 graceful fallback**: if your Zylann build doesn't expose `material_override` on `VoxelLodTerrain`, Layer A still shows. No crash.

**Lightning**

- [ ] **Random strikes during HEAVY_RAIN**: stay in the state for 30+ seconds. At least one strike fires.
- [ ] **Force lightning**: click `FORCE LIGHTNING` in WEATHER submenu. Strike fires immediately. Repeat 5+ times — strike position (and thus directional flash) varies.
- [ ] **Directional cue**: when a strike fires, the side of the world facing the strike brightens noticeably more than the opposite side.
- [ ] **Thunder spatial**: thunder rumble comes from the strike's direction (3D audio panning). Far strikes have a longer flash → thunder gap than near strikes.

**Story override**

- [ ] **Override lasts duration**: in the editor remote inspector, call `WeatherManager.set_weather_override("heavy_rain", 0.01)` (≈ 36 real seconds). After ~36 s, weather returns to schedule.

**Schedule rolls**

- [ ] **Hourly rolls only at scheduled hours**: F1 → ADVANCE TIME... → step through several days. Weather rolls happen at hours 6 / 12 / 18, not other hours.
- [ ] **Authored Mira-temperate sequence**: load mira_temperate.tres via `WeatherManager.set_location_profile()`. Days 1–4 follow the authored opener (overcast / clear / overcast / light rain) at hour 6.

**WeatherZone**

- [ ] **Place a test zone**: in `World3D.tscn`, drop an Area3D with `WeatherZone.gd`, `weather_state="fog"`, BoxShape3D ~10 m extents near the campfire. Walk in. State swaps to FOG within 30 s. Walk out — state returns to scheduled.

**Save / load**

- [ ] **Round-trip current state**: enter HEAVY_RAIN. Save. Quit Godot. Reopen the save. Weather is still HEAVY_RAIN.
- [ ] **Round-trip override timer**: set a 1-hour override. Save. Reload. Override timer has the remaining hours intact.

**Performance**

- [ ] **No frame stutter on state change**: cycle through all 6 states rapidly. Frame time stays under 16 ms.
