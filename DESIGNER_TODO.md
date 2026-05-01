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

- [ ] **Add `interact` input action (E key)**
  Project Settings → Input Map → Add Action: `interact` → assign key: E.
  Required by `DialogueTrigger3D.gd` and `NPC.gd` (press-E dialogue).

- [ ] **Register `BarkManager` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/BarkManager.gd` → node name: `BarkManager`.
  Required for all bark lines to fire in-game. Reference: `design/NPC_SYSTEM.md`

- [ ] **Register `WorldClock` as an Autoload**
  Project Settings → Autoload → path: `res://scripts/WorldClock.gd` → node name: `WorldClock`.
  Required for NPC daily schedules and time-of-day bark triggers. Reference: `design/NPC_SYSTEM.md`

- [ ] **Configure `camera_left` / `camera_right` input actions** (if horizontal camera rotation is ever enabled)
  Project Settings → Input Map → Add: `camera_left` (Q), `camera_right` (E or comma/period).
  Not needed until `CameraRig.gd` has `allow_horizontal_rotation = true`.

---

## Section 2 — Godot Editor: Scene Work

Scene building and node configuration that has to be done in the editor.

- [ ] **Verify Milestone 4-3D in Godot**
  Open `scenes/World3D.tscn` and run it. Confirm:
  - WASD / arrow keys move the green box on the flat floor
  - Camera follows at a fixed ~50° angle and does not tilt or rotate
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

- [ ] **Roland walk cycle sprite sheet (Aseprite)**
  32×48 px, 8 directions, 4 frames each = 32 total frames.
  Export as sprite sheet → import as `Sprite3D` in Godot (billboard mode).
  Used for Act I characters; low-poly Blender models come in Act II+.
  Reference: `design/ART_PIPELINE.md`

---

## Section 4 — TTS & Audio Production

Voice generation tasks for the text-to-speech pipeline.

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

## Section 7 — Verification Checklist (after each Godot session)

Run these after any session where you change scenes or scripts:

- [ ] World3D.tscn runs without errors in the Output panel
- [ ] Player moves on the 3D floor, camera follows correctly
- [ ] Press E near a dialogue trigger → Dialogic opens
- [ ] Campfire flickers (OmniLight3D energy varies)
- [ ] No "Autoload not found" warnings (means a required autoload isn't registered)
