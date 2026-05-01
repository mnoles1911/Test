# NPC System Design

How non-player characters are built, categorized, and managed in Game One.

> For bark line content and trigger IDs, see `design/BARK_LIBRARY.md`.
> For conversation structure and Dialogic timelines, see `design/NPC_DIALOGUE_LIBRARY.md`.
> For TTS script formatting, see `dialogue/STYLE.md`.

---

## The Core Problem

A 30-hour RPG needs hundreds of characters populating its world — market vendors, street walkers,
guards at gates, archivists in libraries. Each one is a different authoring and implementation cost.
Without a system, every character becomes a one-off puzzle. With a system, 80% of characters can be
deployed in under an hour.

The solution is a **tier system**: four tiers of NPC complexity, each a superset of the tier below.
Every character gets the minimum tier they need. Nothing more.

---

## The Four Tiers

### Tier 0 — Background / Decoration

**What they do:** Fill the world visually. Market crowds, distant soldiers, ambient townspeople.
**How they're built:** A plain `Node3D` or `CharacterBody3D` with a mesh. No script. No data.
**Cost:** Zero authoring, zero runtime overhead.
**Examples:** The three people walking through Aldenholt's market square when you arrive.

**Rule:** If a player can never reach them or would never expect to interact with them, they are Tier 0.
Do not give Tier 0 NPCs an NPC.gd script. The extra collision and Area3D costs add up across a scene.

---

### Tier 1 — Bark-Only

**What they do:** Speak a short line when the player is nearby. Do not respond to E-press.
**How they're built:** `CharacterBody3D` + `NPC.gd` + `NPCData.tres`. No dialogue timeline.
**Cost:** ~30 minutes per character (data entry + writing bark lines).
**Examples:** A street vendor calling out their wares, a guard muttering at their post,
the alchemist's apprentice reacting when you enter the shop.

**What they need:**
- An NPCData resource with `tier = BARK` and `npc_id` set.
- A bark line file at `dialogue/scripts/barks/{category}/{npc_id}.txt`.
- Optional: voiced audio at `assets/audio/barks/{npc_id}/{trigger}_{variant}.ogg`.

**What they do NOT need:**
- A Dialogic timeline.
- A schedule.
- A portrait.

---

### Tier 2 — Conversational + Scheduled

**What they do:** Talk to the player on E-press, move to different locations during the day.
**How they're built:** Same as Tier 1, plus a Dialogic timeline and a schedule array.
**Cost:** ~2–4 hours per character (dialogue writing + schedule setup).
**Examples:** Tomlin at the Archive front desk (mornings), Tomlin at the sorting room (afternoons).

**What they need (beyond Tier 1):**
- `dialogue_timeline` set in NPCData.
- A portrait image at `assets/portraits/{npc_id}.png`.
- One or more `NPCScheduleEntry` resources in the `schedule` array.
- Named `SpawnPoint3D` nodes in the scene for each schedule location.
- An entry in `dialogue/CHARACTER_VOICES.md` for their voice profile.

**Schedule rules:**
- Each entry covers a time window (hour start → hour end).
- Gaps in the schedule are fine: the NPC stays put during uncovered hours.
- A `dialogue_override` on a schedule entry lets the NPC say "the shop is closed" at night.
- The world clock writes `world_hour` (0–23) to `GameState` each time the hour advances.
  Call `NPC.update_schedule(hour)` from whatever drives the clock.

---

### Tier 3 — Quest-Linked

**What they do:** Everything Tier 2 does, plus: run a shop/service, hand out quests,
have relationship history that changes their dialogue permanently.
**How they're built:** Same node setup as Tier 2. Extra data fields on NPCData.
**Cost:** ~1 day per character (full dialogue tree + Dialogic branching).
**Examples:** Dame Calla Vane (information broker, disposition-gated), Ser Brenn in Solgrade (quest hub).

**What they need (beyond Tier 2):**
- `service_type` set if offering a shop, inn, healer, etc.
- `quest_hooks` array populated with quest IDs the NPC can give out.
- A full Tier 3 conversation in `design/NPC_DIALOGUE_LIBRARY.md` format (companion branches).
- Story-flag conditions wired into the Dialogic timeline using `GameState` flags.

---

## GDScript Files

| File | Purpose |
|---|---|
| `scripts/NPCData.gd` | Resource class. One `.tres` file per NPC in `/assets/npcs/`. |
| `scripts/NPCScheduleEntry.gd` | Resource class. One entry per schedule time block in NPCData. |
| `scripts/NPC.gd` | Node script. Attach to CharacterBody3D. Reads NPCData, enables features by tier. |
| `scripts/BarkManager.gd` | Autoload. Loads bark line pools, picks random variants, shows overlay. |

---

## Data Flow

```
GameState.gd (flags, world_hour)
        │
        ├─► NPC.gd ──────────────────────► NPCData.tres
        │   ├── _ready()                   ├── npc_id
        │   ├── _process() [E-press check] ├── tier
        │   ├── fire_bark()                ├── dialogue_timeline
        │   │       └───────────────────── ├── schedule[]
        │   │                              └── quest_hooks[]
        │   └── _start_dialogue()
        │           └── Dialogic.start()
        │
        └─► BarkManager.gd (autoload)
                ├── fire(npc_id, trigger, position)
                ├── _pick_line() ──────────► /dialogue/scripts/barks/{cat}/{npc_id}.txt
                ├── _show_overlay()        (loaded on startup)
                └── _play_audio() ────────► /assets/audio/barks/{npc_id}/{trigger}_{n}.ogg
```

---

## Disposition System

