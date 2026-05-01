# Level Layouts — Act III: The Elder Peoples

Act III takes Roland beyond the human kingdoms into the territories of the Aelorin,
the dwarves, and the Naergrim. The tone shifts — these are older places, older
agreements, older griefs.

Two major arcs in Act III:
1. **Karaz-Dûn** — The copper disc. Dagna Irontrack joins in the Underway.
2. **Mor-Vethrin** — The obsidian shard (seventh piece, the one Henrietta couldn't trace).

For story context: `GAME1_PART2.md` → Acts III and IV (the seventh piece).
For visual direction: `ART_DIRECTION.md` → Karaz-Dûn, Underway, Mor-Vethrin.

> **Status:** Sketch. Act III level design sessions have not been run yet.
> Expand into full per-scene layouts before building.

---

## Karaz-Dûn Arc — The Copper Disc

**Scenes (5–6):** Underway entry → Underway tunnels (Dagna joins mid-route) →
Kazaad-Brak approach → Kazaad-Brak interior (Barak Stonecroft) → Karaz-Dûn
upper halls → Dragon-Watcher record office → Thrarin's treasury (via Darva)

**Piece:** Copper disc — in Thrarin's treasury as part of a Second Age artifact
collection. Thrarin collected it a century ago as a curiosity; he does not know
what it is.

### The Underway

The Underway is the dwarven tunnel network beneath the Spine. Travel scene —
the player moves through connected passages, each with a junction and a choice
of direction (Dagna marks every junction she passes with chalk as habit).

**Dagna Irontrack joins here.** Three days into the Underway, Roland's party
encounters a Dragon-Watcher moving in the opposite direction. She is heading
to Kazaad-Brak for the same reason: to reach Barak Stonecroft.

The joining scene is a conversation in a waystation alcove. Neither commits
immediately. They are going the same direction on the same errand. The conversation
where she commits: Roland explains the full scope of what he is doing. Dagna
listens. Then: "Your volcanic problem and my volcanic problem are the same volcanic
problem." She is in.

**Design notes for Underway:**
- Vaulted stone, regular spacing, waystation alcoves with supply caches
- Low warm runelight — maintained, not dark. The Underway feels safe in a way the
  surface doesn't always.
- Enemy encounters in the Underway: the first multi-encounter sequence of the game.
  Ashfallen soldiers using the tunnels. Dagna's seismic analysis unlocks investigation
  points at tunnel intersections — cracks in the wall, stress patterns.
- The junction system: a small navigational choice at each junction. Wrong turns
  lead to dead ends with minor loot or environmental storytelling. Dagna's chalk
  marks persist (visual feedback that the player has been here).

### Kazaad-Brak

The southern dwarven hold. Besieged eleven times — defensive architecture everywhere.
Barak Stonecroft is in protective isolation here (not imprisoned, but separated from
Karaz-Dûn by the compromised steward's operation).

Barak scene: the information exchange. He confirms Drossvik's operation. He knows
the disc's location. He can help Roland reach Darva — Thrarin's regent daughter.

### Karaz-Dûn Upper Halls

The Dragon-Watcher records office: Dagna recovers her original seismic data and
proves the falsification. The compromised steward's amendments are in a different
hand. Darva (once the auditor's report is in hand) recognizes the handwriting.
Steward removed. Dagna's name cleared.

Thrarin's treasury: access via Darva. She retrieves the disc in exchange for the
auditor's report — leverage to deal with her father on her own terms. Roland gets
the disc; Darva gets what she needs to stabilize Karaz-Dûn without Roland's
further involvement.

**Design notes:**
- Forge heat: upper Karaz-Dûn is warm year-round. Orange-amber dominant light.
- Dragon-Watcher records vault: fire-resistant stone, Level 3. Cooler, more sober.
- The treasury approach: not a heist — Darva is the door. The scene is a political
  negotiation, not stealth.
- Bromrin appears briefly here: his mind is intact at this point in Game One.
  His Game Two deterioration is foreshadowed in small ways (a repeated phrase,
  a moment of unusual stillness).

**Key flags:**
- `dagna_joined = true`
- `dagna_name_cleared = true` (optional side quest completion)
- `copper_disc_acquired = true`
- `drossvik_operation_confirmed = true` (sets up Game Two)
- `darva_alliance = true` (Karaz-Dûn stabilized)

---

## Mor-Vethrin Arc — The Obsidian Shard

> **Note:** The Mor-Vethrin visit is now Act IV, not Act III. It was relocated here
> from the old Act III structure when the lore was updated. The Mor-Vethrin arc follows
> the Karaz-Dûn arc and precedes the Ashfields fighting retreat. See `LEVEL_LAYOUTS_ACT4.md` for the
> Act IV scene sequence. This section describes the Mor-Vethrin scenes themselves.

**Scenes (2–3):** Weeping Wood approach → The bone-arch gate → Serethi's
audience chamber

**Piece:** Obsidian shard — in the Naergrim's central vault. Held for two thousand
years since the Grand Alliance. The Naergrim have always known what it is.

### The Approach

Northeastern Mira. The Weeping Wood: dead grey-trunked trees with bare permanent
branches, fixed cloud cover overhead, voices in the trees (Naergrim scouts watching
the borders). The city is difficult to identify from a distance — it blends into the
dark cliff escarpment at the wood's eastern edge.

One path in. One gate. The bone arch above it: actual bone, from something large,
mortared in place. Roland observes it. His journal notes it without comment.

No combat on the approach — arriving at Mor-Vethrin in a fighting posture would be
read as an insult. The Naergrim watch the approach path. Roland knows this.

### Serethi's Audience Chamber

The most stripped-down room in the game. One carved chair. One carved bowl. Nothing
else. Serethi-Twice-Dead occupies the chair.

The Naergrim leader's offer: he will provide the shard in exchange for Roland's
acknowledgment that the Naergrim will not be included in any punitive settlement
after Mordvar's defeat. Not loyalty — withdrawal. Serethi has calculated that
Roland will accept. He is watching the calculation play out on Roland's face.

**This is Game One's last real decision.** No delay option. No third path. Is freeing
the world from Mordvar worth letting the Naergrim walk away from the atrocities of
the last decade?

The player decides.

**Optional: The Dissenting Voice.** A minority Naergrim faction approaches Roland
quietly before or after the Serethi audience. Their leader — called the Pale
Defection as a joke and has adopted it — wants genuine alliance, not withdrawal.
If Roland acknowledges this faction and creates a quiet channel, three Naergrim
fighters join Roland at the Ashfields fighting retreat,
acting under their own authority. Serethi is furious. He honors the deal anyway.

**Design notes:**
- Mor-Vethrin: no warm tones at all. No torches. Pale, cold, even illumination
  from sources the player cannot identify.
- Serethi's chamber: the visual silence is the point. One chair. One bowl. The
  conversation is the entire content of the room.
- The Pale Defection contact happens in a Mor-Vethrin corridor before the audience —
  a brief quiet exchange, no NPC name given, only the faction name.
- Naergrim NPCs (ambient): move with economy. No wasted motion. Their city wastes
  nothing — their people reflect the city.

**Key flags:**
- `naergrim_withdrawal_deal = true` (Serethi's terms accepted)
- `naergrim_deal_refused = true` (if player refuses — Serethi notes it, revises terms;
  there is a deal to be made but it costs more)
- `obsidian_shard_acquired = true`
- `pale_defection_contact = true` (optional — three Naergrim fighters at Drûn-Khazad)

---

## Act III — Completion Conditions

Both remaining pieces acquired:
- `copper_disc_acquired = true` (Karaz-Dûn)
- `obsidian_shard_acquired = true` (Mor-Vethrin)

**All seven pieces of the Sundered Crown are now in Roland's possession.**

Companions: Orion Farr (joined Act II) + Dagna Irontrack (joined Act III Underway).

Information state:
- `aelthurion_briefed = true` — Roland knows the binding requires blood of three peoples
- `aldric_vane_identity_known = true` — Roland knows what Aldric is and what it means
- `drossvik_operation_confirmed = true` — the intelligence that drives Act II of Game Two

**Act IV begins — Roland moves to exit through the Ashfields with all seven Crown pieces.**
