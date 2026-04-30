# Level Layouts — Act I: Aldenholt

Act I takes place entirely in Aldenholt, the largest city in Mira. Five scenes,
all connected through an Aldenholt street hub. The player can revisit scenes as
the story allows; some scenes have new content after key flags are set.

For city physical description, see `CITY_DESCRIPTIONS.md` → Aldenholt.
For visual direction, see `ART_DIRECTION.md` → Aldenholt.
For story context, see `GAME1_PART1.md` → Act I.

---

## Scene 1 — The Night Chase (Aldenholt Alleys)

**File:** `scenes/act1/NightChase.tscn`
**Plays:** Game opening. Linear, no return.
**Size:** ~5 screens wide, mild vertical branching

### What Happens Here
Game One opens mid-chase. Roland is running. He does not know who hired the pursuer —
only that someone wants what he found and knows he found it. He needs to reach Henrietta
at the Archive before anyone else does.

This is the movement tutorial. No combat. No dialogue except Roland's internal monologue
triggered by environmental objects.

### Layout

```
[ALLEY START] → [MARKET ROW] → [LOCKED GATE / ALTERNATE PATH] → [ARCHIVE STREET] → [ARCHIVE DOOR]
                                      ↓
                               [BACK PASSAGE]
                                      ↓
                               [rejoins ARCHIVE STREET]
```

**ALLEY START** — narrow cobblestone alley, walls close, torches guttering. The player
begins here already in motion (spawn mid-run). A knocked-over market cart creates the
first obstacle: go around left or right, both clear.

**MARKET ROW** — slightly wider, stalls packed away for the night. Some cloth awnings
still out. Ambient: a cat startles from behind a crate. One NPC (sleeping night watchman
in a doorway) — Roland's narration notes the man is better off not seeing him.

**LOCKED GATE / ALTERNATE PATH** — the direct route has a locked iron gate (not breakable).
Left path goes to a narrow Back Passage: tighter walls, a broken rain barrel, puddle
underfoot. A torch sconce has gone out — one dark stretch. Right path does not exist here
(wall). Back Passage rejoins the main route 20m on.

**ARCHIVE STREET** — the Scholar's Block district. Wider street, stone-paved. The Archive
building dominates the right side: windowless lower floors, massive oak doors at the
entrance. Lamplight at the Archive door.

**ARCHIVE DOOR** — trigger zone. When Roland reaches it, Henrietta opens the door.
Dialogue fires (the handoff scene). After dialogue ends: scene ends, transition to
the Aldenholt Hub.

### Objects and Interactions
- Market cart (obstacle, no interaction)
- Locked gate (impassable — investigation point: "No time. The other way.")
- Sleeping watchman (pass without waking — investigation point triggers Roland narration)
- Broken rain barrel in the Back Passage (investigation point: Roland notes the route out
  in case he needs it later — plants Orion-style exit-awareness before Orion joins)

### Flags Set
- None (this is the opening — no flags set yet, nothing to read)

### Flags Read
- None

### Lighting
- CanvasModulate: very dark (`#1A1F3A` or darker — this is the most oppressive lighting
  in Act I, Roland is hunted here)
- Torch sconces at ~96px intervals — warm pools between cold stretches
- One torch out in the Back Passage — a deliberate dark stretch
- Archive door: one warm lamp, the only invitation in the scene

### Transition Out
- Archive Door trigger → fade to black → `scenes/act1/AldenholtHub.tscn`
  (Henrietta dialogue fires during or after this transition — design decision TBD)
- Flag set on transition: `scene_night_chase_complete = true`

---

## Scene 2 — Aldenholt Hub (The Street)

**File:** `scenes/act1/AldenholtHub.tscn`
**Plays:** Acts as the connective tissue for all Act I scenes. Re-entrant.
**Size:** ~3 screens wide

