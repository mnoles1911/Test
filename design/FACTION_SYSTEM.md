# Faction System Design

How factions work, how Roland's standing with them changes, and how that affects what the world offers him.

> Cross-reference: `design/ECONOMY_AND_VENDORS.md` for how faction disposition affects vendor prices.
> `design/CONVERSATION_SYSTEM.md` for faction-gated dialogue branches.
> `design/QUEST_SYSTEM.md` for faction quest chains and alliance building.
> `lore/GUILDS_KNIGHT_ORDERS.md`, `lore/GUILDS_SHADOW_AND_BANDS.md`, `lore/GUILDS_TRADE_SCHOLAR.md` for faction lore.
> `lore/REFERENCE.md` for the Game Three alliance status table.

---

## Design Philosophy

**Factions are not meters to max out.** Roland is not trying to become best friends with every faction in the world. He is a former knight navigating complex institutional loyalties while pursuing a mission that those institutions may or may not care about. His relationship with each faction is a story, not a progress bar.

**Disposition is earned, not ground.** Standing improves through specific, meaningful choices — not through repeated small interactions that accumulate into friendship. A single decision to honor an agreement with the Iron Chalice, despite the personal cost, matters more than ten quests that could be completed without thought.

**Factions remember, but they also forget context.** The Frost Brotherhood does not care that Roland helped the Golden Lance — in fact, they may care negatively. Improving standing with one faction can reduce standing with a rival. This creates genuine tradeoffs.

**The endgame is the point.** Game Three's battle for the Ashfields requires alliance commitments from specific factions. Game One is where those commitments are seeded or foreclosed. The player may not know it in Act I, but every faction interaction is laying groundwork.

---

## Faction Roster — Game One

### Iron Chalice Order

**What they are:** Roland's former Order. Military brotherhood founded to guard the passes between Vosskara and the eastern frontier. Currently under Dame Calla Vane's command, debt-ridden and politically diminished.

**Roland's default standing:** Former member in unclear status — he left, they didn't expel him, but his departure was complicated. *Starting disposition: Neutral-cautious.*

**Disposition changes:**
- **Resolving the Order's debt** (Act I main quest) → Friendly
- **Recovering the Iron pommel** via negotiation → Allied
- **Agreeing to a future service obligation** to Dame Calla → Allied (with a commitment string attached — she will call it in)
- **Taking the Iron pommel by force** → Hostile (permanently locked out of Iron Chalice support in Game Three)

**What good standing unlocks:**
- Access to Iron Chalice safe-houses and supply caches throughout Game One
- Iron Chalice knights as reliable allies in encounters Roland would otherwise face alone
- Dame Calla's full intelligence on the Korvath network (Act II)
- 1,088 veteran fighters committed to the Game Three battle (if Allied by Game Three)

**What they want from Roland:** Acknowledgment that the Order's mission still matters, and at least one act that demonstrates Roland is still, at heart, one of them.

---

### Frost Brotherhood

**What they are:** A mercenary order-turned-intelligence network operating out of Caer Brannoch and the northern passes. Officially couriers. Actually the most effective human intelligence apparatus in the western continent.

**Roland's default standing:** Unknown — Edran Vane has Brotherhood contacts, and Roland's history with Edran creates an ambiguous introduction. *Starting disposition: Neutral.*

**Disposition changes:**
- **Completing the Caer Brannoch job** (Act II side quest — recovering Brotherhood intelligence from a compromised cache) → Friendly
- **Introducing Orion's maritime contacts** to Brotherhood leadership → Friendly
- **Refusing to hand over intelligence to Prince Aedric** when pressed → Allied
- **Handing Brotherhood intelligence to a crown faction** → Hostile

**What good standing unlocks:**
- Brotherhood safe-houses in every city — a fallback location when Roland is burned elsewhere
- Early intelligence on Ashen Hand movements (precedes faction warnings from other sources by days)
- Pass credentials for the northern Spine road without checkpoint harassment
- Automatic Game Three commitment (the Brotherhood fights regardless of diplomatic standing — but higher standing means they share tactical intelligence freely)

**What they want from Roland:** Proof that he keeps secrets and honors agreements. They do not want his loyalty — they want his reliability.

