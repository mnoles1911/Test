# Economy & Vendors

How money, trade, and vendors work in Game One.

> Cross-reference: `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` for item categories, weight, and smithing tiers.
> `design/ITEM_LIBRARY.md` for the full item list with pricing context.
> `design/CRAFTING.md` for the alternative to buying — making your own.
> `design/FACTION_SYSTEM.md` for how faction disposition affects vendor prices.

---

## Design Philosophy

**Roland is not wealthy.** He is a former knight whose Order no longer exists. He has skills, a sword in serviceable condition, and whatever he can find or earn along the way. The economy should reflect this: money is meaningful, not abundant. Finding a Gold coin in a chest should feel like a find, not a reload of pocket change.

**No vendor trash.** Roland does not loot enemies for coin drops or sell piles of miscellaneous junk to a generic shop. Every item sold to a vendor is something the player chose to part with — a piece of gear they replaced, a material surplus they do not need. The economy is lean by design.

**Prices have a texture.** A smith in a busy trade city charges more than a smith in a frontier town. A vendor who knows Roland, or who owes a faction Roland has helped, gives him a better deal. The economy is not a flat exchange rate.

**The goal is never grinding.** If Roland needs money for something specific — a better weapon, a smith to repair his armor, passage on a boat — that money should be available through play without requiring the player to farm encounters repeatedly. If the player finds themselves grinding for coin, the economy is miscalibrated.

---

## Currency

One currency: **crowns** (gold). Subdivided in merchant parlance but never tracked at less than 1 crown in the game interface.

Roland carries crowns as a simple integer. He does not manage pouches, denominations, or weight.

**Starting crowns (Game One): 80 crowns.** Enough for one night at a modest inn (4–8 crowns) or a weapon sharpening (2–4 crowns), but not enough to buy a replacement weapon or a suit of armor. The initial shortage is intentional: it frames the opening as genuinely uncertain and pushes Roland toward earned income before shopping.

---

## Vendor Types

### Smith / Armorer

Found in every settlement of meaningful size.

**Sells:** Weapons and armor at Common tier by default. A skilled smith in a major settlement may sell Quality tier items if Roland's Crafting domain has reached the Veteran threshold (confirmed Quality tier unlocked).

**Buys:** Weapons and armor. Pays roughly 40% of the item's sell price for degraded equipment; up to 60% for good condition. Will not buy items below 20% condition ("not worth my time to restore").

**Services:**
- **Weapon sharpening:** Restores condition on Roland's primary weapon. Faster and more effective than a Sharpening Kit. Costs crowns.
- **Armor repair:** Restores condition on one armor piece per visit. Costs crowns scaled to damage.
- **Commission a weapon or armor piece:** Roland provides the materials (or pays market rate), smith takes time (WorldClock advances 1–3 in-game days depending on complexity). Result is at the smith's tier ceiling and Roland's Crafting domain tier, whichever is lower.

**Named smiths in Game One:**
- **Marten Voss** — Aldenholt. Common-tier reliable. Gruff, fair prices. Has been repairing Iron Chalice gear for thirty years.
- **Renna Aldgate** — Solgrade. Quality-tier capable. Higher prices. Requires Roland to have a Solgrade merchant introduction to unlock Quality commissions.
- **Hagrim of Kazaad-Brak** — Dwarven standard. Will work to Quality-tier and can theoretically commission Masterwork, but requires the Khorumzad alliance path to unlock access.

---

### Herbalist / Apothecary

Found in most towns. Some rare ingredients are only available from specific herbalists.

**Sells:** Common herbs and base alchemy ingredients. Pre-made low-tier potions (Field Herb Tea, basic bandages) at higher price than crafting cost. The point of buying pre-made is speed — Roland may not always have time to brew.

**Buys:** Surplus herbs and crafting materials. Pays fair rates for rare finds.

**Key herbalist — Old Mira (Aldenholt):** The herbalist Roland can learn alchemy from (trainer NPC). Sells a wider ingredient range than most. Can teach recipes not available elsewhere in Act I. Disposition gate: requires Roland to complete a minor favor (finding her lost apprentice or returning a stolen supply batch — one of which is an Act I side quest).

---

### General Merchant

Varied stock depending on settlement size and trade connections.

**Sells:** Miscellaneous: rope, torches, camp supplies (tinder, basic food), lockpicks, simple tools. Not weapons, not armor.

**Buys:** Almost anything — they are the most permissive buyers. Pay the worst rates but accept the broadest inventory.

