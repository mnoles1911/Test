# Rest and Camp System Design

How Roland rests, sleeps, manages time, and uses camp as a functional base.

> Cross-reference: `design/CRAFTING.md` for the Alchemist's Still and Assembly Table at camp.
> `design/SKILLS_AND_PROGRESSION.md` for rest as a Vitality XP source.
> `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` for companion pack access at camp.
> `design/NPC_SYSTEM.md` for WorldClock and time-of-day period transitions.

---

## Design Philosophy

**Rest is not a reward, it is a rhythm.** Roland is a man on a long journey. He needs to sleep. Eating before bed improves the quality of sleep. Fighting through the day without rest makes the next fight harder. The system does not punish the player for not managing rest optimally — it rewards them for doing it well.

**Camp is a place, not a menu.** When Roland makes camp, he is somewhere. There is a fire. There are companions. There are things to do. Camp is not a pause screen with options — it is a scene the player inhabits briefly before moving on.

**Time has weight.** The WorldClock advances continuously. Resting advances it in hours, not frames. Choosing to rest in a dangerous area costs time that enemies or events may consume. The world does not freeze while Roland sleeps.

---

## Rest Types

Three ways Roland can rest, with different effects and availability:

| Rest type | HP restored | Wound recovery | Endurance | Hunger reset | Time cost | Save created? |
|---|---|---|---|---|---|---|
| **Roadside rest** (sit at campfire, no bedroll) | 25% of missing HP | None | Full | No | 2 game hours | No |
| **Bedroll rest** (unrolled at camp) | 60% of missing HP | Partial (50% of wound HP) | Full | Partial (4 hours) | 6 game hours | No |
| **Full rest** (inn bed or established camp cot) | 100% of missing HP | Full wound recovery | Full | Full (8 hours) | 8 game hours | Yes (autosave) |

**Wound HP:** A portion of HP lost in combat becomes "wound HP" — it does not recover from potions or roadside rest. Only full rest or the **Boneknit Compound** potion can restore wound HP. This ensures that a Roland who took a serious beating cannot simply drink his way back to full health — he needs time.

**Well-fed bonus:** Eating a meal before any rest improves the rest quality by one tier (roadside → bedroll quality; bedroll → full rest quality for HP/wound recovery). The hunger reset still follows the sleep type. See `design/ITEM_LIBRARY.md` — Section 3 for meals that grant the rest bonus.

---

## Making Camp

Roland can establish a camp at any location that is:
1. Not in an active combat area
2. Not an interior scene with no fire (he needs something to cook at / sit beside)
3. Not a restricted or story-blocked zone (certain story scenes disable camping)

**Interaction:** Approach a campfire or a valid outdoor resting spot and press E. The camp menu opens. Roland does not build fires from scratch in Game One — he uses existing fires, the braziers in safe-houses, or his own campfire prop (see Camp Upgrades below).

### The Camp Menu

When the camp menu opens, the game does not pause — time advances slowly in the background (WorldClock continues at 1/4 normal rate while the menu is open, so prolonged camp planning still costs some time). The menu presents:

```
[ Rest ]  [ Craft ]  [ Companions ]  [ Gear ]
```

