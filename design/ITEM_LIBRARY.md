# Item Library — Master Reference

All craftable items, their ingredients, and the input materials used across the crafting system.

> This document is the canonical reference for recipe content. Design philosophy and station mechanics live in `design/CRAFTING.md`. Skill quality effects and perk interactions live in `design/SKILLS_AND_PROGRESSION.md`. Equipment stats, condition, and smithing tiers live in `design/INVENTORY_AND_EQUIPMENT.md`.

---

## How to Read This Document

**Quality column** shows the base effect at Good quality (Roland's default at Trained skill). Fine and Exceptional scale up per `design/CRAFTING.md` quality tier table.

**Recipe Required** — Roland must learn the recipe before he can craft the item. Starting recipes are noted. All others must be discovered in the world.

---

## Raw Materials

All crafting input materials. This is the master list — cross-reference when designing world placement and NPC vendor inventories.

### Herbs and Organic (Alchemy)

| Material | Fresh shelf life | Dried potency | Where found |
|---|---|---|---|
| **Silverleaf** | 3 days | 70% | Aldenholt market; riverbanks throughout Act I–II |
| **Bitterroot** | 5 days | 70% | Damp forest floors; Aelorin Greatwood abundant |
| **Hearthwort** | 2 days | 70% | Near campfires; grows in ash-warmed soil; Ashfields common |
| **Coldmoss** | 7 days | 75% | Rocky hillsides; Spine of Mira; does not wilt easily |
| **Ashbloom** | 1 day | 60% | Ashfields only; degrades fast even when dried |
| **Greywillow bark** | 10 days | 80% | Old-growth forests; Aelorin Greatwood; Caer Brannoch hills |
| **Ironweed** | 4 days | 70% | Open fields; roadside everywhere; plentiful and cheap |
| **Nightshade cluster** | 2 days | 65% | Shaded ruins, cellars; dangerous to handle carelessly |
| **Aelorin blossom** | 1 day | 50% | Lirien-Thal interior only; cannot be cultivated outside |
| **Waymarker herb** | 6 days | 75% | Ashfields pilgrimage routes; old Iron Chalice wayside markers |
| **Thornwax** | 8 days | 80% | Rocky Spine terrain; grows in cracks |
| **River clay** | N/A | N/A | Any riverbank; used as a binding agent |
| **Cave fungus** | 3 days | 65% | Underground; Underway; Spine cave systems |
| **Ashstone dust** | N/A | N/A | Ashfields surface; ground from ashstone rock |
| **Bloodmoss** | 1 day | 55% | Found near old battlefields and Ashfallen territory |
| **Emberroot** | 4 days | 70% | Volcanic margins near Drûn-Khazad; rare in Game One |
| **Dragonwort** | 3 days | 70% | Coastal cliffs, Copper Isles; salt-air tolerant |
| **Silkweed fiber** | N/A | N/A | Woven from silkweed plant stalks; dry good |
| **Preserved fat** | N/A | N/A | Rendered from game animals; purchased from butchers |
| **Still's spirit** | N/A | N/A | Distilled grain spirit; purchased from taverns and distillers; expensive |

### Metals and Minerals

| Material | Source | Use |
|---|---|---|
| **Iron ore** | Mined; purchased from smiths | Base metal for all iron items |
| **Iron ingot** | Smelted from iron ore (2:1); purchased | Primary smithing input |
| **Steel ingot** | Iron ingot + coal-fired flux; purchased from smiths | Quality and Masterwork weapons/armor |
| **Copper ingot** | Mined in Copper Isles; purchased | Fittings, decorative work, some tools |
| **Coal** | Mined; purchased from smiths | Forge fuel; flux component |
| **Flux powder** | Purchased from smiths; sometimes found in ruins | Combines with iron to produce steel |
| **Whetstone** | Purchased; found in caves and ruins | Sharpening kits; grindstone consumable |
| **Pitch** | Refined from pine resin; purchased | Fire bombs, oil flasks, torches |
| **Sulphur** | Volcanic margins, Ashfields surface | Smoke grenades, some explosives |
| **Saltpeter** | Dry caves; purchased from alchemists | Flash powder, some throwable recipes |

### Textiles and Organics (Assembly)

| Material | Source | Use |
|---|---|---|
| **Linen cloth** | Purchased; looted from camps | Bandages, wrappings, pouches |
| **Heavy canvas** | Purchased from merchants | Sacks, assembly pouches, waterproof wrapping |
| **Leather strip** | Cut from hides; purchased from tanners | Armor repair, weapon wraps, bindings |
| **Cured hide** | Purchased from tanners; some combat loot | Padded armor components |
| **Rope** | Purchased; found in many locations | Assembly components, traps, climbing |
| **Wax** | Purchased from beekeepers and chandlers | Waterproofing, seals, fire starters |
| **Charcoal** | Made at campfire from wood; purchased | Smoke grenades, cooking, forge fuel |
| **Iron scraps** | Combat loot from armored enemies; smiths' offcuts | Assembly items requiring small metal parts |
| **Hardwood dowel** | Cut from hardwood; purchased from carpenters | Structural assembly items |

### Food Ingredients (Cooking)

| Material | Source |
|---|---|
| **Trail bread** | Purchased; baked at cooking fire with flour + water |
| **Dried oats** | Purchased from grain merchants |
| **Salted pork** | Purchased; common and cheap |
| **Salted fish** | Purchased near water; some loot |
| **Fresh river fish** | Caught at riverbanks (interact with fishing spots) |
| **Root vegetables** | Purchased; found at abandoned farmsteads |
| **Wild mushrooms** | Foraged from forest floors |
| **Game bird** | Hunted (interact with bird snare trap) |
| **Venison** | Hunted from deer; some quest/camp loot |
| **Flour** | Purchased from grain merchants |
| **Olive oil** | Purchased; primarily Solgrade region |
| **Salt** | Purchased; universal; cheap |
| **Dried fruit** | Purchased; preserves well; Solgrade plentiful |
| **Honey** | Purchased from beekeepers; rare find in ruins |
| **Spiced wine** | Purchased from taverns |
| **Hearth herbs** | Hearthwort + ironweed combination; foraged or purchased |

---

## Section 1 — Potions (40 recipes)

All crafted at the **Alchemist's Still** unless otherwise noted.
Base effect column assumes **Good quality** (Trained skill, "Work with care").

### Healing

| # | Name | Base Effect (Good) | Primary Ingredient | Secondary | Tertiary | Roland's Note |
|---|---|---|---|---|---|---|
| 1 | **Field Herb Tea** *(starting recipe)* | Restore 20 HP | Silverleaf (fresh/dried) | Water | — | *"What every traveler should know. It's not much but it's reliable."* |
| 2 | **Healer's Remedy** | Restore 45 HP | Silverleaf (2, fresh) | Hearthwort | River clay | *"Takes longer to prepare than the tea. Worth it."* |
| 3 | **Deep Draught** | Restore 80 HP | Silverleaf (3, fresh) | Greywillow bark | Bitterroot | *"The bark is the hard part. Get it wrong and it's just bitter water."* |
| 4 | **Ironheart Tonic** | Restore 60 HP; prevents HP dropping below 5% for 30 seconds | Hearthwort (2) | Ironweed | Preserved fat | *"Old soldiers' recipe. It doesn't heal you, it stalls the dying."* |
| 5 | **Boneknit Compound** | Accelerates wound recovery (HP-from-wounds heals twice as fast after next rest) | Coldmoss | Greywillow bark | Still's spirit | *"Smells like pine and regret. Works regardless."* |
| 6 | **Slow Release** | Restore 15 HP per minute for 5 minutes (75 HP total over time) | Bitterroot (2) | Silverleaf | River clay | *"The long brew. You have to be patient with the heat."* |
| 7 | **Field Surgeon's Oil** *(compress assist)* | Bandage heals 50% more HP when applied after this | Silverleaf | Silkweed fiber | Preserved fat | *"Apply the oil before the bandage goes on. Not after."* |
| 8 | **Sorrow's End** | Restore 120 HP; clears wound status entirely | Aelorin blossom (2) | Silverleaf (2) | Still's spirit | *"I don't know what the Aelorin put in these. I'm not sure I want to."* |

### Endurance and Stamina

| # | Name | Base Effect (Good) | Primary Ingredient | Secondary | Tertiary | Roland's Note |
|---|---|---|---|---|---|---|
| 9 | **Endurance Draught** *(starting recipe)* | Restore 50% endurance | Hearthwort | Ironweed | — | *"The herbalists make a version of this. This is the purer form."* |
| 10 | **Ironbody Tonic** | Endurance recovers 40% faster for 10 minutes | Hearthwort (2) | Thornwax | Preserved fat | *"The thorn flavor stays in your mouth. Proves it's working."* |
| 11 | **Wakefulness Tonic** | Removes fatigue penalty; restores endurance as if fully rested (without actual sleep) | Hearthwort | Coldmoss | Ashbloom | *"Borrowed time. Your body will collect the debt later."* |
| 12 | **Rootbrew Tea** | Removes hunger penalty for 6 hours | Root vegetables (dried) | Ironweed | Water | *"Tastes like nothing. Does the job."* |

### Resistance and Defense

| # | Name | Base Effect (Good) | Primary Ingredient | Secondary | Tertiary | Roland's Note |
|---|---|---|---|---|---|---|
| 13 | **Antidote** | Clears poison status; prevents re-poisoning for 2 hours | Bitterroot (2) | Ironweed | River clay | *"Bitterroot neutralizes most poisons by being more unpleasant than the poison itself."* |
| 14 | **Ironblood Tonic** | Stops bleeding; reduces ongoing HP loss from wounds by 75% | Coldmoss | Silkweed fiber | Ironweed | *"The coldmoss constricts. I don't know the mechanism. I know it works."* |
| 15 | **Stonehide Paste** | Topical; applies to armor. Armor absorbs 15% more damage for 1 hour | Thornwax (2) | River clay | Coal dust | *"Rub it into the leather before you dress. It stiffens the grain."* |
| 16 | **Warmfire Elixir** | Cold resistance for 4 hours (reduces endurance cost in cold environments) | Hearthwort (2) | Ashbloom | Preserved fat | *"The Ashfields in winter are not hospitable. This helps."* |
| 17 | **Ashbane Tincture** | Reduces Ashfallen corruption effects (quest-relevant; certain Ashfallen attacks cause temporary stat penalties) | Ashstone dust (2) | Bloodmoss | Ironweed | *"Something in the ash responds to its own kind. Goes against it."* |
| 18 | **Spiritbane Essence** | Weakens Hollow enemies (Mordvar-adjacent); increases damage dealt to Hollow by 20% for 1 combat | Ashbloom | Cave fungus | Bloodmoss | *"The Aelorin herbalist explained this once. I took notes I'm not sure I understand."* |
| 19 | **Nullweave Tincture** | Resists magical alteration effects for 2 hours (relevant in Game Two; minor use in Game One) | Aelorin blossom | Coldmoss | Thornwax | *"Rare. The blossom is the hard part."* |

### Utility and Investigation

| # | Name | Base Effect (Good) | Primary Ingredient | Secondary | Tertiary | Roland's Note |
|---|---|---|---|---|---|---|
| 20 | **Nighteye Tonic** | Improved low-light vision for 1 hour (darker areas become visible) | Cave fungus (2) | Bitterroot | Still's spirit | *"The Underway was how I found this recipe. The fungus sees in the dark."* |
| 21 | **Bitterwort Draught** | Reveals if food or drink has been poisoned before consuming | Bitterroot (2) | Ironweed | River clay | *"Turns your tongue cold if the cup is wrong. A useful party trick."* |
| 22 | **Trackhound Brew** | Improves Roland's awareness of nearby NPCs through walls/terrain (awareness radius +30%) for 30 minutes | Cave fungus | Coldmoss | Ashstone dust | *"I'm not sure what this does to the inner ear. Something."* |
| 23 | **Veilbreaker Essence** | Reveals hidden things: concealed doors, invisible markings, illusion effects (quest-specific use) | Aelorin blossom (2) | Ashbloom | Still's spirit | *"The Aelorin showed me this. It reveals what the forest wants hidden."* |
| 24 | **Truth in the Cup** | Lowers NPC resistance to honest conversation; unlocks one additional dialogue option per use (consumed, quest contexts only) | Dragonwort (2) | Greywillow bark | Still's spirit | *"It doesn't make them tell the truth. It makes them want to."* |
| 25 | **Clearwater Tonic** | Purifies contaminated water sources (quest/environmental) | Ironweed (2) | Coldmoss | River clay | *"Practical. Not exciting."* |

### Social and Charisma

| # | Name | Base Effect (Good) | Primary Ingredient | Secondary | Tertiary | Roland's Note |
|---|---|---|---|---|---|---|
| 26 | **Silvertongue Draught** | +15 temporary Charisma for 1 hour (effects as Charisma rules in SKILLS_AND_PROGRESSION.md) | Dragonwort | Silverleaf | Honey | *"Tastes good. Works better than it should."* |
| 27 | **Steadfast Brew** | Resists fear and intimidation dialogue checks for 2 hours; Roland cannot be shaken into retreating from a conversation | Hearthwort | Ironweed (2) | Thornwax | *"For the conversations I know are going to be difficult."* |
| 28 | **Ironwill Tonic** | Resists interrogation and psychological pressure (story-specific use; certain scenes have a resistance check) | Thornwax (2) | Coldmoss | Still's spirit | *"For situations where saying nothing is the most important thing I can do."* |

### Weapon Coatings

Applied to a weapon from inventory; effect lasts for one combat encounter or 10 minutes.

| # | Name | Base Effect (Good) | Primary Ingredient | Secondary | Tertiary | Roland's Note |
|---|---|---|---|---|---|---|
| 29 | **Embercoat Oil** | Weapon deals fire damage on hit; enemies that take fire damage lose 5% armor efficiency for 10 seconds | Ashbloom (2) | Pitch | Preserved fat | *"Apply with the cloth, not your hand."* |
| 30 | **Frostcoat Oil** | Weapon slows enemy movement on hit by 20% for 5 seconds | Coldmoss (2) | Thornwax | Preserved fat | *"Reduces their speed. Useful against wolves."* |
| 31 | **Venombane Coating** | Weapon inflicts mild poison on hit; 5 HP per minute for 3 minutes | Nightshade cluster (2) | Preserved fat | Still's spirit | *"Handle with cloth. Learned that the hard way."* |
| 32 | **Brightcoat** | Weapon burns brightly on swing; blinds enemies for 2 seconds when hit (one use per coating) | Ashstone dust | Sulphur | Preserved fat | *"Mostly a distraction. A good one."* |

### Quest and Narrative Items

Crafted items used in specific story contexts, not general utility.

| # | Name | Base Effect (Good) | Primary Ingredient | Secondary | Tertiary | Roland's Note |
|---|---|---|---|---|---|---|
| 33 | **Deepsleep Draught** | Renders a consenting NPC unconscious for 8 hours (medical/story use; cannot be used offensively in normal combat) | Nightshade cluster | Greywillow bark | Still's spirit | *"Used by field surgeons. One of the things I learned that I hoped I'd never need."* |
| 34 | **Last Rites Compound** | Preserves a body for 3 in-game days (quest item; certain story scenes require examining a body before it degrades) | Coldmoss (2) | Ashstone dust | River clay | *"Old Chalice practice. They had good reasons for it."* |
| 35 | **Mindclearing Draught** | Clears all temporary negative status effects (poison, bleeding, fear, cold, fatigue — everything active) | Bitterroot | Ironweed | Silverleaf | *"Clears the board. Sometimes that's what you need."* |

### Special

| # | Name | Base Effect | Primary Ingredient | Secondary | Tertiary | Roland's Note |
|---|---|---|---|---|---|---|
| 36 | **Wanderer's Seal** | Creates a manual save point when consumed | Still's spirit (1) | Waymarker herb | — | *"Old pilgrimage practice. Mark the moment before you walk into what comes next."* |
| 37 | **Lethe's Draught** | Resets all perk allocations; Roland forgets specific techniques and may relearn them differently | Still's spirit (2) | Emberroot | Aelorin blossom | *"The river of forgetting. Some things are better unlearned."* |
| 38 | **Brainhale Tonic** | Improves investigation: Roland can examine 2 additional objects in a scene before his attention saturates (story effect; certain scenes have an examination cap) | Cave fungus (2) | Coldmoss | Bitterroot | *"My head gets clearer. I notice more. Probably unnatural."* |
| 39 | **The Healer's Reserve** | As "Slow Release" but also removes one wound stack entirely | Bitterroot (2) | Silverleaf (2) | Still's spirit | *"The full compound. I don't make this unless I expect a bad day."* |
| 40 | **Aelorin Essence** | Restore 100 HP; cure all negative statuses; side effect: Roland hears the forest for 30 minutes (cosmetic — ambient dialogue changes) | Aelorin blossom (3) | Silverleaf (2) | Waymarker herb | *"Whatever they put in this, it's old. It doesn't feel like medicine. It feels like remembering something."* |

---

## Section 2 — Smithable Items (40 recipes)

All crafted at the **Smithing Forge** unless noted. Quality tier affects damage (weapons) or protection (armor).

### Weapons (15)

| # | Name | Smithing Tier | Primary Material | Secondary | Tertiary | Base Damage (Good quality) | Notes |
|---|---|---|---|---|---|---|---|
| 1 | **Iron Shortsword** | Common | Iron ingot (3) | Coal (2) | — | 18 | Starting pattern; first recipe Roland knows |
| 2 | **Soldier's Arming Sword** | Common | Iron ingot (4) | Coal (2) | Leather strip | 22 | Standard military issue; Aldenholt Guard pattern |
| 3 | **Chalice Knight Sword** | Quality | Steel ingot (3) | Iron ingot (1) | Leather strip (2) | 32 | Iron Chalice order pattern; longer blade, one-handed; recipe from Ser Brenn |
| 4 | **Spine-Forged Blade** | Quality | Steel ingot (2) | Iron ingot (2) | Coal (3) | 29 | Forged from high-carbon Spine iron; holds an edge well; recipe from a Spine-region smith |
| 5 | **Vosskaran Dirk** | Common | Iron ingot (2) | Coal (1) | — | 14 | Double-edged fighting knife; Vosskaran military design; close-quarters |
| 6 | **Hunting Knife** | Common | Iron ingot (2) | Coal (1) | Leather strip | 11 | Utility/combat; can be used as a tool for skinning (unlocks certain ingredient harvesting) |
| 7 | **Khorumzad Waraxe** | Quality | Steel ingot (2) | Iron ingot (2) | Hardwood dowel | 30 | Dwarven-pattern fighting axe; heavy; no combo chaining but power attacks break blocks reliably; recipe from a Khorumzad contact in Act III |
| 8 | **Copper Isle Boarding Axe** | Common | Iron ingot (3) | Hardwood dowel | Coal (2) | 20 | Designed for close ship-deck fighting; short handle, broad head; recipe from Caer Brannoch |
| 9 | **Iron Mace** | Common | Iron ingot (4) | Hardwood dowel | Coal (2) | 17 | Blunt; effective against armored enemies; ignores 20% of armor reduction |
| 10 | **Steel Mace** | Quality | Steel ingot (3) | Iron ingot (1) | Hardwood dowel | 26 | As iron mace; ignores 30% armor reduction |
| 11 | **Irontrack Hammer** | Quality | Steel ingot (3) | Iron ingot (2) | Hardwood dowel (2) | 28 | Dwarven construction-forged pattern; heavy striking head; Dagna recognizes the design (companion comment) |
| 12 | **Ashfields Cleaver** | Common | Iron ingot (3) | Coal (2) | — | 19 | Broad chopping blade; heavier than a shortsword; useful in ash terrain where sword points catch |
| 13 | **Braided Chain Flail** | Quality | Steel ingot (2) | Iron ingot (2) | Iron scraps (4) | 27 | Chain-and-weight; bypasses block completely but has slow recovery; recipe from a mercenary contact |
| 14 | **Thornback Blade** | Masterwork | Steel ingot (4) | Flux powder (2) | Coal (3) | 40 | Serrated spine; inflicts bleeding on hit; recipe from a master smith in Act III |
| 15 | **The Ashford Blade** | Masterwork | Steel ingot (4) | Copper ingot (1) | Flux powder (2) | 38 | Roland's family pattern; a reconstruction of the blade described in backstory documents; recipe assembled from Archive fragments |

### Armor (15)

| # | Name | Smithing Tier | Primary Material | Secondary | Tertiary | Base Protection (Good quality) | Notes |
|---|---|---|---|---|---|---|---|
| 16 | **Padded Coif** | Common | Linen cloth (4) | Cured hide (2) | — | 8 | Head protection; lightweight; full mobility |
| 17 | **Iron Helm** | Common | Iron ingot (3) | Coal (2) | Leather strip | 18 | Standard closed helm; significant head protection; slight visibility reduction |
| 18 | **Steel Helm** | Quality | Steel ingot (2) | Iron ingot (1) | Coal (2) | 26 | Quality iron helm; better protection, same visibility trade-off |
| 19 | **Studded Leather Jerkin** | Common | Cured hide (4) | Iron scraps (6) | Linen cloth (2) | 15 | Body armor; lightweight; full mobility; no carry penalty |
| 20 | **Chainmail Hauberk** | Quality | Iron ingot (5) | Coal (3) | — | 28 | Body protection; heavier; provides protection vs. cuts; reduced vs. blunt |
| 21 | **Iron Breastplate** | Common | Iron ingot (5) | Coal (3) | — | 22 | Solid plate chest protection; carry weight cost; moderate mobility reduction |
| 22 | **Steel Breastplate** | Quality | Steel ingot (4) | Iron ingot (1) | Coal (3) | 32 | Full plate chest; significant protection; carry weight cost; Roland's preferred endgame chest |
| 23 | **Iron Pauldrons** | Common | Iron ingot (3) | Coal (2) | Leather strip (2) | 14 (shoulders) | Shoulder protection; reduces damage from overhead attacks |
| 24 | **Reinforced Leather Bracers** | Common | Cured hide (3) | Iron scraps (3) | — | 10 (arms) | Arm protection; light; useful for endurance-focused builds |
| 25 | **Steel Gauntlets** | Quality | Steel ingot (2) | Iron ingot (1) | Coal (2) | 18 (hands) | Full hand protection; slightly reduces combo window (weight); worth it against enemies with blade attacks |
| 26 | **Iron Greaves** | Common | Iron ingot (4) | Coal (2) | Leather strip | 16 (legs) | Leg protection; reduces dodge distance slightly |
| 27 | **Steel Boots** | Quality | Steel ingot (3) | Iron ingot (1) | Leather strip (2) | 20 (feet) | Heavy foot protection; reduces sprint speed 5% |
| 28 | **Iron Kite Shield** | Common | Iron ingot (5) | Hardwood dowel (3) | Coal (2) | +30% block reduction | Passive block; reduces incoming damage while held; requires off-hand |
| 29 | **Steel Tower Shield** | Quality | Steel ingot (4) | Hardwood dowel (3) | Coal (3) | +45% block reduction | Larger coverage; significant carry weight; situational but powerful vs. archers (Game Two+) |
| 30 | **Dwarven Plate Vest** | Masterwork | Steel ingot (5) | Flux powder (2) | Coal (4) | 40 (body) | Khorumzad construction; exceptional protection; heavy; recipe from a dwarven smith in Act III |

### Other Smithed Items (10)

| # | Name | Purpose | Primary Material | Secondary | Notes |
|---|---|---|---|---|---|
| 31 | **Lockpick Set (iron)** | Opens common locks (1–2 tumbler) | Iron scraps (3) | Coal (1) | Assembly-like but requires forge; can also be purchased |
| 32 | **Lockpick Set (steel)** | Opens complex locks (3–4 tumbler) | Steel ingot (1) | Iron scraps (2) | Requires Quality Smithing unlock |
| 33 | **Campfire Grate** | Improves campfire cooking (all meals improve by one quality tier when used) | Iron ingot (2) | Coal (1) | Placed at camp; persists |
| 34 | **Weighted Grapple Hook** | Climbing/traversal tool (story and environmental use) | Iron ingot (3) | Coal (2) | Attaches to rope (rope from assembly) |
| 35 | **Iron Key Blank** | Crafted to match a found lock pattern (quest-specific; certain locked doors can be matched if Roland has the right materials) | Iron ingot (1) | Coal (1) | Requires a smith and the lock's wax impression |
| 36 | **Lantern Frame** | Holds a candle or oil wick; improves visibility while carried (torch replacement) | Iron ingot (2) | Coal (1) | Safer than torches near combustibles |
| 37 | **Chain Links (bundle)** | Crafting component; used in certain assembly recipes and armor repairs | Iron ingot (2) | Coal (1) | Stackable material; 10 links per craft |
| 38 | **Horseshoe Set** | Trade good; currency equivalent in rural areas; improves mount availability (Game Two+) | Iron ingot (3) | Coal (2) | Made in sets of 4 |
| 39 | **Arrowhead Bundle** | Crafting component; 20 per batch; used in certain throwable recipes | Iron ingot (2) | Coal (1) | No ranged weapon in Game One; component for caltrops and trap variants |
| 40 | **Repair Bracket** | Armor repair component; required for forge-level armor maintenance on plate items | Iron scraps (4) | Coal (1) | Field kits cover minor repairs; plate items need this for major restoration |

---

## Section 3 — Cooking Recipes (15 recipes)

All cooked at a **Cooking Fire**. No quality tiers — cooking quality is binary (prepared vs. unprepared). All meals provide hunger recovery; some provide additional effects.

| # | Name | Hunger Recovery | Additional Effect | Ingredients | Roland's Note |
|---|---|---|---|---|---|
| 1 | **Trail Porridge** | 4 hours | None | Dried oats (2), Water | *"The universal breakfast. Gets the job done without memorable flavor."* |
| 2 | **Salt Pork and Bread** | 5 hours | None | Salted pork, Trail bread | *"Mercenary food. Keeps."* |
| 3 | **Roasted River Fish** | 4 hours | Slight endurance boost for 1 hour | Fresh river fish, Salt, Hearth herbs | *"Worth stopping for. Requires time."* |
| 4 | **Herb-Crusted Fowl** | 6 hours | Rest quality improved (bonus endurance on next wake) | Game bird, Hearth herbs, Salt | *"The best campfire meal I know how to make."* |
| 5 | **Vosskaran Root Stew** | 7 hours | Removes cold penalty for 4 hours | Root vegetables (3), Salted pork, Salt | *"Vosskaran recipe. They make it in quantities that last a week. This is the single-night version."* |
| 6 | **Solgrade Olive Flatbread** | 5 hours | +5 temporary Charisma for 2 hours (well-fed and presentable) | Flour (2), Olive oil, Salt | *"You have to have the olive oil. Without it, it's just bread."* |
| 7 | **Dwarven Black Bread** | 8 hours | None (but very filling; no hunger for 8 hours) | Flour (2), Charcoal (a trace), Salt | *"I don't know what they put in it. It's not charcoal, exactly. It's something."* |
| 8 | **Aldenholt Market Pie** | 6 hours | Rest quality improved | Trail bread (as crust), Root vegetables (2), Game bird or salted pork | *"The filling varies. The effect is the same: it's worth having before you sleep."* |
| 9 | **Hunter's Stew** | 6 hours | Endurance recovery rate +20% for 2 hours | Venison, Wild mushrooms (2), Root vegetables, Salt | *"The mushrooms are the point. Get them wrong and it tastes like earth."* |
| 10 | **Campfire Mushroom Soup** | 4 hours | None | Wild mushrooms (3), Water, Salt | *"The lean option. Not unpleasant."* |
| 11 | **Aelorin Forest Salad** | 3 hours | Removes fatigue; Roland is alert for 2 hours as if rested | Aelorin blossom (1), Silverleaf (fresh), Wild mushrooms | *"You don't cook this. You compose it. The Aelorin showed me. It doesn't last more than an hour before it wilts."* |
| 12 | **Smoked Venison Strips** | 8 hours | None; long shelf life (10 in-game days) | Venison (2), Salt (2), Coal (trace) | *"Takes time over the fire. Worth it for the road — these travel."* |
| 13 | **Iron Chalice Hardtack** | 6 hours | None; very long shelf life (30 in-game days) | Flour (3), Salt, Water | *"Knights on campaign lived on this for weeks. I understand why they were difficult men."* |
| 14 | **Spiced Cider** | 2 hours | +10 temporary Charisma for 1 hour; removes cold penalty 1 hour | Dried fruit (2), Water, Honey | *"Warm. Sociable. Probably the best thing I can offer a contact on a cold evening."* |
| 15 | **Traveler's Mess** | 5 hours | None | Any 3 food ingredients (fallback recipe; uses whatever is available) | *"Not a recipe, exactly. An act of necessity."* |

---

## Section 4 — Assembly Table Recipes (30 recipes)

All crafted at the **Assembly Table**. No alchemy involved — pure material construction.

### Throwables (combat use)

| # | Name | Effect | Primary Material | Secondary | Tertiary | Batch (base) |
|---|---|---|---|---|---|---|
| 1 | **Pitch Bomb** | Fire damage in a 3m radius; sets flammable surfaces alight | Pitch (2) | Linen cloth | Coal (trace) | 2 |
| 2 | **Oil Flask** | Creates slippery surface; enemies in area are slowed 40% for 15 seconds | Pitch (3) | Linen cloth | — | 3 |
| 3 | **Smoke Grenade** | Dense smoke cloud; obscures vision for 10 seconds; Roland and enemies both affected | Sulphur | Charcoal (2) | Linen cloth | 2 |
| 4 | **Caltrops (scatter)** | Dropped on floor; enemies who walk through take minor damage and are slowed | Arrowhead bundle (10 heads) | Iron scraps (2) | — | 4 |
| 5 | **Flash Powder Pouch** | Thrown; blinds enemies for 3 seconds; no damage | Saltpeter | Sulphur (trace) | Linen cloth | 2 |
| 6 | **Ashbane Torch** | Thrown; burns with ash-reactive light; Ashfallen and Hollow enemies in radius take +20% damage for 5 seconds | Ashstone dust (2) | Pitch | Rope (short) | 2 |
| 7 | **Noise-Maker Pouch** | Thrown or placed; creates loud noise at a location to draw enemy attention | Iron scraps (3) | Rope (short) | — | 3 |
| 8 | **Venomtip Bundle** | Three needle-darts; thrown at enemy; inflicts poison (5 HP/min for 3 min) | Arrowhead bundle (5) | Nightshade cluster | Leather strip | 1 bundle of 3 |

### Traps (placed in environment)

| # | Name | Effect | Primary Material | Secondary | Tertiary | Batch (base) |
|---|---|---|---|---|---|---|
| 9 | **Tripwire Snare** | Placed on ground; triggers when enemy crosses; snares and roots enemy for 4 seconds | Rope | Iron scraps (2) | Hardwood dowel | 1 |
| 10 | **Poison Trap** | Placed; triggers on approach; releases poison gas in 2m radius | Nightshade cluster (2) | Iron scraps (3) | Rope | 1 |
| 11 | **Bear Trap** | Placed; triggers on step; roots and deals 30 damage; enemies require 8 seconds to free | Iron scraps (6) | Coal (1) | — | 1 |
| 12 | **Alarm Wire** | Placed across a doorway; makes noise when crossed (alerts Roland to NPC entry, not a damage trap) | Rope | Iron scraps (2) | — | 2 |

### Tools and Utility

| # | Name | Effect | Primary Material | Secondary | Tertiary | Batch (base) |
|---|---|---|---|---|---|---|
| 13 | **Bandage Roll** *(starting recipe)* | Field heal: 15 HP; stops bleeding | Linen cloth (3) | — | — | 3 |
| 14 | **Surgeon's Compress** | Field heal: 30 HP; stops bleeding; reduces wound HP loss 50% for next 4 hours | Linen cloth (4) | Silkweed fiber (2) | — | 2 |
| 15 | **Splint** | Stabilizes a broken-state wound (quest/story use; certain combat outcomes require a splint to continue moving at full speed) | Hardwood dowel (2) | Linen cloth (2) | — | 2 |
| 16 | **Sharpening Kit** | Field weapon maintenance: restores 20% weapon sharpness condition | Whetstone | Leather strip | — | 2 |
| 17 | **Repair Kit** | Field armor maintenance: restores 15% armor/blunt weapon condition | Leather strip (2) | Iron scraps (2) | — | 2 |
| 18 | **Rope Coil (20m)** | Climbing, rigging, securing; general utility | Rope (3) | — | — | 1 |
| 19 | **Grapple Hook Assembly** | Thrown onto ledges and anchors; allows climbing (requires Rope Coil) | Weighted Grapple Hook (smithed) | Rope Coil | — | 1 |
| 20 | **Climbing Pitons (set of 6)** | Drive into stone to create handholds; story/traversal use | Iron ingot (1) | Coal (1) | — | 1 set |
| 21 | **Lockpick (field)** | Opens simple locks (1 tumbler); single use | Iron scraps (2) | — | — | 3 |
| 22 | **Torch Bundle** | 3 torches; provide light in dark areas; burn for 10 real minutes each | Hardwood dowel | Linen cloth (2) | Pitch (1) | 3 |
| 23 | **Tallow Candle (set of 6)** | Stable interior light; lasts longer than torches; can be left in place | Preserved fat (2) | Linen cloth (trace) | — | 6 |
| 24 | **Map Case** | Protects documents from moisture; quest-relevant for carrying the Tribute Papers and other documents | Heavy canvas (2) | Leather strip | — | 1 |
| 25 | **Wax Seal Kit** | Seals letters and documents with Roland's mark; quest/dialogue use | Wax (2) | — | — | 1 |
| 26 | **Scent Masker** | Applied to gear; wolves require 50% longer to detect Roland for 4 hours | Hearthwort (2) | Preserved fat | Charcoal (trace) | 2 |
| 27 | **Water Purification Kit** | Purifies water at the point of collection; simpler than the potion; single use | Ironweed (2) | Linen cloth | River clay | 3 |
| 28 | **Signal Mirror** | Reflects sunlight; used for long-distance signaling (quest use; certain outdoor scenes have signal options) | Copper ingot (1) | Leather strip | — | 1 |
| 29 | **Decoy Bundle** | Placed; creates the appearance of a person (shadow/silhouette) to draw enemy attention for 20 seconds | Heavy canvas (2) | Hardwood dowel | — | 1 |
| 30 | **Fire Starter Kit** | Lights campfires without requiring a nearby flame; also used as a backup to light torches | Wax | Flint fragment (found item) | Charcoal (trace) | 3 |

---

## Master Input Material Summary

All unique input materials used across all four crafting sections. Use this table for world-placement and vendor inventory design.

| Material | Sections used | Primary source | Purchasable? |
|---|---|---|---|
| Silverleaf | Potions | Aldenholt market; riverbanks | Yes |
| Bitterroot | Potions | Forests; Aelorin Greatwood | Yes |
| Hearthwort | Potions, Assembly | Ash-soil areas; Ashfields common | Yes |
| Coldmoss | Potions | Rocky hillsides; Spine | Yes |
| Ashbloom | Potions | Ashfields only | Rare |
| Greywillow bark | Potions | Old-growth forest | Yes |
| Ironweed | Potions, Assembly | Roadside everywhere | Yes |
| Nightshade cluster | Potions, Assembly | Shaded ruins, cellars | Limited |
| Aelorin blossom | Potions | Lirien-Thal only | No |
| Waymarker herb | Potions | Ashfields pilgrimage routes | No |
| Thornwax | Potions | Rocky Spine terrain | Rare |
| River clay | Potions | Any riverbank | Yes |
| Cave fungus | Potions | Underground locations | Limited |
| Ashstone dust | Potions, Assembly | Ashfields surface | Yes (Ashfields) |
| Bloodmoss | Potions | Old battlefields; Ashfallen territory | No |
| Emberroot | Potions | Volcanic margins; rare in Game One | No (Game One) |
| Dragonwort | Potions | Copper Isle coastal cliffs | Limited |
| Silkweed fiber | Potions, Assembly | Silkweed stalks; purchased | Yes |
| Preserved fat | Potions | Butchers; rendered from animals | Yes |
| Still's spirit | Potions | Taverns; distillers | Yes (expensive) |
| Iron ore | Smithing | Mines; purchased | Yes |
| Iron ingot | Smithing, Assembly | Smelted / purchased | Yes |
| Steel ingot | Smithing | Smiths; Spine region | Yes (expensive) |
| Copper ingot | Smithing, Assembly | Copper Isles; purchased | Yes |
| Coal | Smithing, Assembly | Mines; purchased | Yes |
| Flux powder | Smithing | Smiths; ruins | Yes (smiths only) |
| Whetstone | Assembly | Purchased; found | Yes |
| Pitch | Assembly | Pine resin; purchased | Yes |
| Sulphur | Assembly | Volcanic margins; Ashfields | Limited |
| Saltpeter | Assembly | Dry caves; alchemists | Limited |
| Linen cloth | Assembly, Cooking | Merchants | Yes |
| Heavy canvas | Assembly | Merchants | Yes |
| Leather strip | Assembly, Smithing | Tanners | Yes |
| Cured hide | Assembly, Smithing | Tanners | Yes |
| Rope | Assembly | Merchants; many locations | Yes |
| Wax | Assembly, Cooking | Beekeepers; chandlers | Yes |
| Charcoal | Assembly, Cooking | Campfire (from wood); purchased | Yes |
| Iron scraps | Assembly, Smithing | Combat loot; smiths | Yes |
| Hardwood dowel | Assembly, Smithing | Carpenters; purchased | Yes |
| Arrowhead bundle | Assembly | Smithed or purchased | Yes |
| Dried oats | Cooking | Grain merchants | Yes |
| Salted pork | Cooking | Butchers; common | Yes |
| Salted fish | Cooking | Coastal vendors | Yes |
| Fresh river fish | Cooking | Caught at fishing spots | No (harvested) |
| Root vegetables | Cooking | Markets; farmsteads | Yes |
| Wild mushrooms | Cooking | Forest floors | No (harvested) |
| Game bird | Cooking | Snare traps | No (harvested) |
| Venison | Cooking | Deer; some camp loot | No (hunted) |
| Flour | Cooking | Grain merchants | Yes |
| Olive oil | Cooking | Solgrade primarily | Yes |
| Salt | All | Universal; cheap | Yes |
| Dried fruit | Cooking | Merchants; Solgrade plentiful | Yes |
| Honey | Cooking | Beekeepers; rare finds | Limited |
| Spiced wine | Cooking | Taverns | Yes |
| Trail bread | Cooking | Purchased; baked | Yes |
| Hearth herbs | Cooking | Hearthwort + ironweed combined | See components |
| Flint fragment | Assembly | Found item; rocky terrain | Yes (common find) |