Every NPC has a `current_disposition` value from 0 to 100.

| Range | Label | Dialogue behavior |
|---|---|---|
| 0–24 | HOSTILE | Curt refusals, may not speak at all |
| 25–49 | UNFRIENDLY | Minimal responses, no extra information |
| 50–74 | NEUTRAL | Default for most civilians |
| 75–89 | FRIENDLY | Warmer tone, more information unlocked |
| 90–100 | TRUSTED | Deepest dialogue branches, personal topics |

**How to use in Dialogic timelines:**
When the player presses E, NPC.gd writes two flags before starting the timeline:
```
GameState.set_flag("active_npc", "tomlin")
GameState.set_flag("active_npc_disposition", "62")   ← the number
```
In your Dialogic timeline, add a Condition node that checks:
```
GameState.get_flag("active_npc_disposition").to_int() >= 75
```
Branch to the friendly dialogue, or fall through to neutral.

**Changing disposition:**
```gdscript
# From any script that has a reference to the NPC node:
npc_node.adjust_disposition(+15)   # player did something the NPC appreciates
npc_node.adjust_disposition(-25)   # player did something hostile
```
Disposition persists across saves automatically (stored in GameState flags).

---

## Bark Integration

The bark trigger IDs used in NPC bark files must match exactly the trigger IDs
in `design/BARK_LIBRARY.md`. The most common ones:

| Trigger ID | When it fires |
|---|---|
| `PLAYER_NEARBY` | Player enters BarkArea (Tier 1 default) |
| `COMBAT_ENGAGE` | Combat system: first enemy spotted |
| `ENTERING_REGION` | Exploration system: entering a new zone |
| `IDLE_LONG` | Player standing still > 60 seconds |
| `INVESTIGATION_GENERIC` | Player interacts with a generic object |

The BarkManager loads all bark files in `dialogue/scripts/barks/` at startup.
No manual registration is needed — just create the file in the right folder.

---

## Godot Scene Setup

### NPC scene structure

```
NPCNode (CharacterBody3D + NPC.gd)          ← root; set npc_data here
├── MeshInstance3D                           ← voxel character / sprite
├── CollisionShape3D (CapsuleShape3D)       ← physics collision
├── BarkArea (Area3D)                        ← Tier 1 proximity trigger
│   └── CollisionShape3D (SphereShape3D)   ← radius = bark_radius
└── InteractArea (Area3D)                   ← Tier 2+ E-press trigger
    └── CollisionShape3D (SphereShape3D)   ← radius = interact_radius
```

Build `scenes/NPC_Template.tscn` once with this structure. Duplicate it for every new NPC.
Change only the NPCData resource on the root node.

### Adding an NPC to a scene

1. Duplicate `NPC_Template.tscn` (or instance it as a scene).
2. Create a new `NPCData.tres` in `/assets/npcs/` for this character.
3. Assign the `.tres` to the root node's `npc_data` property.
4. If Tier 2+: add `SpawnPoint3D` nodes named to match the `location_id` values in the schedule.
5. Add those `SpawnPoint3D` nodes to the `spawn_points` group (Node panel → Groups tab).

### Autoload setup

BarkManager must be registered as an Autoload:
- **Project → Project Settings → Autoload**
- Path: `res://scripts/BarkManager.gd`
- Node Name: `BarkManager`

---

## WorldClock (Not Yet Built)

The schedule system requires a `WorldClock` autoload that:
1. Tracks in-game time (minutes and hours passing at a configurable rate).
2. Writes `world_hour` (0–23) to `GameState` each time the hour changes.
3. Calls `update_schedule(hour)` on all NPC nodes in the group `"scheduled_npcs"`.

This is Milestone 5 work. Until then, schedules can be simulated by manually setting
`world_hour` in `GameState` from the DebugOverlay.

To register an NPC for schedule updates: add the NPC node to the `"scheduled_npcs"` group
in the Node panel. The WorldClock will call `update_schedule()` on all members automatically.

---

## Implementation Roadmap

These tasks are ordered by dependency. Each is a separate branch/PR.

| # | Task | Milestone |
|---|---|---|
| 1 | Create `NPC_Template.tscn` with the node structure above | 5-3D |
| 2 | Register `BarkManager` as an Autoload | 5-3D |
| 3 | Create first bark file: `dialogue/scripts/barks/idle/aldenholt_vendor.txt` | 5-3D |
| 4 | Place one Tier 1 NPC (vendor) in `World3D.tscn`; verify bark fires | 5-3D |
| 5 | Place Tomlin as Tier 2 NPC; verify E-press opens the sorting room timeline | 5-3D |
| 6 | Build `WorldClock.gd` autoload; test Tomlin's schedule across two time blocks | 6-3D |
| 7 | Build the "Press E" world-space prompt UI node | 6-3D |
| 8 | Build the `BarkOverlay` UI node (portrait + text, corner overlay) | 6-3D |
| 9 | Extend `DebugOverlay` to show active NPC name, disposition, and schedule block | 6-3D |

---

## Cross-References

- `design/BARK_LIBRARY.md` — bark trigger IDs, line counts, cooldown rules
- `design/NPC_DIALOGUE_LIBRARY.md` — conversation structure for Tier 2 and 3
- `dialogue/STYLE.md` — bark line formatting rules
- `dialogue/CHARACTER_VOICES.md` — voice profiles referenced by NPCData.voice_profile
- `design/CONVERSATION_SYSTEM.md` — four-tier conversation system (Tier 1 = barks)
- `design/SYSTEMS_DESIGN.md` — GameState flag conventions used by NPC disposition
