# Lockpicking System Design

How Roland opens locked doors and containers.

> Cross-reference: `design/ITEM_LIBRARY.md` for lockpick item stats, stack sizes, and vendor availability.
> `design/INVESTIGATION_SYSTEM.md` for how examining a lock first gives free tier information.
> `design/SKILLS_AND_PROGRESSION.md` for the Lockpicking sub-skill under the Exploration domain.
> `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` for lockpick storage (consumable, not quick-slotted).

---

## Design Philosophy

**The lock is a puzzle Roland is solving with his hands, not a menu he navigates.** Lockpicking in this game is a physical activity — tactile, tense, and readable. A player learns how locks work the way Roland does: by doing it badly at first, then better.

**Inspired by KCD2, reimagined.** Kingdom Come: Deliverance 2 uses a cylindrical tumbler — the player physically rotates a pick inside a cylinder, feeling for where the lock yields through controller rumble and audio. That feeling of *exploration inside the lock* is the right tone: you are searching, not executing a sequence. This system keeps that feel but moves to a different geometry that works in 2D screen space and reads clearly at isometric camera angles.

**One consumable per attempt, not per pin.** Tension pins are set one at a time, but a single lockpick lasts the whole attempt. You lose it only if the lock resets — either from your mistake or from the spring catching you. A skilled player uses far fewer picks than a careless one.

**No punishment for trying a lock you can't open.** Locks above Roland's current skill read as "too complex to pick cleanly" before he commits. He can still try — and he might get lucky or find a workaround — but he won't waste picks on an attempt the game has told him he cannot win.

---

## The Resonance Pick — Core Mechanic

### What It Looks Like

When Roland kneels at a locked container or door, the screen shows a **circular lock face** rendered as a close-up diegetic view: a dark iron disc with a central keyhole, framed by Roland's fingers at the edge of the frame. This is not a UI overlay — it is a camera cut to a close-up view. The rest of the scene is visible as a blurred background.

The **pick** is a fine metal probe that enters the lock face from the center. The player controls which direction it points by rotating it around the dial — a clock face mental model: twelve o'clock is straight up, three o'clock is right, etc. Input is A/D (keyboard) or left/right stick (controller).

Somewhere on that dial, one or more **tension pins** are seated. The player cannot see where they are. Finding them is the game.

---

### How Pins Are Found — Resonance Feedback

As the pick rotates, it passes across the lock face. When the tip approaches a pin, three feedback channels activate simultaneously:

1. **Visual:** The pick tip develops a faint amber glow that intensifies as it gets closer to the pin position. At the pin's center, it pulses.
2. **Audio:** A low metallic hum grows in pitch as the pick nears a pin. At center: a short ringing tone.
3. **Haptic (controller):** Increasing rumble as pick approaches; a short firm pulse at the pin center.

The player **holds the pick still** at that position (stop rotating). A **set bar** appears below the lock face — a short fill animation. When it completes, the pin sets with an audible click.

Then the player sweeps to find the next pin.

### What Makes It Feel Different from KCD2

KCD2's cylinder is 3D — the player physically rotates and lifts a pick inside a virtual barrel, fighting the lock's spring pressure while hunting for the sweet spot. The geometry is a cylinder; the motion is rotation plus vertical lift; the visual metaphor is a literal lock tumbler.

This system's geometry is a **flat radial plane** — a clock face. The motion is single-axis rotation (sweep around the face). There is no vertical dimension, no lifting. The difficulty comes from:
- **Zone width:** How wide the resonance zone is around each pin. Simple locks have wide zones (easy to feel). Complex locks have narrow zones (must be precise).
- **Pin count:** How many pins must be set before the lock opens. Simple = 1, Standard = 2, Complex = 3.
- **False resonances on Complex locks:** Complex locks have 1–2 positions on the dial that produce a weaker false resonance — the visual and audio triggers look similar but the set bar fills only halfway before stalling. The player must learn to distinguish the genuine tone from the false one. (The genuine resonance has a slightly warmer pitch and a clean pulse; the false one has a faintly hollow tone and an irregular pulse.)

---

## Lock Tiers

| Tier | Pins | Resonance zone width | False resonances | Typical use |
|---|---|---|---|---|
| **Simple** | 1 | Wide (~40° arc) | None | Common doors, basic containers, old padlocks |
| **Standard** | 2 | Medium (~25° arc each) | None | Locked rooms, merchant strongboxes |
| **Complex** | 3 | Narrow (~15° arc each) | 1–2 false resonances | Archive restricted doors, noble quarters, Brotherhood caches |
| **Masterwork** | 3 | Very narrow (~8° arc) | 2 false resonances | Key story locks (Brotherhood vault, Ashen Hand archive) |

