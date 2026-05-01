# Companion System Design

How companions join, behave, fight, and relate to Roland and the player.

> Cross-reference: `design/COMBAT_DESIGN_3D.md` for companion combat orders and friendly fire rules.
> `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` for companion pack management at camp.
> `design/NPC_SYSTEM.md` for WorldClock schedule support and bark system.
> `design/CONVERSATION_SYSTEM.md` for companion dialogue and bark lines.
> `design/INVESTIGATION_SYSTEM.md` for companion observational lenses.
> `lore/CHARACTERS_COMPANIONS.md` for character detail, arcs, and relationships.

---

## Design Philosophy

**Companions are people, not abilities.** Orion is not "the scout class." He is a twenty-two-year-old sailor who assesses exits in every room he enters because that is what years on dangerous ships teach you. His mechanical behavior — checking flanks, identifying escape routes — is the game expressing his character, not his stat sheet.

**Companions have opinions.** They comment on what Roland does, where he goes, and what he says. These comments are not random barks — they are authored to specific story states, locations, and choices Roland has made. A companion who has been silent for three hours will say something specific when they arrive somewhere that matters to them. This is not constant chatter. It is the world noticing.

**Companions are not shields.** They can be hurt. Their consumables deplete. Their equipment degrades. A player who ignores companion management will eventually fight without the backup they expect. The game does not quietly compensate for neglect.

**Autonomy with override.** Companions fight on their own judgment. Roland can issue three simple orders via a context menu — Engage, Hold, Retreat. He cannot micromanage them, and he should not need to. The default AI handles 80% of combat situations appropriately. The orders exist for the 20% where the player needs to coordinate.

---

## Game One Companions

### Orion Farr

**Joins:** Midway through Game One, Caer Brannoch arc.

**Combat role — Scout/Flanker:**
- Orion moves fast. He does not block — he dodges, repositioning to a flank or rear position.
- His attacks are quick and light. High attack frequency, lower damage per hit than Roland.
- When Orion reaches an enemy's flank or rear arc, he gains a flanking bonus that he uses consistently — Roland benefits by pressing from the front while Orion is behind.
- If Roland takes a hit, Orion will often reposition to draw aggression temporarily — not a taunt mechanic, just behavioral: he moves into the enemy's vision to redirect attention.

**Out-of-combat role:**
- Orion scouts ahead in unfamiliar zones — he moves faster than Roland (non-combat sprint speed is higher) and can return to report what he saw. In practice: the player moves Orion forward using the Engage order on a point of interest, and Orion's commentary when he returns serves as information.
- His observation lens in the investigation system: exits, escape routes, signs of recent foot traffic, Brotherhood markers. See `design/INVESTIGATION_SYSTEM.md`.

**At camp:**
- Orion does not have strong camp opinions. He checks his gear, sharpens things that need sharpening, makes practical comments about the next leg of the journey. He is not introspective at rest.

**Relationship dynamic with Roland:**
- Orion resists Roland's protective instinct. He has been competent in dangerous situations since he was sixteen and does not need shepherding. The arc of their relationship is Roland accepting this. Moments where Roland treats Orion as an equal (rather than someone to protect) are the milestones of their friendship.

---

### Dagna Irontrack

**Joins:** Game One Act III, the Underway encounter.

**Combat role — Anchor/Support:**
- Dagna is slower than Roland. She does not dodge — she plants and blocks, and her block is exceptional: high stamina efficiency, can absorb more consecutive hits before breaking.
- Her attacks are deliberate and powerful. She applies a **mark** to enemies with her primary attack: the next hit from any source against a marked enemy deals bonus damage. This makes her a force multiplier — Roland's follow-up on a marked enemy hits harder.
- She does not pursue fleeing enemies. She holds ground.

**Out-of-combat role:**
- Dagna marks passages as she moves through them (chalk marks on walls, floor, stone). This is diegetic navigation aid in underground zones — looking at the path you came in on, Dagna's marks are there. In the Underway specifically, this becomes a plot element.
- Her observation lens: structural details, old construction, geological features, underground access. She will comment on things Orion and Roland both miss.

**At camp:**
- Dagna is the camp's most verbally specific presence. She has opinions about campsites (vent proximity, structural stability of overhangs), about the fire (she knows how to read smoke), and about what they are walking toward. Her camp comments in Act III underground sections are the most information-dense companion barks in the game.

**Relationship dynamic with Roland:**
- Mutual recognition between professionals outside their usual domain. She does not fully trust Roland until he keeps his word about Barak Stonecroft's testimony. Before that point, she is cooperative but reserved. After that point, she is reliable in a way Roland has not experienced from many people.

---

## Companion Presence in Scenes

### Bringing Companions

The player chooses which companions to bring to a scene from a selection at zone boundaries (or at camp for pre-planned outings). Not all companions can accompany Roland everywhere:

- **Restriction examples:** Dagna cannot accompany Roland to Lirien-Thal (her presence complicates Aelorin willingness to speak openly). Orion is restricted from certain Brotherhood interior meetings (he is not a member).
- Restrictions are communicated in Roland's voice in his journal — a brief note about why this companion would be a problem here. The player is not locked out without explanation.
- Some scenes actively benefit from a specific companion's presence — certain investigation observations only trigger with the right companion present (see `design/INVESTIGATION_SYSTEM.md` → Companion Observations).

### Active Party

Roland plus up to 2 companions in any scene. If Roland has only one companion, that companion is always active. If Roland has both Orion and Dagna available, he brings both by default unless the scene restricts one.

---

## Companion Behavior in Combat

### Default AI

Companions run their own simplified combat AI loop:
1. Move toward the current highest-threat enemy (closest enemy with active aggression toward Roland)
2. Use attacks according to their combat role
3. Use consumables from their own pack when HP drops below 40%
4. Avoid standing in fire/hazards

