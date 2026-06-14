# The Spine of the World

**Type:** Region (mountain range)
**Kingdom/People:** Dwarven holds (Karaz-Dûn, Khorumzad, Kazaad-Brak) — no single ruler above
**Position:** Eastern third of Mira, running vertically north to south
**Story relevance:** Game One, Act III — the three dwarven hold arcs; Underway traversal; the Spine separates human kingdoms from the Ashfields

---

## Physical Description

From the west the Spine presents as a wall of blue-grey mountains with three distinctive peaks marking the dwarven holds:
- **Kara-Thûn** (above Karaz-Dûn): the tallest, permanently snow-crowned, visible from the Central Plains on clear days
- **Khorumzad's Crown**: a broad flat-topped massif with a distinctive silhouette, the hold carved into its central mass
- **The Broken Fang** (above Kazaad-Brak): twin peaks split by an ancient fault, lightning magnet in storm season

The western face has gentler foothills — pine forest transitioning to farmland. The eastern face drops sharply into the Ashfields as sheer cliff-faces of grey-black volcanic rock.

Glaciers are visible at the highest elevations in the northern Spine. Snow is permanent above a certain altitude. The mountain color shifts from grey-green in the foothills to grey-blue in the mid-ranges to white-black at the peaks.

Map texture: classic Tolkien-style row-of-peaks illustration, denser and more dramatic in the north, the three named peaks taller than their neighbors.

---

## 3D Scale Reference
> At 10 voxels per meter (project standard: 1 voxel = 0.1 m)

Key dimensions:

- [x] Kara-Thûn height: permanently snow-crowned, visible from the Central Plains on clear days — must be significant; estimate ~2000–3000 m = 20000–30000 voxels total elevation (background geometry only; player does not summit)
- [x] Khorumzad's Crown: broad, flat-topped — distinctive silhouette from below; the flat summit is a navigation landmark
- [x] The Broken Fang: twin peaks with an ancient fault split — the split between the peaks should be visible from below
- [x] Western foothills: pine forest to farmland transition — gradual terrain change over ~20–30 km; the playable portion is only the approach to each hold
- [x] Eastern cliff face: sheer drop into Ashfields — cliff height at approach to Ashfields ~30–80 m = 300–800 voxels (varies by location)
- [x] Underway entrance near Khorumzad (King's Road endpoint): the main overland route terminates here — approach road ~4 m wide = 40 voxels; Underway gate ~4 m × 4 m = 40 × 40 voxels
- [x] Snow line altitude: visual transition from grey-green to white-black — background art direction, not gameplay geometry

The Spine is background geography for most of Game One. The playable zones are the Underway interior and the hold interiors — not the mountain faces themselves.

---

## Art Direction Notes

The color progression is the key visual identity: grey-green foothills → grey-blue mid-range → white-black peaks. Three distinctive peak silhouettes serve as navigation landmarks visible from the Central Plains.

From the east (the Ashfields view): sheer volcanic grey-black cliff faces with no foothills. The Spine's eastern face is a wall, not a gradual ascent. This view is seen from Vosskar's eastern wall and from the Ashfields approach.

The Underway entrance near Khorumzad (King's Road endpoint): the point where the overland route goes underground. This is a transitional scene — above ground to below ground, sunlight to runelight, wind to still air.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT3.md`
**Status:** Sketched. The Spine is traversed via the Underway in Act III; the mountain exterior is background dressing.

The King's Road connects Aldenholt to the Spine western foothills and the Underway entrance near Khorumzad (from WORLD_GEOGRAPHY.md). This is the overland route Roland takes to begin Act III.

---

## Connections

- **Arrives from:** Central Plains (King's Road from Aldenholt)
- **Contains:** Karaz-Dûn, Khorumzad, Kazaad-Brak (each their own files)
- **Traversed via:** The Underway (see REGION_UNDERWAY.md)
- **Exits east to:** The Ashfields (see REGION_ASHFIELDS.md)

---

## Open Questions / Gaps

- Is there a playable exterior approach scene for any of the holds (mountain gate approach from the surface), or does all travel enter via the Underway?
- The Frontier Road along the Spine's eastern face (Vosskaran garrison road): does Roland ever travel this route, or is it background geography?
- The glaciers at northern elevations: are these visible in any playable scene, or purely map notation?
- Khorumzad's Crown flat-topped summit: is the summit ever a location (lookout point, Act II approach scene from above)?
