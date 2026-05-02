# Inventory & Equipment System Design
## How the inventory works — slots, weight, condition, and gear mechanics

> This document covers the **system mechanics** of the inventory: how slots work, how weight and condition are tracked, how smithing tiers function as item properties, and how companion packs are managed. It does not list specific items or recipes.
>
> For the complete item and recipe reference (potions, weapons, armor, throwables, meals), see `design/ITEM_LIBRARY.md`.
> For crafting station mechanics and quality tiers, see `design/CRAFTING.md`.
> For combat use of consumables and quick slots in combat, see `design/COMBAT_DESIGN_3D.md`.
> For the Items and Crafting tabs of the journal UI, see `design/JOURNAL_UI.md`.

---

## Design Philosophy

**Every item has a reason to exist.** No junk loot, no vendor trash, no ten varieties of "rusty sword." If an item is in the game, the player should be able to name what it does and why they might want it. Roland travels light because he has to.

**Weight and commitment, not spreadsheet management.** Roland can carry a reasonable load without the player obsessing over numbers. The weight system exists to create tradeoffs, not to punish. A bandage and a grenade are both small. A full suit of plate armor is not.

**Items are diegetic.** A Wanderer's Seal is a real vial Roland drinks. Bandages are real bandages applied during a real pause in combat. The game does not have a "use potion" button — it has Roland pulling something from his pack and using it, with a visible animation that costs time.

---

## Equipment Slots

Roland has six equipment slots. Only items of the correct type can occupy each slot.

| Slot | Description |
|---|---|
| **Weapon** | Main-hand melee weapon (sword, axe, or mace) |
| **Off-Hand** | Shield, torch, or second weapon (if dual-wield unlocked via skill) |
| **Head** | Helmet or hood |
| **Body** | Chest armor (gambeson, mail, plate) |
| **Hands** | Gauntlets or gloves |
| **Boots** | Footwear |

### Weapon Handedness

All weapons are either **one-handed** or **two-handed**. This determines whether the Off-Hand slot is available simultaneously.

| Handedness | Weapons | Off-Hand available? |
|---|---|---|
| **One-handed** | Short swords, daggers, hand axes, maces, clubs | Yes — can use shield, torch, or (if unlocked) off-hand weapon |
| **Two-handed** | Longswords, broadswords, war axes, mauls | No — occupies both Weapon and Off-Hand slots |

Roland's starting weapon (Common-tier short sword) is one-handed. Two-handed weapons become available as loot and purchase options from Act II onward. A Roland who uses a two-handed weapon hits harder but cannot use a torch for light or a shield for defense — a genuine tradeoff.

**Equipping a two-handed weapon** automatically empties the Off-Hand slot (any shield or torch is moved back to inventory). The UI warns the player before this happens.

### Tools (Edit Verbs)

Tools — axes, pickaxes, shovels — are **weapons that can also edit terrain**. They occupy the Weapon slot when equipped. Each tool has two functions:

1. **Combat use:** swing damages enemies (lower than dedicated weapons). Axe = anti-armor. Pickaxe = blunt. Shovel = light.
2. **Terrain use:** when the swing connects with a voxel surface (no enemy in front), it removes voxels of the matching material type, yielding the material into Roland's inventory.

| Tool | Slot | Combat damage | Terrain target | Notes |
|---|---|---|---|---|
| **Axe** | Weapon | Moderate (anti-armor bias) | Wood (trees, logs) | Felling trees triggers a directional topple animation; trunk resolves into log voxels Roland can pick up |
| **Pickaxe** | Weapon | Low (blunt) | Rock, stone, ore | Per-swing voxel removal; tier gates material hardness (wooden pick → stone; quality → iron-tier; masterwork → adamant-tier) |
| **Shovel** | Weapon | Low | Dirt, sand, clay, ash | Faster swing than pickaxe; ash-tier shovel needed for hardened ash voxels |

**Material gating** is independent of skill — a wooden pickaxe cannot mine adamant ore regardless of Mining sub-skill (see `design/SKILLS_AND_PROGRESSION.md` → Crafting → sub-skills). Skill controls speed and yield within the tier the tool can handle.

**Edit speed is intentionally slow.** Each swing has a cooldown comparable to a melee combat swing. Number and velocity of edits per session is far below Minecraft pace — this is a feature, not a bug. It keeps voxel deltas sparse, save sizes small, and the world feeling resistant. Players will not casually reshape kilometers of terrain.

**NoEditZones:** Swings inside a NoEditZone (settlements, dungeon entrances, lore landmarks) silently fail to remove voxels and trigger a Roland bark *"This place doesn't yield to me."* Combat damage to enemies still works inside NoEditZones.

### Explosives

Explosives are **throwables** (quick slot) that produce voxel-removal AOE on detonation in addition to combat damage. Crafted at the Assembly Table — see `design/CRAFTING.md` and `design/ITEM_LIBRARY.md`. Loud — draws enemy attention from a wide radius.