### What Happens Here
The Scholar's Block street. Roland's base of operations in Act I. Between objectives,
he walks this street to reach locations. Some ambient NPCs update their dialogue after
story flags change (they notice things, overhear things).

This scene connects:
- The Archive entrance (→ Scene 3/5 depending on flag state)
- The Iron Chalice Chapel (→ Scene 4 when flag conditions met)
- Roland's lodgings (→ rest point / journal access / autosave)
- The Aldenholt Market (background dressing — not a scene, but visible at the street's
  far end)

### Layout

```
[LODGINGS] ←→ [SCHOLAR'S BLOCK STREET] ←→ [ARCHIVE ENTRANCE]
                        ↓
                [CHAPEL SIDE STREET]
                        ↓
                [IRON CHALICE CHAPEL entrance]
```

### Key Objects
- **Archive entrance door** — leads to Scene 3 (before restricted section unlocked) or
  Scene 5 (after `tomlin_helped = true`)
- **Roland's lodgings door** — rest point. Journal opens here. Autosave.
- **Chapel side street entrance** — only visible/accessible after Dame Calla dialogue
  (flag: `calla_meeting_arranged = true`)
- **Ambient NPC: street vendor** — sells nothing but talks. Dialogue updates after
  `henrietta_dead = true`: "They say someone died in the Archive quarter last night.
  Terrible business."
- **Ambient NPC: Iron Chalice novice** — passes through. Post-expulsion Roland avoids
  eye contact. If player investigates: brief cold shoulder exchange.

### Flags Set
- None (hub scene sets no flags directly)

### Flags Read
- `henrietta_dead` — changes ambient NPC dialogue
- `calla_meeting_arranged` — makes chapel side street accessible
- `pommel_piece_1_acquired` — novice dialogue changes ("I heard he left the city")

---

## Scene 3 — The Archive (Henrietta's Quarters)

**File:** `scenes/act1/Archive.tscn` (the room accessed immediately after the chase)
**Plays:** After Night Chase, before restricted section. Short.
**Size:** ~1.5 screens — a single suite of rooms

### What Happens Here
Roland returns to the Archive the next day (or within hours) and finds Henrietta's
personal quarters searched. The original notes are gone. Her body is present — the
game shows this without dwelling on it, one environmental beat.

This is environmental storytelling, not dialogue. Roland observes. The player investigates.
This is the scene that proves to Roland the pommel matters and hesitation will kill him.

### Layout

```
[ARCHIVE ENTRANCE HALL] → [STAIRCASE UP] → [HENRIETTA'S STUDY / QUARTERS]
```

**ARCHIVE ENTRANCE HALL** — a small foyer. One archivist at a desk (not Tomlin — Tomlin
is on suspension). The archivist is on edge, unhelpful. Dialogue is perfunctory: "The
Archive is closed to outsiders pending investigation." Roland can push (gets nothing) or
leave.

**HENRIETTA'S STUDY** — accessible via staircase once Roland has reason to go (he knew
the room from previous visits). Key investigation points:

- **The desk** — drawers pulled out, papers scattered. Investigation: "The originals are gone.
  She would have kept them here."
- **The overturned bookshelf** — methodical, not ransacking. Someone knew what they were
  looking for. Investigation: "Whoever did this was thorough. Professional."
- **The window** — cracked open. Roland looks out at the street below. Investigation: "They
  came in here. And they left without being seen. The Iron Chalice doesn't operate this way.
  This is someone else's work."
- **Henrietta's coat** — still on its hook. Her personal things are untouched. Only the
  research materials were taken. Investigation: "They only wanted what she had found."

### Flags Set
- `henrietta_dead = true` (set on first entry to the study, not on the investigation
  points — the flag is set by the fact of the room, not by specific actions)
- `archive_searched = true`

### Flags Read
- None (this is early in Act I)

### Lighting
- Archive entrance: lamp-lit, institutional. Not warm. This building is full of loss.
- Henrietta's study: one window, afternoon light (grey). The searched room is bright
  enough to see everything clearly — this horror doesn't hide in shadow.

