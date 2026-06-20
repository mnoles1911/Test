# Input & Controls Design

The full control scheme for Game One — keyboard/mouse and controller.

> Cross-reference: `design/COMBAT_DESIGN_3D.md` for combat input (attack, block, dodge).
> `design/HUD_AND_UI.md` for menu navigation and quick slot cycling.
> `design/ACCESSIBILITY_AND_SETTINGS.md` for remapping and input adjustments.
> `DESIGNER_TODO.md` → Section 1 for Godot Input Map setup required.

---

## UE5 Port — First-Person Test Pawn Controls (dev rig)

> **Scope:** this section documents the **UE5 dev test pawn** (`AMiraFPCharacter`, module
> MiraThalCore), used to drive/verify the streamed voxel world. It is NOT the final game control
> scheme — the canonical scheme (Roland, third-person, remappable) is everything below this section.
> The final game camera is third-person over-shoulder (`design/CAMERA_AND_PERSPECTIVE.md`); this
> first-person rig comes first only because it's the simplest way to fly the 5 km map and test
> streaming/LOD/dig. As of 2026-06-18 this pawn is the default Play pawn on `/Game/Maps/MiraStreamTest`.

**Implementation note:** the EnhancedInput plugin (on in this project) forces the
`UEnhancedInputComponent`, on which legacy `BindAxis` still fires but legacy `BindAction` is **silently
dropped**. So WASD + mouse use legacy axis bindings, but every BUTTON goes through **Enhanced Input** —
`UInputAction`s + a `UInputMappingContext` created in-code in the pawn's constructor (no Input asset
files), added in `BeginPlay`. Continuous fly up/down is applied every frame in `Tick` from
press/release flags, because the per-frame `ETriggerEvent::Triggered` event proved unreliable here.

| Key | Walk/Run mode | Fly mode |
|---|---|---|
| **W A S D** | Move (camera-relative; W = where you look) | Same; in fly, look-up + W climbs |
| **Mouse** | Look (yaw rotates the body so move stays camera-relative; pitch = camera) | Same |
| **Space** | **Jump** | **Hold = ascend** (gain altitude, continuous) |
| **Left Shift** | **Hold = sprint** (momentary, not a toggle) | **Hold = descend** (lose altitude, continuous) |
| **C** | **Crouch toggle** (lower view ↔ standing; standing default) | — |
| **F** | Toggle **Walk ↔ Fly** | Toggle **Walk ↔ Fly** |
| **LMB** | **Dig** — camera line-trace (80 m reach) carves a **3×3×3** voxel box at the crosshair | Same |

Each button flashes a short on-screen confirmation (dev feedback) when it fires.

**Camera / body:** human capsule (90 cm half-height → 180 cm / 18-voxel tall), eye height **168 cm**
above ground when standing (camera follows the capsule down when crouched), first-person **FOV 95°**.
Mouse is captured (cursor hidden) during play.

