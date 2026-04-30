# Level Layouts — Act IV: The Binding

Act IV is short, climactic, and largely fixed in structure. The player has no
quest choices left — only how to fight. Three scenes. One decision was already
made in Mor-Vethrin.

For story context: `GAME1_PART2.md` → Act IV.
For visual direction: `ART_DIRECTION.md` → The Ashfields.

> **Status:** Sketch. Act IV level design sessions have not been run yet.
> Expand into full per-scene layouts before building.

---

## The Ashfields — Act IV

**Scenes (3):** Ashfields approach → The Binding Site (the ritual) → The Fighting
Retreat (Vaeroth's counterstroke)

The Ashfields are eastern Mira beyond the Spine. Grey dead ground, thin soil over
ancient lava beds, permanent ash-haze drifting from Drûn-Khazad far across the
Shroud Sea. Roland grew up near here. The haze is normal to him.

---

## Scene 1 — Ashfields Approach

**File:** `scenes/act4/AshfieldsApproach.tscn`

The party crosses from the Spine's eastern foothills into the Ashfields. The visual
shift is immediate and significant: all color drains toward grey. The warm palette
of dwarven holds gives way to grey-brown dead soil, ghost stumps of ancient trees,
crumbled farmstead walls. The colour drains out of the world.

**Design notes:**
- Ash-haze particle effect: sparse, slow-drifting grey particles. Low opacity. Perpetual.
- No warm light sources except what the party carries. The campfire (if the player
  rests here) is the warmest thing in the scene — the contrast with the cave scene
  from Milestone 1 is intentional.
- Ambient: Brightwatch fighters sheltering ahead of the party. Their camp is the first
  warm thing visible on the approach. This is where Roland meets them — volunteers,
  not soldiers. The interaction sets up their role in the retreat.
- Optional investigation: Roland recognizes landmarks from childhood. Brief internal
  monologue — not about the quest, about what this place was before it was grey.

**Key flags set:**
- `brightwatch_contacted = true`
- `ashfields_reached = true`

---

## Scene 2 — The Binding Site

**File:** `scenes/act4/BindingSite.tscn`

The original location of the Second Age ritual — a specific valley in the Ashfields
of eastern Mira. The Binding Site is not on or near the volcano. The Grand Alliance
chose this location deliberately: as far from Drûn-Khazad as the world allows, on
the western continent, on Mira's own soil.

### The Assembly

Roland assembles the Crown here. The pieces fit together as the Crown they were —
no puzzle mechanic. What Roland did not know (what Aelthurion declined to say
explicitly): the ritual requires blood of the Grand Alliance. A human, an Aelorin,
and a dwarf.

Aelthurion is present. He arranged this without explaining it. His arrival is not a
surprise to Roland — only the requirement is.

The dwarven blood: Dagna volunteers without being asked. This earns her Roland's
trust in a way the preceding weeks of shared errand had not quite managed.

### The Ritual

Not a combat scene. Not a timing mechanic. A sequence:
- The Crown assembled (interaction point on a stone altar at the valley floor)
- Roland places his blood (short dialogue — he understands now what Aelthurion arranged)
- Aelthurion steps forward (he has been waiting for this for forty years)
- Dagna steps forward (no hesitation)
- The binding renews

Visual: CanvasModulate warms slightly during the ritual — shifts from the Ashfields'
grey toward a faint orange. Subtle. The world responding to something being made right.

### What the Binding Does (and Does Not Do)

The renewed binding stabilizes what was deteriorating. It does not seal Mordvar again.
The seal was broken when the Vault of Aen-Vael was disturbed in Khorumzad. The only
thing that can truly end Mordvar is the Aeluvain, wielded by someone of his bloodline.

The binding buys time. The Ashlord — through whom Mordvar's will was flowing most
directly — is severed from the connection. Vaeroth loses a significant fraction of
his power.

Roland's journal update: "We have not won. We have bought time. The next step is
Khorumzad." (Sets up Game Two.)

**Key flags set:**
- `crown_assembled = true`
- `binding_renewed = true`
- `ashlord_severed = true`

---

## Scene 3 — The Fighting Retreat

**File:** `scenes/act4/FightingRetreat.tscn`

Vaeroth, diminished but not broken, launches a coordinated strike to prevent Roland
from leaving the Ashfields. This is the climax of Game One's combat — a fighting
retreat, not a boss fight.

### Structure

The retreat moves left to right (west). Orion has been planning the exit route since
they arrived — he does not explain this until it is needed, which is now.

Combat encounters along the retreat path, with the party fighting rearguard while
moving. The Brightwatch fighters hold the rear. Some do not survive.

Vaeroth does not appear directly in Game One. His forces do: Ashen Hand soldiers,
coordinated, efficient. No Hollow in this battle — these are human soldiers following
orders with full understanding of what they are doing.

### The Brightwatch

The Brightwatch fighters who sheltered Roland earlier hold the rear. Their sacrifice
is not cutscene-framed — it happens on the map, in the battle, as part of the retreat
sequence. Named fighters from the Brightwatch camp (met in Scene 1) may not survive.

If the player spoke with specific Brightwatch fighters at the camp and remembers their
names, their absence in the retreat's aftermath is legible without narration.

### Orion's Route

The exit is a Brotherhood safe-house tunnel that exits west of the Ashfields. Orion
knows about it because he has been cataloguing exits. His idle animation throughout
the game (the exit-glance when entering new rooms) pays off here: he found this tunnel
two days ago and said nothing because they weren't leaving yet.

The tunnel is the final scene beat: the party enters, the Ashen Hand does not know
where it goes. The last shot is the tunnel entrance behind them. The Ashfields outside.
The ash-haze.

**Design notes:**
- The retreat combat is the most mechanically demanding sequence in Game One. Multiple
  encounters, limited rest between them. The timing pressure is intentional.
- Dagna's seismic analysis unlocks a side passage at one junction — shorter route, fewer
  encounters, at the cost of missing a Brightwatch fighter who needs to be told which
  way to go.
- The named Brightwatch fighters: at least two should be nameable in the camp scene.
  Their fate in the retreat is flagged but not forced — some may survive based on
  player pathing choices.

**Key flags set:**
- `vaeroth_counterstroke_survived = true`
- `brightwatch_casualties = [list of named fighters who did not make it]`
- `orion_route_used = true`
- `game_one_complete = true`

---

## Game One — Final State

**Crown reassembled. Binding renewed. Ashlord severed. Vaeroth diminished.**

Roland leaves the Ashfields with:
- The renewed Crown (subtly different from what it was — reassembled, not restored)
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
