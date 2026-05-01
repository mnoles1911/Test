# Inventory & Equipment Design
## What Roland carries, wears, and uses

> This document covers the inventory and equipment systems. For crafting recipes and the crafting UI, see `design/CRAFTING.md` (when written). For combat use of consumables, see `design/COMBAT_DESIGN_3D.md`. For the Items tab of the journal, see `design/JOURNAL_UI.md`.

---

## Design Philosophy

**Every item has a reason to exist.** No junk loot, no vendor trash, no ten varieties of "rusty sword." If an item is in the game, the player should be able to name what it does and why they might want it. Roland travels light because he has to.

**Weight and commitment, not spreadsheet management.** Modeled on KCD2: Roland can carry a reasonable load without the player obsessing over numbers. The weight system exists to create tradeoffs, not to punish. A bandage and a grenade are both small. A full suit of plate armor is not.

**Items are diegetic.** A Saviour Schnapps is a real bottle Roland drinks. Bandages are real bandages applied during a real pause in combat. The game does not have a "use potion" button — it has Roland pulling something from his pack and using it, with a visible animation that costs time.

---

## Equipment Slots

Roland has six equipment slots. Only items of the correct type can occupy each slot.

| Slot | Description |
|---|---|
| **Weapon** | Main-hand melee weapon (sword, axe, or mace) |
| **Off-Hand** | Shield or second weapon (if dual-wield unlocked via skill) |
| **Head** | Helmet or hood |
| **Body** | Chest armor (gambeson, mail, plate) |
| **Hands** | Gauntlets or gloves |
| **Boots** | Footwear |

### Game One Equipment Reality

Roland starts Game One with a basic sword (Common tier) and a padded gambeson. He is a former Iron Chalice knight whose equipment has been repaired many times. His gear is functional, not impressive. The Arc of progression is acquiring better gear through the game's events — not through shopping.

**No off-hand in Game One Act I.** Roland's block mechanic uses his sword-arm positioning, not a shield. A shield option opens in Act II when Roland finds or buys one.

---

## Item Categories

### 1. Consumables

Used from the quick slot bar mid-combat or from the inventory menu at camp/rest. Each use plays a short animation during which Roland is vulnerable.

| Item | Effect | Use time | Source |
|---|---|---|---|
| **Bandage** | Restores a small amount of HP. Fast to apply. | Short | Lootable, purchasable |
| **Healing Herb** | Restores moderate HP. Slightly slower than a bandage. | Medium | Foraged, purchasable |
| **Potion (basic)** | Restores significant HP. Crafted only — not sold. | Medium | Crafted |
| **Endurance Draught** | Restores endurance pool immediately. Crafted only. | Short | Crafted |
| **Saviour Schnapps** | Creates a manual save when drunk. Diegetic quicksave. | Short | Purchasable (limited), crafted |
| **Sharpening Kit** | Restores weapon condition (damage). Applied at camp or in a pause between fights. | Long | Purchasable, looted |
| **Repair Kit** | Restores armor and blunt weapon condition. Applied at camp. | Long | Purchasable, looted |

**Saviour Schnapps** is intentionally limited in supply. It is not a consumable to stockpile — it is a decision point. The player should feel the choice to drink one.

### 2. Throwables

Used from the quick slot bar. Roland pulls the item and throws it with a short aiming arc. Cannot be used while locked in an attack animation.

| Item | Effect | Radius | Source |
|---|---|---|---|
| **Fire Bomb** | Burning AoE on impact. Enemies in the fire take damage-over-time. | Medium | Crafted |
| **Oil Flask** | Slick surface. Enemies crossing it move slowly and fall. Combine with a fire bomb. | Large | Crafted, looted |
| **Smoke Grenade** | Obscures vision in a radius. Enemies disengage momentarily. | Medium | Crafted |
| **Caltrops** | Scattered metal spikes. Enemies crossing them slow significantly. | Small (line) | Crafted, purchasable |

### 3. Quest Items

Items Roland carries because the story requires them. They occupy no weight and cannot be discarded. They are visible in the Items tab but clearly marked. The seven Crown pieces are Quest Items.

### 4. Crafting Materials

Raw ingredients for consumables, throwables, and potions. They do have weight, which is the game's gentle pressure toward not hoarding everything. See `design/CRAFTING.md` for the full material list and recipe reference.

---

## Quick Slot Bar

**Four quick slots.** Displayed at the bottom of the screen during play, hidden during dialogue. Each slot holds one item type (any quantity of that item). During combat the player cycles slots with Q/E and activates with F.

Why four: enough to carry a healing option, an endurance option, and two tactical choices (a throwable or two) — without overwhelming the UI or making every encounter a menu-management task.

**Assigning items to slots:** Done from the inventory screen. Drag an item to a quick slot, or press the assign button. This cannot be done during combat.

**Quick slot display:** Each slot shows the item icon and a number (quantity remaining). When a slot is empty it dims. When Roland activates a slot, a short radial fill animation plays on the slot icon as the use animation runs — giving the player a clear visual for the vulnerability window.

---

## Carry Capacity — Weight

Roland has a maximum carry weight. The player sees a weight bar in the inventory screen: current weight / maximum.

| Condition | Effect |
|---|---|
| Under 70% | No penalty |
| 70–90% | Stamina recovery is slightly slower |
| 90–100% | Stamina recovery is significantly slower; cannot sprint |
| Over 100% | Cannot move. (This should not happen in normal play — the game warns before it happens.) |