**Masterwork locks** require the **Trained lockpicking sub-skill** to attempt cleanly. Roland can examine a Masterwork lock at Novice skill and will narrate: *"This is finer work than I've handled. I'd need a steadier hand."* He can still attempt it, but his resonance feedback is degraded — the hum barely registers, requiring guesswork. Players who attempt this will use several picks.

---

## The Pick Snap — When You Fail

A pick can snap in two situations:

1. **Holding too long without setting.** Each pin position has a **hold timer** — about 3 seconds at Standard skill. If Roland holds the pick at a pin position and the set bar does not complete in time (because he is slightly off-center, or it is a false resonance), the spring pressure increases and the pick snaps.
2. **Moving while the spring is loaded.** Once the first pin is set on a 2- or 3-pin lock, the lock's internal spring applies back-pressure. If Roland sweeps too fast through the danger zone (the half of the dial farthest from the set pins), the pick catches and snaps. On Simple locks there is no back-pressure. On Complex locks the danger zone is larger and the snap happens faster.

**On snap:** Short sharp audio cue. The pick breaks in Roland's hand (brief animation). The lock resets — all set pins return to unsent. A new pick is consumed from inventory on the next attempt.

If Roland has no more picks, he cannot try again. He will need to find picks in the world or buy them from a vendor.

---

## Examining a Lock First

Before attempting to pick a lock, Roland can **examine** it (press E at close range without a pick equipped, or hold E for the interaction menu). This is a free Type 1 investigation — no skill check, no cost.

Roland narrates what he observes. The journal entry he makes (shown briefly in the upper-left journal overlay) gives:
- Lock tier (Simple / Standard / Complex / Masterwork)
- Number of pins required
- A flavor note: *"Old iron, good condition. The cylinder turns smooth — someone oils this."*

This information is also useful for deciding whether to attempt the lock at all. Roland noting "Complex" tells the player to bring extra picks.

Examining does not consume a pick. The close-up camera cut does not occur during examination — Roland just crouches and looks.

---

## Lockpick Items

Lockpicks are consumable items stored in inventory. They are not quick-slotted and cannot be used mid-combat.

| Item | Weight | Carries | Notes |
|---|---|---|---|
| **Lockpick** | 0.05 kg each | Up to 20 in stack | Standard. Available from General Merchants, Brotherhood caches, found in the world. |
| **Fine Lockpick** | 0.05 kg each | Up to 10 in stack | Slower snap timer (+1.5s hold tolerance) and slightly wider resonance feedback. Useful on Complex locks. Sold only by Brotherhood contacts and specialty vendors at FRIENDLY+. |

A Fine Lockpick does not make Masterwork locks easier — it extends forgiveness on hold timing, not resonance zone width.

---

## Lockpicking Skill — Exploration Domain

Roland's lockpicking improves through the **Exploration domain** in the skills system. The sub-skill is **Lockpicking**.

