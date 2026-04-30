# The Underway

**Type:** Region (dwarven tunnel network)
**Kingdom/People:** Dwarven holds jointly (Karaz-Dûn holds the maintenance contracts)
**Position:** Beneath the Spine of the World, connecting all three holds
**Story relevance:** Game One, Act III — primary transit route between the dwarven holds; Dagna Irontrack joins the party here

---

## Physical Description

The Underway is the dwarven tunnel network beneath the Spine. Travel scene — the player moves through connected passages, each with a junction and a choice of direction. Dagna marks every junction she passes with chalk as habit.

Vaulted stone, regular spacing, waystation alcoves with supply caches. Low warm runelight — maintained, not dark. The Underway feels safe in a way the surface doesn't always.

The junction system: a small navigational choice at each junction. Wrong turns lead to dead ends with minor loot or environmental storytelling. Dagna's chalk marks persist (visual feedback that the player has been here).

From WORLD_GEOGRAPHY.md: shown on maps as dotted lines connecting Karaz-Dûn, Khorumzad, and Kazaad-Brak beneath the Spine. The only reliable transit through the mountains year-round.

---

## 3D Scale Reference
> At 8 voxels per meter (project standard: 1 voxel = 0.125 m)

Key dimensions (from scale reference guide):

- [x] Standard tunnel width: ~3 m wide × 3 m tall = 24 × 24 voxels (dwarven tunnel standard)
- [x] Waystation alcove: recessed chamber off the main tunnel — ~4 m wide × 3 m deep × 3 m tall = 32 × 24 × 24 voxels; supply cache storage and rest area
- [x] Junction chamber: wider space where tunnels intersect — ~6 m × 6 m × 4 m = 48 × 48 × 32 voxels (enough for a party to gather and consult)
- [x] Runelight spacing: regular warm illumination — runelight sources embedded in the ceiling at ~4 m intervals = 32 voxels
- [x] Dead-end branch length: navigational wrong turns — ~20–30 m = 160–240 voxels before the dead end (long enough to reward exploration but clearly finite)
- [x] Dagna's chalk marks: ~0.3 m diameter circles or directional arrows on the wall — sub-voxel scale detail; rendered as a texture or decal on the wall surface
- [x] Camera arm length: Underway tunnels — arm 10, elevation 50°, no horizontal rotation (standard enclosed 3D tunnel settings; similar to Khorumzad upper levels)

Three days of in-world travel through the Underway: the space needs to feel large enough to justify this, even if the playable representation compresses the actual distance.

---

## Art Direction Notes

The Underway is the one underground space in the game that is NOT oppressive. It is maintained. It is warm (runelight). It has supply caches. The Underway feels like infrastructure — a thing built by people who know what they're doing and have maintained it for centuries.

This is a deliberate contrast to the cave environments of Act I and the claustrophobia of Khorumzad's deep levels. The Underway is the mountain equivalent of a well-maintained road.

Runelight: warm amber glow from embedded light sources. Not flickering — steady. The reliability of the light is part of what makes the Underway feel safe.

Dagna's chalk marks: a visual system the player learns quickly. Junction → Dagna marks the correct path → chalk arrow visible on next visit. This is both a navigation aid and a character moment (her Dragon-Watcher training; systematic, habitual, precise).

Enemy encounters: Ashfallen soldiers are using the tunnels in Act III. The first multi-encounter combat sequence of the game. The Underway's tunnel geometry (choke points, waystation alcoves for cover) becomes tactically relevant in these encounters.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT3.md`
**Status:** Sketched. The Underway is the first two scenes of the Karaz-Dûn arc.

Scene structure:
1. Underway entry — overland transition goes underground at the Spine foothills
2. Underway tunnels — the junction system; Dagna joins at a waystation alcove three days in
3. Arrival at Kazaad-Brak (southern entrance) — see KAZAAD_BRAK.md

Dagna's joining scene: a waystation alcove, three days in. She is a Dragon-Watcher moving in the opposite direction (toward Kazaad-Brak for the same reason). The conversation where she commits: "Your volcanic problem and my volcanic problem are the same volcanic problem."

---

## Connections

- **Arrives from:** Spine western foothills — Underway entry near Khorumzad (King's Road terminus)
- **Internal nodes:** Khorumzad (central hub), Karaz-Dûn (northern terminus), Kazaad-Brak (southern terminus)
- **Exits to:** Surface exits near each hold; Kazaad-Brak is the first stop in Act III; Karaz-Dûn is the final destination

---

## Open Questions / Gaps

- Three days of travel compressed into how many scenes? The level design needs to decide how many junction-and-waystation segments represent three days
- Khorumzad: does Roland pass through the central hold during Underway traversal, or does the Underway route bypass the hold interior? This matters for Act III's scene count
- Ashfallen soldiers in the tunnels: how many encounter sequences? What types of Ashfallen? The junction system means some encounters could be avoidable (wrong turn = no combat; correct path = encounter)
- Dagna chalk marks as a persistent save state: do her marks need to be stored as flags in GameState.gd, or can they be built into the scene geometry as permanent fixtures?
- The Underway's source of air and the runelight's energy source: lore flavor, not designed yet
