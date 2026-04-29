# Systems Design — Mira-Thal: Game One
## How the lore translates into Godot 4 mechanics

> This document covers game systems only. For story, characters, world, or quest content, go to `/lore`.

---

## Core Design Philosophy

**The writing is the game.** Every system exists to serve the story. Combat, traversal, and exploration are the verbs. The narrative is the meaning.

**Roland solves problems by understanding people.** The mechanical expression: most major encounters have non-combat solutions. Players who pay attention to what characters want can almost always find a path that does not require fighting. Players who fight through everything can still win — but will miss context.

**Choices have weight because information is real.** The game does not hide whether a choice matters. It hides what the consequence is and when it arrives. Henrietta's death, Aldric Vane's name in the Archive, Yaromir's unspoken question — all are surfaced honestly. The world remembers.

---

## Combat System — Active Turn-Based with Timing

### Core Loop

Turn-based at its core. Player selects actions from a menu. Actions have real-time timing windows that modify outcome.

### Timing Mechanics

**Attack timing.** A bar or arc sweeps across a target zone. Press at the right moment for bonus damage. Miss the window: normal damage. Hit the window: damage bonus + possible status effect.

**Block timing.** Enemy telegraphs before attacking. Press block in the window to reduce damage significantly. Miss: take full damage. Perfect block (tight window): reflect small damage or stagger enemy.

**Charge/hold.** Some abilities require holding through a fill bar. Release at full charge for maximum power. Used primarily by Corvus's environmental magic in Game Two — sustained effort with a visible cost meter.

### Game One Party Roster

Per `/lore/CHARACTERS_COMPANIONS.md` and `/lore/GAME1_PART1.md` / `GAME1_PART2.md`:

| Character | Joins | Mechanical role |
|---|---|---|
| **Roland Ashford** | Always present | Balanced — solid attack timing, decent blocking, investigative special abilities (analyze enemy for weaknesses) |
| **Orion Farr** | Mid Game One (Caer Brannoch arc) | Evasion-focused — "block" is a dodge that repositions; small timing window but large damage reduction if hit. Stealth and exit-route options |
| **Dagna Irontrack** | Game One Act III (Underway encounter) | Structural — slower attacks that mark enemies (next hit from any source deals bonus damage). Seismic/structural analysis unlocks investigation options |

**Note on Edran Vane:** `/lore/BACKSTORY_EDRAN.md` describes him joining in Game One as an institutional analyst. He does not appear in `CHARACTERS_COMPANIONS.md` or `REFERENCE.md`. Treat him as a recurring contact/ally until the writer confirms his companion status before building combat mechanics for him.