---

### Sailor's Guild

**What they are:** The international trade-and-information guild based in Caer Brannoch, with chapters at every port. Controls access to the Shroud Sea chart archive and the cross-faction information network.

**Roland's default standing:** None — he has no maritime history. *Starting disposition: Unknown (not hostile, not friendly; Roland simply does not exist to them yet).*

**Disposition changes:**
- **Completing one voyage with a Guild crew** (Act II side quest) → Endorsed (full Guild membership unlocks)
- **Delivering intelligence that prevents an Ashen Hand operation against Guild shipping** → Friendly
- **Sharing the Shroud window information** with a Guild-friendly party (Tidewarden or Queen Eilwen) → Allied
- **Using Guild intelligence for personal advantage** without sharing outcome → −10 standing (not hostile, but noted)

**What good standing unlocks:**
- Access to the Copper Isles Archive and the seventh Crown piece
- Sailor's Guild merchants (rare alchemical imports)
- Orion's formal Guild credentials (important for his character arc)
- Tidewarden military commitment in Game Three (the Tidewardens follow Guild recommendation on Roland's reliability)

**What they want:** A trustworthy outside contact who can move information through channels the Guild cannot directly touch without political exposure.

---

### Golden Lance

**What they are:** Elite mercenary company, based in Solgrade, under Ser Aldric Vossant. Expensive, professional, and scrupulously neutral in royal politics — they fight for whoever pays, but they honor contracts absolutely.

**Roland's default standing:** None. *Starting disposition: Neutral (professional indifference).*

**Disposition changes:**
- **Honoring a contract the Lance has been told Roland holds responsibility for** (Act II — a debt inherited from a dead Iron Chalice officer) → Friendly
- **Providing tactical intelligence on Ashen Hand movements** that saves a Lance unit → Friendly
- **Referring wealthy clients** (quest reward from Renna Aldgate in Solgrade) → +5 standing (minor but tracked)
- **Breaking a contract or allowing a contract-holder to be harmed** while Roland was the responsible party → Hostile

**What good standing unlocks:**
- Vossant's advice and tactical intelligence on Ashen Hand forces (he has fought them twice)
- Reduced commission price if Roland hires a Lance escort for a dangerous crossing
- Game Three commitment if Roland honors Vossant's contract and demonstrates the mission's strategic scope

**What they want:** Someone who understands contractual obligation the way they do. Not affection. Not ideology. Honor in the professional sense.

---

### Vosskara (Despot Yaromir's court)

**What they are:** The eastern frontier despot, semi-autonomous, nominally loyal to no human kingdom. Controls the eastern road and the trade route through Vosskara Pass. Yaromir is the authority — there is no guild here, only a personal relationship with the man.

**Roland's default standing:** None. *Starting disposition: Cautious (Yaromir is careful about outsiders).*

**Disposition changes:**
- **Listening first before negotiating** (the listening mechanic — spending one full conversation without trying to leverage) → Begins opening
- **Resolving the Tribute War escalation** (a timed side quest — Ashen Hand agents are framing Vosskara soldiers for border incidents) → Friendly
- **Asking the right question** (what Yaromir wants to be remembered for — the key Tier 3 dialogue moment) → Allied
- **Using information Yaromir shared** against Vosskaran interests → Hostile

**What good standing unlocks:**
- The bronze ring Crown piece via diplomatic gift rather than bargaining or theft
- Safe passage through Vosskara Pass (closes an otherwise dangerous act traversal)
- Yaromir's full intelligence on Ashen Hand Vosskaran operations
- Vosskara troop commitment in Game Three if the Tribute War is resolved and Roland has not exploited the relationship

**What they want:** A person who treats Yaromir as a full human being with a stake in the future, not as an asset to be managed.

---

### Aelorin (Aelthurion / the Greatwood)

**What they are:** The oldest civilization in the western continent, diminishing. Aelthurion has held the Second Glade for centuries. Contact with humans is limited and conditional — Aelorin do not seek engagement.

**Roland's default standing:** None. The Aelorin do not have a disposition toward Roland — they have a disposition toward humans as a category, which is cautious. *Starting state: Requires introduction.*

**Disposition changes:**
- **Seren's recommendation** (once she joins in Game Two) → Open to dialogue
- **Recovering the Second Glade document** stolen by a House Korvath agent (Act II) → Indebted
- **Providing evidence of the Khorumzad contamination's spread** toward the Greatwood → Concerned (motivates cooperation)
- **Attempting to enter Lirien-Thal without invitation** → Permanently barred from the interior (the silver clasp becomes inaccessible without Seren's mediation)

**What good standing unlocks:**
- The silver clasp Crown piece
- Aelthurion's knowledge of Mordvar's original binding (significant lore for Game Three prep)
- Safe passage through the northern Greatwood road (saves weeks of travel around the edge)
- Game Three: the Aelorin do not send fighters, but Aelthurion provides the final piece of the ritual framework

**What they want:** Evidence that this human is not another transient concern but someone engaged with consequences that span centuries.

---

## Faction Disposition Mechanics

### Disposition Scale

Each faction has an integer disposition value in `GameState.gd`:

```
-100  Hostile (will not trade, may attack on sight, will not send Game 3 forces)
  -50  Unfriendly (disadvantageous prices, limited dialogue options)
    0  Neutral (default; standard interactions)
  +25  Friendly (better prices, more dialogue, more information)
  +60  Allied (maximum benefits; Game Three commitment secured)
```

Disposition does not change gradually through small interactions. It changes in **discrete steps** when specific story flags fire:
- Small change: ±10–15 points
- Significant change: ±25–30 points
- Major change: ±40–50 points

### Rival Faction Reactions

Certain faction pairs have tension. Improving one at the expense of another:

| Faction A improved | Faction B affected | Change |
|---|---|---|
| Iron Chalice (Allied) | Prince Aedric's court | −20 (Aedric sees Chalice loyalty as threat) |
| Frost Brotherhood (Allied) | Crown factions generally | −10 (Brotherhood's political independence rankles crowns) |
| Vosskara (Allied) | House Korvath, Solgrade | −15 (Yaromir and Korvath have a trade dispute) |

These secondary effects happen automatically when the primary flag fires. The player is not told about them unless they notice the change in NPC behavior or dialogue.

### Faction Lockouts

Some faction standings can be permanently foreclosed by specific choices:
- **Attacking the Iron Chalice** in any scene → Permanently Hostile (even Dame Calla cannot reverse this)
- **Handing Brotherhood intelligence to a crown** → Hostile + cannot be reversed in Game One (may be repaired in Game Two with significant effort)
- **Entering Lirien-Thal without invitation** (before Aelorin standing is unlocked) → Access revoked, cannot be reversed without Seren (Game Two)

These lockouts are not arbitrary punishment. They represent the logic of the institutions involved. The Iron Chalice does not forgive betrayal. The Brotherhood does not trust someone who sold them out. The Aelorin do not extend further trust to someone who violated their space.

---

## GDScript Notes

### FactionManager autoload

```gdscript
# FactionManager.gd — new autoload to add
# Wraps GameState flag read/write for faction dispositions.

func get_disposition(faction_id: String) -> int:
    return GameState.get_flag("faction_" + faction_id).to_int()

func change_disposition(faction_id: String, amount: int) -> void:
    var current: int = get_disposition(faction_id)
    var new_val: int = clamp(current + amount, -100, 60)
    GameState.set_flag("faction_" + faction_id, str(new_val))
    _apply_rival_effects(faction_id, amount)

func is_hostile(faction_id: String) -> bool:
    return get_disposition(faction_id) < -30

func _apply_rival_effects(faction_id: String, amount: int) -> void:
    # Apply secondary changes to rival factions.
    # Called automatically when a disposition changes.
    var rivals: Dictionary = RIVAL_MAP.get(faction_id, {})
    for rival_id in rivals:
        if sign(amount) == sign(rivals[rival_id]):
            change_disposition(rival_id, rivals[rival_id])
```

### Faction-gated dialogue check

```gdscript
# In a Dialogic condition node:
func is_iron_chalice_allied() -> bool:
    return FactionManager.get_disposition("iron_chalice") >= 60
```
