# Lockpicking System Design

How Roland opens locked doors and containers.

> Cross-reference: `design/ITEM_LIBRARY.md` for lockpick item stats, stack sizes, and vendor availability.
> `design/SKILLS_AND_PROGRESSION.md` for the Lockpicking sub-skill under the Exploration domain.
> `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` for lockpick storage (consumable, not quick-slotted).

---

## Design Philosophy

**The lock is a puzzle Roland is solving with his hands, not a menu he navigates.** Lockpicking is tactile, tense, and readable. A player learns how locks work the way Roland does: by doing it badly at first, then better.

**Inspired by KCD2, reimagined.** Kingdom Come: Deliverance 2 uses a cylindrical tumbler — the player physically rotates a pick inside a cylinder, feeling for where the lock yields through controller rumble and audio. That feeling of *exploration inside the lock* is the right tone. This system keeps that feel but moves to a different geometry: a flat radial dial that reads clearly as a UI overlay at any camera angle.

**Skill determines forgiveness, not permission.** Roland can attempt any lock. A low-skilled Roland attempting a Very Hard lock will almost certainly break his pick — but the attempt is always available. The game should feel impossible early and achievable late, not locked behind a gate that says "you can't try."

**One consumable per attempt, not per pin.** A single pick lasts the whole attempt. You lose it only if the lock resets — either from your mistake or the spring catching you. A skilled player uses far fewer picks than a careless one.

**Time keeps moving.** The lockpicking overlay does not pause the game. Roland is exposed while picking. Enemies can approach. Companions can be heard shouting warnings. Picking quickly is a real consideration, not just an efficiency preference.

---

## Proximity Auto-Examine

Roland automatically reads a lock when he passes within interaction range. No button press required — just walking close to a locked container or door triggers a silent assessment.

What appears: a brief **difficulty label** in the interaction prompt area (the same place the "E — Open" label would be):

| Internal tier | Player-facing label |
|---|---|
| Simple | **Easy** |
| Standard | **Medium** |
| Complex | **Hard** |
| Masterwork | **Very Hard** |

The label appears alongside the lock icon for 2 seconds, then fades. It reappears any time Roland re-enters range.

