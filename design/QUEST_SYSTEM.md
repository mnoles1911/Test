# Quest System Design

How quests are structured, tracked, and resolved in Game One.

> Cross-reference: `design/SYSTEMS_DESIGN.md` for the "information as currency" design philosophy.
> `design/FACTION_SYSTEM.md` for how quest outcomes affect faction standing.
> `design/JOURNAL_UI.md` for how quests are presented in the Quests tab.
> `design/INVESTIGATION_SYSTEM.md` for how investigation findings change available quest resolutions.
> `design/NPC_SYSTEM.md` for FlagScheduler and time-sensitive quest deadlines.
> `lore/GAME1_PART1.md` and `lore/GAME1_PART2.md` for the full story outline and quest context.

---

## Design Philosophy

**Quests are situations, not instructions.** The journal tells Roland what he knows, not what to do. "Find the Korvath connection to Henrietta's death" is a quest. "Go to the Archive third floor, open the second chest on the left, take the document" is not. The difference is authorial respect for the player's agency.

**Most quests have more than one resolution.** A quest that can only end one way is not a quest — it is a cutscene with extra walking. Roland's approach, the information he has gathered, the factions he has relationships with, and the choices he makes should all shape how a situation resolves. The same situation should be resolvable three or four different ways by players who have taken different paths through the game.

**Quests fail naturally.** Not every situation waits for Roland. Time-sensitive quests (events, contacts, opportunities) advance regardless of whether Roland acts. Missing a window does not break the game — it changes what is available afterward. The journal records what happened, in Roland's voice. The player learns the world moves without them.

**No quest markers.** Quests do not have waypoints, objective arrows, or progress trackers beyond Roland's written notes. The player finds the path by reading the journal, talking to people, and paying attention to what Roland observes. See `design/WORLD_NAVIGATION.md`.

---

## Quest Categories

### Main Quests

The primary narrative thread. In Game One, the main quest is the recovery of the Seven Pieces of the Sundered Crown and the defeat of Vaeroth's operation in the four kingdoms.

Main quests:
- Are always tracked in the journal Quests tab
- Are never permanently faileable (the plot must be completable)
- May resolve differently based on player choices, but always resolve
- Drive act transitions

### Side Quests

Optional situations Roland discovers through conversation, observation, or exploration. They have their own conclusions that matter to the world — a side quest resolved in Act I can have visible consequences in Act III.

Side quests:
- May be permanently missed (if Roland does not engage before a time window closes)
- Affect faction standing when resolved
- Often provide materials, resources, or contacts Roland cannot get otherwise
- Are authored to feel like complete stories, not fetch tasks

### Timed Quests (Events)

A subset of side quests that have a hard deadline tracked by `FlagScheduler`. When the deadline passes:
- The situation resolves without Roland's input (the contact leaves, the evidence is destroyed, the event occurs)
- The journal records what happened: *"Old Mira's apprentice — I waited too long. She was taken to Solgrade by the time I returned."*
- The result changes what is available but does not block main quest completion

The existence of timed quests communicates: *the world moves. Not everything waits.*

### Investigations

Quest-adjacent content that uses the Investigation System. An investigation is a series of Type 2 observation points that, when combined, produce a Deduction. The Deduction is the "reward" — a piece of understanding that unlocks dialogue options or confirms a theory Roland had.

Investigations are not listed as quests in the journal. They feed into quest entries as context. Roland's journal notes when there is more to find in a scene ("I should look around more carefully before deciding what to say to Tomlin") — not as a waypoint, but as an authored reminder.

See `design/INVESTIGATION_SYSTEM.md` for the full spec.

---

## Quest Structure

Each quest has:

| Field | Description |
|---|---|
| `quest_id` | Unique string identifier |
| `title` | Roland's shorthand for the situation (not a formal name) |
| `status` | `active`, `complete`, `failed`, `dormant` |
| `journal_entries` | Array of text strings added as the quest progresses |
| `flags_required` | GameState flags that must be set for the quest to become available |
| `flags_set_on_complete` | GameState flags this quest sets when finished |
| `faction_changes` | Faction disposition deltas applied on resolution (per outcome) |
| `deadline_flag` | Optional FlagScheduler event that auto-resolves if Roland has not acted |

Quests are defined as Resource files (`.tres`) or as inline data in the quest scripts. The journal reads from `GameState` flags to determine which journal entries to show.

---

## Quest State and the Journal

The journal Quests tab shows three sections:
1. **Active** — quests Roland is currently pursuing
2. **Completed** — quests resolved, with Roland's written outcome note
3. **Failed / Missed** — quests that expired or were abandoned, with Roland's observation about what happened

Roland's journal entries for quests are written in his voice — not system text. A completed quest does not say "OBJECTIVE COMPLETE." It says: *"Marten Voss has his iron back. He didn't say thank you, but he did charge me less for the sword repair. That counts."*

Failed quests are written the same way. Roland does not catastrophize missing something. He notes it, considers what it means, and moves on. The journal is the record of a man doing his best, not a ledger of failures.

---

## Quest Resolution Branching

Quests with multiple outcomes store which outcome occurred as a GameState flag. This flag is what other systems read — dialogue conditions, faction standing changes, subsequent quest availability.

**Example — Old Mira's apprentice:**

| Approach | Resolution | Flags set | Faction effect |
|---|---|---|---|
| Find and return her before deadline | Apprentice safe; Mira becomes trainer | `mira_apprentice_returned` | Iron Chalice +10, Mira disposition: Friendly |
| Find her but can't prevent Solgrade transfer | Partial; Mira provides limited recipes only | `mira_apprentice_warned` | Mira disposition: Neutral-warm |
| Deadline passes, no action | Apprentice gone; Mira grieves; no training available | `mira_apprentice_lost` | Mira disposition: Grief-withdrawn |
| Roland identifies and exposes who was responsible | Adds accountability; unlocks Mira's full recipe set plus a unique item | `mira_apprentice_accountability` | Mira disposition: Allied; House Korvath −15 |