Companions **do not use Roland's items.** They consume only from their own pack.

### Combat Orders

Roland can open a radial order menu (hold a button, typically Tab) to issue simple directives:

| Order | Effect |
|---|---|
| **Engage** | Attack the target Roland is locked onto, or the nearest enemy |
| **Hold Position** | Stop pursuing; defend from current position; only attack enemies that come within melee range |
| **Retreat** | Move toward Roland's position; stop attacking; defensive stance |

These orders are not queued or complex. One order at a time. The companion returns to default behavior after the immediate order context resolves (enemy is dead, Roland moves away, etc.).

**No friendly fire.** Roland cannot hit companions. Companions cannot hit Roland. This is unconditional — confirmed design decision from `design/COMBAT_DESIGN_3D.md`.

### Companion HP and Death

Companions do not permanently die in Game One. If a companion's HP reaches zero, they enter a **downed state** for 10 seconds. Roland can revive them by pressing E near them (brief animation, leaves Roland vulnerable). If not revived within 10 seconds, the companion withdraws from the fight — they are injured and out of combat but recover after the encounter.

A companion who withdraws from multiple consecutive encounters without Roland restocking their consumables will have lower effective HP on entry (unhealed wounds carry over). The game does not silently top up companion HP between scenes.

---

## Companion Inventory Management

At camp, Roland can open each companion's pack through the **Companions tab** of the camp menu.

The companion pack screen shows:
- Current equipped weapon, armor pieces
- Pack contents (consumables, materials)
- Equipment condition for each piece
- A suggestion line from the companion if something is critically low ("Running low on bandages, Roland.")

Actions available:
- Swap equipped weapon/armor (drag from companion pack or Roland's pack)
- Drag healing consumables from Roland's supply to the companion's pack
- Apply a Repair Kit or Sharpening Kit to companion gear (uses the kit from Roland's inventory)

**Companions do not auto-restock.** If Roland does not manually resupply Orion, Orion fights with whatever he has left. The game warns when a companion pack tab opens and consumables are depleted, but does not fix it automatically.

---

## Companion Dialogue and Bark System

### Camp Barks

When the camp menu is open and a companion is present, they fire ambient dialogue — brief lines based on:
- Current story act and recent major choices
- Time of day and location
- Roland's current quest state

These are Tier 1 barks delivered in a stationary context — not a triggered conversation. The player does not need to interact; the lines play while the player is in the camp menu or standing near the fire. See `design/CONVERSATION_SYSTEM.md` → Tier 1 (Barks).

### Investigation Addenda

When Roland examines a Type 2 investigation point with a relevant companion present, that companion adds a line of their own. This is a bark (portrait flash + short text) rather than a full conversation. It adds information Roland's perspective alone would not provide.

**Companion observational lenses:**
- **Orion:** Exits, escape routes, signs of recent foot traffic, Brotherhood markers
- **Dagna:** Structural details, old construction, geological features, underground access

The companion's addendum should always add something Roland's observation did not cover — not restate it. See `design/INVESTIGATION_SYSTEM.md` → Companion Observations.

### Relationship Dialogue

At specific story milestones and locations, companions initiate conversations through the standard Dialogic system (not barks). These are longer exchanges driven by their relationship with Roland and the current story state. They are always optional — the player can exit without engaging. But the conversations exist, and missing them means missing context.

Companion relationship dialogue is authored per act, not per scene. Each companion has 2–3 substantive conversations per act that cannot occur until specific story flags are set.

---

## GameState Tracking for Companions

Companion state is tracked in `GameState.gd`:

```gdscript
# Companion flags:
# Whether each companion is currently in Roland's party:
GameState.get_flag("companion_orion_active")   # "true" / "false"
GameState.get_flag("companion_dagna_active")

# Companion HP and wound HP (persists between scenes):
GameState.get_flag("companion_orion_hp")       # float as string
GameState.get_flag("companion_orion_wound_hp")

# Relationship milestones:
GameState.get_flag("orion_trusted")            # set after Roland accepts Orion as equal
GameState.get_flag("dagna_trusted")            # set after Roland keeps his word about Stonecroft

# Consumable stock warning threshold (used by camp UI):
GameState.get_flag("orion_bandages_low")       # "true" if below 2 units remaining
```

---

## GDScript Notes

### CompanionAI base class

```gdscript
class_name CompanionAI
extends CharacterBody3D

@export var companion_id: String   # "orion", "dagna"
@export var data: CompanionData    # Resource with base stats, pack contents

var current_order: String = "engage"  # "engage", "hold", "retreat"
var hp: float
var wound_hp: float

func receive_order(order: String) -> void:
    current_order = order

func _tick_combat(delta: float) -> void:
    match current_order:
        "engage":  _behavior_engage(delta)
        "hold":    _behavior_hold(delta)
        "retreat": _behavior_retreat(delta)
```

### Companion pack access

```gdscript
# Triggered from camp menu Companions tab:
func open_companion_pack(companion_id: String) -> void:
    # Load companion's current pack state from GameState
    # Open the CompanionPackUI scene, passing companion_id
    # On close, write updated pack state back to GameState
    pass
```

### Companion downed/revive

```gdscript
# In CompanionAI.gd:
var downed_timer: float = 0.0
const DOWN_DURATION: float = 10.0

func _on_hp_zero() -> void:
    state = CompanionState.DOWNED
    downed_timer = DOWN_DURATION
    # Disable combat AI, play downed animation

func _tick_downed(delta: float) -> void:
    downed_timer -= delta
    if downed_timer <= 0.0:
        _withdraw_from_combat()

func revive() -> void:
    hp = max_hp * 0.25
    state = CompanionState.COMBAT
    downed_timer = 0.0
```
