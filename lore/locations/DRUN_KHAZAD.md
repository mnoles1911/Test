# Drûn-Khazad

**Type:** Notable Site (shield volcano; Mordvar's throne)
**Kingdom/People:** Ash Throne (Mordvar)
**Position:** Center of Thal, slightly south of the continent's midpoint
**Story relevance:** Game Three — final area; the Battle of Drûn-Khazad; Mordvar's defeat. Not visited in Game One. (Game One ends in the Ashfields on Mira.)

---

## Physical Description

A shield volcano — broad, low-profile compared to a cone, with a wide flat summit. The caldera is visible from the western approach as a dark depression. The Ash Hearth sits within it: a natural chamber in the caldera's inner wall where Mordvar's Aescstól stands — a throne formed from cooled lava and bone-meal, inlaid with obsidian and silver.

The ash cloud above Drûn-Khazad is permanent, extending west-northwest on prevailing winds. The glow of the caldera is visible at night from Thal's western coast.

On the night of the final battle (Game Three, Day 3): Mordvar descends the slope walking in silence, presence felt as a cold of will rather than temperature. The ash cloud does not change. The volcano does not react. He simply walks down.

Map note: Shield-volcano symbol with broad profile, caldera glow, ash-cloud extending west.

---

## 3D Scale Reference
> At 8 voxels per meter (project standard: 1 voxel = 0.125 m)

Key dimensions:

- [x] Shield volcano profile: broad, low — shield volcanoes are typically 5–10× wider than they are tall; if summit is ~500 m elevation, footprint is ~3–5 km across = enormous; playable area is only the upper slopes and caldera
- [x] Caldera width: GAP — shield volcano calderas vary; suggest ~300–800 m across = 2400–6400 voxels (not all traversable; the playable caldera rim and Ash Hearth are a fraction of this)
- [x] Ash Hearth chamber: natural chamber in caldera inner wall — ~30 m wide × 20 m deep × 15 m tall = 240 × 160 × 120 voxels (estimate; final boss arena scale)
- [x] Aescstól throne dimensions: formed from cooled lava and bone-meal, inlaid with obsidian and silver — ~2.5 m tall × 1.5 m wide = 20 × 12 voxels (the throne itself; the platform it sits on is larger)
- [x] Upper slope playable width: the approach path on the final slope — ~30–50 m traversable width = 240–400 voxels (narrow enough to feel exposed, wide enough for combat)
- [x] Nothing grows on upper two-thirds: vegetation cutoff line visible as the player ascends — below the line: sparse ash-adapted scrub; above: bare rock and ash
- [x] Camera arm length: upper slopes = arm 14–16, elevation 42° (open, exposed, wide view); Ash Hearth = arm 10–12, elevation 50°; caldera floor = GAP

Ash cloud: permanent particle effect, grey-white, extends west-northwest. At night: caldera glow visible below the cloud — OmniLight3D from within the caldera, deep orange-red, energy high.

---

## Art Direction Notes

Two visual registers:
1. **Approach and upper slopes:** exposed, wide, open sky above (obscured by ash cloud). Grey-black rock. No cover. The volcano does not hide; it does not need to.
2. **Ash Hearth and caldera:** enclosed, deep orange-red from the caldera glow, the Aescstól at the center. Where the slope was vast and exposed, this is tight and hot.

Mordvar's descent: he walks. This is not a dramatic volcanic event. The ash cloud does not react. The volcano does not react. The cold of will is felt, not seen. This is a tonal instruction for the final confrontation — the horror is understatement, not spectacle.

The Aescstól throne: cooled lava and bone-meal, inlaid with obsidian and silver. Dark, heavy, permanent. Not a beautiful object.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT4.md`
**Status:** Sketched. Act IV scenes include the Ashfields approach, the Binding Site ritual, and the Fighting Retreat.

The final confrontation at Drûn-Khazad is the climax of Game Three. Scene structure:
1. Western slope ascent (the approach from the Ash-Steppe)
2. Upper slope combat (the battle; faction commitments determine who fights alongside Roland)
3. Ash Hearth (the final confrontation with Mordvar; Aldric Vane wields the Aeluvain)

---

## Connections

- **Arrives from:** Thal western shore (fleet landfall), then the Ash-Steppe march east
- **Exits to:** Game Three ending (The Return, The Hold, or The Fracture — all resolve at or from this location)

---

## Open Questions / Gaps

- The Battle of Drûn-Khazad: how many enemy waves? What types of Ashfallen? The faction commitments (Vosskara, Tidewarden, Golden Lance, Naergrim dissidents) affect who fights — combat design question
- The Ash Hearth confrontation with Mordvar: the final boss encounter design is not yet written
- All three endings (The Return / The Hold / The Fracture) — see GAME1_PART2.md; spatial implications for the ending cinematics not yet mapped to geometry
- Caldera access: does the player descend into the caldera or approach the Ash Hearth from the rim level?

**Canonical naming note:** Drûn-Khazad is the volcano in Thal. The Vault of Aen-Vael is below Khorumzad in the Spine of Mira — NOT below Drûn-Khazad.
