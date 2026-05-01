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

- [ ] **Install Zylann's Voxel Tools plugin**
  Open Godot → AssetLib tab → search "Voxel Tools" → install → enable in
  Project Settings → Plugins. Required for Milestone 5-3D (terrain generation).
  Reference: `design/3D_VOXEL_MIGRATION.md`, `design/ART_PIPELINE.md`

- [ ] **Configure the full Input Map per `design/INPUT_AND_CONTROLS.md`**
  Project Settings → Input Map → add each action below. The full table with controller
  bindings is in the design doc; minimum keyboard defaults:
  - `interact` — E (required by `DialogueTrigger3D.gd` and `NPC.gd`)
  - `sprint` — Left Shift
  - `attack` — Left Mouse Button (tap = light, hold ≥0.20s = power)
  - `block` — Right Mouse Button (hold = block, tap = parry)
  - `dodge` — Space
  - `lock_on` — Middle Mouse Button (or Tab)
  - `quick_slot_next` — Q / `quick_slot_prev` — E (in-combat context)
  - `open_journal` — J
  - `open_inventory` — I
  - `pause` — Escape
  - `debug_overlay` — F1
  - `camera_left` / `camera_right` — only if `CameraRig.allow_horizontal_rotation` is enabled
  Note: `interact` and `quick_slot_prev` both default to E — context is resolved in
  `Player3D.gd` by checking `near_interactable` state.

- [ ] **Register `BarkManager` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/BarkManager.gd` → node name: `BarkManager`.
  Required for all bark lines to fire in-game. Reference: `design/NPC_SYSTEM.md`

- [ ] **Register `WorldClock` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/WorldClock.gd` → node name: `WorldClock`.
  Required for NPC daily schedules and time-of-day bark triggers. Reference: `design/NPC_SYSTEM.md`

- [ ] **Configure camera and lock-on input actions** (required for third-person camera)
  Project Settings → Input Map → Add:
  - `camera_left` (Q), `camera_right` (E)
  - `camera_up` / `camera_down` (right stick vertical or mouse Y)
  - `lock_on` (middle mouse button or right stick click)
  Required by the third-person `CameraRig.gd`. Without these the camera cannot rotate
  and lock-on cannot engage. Reference: `design/CAMERA_AND_PERSPECTIVE.md`