**No journal entry, no voiceover, no animation.** This is ambient awareness — Roland glancing at a lock as he passes. The full examine (with Roland's flavor narration in the journal overlay) is available if the player presses E without a pick equipped.

The difficulty label is honest at all skill levels. A Novice Roland still sees "Very Hard" — he's not blind to what he's dealing with. What changes with skill is whether he can do anything useful about it.

---

## The Resonance Pick — Core Mechanic

### What It Looks Like

Pressing E at a locked object with picks in inventory opens the **Lockpicking overlay**. The game world remains visible and running in the background, blurred (a `BackBufferCopy` + shader desaturation and blur effect). NPCs move, enemies patrol, time advances. Only Roland is stationary.

The overlay shows:
- A **circular lock face** — a stylized iron disc with a keyhole at center, rendered as a clean UI element (not a 3D camera cut).
- A **pick indicator** — a thin line extending from the center, pointing in the current pick direction. The player rotates it with A/D (keyboard) or left/right stick (controller). Clock-face mental model: twelve o'clock is up, three o'clock is right.
- A **difficulty label** in the top corner of the overlay (Easy / Medium / Hard / Very Hard), so the player always knows what they're dealing with.
- The number of **pins remaining** as a small row of icons at the bottom.

Somewhere on the dial, one or more **tension pins** are seated. The player cannot see where. Finding them is the game.

### How Pins Are Found — Resonance Feedback

As the pick sweeps the dial, three feedback channels activate when approaching a pin:

1. **Visual:** The pick indicator develops a faint amber glow that intensifies near a pin. At the pin center, it pulses.
2. **Audio:** A low metallic hum rises in pitch as the pick approaches. At center: a short ringing tone.
3. **Haptic (controller):** Increasing rumble approaching; a short firm pulse at center.

When the player finds the resonance peak, they **hold still**. A **set bar** fills below the lock face. When complete, the pin sets with a click and the pin icon at the bottom fills.

Then sweep to find the next pin.

### False Resonances (Hard and Very Hard Only)

Hard and Very Hard locks have 1–2 false resonance positions on the dial. They look and sound similar to real pins — the glow appears, the hum starts — but the set bar fills only halfway before stalling. The real pin has a warmer, cleaner ring tone. The false one is slightly hollow with an irregular pulse. Players who are paying attention will learn the difference. Players who are rushing will occasionally waste a hold-timer on a false pin.

---

## Lock Tiers and Skill Scaling

The four tiers define how wide the resonance zone is around each pin, how many pins there are, and how many false resonances exist. Roland's skill does not change these — but it changes how much time and forgiveness he gets while working.

| Tier | Player label | Pins | Resonance zone | False resonances |
|---|---|---|---|---|
| Simple | **Easy** | 1 | Wide (~40° arc) | None |
| Standard | **Medium** | 2 | Medium (~25° arc each) | None |
| Complex | **Hard** | 3 | Narrow (~15° arc each) | 1 false |
| Masterwork | **Very Hard** | 3 | Very narrow (~8° arc) | 2 false |

### Skill Tier Effects on Forgiveness

Roland's Lockpicking sub-skill does not widen resonance zones or remove false pins. What it changes is the **hold timer** (how long he can stay at a position before the spring snaps the pick) and the **sweep speed penalty** (how aggressively back-pressure punishes fast sweeping).

| Skill tier | Hold timer | Sweep leeway | Very Hard viable? |
|---|---|---|---|
| **Novice** (default) | 2.5s | Tight — sweeping near set pins snaps fast | Almost never. Manageable with Fine picks and many attempts. |
| **Trained** | 3.5s | Moderate — some margin for deliberate sweeps | Doable with patience and Fine picks. |
| **Expert** | 5.0s | Generous — back-pressure is slow to catch Roland | Comfortably achievable. The lock is still demanding, not a formality. |

**The intended arc:** A Novice Roland looking at a Very Hard lock should feel the same thing the player feels — "I can't do this yet." An Expert Roland approaching the same lock should feel capable. The difficulty label doesn't change. The lock doesn't change. Roland does.

Fine Lockpicks add a flat +1.5s to the hold timer at any skill tier — they are a supplement to skill, not a replacement.

---

## The Pick Snap — When You Fail

A pick snaps in two situations:

1. **Hold timer expires.** Roland is at a position and the set bar does not complete in time. The spring pressure catches the pick and it breaks. This happens if he is off-center on the resonance zone, if he is on a false resonance, or if he simply waited too long.

2. **Sweeping too fast through the back-pressure zone.** Once the first pin is set, the lock's internal spring applies back-pressure in the half of the dial farthest from the set pins. Sweeping quickly through that zone snaps the pick. Easy locks have no back-pressure. Very Hard locks have significant back-pressure and a faster snap on fast sweeps. Higher skill tier gives more time before the snap triggers.

**On snap:** Sharp audio cue. The pick breaks (brief particle effect on the overlay). The lock resets — all set pins return to zero. The consumed pick is removed from inventory. The player can immediately start another attempt if picks remain.

If Roland runs out of picks, the overlay closes. The difficulty label remains visible when he re-enters range, with a secondary line: "No picks."

---

## Full Examine (Optional)

Proximity auto-examine gives the difficulty label. If the player wants more information, pressing E without picks equipped (or through the interaction hold-menu) triggers a **full examine**: Roland narrates a brief observation that appears in the journal bark overlay.

Examples:
- Easy: *"Cheap iron. I could open this with a bent nail."*
- Medium: *"Standard work. Two pins, maybe. Someone put thought into this."*
- Hard: *"Three pins at least. Whoever installed this didn't want it opened."*
- Very Hard: *"Masterwork cylinder. Fine tolerances. I'd need steady hands and some luck."*

Full examine does not consume a pick. It does not surface anything mechanically beyond what the label already communicates — it is flavor and player agency.

---

## Lockpick Items

Lockpicks are consumable items stored in inventory, not quick-slotted.

| Item | Weight | Stack | Notes |
|---|---|---|---|
| **Lockpick** | 0.05 kg | Up to 20 | Standard. General Merchants, Brotherhood caches, found in the world. |
| **Fine Lockpick** | 0.05 kg | Up to 10 | +1.5s hold timer. Useful on Hard and Very Hard. Sold only by Brotherhood contacts and specialty vendors at FRIENDLY+. |

---

## Lockpicking Skill — Exploration Domain

Roland's Lockpicking sub-skill is in the **Exploration domain**. Three tiers: Novice (default), Trained, Expert.

**How it advances:** Successfully picking a lock contributes XP. Only the first successful pick of a given lock counts — the game tracks opened lock IDs. Picking the same Easy lock repeatedly does not advance Roland's skill. Attempting locks at or above the current tier's challenge ceiling contributes more XP.

**Trainer shortcut:** A Brotherhood contact in Caer Brannoch (available at NEUTRAL+) can train Roland directly to Trained tier in exchange for a favor. This is the only non-in-world path to advancement.

---

## Time, Detection, and Interruption

**Time does not pause during lockpicking.** The blurred world behind the overlay is still running. NPCs walk their schedules. Enemies patrol.

- **Enemy detection:** Roland is stationary while picking. He cannot dodge or sprint while the overlay is open. If an enemy would enter detection range, the normal detection timer applies — the lock does not protect him.
- **Interruption:** If Roland takes damage or an enemy enters his immediate area (triggers a combat state), the overlay closes. Roland is placed back in his idle stance. **The pick is not consumed on interrupt** — only on snap.
- **Companion behavior:** Companions hold position near Roland during lockpicking. Orion will bark a warning if he spots someone approaching. The player can hear these barks through the overlay audio.

Skilled play involves clearing the area first, or using Orion on Hold Position as a perimeter watch.

---

## Keys

Most named locks have a key somewhere in the world. Keys are Quest Items — weightless, cannot be dropped, found through investigation or looting.

**A key is always faster and silent.** Finding a key is the reward for exploration; lockpicking is the fallback. Some locks have no key — they can only be picked.

A key is consumed on use and marked spent in the journal (the physical key remains visible on Roland's keyring but is flagged used).

---

## Locked Containers vs. Locked Doors

- **Containers:** Picking is private. Consequence is only what's inside.
- **Doors:** Opening a locked door may take Roland somewhere he is not supposed to be. If an NPC finds the door open or catches Roland inside, it carries disposition consequences. The picking itself is private — only the trespass matters.

**Quest-critical locks** are always pickable regardless of skill tier. A Novice Roland will struggle — degraded feedback, likely several snapped picks — but the story does not gate him out.

---

## GDScript Integration Notes

### Lock Resource

```gdscript
class_name LockData
extends Resource

@export var lock_id: String
@export var tier: int                  # 0=Easy/Simple, 1=Medium/Standard, 2=Hard/Complex, 3=Very Hard/Masterwork
@export var pin_count: int             # 1–3
@export var key_item_id: String        # "" if no key exists
@export var quest_critical: bool = false
@export var examine_bark: String       # Roland's full-examine narration line
```

### Proximity Auto-Examine (on LockObject3D)

```gdscript
# Fires when player enters interaction range — no input required
func _on_player_entered_range() -> void:
    var label: String = ["Easy", "Medium", "Hard", "Very Hard"][lock_data.tier]
    InteractionPrompt.show(label, "lock_icon", 2.0)
```

### Hold Timer by Skill Tier

```gdscript
const HOLD_TIMER_BY_SKILL: Dictionary = {
    0: 2.5,   # Novice
    1: 3.5,   # Trained
    2: 5.0    # Expert
}
const FINE_PICK_BONUS: float = 1.5

func get_hold_timer() -> float:
    var skill_tier: int = SkillManager.get_subskill_tier("lockpicking")
    var base: float = HOLD_TIMER_BY_SKILL[skill_tier]
    var bonus: float = FINE_PICK_BONUS if pick_type == "fine" else 0.0
    return base + bonus
```

### Overlay Open (not a camera cut)

```gdscript
# LockpickingUI.gd — a CanvasLayer that renders over the blurred world
func open(lock: LockData) -> void:
    lock_data = lock
    active_pins = _generate_pins(lock.tier, lock.pin_count)
    pins_set = 0
    current_angle = 0.0
    WorldBlur.enable()          # BackBufferCopy + blur shader on the world viewport
    show()
    # World continues running — no get_tree().paused = true
```

### Resonance Check

```gdscript
const RESONANCE_ZONE_DEGREES: Dictionary = {0: 40.0, 1: 25.0, 2: 15.0, 3: 8.0}

func _check_resonance(angle: float) -> void:
    for pin in active_pins:
        var dist: float = _angular_distance(angle, pin.position_degrees)
        var zone: float = RESONANCE_ZONE_DEGREES[lock_data.tier] / 2.0
        if dist < zone:
            var intensity: float = 1.0 - (dist / zone)
            _show_resonance(intensity, pin.is_false)
```

### Pick Snap and Consumption

```gdscript
func _on_pick_snap() -> void:
    InventoryManager.remove_item("lockpick_fine" if pick_type == "fine" else "lockpick_standard", 1)
    pins_set = 0
    active_pins = _generate_pins(lock_data.tier, lock_data.pin_count)  # randomize positions
    _play_snap_effect()
    if not _player_has_picks():
        close()
        InteractionPrompt.show("No picks.", "lock_icon", 2.0)
```

### Skill Advancement

```gdscript
func _on_unlock() -> void:
    WorldBlur.disable()
    close()
    var lock_id: String = lock_data.lock_id
    if not GameState.get_flag("picked_" + lock_id):
        GameState.set_flag("picked_" + lock_id, "true")
        var xp: int = [20, 40, 70, 120][lock_data.tier]  # more XP for harder locks
        SkillManager.add_xp("lockpicking", xp)
```
