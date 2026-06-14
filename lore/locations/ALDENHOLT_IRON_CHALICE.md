# Iron Chalice Chapel, Aldenholt

**Type:** Notable Sub-Location (within Aldenholt)
**Kingdom/People:** Iron Chalice order (within Eldermark)
**Position:** Scholar's Block adjacent, Aldenholt — inside the city walls, accessible via a chapel side street from the Hub
**Story relevance:** Game One, Act I — Scene 4; Piece One of the Sundered Crown acquired here; Roland's complicated relationship with the Order is embodied in this space

---

## Physical Description

A stone chapel maintained by the Iron Chalice order. Inside the city walls. Houses a fragment of the Sundered Crown pommel behind the altar — the only piece known to be in human hands.

Scene 4 layout:
- **Chapel anteroom**: Small waiting room. Dame Calla receives Roland here and makes the arrangement (40 minutes, light off, chapel empty).
- **Chapel nave**: Dark — the only light source is a single candle on the altar. Pews on both sides. Stone floor. Iron Chalice iconography on the walls. The architecture should feel familiar to Roland — he worshipped here.
- **Altar area**: One step up from the nave. The altar itself, stone, with the iron pommel on a fitted mount. Candle to one side. This is where Roland takes the pommel and leaves an iron rod of identical weight in its place.

Dame Calla waits in the anteroom during Roland's 40 minutes alone in the chapel.

---

## 3D Scale Reference
> At 10 voxels per meter (project standard: 1 voxel = 0.1 m)

Key dimensions (derived from LEVEL_LAYOUTS_ACT1.md — fully detailed):

- [x] Chapel scale: "modest" per scale reference — ~8 m wide × 12 m long × 8 m tall = 80 × 120 × 80 voxels
- [x] Anteroom: small waiting room — ~4 m × 5 m × 3.5 m = 40 × 50 × 35 voxels
- [x] Nave pew spacing: rows of pews both sides, stone floor — pew rows every ~1.5 m = 15 voxels; central aisle ~2.5 m = 25 voxels
- [x] Altar step height: one step up — ~0.25 m = 2–3 voxels (subtle, but Roland should be visibly one step higher at the altar)
- [x] Altar dimensions: stone, pommel on a fitted mount — ~1.5 m wide × 0.8 m deep × 1.0 m tall = 15 × 8 × 10 voxels
- [x] Pommel mount: fitted receptacle in the altar — the replacement rod must match exactly; this is a geometry note for the altar prop
- [x] Camera arm length — Iron Chalice chapel: arm 9, elevation 52°, no horizontal rotation (per design/CAMERA_AND_PERSPECTIVE.md)

---

## Art Direction Notes

The chapel is the darkest playable scene in Act I. From the design file:
- **Anteroom:** lamplight, functional. Calla's space is composed.
- **Chapel nave:** very dark. Single altar candle only. "The player navigates by feel." `CanvasModulate` equivalent in 3D: WorldEnvironment ambient near-zero; only the OmniLight3D altar candle provides light. This is the darkest scene in the game so far.
- **Altar:** the candle casts a small warm circle. The pommel is visible in it.

Iron Chalice iconography on the walls: the order's symbol (a chalice, presumably iron-rendered — MagicaVoxel wall hangings or bas-relief geometry). These are familiar to Roland and should read as recognition, not discovery.

The space should feel like a building Roland knows. The architecture is institutional religious — stone, modest, functional. Not grand. The Iron Chalice is a martial order; their chapel is a weapon maintenance room that also has pews.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT1.md` — Scene 4
**Status:** Fully detailed.

Flags:
- **Required to enter:** `calla_meeting_arranged = true`
- **Set on completion:** `pommel_piece_1_acquired = true`, `calla_knows_roland_took_pommel = true`
- **Unlocks:** Act II (Roland leaves Aldenholt)

Key design note: "The 40-minute constraint is narrative only (no real-time clock). The scene ends when the player takes the pommel."

---

## Connections

- **Arrives from:** Aldenholt Hub (via chapel side street — only visible/accessible after `calla_meeting_arranged = true`)
- **Exits to:** Aldenholt Hub (Roland returns to report to Calla, then the side street)

---

## Open Questions / Gaps

- Where exactly is Dame Calla's position in the anteroom? Seated at a table? Standing?
- The locked iron door to the chapter records room: is this ever relevant to a side quest, or permanently locked background detail?
- Iron Chalice iconography: the specific visual design of the order's symbol is not defined — needs art direction input before building the chapel walls
- Is the chapel accessible after Act I ends? Roland leaves Aldenholt; does he ever return to the chapel in a later act?
- The iron rod Roland uses as a swap: this is pre-planned (he brings it specifically). Does the player see it in the inventory before this scene, or is it handled as a narrative-only swap?
