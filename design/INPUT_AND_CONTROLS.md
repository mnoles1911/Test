# Input & Controls Design

The full control scheme for Game One — keyboard/mouse and controller.

> Cross-reference: `design/COMBAT_DESIGN_3D.md` for combat input (attack, block, dodge).
> `design/HUD_AND_UI.md` for menu navigation and quick slot cycling.
> `design/ACCESSIBILITY_AND_SETTINGS.md` for remapping and input adjustments.
> `DESIGNER_TODO.md` → Section 1 for Godot Input Map setup required.

---

## Design Philosophy

**Controls are learnable, not complex.** Roland does three primary things: move, fight, and interact. Every control serves one of these. There are no mode switches, no complex input sequences, no button combinations except where the interaction is specifically designed to feel like effort (power attack charge).

**Keyboard/mouse and controller are equal citizens.** Both input methods should feel natural. Neither is an afterthought. The control scheme on both is designed around what each method does well — mouse aim for cursor interactions, analog stick for smooth movement.

**Remappable by default.** All actions are remappable in Settings → Controls. No action is locked to a physical key. See `design/ACCESSIBILITY_AND_SETTINGS.md`.

---

## Godot Input Actions

All input is routed through Godot's Input Map. Physical keys are defaults only — players can rebind everything.

### Movement Actions

| Action name | Default (KB) | Default (Controller) | Description |
|---|---|---|---|
| `ui_left` / `move_left` | A | Left stick left | Move left |
| `ui_right` / `move_right` | D | Left stick right | Move right |
| `ui_up` / `move_forward` | W | Left stick up | Move forward |
| `ui_down` / `move_back` | S | Left stick down | Move backward |
| `sprint` | Left Shift (hold) | Left stick click / L3 | Sprint (drains endurance) |
| `dodge` | Space | B / Circle | Directional dodge roll (costs endurance) |

Note: `ui_left/right/up/down` are Godot's built-in UI navigation actions. Movement reads from these plus arrow keys by default. Add explicit `move_*` actions if finer control is needed.

### Combat Actions

| Action name | Default (KB) | Default (Controller) | Description |
|---|---|---|---|
| `attack` | LMB (tap = light, hold = charge) | R2 / RT (tap/hold) | Light attack or power attack charge |
| `block` | RMB (hold = block, tap = parry) | L2 / LT (hold/tap) | Block stance or parry timing |
| `lock_on` | Middle Mouse / Tab | R3 / Right stick click | Toggle lock-on to nearest enemy |
| `next_target` | Mouse Scroll Up | Right stick right | Cycle lock-on target right |
| `prev_target` | Mouse Scroll Down | Right stick left | Cycle lock-on target left |

**Tap vs hold detection:** `attack` and `block` use press duration to distinguish tap from hold. In GDScript: `Input.is_action_just_pressed("attack")` = tap; `Input.is_action_pressed("attack")` held for >0.15 seconds = charge/hold.

### Interaction Actions

| Action name | Default (KB) | Default (Controller) | Description |
|---|---|---|---|
| `interact` | E | A / Cross | Press-E interact: talk, examine, open, rest |
| `quick_slot_1` | 1 | D-pad up | Activate quick slot 1 |
| `quick_slot_2` | 2 | D-pad down | Activate quick slot 2 |
| `quick_slot_3` | 3 | D-pad left | Activate quick slot 3 |
| `quick_slot_4` | 4 | D-pad right | Activate quick slot 4 |
| `quick_slot_next` | E (hold inventory open) | Q (right shoulder) | Cycle quick slot selection right |
| `quick_slot_prev` | Q (hold inventory open) | R (left shoulder) | Cycle quick slot selection left |

Note: `quick_slot_next` / `quick_slot_prev` are the cycle inputs used mid-combat. The numbered slots 1–4 are for direct selection when there is time.

### Menu and UI Actions

| Action name | Default (KB) | Default (Controller) | Description |
|---|---|---|---|
| `open_journal` | J | Select / Back | Open/close journal overlay |
| `open_inventory` | I | Y / Triangle | Open/close inventory screen |
| `pause` | Escape | Start | Open/close pause menu |
| `debug_overlay` | F1 | — | Toggle debug overlay (dev only) |
| `map_note` | M (in journal Map tab) | — | Add map annotation at current cursor position |

### Camera Actions

| Action name | Default (KB) | Default (Controller) | Description |
|---|---|---|---|
| `camera_left` | Q | Right stick left | Rotate camera left (if enabled) |
| `camera_right` | E | Right stick right | Rotate camera right (if enabled) |