| Sub-skill tier | Effect |
|---|---|
| **Novice** (default) | Can cleanly attempt Simple and Standard locks. Masterwork degraded feedback. |
| **Trained** | Can cleanly attempt all tiers including Masterwork. Resonance zones feel 15% wider (not actually wider — Roland's hands are steadier, so the same zone seems easier). |

Lockpicking sub-skill increases by using it. Every successful lock opened at the current tier's challenge level has a chance to advance the sub-skill. Roland will not improve by picking the same Simple lock repeatedly — the game tracks unique lock IDs, and only the first successful open contributes to advancement.

**Trainer:** A Brotherhood contact (unnamed, available in Caer Brannoch at NEUTRAL+) can train Roland to Trained tier in exchange for a small favor. This skips the in-world advancement and is the only shortcut.

---

## Stealth and Detection During Lockpicking

Lockpicking takes time. Roland is stationary and focused. He is detectable.

- **Enemy detection:** While picking, Roland's movement radius is 0. His vision range for detection is unchanged, but he cannot react (dodge, sprint) while the lock UI is active.
- **Interruption:** If an enemy enters detection range during picking, the lock UI closes. Roland stands up (0.5s animation). The pick is **not consumed** on interrupt — only on snap.
- **Companion behavior:** Companions hold position near Roland during lockpicking unless ordered to Engage. Orion will murmur a warning bark if he spots someone approaching.

Skilled players will clear the area before picking, or station Orion as a lookout using the Hold Position order.

---

## Keys

Most named locks have a key somewhere in the world. Keys are Quest Items — they weigh nothing, they cannot be dropped, and they are found through investigation, NPC dialogue, or looting.

**Using a key is always faster and silent.** Players who find keys bypass lockpicking entirely. Finding a key is the reward for thorough exploration; lockpicking is the fallback for players who didn't find it or who are in a hurry.

Some locks have no key in the world — they can only be picked.

A key can only be used once and is removed from Roland's inventory after use (it stays on the keyring visually but is marked used in the journal).

---

## Locked Containers vs. Locked Doors

The same mechanic applies to both. The difference is context and consequence:

- **Containers** (chests, strongboxes, lockboxes): Picking is always private. No NPC can see into a chest. Consequence of picking is only what's inside.
- **Doors** (locked rooms, restricted areas): Opening a locked door may bring Roland into a space he is not supposed to be in. If an NPC later finds the door open or catches Roland inside, it has disposition consequences. The picking itself is private — only the trespass matters.

**Quest-critical locks** have a small brass-colored marker on their icon in Roland's journal. These locks are always openable, regardless of Roland's skill tier — if the story requires Roland to get through, he gets through, even if the feedback is degraded and it costs him several picks.

---

## GDScript Integration Notes

### Lock Resource

```gdscript
class_name LockData
extends Resource

@export var lock_id: String
@export var tier: int                  # 0=Simple, 1=Standard, 2=Complex, 3=Masterwork
@export var pin_count: int             # 1–3
@export var key_item_id: String        # "" if no key exists in the world
@export var quest_critical: bool = false
@export var examine_note: String       # Roland's voiced examination line
```

### Interaction Entry Point

```gdscript
# On E-press at a locked door or container:
func _on_interact():
    if Input.is_action_just_pressed("interact"):
        if player_has_key(lock_data.key_item_id):
            use_key()
        elif lock_data.quest_critical or player_has_lockpicks():
            LockpickingUI.open(lock_data)
        else:
            show_interaction_prompt("No key. No picks.")
```

### Lock Picking UI

```gdscript
# LockpickingUI.gd — controls the radial dial and pin-set logic

const SNAP_HOLD_TIME_BASE: float = 3.0   # seconds before snap if stationary and off-center
const SNAP_HOLD_FINE: float = 1.5        # bonus seconds for Fine Lockpick
const RESONANCE_ZONE_DEGREES: Dictionary = {
    0: 40.0,   # Simple
    1: 25.0,   # Standard
    2: 15.0,   # Complex
    3: 8.0     # Masterwork
}

var pins_set: int = 0
var current_angle: float = 0.0
var pick_type: String = "standard"   # or "fine"

func _process(delta: float) -> void:
    var rotate_input: float = Input.get_axis("lock_rotate_left", "lock_rotate_right")
    current_angle = fmod(current_angle + rotate_input * ROTATE_SPEED * delta, 360.0)
    _check_resonance(current_angle)

func _check_resonance(angle: float) -> void:
    for pin in active_pins:
        var dist: float = _angular_distance(angle, pin.position_degrees)
        var zone: float = RESONANCE_ZONE_DEGREES[lock_data.tier] / 2.0
        if dist < zone:
            var intensity: float = 1.0 - (dist / zone)
            _show_resonance(intensity, pin.is_false)

func _on_pin_set(pin: PinData) -> void:
    pins_set += 1
    if pins_set >= lock_data.pin_count:
        _unlock()
```

### Lockpick Consumption

```gdscript
func _on_pick_snap() -> void:
    InventoryManager.remove_item("lockpick_standard" if pick_type == "standard" else "lockpick_fine", 1)
    pins_set = 0
    active_pins = _regenerate_pin_positions()   # pins randomize on each attempt
    LockpickingUI.play_snap_animation()
    if not player_has_lockpicks():
        LockpickingUI.close()
        show_interaction_prompt("Out of picks.")
```

### Skill Advancement

```gdscript
# After a successful pick:
func _on_unlock() -> void:
    var lock_id: String = lock_data.lock_id
    if lock_data.tier >= SkillManager.get_subskill_tier("lockpicking") \
       and not GameState.get_flag("picked_" + lock_id):
        GameState.set_flag("picked_" + lock_id, "true")
        SkillManager.add_xp("lockpicking", 40)
```
