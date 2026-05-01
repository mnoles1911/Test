# Level Layouts — Act II: The Four Kingdoms

Act II spans all four human kingdoms. Player determines the order — Solgrade is
recommended last because it connects information from the other three. Each kingdom
is 3–5 scenes internally linear; the kingdom selection is open.

For story context: `GAME1_PART1.md` → Act II.
For visual direction: `ART_DIRECTION.md` → location visual identities.
For city descriptions: `CITY_DESCRIPTIONS.md`.

> **Status:** Sketch. Act II level design sessions have not been run yet.
> Expand each kingdom into full per-scene layouts (like `LEVEL_LAYOUTS_ACT1.md`)
> before building.

---

## Kingdom Order Logic

| Kingdom | Piece | Recommended? |
|---|---|---|
| Vosskara | Bronze ring | Any order |
| Caer Brannoch | Copper wire | Any order |
| Aelorin Greatwood | Silver clasp | Any order |
| Solgrade | Gold coin | Last — connects Korvath intel to other arcs |

The player is told Solgrade is recommended last (via Roland's journal) but not prevented
from going there first. Doing so changes available dialogue options in the Korvath scene —
Roland has less leverage without intelligence from other kingdoms.

---

## Vosskara — The Bronze Ring

**Scenes (3–4):** City approach → Yaromir's citadel exterior → War council chamber
(underground) → optional: Garrison frontier (Tribute Papers side quest)

**Piece:** Bronze ring — thumb ring worn by Yaromir, given to his grandmother by a
wandering smith. Yaromir will give it freely once commitment is earned.

**Design notes:**
- The negotiation IS the quest. There is no infiltration, no theft.
- Scene structure: first conversation (Roland tries to negotiate — fails), mandatory
  return conversation after player has spent time in the city (the listening gate),
  then the key question: "What do you want to be remembered for?"
- The listening mechanic lives here. Player MUST not push for the ring on first meeting.
  The option to ask too early is available — taking it locks out the optimal path.
- Underground war council chamber: the most militarily austere room in the game. No
  decoration. Torch-lit only. Seating for twelve, maps on a central table.
- Ash-haze visible from the eastern wall — particle effect, slow drift, grey.

**Key flags:**
- `yaromir_first_meeting_complete` — listening gate; ring cannot be asked for until set
- `vosskara_committed` — earned after the key conversation
- `tribute_papers_delivered` (optional) — Frost Brotherhood intel delivered to Yaromir

---

## Caer Brannoch — The Copper Wire

**Scenes (4–5):** Lower docks + Sailor's Guild Hall → Sea-lift to upper city → Eilwen's
court → Sailor's Guild voyage (ship deck, traveling scene) → Copper Isles Archive

**Piece:** Copper wire — catalogued as an artifact of unknown function in the Sailor's Guild
Archive. Released without difficulty once Roland has Sailor's Guild endorsement.

**Design notes:**
- Orion Farr joins here. His joining scene is in the lower docks — he spots Roland
  trying to get passage to the Copper Isles without credentials.
- The voyage is a traveling scene: ship deck, storm sequence, discovery of the Hollow
  Court infiltrator in the Sailor's Guild safe-house island. This is the most spatially
  unusual Act II scene — a moving environment.
- Caer Brannoch visual split: lower city (wet, dark wood, salt, rope) vs upper city
  (stone, fleet command, windswept). The sea-lift connects them.
- Eilwen's court (upper city): the Shroud charts side quest fires here if Roland
  delivers the charts from the Sailor's Guild Archive.

**Key flags:**
- `orion_joined = true` — Orion available as companion from this point
- `copper_wire_acquired = true`
- `shroud_charts_delivered` (optional) — earns Caer Brannoch naval commitment
- `hollow_court_infiltrator_found` — story beat during the voyage

---

## Aelorin Greatwood — The Silver Clasp

**Scenes (3–4):** Sirathiel-by-the-Sea (entry) → Greatwood approach (transition) →
Lirien-Thal canopy platform (Aelthurion audience) → The Second Glade

**Piece:** Silver clasp — left at the Second Glade boundary by an Aelorin who completed
the Aelthiren three centuries ago. The objects of the Aelthiren are not touched. Roland
must be given access by Aelthurion.

**Design notes:**
- Dagna CANNOT accompany Roland here. Her presence complicates Aelorin willingness to
  speak openly. If player brings Dagna, Aelthurion is polite but guarded — some
  dialogue options close.
- Aelthurion's audience is one of the trilogy's significant scenes. He gives Roland
  a full intelligence briefing — 40 years of observation. He also tells Roland what
  the Aeluvain requires and reveals Aldric Vane's identity and bloodline.
- The scene ends with the line: "Is there anything else I should know?" / "Everything
  that matters is in what I have already told you." Roland notices what was NOT said.
- Lirien-Thal visual: silverwood canopy, bioluminescent at night, faces in the bark
  (visible on close approach). No torches. Silver-green filtered light by day.
- The Second Glade: the Aelthiren boundary. Objects are preserved exactly as left.
  The clasp is among them — Roland must identify it from Henrietta's description.

**Key flags:**
- `aelthurion_briefed = true` — major information dump, unlocks many dialogue options
  in Acts III and IV
- `silver_clasp_acquired = true`
- `aldric_vane_identity_known = true` — expands the journal entry from Act I

---

## Solgrade — The Gold Coin

**Scenes (4–5):** City arrival → Golden Lance Hall (Vossant contact) → Korvath counting
house (infiltration) → Korvath negotiation → Council hearing (optional: Vossant verdict)

**Piece:** Gold coin — held by House Korvath, who know what it is and have been waiting
for someone to come asking.

**Design notes:**
- Most complex Act II arc. Two factions want different things from Roland simultaneously:
  Vossant (smuggling evidence) and Korvath (public endorsement).
- The counting house infiltration: Roland uses a purchased identity. This is a stealth/
  navigation scene — not combat, but timed or guarded access. He finds both the smuggling
  evidence and the coin on the same visit.
- Korvath negotiation is sophisticated. They have leverage; Roland has leverage. The deal
  that works: Roland gives them the smuggling evidence (implicating other Houses) in
  exchange for the coin + non-interference. Neither side is purely right.
- Solgrade visual: daylight, terracotta roofs, open streets. No CanvasModulate darkness —
  the brightest scenes in the game. Crisp shadows.
- The Council Hall has twelve equal entrances. The symmetry is the point.
- Vossant verdict (optional): delivering evidence to Vossant after the Korvath deal. Two
  Houses censured, one (House Pelarin) expelled. Sets up faction commitment.

**Key flags:**
- `gold_coin_acquired = true`
- `korvath_deal_made = true`
- `vossant_evidence_delivered` (optional) — earns Golden Lance commitment
- `house_pelarin_expelled` (optional, consequence) — mentioned in Act III ambient dialogue
- `iron_chalice_debt_path_available = true` — Korvath path resolves the Order's debt

---

## Act II — Completion Conditions

All four pieces acquired:
- `bronze_ring_acquired = true` (Vosskara)
- `copper_wire_acquired = true` (Caer Brannoch)
- `silver_clasp_acquired = true` (Aelorin Greatwood)
- `gold_coin_acquired = true` (Solgrade)

Optional commitments available:
- `vosskara_committed` (tribute dispute de-escalated)
- `tidewarden_committed` (Shroud charts delivered to Eilwen)
- `frost_brotherhood_committed` (Tribute Papers side quest)
- `golden_lance_committed` (Vossant's contract honored)
- `iron_chalice_debt_resolved` (Korvath path completed)

With all four pieces: Roland's journal notes the pattern. Act III begins — the older
peoples hold what remains. Six pieces in hand, one left unknown.

**Orion Farr has joined. Roland is no longer alone.**
