# Skills & Progression Design
## How Roland improves over time

> Cross-reference: `design/COMBAT_DESIGN_3D.md` for how skills affect combat mechanics. `design/INVENTORY_AND_EQUIPMENT.md` for smithing tiers and crafting unlocks. `design/JOURNAL_UI.md` for how the skill trees are presented to the player.

---

## Design Philosophy

**You improve what you actually do.** There is no XP pool. There is no level-up screen. Roland does not gain a sword skill by defeating enemies — he gains it by swinging a sword, successfully parrying, and surviving fights. He gains crafting skill by crafting things. He gains endurance by running and fighting through exhaustion.

This mirrors how people actually develop skill. It also means a player who fights their way through everything will be mechanically different from a player who talks and maneuvers their way around conflicts. Both are valid. Neither is objectively better.

**No mandatory skill gates.** Roland can enter any zone and complete any story beat regardless of his skill level. Skills affect *how effectively* he does things, not *whether* he can do them. A low-Vitality Roland fighting Ashfallen is harder than a high-Vitality Roland doing the same — not impossible.

**Enemies do not scale.** A goblin at the end of the game is the same threat as a goblin at the beginning. Roland's growth is real progress, not a treadmill.

---

## The Four Domains

Roland's skills are grouped into four domains. Each domain has a progression track and a small set of discrete skill nodes that unlock at certain thresholds.

---

### Domain 1 — Combat

**What improves it:** Landing attacks, successfully parrying, landing power attacks, surviving fights. Every successful parry contributes more than a landed swing — good technique is rewarded more than volume.

**Progression track:** Combat XP fills a hidden meter. The player sees their current tier (Novice → Trained → Veteran → Master) and the next skill node. They do not see the exact number.

**Skill nodes:**

| Tier | Node | Effect |
|---|---|---|
| Trained | **Wider Parry Window** | The green parry flash lasts 15% longer. The margin for a successful parry increases. |
| Trained | **Light Combo Extension** | The timing window between light-combo hits extends slightly — easier to chain `tap → tap → tap` without breaking the combo. |
| Veteran | **Power Through Block** | Power attacks against a blocking enemy now deal 30% of the power attack damage through the block (chip damage). Previously, a blocked power attack dealt zero. |
| Veteran | **Fast Recovery** | Roland returns to neutral stance 20% faster after a missed or blocked attack — reduces the punishment window for a swing that doesn't connect. |
| Master | **Riposte** | After a successful parry, the first attack Roland makes within 2 seconds deals +50% damage. The parry creates an opening; this rewards capitalizing on it. |
| Master | **Endurance on Parry** | Each successful parry restores a small amount of endurance. Rewards defensive play with the resource that makes offensive play possible. |

---

### Domain 2 — Vitality

**What improves it:** Taking damage, recovering from near-death situations, running until endurance depletes, sleeping in a bed (any full rest). Vitality is the body learning its limits and adapting to them.

**Progression track:** Vitality XP comes from surviving punishment. A player who fights cautiously and takes little damage will progress Vitality slowly. A player who takes hits but keeps going will progress it faster. This is not a design flaw — it reflects what Vitality is.

**Skill nodes:**

| Tier | Node | Effect |
|---|---|---|
| Trained | **Endurance Pool +1** | Maximum endurance increases. More capacity for attacks, blocks, dodges, and sprints before fatigue sets in. |
| Trained | **Wound Recovery** | HP-lost-to-wounds (the portion of HP that only heals by sleeping, not by bandages) recovers faster after rest. |
| Veteran | **Carry Capacity** | Maximum carry weight increases by 15%. Allows heavier armor or larger supply loads without penalty. |
| Veteran | **Endurance Recovery Rate** | The rate at which endurance refills during rest-between-actions increases by 20%. Less waiting between offensive moves. |
| Master | **Second Wind** | Once per combat encounter, when Roland would be reduced to 0 HP, he survives with 10% HP instead. One use. Resets after rest. Not a guaranteed save — only applies once. |
| Master | **Endurance Pool +2** | Second endurance pool increase. Stacks with +1. |

---

### Domain 3 — Crafting

**What improves it:** Actually crafting things. Using a crafting station, preparing herbs, assembling throwables. Each crafted item contributes to Crafting progression. Roland does not need to craft in bulk — consistent use matters more than volume.

**Progression track:** Crafting XP comes from unique recipe use as much as repeat crafting. Trying new recipes advances Crafting faster than mass-producing the same potion. The game rewards experimentation.

**Skill nodes:**