Each of these outcomes is a complete experience. None of them is the "correct" one. The player who missed the deadline but found the responsible party gets something the player who acted quickly but didn't investigate does not.

---

## Flag Scheduler and Timed Events

`FlagScheduler.gd` (existing autoload) handles time-based quest state changes.

A timed quest registers a deadline:

```gdscript
# When the quest becomes active:
FlagScheduler.schedule("mira_apprentice_deadline", WorldClock.get_day() + 3)
# Three in-game days from activation.
```

When the deadline fires:
- `FlagScheduler` sets the deadline flag
- If Roland has not set the resolution flag, the auto-resolve function runs:
  - Sets the "missed" outcome flag
  - Updates the journal with Roland's note about what happened
  - Applies any world-state changes (NPC leaves, door locks, etc.)

The player is not warned that a deadline is approaching. Some quests — if Roland has gathered enough information — will contain a note in the journal that implies urgency: *"Whatever I'm going to do about this, I should do it soon."* This is authored, not a system timer notice.

---

## Multi-Act Consequences

Certain quest outcomes in Game One directly affect Game Two and Game Three. These are tracked as long-lived GameState flags that persist across saves.

**Examples:**
- Resolving the Iron Chalice debt (Act I) → Iron Chalice supports Roland in Game Two with intelligence; commits forces in Game Three
- Exposing Prince Aedric's role in the Korvath network (Act II) → Solgrade political situation different in Game Two; Aedric is a complication or a removed factor depending on resolution
- Honoring the Golden Lance contract (Act II) → Vossant's trust established; Game Three tactical alliance available

These consequences are not announced. The player discovers them when Game Two begins and finds that certain doors are already open (or closed) based on what they did.

---

## Quest Anchors and Destructible Terrain

The world is destructible by default (see `design/3D_VOXEL_MIGRATION.md`). This affects how quest triggers and locations are authored.

**Rules for quest authors:**

1. **Quest anchors are Area3D volumes, never voxel features.** "Reach the rock outcrop" must be implemented as an `Area3D` whose bounds the player can enter — never as a check against a specific voxel block. The outcrop may or may not still exist visually by the time the player gets there. The Area3D persists regardless.
2. **Narratively load-bearing locations sit inside NoEditZones.** Settlements, named landmarks, dungeon entrances, lore sites, and any quest-critical structure must be authored as `MeshInstance3D` props inside an `Area3D` registered to the `no_edit_zone` group. The `VoxelEditManager` rejects all writes inside these volumes — players cannot dig under Caer Brannoch's foundation, blow up the Iron Chalice chapel, or bury the entrance to the Underway.
3. **Author fallback access for likely-edit-adjacent paths.** If a quest path crosses voxel terrain that's *not* in a NoEditZone (a forest road, a riverside trail, a mountain pass), assume the player may have altered it. Provide at least one of: an alternate entry point, an NPC who clears the path on request, or a Roland action that resolves the obstruction (rope-and-piton climb, pickaxe through). "Player buried the only path" should never be a quest-blocking state.
4. **Roland's bark inside a NoEditZone** when the player attempts a forbidden edit: *"This place doesn't yield to me."* Single line, one-time per session per zone.

---

## Quest Authoring Guidelines

For writers adding new quests:

1. **Write the journal entry first.** The quest's journal text — in Roland's voice — defines what the quest is. If you can't write Roland's note about it, the quest concept is not clear enough.

2. **Author at least two resolutions.** A quest with one outcome is a cutscene. What does a player who came late, or who has different information, or who chose a different faction alignment, get?

3. **Define what fails naturally.** What happens if the player never engages? The world needs an answer. That answer becomes the `deadline_auto_resolve` function.

4. **Connect to at least one other system.** A quest that only adds a journal entry and some crowns is thin. What faction does it affect? What investigation does it connect to? What dialogue does it unlock?

5. **Write the completion note, not just the setup.** Roland's voice on completion — whether he succeeded, partially succeeded, or failed — should feel earned. The completion text is the last word on the situation.

---

## GDScript Notes

### Quest resource structure

```gdscript
class_name QuestData
extends Resource

@export var quest_id: String
@export var title: String
@export var journal_entries: Array[String]  # index matches progression stage
@export var deadline_flag: String            # "" = no deadline
@export var outcome_flags: Array[String]     # the flags that represent different resolutions
```

### Quest state in GameState

```gdscript
# Quests are tracked entirely through flags:
GameState.set_flag("quest_" + quest_id + "_status", "active")  # active/complete/failed
GameState.set_flag("quest_" + quest_id + "_stage", str(stage)) # journal entry index
GameState.set_flag("quest_" + quest_id + "_outcome", outcome)  # outcome string

# JournalUI reads these flags to build the quest display.
```

### Advancing a quest

```gdscript
# QuestManager.gd (new lightweight autoload — just flag management):
func advance_quest(quest_id: String, new_stage: int) -> void:
    GameState.set_flag("quest_" + quest_id + "_stage", str(new_stage))
    # JournalUI will pick up the change on next open.

func complete_quest(quest_id: String, outcome: String) -> void:
    GameState.set_flag("quest_" + quest_id + "_status", "complete")
    GameState.set_flag("quest_" + quest_id + "_outcome", outcome)
    # Apply faction changes defined for this outcome (called from quest script).
```
