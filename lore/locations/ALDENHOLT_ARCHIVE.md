# Loremaster's Archive, Aldenholt

**Type:** Notable Sub-Location (within Aldenholt)
**Kingdom/People:** Eldermark / Independent institution
**Position:** Scholar's Block district, Aldenholt — occupies an entire city block
**Story relevance:** Game One, Act I — three of five Act I scenes are set here or involve it; the starting point of the entire investigation

---

## Physical Description

The Loremaster's Archive occupies an entire city block in the Scholar's Block district. Windowless lower floors, reading rooms above, a smell of old vellum that reaches the street. The largest single repository of written records in Eldermark.

Henrietta's personal quarters are in the Archive — above the reading rooms, accessible via a staircase from the main stacks. Her body is found here by Roland in Scene 3.

The restricted section is a smaller back room: only the oldest and most sensitive records. Low shelves, locked display cases (unrelated to Roland's quest). The genealogical record connecting Aldric Vane to Mordvar's bloodline is here.

---

## 3D Scale Reference
> At 10 voxels per meter (project standard: 1 voxel = 0.1 m)

Key dimensions (derived from LEVEL_LAYOUTS_ACT1.md — fully detailed):

- [x] Building footprint: a full city block — ~60 m × 40 m = 600 × 400 voxels (estimate for a dense urban city block)
- [x] Lower floors: windowless — solid stone exterior; no light from outside; ~6–8 m ground floor height = 60–80 voxels
- [x] Archive entrance hall: small foyer, one archivist desk — ~8 m × 10 m × 4 m = 80 × 100 × 40 voxels
- [x] Main stacks: rows of shelving, lamplight, vaulted stone ceiling — ~20 m × 30 m × 6 m = 200 × 300 × 60 voxels (estimate)
- [x] Side room (Tomlin's sorting room): small room off the main stacks — ~5 m × 6 m × 3 m = 50 × 60 × 30 voxels
- [x] Restricted section: smaller back room — ~6 m × 8 m × 3 m = 60 × 80 × 30 voxels (darker, mustier than main stacks)
- [x] Henrietta's study: single suite of rooms, accessible via staircase — ~8 m × 10 m × 3.5 m per room = 80 × 100 × 35 voxels (estimate)
- [x] Camera arm length — Archive interior: arm 8, elevation 55°, no horizontal rotation (tight ceiling per design/CAMERA_AND_PERSPECTIVE.md)

---

## Art Direction Notes

The Archive has distinct lighting zones that carry narrative weight:

- **Archive entrance (Scene 3/5):** institutional lamplight. Not warm. "This building is full of loss."
- **Main stacks:** lamplight, functional. Consistent between visits. The vaulted stone ceiling is the architectural character.
- **Henrietta's study:** one window, afternoon light (grey). The searched room is "bright enough to see everything clearly — this horror doesn't hide in shadow."
- **Restricted section:** darker, mustier. One lamp. Records not meant to be read often.

The windowless lower floors mean the building's exterior is a blank stone face at street level — the great oak doors at the entrance are the only architectural invitation. This is deliberate: the Archive doesn't advertise access.

Smell of old vellum reaching the street: an environmental detail worth an ambient audio note.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT1.md` — Scenes 3 and 5
**Status:** Fully detailed for both scenes (Henrietta's Quarters and the Restricted Section).

Scenes:
- **Scene 3 (Archive / Henrietta's Quarters):** Post-Night Chase. Roland finds the searched room and Henrietta dead. Environmental storytelling, no combat. Sets `henrietta_dead = true`.
- **Scene 5 (Archive Interior / Restricted Section):** After Tomlin is found and convinced. Roland discovers the genealogical record. Sets `tomlin_helped = true` and `aldric_vane_name_logged = true`.

Both scenes share the Archive Entrance Hall geometry; the staircase to Henrietta's study and the restricted section door are the branching points.

---

## Connections

- **Arrives from:** Aldenholt Hub (Scholar's Block street) — the Archive entrance door is on the Hub
- **Exits to:** Aldenholt Hub (return after both scenes complete)

---

## Open Questions / Gaps

- The Archive entrance has different archivists in Scene 3 vs Scene 5 — does the building geometry change, or only the NPC? Should be identical geometry, different NPC instance
- The noticeboard with Tomlin's suspension notice (Scene 5 hook): placement in the entrance hall — on the wall near the desk, or near the main stacks door?
- Locked display cases in the restricted section: are any of these relevant to side quests or ambient world-building? Currently noted as "unrelated to current quest"
- The Archive building exterior: visible from the Scholar's Block street (Hub scene), but only the door is interactive. How much of the facade is modeled vs implied?