| Tier | Node | Effect |
|---|---|---|
| Trained | **Potion Effectiveness** | All potions and draughts restore 20% more of their base effect. Craft fewer, recover more. |
| Trained | **Throwable Yield** | Crafting throwables (fire bombs, smoke grenades, oil flasks) produces 2 items instead of 1. Same materials, doubled output. |
| Veteran | **Quality Smithing Unlocked** | Roland can now craft and commission Quality-tier weapons and armor. Previously capped at Common tier. Also unlocks the ability to recognize Quality-tier items by inspection. |
| Veteran | **Extended Sharpen** | Using a Sharpening Kit restores 20% more weapon condition. Same kit, better result. |
| Master | **Masterwork Smithing Unlocked** | Roland can craft and commission Masterwork-tier items. Requires access to a skilled smith (Aldric Vane in Game Three, or specific named smiths in Games One and Two). |
| Master | **Material Efficiency** | Crafting recipes cost one fewer unit of their primary ingredient (minimum one). Stretches material supplies in the late game. |

---

### Domain 4 — Exploration & Speech

**Status: deferred for Game One.** The domain exists and tracks progress, but no skill nodes unlock during Game One. Roland's dialogue options and investigation abilities are governed by story flags and companion presence, not skill gates.

**What would improve it (for design completeness):** Successful dialogue resolutions, discovering unmarked locations, completing side quests, reading books or documents. The "listening mechanic" in key scenes also contributes — choosing patience over pressure improves Speech.

**Planned nodes for Game Two (do not build yet):**
- Persuasion Tier — unlocks additional Empathetic dialogue branches
- Investigation Recall — Roland's journal annotations automatically cross-reference related entries
- Reputation Carry — faction disposition gained in one kingdom affects first-contact disposition in another

---

## How Skill Progress is Tracked

**Hidden meters, visible tiers.** The player sees their current tier in each domain (Novice / Trained / Veteran / Master). They do not see a progress bar or a number. The tier advances without announcement — Roland notices he is doing something better before the game labels it.

**No pop-up skill-up announcements.** The first time a skill node activates, a brief contextual notification appears: not "Skill Unlocked: Wider Parry Window" but something Roland-voiced: *"That felt different. I'm reading them better."* One line. Then silence. The player discovers what changed by paying attention in combat.

**In GDScript:** Each domain has an integer counter in `GameState.gd`. Specific in-game events call `GameState.add_skill_xp(domain, amount)`. The counter is never shown directly to the player — only the tier, derived from the counter, is displayed.

```gdscript
# Domain IDs
enum SkillDomain { COMBAT, VITALITY, CRAFTING, EXPLORATION }

# Tier thresholds (internal — not shown to player)
const TIER_THRESHOLDS = {
    SkillDomain.COMBAT:      [0, 300, 700, 1200],
    SkillDomain.VITALITY:    [0, 200, 500, 900],
    SkillDomain.CRAFTING:    [0, 150, 400, 800],
    SkillDomain.EXPLORATION: [0, 250, 600, 1000],
}

# Tier names
const TIER_NAMES = ["Novice", "Trained", "Veteran", "Master"]

# XP amounts awarded per action
const XP_VALUES = {
    "parry_success":    15,
    "power_attack_land": 8,
    "swing_land":        3,
    "combat_survived":  25,   # awarded at end of combat if Roland is alive
    "near_death_survived": 50, # Vitality only
    "endurance_depleted": 20, # Vitality only
    "item_crafted":     30,   # Crafting: per unique recipe (10 for repeat)
    "dialogue_resolved": 40,  # Exploration: per successful listening-mechanic resolution
    "location_discovered": 15, # Exploration: per unmarked location
}
```

---

## Skill UI Presentation

The skill system is visible from the **Journal UI → Skills tab** (see `design/JOURNAL_UI.md`). The layout per domain:

- Domain name and current tier
- Two or three active skill nodes (earned) displayed with their names and a one-sentence description in Roland's voice — not mechanical language
- The next locked node shown as a question mark with a hint: *"There's something I'm not doing yet when I block."* (for Endurance on Parry)
- No numbers. No percentages. No bars. Roland is not a spreadsheet.

**Why no numbers:** This is a game about a knight who reads people. He does not think in percentages. The skill descriptions should read like things Roland notices about himself — not patch notes. If the player wants to know the exact benefit, the design doc (this document) is the reference. The game's job is to make the player *feel* the improvement.

---

## Progression Arc — Game One

Roland starts Game One as a trained former knight who has been inactive. He is not a beginner — he knows how to fight. He is someone whose body has gotten slower while his mind has stayed sharp.

**Act I:** Combat skill is low-Trained. Parry windows feel tight. He can fight, but goblins are a real threat if he's careless.

**Act II:** After the four kingdoms arc and the companion missions — each of which involves more combat — Roland is mid-Veteran in Combat and Vitality. He has been fighting consistently for weeks. The difference is perceptible: he is faster off a parry, his endurance lasts longer.

**Act IV:** By the Ashfields, Roland has been in more fights in six months than in his previous three years combined. Master tier in Combat is achievable by a player who has engaged with combat rather than avoided it. Not guaranteed — achievable.

This arc mirrors the story: Roland at the start is reactive, surviving. Roland at the end is deliberate, controlling. The skill system's job is to make the player *feel* that change in their hands, not just read it in the epilogue.
