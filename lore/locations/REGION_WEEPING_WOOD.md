# The Weeping Wood

**Type:** Region (dead forest / Naergrim territory)
**Kingdom/People:** Naergrim (controlled); no human, Aelorin, or dwarven presence
**Position:** Northeastern Mira — north of the Ashfields, east of the Greatwood's southeastern fringe
**Story relevance:** Game One, Act IV — approach route to Mor-Vethrin; the most dangerous terrain on Mira

---

## Physical Description

A dead forest in northeastern Mira. The trees are grey-trunked with permanent bare branches — they have not produced leaves in recorded history. The cloud cover above the wood does not move with regional wind patterns; it sits fixed overhead in all weather, a permanent effect of Naergrim corruption magic that has persisted for two thousand years.

The Weeping Wood was once living forest — woodland at the northeastern fringe of what is now the Ashfields and the eastern Greatwood fringe. When the Naergrim chose the Ash Throne two thousand years ago and settled in this region, their corruption magic killed the forest. The permanent cloud cover is a side effect of that corruption. The forest has been dead ever since; no growth of any kind occurs within it.

From outside the wood, the fixed cloud cover is visible as a dark grey mass on the horizon that does not change with weather. Travelers who have seen it report that the boundary is unmistakable: living trees stop, dead trees begin, and the sky above goes grey.

At ground level: grey trunks standing close together, dead branches interlocking overhead, no undergrowth, no leaf litter (the leaves fell two thousand years ago and decomposed long since). The ground is bare dark earth, slightly soft underfoot but not wet. Sound behaves strangely: footsteps are muffled, voices carry further than they should, and there is a persistent quality of being heard.

The voices in the trees are not echoes or supernatural haunting. They are Naergrim scouts watching the wood's borders. The Naergrim do not permit casual passage. Almost no one enters the Weeping Wood and returns unchanged — because the Naergrim do not allow strangers to leave who have not been evaluated. The voices are watchers, and the watchers report to Mor-Vethrin.

Mor-Vethrin sits at the wood's eastern edge, built into the dark cliff escarpment rock where the dead forest meets hard stone.

Map texture: bare-branch tree symbols (no leaf canopy), grey/dark shading beneath, fixed cloud symbol above. Dark fortress symbol at the eastern cliff edge for Mor-Vethrin.

---

## 3D Scale Reference
> At 8 voxels per meter (project standard: 1 voxel = 0.125 m)

Key dimensions:

- [x] Dead tree trunk diameter: old-growth scale — ~0.5–1.5 m = 4–12 voxels; no bark variation, uniform grey-brown dead wood
- [x] Dead tree height: ~10–20 m = 80–160 voxels; branches interlocking overhead at roughly 8–15 m height = 64–120 voxels
- [x] Canopy-equivalent height (bare branches overhead): creates a ceiling effect at ~8–15 m without actual canopy cover; light is reduced and directionless
- [x] Ground level: bare dark earth, no undergrowth, occasional fallen branch debris — essentially clear at foot level; the trees do not obstruct ground movement significantly
- [x] Visibility: reduced by tree density; clear line of sight ~30–50 m in most directions, then obscured by trunk density; no ash-haze here (different from the Ashfields) but grey ambient light makes distance judgment difficult
- [x] Camera arm length: interior Weeping Wood = arm 10–12, elevation 48°; the dead branch canopy creates an intermittent ceiling effect that may require camera collision handling; approach toward Mor-Vethrin = arm 10, elevation 50°
- [ ] Wood dimensions: how wide is the Weeping Wood east-to-west? How long north-to-south? — GAP (needed for travel time estimates in Act IV)

The Weeping Wood is not a combat-heavy zone on approach — the Naergrim prefer to observe, report, and direct travelers toward Mor-Vethrin rather than engage. Combat here would be a significant failure condition. The environment should feel watched, not threatened.

---

## Art Direction Notes

The Weeping Wood is visually distinct from every other environment in the game:
- The Ashfields are grey-brown dead soil, open, exposed. The Weeping Wood is grey-trunked enclosed forest — same dead palette but vertical and close.
- The Greatwood is dark-green ancient living forest, filtered light. The Weeping Wood is dark-grey dead forest, no light filtering (the fixed clouds kill direct sunlight entirely).

Palette: grey-brown trunks, dark earth, grey-white dead branches against a permanent grey sky. No color accent anywhere. Cold ambient light only — no warm tones. The only warm element should be the brazier glow visible through Mor-Vethrin's gate when it comes into view.

The fixed cloud cover should be implemented as a WorldEnvironment change when the player crosses the boundary: fog increases, sky color shifts to fixed grey, directional light intensity drops. The transition should be noticeable within a few steps of entering.

Audio: the Ashfields have a dry mineral ambient. The Weeping Wood should shift to something different — a deeper, more resonant absence of sound, occasionally broken by the voices (Naergrim scouts, heard before seen or never seen at all). The acoustic note of being listened to rather than being in a dangerous place.

The wood should feel like a waiting room. The Naergrim already know Roland is there.

---

## Level Layout Reference

**File:** `lore/LEVEL_LAYOUTS_ACT4.md`
**Status:** Sketched. The Weeping Wood is the transition zone between the open Ashfields and Mor-Vethrin.

In Game One: the Weeping Wood is traversed in Act III during the approach to Mor-Vethrin to acquire the obsidian shard; Act IV is the Ashfields fighting retreat. The playable portion is the approach path through the wood to Mor-Vethrin's gate.

The Weeping Wood is not a combat zone on approach. It is a tone-setting traversal — the game's pacing should slow here, the player becoming aware of being watched, before arriving at Mor-Vethrin.

No significant combat encounters in the Wood itself. The Naergrim scouts remain unseen (or barely seen — a glimpse of movement, a voice from a direction that makes no sense). If the player has done the optional Pale Defection quest chain, they may be briefly contacted in the Wood before reaching the gate.

---

## Connections

- **Arrives from:** Ashfields (northeast travel from the Vosskaran frontier zone)
- **Contains:** Naergrim-controlled dead forest; Mor-Vethrin at the eastern escarpment
- **Exits to:** Mor-Vethrin (the only destination — there is no exit north or south through Naergrim territory)

---

## Open Questions / Gaps

- Wood dimensions: how large is the Weeping Wood? Travel time from the Ashfields boundary to Mor-Vethrin gate — a few hours? A day?
- The voices: are the Naergrim scouts ever glimpsed visually, or are they purely audio? The latter is more atmospheric but the former may be more satisfying gameplay.
- The boundary moment: is there a specific visual trigger or dialogue beat when Roland first enters the Weeping Wood, or does it transition silently?
- Is any part of the Weeping Wood north of Mor-Vethrin relevant to game content, or does the playable zone simply end at the city gate?
