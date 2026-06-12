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

- [x] **VoxelLodTerrain set up in `World3D.tscn`** (done — adapter → C++ `CubicHeightmapGeneratorCpp` generator, `VoxelStreamSQLite` stream, `VoxelMesherBlocky` mesher with `VoxelBlockyLibrary`. The early-pivot plan to use `VoxelGeneratorGraph` + Gaea EXR was replaced by the C++ generator. See `CLAUDE.md` → "Voxel + world systems".)

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

- [ ] **Verify graphics quality presets across all five tiers**
  PR #235 added `GraphicsManager` (autoload) + a GRAPHICS QUALITY cycle
  button in Settings. Only **HIGH** — the default, which mirrors
  `World3D.tscn` exactly — has been visually verified. Run `World3D.tscn`,
  open Settings, cycle the GRAPHICS QUALITY button through
  POTATO / LOW / MEDIUM / HIGH / ULTRA and confirm each reads as a
  deliberate visual *step*, not just HIGH with effects switched off:
  watch MSAA edge cleanliness, SSAO/SSIL crevice depth, shadow
  sharpness, glow, and ULTRA's SDFGI. The chosen tier persists to
  `user://graphics.json` and re-applies on next launch. If the tiers
  don't feel cohesive, that is the deferred **Phase F preset rebalance**
  pass — note which tier looks wrong and how.
  Reference: `design/GRAPHICS_PASS_2026-05-19.md` → "Phases F / H / K — SHIPPED".

