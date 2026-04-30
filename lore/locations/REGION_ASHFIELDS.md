# The Ashfields

**Type:** Region (ash wastes)
**Kingdom/People:** Vosskaran frontier (western edge); goblin territory (interior); Ash Throne influence (eastern depths)
**Position:** Eastern Mira — from the Spine's eastern cliff face to the Shroud Shore
**Story relevance:** Game One, Act IV — the Ashfields approach to Drûn-Khazad crossing; also visible from Vosskar-on-the-Iron (Act II)

---

## Physical Description

From above: a gradual color change from brown-gold farmland to flat grey ash-soil. The transition takes about fifty miles — you notice the soil lightening, then the vegetation thinning, then the first patches of bare grey ground appearing, then the ash-haze.

Basalt outcroppings break the flat monotony — old lava beds from the First Age when Drûn-Khazad's influence reached this far west. They protrude from the ash-soil as dark irregular shapes, too hard to farm around, too isolated to shelter behind.

Vosskaran garrison towns are the last built structures before the landscape empties. Beyond them: grey ground, wind, the smell of ash, and goblin territory.

Map texture: light grey stippling increasing in density toward the east. Occasional dark blotches for basalt outcroppings. Dotted lines for the garrison road. No trees.

---

## 3D Scale Reference
> At 8 voxels per meter (project standard: 1 voxel = 0.125 m)

Key dimensions:

- [x] Ash-soil depth (surface detail): ~0.1–0.3 m = 1–2 voxels of ash overlay on the terrain
- [x] Basalt outcropping height: old lava beds, irregular — ~2–5 m tall = 16–40 voxels; ~5–15 m wide = 40–120 voxels
- [x] Ash-haze density: increases toward the east — particle effect in WorldEnvironment, grey, density increasing; no clear line of sight beyond ~200 m in the deep Ashfields
- [x] Vosskaran garrison town scale: small fortress-style settlements — ~80 m × 60 m = 640 × 480 voxels approximate footprint; garrison walls ~4–5 m tall = 32–40 voxels
- [x] Garrison road (Frontier Road): dotted line on maps — maintained gravel/stone surface, ~4 m wide = 32 voxels
- [ ] Goblin territory markers: how far into the Ashfields before goblin presence begins — GAP
- [x] Camera arm length — Ashfields open: arm 16, elevation 42°, optional horizontal rotation (per design/CAMERA_AND_PERSPECTIVE.md — maximum open-space camera settings)

The flat featureless terrain is a design challenge: the basalt outcroppings are the only cover in an otherwise exposed landscape. Combat design in the Ashfields should account for this — the player has no natural defensive position except the outcroppings.

---

## Art Direction Notes

The color progression in the Ashfields tells the story of the terrain: brown-gold farmland → grey-brown → flat grey → grey-white ash. Each zone is distinct but the transition is gradual.

Three key visual elements:
1. **Ash-haze:** permanent grey atmospheric fog building toward the east. WorldEnvironment fog density increases as the player moves east. At maximum depth in the Ashfields, visibility is dramatically reduced.
2. **Basalt outcroppings:** dark irregular shapes against the grey ground — volcanic rock from the First Age. These are the only visual landmarks in an otherwise featureless landscape.
3. **No trees:** the absolute absence of vegetation (except sparse scrub near the western edge) is itself a visual statement. After the Greatwood and the Spine's pine forests, the emptiness is stark.

The ash smell: ambient audio design — a dry, mineral, slightly sulphurous ambient sound bed should distinguish the Ashfields from any other outdoor environment.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT4.md`
**Status:** Sketched. Act IV begins with the Ashfields approach to the Shroud Sea crossing.

In Game One: the Ashfields are traversed in Act IV on the way to Thal. The playable portion is probably the approach road through the Vosskaran garrison zone and then the open Ashfields toward the Shroud Shore.

Also referenced in Act II (Vosskar): the ash-haze is visible from Vosskar's eastern wall as a particle effect — this is background/visual dressing during the Vosskar scenes, not a separate playable zone.

---

## Connections

- **Arrives from:** Vosskaran frontier (from Vosskar-on-the-Iron, east via the Frontier Road)
- **Contains:** Vosskaran garrison towns (multiple, unnamed in lore), basalt outcroppings (cover points), the Greyflow delta area (Shroud Shore approach)
- **Exits to:** Shroud Shore → Shroud Sea crossing → Thal (see REGION_SHROUD_SEA.md)

---

## Open Questions / Gaps

- Act IV approach: is the playable Ashfields zone entirely linear (road east), or does the player have freedom to explore the basalt outcroppings?
- Goblin encounters: the lore notes goblin raids on Vosskaran farmsteads are "common" — does the player encounter goblins in the Ashfields in Act IV, or is goblin presence implied but not confronted?
- The Sorrowmarsh to the south: does Roland pass near it or through it? Not defined for Act IV.
- Binding Site (BINDING_SITE.md): the lore mentions an Act IV ritual location in the Ashfields — is this before or after the Shroud Sea crossing? This needs clarification (see BINDING_SITE.md).
- The Brotherhood observation station at the Shroud Shore (staffed by volunteers, six-month rotations): is this a playable scene or background lore?