- [ ] **Register `EntityRegistry` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/EntityRegistry.gd` → node name: `EntityRegistry`.
  Required before `EntityStreamer` can load/unload world entities. Build after `WorldGenerator.gd`.

- [ ] **Register `WorldGenerator` in `World3D.tscn`**
  Add `VoxelLodTerrain` node to `World3D.tscn` → assign `WorldGenerator.gd` as its generator script.
  Configure LOD count (6–8 levels), LOD0 radius (~60m), `VoxelMesherTransvoxel` as mesher.
  Reference: `design/ART_PIPELINE.md` → Tool 2, `design/3D_VOXEL_MIGRATION.md`

- [ ] **Set up the audio bus layout per `design/AUDIO_DESIGN.md`**
  Bottom panel → Audio → add buses: `Music`, `SFX` (with children `Combat`, `Ambient`),
  `Voice` (with children `NPC`, `Roland`), `UI`. Save as `default_bus_layout.tres`.
  Required before any music or voiced dialogue work — `Settings.gd` volume sliders
  target the bus names exactly as written above.

---

## Section 2 — Godot Editor: Scene Work

Scene building and node configuration that has to be done in the editor.

- [ ] **Verify Milestone 4-3D in Godot**
  Open `scenes/World3D.tscn` and run it. Confirm:
  - WASD / arrow keys move the placeholder character on the flat floor
  - Camera follows in third-person over-shoulder; right stick / Q/E rotates it
  - Campfire glows orange and flickers
  - No clipping through the floor
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

- [ ] **Create local `.env` file with your ElevenLabs API key**
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
Each item links to its spec. Build in dependency order.

- [ ] **`WorldGenerator.gd`** ← build first; everything else stands on this
  Extends `VoxelGeneratorScript`. Defines terrain from world coordinates using layered
  `FastNoiseLite`. Must encode: Spine ridge (wx ~5000–7000), Greatwood flat (wz ~0–2500),
  Aldwater valley channel, Ashfields (low, flat east of Spine), forced-flat zones at all
  settlement world coordinates (see CLAUDE.md → World coordinate reference).
  Reference: `design/3D_VOXEL_MIGRATION.md` → Milestone 5-3D, `design/ART_PIPELINE.md` → Tool 2

- [ ] **`EntityRegistry.gd`** ← build second
  Autoload singleton. Spatial dictionary keyed by chunk ID. Stores `EntityRecord` objects:
  `{ entity_type, world_position, scene_path, saved_state }`. No scene nodes — data only.
  Populated at startup from entity definition files (or hardcoded for early milestones).
  Reference: architecture established in design session 2026-05-01.

- [ ] **`EntityStreamer.gd`** ← build third, depends on EntityRegistry
  Node in `World3D.tscn`. Each physics frame checks player world position against
  `EntityRegistry`. Instantiates entity scene nodes when within load radius; saves state
  and `queue_free()`s them when beyond unload radius. Load radius: ~150m for buildings/props,
  ~80m for NPCs, ~60m for enemies.
  Reference: architecture established in design session 2026-05-01.

- [ ] **`RecipeData.gd` resource class**
  Defines the data shape for a single crafting recipe (station type, ingredients,
  output, required flags). Must exist before CraftingUI or ItemData population.
  Reference: `design/CRAFTING.md` → GDScript Integration Notes

- [ ] **`ItemData.gd` additions: smithing_tier, condition, weight, item_category**
  Add these fields to the existing ItemData resource class.
  Required before InventoryManager can track condition or weight correctly.
  Reference: `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` → GDScript Notes

- [ ] **`GameState.gd` additions: skill XP tracking and perk points**
  Add `SkillDomain` enum, per-domain XP counters, sub-skill counters, perk point
  pools, and `has_perk()` / `spend_perk_point()` / `get_charisma()` methods.
  Reference: `design/SKILLS_AND_PROGRESSION.md` → GDScript section

- [ ] **`PlayerStats.gd` — wound HP tracking**
  Separate "wound HP" from regular HP. Regular potions and bandages cannot restore
  wound HP; only full rest and Boneknit Compound can. Required for rest mechanics.
  Reference: `design/REST_AND_CAMP.md`

- [ ] **`CampMenuUI.tscn` + `CampMenu.gd`**
  Four-tab camp overlay (Rest / Craft / Companions / Gear). Opens on E-press at
  a campfire. Calls `WorldClock.advance_hours()` on rest confirmation. Time
  continues at 1/4 rate while menu is open.
  Reference: `design/REST_AND_CAMP.md` → The Camp Menu

- [ ] **`CraftingUI.gd` — station crafting interface**
  Opens from camp menu Craft tab or from station InteractArea. Shows known recipes
  filtered by station type. Intent choice (Quick / Care / Mastery). Calls quality
  calculation and `GameState.unlock_recipe()` on first use.
  Reference: `design/CRAFTING.md`

- [ ] **`InvestigationPoint.gd` node script**
  Area3D script: on E-press, delivers observation text overlay, sets journal flags,
  checks deduction conditions, fires companion observation if applicable. Tracks
  saturation count via GameState.
  Reference: `design/INVESTIGATION_SYSTEM.md` → GDScript Implementation Notes

- [ ] **`InvestigationUI.gd` — observation text overlay**
  World-space (or screen-edge) text that fades in/out when Roland examines something.
  Shows `roland_line`, brief "Noted" icon for Type 2 observations, companion
  portrait flash for companion addenda.
  Reference: `design/INVESTIGATION_SYSTEM.md` → The Examination Interface

- [ ] **Skills tab in `JournalUI.gd`**
  Add a sixth tab to the journal (or repurpose the existing structure). Per-domain
  display: current tier, sub-skill tiers, earned perks, locked perk hints, perk
  point spend button. No numbers — tier names only.
  Reference: `design/SKILLS_AND_PROGRESSION.md` → Skill Screen Presentation

- [ ] **Populate `ItemData` resource files from ITEM_LIBRARY.md**
  Create `.tres` files in `assets/items/` for the 40 potions, 40 smithable items,
  30 assembly items. Start with the Act I-relevant subset (Field Herb Tea, Bandage
  Roll, Wanderer's Seal, Iron Shortsword, Studded Leather Jerkin, Pitch Bomb,
  Smoke Grenade) before populating the full library.
  Reference: `design/ITEM_LIBRARY.md`

- [ ] **`FactionManager.gd` autoload**
  Wraps GameState faction disposition flags; emits `disposition_changed` signal;
  applies rival-faction effects on adjustment. Six Game One factions seed
  Game Three lockouts.
  Reference: `design/FACTION_SYSTEM.md`

- [ ] **`QuestManager.gd` autoload**
  `start_quest()`, `advance_quest()`, `complete_quest()`, `fail_quest()`. Manages
  quest flag namespace, journal entry creation, and timed-event handoffs to
  `FlagScheduler`.
  Reference: `design/QUEST_SYSTEM.md`

- [ ] **`WeatherManager.gd` autoload**
  Tracks current weather state, tweens `WorldEnvironment` between authored presets,
  honors zone-specific weather overrides, exposes `is_outdoor` for Roland's hood/cloak
  visual states.
  Reference: `design/WEATHER_AND_ENVIRONMENT.md`

- [ ] **`CompanionManager.gd` autoload**
  Active companion state, HP, downed/revive flags, combat order issuing, pack
  inventory. Serializes/deserializes for save.
  Reference: `design/COMPANION_SYSTEM.md`

- [ ] **`EnemyAI.gd` base script + per-type subclasses**
  State machine (Idle / Suspicious / Alert / Combat / Fleeing), attack-token
  arbitration with sibling enemies, per-type specs for Goblin, Ashfallen, Wolf, Bear.
  Reference: `design/ENEMY_AI.md`

- [ ] **`DeathHandler.gd` + Roland death-line library**
  Triggers on Roland HP=0: plays authored death line, fades to black, offers
  Second Wind (if available) or reload-from-last-save. No XP loss, no item loss.
  Reference: `design/DEATH_AND_RESPAWN.md`

- [ ] **`SaveSystem.gd` backup rotation update**
  Extend the existing multi-slot save with: rest autosave hook, Wanderer's Seal
  manual save hook, three-deep backup rotation per slot. Diegetic-only — no
  free-form quicksave outside camp/seal.
  Reference: `design/SAVE_SYSTEM.md`

- [ ] **HUD overhaul per `design/HUD_AND_UI.md`**
  HP bar, endurance bar, lock-on reticle, quick-slot tray, interaction prompt,
  bark overlay slot. Replace any 2D-era HUD remnants. Builds on `BarkOverlay` UI
  task in Section 6.

- [ ] **`Settings.gd` expansion per `design/ACCESSIBILITY_AND_SETTINGS.md`**
  Add: subtitle on/off + size, colorblind mode, screen shake intensity, parry
  window assist, voice/music/SFX bus volume sliders (target the bus names from
  Section 1's audio bus task). Persist to `user://settings.cfg`.