**Sailor's Guild merchants (Caer Brannoch):** Access to materials from the Shroud Sea trade route — rare alchemical components not available inland. Requires Roland to have Sailor's Guild standing (see `design/FACTION_SYSTEM.md`).

---

### Inn

Not strictly a vendor, but provides services for crowns.

**Services:**
- **Full rest** — inn bed guarantees Full Rest quality regardless of location. Creates an autosave (see `design/REST_AND_CAMP.md`). Costs crowns per night.
- **Meal** — a cooked meal from the inn kitchen. Provides the well-fed bonus before rest. Cheaper than buying ingredients and cooking at camp.
- **Information** — innkeepers are information nodes. Asking an innkeeper about a town often unlocks relevant NPC locations on Roland's map or adds annotations.

---

## Pricing Framework

All prices are relative, not fixed. The base price of an item scales with:

1. **Smithing tier:** Common < Quality < Masterwork (roughly 1× / 2.5× / 6× base)
2. **Item condition:** Full price at 100%, sliding scale down to ~30% price at 20% condition
3. **Vendor quality:** A skilled city smith charges more for repair than a frontier smith
4. **Faction disposition:** See below

**Rough price anchors (crowns):**
| Item | Buy price (typical) | Sell price (to vendor) |
|---|---|---|
| Common sword (new) | 8–12 | 4–6 |
| Quality sword (new) | 22–30 | 11–15 |
| Masterwork sword | 80–120 | not typically sold |
| Weapon sharpening | 2–4 | — |
| Armor repair (light) | 3–6 | — |
| Armor repair (heavy) | 6–12 | — |
| Field Herb Tea (pre-made) | 3 | 1 |
| Bandage Roll (pre-made) | 2 | 1 |
| Inn bed (night) | 4–8 | — |

Roland's typical income sources: selling surplus materials, selling replaced gear, quest rewards, one-time finds.

---

## Faction Disposition and Prices

A vendor's faction affiliation affects prices for Roland based on his standing with that faction:

| Disposition | Price modifier |
|---|---|
| Hostile | Will not trade |
| Neutral | Standard price |
| Friendly | −10% to −15% |
| Allied | −20% to −25% |

Faction disposition is set and modified by `GameState` flags (see `design/FACTION_SYSTEM.md`). The vendor checks Roland's disposition with their affiliated faction on each interaction.

The price change is never announced. The vendor might give Roland a better price without explaining why — or might simply not argue when Roland haggles. The effect is subtle but real.

---

## Haggling

Roland can attempt to negotiate price on individual transactions. This is not a minigame and not a skill check. It is a dialogue option that appears for certain purchases when Roland has relevant leverage:

- **Information advantage:** Roland knows something the vendor needs ("I could tell the Confederation what you've been selling to that Ashen Hand contact — or we could find a number that works for both of us.")
- **Faction standing:** "The Tidewarden commission has been good to my work. A friend of the captain deserves a better rate."
- **Volume:** "I need six of them. I can pay for two now and bring materials for the other four."

Haggling does not use the Charisma stat — it uses specific flags Roland has earned through play. A player who has done the right quests and paid attention has more leverage. A player who has not, does not.

---

## Economy and Game Pacing

**Act I:** Money is tight. Roland is scraping. He can afford repairs but not upgrades. A Quality sword found in the Archive vault is notable precisely because he could not afford to buy one.

**Act II:** Roland has more contacts and income sources. He can afford to commission specific items and maintain his gear properly. Money is still meaningful but not a constant concern.

**Act III–IV:** Roland is deep into a mission. Money matters less — he is not shopping. The economy takes a back seat to survival and faction relationships.

---

## GDScript Notes

### Vendor transaction

```gdscript
# VendorUI.gd — handles a buy/sell transaction:
func complete_purchase(item: ItemData, quantity: int, price: int) -> void:
    if GameState.get_flag("crowns").to_int() < price:
        # Not enough crowns — show feedback, do not complete
        return
    var new_total: int = GameState.get_flag("crowns").to_int() - price
    GameState.set_flag("crowns", str(new_total))
    InventoryManager.add_item(item, quantity)
```

### Faction price modifier

```gdscript
func get_price_modifier(faction_id: String) -> float:
    var disposition: int = FactionManager.get_disposition(faction_id)
    if disposition < 0:     return 999.0  # effectively blocked
    elif disposition < 25:  return 1.0    # neutral
    elif disposition < 60:  return 0.87   # friendly
    else:                   return 0.77   # allied
```
