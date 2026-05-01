# Journal UI Design
## Roland's journal as the player's primary reference

> This document covers the Journal UI system. For the dialogue flag logic that populates journal entries, see `design/SYSTEMS_DESIGN.md`. For quest content, see `lore/SIDE_QUESTS_GAME1.md` and the relevant lore files. For skill display, see `design/SKILLS_AND_PROGRESSION.md`.

---

## Design Philosophy

**The journal is Roland, not the game.** Entries are written in his voice — partial, occasionally wrong, updated as he learns more. He does not have perfect knowledge of the world. He has his notes. The player's experience of the journal should feel like reading someone's actual journal, not consulting a database.

**No quest markers. No waypoints.** The journal is the player's navigation tool. If a player wants to know where to go next, they open the journal and read what Roland wrote. NPCs provide verbal directions when asked. The world does not label itself.

**The journal as plant.** The Aldric Vane entry — added in Act I when Roland logs the name Henrietta was researching — should read like a footnote on first play. On replay, it is the most important entry in the game. The journal's writing must support both readings without cheating either.

---

## Opening the Journal

Press **J** (or the Journal button on controller) from anywhere during exploration. The game does not pause when the journal opens — time continues, ambient sound continues, Roland is still standing where he was. The journal is a real object Roland is holding.

During dialogue or combat, **J** is disabled.

The journal opens to the **last tab the player used.** On first open, it defaults to the Quests tab.

**Closing:** press J again, or Escape. The journal closes without fanfare.

---

## Tab Structure

Five tabs, accessed by clicking the tab header or cycling with Tab/Shift-Tab:

```
[ Quests ]  [ Map ]  [ Items ]  [ Crafting ]  [ Codex ]
```

Each tab is described below.

---

## Tab 1 — Quests

### Layout

Left column (30% width): the quest list. Right column (70% width): the selected quest's full entry.

The quest list is divided into two sections:
- **Active** — quests Roland is currently pursuing
- **Resolved** — completed quests, listed in chronological order (most recently resolved first)

Each quest in the list shows its name and a one-line status note in Roland's handwriting style (short, terse). Selecting a quest loads its full entry in the right column.

### Quest Entry Format

Each active quest entry contains:

1. **Name** — the quest's title (in Roland's handwriting aesthetic, not a bold system header)
2. **What I know** — Roland's summary of the situation. Updated each time a significant new development occurs. Written entirely in first person. May contain his interpretation of events, which can be wrong.
3. **What I need to do** — one to three lines maximum. Concrete. Not lore — task. "Find out who Henrietta was researching. Tomlin might know if I can convince him to talk."
4. **People involved** — names with one-phrase descriptions. Updates if Roland learns more. "Tomlin Rew — Archive junior archivist. Knows Henrietta. Nervous."
5. **Last updated** — the in-game date and time (from WorldClock)

There is no quest waypoint marker in this tab. If the player needs to know where to go, the "What I need to do" line tells them in words.

### Resolved Quest Entries

Resolved quests keep their full entry but gain a final line: **What happened.** Roland's summary of the outcome, in past tense, in his voice. This may include his emotional response if the outcome was significant. A quest resolved well reads differently from a quest that went badly.

Example (Iron Chalice pommel):
> *What happened: I took the pommel. Calla let me. Neither of us said what we both understood — that she had just handed me something the Order considers a sacred object, and I had just confirmed that I would use it against whatever stands in the way. I left the rod in its place. It seemed important to leave something.*

### The Crown Tracker

At the bottom of the Quests tab, always visible regardless of which quest is selected: a small horizontal tracker showing the seven Crown pieces.

Each piece is represented by a small icon (the piece type, not a named label). Its state:
- **Unknown** — greyed out, no label
- **Located** — icon fills in, location noted in one word (e.g. "Archive," "Spine")
- **Acquired** — icon bright, checkmark

This is the only part of the Quests tab that functions like a traditional game tracker. The seven pieces are the spine of the plot — the player should always be able to see at a glance where they stand.

---

## Tab 2 — Map

### What the map shows

The map is **hand-drawn in Roland's style** — not a satellite view, not a minimap blown up. Lines, labels, rough shapes. When Roland arrives somewhere new, he adds it to his map. When he learns something about a place he has not visited, he makes a note in the margin.

The map opens showing **Mira at continent scale.** Zooming in (scroll wheel or pinch) reveals regional detail. Zooming in further reveals the specific district or zone Roland is currently in or has visited.

**Discovered locations** are shown with Roland's notation: a small symbol (city = square, hold = triangle, ruin = X) and the name he knows it by. Locations Roland has heard about but not visited are shown as dotted labels — he knows they exist, not exactly where.

**Current position** is shown as a small X-marks-the-spot — Roland's best guess of where he is. In wilderness or the Underway, this may be imprecise. In a city he has walked, it is accurate.

### Progressive reveal

The map starts almost blank — Aldenholt and the Salt Road west of it. As Roland travels, regions fill in. Areas Roland has not been to are empty parchment. He cannot see the full world map without traveling the world.

**No fast travel from the map.** The map is a reference, not a transit system. Fast travel (if implemented at all) is handled through specific in-world mechanics — horses, Sailor's Guild voyages, the Underway — not through a map click.

### Annotations

Roland occasionally adds written notes to the map margins when a location or route is significant. These appear automatically at story beats:

- After the Night Chase: a note near the Scholar's Block reading *"Tomlin. Back entrance only after dark."*
- After Act II: notes on each kingdom capital with Roland's one-line assessment of the alliance state
- After the Underway: Dagna's handwriting appears on the Underway section — she has taken over that portion of the map and Roland has let her

---

## Tab 3 — Items

### Layout

