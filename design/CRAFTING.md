# Crafting System Design

How Roland makes things: potions, throwables, food, and maintained equipment.

> Cross-reference: `design/INVENTORY_AND_EQUIPMENT.md` for item condition and smithing tiers.
> `design/SKILLS_AND_PROGRESSION.md` for Crafting domain skill nodes and quality tiers.
> `design/ITEM_LIBRARY.md` for all craftable recipes, ingredients, and output items.
> `design/NPC_SYSTEM.md` for smith and alchemist NPC setup.

---

## Design Philosophy

**Recipes are knowledge, not menus.** Roland cannot walk up to any station and produce anything. He must have learned the recipe — from a book, a mentor, an old manuscript, or his own experimentation. A player who explores and pays attention to the world will know more recipes than a player who rushes. The recipe list is a record of what Roland has discovered, not a pre-populated catalogue.

**Skill determines quality, not permission.** There are no skill checks that block a recipe. If Roland knows how to make something and has the materials, he can make it. What his Crafting skill determines is how well it turns out. A Novice Roland making a healing draught produces a weak result. A Master Roland making the same draught produces something significantly more potent. Same recipe. Same materials. Different hands.

**Crafting is intentional, not mechanical.** There are no reflex minigames — no timing bars, no button sequences that require dexterity to complete. The act of crafting is a choice of focus: how much care Roland brings to the work. This fits a game about a man who solves problems through attention and understanding.

**No power food.** Cooking manages hunger and rest quality. No meal grants combat bonuses, bonus HP, or stat buffs. Hunger is a survival consideration, not an optimization lever.

---

## The Craft's Intention — How Quality Is Determined

When Roland sits at any crafting station, after selecting a recipe and confirming he has materials, he makes a single choice before committing:

| Intent | Time cost | Quality result |
|---|---|---|
| **Work quickly** | Minimal in-game time | One quality tier below Roland's current skill ceiling |
| **Work with care** | Standard | Roland's current skill ceiling |
| **Work with mastery** | Extended; costs slightly more material | One quality tier above Roland's current skill ceiling — only available at Veteran+ Crafting |

This is not a hidden system — Roland knows what he is doing. The choice is shown as three options before the craft resolves, like a dialogue option. The player always knows what they are trading.

### Quality Tiers

| Tier | Name | Typical effect vs. base |
|---|---|---|
| 1 | **Common** | 70% of base effect |
| 2 | **Good** | 100% of base effect |
| 3 | **Fine** | 130% of base effect |
| 4 | **Exceptional** | 165% of base effect |

Roland's skill ceiling per domain tier:

| Crafting Domain Tier | Default ceiling |
|---|---|
| Novice | Common |
| Trained | Good |
| Veteran | Fine |
| Master | Exceptional |

Working quickly drops one tier below the ceiling. Working with mastery (Veteran+) raises one tier above — up to the cap of Exceptional.

### Ingredient Quality Multiplier

For alchemy, the freshness of organic ingredients affects the output quality regardless of skill:
- Fresh herb + Veteran skill: Fine quality
- Dried herb + Veteran skill: Good quality (one tier below the fresh equivalent)

This is the only non-skill factor in quality. A player who harvests fresh herbs and uses them promptly produces better output than a player who buys dried stock. The game rewards active engagement with the natural world.

---

## Stations

All crafting happens at a physical station in the world. There is no crafting from the inventory screen.

| Station | Location(s) | Produces |
|---|---|---|
| **Alchemist's Still** | Herbalist shops, specific quest locations, Roland's camp (unlocked at Act II) | Potions, draughts, compounds, Wanderer's Seal |
| **Smithing Forge** | Smiths' workshops in settlements | Weapons, armor; weapon/armor maintenance; tier improvement |
| **Grindstone** | Smiths' workshops, some campsites | Weapon sharpening (faster, lower ceiling than forge) |
| **Assembly Table** | Roland's camp (available from Act I), certain safe-houses | Throwables, traps, tools, utility items |
| **Cooking Fire** | Any campfire Roland can interact with, tavern kitchens | Meals; hunger and rest-quality effects |

Roland cannot build new stations from scratch. He uses stations that exist in the world. His camp can have a portable Still and Assembly Table added through story or quest progression.

---

## Alchemy — The Alchemist's Still

### Interaction

Roland sits at the still. The interface shows:
- The recipe (if known), with ingredient list and a brief description in Roland's voice: *"This one needs to steep longer than you think. The bitterroot fights the oil until the heat resolves it."*
- His current ingredient inventory, flagged with freshness state
- The three intent options (Quick / Care / Mastery)

