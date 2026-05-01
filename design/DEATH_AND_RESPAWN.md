# Death & Respawn Design

What happens when Roland dies — the sequence, the message, and the return.

> Cross-reference: `design/SAVE_SYSTEM.md` for save types and where the most recent save is.
> `design/COMBAT_DESIGN_3D.md` for the Second Wind perk (once per combat survival).
> `design/SKILLS_AND_PROGRESSION.md` → Vitality domain for near-death XP awards.
> `design/REST_AND_CAMP.md` for the difference between rest saves and manual saves.

---

## Design Philosophy

**Death is not punishment, it is consequence.** Roland died because something in the encounter defeated him — his approach was wrong, his positioning was wrong, he took too many hits. The death screen is not a scolding. It is an invitation to try again with what Roland now knows.

**Restore, don't reset.** The return point is the last save — a moment Roland chose (or was given by rest) to commit to. The world between that save and his death retains no consequence of what happened during that attempt. Enemies are back. Loot is back. The player tries again.

**No death spiral.** Roland cannot lose permanent progress through death. He cannot lose his gear, his skills, his quest state, or his companion relationships by dying. The only thing death costs is the time since the last save and the effort of returning to the moment of failure.

---

## Death Sequence

### 1. HP Reaches Zero

Roland's HP bar empties. If the **Second Wind** perk (Vitality Master tier) has not fired yet this encounter, it triggers here — Roland survives at 10% HP. The perk fires once per encounter and does not prevent death a second time.

If Second Wind does not apply (already spent, or not unlocked), Roland collapses.

### 2. Collapse Animation

Roland falls. The camera holds for ~1.5 seconds on his position — not a dramatic slow-motion sequence, but a brief pause. The world continues: enemies may step back, fires keep burning, ambient sounds continue. The pause is short enough to feel like a breath, not a cinematic.

### 3. Death Screen

A simple full-screen fade to a dark, near-black tone — not pure black. A single line of text in Roland's voice. Not "YOU DIED." Not a score or evaluation. Something that fits the moment:

A few authored variants, selected based on context:

| Context | Line |
|---|---|
| Killed by a goblin early in game | *"Even the small ones."* |
| Killed by an Ashfallen | *"I still move like I have armor I no longer have."* |
| Killed during a story-significant fight | *"Not yet. Not like this."* (context-specific) |
| Killed by a wolf | *"Too many of them. Too fast."* |
| Killed by a bear | *"I should have gone around."* |
| Generic fallback | *"Again."* |

These lines are authored per enemy type and occasionally per specific encounter. They are not randomly rotated — they are matched to the cause of death via a `death_context` flag. There are not many of them (10–15 total for Game One). They do not need to be comprehensive — a good fallback covers most cases.

Two options appear below the line:

- **Return** — loads the most recent save
- **Quit** — exits to the main menu (save is preserved; player can load later)

### 4. Load and Return

Selecting **Return** loads the most recent save (see `design/SAVE_SYSTEM.md`). The load is identical to a manual load: same scene, same position, same inventory, same world state from the save moment.

There is no animation or cinematic on return. Roland appears at the save location. The world is as it was. The player tries again.

---

## The "Near Death" State

At HP below 10%, before Roland reaches zero:

- Screen edges darken (vignette effect — see `design/HUD_AND_UI.md`)
- Roland's breathing is audible — labored, not theatrical
- The Second Wind perk (if available) is visually indicated: a faint amber glow at the HP bar edge, communicating that it has not fired yet

This state is brief in practice — a Roland at 10% who takes another hit is dead. But the window exists to communicate the danger clearly without a sudden death that feels arbitrary.

---

## Vitality XP on Near Death

Surviving a near-death moment (dropping below 20% HP and recovering through rest, not Second Wind) awards Vitality XP:

```
XP_VALUES["near_death_survived"] = 50
```

This is tracked in `GameState.gd` via a `near_death_this_encounter` flag that fires when HP crosses the threshold. The XP awards after the combat encounter ends, not during.

The design intent: a Roland who consistently fights on the edge and survives becomes a harder Roland. Cautious play is valid but does not push Vitality as fast.

---

## Companion Behavior on Roland's Death

Companions do not die when Roland does. Their AI shuts down (they stop acting) and they wait at their last position. On return from a save, companions are restored to their save-time positions and states.

Companions do not have death dialogue that fires on Roland's death — there is no scene for them to react in, since the death screen is immediate. Their save-state condition (HP, consumables) is what matters on return.

---

## What Death Does Not Cost

- Skill XP (all XP earned before the save is preserved; XP earned after the save, during the failed attempt, is lost — this is correct behavior, not a bug)
- Faction standing
- Quest state (beyond the save point)
- Gear, items, or crowns (save state is restored exactly)
- Companion relationships
- Save slots (death never overwrites a save — only rest and Wanderer's Seal do)

---

## GDScript Notes

### Death trigger in PlayerStats

```gdscript
# PlayerStats.gd:
signal player_died(death_context: String)

func take_damage(amount: float, source: String) -> void:
    current_hp -= amount
    _check_hp_thresholds()
    if current_hp <= 0.0:
        if _try_second_wind():
            return
        emit_signal("player_died", source)

func _try_second_wind() -> bool:
    if GameState.has_perk("second_wind") and not second_wind_spent:
        current_hp = max_hp * 0.10
        second_wind_spent = true
        return true
    return false
```

### Death screen handler

```gdscript
# DeathScreen.gd — a CanvasLayer that listens for player_died signal:
func _on_player_died(death_context: String) -> void:
    get_tree().paused = true
    _fade_to_dark()
    await get_tree().create_timer(1.5).timeout
    _show_death_line(death_context)
    _show_buttons()

func _get_death_line(context: String) -> String:
    return DEATH_LINES.get(context, DEATH_LINES["default"])

func _on_return_pressed() -> void:
    get_tree().paused = false
    GameState.load_game()

func _on_quit_pressed() -> void:
    get_tree().paused = false
    TransitionManager.go_to_scene("res://scenes/MainMenu.tscn")
```

### Death line table (authored)

```gdscript
const DEATH_LINES: Dictionary = {
    "goblin":       "Even the small ones.",
    "ashfallen":    "I still move like I have armor I no longer have.",
    "wolf":         "Too many of them. Too fast.",
    "bear":         "I should have gone around.",
    "default":      "Again.",
}
# Story-specific deaths are added here as their encounter IDs are authored.
```
