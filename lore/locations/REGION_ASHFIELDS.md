# The Ashfields

**Type:** Region (ash wastes)
**Kingdom/People:** Vosskaran frontier (western edge); goblin territory (interior); outlaw camps (throughout)
**Position:** Eastern Mira — from the Spine's eastern cliff face to the Shroud Shore
**Story relevance:** Game One, Act IV — the Ashfields are the scene of the Ashlord's counterstroke and the fighting retreat that ends the game; also visible from Vosskar-on-the-Iron (Act II)

---

## Physical Description

The Ashfields were once productive rolling hills and light forest — farmland and wilderness that supported life. They died over centuries as ash from Drûn-Khazad drifted west across the Shroud Sea on prevailing winds, growing denser year by year as Mordvar's power stirs. The dead zone creeps westward still.

From above: a gradual color change from brown-gold farmland to flat grey-brown dead soil. The transition takes about fifty miles — you notice the soil lightening, then the vegetation thinning, then ghost stumps of ancient trees appearing, then crumbled stone walls of long-abandoned farmsteads, then the ash-haze thickening as you move east.

The ghost stumps and crumbled farmstead walls are the most evocative features of the Ashfields: evidence of the world that was here before the ash came. Dry creek beds trace the old drainage patterns. A land that clearly once lived, clearly dead now.

Vosskaran garrison towns are the last built structures before the landscape empties. Beyond them: grey-brown ground, wind, the smell of ash, goblin territory, and the occasional outlaw camp of those who fled justice in Vosskara or Eldermark and find the lawless wastes useful.

The northeastern Ashfields transition into the Weeping Wood — dead soil giving way to dead forest, the goblin territory eventually yielding to something more dangerous.

Map texture: light grey-brown stippling increasing in density toward the east. Ghost stump symbols scattered through the middle zone. Dotted lines for the garrison road. Occasional crumbled wall symbols in the dead farmland zone. No living trees.

---

## 3D Scale Reference
> At 8 voxels per meter (project standard: 1 voxel = 0.125 m)

Key dimensions:

- [x] Ash-soil depth (surface detail): ~0.1–0.3 m = 1–2 voxels of ash overlay on the terrain
- [x] Ghost stump height: remnants of felled or dead trees — ~0.5–2 m tall = 4–16 voxels; ~1–3 m wide = 8–24 voxels; weathered, grey-brown, no bark remaining
- [x] Crumbled farmstead wall height: collapsed stone walls — ~0.5–1.5 m remaining = 4–12 voxels; provide partial cover in the Ashfields fighting retreat
- [x] Ash-haze density: increases toward the east — particle effect in WorldEnvironment, grey, density increasing; no clear line of sight beyond ~200 m in the deep Ashfields
- [x] Vosskaran garrison town scale: small fortress-style settlements — ~80 m × 60 m = 640 × 480 voxels approximate footprint; garrison walls ~4–5 m tall = 32–40 voxels
- [x] Garrison road (Frontier Road): dotted line on maps — maintained gravel/stone surface, ~4 m wide = 32 voxels
- [ ] Goblin territory markers: how far into the Ashfields before goblin presence begins — GAP
- [x] Camera arm length — Ashfields open: arm 16, elevation 42°, optional horizontal rotation (per design/CAMERA_AND_PERSPECTIVE.md — maximum open-space camera settings)

The ghost stumps and crumbled farmstead walls are the only cover in an otherwise exposed landscape. Combat design in the Ashfields — particularly the Act IV fighting retreat — should account for this. The player has limited natural defensive positions; the ruins of the former civilization provide them.

---

## Art Direction Notes

The color progression in the Ashfields tells the story of the terrain: brown-gold farmland → grey-brown → flat grey → grey-white ash. Each zone is distinct but the transition is gradual.

Four key visual elements:
1. **Ash-haze:** permanent grey atmospheric fog building toward the east. WorldEnvironment fog density increases as the player moves east. At maximum depth in the Ashfields, visibility is dramatically reduced.
2. **Ghost stumps:** grey weathered remnants of ancient trees — the most human-scale evidence of what was lost. Clustered unevenly, not in rows; these were wild trees and woodland, not an orchard.
3. **Crumbled farmstead walls:** low stone ruins scattered through the middle Ashfields zone — foundations, partial walls, collapsed archways. The scale is domestic. These were homes.
4. **No trees:** the absolute absence of living vegetation (except sparse scrub near the western edge) is itself a visual statement. After the Greatwood and the Spine's pine forests, the emptiness is stark.

The ash smell: ambient audio design — a dry, mineral, faintly acrid ambient sound bed should distinguish the Ashfields from any other outdoor environment.

The northeast approach toward the Weeping Wood: as the player moves north-northeast, the dead soil transitions to dead forest. The Weeping Wood's fixed cloud cover becomes visible on the horizon as a darker grey mass that does not move.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT4.md`
**Status:** Sketched. Act IV takes place entirely in the Ashfields.

In Game One: the Ashfields are the primary Act IV environment. After Roland secures the Obsidian Shard from the Naergrim at Mor-Vethrin, his party exits the Weeping Wood into the Ashfields. The Ashlord, who has been tracking the operation and knows Roland now holds all seven Crown pieces, launches a coordinated counterstroke here himself — coming out of the Ash Tower for the first time in decades. Roland's party fights a brutal westward retreat. The Ashlord is gravely injured and retreats east. Vaeroth Caine, commanding the Hand's conventional forces, is killed or captured in the same engagement.

Also referenced in Act II (Vosskar): the ash-haze is visible from Vosskar's eastern wall as a particle effect — this is background/visual dressing during the Vosskar scenes, not a separate playable zone.

---

## Connections

- **Arrives from:** Vosskaran frontier (from Vosskar-on-the-Iron, east via the Frontier Road)
- **Contains:** Vosskaran garrison towns (multiple, unnamed in lore), ghost stumps and farmstead ruins (cover points), the Greyflow delta area (Shroud Shore approach)
- **Exits to (northeast):** Weeping Wood → Mor-Vethrin (Act IV approach to the Naergrim city)
- **Exits to (east):** Shroud Shore (see REGION_SHROUD_SEA.md — not visited in Game One)

---

## Open Questions / Gaps

- Act IV approach: is the playable Ashfields zone entirely linear (road east), or does the player have freedom to explore the ruins?
- Goblin encounters: the lore notes goblin raids on Vosskaran farmsteads are "common" — does the player encounter goblins in the Ashfields in Act IV, or is goblin presence implied but not confronted?
- The Sorrowmarsh to the south: does Roland pass near it or through it? Not defined for Act IV.
- Outlaw camps: are any named outlaws encountered in Act IV, or are they background population?