Camera rotation is **disabled by default** in Game One — the camera follows at a fixed angle. These actions are registered for future use if `CameraRig.gd` has `allow_horizontal_rotation = true` toggled on. See `DESIGNER_TODO.md` → Section 1.

---

## Keyboard and Mouse Specifics

### Mouse in Combat

- **LMB / RMB** are the primary combat inputs. The mouse cursor is hidden during combat and exploration (the camera does not follow the cursor — Roland moves with WASD, the camera follows him).
- **Mouse scroll wheel** cycles lock-on targets when locked on.
- There is no mouse-aim for melee attacks. Roland always attacks toward his current facing direction or lock-on target.

### Mouse in Menus

When a menu is open (journal, inventory, camp menu), the cursor reappears and functions as a standard UI cursor — hover to highlight, click to interact. The `Input.mouse_mode` switches between `CAPTURED` (during play) and `VISIBLE` (during menus).

---

## Controller Specifics

### Analog Movement

Left stick provides 8-directional movement. Stick magnitude maps to movement speed — a slight tilt walks; full deflection runs. Sprint still requires the L3 press (or rebind).

### Controller Rumble

Light rumble feedback for:
- Landing a power attack (short, strong pulse)
- Taking a significant hit (short, proportional to damage)
- Parry success (very brief, sharp pulse — distinct from hit feedback)
- Roland at critical HP (slow, low-intensity pulse — communicates the danger without being intrusive)

Rumble is controlled by the **Haptic Feedback** setting (on by default). See `design/ACCESSIBILITY_AND_SETTINGS.md`.

### Controller Navigation in Menus

Journal and inventory use D-pad navigation between tabs and items. The left stick also navigates. A/Cross confirms; B/Circle cancels. Y/Triangle opens inventory from anywhere; Select opens journal.

---

## Input Buffering

A small input buffer (~0.1 seconds) exists for combat actions:

- If the player presses `attack` during the recovery frames of a previous attack, the next attack queues and fires as soon as the recovery window ends.
- This prevents the "I pressed it but nothing happened" frustration while preserving the commitment design (you cannot skip recovery frames, only queue the next action).

Buffer only applies to `attack` and `dodge`. Block and interact fire immediately on press.

---

## Required Godot Input Map Setup

The following actions **must be configured in Godot Project Settings → Input Map** before they will function:

- `interact` — E key (and A/Cross for controller). Required by `DialogueTrigger3D.gd` and `NPC.gd`.
- `sprint` — Left Shift
- `dodge` — Space
- `lock_on` — Middle Mouse Button / Tab
- `quick_slot_next` — Q (in-combat context)
- `quick_slot_prev` — E (in-combat context, separate from `interact` context)
- `camera_left` / `camera_right` — Q and E (only needed if horizontal rotation enabled)
- `open_journal` — J
- `open_inventory` — I
- `debug_overlay` — F1

Note: `quick_slot_next` and `interact` both default to E. These are context-sensitive: `interact` fires when near an interactable object; `quick_slot_next` fires during combat. In GDScript, context is managed by checking `near_interactable` state — if true, E = interact; if false, E = cycle slot. Alternatively, rebind one of them in the Input Map during development if the context logic is not yet in place.

See `DESIGNER_TODO.md` → Section 1 for the full manual setup checklist.

---

## GDScript Notes

### Reading movement input

```gdscript
# Player3D.gd — 8-directional XZ movement from input:
var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
var direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
# ui_up/down map to -Z/+Z in world space; ui_left/right to -X/+X.
# NEVER map input_dir.y to velocity.y — that launches the player upward.
```

### Tap vs hold for attack/block

```gdscript
# In CombatHandler.gd:
var attack_held_time: float = 0.0
const POWER_ATTACK_THRESHOLD: float = 0.20  # seconds of hold to trigger charge

func _process(delta: float) -> void:
    if Input.is_action_pressed("attack"):
        attack_held_time += delta
        if attack_held_time >= POWER_ATTACK_THRESHOLD:
            _enter_power_charge_state()
    elif Input.is_action_just_released("attack"):
        if attack_held_time < POWER_ATTACK_THRESHOLD:
            _execute_light_attack()
        else:
            _release_power_attack()
        attack_held_time = 0.0
```

### Context-sensitive E key

```gdscript
# In Player3D.gd:
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("interact"):
        if _nearest_interactable != null:
            _nearest_interactable.interact()
        elif _in_combat:
            _cycle_quick_slot_next()
```
