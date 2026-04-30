# The Greatwood

**Type:** Region
**Kingdom/People:** Aelorin (stewardship, not ownership)
**Position:** Northern Mira — from the Central Plains tree-line north to the tundra edge
**Story relevance:** Game One, Act II — the Aelorin Greatwood arc passes through here; silverwood groves near Lirien-Thal; the Second Glade

---

## Physical Description

From above the canopy appears as an unbroken dark-green mass broken only by the pale-silver patches of silverwood groves near Lirien-Thal and the circular light-openings of the Eight Glades. The wood's northern edge transitions into a shorter, stranger tree-line — locals call it the Edgewood — before giving way to tundra scrub at the continent's northern coast.

At ground level: ancient trunks wider than houses, root systems that form walls and natural bridges, a permanent green twilight even at noon. The deeper you go the larger the trees and the quieter the animals. Sound travels differently in the old growth. Visitors notice it without being able to say what changed.

Map texture: dense stippled or cross-hatched forest canopy with individual large trees indicated near Lirien-Thal. The Glades shown as small open circles within the forest mass.

---

## 3D Scale Reference
> At 8 voxels per meter (project standard: 1 voxel = 0.125 m)

Key dimensions:

- [x] Ancient trunk diameter: described as wider than houses — ~4–8 m = 32–64 voxels (at the base; significant taper upward)
- [x] Trunk height to first branch: old growth scale — ~20–30 m before canopy starts = 160–240 voxels
- [x] Canopy height: ~40–60 m above ground = 320–480 voxels
- [x] Root system walls: natural root bridges and enclosures — root diameters ~1–2 m = 8–16 voxels; root walls ~3–5 m tall = 24–40 voxels
- [x] Forest floor corridor width: path between trunk-root systems — ~3–5 m = 24–40 voxels
- [x] Light level: permanent green twilight even at noon — ambient light from WorldEnvironment, green-filtered, low energy; no direct sun on the floor
- [x] Silverwood grove area: pale silver patches visible from above — GAP for exact area; suggest ~50 m diameter per grove = 400 voxels
- [x] Eight Glades: circular light-openings in the canopy — circular clearings, suggest ~20–40 m diameter = 160–320 voxels each
- [x] Camera arm length — Greatwood canopy walk: arm 14, elevation 38°, optional horizontal rotation (per design/CAMERA_AND_PERSPECTIVE.md)

The sound-travels-differently note is an audio design cue, not a geometry concern. The geometry implication: the forest floor is enclosed by massive trunks and root walls enough to create natural reverb chambers.

---

## Art Direction Notes

Three distinct visual zones within the Greatwood:
1. **Forest edge (approach):** trees growing in scale as the player moves north; light levels dropping; normal woodland transitioning to something older
2. **Deep Greatwood (approach to Lirien-Thal):** ancient trunks, root walls, green twilight. The Greatwood feels alive in a way that should be subtly uncomfortable. The animals are quieter. Something attentive.
3. **Silverwood grove:** pale silver-grey bark and silver leaves; faint bioluminescence at night. A different color register entirely — cooler, brighter, almost lunar.

The Eight Glades: circular openings in the canopy where full sky light reaches the floor. These are sacred to the Aelorin. Entering one is not an act of trespass — but it is an act of notice.

Faces in the bark (near Lirien-Thal): visible on close approach to the ancestor-trees. A subtle detail the player discovers, not a tutorial prompt.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT2.md`
**Status:** Sketched. The Greatwood approach is Scene 2 in the Aelorin arc (between Sirathiel entry and Lirien-Thal canopy).

The Greatwood is a traversal region — the player moves through it rather than spending significant time here. The visual transformation as the player goes deeper is the narrative content of the traversal scene.

---

## Connections

- **Arrives from:** Sirathiel-by-the-Sea (Act II entry point for the Aelorin arc)
- **Exits to:** Lirien-Thal canopy (ascending from the forest floor)

---

## Open Questions / Gaps

- Traversal mechanics in the Greatwood: is this a linear corridor between Sirathiel and Lirien-Thal, or an open area with sub-locations?
- The Eight Glades: are any visited in Game One, or are they background lore for Games Two and Three?
- Edgewood (the northern edge before tundra): not visited in any game identified — purely map notation
- Goblin or wildlife encounters: the forest is old growth and the animals are quieter; does this mean no combat in the Greatwood, or specifically no goblin presence here?
- Dagna cannot accompany Roland into the Greatwood — does the Greatwood itself have a detection/reaction to dwarves, or is this purely Aelthurion's political preference?
