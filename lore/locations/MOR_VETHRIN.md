# Mor-Vethrin

**Type:** City
**Kingdom/People:** Naergrim
**Position:** Eastern escarpment of the Weeping Wood, northeastern Mira
**Story relevance:** Game One, Act IV — obsidian shard (seventh piece); Serethi-Twice-Dead audience; the final deal

---

## Physical Description

Built into dark sedimentary and metamorphic cliff-faces at the eastern edge of the Weeping Wood, where the dead forest meets hard escarpment rock. No windows on the western side — a design choice, not a structural limitation, facing away from the Greatwood and Aelorin lands. The single gate has a bone arch: actual bone, from something large, mortared in place when the city was founded. The city blends into the dark cliff rock to a degree that makes it difficult to identify from a distance.

The architecture is vertical — sheer face construction going up and down the cliff rather than spreading horizontally. Inside: narrow passages, cold stone, braziers burning black (the only heat source — no volcanic vents here), no wasted material anywhere. The Naergrim do not offer comfort. The cold is a condition of the place and they have not sought to change it.

The obsidian in the city's construction — and in the vault where the Crown shard is kept — was brought from Thal by trade, not sourced locally. The escarpment here is dark sedimentary rock, not volcanic. The Naergrim chose this site for the cliff face and the dead forest around them, not for geology.

Map note: Dark fortress symbol on cliff face, no windows west.

---

## 3D Scale Reference
> At 8 voxels per meter (project standard: 1 voxel = 0.125 m)

Key dimensions:

- [x] Cliff face height: dark sedimentary/metamorphic escarpment, older and more weathered than volcanic peaks — estimate 40–80 m exposed cliff face = 320–640 voxels
- [x] Bone arch gate: from something large — arch span ~4 m wide × 5 m tall = 32 × 40 voxels; bone material implies curved, organic geometry
- [x] Interior passage width: narrow, no waste — ~2–3 m = 16–24 voxels
- [x] Interior passage ceiling: cold stone, low ceiling — ~3 m = 24 voxels; no volcanic vent heating; braziers burning black provide the only warmth
- [x] Serethi's audience chamber: one carved chair, one carved bowl, nothing else — deliberately small room; suggest ~6 m × 6 m × 4 m = 48 × 48 × 32 voxels (the smallness is the point)
- [x] No windows on western face: affects geometry — all window openings face east into the cliff rock, away from the Weeping Wood and the Aelorin lands beyond
- [x] Camera arm length: exterior approach = arm 12, elevation 48°; interior passages = arm 8–9, elevation 52°; Serethi's chamber = arm 8, elevation 55° (tight, no wasted space)

The "vertical architecture" description means floors are carved into the cliff face, accessed by narrow internal stairs or passages rather than horizontal street navigation. This is fundamentally different from any other location in the game — vertical rather than horizontal movement within the city.

---

## Art Direction Notes

No warm tones at all. No torches — the Naergrim use braziers burning black for minimal heat. The primary light source is not identifiable: pale, cold, even. This is a deliberate visual mystery — light filters through the cliff stone itself in ways that should not be physically possible, a residue of Naergrim corruption magic. The braziers burn but give minimal illumination; they are for heat only, and the Naergrim seem largely indifferent to the cold anyway.

Serethi's audience chamber: the visual silence is the point. One carved chair. One carved bowl. The conversation is the entire content of the room. Any decorative element would be wrong.

Naergrim NPCs move with economy. No wasted motion. Their city wastes nothing — their people reflect the city. This is a behavioral note for NPC animation: minimal gesture, deliberate movement, no idle shuffling.

The city blending into the volcanic rock: from the approach path, Mor-Vethrin is nearly invisible. The bone arch gate is the first clear landmark. This is an art direction challenge — the city must be identifiable in-game but the lore says it's hard to spot.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT3.md`
**Status:** Sketched. 2–3 scenes identified.

Scenes:
1. Weeping Wood approach — dead grey-trunked trees, fixed cloud cover overhead, the voices in the trees (Naergrim scouts), bone arch gate appearing from the darkness at the cliff base; no combat on approach (arriving in fighting posture is an insult; Naergrim watch the path from the moment the player enters the Wood)
2. (Optional) Pale Defection corridor encounter — brief quiet exchange before the audience
3. Serethi's audience chamber — the deal; obsidian shard acquired

Game One's last real decision lives here: is freeing the world from Mordvar worth letting the Naergrim walk away from the atrocities of the last decade? No delay option. No third path.

---

## Connections

- **Arrives from:** Ashfields approach (northeast from the Vosskaran frontier zone, into the Weeping Wood, east to the cliff escarpment)
- **Exits to:** Act IV continues (return from Mor-Vethrin to the Binding Site in the Ashfields)

---

## Open Questions / Gaps

- The "Pale Defection" faction contact: where exactly in the Mor-Vethrin approach does this happen? A corridor before the audience, but which corridor?
- If three Naergrim fighters join Roland at the Binding Site and the Ashfields fighting retreat (via the Pale Defection option): how do they travel there from Mor-Vethrin? Do they follow Roland out of the Weeping Wood?
- The Naergrim vault where the obsidian shard is held: is it shown to the player, or does Serethi simply produce the shard during the audience?
- Vertical architecture as gameplay: how does the player navigate up and down the cliff face? Internal stairs? Rope-and-pulley systems? This is an unusual movement requirement for the game's camera setup.
- Lighting mystery: "sources the player cannot identify" — in 3D voxel terms, this likely means diffuse ambient lit from an unknown direction without visible OmniLight sources; no volcanic glow here, so the effect must be achieved differently than originally planned
