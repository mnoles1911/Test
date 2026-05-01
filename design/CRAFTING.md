# Crafting System Design

How Roland makes things: potions, throwables, food, and maintained equipment.

> Cross-reference: `design/INVENTORY_AND_EQUIPMENT.md` for item condition and smithing tiers.
> `design/SKILLS_AND_PROGRESSION.md` for Crafting domain skill nodes and perk effects.
> `design/NPC_SYSTEM.md` for smith and alchemist NPC setup.

---

## Design Philosophy

**Crafting is physical work, not menu navigation.** Every station has a minigame — short, learnable, with quality determined by execution. A skilled player who understands the process produces better results than a player mashing through it. Skill in the Crafting domain makes the minigame easier and the output better, but it does not eliminate player execution.

**Recipes are discovered, not purchased from menus.** Roland finds recipes by reading documents, talking to knowledgeable NPCs, and — for some combinations — experimenting. The recipe list is not pre-populated. Trying unlisted ingredient combinations at a station is always possible and sometimes reveals something.

**No power food.** Cooking produces meals that manage hunger and stamina recovery. No meal gives Roland bonus attack damage or extra HP. The game does not have a cooking-for-combat-advantage system. Hunger and rest are survival mechanics, not optimization levers.

**Condition is the driver.** Equipment degrades with use. The primary motivation for engaging with smithing is not "make powerful gear" — it is "keep existing gear from falling apart." Crafting is maintenance first, improvement second.

---

## Stations

All crafting happens at a physical station in the world. There is no crafting from the inventory screen. Each station type produces a different category of item.

| Station | Location(s) | Produces |
|---|---|---|
| **Alchemy Bench** | Herbalist shops, Roland's camp (after upgrade), certain quest locations | Potions, draughts, Saviour Schnapps |
| **Brewing Table** | Tavern kitchens, camp | Saviour Schnapps (alternative; same output, different minigame feel) |
| **Smithing Forge** | Smiths' workshops in settlements | Weapon/armor maintenance; tier improvement (Quality/Masterwork with skill) |
| **Grindstone** | Smiths' workshops, some outdoor camps | Weapon sharpening; faster than forge, lower ceiling |
| **Assembly Table** | Roland's camp, certain safe-houses | Throwables: fire bombs, smoke grenades, oil flasks, caltrops |
| **Cooking Fire** | Any campfire Roland can interact with; tavern kitchens | Meals: hunger recovery, rest-quality bonuses |

Roland cannot build new stations. He uses stations that exist in the world and, for camp, can unlock a portable alchemy bench and assembly table through story progression.

---

## Alchemy

### The Station

An alchemy bench has four interactive elements:
- **Cauldron** — where ingredients are combined and cooked
- **Mortar and Pestle** — grinds dry ingredients before they go in
- **Hourglass** — times the boiling phase; rotate to start the countdown
- **Bellows** — controls heat; pump to raise temperature, stop to let it drop

The player interacts with each element in sequence. The minigame is not random — the same inputs produce the same result every time. A player who has done this recipe before should feel competent.

### The Minigame — Step by Step