**Base carry weight** increases with the Vitality → Carry Capacity skill node. Starting weight is intentionally limited: Roland travels on foot. He is not a pack mule.

**Equipment counts toward weight.** Heavier armor provides better protection but increases carry cost. A full plate harness is heavy enough to make consumable management meaningful.

**Quest items weigh nothing.** They are carried by story logic, not backpack physics.

---

## Equipment Condition

All weapons and armor have a **condition** value: a percentage from 0% (destroyed) to 100% (mint).

**Condition degrades through use:**
- Weapons lose condition with every swing (slow)
- Weapons lose condition faster when blocking (medium)
- Armor loses condition when Roland takes hits (slow per hit, cumulative)

**Effects of degraded condition:**
| Condition | Weapon | Armor |
|---|---|---|
| 100–70% | Full damage | Full protection |
| 70–40% | Slight damage reduction | Slight protection reduction |
| 40–10% | Meaningful damage reduction; charge attacks lose impact | Noticeable protection reduction |
| Below 10% | Severe damage penalty; weapon may fail to block | Minimal protection |
| 0% | Still usable but at severe penalty — forces a gear decision | No protection |

**Restoring condition:**
- **Sharpening Kit** → restores weapon condition (edge damage only; does not fix a bent crossguard)
- **Repair Kit** → restores armor condition and blunt weapons (maces, hammers)

Kits are used from the inventory screen, not quick slots. They require Roland to be at rest (not in active combat). At camp, Roland can maintain all of his gear.

---

## Smithing Tiers

Weapons and armor come in three tiers, determined at the point of creation or acquisition.

| Tier | Damage / Protection | Durability | Availability |
|---|---|---|---|
| **Common** | Baseline | Standard | Starting gear, common loot, cheap vendors |
| **Quality** | +20–30% | Higher | Better vendors, skilled blacksmiths, specific crafting |
| **Masterwork** | +50–60% | Highest | Requires Crafting skill, named smiths, rare |

Tier is a fixed property of the item — it cannot be upgraded. A Common sword cannot become a Quality sword through sharpening. It can only be replaced.

**Roland's starting sword** is Common tier, repaired twice. Replacing it in Act I is a minor but real upgrade. A Masterwork weapon in Game One is exceptional and should feel exceptional.

---

## Companion Inventory

Orion and Dagna carry their own gear and consumables. Roland cannot directly command what they use in combat — they make those decisions autonomously. Between fights (at camp or a rest point), Roland can **open a companion's pack** through the dialogue interaction with that companion.

The companion pack screen is a simplified version of Roland's inventory:
- View what they're currently equipped with
- Swap weapons or armor from their pack or Roland's pack
- Restock their consumables (drag from Roland's supply)
- See their equipment condition and decide whether to use a kit

This is not a menu Roland opens mid-combat. It requires physical proximity and a moment of stillness — both of which camp provides.

**Companions do not run out of basic consumables automatically.** If Roland neglects to restock Orion's bandages, Orion fights without bandages. The game does not quietly refill companion supplies.

---

## Loot and Pickup

**Loot is placed by hand**, not procedurally generated. Every item on a dead enemy or in a chest was put there by a designer decision. This keeps the world's items meaningful — finding a quality sword on a specific Ashfallen lieutenant means something.

**Pickup interaction:** Approach the item or container, press E. If the item takes Roland over carry weight, the game warns before adding it.

**Enemy drops:** Enemies drop the gear they visibly wear. An unarmored goblin drops no armor. An Ashfallen in chain mail drops chain mail (in degraded condition — they've been wearing and fighting in it).

**Container types:**
- **Bodies:** looted after combat. Yield gear and whatever the enemy carried.
- **Chests:** found in the world. Usually locked — requires a lockpick (consumed on use) or a key.
- **Caches:** the Brotherhood maintains supply caches in the Underway and at safe-house junctions. These contain specific items Roland can plan around.

---

## GDScript and InventoryManager Notes

`InventoryManager.gd` (already written as an autoload) manages the inventory. Key additions the combat and equipment systems require:

```gdscript
# Item resource fields needed (add to ItemData.gd resource class):
var smithing_tier: int        # 0 = Common, 1 = Quality, 2 = Masterwork
var condition: float          # 0.0 to 1.0
var weight: float             # in arbitrary units
var item_category: String     # "consumable", "equipment", "quest", "material", "throwable"
var equipment_slot: String    # "weapon", "offhand", "head", "body", "hands", "boots", ""
var quick_slottable: bool     # whether it can go in a quick slot

# Key methods to add/verify:
InventoryManager.get_equipped(slot: String) -> ItemData
InventoryManager.equip(item: ItemData, slot: String) -> void
InventoryManager.get_condition(item: ItemData) -> float
InventoryManager.degrade_condition(item: ItemData, amount: float) -> void
InventoryManager.repair_condition(item: ItemData, amount: float) -> void
InventoryManager.get_total_weight() -> float
InventoryManager.get_quick_slot(index: int) -> ItemData
InventoryManager.assign_quick_slot(item: ItemData, index: int) -> void
InventoryManager.open_companion_pack(companion_id: String) -> void
```

The `condition` float is stored per item instance, not per item type. Two identical swords can have different condition values. This means inventory items are instances, not references to a shared resource — each pickup creates a new resource instance with its own condition value.