| Item | AOE | Combat damage | Voxel target |
|---|---|---|---|
| **Powder Charge** | 2m radius | Light | Stone, rock, ore — useful for breaching cave walls and fortification masonry |
| **Sapper's Bundle** | 4m radius | Heavy | Same — for serious breach jobs; rare |

Spells are the magical equivalent and become available when magic-using companions join (Game Two onward). Earth-school spells dig; fire spells fell trees and ignite. Spell terrain effects route through `VoxelEditManager` like any other edit verb.

### Torches

A torch equips to the **Off-Hand slot**. While equipped:
- Roland cannot block (no free hand for sword-arm positioning)
- A light radius of **8 meters** illuminates the area around Roland
- Enemy detection range is slightly increased (Roland is visible from farther away in darkness)
- Torches are **incompatible with two-handed weapons** (both use the Off-Hand slot)

**Torch properties:**
- **Duration:** 4 in-game hours (WorldClock hours) per torch
- **Weight:** 0.3 kg each
- **Carried quantity:** No specific limit beyond weight capacity; carrying 3–5 is typical for a dungeon run
- When a torch's duration expires, it extinguishes and is removed from the Off-Hand slot (Roland is not warned — he sees the light go out)
- Torches cannot be re-lit once extinguished

Torches are sold by general merchants and found in dungeon environments. They are a genuine resource decision in underground zones — committing picks and map attention to navigate in darkness vs. committing Off-Hand and combat options to stay lit.

### Game One Equipment Reality

Roland starts Game One with a basic short sword (Common tier, one-handed) and a padded gambeson. He is a former Iron Chalice knight whose equipment has been repaired many times. His gear is functional, not impressive. The arc of progression is acquiring better gear through the game's events — not through shopping.

**No off-hand combat item in Game One Act I.** Roland's block mechanic uses his sword-arm positioning, not a shield. A shield option opens in Act II when Roland finds or buys one. A torch can be equipped at any time — it does not require Act II.

---

## Item Categories

### 1. Consumables

Used from the quick slot bar mid-combat or from the inventory menu at camp/rest. Each use plays a short animation during which Roland is vulnerable.

**Consumable categories:**
- **Healing items** — bandages, herb teas, draughts, and potions. Restore HP; some also address wounds, bleeding, or status effects. Use time varies: bandages are fast, potions are slower.
- **Endurance items** — draughts that restore endurance immediately or improve recovery rate.
- **Maintenance kits** — Sharpening Kits (weapon condition) and Repair Kits (armor and blunt weapon condition). Applied at camp, not mid-combat.
- **The Wanderer's Seal** — a crafted vial that creates a manual save when consumed. Intentionally limited in supply; not a consumable to stockpile. The player should feel the weight of the choice to use one.

For the complete list of all consumable items, their ingredients, and effects, see **`design/ITEM_LIBRARY.md` → Section 1 (Potions)** and **Section 4 (Assembly Table)**.

### 2. Throwables

Used from the quick slot bar. Roland pulls the item and throws it with a short aiming arc. Cannot be used while locked in an attack animation.

**Throwable categories:** fire bombs, oil flasks, smoke grenades, caltrops, flash powder, traps, and utility throws. Each has a distinct tactical purpose and does not overlap in function with others.

For the complete list of throwables with materials, batch sizes, and effects, see **`design/ITEM_LIBRARY.md` → Section 4 (Assembly Table)**.

### 3. Quest Items

Items Roland carries because the story requires them. They occupy no weight and cannot be discarded. They are visible in the Items tab but clearly marked. The seven Crown pieces are Quest Items.

### 4. Crafting Materials

Raw ingredients for consumables, throwables, potions, and smithed items. They have weight — the game's gentle pressure toward not hoarding everything.

For the master list of all input materials, their sources, and which crafting sections use them, see **`design/ITEM_LIBRARY.md` → Raw Materials**.

---

## Quick Slot Bar

**Four quick slots.** Displayed at the bottom of the screen during play, hidden during dialogue. Each slot holds one item type (any quantity of that item). During combat the player cycles slots with Q/E and activates with F.

Why four: enough to carry a healing option, an endurance option, and two tactical choices (throwables, a trap, a coating) — without overwhelming the UI or making every encounter a menu-management task.

**Assigning items to slots:** Done from the inventory screen. Cannot be changed during combat.

**Quick slot display:** Each slot shows the item icon and quantity remaining. When a slot empties it dims. When Roland activates a slot, a short radial fill animation plays on the slot icon as the use animation runs — a clear visual indicator of the vulnerability window.

---

## Carry Capacity — Weight

Roland has a maximum carry weight. The player sees a weight bar in the inventory screen: current weight / maximum.