A grid of all items currently in Roland's inventory (not equipped). Items are sorted by category by default: consumables, throwables, materials, quest items.

Each item shows:
- Icon
- Name
- Quantity
- Condition bar (for equipment items — condensed into a small color indicator: green/yellow/red)

Selecting an item opens a description panel on the right: what the item is, what it does, in plain language. Not stat blocks — sentences. "A coil of linen bandage. Stops bleeding, buys time. Not enough if the wound is deep."

**Quest items** are shown in a separate section at the bottom of the grid, with a small lock icon. They cannot be discarded, dropped, or used from this screen.

### Quick Slot Assignment

From the Items tab, the player can assign consumables and throwables to quick slots. The four quick slots are displayed at the bottom of the screen above the tab bar. Drag an item to a slot, or select an item and press the assign key to put it in the next empty slot.

### Companion Packs

When in camp or interacting with a companion, the Items tab gains a secondary panel: the companion's pack. Same grid layout, same interaction. The player can drag items between Roland's inventory and the companion's pack. This is the only way to restock companion consumables.

---

## Tab 4 — Crafting

### Layout

Left column: a list of known recipes, organized by category (Consumables, Throwables, Kits). Right column: the selected recipe's details.

**Known recipes** are recipes Roland has learned — from a book, from an NPC, by experimenting. Unknown recipes are not shown. The player discovers recipes through play, not through a wiki.

### Recipe Entry

Each recipe shows:
- **What it makes** — name and icon of the output item
- **What it takes** — list of required materials with current inventory count / required count (e.g. "Healing Herb: 2 / 3" in red if Roland doesn't have enough)
- **What it does** — one sentence, plain language
- **Craft button** — active only if Roland is at a crafting station (campfire, workbench) and has the materials

**Crafting is not instantaneous.** A short animation plays (Roland preparing the item). Cannot be interrupted. This prevents crafting mid-combat.

### Skill Gate Display

If a recipe requires a Crafting skill tier Roland has not reached, it appears in the list but is greyed out with a note: *"I don't know how to do this yet."* No tier label, no progress bar — just an honest acknowledgment that the knowledge is not there yet.

---

## Tab 5 — Codex

### What the Codex is

The Codex is everything Roland knows about the world that is not a quest or an item. It populates automatically as Roland encounters new people, places, factions, and events. It is a lore reference, not a game guide.

The Codex is written in Roland's voice — but slightly more formal than his journal entries, as if he is summarizing what he knows as clearly as he can rather than processing it emotionally. He is making notes he expects to need later.

### Categories

| Category | Contains |
|---|---|
| **People** | Everyone Roland has met or heard of by name. Updated as he learns more. |
| **Places** | Locations Roland has visited or learned about in detail. |
| **Factions** | Orders, guilds, and political groups. What Roland knows about their goals and structure. |
| **The Crown** | History of the Sundered Crown. The seven pieces. Updated as Roland learns more. |
| **Lore** | Things Roland has read or been told that did not fit another category. Ancient history, magic, the Aelthiren. |
| **Bestiary** | Enemies Roland has fought or observed. What he has learned about them. |

### Entry format — People

Each person entry has:
- Name and one-line identification ("Dame Calla Vane — Knight-Commander, Iron Chalice Order")
- What Roland knows about them (updated on key story beats)
- Last known location and circumstance
- Roland's assessment — brief, honest, possibly wrong

The assessment is what makes these entries distinctive. Roland is not a neutral observer. His entry on Yaromir reads differently from his entry on Vaeroth, and that difference is revealing.

**Entries can be wrong.** If Roland is deceived about someone, his Codex entry reflects his deceived understanding until he learns otherwise. On replay, these wrong entries are visible as dramatic irony.

### Entry format — Bestiary

After Roland has fought an enemy type, he adds a Bestiary entry. After using the **Analyze** action in combat, the entry expands with the enemy's specific weakness.

Bestiary entries are written as field notes — practical, terse, occasionally grim. "Ashfallen: former knights, from the look of the armor. They fight the way I was trained to fight. That's the problem. They hesitate slightly when you parry — they remember what that means."

### Populating the Codex

Entries are added automatically when:
- Roland meets someone for the first time (People entry created)
- Roland visits a location for the first time (Places entry created)
- Roland completes a significant story beat (entries updated)
- Roland reads a book or document in the world
- Roland uses Analyze on a new enemy type (Bestiary entry expanded)

The player cannot manually add entries. The Codex is what Roland knows — not what the player wants to remember. If the player wants their own notes, that is what paper is for.

---

## GDScript Notes

The Journal UI is managed by `JournalUI.gd` (existing autoload). Key additions required:

```gdscript
# Open to a specific tab from code:
JournalUI.open_to_tab("codex")
JournalUI.open_to_tab("quests")

# Add or update a quest entry:
JournalUI.update_quest(quest_id: String, status: String, what_i_know: String, what_to_do: String)

# Add a Codex entry:
JournalUI.add_codex_entry(category: String, entry_id: String, name: String, text: String)

# Update a Codex entry (appends new information):
JournalUI.update_codex_entry(entry_id: String, new_text: String)

# Mark a Crown piece as located or acquired:
JournalUI.update_crown_piece(piece_index: int, status: String)  # status: "unknown", "located", "acquired"

# Add a map annotation:
JournalUI.add_map_annotation(location_id: String, note: String, handwriting: String)
# handwriting: "roland" or "dagna" (for Underway sections)

# Add a map discovery:
JournalUI.discover_location(location_id: String, map_symbol: String, label: String)
```

All journal updates should be called from within Dialogic timelines or scene scripts via `GameState.gd` flag-setting hooks — not directly from NPC.gd. The journal reflects the story state; the story state is owned by GameState.