No button sequences. No timing. Roland's competence is in his hands — the player's competence is in knowing the recipe and choosing the right ingredients.

### Recipe Discovery

Roland discovers alchemy recipes through:
- **Documents:** Recipe pages in the Archive restricted section, herbalist notes, old campsite journals, monastery records
- **Mentors:** Herbalists and alchemists at FRIENDLY+ disposition will teach recipes in conversation
- **Purchase:** Specialist vendors sell certain recipe pages (not all are purchasable)
- **Experimentation:** Roland can combine any 1–3 ingredients at the Still without a known recipe. See below for full rules.

Experimental recipes found through play will sometimes not appear in any sold or written source. A curious player will know things a thorough researcher will not.

### Alchemy Experimentation

At the Still, Roland can attempt any ingredient combination without a recipe. The process:

1. **Combine ingredients** — select 1 to 3 ingredients and confirm. The combination is attempted regardless of whether it is a valid recipe.
2. **Result:**
   - **Valid combination:** An **"Unfamiliar Potion"** is produced. The vial has no label and no listed effect. The quantity follows the recipe's normal batch size.
   - **Invalid combination:** A **"Foul Residue"** is produced — a dark, malodorous liquid. The ingredients are consumed. No usable output.
3. **Discovery via consumption:** Roland can consume an Unfamiliar Potion from the inventory (not quick-slot). Over the next 30–60 seconds of in-game time, the effect manifests and Roland narrates what he feels: *"That's the bloodmoss working. This clears a head wound — I can feel it."*
   - If the effect is beneficial, the recipe is permanently added to his Known Recipes list with a note: *"Discovered by trial."*
   - If the combination was partially valid but incorrect, Roland experiences a mild negative effect (brief nausea, -20 endurance for 30 seconds, no lasting harm) and the recipe is NOT added — he knows this combination doesn't work.
4. **Failure memory:** GameState records every failed combination by ingredient pair. Attempting the same failed combination again shows Roland's note: *"I've tried this. It doesn't work."* — and refuses to consume the ingredients.

**Experimentation constraints:**
- Only alchemy (the Still) supports experimentation. Smithing and Assembly Table do not — their recipes are precision processes that require prior knowledge.
- A failed experiment is never dangerous beyond the mild nausea effect. Roland is not poisoned to incapacitation by failed potions.
- The Brainhale Tonic (see `design/ITEM_LIBRARY.md`) does not affect experimentation. The Potion Effectiveness skill perk (Crafting Trained tier) applies to experimentally discovered recipes at the normal quality calculation.
- Consuming an Unfamiliar Potion in combat is Roland's risk to take. Effects are immediate but unidentified — the player is warned by the item name.

### Starting Recipes

Roland begins Game One knowing two recipes: a **Field Herb Tea** (basic healing) and a **Compress Oil** (bandage assistant draught). All others must be found.

---

## Smithing — The Forge

### Weapon and Armor Maintenance

The primary use of the forge in Game One is keeping equipment functional. Weapons and armor degrade with use (see `design/INVENTORY_AND_EQUIPMENT.md`).

At the forge, Roland selects a damaged item and the applicable maintenance recipe. The intent choice (Quick / Care / Mastery) determines how much condition is restored per kit used.

**Grindstone:** For weapon sharpness only. Faster than the forge. Same intent choice. Cannot restore armor or blunt weapon structural condition.

### Smithing New Items

Roland can produce new weapons and armor if:
1. He knows the recipe (learned from a smith NPC or written source)
2. He has the required materials
3. His Smithing sub-skill is at the required tier (controls output quality, not permission to attempt)

**Smithing tier improvement** (Common → Quality, Quality → Masterwork) requires additional materials and a higher Smithing sub-skill tier. See `design/ITEM_LIBRARY.md` for all smithable items and their requirements.

### Field Maintenance

Between station visits, Roland can apply **Sharpening Kits** and **Repair Kits** from inventory without a station. This is field maintenance — less effective than a forge, but available anywhere.
- Field sharpen: restores 20% weapon sharpness condition, no intent choice
- Field repair: restores 15% armor/blunt condition, no intent choice

---

## Assembly Table

Throwables, traps, and utility items. No minigame — pure material management. Select recipe, confirm materials, produce output. Intent choice (Quick / Care / Mastery) affects yield per batch (Quick: 1 fewer unit; Care: base yield; Mastery: 1 additional unit, Veteran+ only).

