# Design Directory — Mira-Thal: Game One

## What this directory is

Game implementation reference. How the world's lore translates into Godot 4.3
systems, mechanics, and visual production.

**This is not where the world lives.** The world lives in `/lore`.

---

## The split

```
/lore/    →  Canonical narrative. Story, characters, geography, history.
              The source of truth for "what's true in Mira-Thal."
              Start here: /lore/INDEX.md

/design/  →  Game implementation. Combat systems, dialogue mechanics,
              save architecture, art direction, scene structure.
              The source of truth for "how we build it in Godot."
```

When the two conflict, lore wins. Design adapts.

---

## Files in this directory

The full annotated index lives in `CLAUDE.md` (project root) → "Design reference".
The summary below groups the docs by domain so a new contributor can find the
right one quickly. **Read `MILESTONE_ROADMAP.md` first** for the build order.

### Combat, AI, and progression

- `COMBAT_DESIGN_3D.md` — real-time 3D combat: tap-vs-hold attack, parry, dodge,
  lock-on, locked tunable values (parry 300 ms, endurance costs, wound HP 25 %)
- `ENEMY_AI.md` — detection states, attack-token arbitration, per-type specs
  (Goblin, Ashfallen, Wolf, Bear)
- `SKILLS_AND_PROGRESSION.md` — learn-by-doing skill domains, sub-skills, perk
  trees, Charisma, Lethe's Draught
- `DEATH_AND_RESPAWN.md` — death sequence, authored Roland death lines, Second
  Wind, no permanent loss

### Inventory, crafting, and items

- `INVENTORY_AND_EQUIPMENT_SYSTEM.md` — equipment slots, weapon handedness,
  weight, condition, smithing tiers, torch mechanics
- `ITEM_LIBRARY.md` — master recipe reference: 40 potions, 40 smithable items,
  15 meals, 30 assembly items
- `CRAFTING.md` — station mechanics, intent-based quality, alchemy
  experimentation, Wanderer's Seal

### Exploration and world systems

- `INVESTIGATION_SYSTEM.md` — examine system, investigation points, Roland's
  deduction mechanic
- `LOCKPICKING.md` — Resonance Pick radial dial, lock tiers, pick consumption,
  skill-driven hold timer
- `REST_AND_CAMP.md` — rest mechanics, camp setup, sleep effects, time
  advancement
- `WEATHER_AND_ENVIRONMENT.md` — authored weather, six time-of-day periods,
  WorldClock lighting, environmental hazards
- `WORLD_NAVIGATION.md` — no-waypoint navigation, hand-drawn journal map, zone
  structure, landmarks
- `SAVE_SYSTEM.md` — diegetic saves (rest autosave + Wanderer's Seal), three
  slots, backup rotation

### Player UI and input

- `HUD_AND_UI.md` — minimal HUD, HP/endurance bars, quick slots, interaction
  prompt, bark overlay, menus
- `JOURNAL_UI.md` — five-tab journal: Quests, Map, Items, Crafting, Codex
- `INPUT_AND_CONTROLS.md` — full KB/mouse and controller scheme, all Input Map
  actions, tap-vs-hold combat
- `ACCESSIBILITY_AND_SETTINGS.md` — display/audio/controls/accessibility,
  subtitle defaults, colorblind support

### Companions, NPCs, and dialogue

- `COMPANION_SYSTEM.md` — companion mechanics, combat orders, downed/revive,
  pack management
- `NPC_SYSTEM.md` — NPC tier system, disposition, WorldClock schedules, schedule
  gap behavior
- `CONVERSATION_SYSTEM.md` — four-tier conversation system (barks → illustrated
  keyframes), TTS pipeline overview
- `BARK_LIBRARY.md` — bark trigger IDs, line counts, cooldown rules
- `NPC_DIALOGUE_LIBRARY.md` — conversation structure for Tier 2 and 3 NPCs

### Narrative systems and economy

- `FACTION_SYSTEM.md` — six Game One factions, disposition scale, rival effects,
  lockouts, Game Three seeding
- `QUEST_SYSTEM.md` — situation-based quests, multi-resolution outcomes, timed
  events
- `ECONOMY_AND_VENDORS.md` — lean economy, vendor types with named vendors,
  faction price modifiers, haggling

### Art, audio, and pipeline

- `ART_DIRECTION.md` — palette, location visual identity, architecture by
  region, shaders
- `CAMERA_AND_PERSPECTIVE.md` — third-person over-shoulder follow camera at
  ~15° elevation, player-rotatable, with lock-on for 1-vs-many combat
- `ART_PIPELINE.md` — MagicaVoxel for props/buildings, Zylann Voxel Tools for
  terrain (`VoxelLodTerrain` streaming), low-poly Blender characters from Act I
- `3D_VOXEL_MIGRATION.md` — open-world architecture: 12 km × 10 km playable
  Mira, streaming voxel terrain, third-person camera, milestone sequence
- `AUDIO_DESIGN.md` — audio bus layout, music/SFX/voice routing, spatial 3D
  audio, settings volume sliders

### Planning, ops, and overview

- `MILESTONE_ROADMAP.md` — Act I scene breakdown and ordered deliverables
- `SYSTEMS_DESIGN.md` — high-level overview of how the systems interlock
- `ENDGAME_CHOICES.md` — Game Three endgame and trilogy-spanning choice
  consequences
- `DIALOGIC_SETUP.md` — step-by-step Dialogic 2 installation and character setup
- `TTS_PIPELINE.md` — AI-assisted draft → ElevenLabs render → Dialogic handoff
  (paired with the scripts in `/tools`)
- `LESSONS_LEARNED.md` — running log of bugs and fixes

---

## What used to be here

Earlier versions of this directory contained `WORLD_OVERVIEW.md`,
`CHARACTER_BIBLE.md`, and `GAME_ONE_QUESTS.md`. These were deleted because the
`/lore` directory now contains far more thorough, canonical versions of the same
content. Maintaining two copies would guarantee drift.

If you find yourself wanting to look something up about the world, characters,
or plot — go to `/lore`, not here.

---

## How design and lore stay in sync

When lore changes (a character's surname is corrected, a location moves, a quest
path is revised):

1. The change is made in the relevant `/lore` file
2. `lore/INDEX.md` is updated if scope changed
3. Implementation docs in `/design` are reviewed for stale references
4. `CLAUDE.md` (project root) is updated if the change affects canonical naming
   or current milestone

The reverse is rare but happens: when implementation reveals that a design
assumption does not fit the lore, the lore is the authority and the design
adapts.

---

## CLAUDE.md (project root)

The root-level `CLAUDE.md` points Claude Code at both `/lore` and `/design`,
locks in canonical naming, lists the maintenance schedule for files that go
stale, and tracks current milestone state. Update it when:

- A new lore or design file is added or renamed
- A milestone is completed
- A new canonical naming contradiction is discovered

`DESIGNER_TODO.md` (also project root) is the single source of truth for manual
work — Godot editor setup, asset production, design decisions still open. Check
it before starting a session.

That pair of files is the orientation document Claude Code reads at the start
of every session. Keep them accurate and they do most of the heavy lifting in
keeping the project coherent across years of work.