1. **Open the recipe book** — Roland reads the recipe aloud (first time only; after that it's available at the bench as a prompt).

2. **Grind ingredients that require it** — at the mortar. A brief press-and-hold rhythmic input: press the button in time with the grind animation. Three good presses = well-ground; missing one = coarsely ground (quality penalty).

3. **Add base liquid to cauldron** — automatic; Roland tips the vial in.

4. **Add ingredients in sequence** — some go in at the start, some after the liquid reaches temperature. The recipe tells you when. Adding out of order produces a flawed result rather than a failure.

5. **Flip the hourglass** — starts the boil timer. A visual effect shows the cauldron reaching temperature.

6. **Pump the bellows** — during the boil, the heat indicator climbs and falls. Keep it in the green zone by pumping when it drops, stopping when it rises. Too hot or too cold during this phase degrades quality.

7. **Add finishing ingredients** (if any) — some recipes call for a herb added at the last moment before the timer runs.

8. **Decant** — when the hourglass empties, Roland pours the result into a vial. The number of vials produced and their quality is displayed.

### Quality

| Execution | Quality | Effect |
|---|---|---|
| Rushed (all steps skipped or done poorly) | **Weak** | 60% of base effect |
| Standard (most steps done correctly) | **Normal** | 100% of base effect |
| Careful (all steps done well, timing correct) | **Strong** | 140% of base effect |
| Flawless (all steps perfect; only achievable with Veteran+ Crafting) | **Roland's Reserve** | 175% of base effect; labeled with Roland's initials |

The **Potion Effectiveness** crafting perk adds 20% to all tiers — it does not unlock a new tier, it makes every tier better.

### Ingredient Freshness

Herbs and organic ingredients degrade after harvest. A fresh-picked herb is at 100% potency. Every 2 in-game days without preservation, it drops one quality tier.

| State | Potency | Notes |
|---|---|---|
| Fresh | 100% | Picked within 2 days |
| Slightly Dried | 85% | 3–5 days |
| Dried | 70% | 6+ days; stable, does not degrade further |
| Spoiled | 30% | Overripe organic ingredients (applies to food-adjacent items) |

**Drying deliberately:** Roland can dry herbs at any campfire by interacting with them in inventory and selecting "Dry." This stops degradation at the Dried state — useful for preserving a large harvest. The trade-off: dried herbs permanently cap potency at 70% unless the **Preservation** perk is active (which raises the Dried ceiling to 85%).

**Purchased herbs** from a herbalist are typically Dried (stable, not fresh-picked). Roland can source fresh herbs by harvesting himself, or by asking a herbalist NPC to sell him same-day stock (relationship-gated; FRIENDLY+ disposition required).

### Recipes and Discovery

Roland starts knowing two recipes: a basic healing herb tea and a basic bandage-assist draught. All other recipes must be found.

**Recipe sources:**
- Reading documents in the world (Archive restricted section, herbalist notes, old campsite journals)
- Talking to alchemists and herbalists at TRUSTED disposition
- Purchasing recipe pages from specialist vendors (not all recipes are purchasable — some exist only in documents)
- **Experimental discovery:** Combining two ingredients at the bench without a known recipe has a chance of producing a usable result. If it does, Roland notes the combination in his journal. Not all combinations work. Dangerous combinations produce a smoke burst and waste the ingredients without harming Roland.

The experimental discovery system means a curious player can find recipes that a completionist player researching only vendors and documents will miss.

---

## Throwables

Assembled at the **Assembly Table**. No timing minigame — throwable crafting is pure resource management. The player selects a recipe, confirms they have materials, and Roland assembles the batch.

**Why no minigame:** Throwables are tactical consumables assembled between fights, not precision tools. The design decision is that the tactical thinking happens in how you use them, not how you make them. The Assembly Table is a logistics station, not a performance station.

**Throwable Yield perk:** Doubles output per batch. No other changes.

### Throwable Recipes

| Item | Primary Material | Secondary | Batch Size (base) |
|---|---|---|---|
| Fire Bomb | Pitch flask | Dried moss | 2 |
| Oil Flask | Lamp oil | Cloth scraps | 3 |
| Smoke Grenade | Sulphur | Charcoal | 2 |
| Caltrops | Iron scraps | — | 4 |

Materials are bought from vendors, looted from camps, or found in environments (lamp oil from wall sconces in abandoned buildings, iron scraps from destroyed equipment).

---

## Smithing and Equipment Maintenance

### Sharpening (Grindstone)

The fastest form of maintenance. Costs one **Sharpening Kit** per use.

**Minigame:** A short back-and-forth rhythm on the grindstone wheel. Keep the blade in contact with the wheel by following a simple left-right prompt. Missing contacts wastes kit material without improving condition.

- Base result: restores weapon sharpness (damage condition) by 35–50%
- **Extended Sharpen** perk: same kit, restores 60–70%
- Cannot restore armor. Cannot improve smithing tier.

Grindstones exist at smiths' workshops and some outdoor campsites. Roland cannot grind on the road.

### Forge Maintenance

Full weapon and armor repair. Costs **Repair Kits** (for blunt/armor) or **Sharpening Kits** (for bladed weapons, at forge; deeper repair than grindstone).

**Minigame:** Three phases.
1. **Heat** — watch the color indicator on the metal. Strike (press button) when the metal is bright orange, not red-hot or cooling-grey. Miss the window: wasted fuel, partial heating.
2. **Hammer** — a directional prompt sequence. Match the shown directions to shape the metal correctly. 4–6 prompts per piece. Each miss adds a small flaw.
3. **Quench** — dip the piece at the right moment (timed). Early: brittle (quality penalty). Late: soft (condition not fully restored). On-time: full restoration.

**Smithing tier improvement** (Common → Quality, Quality → Masterwork) requires:
- The appropriate Crafting perk unlocked (**Quality Smithing Unlocked** or **Masterwork Smithing Unlocked**)
- Additional rare materials (quality iron, masterwork alloy — purchased from or commissioned through skilled smiths)
- A full successful forge sequence with no missed prompts

Tier improvement is expensive and meaningful. Roland cannot improve a piece's tier on the road — only at a capable smith's forge.

### Camp Maintenance

Between fights, Roland can apply **Sharpening Kits** and **Repair Kits** directly from inventory without a station. This is field maintenance — slower and less effective than a grindstone or forge, but available anywhere.

- Field sharpening: restores 20% weapon sharpness condition
- Field repair: restores 15% armor/blunt condition

No minigame. Just the cost of a kit and a brief animation.

---

## Cooking

At any campfire Roland can interact with, or at a tavern kitchen. Simple and fast — no multi-step minigame.

**What cooking does:**
- Prepares meals from raw ingredients
- Cooked meals recover more hunger than raw food
- A good meal before rest improves rest quality (Roland wakes with slightly more endurance headroom for the first hour of play after sleep)

**What cooking does not do:**
- Grant combat buffs
- Provide bonus HP
- Give Roland any mechanical advantage beyond the hunger and rest effects above

### Hunger

Roland is not killed by hunger. He is slowed. A hungry Roland has:
- Endurance recovery rate reduced by 15%
- Carry weight threshold reduced by 10%

This is noticeable in a hard fight but not catastrophic. The game does not punish forgetting to eat — it nudges toward eating as a reasonable part of a day.

A meal resets hunger for 4–8 in-game hours depending on the dish.

### Meal Quality

| Preparation | Effect |
|---|---|
| Raw food | Minimal hunger recovery; some foods cannot be eaten raw |
| Basic cooked | Standard hunger recovery |
| Well-prepared | 120% hunger recovery; bonus rest quality if eaten before sleeping |

---

## Saviour Schnapps (Diegetic Save)

Produces a **manual save** when consumed. The animation is the same as drinking a potion — the game saves during the drinking action. Roland looks slightly glazed afterward (brief visual effect).

Crafted at an Alchemy Bench or Brewing Table using:
- **Base spirit** (bought from taverns or distillers — expensive)
- **Saviour herb** (found in the Ashfields region; rare; cannot be cultivated)

Base production: 1 per batch. **Material Efficiency** perk: 2 per batch. Always Standard quality — quality is irrelevant to the save function.

Roland can carry up to 3. They stack but do not stack beyond 3 in inventory. The supply constraint is the design — diegetic saves are meaningful because they are limited.

---

## GDScript Integration Notes

### Station Interaction

Each crafting station is a world object with `InteractArea (Area3D)`. On E-press, the station calls:

```gdscript
func _on_interact():
    var station_type: String = "alchemy_bench"  # or "forge", "grindstone", etc.
    CraftingUI.open(station_type)
```

`CraftingUI.gd` (not yet built) reads the player's known recipes from `GameState.get_known_recipes()` and filters by station type.

### Recipe Data

Recipes are stored as a custom Resource class `RecipeData.gd`:

```gdscript
class_name RecipeData
extends Resource

@export var recipe_id: String          # "healing_potion_basic"
@export var station_type: String       # "alchemy_bench"
@export var ingredients: Array[Dictionary]  # [{item_id, quantity, freshness_min}]
@export var output_item_id: String
@export var output_quantity: int = 1
@export var requires_crafting_perk: String = ""  # "" = no perk required
```

### Known Recipes

```gdscript
# In GameState.gd
func unlock_recipe(recipe_id: String) -> void:
    if not recipe_id in known_recipes:
        known_recipes.append(recipe_id)
        SaveNotification.show("Recipe recorded: " + recipe_id)

func knows_recipe(recipe_id: String) -> bool:
    return recipe_id in known_recipes
```

### Ingredient Freshness Tracking

Herbs with a freshness component use an additional field in the item's inventory entry:

```gdscript
# InventoryManager item entry structure (partial):
{
    "item_id": "herb_silverleaf",
    "quantity": 3,
    "freshness": 1.0,       # 0.0 = spoiled, 1.0 = fresh
    "harvest_day": 42       # world day when picked; compared against WorldClock.current_day
}
```

Freshness is recalculated when the item is used or when the player opens the inventory, comparing `WorldClock.current_day` against `harvest_day`. Vendors' herbs are initialized with `harvest_day` set several days in the past (typically 5–7).

### Quality Calculation

```gdscript
func calculate_craft_quality(minigame_score: float, crafting_tier: int) -> String:
    # minigame_score: 0.0 (failed all steps) to 1.0 (perfect)
    # crafting_tier: 0 = Novice, 1 = Trained, 2 = Veteran, 3 = Master
    var adjusted_score = minigame_score + (crafting_tier * 0.08)
    if adjusted_score >= 0.95:
        return "rolands_reserve"
    elif adjusted_score >= 0.75:
        return "strong"
    elif adjusted_score >= 0.45:
        return "normal"
    else:
        return "weak"
```