---

## Scene 4 — The Iron Chalice Chapel

**File:** `scenes/act1/IronChaliceChapel.tscn`
**Plays:** After `calla_meeting_arranged = true`
**Size:** ~2 screens wide

### What Happens Here
Dame Calla gives Roland 40 minutes in the chapel alone, light off. He takes the pommel.
He tells her what he's done before he leaves. She does not stop him.

This is the first major objective — Piece One of the Sundered Crown. The scene is tense
because Roland is doing something irreversible in a building he was expelled from.

### Layout

```
[CHAPEL ANTEROOM] → [CHAPEL NAVE] → [ALTAR AREA]
        ↑
[DAME CALLA waits here during Roland's time in the chapel]
```

**CHAPEL ANTEROOM** — small waiting room. Dame Calla is here on arrival. Dialogue: the
arrangement. She explains she can give him 40 minutes, the chapel will be empty, the
light will be off. She does not ask why he needs the pommel. She has made her calculation.
This conversation has no branching — she will not change her terms — but Roland's
responses reveal character.

After dialogue: Calla stays in the anteroom. Roland enters the chapel alone.

**CHAPEL NAVE** — the chapel interior, dark. The only light source is a single candle on
the altar (PointLight2D, low energy, warm). Pews on both sides. Stone floor. Iron Chalice
iconography on the walls (placeholder: dark wall tiles). The architecture should feel
familiar to Roland — he worshipped here.