**Rest tab:** Choose rest type (roadside / bedroll / full, depending on what's available at this location). Shows current HP, wound HP, and what will be recovered. If well-fed, shows the bonus.

**Craft tab:** Opens to the available crafting stations at this camp. A roadside fire gives access to Cooking only. An established camp with upgrades gives access to all available stations.

**Companions tab:** Opens companion pack management for each present companion. See `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md`.

**Gear tab:** Apply field maintenance kits (Sharpening Kits, Repair Kits) without visiting a smith. Less effective than forge maintenance but available anywhere. See `design/CRAFTING.md` for field vs. station maintenance comparison.

---

## Camp Upgrades

As Game One progresses, Roland's camp can be improved through story progression and side quests. Upgrades persist — once established, a camp location keeps its upgrades.

| Upgrade | Unlocked by | Provides |
|---|---|---|
| **Bedroll** | Default from Act I (Roland carries one) | Bedroll rest at any valid campsite |
| **Portable Alchemist's Still** | Purchased or found in Act II (Herbalist contact in Caer Brannoch or Vosskara) | Alchemy bench at camp |
| **Assembly Table** | Default from Act I at Roland's established safe-house; portable version found in Act II | Assembly table at camp |
| **Camp Cot** (fixed location only) | Establishing a permanent base (Iron Chalice safe-house, Brotherhood cache, or rented room) | Full rest quality at that location |

The portable still and table are items in Roland's inventory — they have weight. A player who wants full crafting capability at every camp carries them, trading carry capacity for convenience.

---

## Sleep, Time Skipping, and WorldClock

When Roland chooses to rest:

1. A brief fade-to-dark plays (not a full black screen — more like closing eyes).
2. `WorldClock.advance_hours(n)` is called. `n` is 2, 6, or 8 depending on rest type.
3. All NPC schedules update for the new hour. NPCs move to their correct schedule positions.
4. If the hour advance crosses a time-of-day period boundary (e.g., NIGHT → DAWN), the `time_of_day_changed` signal fires and the world lighting shifts accordingly.
5. A brief fade-in shows the new time of day.
6. For full rest: autosave fires before the fade-in completes.

**Time-sensitive quests:** Certain quests set a FlagScheduler deadline. If Roland sleeps past the deadline, the quest state updates accordingly (a contact leaves, an event resolves without him, a door is locked). This is designed to feel like consequence, not punishment — the journal will note what changed.

**Skipping time without rest:** `WorldClock.advance_hours()` can also be called by other story events (fast travel arrival, time-skipping story cuts). This is the same mechanism.

---

## Hunger During Rest

Hunger is consumed by activity, not by time alone. Sleeping costs no additional hunger — Roland is not burning calories. However:

- Waking from rest without having eaten before sleeping keeps the hunger penalty active.
- Eating before rest clears the hunger penalty for the sleep period plus the well-fed bonus duration.
- A well-fed Roland who sleeps well wakes with full endurance headroom and no penalties for the first in-game hour.

The practical loop: eat at dusk (a meal from camp cooking), rest overnight, wake at dawn at full function. The system rewards the natural rhythm without forcing it.

---

## Camp Atmosphere and Companions

When the camp menu is open and companions are present, they have ambient dialogue — brief lines that fire based on the current story state, time of day, and recent events. This is not a triggered conversation; it is the equivalent of Tier 1 barks in a stationary context.

Examples:
- Orion checking his gear by the fire, commenting on the next leg of the journey
- Dagna looking at the terrain and noting something geological
- Roland's internal monologue noting the quality of the fire, the temperature, what he is about to walk into

These lines require no player input. They play while the player is in the camp menu or standing near the fire. They are authored per act and per story state. See `design/CONVERSATION_SYSTEM.md` → Tier 1 (Barks) for the technical approach.

---

## Save Behavior at Camp

A full rest creates an **autosave**. This is the primary save mechanism — sleeping in a real bed is when the game commits the player's progress.

The **Wanderer's Seal** (crafted consumable) creates a **manual save** and can be used anywhere, including before a difficult fight or at the end of a productive session away from camp. It does not replace rest — it supplements it for moments when Roland cannot safely sleep.

See `design/CRAFTING.md` for the Wanderer's Seal recipe, and `design/SYSTEMS_DESIGN.md` for the full save system specification.

---

## GDScript Notes

### Rest resolution

```gdscript
# Called when the player confirms a rest choice in the camp menu
func resolve_rest(rest_type: String) -> void:
    # rest_type: "roadside", "bedroll", "full"
    var well_fed: bool = GameState.get_flag("hunger_state") == "well_fed"
    var effective_type: String = rest_type

    if well_fed:
        # Upgrade one tier: roadside → bedroll, bedroll → full
        match rest_type:
            "roadside": effective_type = "bedroll"
            "bedroll":  effective_type = "full"

    match effective_type:
        "roadside":
            PlayerStats.restore_hp_percent(0.25)
            WorldClock.advance_hours(2)
        "bedroll":
            PlayerStats.restore_hp_percent(0.60)
            PlayerStats.restore_wound_hp_percent(0.50)
            WorldClock.advance_hours(6)
        "full":
            PlayerStats.restore_hp_percent(1.0)
            PlayerStats.restore_wound_hp_percent(1.0)
            WorldClock.advance_hours(8)
            GameState.save_game()  # autosave on full rest

    GameState.set_flag("hunger_state", "hungry")  # reset after rest
    add_vitality_xp_for_rest(effective_type)
```

### WorldClock integration

```gdscript
# WorldClock.advance_hours() handles all downstream effects:
# - NPC schedule updates (calls update_schedule on "scheduled_npcs" group)
# - time_of_day_changed signal if period boundary crossed
# - day_changed signal if rolling past midnight
# The camp system does not need to call these manually.
```

### Camp upgrade state

Camp upgrades are stored as flags in GameState:

```gdscript
# Upgrade flags:
GameState.set_flag("camp_has_still", "true")       # portable alchemy bench
GameState.set_flag("camp_has_assembly", "true")    # assembly table
GameState.set_flag("camp_has_cot_[location]", "true")  # location-specific full rest

# Camp menu reads these to determine which tabs are available:
func get_available_stations() -> Array[String]:
    var stations: Array[String] = ["cooking"]  # always available at a fire
    if GameState.get_flag("camp_has_still") == "true":
        stations.append("alchemy_still")
    if GameState.get_flag("camp_has_assembly") == "true":
        stations.append("assembly_table")
    return stations
```
