# Endgame Choices — Scoring Framework

**Status:** Working draft (v3). This document replaces the v2 "three discrete endings" model with a cumulative scoring system. The mechanic itself is a placeholder; the design intent is locked.

---

## 1. Design Intent

The trilogy ends not with a branch chosen at the climax alone, but with an **epilogue tone shaped by hundreds of small choices** across Games 1, 2, and 3.

Two layers:

1. **Final Choice (binary-ish, at the climax of Game 3).** Roland still picks the *outcome* of his confrontation with Mordvar — the broad shape of how the trilogy ends. Three candidate paths:
   - **Strike.** Kill Mordvar in his physical/worldly form using the reforged Aeluvain in Aldric's hand. The hard, costly path.
   - **Compromise / Bind.** Some middle path — re-bind Mordvar instead of unmaking him; accept a partial victory; spare a faction or a person at a known cost.
   - **Side / Yield.** Throw in with Mordvar's "diagnosis" — the world IS broken, the old order DID fail, accept his rule or terms in exchange for survival of those Roland loves.
2. **Cumulative Score (granular, accumulated across all three games).** Hundreds of micro-choices feed a running ledger. The score does not gate the Final Choice — every player can pick any of the three paths. The score determines **how the world responds** to that choice in the epilogue: which characters live, which factions thrive, which regions recover, which die quietly.

This separates *what Roland decides* from *what the world becomes of his deciding*. A "Strike" ending with a low score can still leave the continent gutted. A "Side" ending with a high score can leave Roland a tragic figure but spare individual companions and towns.

---

## 2. The Score — Working Mechanic

Single running integer, hidden from the player. Starts at 0. Range roughly -200 to +200. Per-faction sub-scores tracked separately so the epilogue can resolve at the granularity of regions and groups.

**Sub-scores (working list, expand as needed):**
- Aelorin
- Dwarven Holds (Khorumzad / Bromrin / Drossvik-region)
- Eldermark / Aldenholt
- Vosskar
- Sailor's Guild
- Naergrim
- Iron Chalice
- Dawnbringers
- Companion sub-scores (per companion: Edran, Aldric, Dagna, Corvus, Seren, etc.)

The global score is roughly the sum, weighted. Individual companion epilogues read from companion sub-scores; regional epilogues read from regional sub-scores.

---

## 3. Examples of Score-Affecting Choices

Sketch only — not exhaustive. Goal is to show the *kind* of choice that ticks the dial.

| Game | Moment | Choice | Effect |
|---|---|---|---|
| 1 | Aldenholt under-reliquary | Spare or kill the compromised priest | +Iron Chalice / -Iron Chalice |
| 1 | Copper Isles raid | Burn the holdfast or take prisoners | +Sailor's Guild / -Sailor's Guild, +/- Corvus |
| 1 | Vosskaran ambush | Reveal Hand involvement to the Vosskar crown or hush it | +Vosskar / -Vosskar |
| 1 | Weeping Wood pursuit | Spare the corrupted envoy who surrenders | +Naergrim, -Aelorin OR vice versa |
| 1 | Khorumzad Underway | Pay the sub-clan's tithe or break their hold | +Dwarven / -Dwarven |
| 2 | Hadran's rescue | Trust his confession or interrogate him hard | +Aldric / -Aldric |
| 2 | Drossvik confrontation | Public exposure or quiet removal | +Dwarven, -Dawnbringer or inverse |
| 2 | Naergrim parley | Concede the southern fishing grounds | +Naergrim, -Sailor's Guild |
| 3 | Vault of Aen-Vael | Take the relic or leave it sealed | global +/- |
| 3 | Aldric's final forging | Roland gives or refuses the personal token Aldric asks for | +Aldric companion sub-score |

The intent is that no single choice dominates. The ledger drifts in response to consistent patterns of behavior — mercy vs. ruthlessness, transparency vs. expedience, community vs. individual.

---

## 4. Epilogue Resolution

After the Final Choice combat, the epilogue is assembled from the score ledger. Structure (working):

- **Cold open.** A single fixed scene matched to the Final Choice (Strike / Compromise / Side). This is authored, not procedural.
- **Roll-call montage.** For each tracked entity (factions, companions, regions, key NPCs), a short epilogue beat. Each beat is selected from a 3-tier table — *flourishing / surviving / lost* — based on that entity's sub-score.
- **Closing image.** A second fixed scene matched to the Final Choice + a global-score band (high / mid / low). Nine possible closing images total (3 paths × 3 bands).

Total authored content: roughly 9 closing scenes, 3 cold opens, and ~3 epilogue beats × ~15 tracked entities = ~45 short beats. Tractable.

---

## 5. Open Questions

- **Visibility.** Does the player see *any* feedback that the score is moving (companion-affinity bars, faction-relation hints) — or is it entirely hidden until the epilogue? Recommendation: show **companion** affinity (visible), keep **faction/regional** scoring hidden.
- **Reset points.** Are there any choices that "lock in" or override prior drift (e.g., a betrayal that floors a sub-score regardless of prior good choices)? Probably yes for a few major moments.
- **Carryover.** Game 1 → Game 2 → Game 3 score persistence requires a save-import system. This is a real engineering cost. Worth costing out before commitment.
- **Final Choice gating.** Should some Final Choices be unavailable below a score threshold (e.g., "Compromise" requires a minimum global score, because the world won't accept the deal otherwise)? Probably no — keep all three available, let the score shape the *consequences*.
- **The Tether path is dead.** v2's "Tether" ending used the Aeluvain-in-throne-compartment trick. v3 replaces it with the **Compromise / Bind** path above, which still ends in climactic combat — Roland fights Mordvar to a standstill and Aldric performs a binding rite mid-fight, rather than killing him outright. No throne trickery.

---

## 6. Notes for the Writers Room

When writing scenes, flag any moment that should be score-affecting with a comment in the timeline file:

```
# SCORE: +5 Aelorin, -2 Naergrim, +1 Edran (companion)
```

The system will be wired through `GameState.gd`'s flag history — most score deltas can ride on the existing flag system as paired flag-set + score-delta lines.

Do not over-author. Aim for ~80–120 score-affecting choices across the trilogy. More than that and individual choices become illegible; fewer and the ledger feels arbitrary.
