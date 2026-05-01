# Level Layouts — Act IV: The Ashfields

Act IV is short, climactic, and largely fixed in structure. The player has no
quest choices left — only how to fight. Three scenes. One decision was already
made in Mor-Vethrin.

For story context: `GAME1_PART2.md` → Act IV.
For visual direction: `ART_DIRECTION.md` → The Ashfields.

> **Status:** Sketch. Act IV level design sessions have not been run yet.
> Expand into full per-scene layouts before building.

---

## The Ashfields — Act IV

**Scenes (3):** Weeping Wood Exit → The Ashfields Retreat (the Ashlord's counterstroke) → The Tunnel Exit

The Ashfields are eastern Mira beyond the Spine. Grey dead ground — once productive
farmland and light forest, killed over centuries by ash drifting west from Drûn-Khazad
across the Shroud Sea. Ghost stumps of ancient trees, crumbled farmstead walls, dry
creek beds. Permanent ash-haze. Roland grew up near here. The haze is normal to him.

---

## Scene 1 — Weeping Wood Exit

**File:** `scenes/act4/WeepingWoodExit.tscn`

The party emerges from Mor-Vethrin — the deep reaches of the Weeping Wood — with
the Obsidian Shard in hand. The Naergrim's deal is concluded. Whatever was owed has
been paid. The Weeping Wood releases them into the eastern fringe of the Spine's foothills,
and beyond that fringe: the Ashfields begin.

The visual shift is immediate and significant. The Weeping Wood's grey-dead trunks and bare permanent branches give way to grey-brown dead soil. All colour drains toward ash. Ghost
stumps of ancient trees. Crumbled farmstead walls. The sky is the colour of old bone.

Roland now holds all seven Crown pieces — the Obsidian Shard was the last. There is
no ceremony here. The party keeps moving.

**Design notes:**
- Ash-haze particle effect begins at the treeline: sparse, slow-drifting grey particles.
  Low opacity. Perpetual from here on.
- No warm light sources except what the party carries.
- The Brightwatch fighters who sheltered Roland earlier are positioned ahead, holding
  at a ruined farmstead wall. Their camp is the first warm thing visible — torchlight
  against the grey. The interaction here sets up their role in the retreat ahead.
- Optional investigation: Roland recognises landmarks from childhood. Brief internal
  monologue — not about the quest, about what this place was before it was grey.

**Key flags set:**
- `obsidian_shard_secured = true`
- `all_seven_crown_pieces = true`
- `ashfields_reached = true`
- `brightwatch_contacted = true`

---

## Scene 2 — The Ashfields Retreat

**File:** `scenes/act4/AshfieldsRetreat.tscn`

The Ashlord has been tracking the operation. He knows Roland secured the Obsidian
Shard. He knows Roland now holds all seven pieces. He cannot allow them to reach
Aldric Vane. He has come out of the Ash Tower himself for the first time in decades —
the Crown pieces are too important to trust to a field commander.

The counterstroke hits as the party crosses the open Ashfields. This is the climax
of Game One's combat: a fighting retreat westward across grey dead ground, not a
confrontation at a ritual site.

### The Ashlord's Arrival

He does not send soldiers first. He comes himself.

He is centuries old. Partially hollowed — Mordvar's growing presence has been
filling in the places the man used to be. Amplified by that presence, formidable
in a way that no field commander has been. The party has faced Ashen Hand soldiers
and Hollow throughout the game. The Ashlord is neither. He is what happens after.

But proximity to all seven Crown pieces simultaneously creates interference with
his connection to Mordvar. The pieces were sundered for a reason. Reunited, even
unassembled, they resist the influence that flows through the Ashlord. He feels it.
He does not retreat from it. He pushes through — but the push costs him.

### The Engagement

A set piece, not a standard combat encounter:

- The Ashlord engages Roland's party directly on a flat ash-plain, visibility low,
  the haze thickening around him as he approaches
- The seven Crown pieces in Roland's pack create visible interference — a faint pulse,
  a wrongness in the air near him that the Ashlord cannot simply override
- The engagement is brutal. The party holds, barely. The interference from the pieces
  buys the margin that surviving requires.
- The Ashlord is gravely injured — not from any single blow but from the sustained
  interference and the combat together. He does not fall. He retreats east toward
  the Spine, back toward the Ash Tower. He is not capable of pressing further.

He is not killed here. He dies in Game Two, at Khorumzad.

### Vaeroth Caine

Vaeroth Caine — the Ashlord's field commander, the operational mind behind the
Ashen Hand's movements throughout Game One — is present in the same engagement.
He is killed or captured before the retreat is complete. The Ashen Hand's command
structure does not survive Act IV intact.

### The Brightwatch

The Brightwatch fighters who sheltered Roland and held at the farmstead hold the
rear of the retreat as the party moves west. Their sacrifice is not cutscene-framed —
it happens on the map, in the battle, as part of the retreat sequence. Named fighters
from the Brightwatch camp may not survive.

If the player spoke with specific Brightwatch fighters earlier and remembers their
names, their absence in the aftermath is legible without narration.

### Structure

The retreat moves west. Multiple combat encounters along the path, with the party
fighting rearguard while moving. The timing pressure is intentional — this is the
most mechanically demanding sequence in Game One.

Dagna's seismic analysis unlocks a side passage at one junction: shorter route, fewer
encounters, at the cost of missing a Brightwatch fighter who needs to be told which
way to go. Named Brightwatch fighters: at least two should be nameable in the Scene 1
camp. Their fate in the retreat is flagged but not forced — some may survive based on
player pathing choices.

**Key flags set:**
- `ashlord_engaged_directly = true`
- `ashlord_gravely_injured = true`
- `ashlord_retreated_east = true`
- `vaeroth_caine_neutralised = true`
- `brightwatch_casualties = [list of named fighters who did not make it]`

---

## Scene 3 — The Tunnel Exit

**File:** `scenes/act4/TunnelExit.tscn`

Orion has been planning the exit route since they arrived in the Ashfields. He has
not explained this until it is needed. It is needed now.

The exit is a Sailor's Guild safe-house tunnel — not a Brotherhood route, not a
military one. A merchant and navigator's network, catalogue of quiet exits. Orion
knows about it because he has been cataloguing exits. His idle animation throughout
the game — the exit-glance when entering new rooms — pays off here: he found this
tunnel two days ago and said nothing because they were not leaving yet.

The tunnel entrance is in the Ashfields. The exit is west of them, into safer ground.
The Ashen Hand does not know where it goes.

### The Emergence

The party comes up into daylight. The Ashfields are behind them. The ash-haze stops
at the tunnel exit like a curtain — it does not drift this far west.

Roland checks the pack. Seven Crown pieces. All present.

The Ashlord is wounded and retreating toward the Ash Tower. Vaeroth Caine is gone.
The Ashen Hand has no operational command left in the field. None of this ends
Mordvar. None of this seals what is beneath Drûn-Khazad. But the pieces are intact
and Roland is alive and west of the Ashfields.

Roland's journal update: "We have not won. We have bought time. The next step is
Khorumzad." (Sets up Game Two.)

**Design notes:**
- The last shot framing: the tunnel entrance behind the party, the Ashfields beyond
  it. The ash-haze. Then the party turns west.
- No music at the tunnel exit — ambient wind and the absence of the battle's sound.
  The contrast with the retreat is the beat.
- The Epilogue scene follows directly from here.

**Key flags set:**
- `orion_sailors_guild_route_used = true`
- `ashfields_exited_west = true`
- `game_one_complete = true`

---

## Game One — Final State

**All seven Crown pieces secured. Ashlord gravely injured and retreated east. Vaeroth Caine killed or captured. Ashen Hand's operational leadership broken.**

Roland leaves the Ashfields with:
- All seven Crown pieces (unassembled — the Crown is not yet reassembled)
- Aelthurion's complete intelligence briefing (`aelthurion_briefed`)
- Aldric Vane's identity (`aldric_vane_identity_known`)
- Knowledge of what the Aeluvain is and what it requires
- Knowledge that Khorumzad is the next destination
- Orion Farr and Dagna Irontrack

Game One ends. Game Two begins in Khorumzad.

---

## Epilogue Scene (Optional)

**File:** `scenes/act4/Epilogue.tscn`

Brief. Roland, Orion, and Dagna at the tunnel exit. Daylight. The Ashfields visible
behind them. No music — the ambient haze and wind.

Roland opens his journal. He reads the entry on Aldric Vane — the one he wrote in
Act I as a footnote. He adds one line: "Not a footnote."

Journal closes. Screen fades.

**On replay:** the player reads the Aldric Vane entry at the Archive in Act I knowing
what this moment will contain. The epilogue line is written for the second playthrough.
