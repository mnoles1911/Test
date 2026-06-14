# Aldenholt

**Type:** City
**Kingdom/People:** Eldermark
**Position:** Central Plains, at the confluence of the Aldwater and Silverthread rivers
**Story relevance:** Game One, Act I (primary setting); mentioned throughout Games Two and Three

---

## Physical Description

The largest city on Mira. Walls three men thick, built from grey quarried stone, maintained continuously for four centuries. The city spreads across both banks of the Aldwater where the Silverthread feeds in from the north — the old city occupies the southern bank, the newer merchant districts the northern. The market district never fully closes; stalls open before dawn and the last traders pack at midnight, if then.

Population approximately 80,000.

Key landmarks:
- **King Othric's Longhall Keep**: The royal seat. A fortified great hall complex — stone gatehouse and towers with a half-timbered great hall built inside the curtain wall. Royal banners of Eldermark (iron-grey field, white boar) fly from the keep towers and gate arch year-round. The longhall interior is large, dark-timbered, firepit-lit.
- **Scholar's Block**: A dense quarter of connected buildings housing the Conclave's Eldermark chapter, several independent scribes' halls, and the map-sellers. The Loremaster's Archive occupies an entire city block here — windowless lower floors, reading rooms above, a smell of old vellum that reaches the street.
- **Iron Chalice Chapel**: Inside the city walls, a stone chapel maintained by the Iron Chalice order. Houses a fragment of the Sundered Crown pommel behind the altar — the only piece known to be in human hands.
- **Temple of Aldrath & Aeadis**: A dual-shrine temple housing both gods in a single stone building. Over the main entrance: a war hammer and a wheat sheaf carved in relief. Interior: Aldrath's shrine on one side (forge-warm amber light), Aeadis's shrine on the other (cool daylight from a high window). The two light sources are separated by the central aisle — visually distinct, deliberately so.
- **River Confluence Docks**: Working docks at the point where the Aldwater and Silverthread rivers meet. Barge traffic arrives daily from the Spine and the coast. Voxel quays of heavy stone, barge moorings, wooden crane jibs for cargo. Dock warehouses have loading doors at upper-floor level for crane access.

Map note: Walled city symbol with multiple towers. Two river lines converging at the city.

---

## 3D Scale Reference
> At 10 voxels per meter (project standard: 1 voxel = 0.1 m)

Key dimensions (derived from lore and standard urban scale):

- [ ] Approximate footprint: large walled city — GAP (needs map-level definition, but walls are a 4-century structure, 3-men-thick = ~2 m = 20 voxels thick)
- [x] Street width — Scholar's Block street (hub scene): ~8 m wide = 80 voxels
- [x] Alley width — Night Chase alleys: ~2–3 m wide = 20–30 voxels
- [x] Standard door/archway height: 2.2 m = 22 voxels
- [x] City wall height: city wall this substantial — ~8–10 m = 80–100 voxels
- [x] King's Hall tower height: GAP — but three towers implies significant vertical scale, suggest 20–30 m = 200–300 voxels
- [x] Camera arm length — Aldenholt streets: arm 12, elevation 48°, no horizontal rotation (per design/CAMERA_AND_PERSPECTIVE.md)

Playable area scope: Act I uses five distinct scenes within the city — Night Chase alleys, Scholar's Block street hub, Archive interior (two versions), Iron Chalice Chapel. Full city is background/ambient, not fully traversable in Act I.

---

## Art Direction Notes

Half-timbered upper stories over stone ground floors — Eldermark's defining architectural style. The city shows its age in patched mortar, worn cobbles, iron hinges dark with rust. Grey quarried stone walls. Warm torch sconces in narrow alleys on iron brackets every ~6m. The Scholar's Block is lamplit and institutional. Night Chase scene uses the most oppressive lighting of Act I — very dark ambient (`#1A1F3A` equivalent in 3D WorldEnvironment), guttering torches. The market district even at night has more ambient activity than the chapel quarter.

Market stall awnings: striped canvas in fully saturated colors — red, green, blue, yellow — against the neutral grey-stone backdrop. This color pop is intentional; the market is the city's life.

Two rivers give the city a navigational logic — crossing the Aldwater means going north to the merchant districts; staying south is the old city. The River Confluence Docks sit at the junction point.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT1.md`
**Status:** Fully detailed — five scenes with per-scene room dimensions, flag lists, lighting notes, and NPC placement.

Scenes:
1. Night Chase (Aldenholt Alleys) — linear, no return
2. Aldenholt Hub (Scholar's Block street) — re-entrant hub connecting all Act I locations
3. Archive / Henrietta's Quarters — short, post-Night Chase
4. Iron Chalice Chapel — gated behind `calla_meeting_arranged = true`
5. Archive Interior / Restricted Section — gated behind `henrietta_dead = true`

---

## Connections

- **Arrives from:** Game opening (Night Chase is the first scene)
- **Exits to:** Act II begins when Roland leaves Aldenholt with Piece One (Iron Chalice pommel fragment)

---

## Open Questions / Gaps

- Full city footprint in voxels not defined — only the five Act I scenes need to be built for Game One
- King's Hall is background lore; no visit in Game One (the succession crisis with Aedric Castrove plays out in Solgrade and ambient dialogue)
- Docks visible/referenced but not a playable scene in Act I
- Market district referenced but not playable in Act I
