# Lirien-Thal

**Type:** Aelorin Settlement (canopy city)
**Kingdom/People:** Aelorin
**Position:** Deep Greatwood, northern Mira
**Story relevance:** Game One, Act II (Silver Clasp arc; Aelthurion audience here)

---

## Physical Description

Not built — grown. The city occupies the silverwood canopy, its platforms and walkways formed from living wood shaped over centuries by Aelorin who completed the Aelthiren transition. The trees themselves are ancestors: elder Aelorin who chose the forest-path of transformation and whose consciousness persists in the wood. Walking on the platforms is walking on the body of someone's grandmother.

From below, the city is invisible — the canopy closes it. From within, it is open to sky through gaps in the canopy and filtered in perpetual silver-green light. No torches: the silverwood glows at night — a dramatic blue-white bioluminescence bright enough to cast shadows and illuminate the platforms clearly. It is the dominant light source after dark. It is not comforting. It is alien and beautiful.

Map note: Tree-and-star symbol. No walls.

---

## 3D Scale Reference
> At 8 voxels per meter (project standard: 1 voxel = 0.125 m)

Key dimensions:

- [x] Silverwood trunk diameter: trees described as wider than houses — ~4–8 m across = 32–64 voxels
- [x] Canopy height above ground: ancient trees of this scale — ~40–60 m = 320–480 voxels
- [x] Platform walkway width: two Aelorin walking side by side — ~2–3 m = 16–24 voxels
- [x] Platform structural thickness: shaped living wood — ~0.5 m = 4 voxels
- [x] Gap spacing between platforms: traversal distance — GAP, but must be jumpable or bridged; suggest no gap larger than 3 m = 24 voxels for gameplay
- [ ] Aelthurion's audience hall: the city's most significant interior — GAP (is it a platform? a carved interior space in a trunk? needs design decision)
- [x] Camera arm length — Greatwood canopy walk: arm 14, elevation 38°, optional horizontal rotation (per design/CAMERA_AND_PERSPECTIVE.md)

The bioluminescence at night is a lighting effect, not a geometry concern — use OmniLight3D nodes distributed through the tree trunks and platform edges, `color: Color(0.7, 0.85, 1.0)`, energy 1.5–2.0. This is the dominant light source at night, not an accent. The scene at night should read primarily in blue-white with deep forest shadow between lit areas.

The primary design challenge: vertical gameplay on platforms at 40+ meters elevation. Need to define how the player accesses the canopy level from the forest floor.

---

## Art Direction Notes

Silver-green filtered light by day. Dramatic bioluminescent blue-white at night — no torches. The silverwood glow is bright enough to cast visible shadows and read clearly at the game's camera distance. It is the only light source after dark. The silverwood canopy is the defining visual identity: pale silver-grey bark, silver leaves, platforms of living wood.

Faces in the bark: visible on close approach. The ancestor-Aelorin consciousness in the wood is suggested visually, not stated. This is a detail for the player to discover, not a tutorial prompt.

The city from below is invisible — this means the approach scene on the forest floor gives no preview of what's above. The reveal (ascending to the canopy level for the first time) is a major visual moment.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT2.md`
**Status:** Sketched. Part of the Aelorin Greatwood arc (3–4 scenes).

Lirien-Thal is one scene in the Aelorin Greatwood sequence:
1. Sirathiel-by-the-Sea — entry point for Roland (only Aelorin city open to humans)
2. Greatwood approach — transition through forest floor
3. **Lirien-Thal canopy platform — Aelthurion audience** (this location)
4. The Second Glade — silver clasp acquired here

Note: Dagna cannot accompany Roland into the Aelorin Greatwood without closing some dialogue options with Aelthurion.

---

## Connections

- **Arrives from:** Greatwood approach (forest floor ascent — mechanism not yet designed)
- **Exits to:** The Second Glade (silver clasp) → return to Act II open world

---

## Open Questions / Gaps

- Ascent mechanism from forest floor to canopy level: not designed (living-wood ramp? root stairway? Aelorin-assisted lift?)
- Aelthurion's audience hall: described as where the Vigil-Keeper-equivalent receives outsiders — GAP for room geometry
- The Second Glade is a distinct sub-location (boundary of the Aelthiren objects, including the silver clasp) — may need its own location file
- Platform network extent: how many platforms constitute the traversable city? Game One only needs the Aelthurion scene; full city scope is background
- Night visit timing: does Roland arrive by day or night? The bioluminescence night scene is potentially the more memorable visual