| Condition | Effect |
|---|---|
| Under 70% | No penalty |
| 70–90% | Stamina recovery is slightly slower |
| 90–100% | Stamina recovery is significantly slower; cannot sprint |
| Over 100% | Cannot move. The game warns before this happens. |

**Base carry weight** increases with the Vitality → **The Long Pack** skill perk. Starting weight is intentionally limited: Roland travels on foot.

**Equipment counts toward weight.** Heavier armor provides better protection but increases carry cost. A full plate harness is heavy enough to make consumable management meaningful.

**Quest items weigh nothing.** They are carried by story logic, not backpack physics.

---

## Equipment Condition

All weapons and armor have a **condition** value from 0% (destroyed) to 100% (mint).

**Condition degrades through use:**
- Weapons lose condition with every swing (slow degradation)
- Weapons lose condition faster when used to block (medium)
- Armor loses condition when Roland takes hits (slow per hit, cumulative)

**Effects of degraded condition:**

| Condition | Weapon | Armor |
|---|---|---|
| 100–70% | Full damage | Full protection |
| 70–40% | Slight damage reduction | Slight protection reduction |
| 40–10% | Meaningful damage reduction; power attacks lose impact | Noticeable protection reduction |
| Below 10% | Severe damage penalty; weapon may fail to block | Minimal protection |
| 0% | Still usable but at severe penalty — forces a gear decision | No protection |

**Restoring condition:**
- **Sharpening Kit** → restores weapon sharpness condition (at a grindstone or forge, or as field maintenance)
- **Repair Kit** → restores armor and blunt weapon structural condition

Kits used at a station restore more condition per kit than field application. See `design/CRAFTING.md` for the distinction.

---

## Smithing Tiers

Weapons and armor come in three tiers, determined at the point of creation or acquisition.

| Tier | Damage / Protection | Durability | Availability |
|---|---|---|---|
| **Common** | Baseline | Standard | Starting gear, common loot, cheap vendors |
| **Quality** | +20–30% | Higher | Better vendors, skilled smiths; requires **Quality Work** perk to craft |
| **Masterwork** | +50–60% | Highest | Named smiths only; requires **Master's Work** perk to craft |

Tier is a **fixed property** — it cannot be upgraded through maintenance. A Common sword cannot become a Quality sword by sharpening it. It can only be replaced with a better piece.

**Roland's starting sword** is Common tier, repaired twice. Replacing it in Act I is a minor but real upgrade. A Masterwork weapon in Game One is exceptional and should feel exceptional.

For all specific weapons and armor with their tier requirements and materials, see **`design/ITEM_LIBRARY.md` → Section 2 (Smithable Items)**.

---

## Companion Inventory

Orion and Dagna carry their own gear and consumables. Roland cannot directly command what they use in combat — they make those decisions autonomously. Between fights (at camp or a rest point), Roland can **open a companion's pack** through the dialogue interaction with that companion.

The companion pack screen is a simplified version of Roland's inventory:
- View what they're currently equipped with
- Swap weapons or armor from their pack or Roland's pack
- Restock their consumables (drag from Roland's supply)
- See their equipment condition and decide whether to use a kit

This is not a menu Roland opens mid-combat. It requires physical proximity and a moment of stillness — both of which camp provides.

**Companions do not auto-restock.** If Roland neglects to resupply Orion's bandages, Orion fights without bandages. The game does not quietly refill companion supplies.

---

## Loot and Pickup

**Loot is placed by hand**, not procedurally generated. Every item on a dead enemy or in a chest was put there intentionally. Finding a Quality sword on a specific Ashfallen lieutenant means something.

**Pickup:** Approach the item or container, press E. The game warns if the item would exceed carry weight before adding it.

**Enemy drops:** Enemies drop the gear they visibly wear. An unarmored goblin drops no armor. An Ashfallen in chainmail drops chainmail in degraded condition — they've been fighting in it.

**Container types:**
- **Bodies** — looted after combat; yield gear and carried items
- **Chests** — found in the world; usually locked (lockpick consumed on use, or a key)
- **Caches** — Brotherhood supply points in the Underway and at safe-house junctions; contain specific items Roland can plan around

---

## GDScript and InventoryManager Notes

`InventoryManager.gd` (existing autoload) manages the inventory. Key fields and methods the equipment system requires:

```gdscript
# Item resource fields (add to ItemData.gd):
var smithing_tier: int        # 0 = Common, 1 = Quality, 2 = Masterwork
var condition: float          # 0.0 to 1.0
var weight: float
var item_category: String     # "consumable", "equipment", "quest", "material", "throwable"
var equipment_slot: String    # "weapon", "offhand", "head", "body", "hands", "boots", ""
var quick_slottable: bool

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

The `condition` float is stored per item instance, not per item type. Two identical swords can have different condition values — each pickup creates a new resource instance with its own condition value.