- [x] **Visual gate — graphics Phases G / I / J** — PASSED (2026-05-22, PR #238)
  G (AtmosphereProfile), I (tangent-free terrain relief), J (emissive
  voxels cast coloured light) all verified in-editor. Designer testing
  caught one bug — emissive copper buried in solid rock lit the surface
  through the terrain in a player-following radius — fixed so only
  air-exposed emissive voxels register a light. Glowing ore, the
  day-cycle, and ULTRA-tier SDFGI global illumination all confirmed good.

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

- [x] **Verify + tune the DistantTerrain streaming heightmesh** — DONE
  via PR #240 (2026-05-26). The branch closed with `lod_count=4`,
  `view_distance=512 vox`, `DistantTerrainManager.inner_cull_radius=130 m`,
  `albedo_tint=(0.70, 0.85, 0.55)`. The streaming pipeline went from "outrun
  LOD0 in 10 s" to "designer confirmed cannot out run the streaming." The
  bright-skirt-ghosting-through-hills bug fixed by the new shader tint.
  Outstanding: LOD1+ water-surface line artefact (separate water-shader work,
  not a DistantTerrain issue — see CLAUDE.md 2026-05-26 milestone).

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

- [ ] **Drop the five 10cm-vision reference screenshots into `design/inspiration/`**
  These were shared in the 2026-06-12 chat session. The agent cannot write chat images
  to disk — you need to save them manually. Exact filenames (case-sensitive):
  - `ref_01_grass_blades.png` — Lay of the Land riverbank: dense per-blade grass, voxel flowers, freshly dug dirt patch, teal water behind.
  - `ref_02_waterfall_dig.png` — Lay of the Land player-dug shaft: teal waterfall pouring in, orange-sand walls, grey stone at the bottom.
  - `ref_03_medieval_tower_vista.png` — Shader-grade render: round stone tower, broadleaf forest, cobble bridge, volcanic mountain background.
  - `ref_04_vista_volcano.png` — High aerial view: volcano, forests, farmland, beaches, ocean, voxel-style clouds.
  - `ref_05_golden_hour_godrays.png` — Golden hour: stone church tower, visible god rays, red-flowered riverbank, glowing lantern post.
  Once they're in place, `design/VISION_VOXEL_10CM.md` has full written descriptions
  alongside each image so the doc stands alone even if the images can't be displayed.
  Reference: `design/inspiration/README.md`, `design/VISION_VOXEL_10CM.md`.

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

### SFX (sound effects) — pipeline live, raw takes committed

The SFX system is fully built and wired (`AudioManager` autoload, all
rendered families hooked, no-op-safe). 548 raw ElevenLabs takes are
committed in `assets/audio/sfx/` and audible in-game — but **uncurated**
(rough / again-identical takes still in each set). See
`design/SFX_PROMPTS.md` §8 / §8b for the full record.

- [ ] **SFX quality pass — prune-in-place curation** (no credits, no code)
  For each `<id>` set under `assets/audio/sfx/<folder>/`: audition the
  `<id>_NN.mp3` takes (cross-ref the Desktop `0_KEEP` labels), **delete the
  weak ones from the repo folder**. Loop ids → keep the one best seam-
  checked take (loop-seam recipe in `assets/audio/sfx/README.md`);
  variation ids → keep the strongest 3–5. Footstep takes are the weakest
  source — flag any id that needs a re-roll. Optionally convert keepers to
  `.ogg` (`ffmpeg -i in.mp3 -ac 1 -ar 44100 -c:a libvorbis <id>_NN.ogg`; a
  matching `.ogg` auto-supersedes the `.mp3`). Then flip those entries to
  EXISTING in `design/SFX_LIBRARY.md`. This is the single biggest lever on
  "the SFX sound rough."
- [ ] **Render Combat SFX (Cat 02)** next ElevenLabs billing cycle
  ~9,585 credits, fits one fresh monthly cycle. Run
  `python tools/render_sfx.py --category 02 --credit-cap 11000` with
  `ELEVENLABS_API_KEY` set (see the `.env` step above). Then curate the
  new `combat/` takes and the Combat call sites become wireable (the only
  remaining unwired family).
- [ ] **(Optional) Re-roll the weakest footstep ids** during the Combat
  cycle — regenerate the footstep rows in `SFX_PROMPTS.md §2`, re-curate.

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

### Phase 4-3D — Camera, Movement, Health/Endurance, HUD, UI ✅ COMPLETE

CameraRig (standard + freelook + scroll zoom + lock-on API), Player3D (sprint/crouch/mass-scaled movement/HP/endurance/status_text), HUDOverlay autoload, JournalUI 6-tab programmatic overlay, PauseMenu, DebugOverlay, SaveNotification, NPC.gd `mass` export. See `CLAUDE.md` → "3D core in place".

---

### Phase 5-3D — Open World Foundation (Editable Terrain) ✅ COMPLETE (2026-05-03)

C++ `CubicHeightmapGeneratorCpp` generator (was GDScript, ported 2026-05-11), `VoxelEditManager` + `NoEditZoneRegistry` autoloads, pickaxe edit verb via `EditToolHandler`, `PowderCharge` + `ThrowableHandler`, save/load with `WORLD_GENERATOR_VERSION` validation, swim/drown state machine, `DayNightCycle`, jump + F1 fly. See `CLAUDE.md` → "Voxel + world systems".

**Outstanding Phase 5-3D polish (defer to next batch):**
- [ ] Roland low-poly Blender model (currently green box placeholder).
- [ ] MagicaVoxel exports — campfire, cave wall props.
- [ ] Surface decoration pass — 1-3 voxel vertical pillars (grass / flowers) on terrain top during generation.
- [ ] LOD-bake-on-eviction caching at `user://saves/slot_{N}/mesh_cache/` — deferred until perf demands.
- [ ] Multi-slot voxel save dirs — refactor `user://voxel_deltas.sqlite` → per-slot path when save-slot UI is exercised.
- [ ] `EntityStreamer.gd` full implementation (stub on disk only prints chunk-enter events).

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

- [x] ~~**Water Voxel V2: Minecraft-model water**~~ — **DONE.** Native-fluid pivot landed (PR #225/227), full underwater experience landed (PR #232, merged 2026-05-20). Water is now Zylann-native `VoxelBlockyModelFluid` at `CHANNEL_TYPE` ids 16–23; the original V2 transparent-cube plan was superseded by the native-fluid pivot mid-flight. Final architecture in `design/SWIMMING_AND_WATER.md`. Native-fluid decision record: `design/WATER_STAGE6_PLAN.md`. Current shader spec + deferred Phase 4b–4f items: `design/WATER_SHADER_V3_PLAN.md`.

- [ ] **Water Phase 4b–4f — deferred follow-up work (specs in `design/WATER_SHADER_V3_PLAN.md`)**
  Optional polish on top of the now-complete underwater experience (PR #232). None blocking; pick any when art direction wants them.
  - **4b — Caustics on the seabed.** Animated sun-through-waves projection on submerged terrain (NVIDIA GPU Gems Ch.2 approach: orthographic projector + tiled animated noise). Cost: small. Iconic dappled-light look.
  - **4c — Per-biome fog/extinction.** Read water-body biome at player position; shift `underwater_fog_albedo_*` + `underwater_fog_density_*` anchors. Swamp green, glacial ice-blue, muddy river brown. Needs a biome lookup API.
  - **4d — Planar terrain reflection.** Second Camera/Viewport rendering the world mirrored about the water plane into a sampled texture. The only correct way to see trees/cliffs reflected on water (current Fresnel sheen is sky-only). Cost: medium.
  - **4e — Underwater audio coupling.** Low-pass filter on the master bus while submerged + ambient bubble/current loop. Pairs with the visual murk; small effort once `AudioManager` bus routing is exposed.
  - **4f — Per-pixel screen-space water lerp.** Sea-of-Thieves-class bisected-view effect at half-submerged camera angles. Big-budget bar; requires extra render pass + per-pixel water-surface mask. Spec in V3 plan.

- [ ] **Weather V2: extended profile knobs + elevation modifier**
  Adds sky_top_color / sky_horizon_color / sun_energy / sun_color / wetness / snow_density / gust_intensity to every state profile, then layers an altitude-zone modifier (LOWLAND / RIDGE / ALPINE) on top so high-elevation play feels distinctly windier + colder + eventually snow-bound regardless of the rolled base state. Includes a new `WINDY` base state. Five implementation phases A–E.
  Reference: `design/WEATHER_V2_PLAN.md`

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

- **Weather rework — FRAMEWORK BUILT, ALL VISUALS DEFAULT-OFF.**
  Designer playtest verdict (2026-05-27): "rain visuals look really
  bad… god rays are not visible… needs hours of player iteration and
  VFX and SFX work on another day." All visual phases (A rain shader,
  B wet-terrain + splashes, D god rays) gated behind GraphicsManager
  toggles defaulting OFF — scene baseline preserved, system inert.
  Phase C (audio crossfade envelope) stays live as an objective
  improvement over the linear-dB tween, even if it also needs more
  iteration. Phase E (rainbow shader) stays live but the test was at
  midday so antisolar was below horizon — arc is geometrically
  invisible at high-sun angles even with a working shader.

  **What this means:** the foundation is on disk and ready for a
  dedicated multi-session iteration pass. Each phase is one
  GraphicsManager toggle flip away from being live for tuning. To
  iterate later:
  1. F1 → COMMANDS → GRAPHICS / POST-FX. Flip RAIN VISUALS ON to
     start tuning the rain shader / wet-surface / splash particles.
     Phase A still needs redesign per "looks really bad" — likely
     wants an artist-authored streak texture instead of pure
     procedural.
  2. Flip LIGHT SHAFTS ON to start tuning god rays per-state
     (`vol_fog_density / _length / _albedo` in `STATE_PROFILES`).
  3. Rainbow: trigger via FORCE RAINBOW NOW and stand at dawn or
     dusk where antisolar is above horizon (azimuth + elevation
     logged each second so designer knows where to face).
  4. Audio: tune `WeatherEnvelopeProfile` (lead_seconds /
     fade_seconds / curve_pow / lowpass sweep) or author per-state
     resources.

  Original per-phase implementation testing checklist for the future
  iteration session:
  - **Rain visual (Phase A).** Set HEAVY_RAIN via DebugOverlay WEATHER
    sub-view. Confirm: streaks come in gradually over the 30 s
    transition (not on/off); streaks remain visible at every camera
    angle including looking straight down; streaks lean with wind
    direction; vanish when player submerges. Old GPUParticles3D rig
    available behind the `rain_3d_fallback` toggle for A/B comparison.
  - **Rain audio (Phase C).** Same trigger. Confirm: audio onset is
    immediate (no ~5 s lag vs the visual); ramp feels like a build-up,
    not a switch; bed sounds "muffled → open" as the low-pass sweep
    completes. Designer may want to tune `WeatherEnvelopeProfile` knobs
    (curve_pow, lowpass_hz_low/high, fade_seconds) — author per-state
    Resources if a state needs a different feel.
  - **God rays (Phase D).** Set CLEAR at midday. Confirm: visible
    volumetric shafts where the sun cuts through occluding geometry
    (tree trunks, building edges). Set HEAVY_RAIN — shafts should
    fully vanish. UnderwaterFilter on-submerge override still works.
  - **Rainbow (Phase E).** Set HEAVY_RAIN → wait 30 s → set CLEAR.
    Watch the `[WeatherManager] Rainbow ramping up: ... antisolar
    az=X° el=Y°` log line — face that azimuth + look slightly up.
    Should see the arc form over 30 s. If invisible, hit the
    DebugOverlay WEATHER sub-view "RAINBOW DEBUG" toggle to draw the
    band at full alpha regardless of state, confirming the geometry.
    "FORCE RAINBOW NOW" triggers without needing the rain transition.
  - **Wet terrain (Phase B follow-on).** Same HEAVY_RAIN trigger.
    Stone / dirt / grass surfaces should darken slightly and pick up
    a specular sheen from the sun (roughness drop). Small splash ring
    particles appear on the ground around the player.

  Authoring opportunity: per-state `WeatherEnvelopeProfile` Resources
  in `assets/weather/envelopes/` once the designer wants per-bed feel
  (e.g. fog rolls in slowly with a tighter low-pass; rain crashes in
  with a brighter cutoff). Plumb `STATE_PROFILES["envelope"]` ->
  `_swap_ambient_audio` picks the profile by state.

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

- **DistantTerrain — triplanar texturing for the distant heightmesh.**
  (Was "HorizonSkirt triplanar texturing"; the baked HorizonSkirt was
  retired 2026-05-22 — this now applies to the streaming
  `DistantTerrainManager` heightmesh, which inherited the skirt's
  vertex-colour palette via `assets/shaders/distant_terrain.gdshader`.)
  The distant heightmesh reads as vertex-colour bands with per-vertex
  noise — a 3-stop elevation gradient (forest → rock → snowcap) plus a
  slope-to-rock shift. Coherent at distance, but it reads as untextured
  "low-LOD terrain" if the player gets near the blocky↔smooth handoff
  band — uniformly tinted slopes without surface texture detail.
  
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

- **GPU fluid via compute shaders — real simulated waves + flow.**
  Explore replacing the current authored-look water (flat voxel
  surface + Beer-Lambert depth-fade + Fresnel in `water.gdshader` /
  `water_horizon.gdshader`) with an actual GPU-simulated fluid:
  height-field / shallow-water sim or FFT ocean run as a Godot
  `RenderingDevice` compute shader, producing real propagating
  waves, wakes, and directional flow instead of a static tinted
  sheet. Captured 2026-05-16 out of the water-shader-v2 work.
  - This is a *visual/simulation feature*, NOT a performance task —
    note explicitly: the shader does not move to C++ (GPU work
    stays on the GPU; C++ is CPU-side). Compute shaders are still
    GLSL-family, run on the graphics card.
  - Scope unknowns to investigate before committing: interaction
    with the per-voxel `WaterFlowManager` sim (does GPU water stay
    purely cosmetic on top of the gameplay water bytes, or does it
    feed back?); how it reads against the chunky voxel art
    direction (real waves may fight the blocky aesthetic — needs an
    art-direction call); cost of a compute pass every frame vs the
    current near-zero shader cost; how it behaves on the giant
    follow-player horizon plane.
  - Likely starts as a contained spike: FFT or Gerstner-wave ocean
    on the horizon plane only, leaving near-water and gameplay
    water untouched, to judge the look before any deeper integration.
  - Affects (if promoted): `assets/shaders/water.gdshader`,
    `scripts/WaterFlowManager.gd`, `design/SWIMMING_AND_WATER.md`,
    `design/WATER_SHADER_V3_PLAN.md`, `design/ART_DIRECTION.md`
    (aesthetic sign-off). (`scripts/WaterChunkMesher.gd` deleted in
    the native-fluid pivot — water is now Zylann-native.)
  - Not blocking anything. Revisit only if the authored look proves
    insufficient in playtest or after a profiler capture shows
    headroom we want to spend on water fidelity.

(Three 2026-05-05 bug entries removed: EditToolHandler 1×1×1 carve, right-click smooth on untouched terrain, voxel-color encoding mismatch — all fixed. The CHANNEL_COLOR 32-bit lesson is captured in CLAUDE.md "Critical GDScript patterns" and `design/LESSONS_LEARNED.md`.)

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

### Voxel gravity system (PR #127) — verified 2026-05-03

Single-voxel collapse, cliff overhang, powder-charge ceiling drop, NoEditZone respect, tipping, boulder drop, L-shape true-centroid rotation, stress test, save/load round-trip — all passed at PR landing. Re-run only if `VoxelGravityManager.gd` or `FallingVoxelCluster.gd` change materially.

### Voxel material system (PR #129) — verified 2026-05-04

Registry load + ID collision, per-material mining time / yield / tool gating, LOOSE column-fall (sand), per-material gravity & damage, save/load — all passed. Re-run only if `VoxelMaterial.gd` schema or `VoxelMaterialRegistry.gd` change.

**Adding a new material (target: under 15 min — reusable recipe):**
1. FileSystem dock → `assets/voxels/materials/` → Right-click → New Resource → `VoxelMaterial` → save as `<name>.tres`.
2. Pick an unused `material_id` between 1 and 254 (Output panel prints used IDs at startup).
3. Fill in: `id_string`, `display_name`, color palette, `mining_time_seconds`, `allowed_tools`, `yield_item_id`, `yield_quantity`, `fall_behavior` (NEVER/SOLID/LOOSE), `gravity_scale`, `damage_multiplier`.
4. If `yield_item_id` is new, add it to `InventoryManager.ITEM_REGISTRY`.
5. Restart Godot. Output should show `loaded N+1 materials: ...`.

### Water systems (Area3D upgrade + voxel-water refactor) — verified 2026-05-05

Wave shader, vertical swim, breath/drowning, underwater filter, NoEditZone water gating, bucket tool, river currents, save/load — all passed during the May refactor. The Area3D `WaterVolume` design was retired and replaced by `WaterFlowManager` (host-only sim) + `WaterChunkMesher` (C++ since PR #214). Re-run only if `WaterByteCodec` layout or `WaterFlowManager` rules change.

### WeatherManager (PR #132) — verified 2026-05-04

Six-state machine + fog/wind/particles/lightning + location profiles + WeatherZone + save/load — all passed. Re-run only if state machine or trigger priorities change.

**Audio assets still needed** (system runs silent without these — drop OGGs at the listed paths):
- [ ] `assets/audio/ambient/wind_low.ogg` (FOG / SNOW)
- [ ] `assets/audio/ambient/wind_med.ogg` (OVERCAST)
- [ ] `assets/audio/ambient/rain_light.ogg` (LIGHT_RAIN)
- [ ] `assets/audio/ambient/rain_heavy.ogg` (HEAVY_RAIN)
- [ ] `assets/audio/ambient/thunder_distant.ogg` (per-strike rumble, ~3 s)

## River currents (W7, 2026-06-10)

- Place `RiverFlowVolume` nodes (scripts/RiverFlowVolume.gd) over each
  story-river stretch (the Aldwater first): add a Node3D, attach the
  script, point `flow_direction` downstream, size `extent` to the
  channel. Bootstrap stamps them at world load; swim in to feel the
  push. Diagonal stretches = a chain of volumes alternating cardinals.
- In-engine acceptance for the finite-water rework: pour a 3x3x3 of
  buckets on flat ground -> wide shallow LEVEL pool within seconds,
  `[FlowDiag-finite] conserve=OK`; scoop back -> pool shrinks. Blast a
  sub-sea crater -> ocean refill unchanged. Wade a shallow pool -> no
  swim mode, no underwater filter (intentional, W5).
- Rebuild the Windows DLL (extensions/voxel_gen, scons platform=windows)
  to restore the C++ settle scan (W2 changed its source-gate inputs).
- Buoyancy acceptance (PR 7): fell a tree into a pond — the log
  cluster should bob up, drift, and settle as a floating raft; mine
  stone into the same pond — it sinks. Tune per-material
  `density_relative_to_water` in assets/voxels/materials/*.tres to
  taste (< 1 floats).
- Tree-sever + buoyancy acceptance (PR 6/7) — **BLOCKED 2026-06-12: no
  trees exist in World3D yet.** Once trees are authored (log + leaves
  voxels), chop one at the base: expect ONE 'spawned cluster' line and
  the whole tree tipping as one piece; fell one into a pond: the log
  floats and rafts, stone sinks. Tune `sever_follow_max_height_m` on
  VoxelGravityManager if any authored tree exceeds 12 m. The logic is
  gated headless (`sever`, `gravity` selectors) — this is feel-only.

## Water polish (PRs 3-5, 2026-06-10)

- **Caustics (PR 3, default OFF):** flip `caustics` in the DebugOverlay
  GRAPHICS view, then eyeball a shallow pond at noon — dancing light
  ridges on the lakebed, fading out by ~6 m depth. Dial: the 0.6
  strength constant in GraphicsManager._apply_caustics_global.
- **Per-biome underwater fog (PR 4):** add a Node3D with
  scripts/WaterBiomeZone.gd over the swamp water, size `extent` to the
  body, tune the green-murk anchors (defaults are already swampy).
  Submerge inside it -> green murk; outside -> scene defaults.
- **Underwater audio (PR 5):** SFX + Ambient buses low-pass to 700 Hz
  while submerged (live now). The bubble ambience bed needs an asset:
  render `underwater_ambience` via tools/render_sfx.py into
  assets/audio/sfx/water/ — until then submerge logs a one-time
  missing-asset warning and stays silent.

## 10cm voxel re-architecture — R1 acceptance (2026-06-12)

- **Scale feel check (World3D):** stand Roland against a cliff — he
  should read ~17 voxels tall (1.7 m at 10 cm/voxel). A single-voxel
  dig hole reads as a 10 cm pock, not a 17 cm bite. The ocean sits at
  the same world height as before (12 m); familiar coastline and peak
  shapes are preserved (amplitudes were rescaled to the same metres).
- **Pickaxe default now carves 5x5x5** (same ~0.5 m physical bite as
  the old 3x3x3 at the coarser grid). Scroll wheel still cycles down
  to 1 for true 10 cm precision digging — try both; if you'd rather
  the finer default, say so and we flip one constant.
- **Pour a bucket into a 1 m pit** — collapse/leveling should look
  unchanged (reach is still 3 m; it's 30 voxels now under the hood).
- **F7 in CopperIslesTest** now cycles 10 -> 6 -> 8 vox/m (10 is the
  canonical entry). Any pre-2026-06-12 baked Copper Isles SQLite is
  invalid — delete + re-bake via BakeWorld when you next need it
  (see design/COPPER_ISLES_BAKE_NOTES.md).
- **Expect slower streaming this build** — perf retune is the next
  phase (R2); judge feel, not framerate, until it lands.

## 10cm voxel re-architecture — R2 acceptance (streaming/LOD retune, 2026-06-12)

R2 retuned streaming + LOD for the 10 vox/m scale: blocky terrain band
~86 m (view_distance 864 vox, lod_count 4 -> 5), DistantTerrain inner
cull 130 -> 100 m, water/edit/gravity per-frame budgets scaled for the
~4.63x denser voxel grid. The following are FEEL + PROFILER checks the
designer runs in the editor (the headless harness only covers data/logic):

- **Profiler budget capture (the gate):** in `scripts/Profiler.gd` set
  `capture_on_startup = true`, F6 World3D, then run the **standard
  route — sprint the coastline for 60 s** (the same route used for the
  2026-05-13 baseline). On the RX 7800 XT the capture must show **median
  frame < 5 ms**, **p99 < 16 ms**, and **no streaming spike > 50 ms**.
  Flip `capture_on_startup` back to false afterward. Drop the capture
  JSON into `design/captures/` and analyse it with
  `tools/_analyze_capture.py` (the p50/p99/spike recipe is also in
  `design/PROFILER_AND_DIAGNOSTICS.md`).
- **If the budget FAILS — the 640-voxel retreat dial:** set
  `World3DBootstrap.terrain_view_distance_voxels` from 864 to **640**
  (~64 m blocky band, ~45% fewer streamed chunks) AND nudge
  `DistantTerrainManager.inner_cull_radius` from 100 to ~75 m so the
  overlap band stays gap-free. Re-capture; report which value held.
- **F12 clipbox overlay — confirm you don't out-walk the loader:** tick
  "Diag Enabled" on the World3DBootstrap node, press F12, sprint a long
  straight line. The player must stay inside the streamed clipbox — no
  trailing edge of unloaded terrain catching up to Roland. If it lags,
  that's the retreat-dial signal too.
- **F11 LOD-band shader — eyeball ring placement:** press F11 and walk;
  confirm the green LOD0 disc stays centred on the player and the
  coloured bands step outward at roughly the expected radii (LOD0 ~12.8 m,
  doubling each ring). Mis-centred bands = a viewer-offset regression.
- **Terrain collision ends at 12.8 m (known, not a bug):** projectiles /
  AI beyond ~12.8 m have no terrain collision at this scale. Don't file
  it — the fallback is a separate logged follow-up
  (`design/3D_VOXEL_MIGRATION.md` "10 vox/m hard constraint").