- [ ] **Vendor scripts per `design/ECONOMY_AND_VENDORS.md`**
  `VendorData.gd` resource (inventory list, faction price modifier, restock rules)
  and `VendorUI.gd` (buy/sell/haggle screen). Required before any Aldenholt or
  Solgrade vendor NPCs are placed.

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

- [ ] **Lockpicking system — choose an approach**
  Three options presented (Resource Drain / Timing Window / Investigation-Integrated).
  Recommendation is Option A (Resource Drain) with lock examination as Type 1
  investigation giving pick count info. Confirm before building the lock/door
  interaction system. Reference: audit findings 2026-05-01.

- [ ] **Endgame choices — resolve five open questions**
  ENDGAME_CHOICES.md is a working draft with five explicit open design questions
  (score visibility, reset points, save carryover, gating, path confirmation).
  Update companion roster (Edran is now confirmed). Not a Game One blocker but
  resolve before Game Two design begins.

---

## Section 9 — Verification Checklist (after each Godot session)

Run these after any session where you change scenes or scripts:

- [ ] World3D.tscn runs without errors in the Output panel
- [ ] Player moves on the terrain, camera follows in third-person over-shoulder
- [ ] Camera rotates with Q/E (or right stick) — does not lock to one angle
- [ ] Press E near a dialogue trigger → Dialogic opens
- [ ] Campfire flickers (OmniLight3D energy varies)
- [ ] No "Autoload not found" warnings (means a required autoload isn't registered)
- [ ] (Post Milestone 5-3D) VoxelLodTerrain loads terrain chunks without errors; no "chunk generation" errors in Output
- [ ] No "Bus not found" errors when audio plays (means the audio bus layout from Section 1 is missing)
- [ ] No "InputMap action not found" errors (means an action from Section 1 isn't configured)