**Dig aiming aids (mirror the Godot destroy-preview):** a centre **crosshair** is drawn by `AMiraHUD`
(the game mode's HUD class), and a **3D wireframe outline** of the exact 3×3×3 volume the next dig will
remove is drawn every frame from `AVoxelWorld::ComputeCarvePreviewWorld` — it uses the identical
`compute_carve_box` math as the real carve, so what you outline is what you dig. `DigSizeVoxels` (default
3) and `bShowDigPreview` are pawn properties.

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
| `ui_left` | A only | Left stick left | Move left |
| `ui_right` | D only | Left stick right | Move right |
| `ui_up` | W only | Left stick up | Move forward |
| `ui_down` | S only | Left stick down | Move backward |
| `sprint` | Left Shift (hold) | Left stick click / L3 | Sprint (drains endurance; locked after exhaustion until recovery) |
| `crouch` | C (toggle press) | — | Toggle crouch stance; slower speed, blocks sprint |
| `dodge` | Space | B / Circle | Directional dodge roll (costs endurance) |

**Arrow keys are reserved for camera rotation only** — they are not bound to `ui_*` actions. Movement is WASD-only on KB+M. Movement is camera-relative: W always moves toward where the camera (and Roland) faces.

### Combat Actions

| Action name | Default (KB) | Default (Controller) | Description |
|---|---|---|---|
| `attack` | LMB (hold + mouse flick + release; ≥ 0.4 s held = charged 2x) | R2 / RT | Bannerlord-style hold-flick-release directional swing |
| `parry_block` | RMB (tap ≤ 0.14 s = parry, hold = directional block) | L2 / LT | Block stance (matched direction = 0 dmg) or parry timing (300 ms window) |

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

### Build Mode (Player Construction)

Build Mode is the placement UI for player-built structures (schematics) and per-voxel detail edits. Activated with a held key — releasing the key exits Build Mode. See `design/CRAFTING.md` → Carpentry Bench for the schematic system, and `design/3D_VOXEL_MIGRATION.md` → "Player-Built Structures" for the canonical model.

| Action name | Default (KB) | Default (Controller) | Description |
|---|---|---|---|
| `build_mode` | B (hold) | Right shoulder + D-pad up | Hold to enter Build Mode. Releases on key-up. While in Build Mode, a translucent ghost of the selected schematic / building voxel previews placement at the crosshair, snapping appropriately. |
| `build_confirm` | LMB | A / Cross | Place the schematic / voxel block at the ghost position. Material cost deducted from inventory. Rejected silently inside NoEditZones (ghost turns red). |
| `build_cancel` | RMB | B / Circle | Cancel placement (no material spent). |
| `build_rotate` | R | Right stick click | Rotate the ghost 90° around its vertical axis (where applicable). |
| `build_detail_toggle` | Tab | D-pad right | Toggle between Schematic submode (placing prefab building pieces) and Detail submode (placing single voxel blocks one at a time). |
| `build_select_next` | Mouse Scroll Up | Right stick up | Cycle to the next schematic / building voxel in the player's crafted inventory. |
| `build_select_prev` | Mouse Scroll Down | Right stick down | Cycle to the previous schematic / building voxel. |

Edit-verb tools (axe, pickaxe, shovel) are NOT Build Mode actions — they're handled like weapons. Equip the tool in the Weapon slot, then `attack` swings it. If the swing connects with a matching voxel material (and no enemy is in front), `VoxelEditManager` removes voxels and yields material to inventory. Inside a NoEditZone, the swing still animates and damages enemies but does not remove voxels — Roland's bark *"This place doesn't yield to me."* fires once per session per zone.

Explosives (Powder Charge, Sapper's Bundle) are **equipped to the Weapon slot** like tools and **thrown via `attack` (LMB)** when equipped. `ThrowableHandler` short-circuits unless `ITEM_REGISTRY[equipped_id].type == "throwable"`; `EditToolHandler` short-circuits in the inverse case. Result: same LMB key, action follows what's equipped (mine / fill / throw). Quick-slot number keys (`quick_slot_1` through `quick_slot_4`) are the swap shortcut — see `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` → "Quick Slot Bar".

### Menu and UI Actions

| Action name | Default (KB) | Default (Controller) | Description |
|---|---|---|---|
| `open_journal` | J | Select / Back | Open/close journal overlay |
| `open_inventory` | I | Y / Triangle | Open/close inventory screen |
| `pause` | Escape | Start | Open/close pause menu |
| `debug_overlay` | F1 | — | Toggle debug overlay (dev only) |
| `map_note` | M (in journal Map tab) | — | Add map annotation at current cursor position |

### Camera Actions

| Action name | Default (KB/M) | Default (Controller) | Description |
|---|---|---|---|
| `camera_left` | Left Arrow | Right stick left | Rotate camera left (keyboard fallback) |
| `camera_right` | Right Arrow | Right stick right | Rotate camera right (keyboard fallback) |
| `camera_up` | Up Arrow | Right stick up | Tilt camera up (keyboard fallback) |
| `camera_down` | Down Arrow | Right stick down | Tilt camera down (keyboard fallback) |
| `freelook_camera` | F2 (hold) | — | Hold to enter freelook: mouse orbits camera without rotating Roland. Release to re-center. |

**KB+M primary:** Camera rotation is driven by **mouse motion** (`InputEventMouseMotion`) directly in `CameraRig.gd` — no Input Map action needed. Mouse horizontal → yaw (standard mode: rotates Roland's body; freelook mode: orbits the arm); mouse vertical → pitch. Arrow key actions are fallbacks for players who prefer keys.

**Scroll wheel zoom:** Mouse scroll up/down zooms the camera in/out (arm length 2m–10m). Works in both standard and freelook modes.

**Controller:** Right stick drives camera directly via `Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")`.

`Input.mouse_mode` is set to `CAPTURED` during play so the cursor is hidden and all mouse motion feeds the camera. It switches to `VISIBLE` when any menu opens.

---

## Keyboard and Mouse — Quick Reference

Confirmed KB+M layout. No key conflicts.

| Key / Input | Action | Notes |
|---|---|---|
| W A S D | Move | 8-directional, camera-relative: W always moves toward where Roland faces |
| Mouse drag | Camera rotate | Horizontal = yaw (rotates Roland's body in standard mode); vertical = pitch. Read directly in `CameraRig.gd` via `InputEventMouseMotion` — no Input Map action needed |
| F2 (hold) | `freelook_camera` | Freelook mode: mouse orbits camera without rotating Roland. On release, arm re-centers |
| Left Arrow / Right Arrow | `camera_left` / `camera_right` | Keyboard fallback for camera rotate (also works in freelook) |
| Up Arrow / Down Arrow | `camera_up` / `camera_down` | Keyboard fallback for camera tilt |
| Mouse Scroll Up / Down | Zoom | Camera arm length 2m–10m. Works in both standard and freelook modes |
| E | `interact` | Talk, examine, open door, rest at fire |
| Q | `quick_slot_prev` | Cycle quick slot left |
| LMB | `attack` | Hold + flick mouse + release = directional swing; ≥ 0.4 s held = charged 2x |
| RMB | `parry_block` | Tap (≤ 0.14 s) = parry; hold = directional block |
| Space | `dodge` | Directional roll (costs endurance) |
| Left Shift | `sprint` | Hold to sprint (drains endurance; exhaustion locks sprint until recovery) |
| C | `crouch` | Toggle crouch; reduces speed to ~2 m/s; sprint blocked while crouching |
| J | `open_journal` | Open/close journal overlay |
| I | `open_inventory` | Open/close inventory screen |
| Escape | `pause` | Open/close pause menu |
| F1 | `debug_overlay` | Toggle debug overlay (dev only) |

**During development** (before context-sensitive E logic is in place): rebind `quick_slot_next` to **F** to avoid conflict with `interact` on E.

### Mouse in Combat

- **LMB / RMB** are the primary combat inputs. The mouse cursor is hidden during combat and exploration — Roland moves with WASD, the camera follows mouse movement.
- **Mouse scroll wheel** zooms the camera in/out (arm length 2m–10m) in all modes.
- Melee attacks fire toward Roland's current facing direction. Free-aim — there is no lock-on. The `MouseDirectionSampler` reads the last ~120 ms of mouse motion at the press moment to pick swing direction (UP=THRUST, DOWN=OVERHEAD, LEFT/RIGHT = side swings).

### Mouse in Menus

When a menu is open (journal, inventory, camp menu), the cursor reappears and functions as a standard UI cursor — hover to highlight, click to interact. `Input.mouse_mode` switches between `CAPTURED` (during play) and `VISIBLE` (during menus).

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

Status as of 2026-05-01: all core actions below are configured in `project.godot`. Items marked ✓ are live.

- ✓ `interact` — E key. Required by `DialogueTrigger3D.gd` and `NPC.gd`.
- ✓ `sprint` — Left Shift
- ✓ `attack` — Left Mouse Button
- ✓ `block` — Right Mouse Button
- ✓ `dodge` — Space
- ✓ `lock_on` — Middle Mouse Button
- ✓ `quick_slot_prev` — Q
- ✓ `camera_left` / `camera_right` / `camera_up` / `camera_down` — Arrow keys (KB fallback; controller right stick). Not needed for KB+M since mouse motion drives the camera directly in `CameraRig.gd`.
- ✓ `freelook_camera` — F2 (physical key). Hold to orbit camera without rotating Roland; release to re-center.
- ✓ `open_journal` — J
- ✓ `open_inventory` — I
- ✓ `pause` — Escape
- ✓ `debug_overlay` — F1
- ✓ `crouch` — C (toggle press; blocks sprint while active)
- [ ] `quick_slot_next` — E (context: only fires when no interactable in range). During early development, rebind to F temporarily.
- [ ] `next_target` / `prev_target` — Mouse Scroll Up / Down (optional; scroll zoom takes priority).

Note: `quick_slot_next` and `interact` both default to E. These are context-sensitive: `interact` fires when near an interactable object; `quick_slot_next` fires during combat when no interactable is in range. In GDScript, context is managed by checking `_nearest_interactable != null` — see the GDScript Notes section below. During early development before context logic is in place, rebind `quick_slot_next` to F temporarily.

See `DESIGNER_TODO.md` → Section 1 for the full manual setup checklist.

---

## GDScript Notes

### Reading movement input

```gdscript
# Player3D.gd — camera-relative 8-directional XZ movement:
var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
var local_dir := Vector3(input_dir.x, 0.0, input_dir.y)
# Multiply through the player's transform.basis so W always moves toward
# where Roland (and the camera) is currently facing.
var direction := (transform.basis * local_dir).normalized()
# NEVER map input_dir.y to velocity.y — that launches the player upward.
# The ground plane is XZ; Y is always gravity only.
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