Investigation points in the dark nave:
- **A pew near the front** — Roland sat here as a novice. Investigation: brief memory
  fragment (no cutscene — Roland's internal monologue).
- **The iron door to the left** — locked. The chapter records room. Investigation: "Not
  tonight."

**ALTAR AREA** — the far end of the nave. One more step up. The altar itself, stone, with
the iron pommel resting on a fitted mount in the center. Candle to one side.

- **The altar (investigation/interact)** — Roland approaches. He examines the pommel.
  He makes his decision. He takes it. He replaces it with an iron rod of identical weight
  he brought for this purpose (pre-planned — Roland narrates this).
  Flag set: `pommel_piece_1_acquired = true`.

After taking the pommel: Roland returns to the anteroom. Final Calla dialogue: he tells
her what he's done. She says nothing. He understands. He leaves.

### Flags Set
- `pommel_piece_1_acquired = true`
- `calla_knows_roland_took_pommel = true`

### Flags Read
- `calla_meeting_arranged = true` (required to enter scene)

### Lighting
- Anteroom: lamplight, functional. Calla's space is composed.
- Chapel nave: **very dark**. Single altar candle only. The player navigates by feel.
  This is the darkest playable scene in Act I — intentional. Roland is doing something
  in the dark, literally and figuratively.
- Altar: candle casts a small warm circle. The pommel is visible in it.

### Notes for Implementation
- The 40-minute constraint is narrative only (no real-time clock). The scene ends
  when the player takes the pommel.
- "Light off" means CanvasModulate darker than the night chase — ambient almost zero,
  only the altar candle.
- The iron rod swap is handled in Roland's narration/internal monologue — no separate
  animation needed. He describes what he's doing.

---

## Scene 5 — The Archive Interior (Restricted Section)

**File:** `scenes/act1/ArchiveInterior.tscn`
**Plays:** After finding Tomlin and convincing him
**Size:** ~2.5 screens — entrance hall + side room + restricted section

### What Happens Here
Roland finds Tomlin (the suspended assistant archivist), convinces him to provide access
to the restricted section, and discovers the genealogical record connecting Aldric Vane
to Mordvar's bloodline.

This is the first flag-conditional branching dialogue in the game. The player must have
`henrietta_dead = true` to unlock the key persuasion option. Without it, Tomlin stays
silent — Roland can try twice, then must come back.

### Layout

```
[ARCHIVE ENTRANCE HALL] → [MAIN STACKS] → [RESTRICTED SECTION DOOR]
                                ↓
                          [SIDE ROOM — Tomlin]
```

**ARCHIVE ENTRANCE HALL** — same as Scene 3, but the archivist at the desk is different
(a junior not on suspension). He won't let Roland into the stacks without authorization.
Investigation point: a noticeboard with Tomlin's name listed under "suspended pending
investigation." This is the lead.

**MAIN STACKS** — rows of shelving, lamplight, vaulted stone ceiling. Several ambient
investigation points (books, records Roland can pull and examine — none relevant to the
current quest, but establish the Archive as a real place).

**SIDE ROOM** — a small sorting room off the main stacks. Tomlin is here, not really
working, waiting for something. He is frightened. He knows what Roland wants before Roland
asks.

Tomlin dialogue tree:
- **Without `henrietta_dead = true`:** Tomlin denies having the key. "I don't know what
  you're talking about." Can be pressed once. Leaves. Scene ends — come back after
  Henrietta's room is found.
- **With `henrietta_dead = true`, first option (push):** "Tell me where the key is."
  Tomlin refuses harder. Dead end.
- **With `henrietta_dead = true`, listening option:** "You already know she's dead."
  Pause. Tomlin nods. "Then you know why I'm asking." This is the key option — not an
  argument, an acknowledgment. Tomlin gives the key.
- **Flag `tomlin_helped = true` on success.**

**RESTRICTED SECTION** — unlocked by Tomlin's key. A smaller back room: only the oldest
and most sensitive records. Low shelves, locked display cases (unrelated to current quest).

Investigation: the genealogical record. Roland pulls it — it's a family tree spanning
500 years. He traces the lateral branch. The name change. The frontier settlement.
The name: Vane. He logs it in his journal.

Internal monologue: "I don't know what this means yet. A blacksmith in Coldstoke. I'll
find out later." (This is the plant. On replay: the player knows exactly what it means.)

Flag set: `aldric_vane_name_logged = true`.

### Flags Set
- `tomlin_helped = true`
- `aldric_vane_name_logged = true`

### Flags Read
- `henrietta_dead = true` — gates key persuasion option with Tomlin
- `archive_searched = true` — Tomlin's dialogue acknowledges Roland was in her room:
  "You've already been up there, haven't you." Not a question.

### Lighting
- Entrance and main stacks: institutional lamplight. Consistent with Scene 3.
- Restricted section: darker, mustier. One lamp. The records here are not meant to
  be read often.

### Note on Tomlin
Tomlin is not an adversary. He is terrified and doing the right thing slowly.
His dialogue should feel like someone convincing themselves, not someone being defeated.
The player "wins" this scene not by being clever but by being honest about what has
happened and what it means.

---

## Act I — Connections and Flag Summary

```
Night Chase
  → scene_night_chase_complete = true
  → Opens: Aldenholt Hub

Aldenholt Hub (hub)
  → Connects all Act I scenes
  → Ambient NPC dialogue updates on: henrietta_dead, pommel_piece_1_acquired

Archive / Henrietta's Quarters
  → henrietta_dead = true
  → archive_searched = true
  → Unlocks: Tomlin dialogue option in Scene 5

Iron Chalice Chapel
  → Requires: calla_meeting_arranged = true
  → pommel_piece_1_acquired = true
  → calla_knows_roland_took_pommel = true
  → Unlocks: Act II (Roland now has the first piece and must leave Aldenholt)

Archive Interior / Restricted Section
  → Requires: henrietta_dead = true (for Tomlin key option)
  → tomlin_helped = true
  → aldric_vane_name_logged = true  ← the plant; pays off in Act II/Game Two
```

**Piece One acquired. Henrietta dead. Aldric Vane's name logged as a footnote. Act I ends
when Roland leaves Aldenholt. Act II begins.**