See `design/ITEM_LIBRARY.md` for all 30 assembly table recipes with materials and outputs.

---

## Cooking Fire

At any campfire Roland can interact with. The simplest crafting system in the game: select recipe, confirm ingredients, produce meal. No intent choice — cooking time and care are abstracted. Meal quality is determined solely by ingredient freshness and recipe tier.

### Hunger

Roland is not killed by hunger. A hungry Roland has:
- Endurance recovery rate reduced by 15%
- Carry weight threshold reduced by 10%

A meal resets hunger for 4–8 in-game hours depending on the dish. Eating before rest (the "well-fed" state) improves rest quality — Roland wakes with slightly more endurance headroom for the first play hour after sleep.

See `design/ITEM_LIBRARY.md` for all 15 cooking recipes with ingredients and effects.

---

## The Wanderer's Seal — Diegetic Save

A sealed wax-stopped vial that creates a **manual save point** when consumed. The name comes from the old pilgrimage tradition in Mira-Thal's Iron Chalice order: travelers would seal a small vial of local water or herb at important waypoints as a personal record of their journey. Roland drinks his to mark the moment.

Crafted at an Alchemist's Still:
- **Still's spirit** (purchased from taverns or distillers; expensive; 1 unit per batch)
- **Waymarker herb** (found throughout the Ashfields and along old pilgrimage routes; cannot be cultivated)

Base output: 1 per batch. Maximum carry: 3. The supply constraint is the design — saves are meaningful because they are scarce.

---

## Recipe Discovery Philosophy

Not all recipes can be purchased. The distribution is deliberate:

| Source | Recipes accessible |
|---|---|
| Vendors (any disposition) | Common potions, basic field maintenance, simple cooking |
| Mentor NPCs (FRIENDLY+) | Intermediate potions, specialist alchemy, Quality smithing |
| Documents (found in world) | Unique recipes, lore-specific compounds, lost techniques |
| Experimentation | A small set of recipes not documented anywhere; found only by trying |
| Quest rewards | Specific powerful recipes given by named characters as rewards |

A player who completes all side quests and reaches TRUSTED with key NPCs will know more recipes than one who rushes the main story. The recipe list is a measure of how thoroughly Roland has engaged with the world.

---

## GDScript Integration Notes

### Station Interaction

```gdscript
# Each crafting station is a world object with InteractArea (Area3D).
# On E-press:
func _on_interact():
    var station_type: String = "alchemy_still"  # "forge", "grindstone", "assembly", "fire"
    CraftingUI.open(station_type, self)
```

### Recipe Data

```gdscript
class_name RecipeData
extends Resource

@export var recipe_id: String
@export var station_type: String
@export var display_name: String
@export var roland_note: String             # Shown at the station in Roland's voice
@export var ingredients: Array[Dictionary]  # [{item_id, quantity, freshness_min}]
@export var output_item_id: String
@export var base_output_quantity: int = 1
@export var min_crafting_subskill: int = 0  # 0=none, 1=Journeyman, 2=Skilled, 3=Expert
                                             # Controls quality ceiling, not access
```

### Quality Calculation

```gdscript
func calculate_output_quality(subskill_tier: int, intent: String, freshness: float) -> String:
    # subskill_tier: 0=Apprentice, 1=Journeyman, 2=Skilled, 3=Expert
    # intent: "quick", "care", "mastery"
    # freshness: 0.0–1.0 (ingredient average)

    var base_tier: int = subskill_tier  # 0=Common, 1=Good, 2=Fine, 3=Exceptional
    var adjusted: int = base_tier

    if intent == "quick":
        adjusted = max(0, base_tier - 1)
    elif intent == "mastery" and subskill_tier >= 2:
        adjusted = min(3, base_tier + 1)

    # Freshness penalty (alchemy only): dried herbs reduce one tier
    if freshness < 0.6:
        adjusted = max(0, adjusted - 1)

    const QUALITY_NAMES = ["Common", "Good", "Fine", "Exceptional"]
    return QUALITY_NAMES[adjusted]
```

### Known Recipes

```gdscript
# In GameState.gd
func unlock_recipe(recipe_id: String) -> void:
    if recipe_id not in known_recipes:
        known_recipes.append(recipe_id)
        SaveNotification.show_journal_update("Recipe learned: " + RecipeDatabase.get_name(recipe_id))

func knows_recipe(recipe_id: String) -> bool:
    return recipe_id in known_recipes
```
