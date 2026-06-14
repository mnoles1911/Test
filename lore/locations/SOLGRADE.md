# Solgrade

**Type:** City (city-state)
**Kingdom/People:** Solgrade — independent city-state, council-governed
**Position:** Southern Central Plains, flat farmland
**Story relevance:** Game One, Act II (Gold Coin arc; most complex Act II negotiation)

---

## Physical Description

No walls. This is deliberate and political — Solgrade's founding Council declared that walls signal fear, and Solgrade does not fear. The city sprawls across flat southern farmland, its boundaries defined by habit and property rather than stone. Terracotta roofs throughout, a warm orange-red from the local clay. The color is distinctive from a distance; travelers know they are approaching Solgrade when the roofline turns red.

Key landmarks:
- **Council Hall**: Twelve equal entrances, one per founding guild. No entrance is grander than another. The interior is a single open chamber with a circular floor plan.
- **The Grand Canal**: Solgrade's main street. A canal network running through the city center with flat-bottomed trade barges and passenger gondolas moving between quays. Canal-side buildings have stepped stone embankments at water level and private dock access at their rear. The water reflects the warm terracotta architecture. Canal-side market stalls use striped awnings in warmer tones than Aldenholt — more yellow and red, fewer blues.
- **Banking Quarter**: The financial center of Mira. Three major banking houses, a dozen smaller ones, and the Smiths' Confederation's trade office.
- **Surgeons' School and Apothecaries' College**: Adjoining buildings in the eastern district. The smell of herbs and alcohol. Students in grey coats are a common sight on Solgrade's streets.
- **Golden Lance Hall**: The cavalry order's Solgrade chapter maintains a training yard and stables in the southern district.

Map note: Open city symbol (towers, no enclosing wall).

---

## 3D Scale Reference
> At 10 voxels per meter (project standard: 1 voxel = 0.1 m)

Key dimensions:

- [x] Street width: open city, no walls, streets organically wider — ~8–12 m = 80–120 voxels
- [x] Council Hall: 12 equal entrances, circular interior — ~40 m diameter = 400 voxels; each of the 12 entrances ~3 m wide = 30 voxels; interior height ~8–10 m = 80–100 voxels
- [x] Council Hall entrance archway: 3 m wide × 4 m tall = 30 × 40 voxels (each of 12, equally proportioned)
- [x] Terracotta roof pitch: low pitch for flat farmland climate — ~15–20° slope, approximate
- [x] Banking Quarter building height: urban commercial, 3–4 stories — ~10–14 m = 100–140 voxels
- [x] Surgeons' School: institutional, 2–3 stories, adjoining Apothecaries' College — GAP for exact dimensions
- [ ] Korvath counting house: infiltration scene — needs design session for layout and guard placement
- [x] Camera arm length: outdoor Solgrade = arm 14–16, elevation 42°, optional horizontal rotation (brightest outdoor scenes in the game; open, no walls)

No walls means no wall height to define — the city edge is soft. This is unique in the world.

---

## Art Direction Notes

The brightest scenes in the game. Daylight, no CanvasModulate darkness (3D equivalent: generous WorldEnvironment ambient, direct sunlight). Crisp shadows from terracotta-roofed buildings. Warm orange-red roofline from local clay — distinctive color identity, visible on approach across flat farmland.

The Council Hall's twelve equal entrances is the defining architectural statement of Solgrade's politics. The symmetry is the point. No hierarchy in stone. Circular interior with no head of the table.

Contrasting visual identity to every other Act II location:
- Vosskar: grey iron, low ceilings, underground council
- Caer Brannoch: salt-wet wood, dramatic cliffs
- Aelorin Greatwood: living wood, silver-green light
- Solgrade: open sky, warm terracotta, flat ground, wide streets

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT2.md`
**Status:** Sketched. 4–5 scenes identified.

Scenes:
1. City arrival — open streets, terracotta roofline
2. Golden Lance Hall — Vossant contact (one faction in the double-leverage negotiation)
3. Korvath counting house — infiltration; Roland finds both the smuggling evidence and the gold coin
4. Korvath negotiation — sophisticated leverage exchange; neither side is purely right
5. (Optional) Council hearing — Vossant verdict; two Houses censured, House Pelarin expelled

Key design note: the counting house infiltration is a stealth/navigation scene — not combat, but timed or guarded access. Roland uses a purchased identity.

---

## Connections

- **Arrives from:** Act II open world (recommended last of the four kingdoms — Roland's journal notes the reason)
- **Exits to:** Act II complete (all four pieces acquired), Act III begins

---

## Open Questions / Gaps

- Korvath counting house layout: infiltration scene geometry not designed (guards, entry points, object placement for the two finds)
- Council Hall seating/floor plan during the optional hearing: GAP
- The city has no defined edge — where the playable scene "ends" needs a soft boundary decision (terrain edge? loading zone at a road junction?)
- Surgeons' School not visited in Game One but visible as an ambient landmark — level of detail needed TBD
- Copper Isles students and occasional Aelorin lecturers mentioned in lore: ambient NPC flavor, not a mechanic