**Future games (for forward-compatible system design):**
- Game Two adds Corvus Tane (Conclave mage — high power, visible cost meter) and Seren of the Third Glade (Aelorin loremaster — ancient training, magic-adjacent abilities, lore-revelation gates)
- Game Three adds Aldric Vane (last of Mordvar's bloodline — combat-secondary; he does not need to fight Mordvar, only reach him)

### Active Party

Active party in combat: Roland + up to 2 companions. Player chooses which companions to bring to a scene. Some scenes restrict choices — Dagna cannot accompany Roland to Lirien-Thal for the silver clasp (her presence would complicate Aelorin willingness to speak openly).

### Enemy Design Principles

Per `/lore/PEOPLES.md` — the Hosts of the Ash Throne section:

- **Ashfallen** (former allies, hollowed): fight with familiar tactics. Recognition-hesitation is the design pressure — some Ashfallen wear gear matching named NPCs the player has met
- **Ashen Hand soldiers**: efficient, coordinated. Reflect Vaeroth's character — no wasted motion
- **Hollow** (Mordvar-adjacent): slow, implacable. Their attacks do not stagger — they press. Fighting them feels like fighting pressure, not intention
- **Mordvar himself**: not a boss fight. He is a weather event. The Game Three climax is what you do in his presence, not how you defeat him in combat

### Magic Cost in Combat

Corvus has a visible alteration meter (Game Two onward). Using magic fills it. At high fill: attacks more powerful, but block windows shrink and incoming damage scales up. At full: cannot use magic until combat ends. The meter resets between fights, but visible consequences (eye color shift, accelerated aging) are permanent at scripted thresholds per `/lore/BACKSTORY_CORVUS.md`.

---

## Dialogue System — Dialogic 2 Implementation

### Information as Currency

Roland's primary resource is what he knows. Dialogue options unlock based on:
- Information gathered in the current scene
- Information carried from previous scenes (story flags via GameState.gd)
- Companion presence (some options only available with a specific companion)

### The Listening Mechanic

Yaromir's scene (per `/lore/GAME1_PART1.md`) is the canonical example: the question that earns Vosskaran commitment ("what do you want to be remembered for") is only available after Roland has spent one full conversation with Yaromir without trying to negotiate.

Implementation: certain key dialogue branches require a "listening" or "understanding" response selection first. This is not a skill check — it is a design gate. The path is always there; the player has to find it by not pushing.

This pattern repeats across the game:
- **Yaromir** (Vosskara): listen before negotiating
- **Drossvik confrontation** (Game Two): allow him to provide information rather than forcing it
- **Aelthurion** (Aelorin Greatwood): notice when he says less than everything
- **Aedric Castrove** (optional Game One): present evidence rather than accusation

### Companion Comments

Companions observe during dialogue without interrupting — brief portrait + short text interjection. Each companion has a distinct observational lens from their lore:
- **Dagna**: notes structural details about rooms and old construction
- **Orion**: notes exits, escape routes, signs of recent traffic
- **Corvus**: senses things others do not (Game Two onward)
- **Seren**: recognizes ancient details, formal Aelorin script, things older than the room (Game Two onward)

### Consequence Flags

Every major dialogue outcome sets a flag in GameState.gd. Flags are not hidden — Roland's journal tracks what he knows and what has been agreed to. What the journal cannot tell the player is when a flag matters and how.

---

## Exploration System

### Zone Structure

Per `/lore/GAME1_PART1.md` and `/lore/GAME1_PART2.md`, Game One zones:

**Act I — Aldenholt (hub)**
Iron Chalice chapel, Loremaster's Archive restricted section, Dame Calla's quarters, Roland's lodgings, the night chase route through the streets

**Act II — Four Kingdoms (player-determined order; Solgrade recommended last)**
- Solgrade: House Korvath counting house, Council chambers, Golden Lance hall
- Vosskara / Vosskar-on-the-Iron: Yaromir's citadel, garrison frontier, Tribute Papers investigation
- Caer Brannoch + Copper Isles: cliff city, lower docks, Brotherhood voyage, Brotherhood Archive
- Aelorin Greatwood: Sirathiel-by-the-Sea (entry), Lirien-Thal (Aelthurion audience), the Second Glade

**Act III — The Spine and Beyond**
Karaz-Dûn via the Underway (Dagna joins en route), Kazaad-Brak, Barak Stonecroft, Mor-Vethrin (Naergrim city — Serethi's audience)

**Act IV — The Ashfields**
The binding site (valley below Drûn-Khazad's western approach), the Brotherhood safe-house tunnel retreat

### Each zone contains

- **Traversal areas**: where the player moves Roland. Interactable objects, NPCs with ambient dialogue, environmental storytelling
- **Scene triggers**: Area2D markers that initiate dialogue, combat, or cutscene sequences
- **Investigation points**: locations Roland can examine. Not everything yields game-relevant data. The player learns which type by paying attention to what Roland says

### No quest markers

The player's primary navigation tool is Roland's journal and his conversations. NPCs will tell the player where to go if asked — but asking counts as a dialogue beat, and characters notice when Roland needs help finding something he should already know.

### Companion presence rules

Bringing the relevant companion unlocks investigation observations and sometimes additional dialogue paths. Examples from the lore:
- **Dagna** + Underway / Khorumzad / any structural site → unlocks structural reading, seismic analysis
- **Orion** + any port, ship, or escape-route scenario → unlocks Brotherhood contacts and route options
- **Corvus** (Game Two) + magically active sites → unlocks magical sensing dialogue
- **Seren** (Game Two) + Aelorin sites or ancient construction → unlocks loremaster recognition

---

## Save System

### Manual + Autosave

- Autosave at every zone transition and before every major story scene
- Manual save at established rest points (fires, inns, Roland's safe locations)
- One save file per playthrough, three playthrough slots
- Encourages commitment; discourages reload-for-optimal-outcome on first play

### Cross-Game Persistence

Game One's flag file imports into Game Two. Game Two's into Game Three. The consequence of every choice Roland makes carries forward — see the faction commitment table in `/lore/REFERENCE.md` for which Game One choices alter Game Three's available forces.

This requires GameState.gd to use a forward-compatible serialization format (JSON with versioned schema). Worth establishing now even though it does not matter for Milestone 1.

---

## Journal System

Roland's journal is the player's primary reference. Contents:

- **Active quests**: current state, last known information
- **Completed quests**: what happened, what was agreed to, who was affected
- **People**: brief notes on everyone Roland has met; updates as Roland learns more
- **Places**: description and what Roland knows
- **The Crown**: piece locations known, acquired, assembled

The journal is written in Roland's voice — not neutral documentation. It reflects his perspective, his gaps, occasional wrong assumptions. The entry on Aldric Vane added during the Archive sequence in Act I is the journal's most important plant: a name Roland logged because Henrietta had been tracing it. On first read it should feel like a footnote. On replay it is anything but.

---

## Faction System

### Commitment States in GameState.gd

- **Unknown** — Roland has not encountered this faction
- **Aware** — initial contact made
- **Negotiating** — active quest relationship; terms being established
- **Committed** — alliance secured; faction appears at Drûn-Khazad (Game Three)
- **Lost** — cannot be brought into the alliance this game (some recoverable in Game Two)

### Game One Faction Commitment Triggers

Per `/lore/REFERENCE.md` faction alliance status table:

| Faction | Commitment trigger | Game Three result |
|---|---|---|
| Iron Chalice | Resolve Order's debt (Solgrade/Korvath path) | 1,200 knights; 112 survive |
| Tidewarden (Caer Brannoch Naval) | Deliver Shroud charts to Eilwen | Naval command; ~340 of 900 survive |
| Frost Brotherhood | Tribute Papers side quest | ~89 of 400 survive |
| Golden Lance | Honor Vossant's contract (Solgrade) | Light casualties |
| Vosskara | De-escalate Tribute War with Yaromir | Mostly intact |
| Brightwatch | Met and supported in Ashfields | High casualties (untrained volunteers) |

### Faction Awareness

Factions are aware of each other. The Naergrim withdrawal bargain (Serethi) is known to the Aelorin by Game Two — Aelthurion does not mention it, but he knows. The game does not punish the player for the Naergrim deal; it acknowledges that the world is watching.

---

## Side Quest Framework

Per `/lore/SIDE_QUESTS_GAME1.md`, Game One has seven side quests. None are mandatory. All reward players who explore. Several plant seeds that pay off in Games Two and Three:

- **The Ashsteel Formula** — spans all three games; full payoff in Game Three
- **The Hollow Court's Man** — surfaces Aedric's connection without naming him until Game Two
- **The Pale Defection** (Wyn) — informant payoff in Game Two
- **The Ledger's Price** — quiet institutional corruption thread, ongoing

System requirement: side quest flags must persist across games via GameState.gd, and Game Two must be capable of querying Game One's flag set on import.

---

## Implementation Priority for Milestone 1

Per the project root CLAUDE.md, Milestone 1 is the first walkable scene with lighting. None of the systems above need to be built yet. Build in this order:

1. Player movement (CharacterBody2D, 8-directional)
2. Camera follow at 3/4 angle
3. One zone scene with TileMap
4. PointLight2D + CanvasModulate for atmosphere
5. One Area2D trigger that prints "dialogue trigger fired" to console

Build each step. Verify it works. Then add the next. Combat, faction tracking, dialogue branching, and save serialization all come later.
