# HUD & UI Design

How the game communicates with the player without pulling them out of the world.

> Cross-reference: `design/JOURNAL_UI.md` for the five-tab journal overlay.
> `design/INVESTIGATION_SYSTEM.md` for the observation text overlay.
> `design/REST_AND_CAMP.md` for the camp menu layout.
> `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` for the quick slot bar and inventory screen.
> `design/CONVERSATION_SYSTEM.md` for the Dialogic dialogue UI.

---

## Design Philosophy

**The world speaks for itself.** Roland's HP is visible on his body — he limps, he breathes harder, he flinches. The UI enforces what the world already shows. Numbers appear only when the player explicitly opens a screen. During play, the HUD is minimal.

**No quest compass, no waypoints, no objective arrows.** The player navigates by reading the world and the journal — not by following a floating marker. See `design/WORLD_NAVIGATION.md` for how orientation is handled.

**Diegetic first.** When a system can be represented inside the world (Roland pulling out a flask, an inventory as Roland's pack, a map as an actual map), it should be. Where pure UI is unavoidable, it should feel like Roland's handwriting and tools — worn leather, ink on parchment, charcoal marks — not a modern HUD chrome.

---

## In-World HUD (Always On)

These elements are visible during active play. Everything else is accessed through menus.

### HP Bar

A narrow bar at the lower left. Two layers stacked:

- **Red fill** — Roland's current HP (depletes as he takes hits)
- **Dark red fill** — portion of HP that has become "wound HP" (cannot be restored by potions or bandages; only rest or Boneknit Compound)

The bar does not show numbers. The visual proportion is sufficient. When HP is above 70%, the bar is a muted tone — not glowing, not pulsing. When HP drops below 30%, the bar gains a slow pulse. Below 10%, the edges of the screen darken (vignette) as a physical signal.

The bar does not regenerate passively. It is a record of damage taken, not a resource that replenishes on its own.

### Endurance Bar

A narrow bar just above the HP bar. Lighter orange tone.

- Depletes when Roland attacks, blocks, sprints, or dodges.
- Refills gradually when Roland is not performing those actions.
- When fully depleted: Roland staggers briefly and cannot attack for ~1.5 seconds. This is the stagger state — recoverable, but dangerous.
- The bar pulses faintly when endurance is critically low (below 15%).

**Grey cap:** Roland's maximum effective endurance is slightly capped when wounded. A fine grey line marks the current cap. If wound HP is significant, this cap may be noticeably reduced from the bar's full length — the bar graphically shows Roland is fighting below capacity.

### Quick Slot Bar

Four slots at the bottom center of the screen, visible during combat and exploration, hidden during dialogue.

Each slot shows:
- The item icon
- A quantity count (bottom right of the slot, small)
- A radial fill animation when the item is being used (the use window)
- Dimming effect when the slot is empty

Cycle slots with Q/E. Activate with F. Cannot change slot assignment mid-combat.

When Roland uses an item, the slot's radial animation plays over approximately the duration of the use animation — giving the player clear feedback of the vulnerability window.

See `design/INVENTORY_AND_EQUIPMENT_SYSTEM.md` for assignment rules.

### Interaction Prompt

When Roland is within range of something interactive (a door, an NPC, an investigation point, a container), a small prompt appears near the object in world-space — not as a screen-corner notification.

Format: a small handwritten-style label reading `[ E ]` and the action name:
- `[ E ] Talk` — near a Tier 2+ NPC
- `[ E ] Examine` — near an investigation point or readable object
- `[ E ] Open` — near a door or container
- `[ E ] Rest` — near a campfire or valid rest point

The prompt does not appear until Roland is within the interact radius. It disappears if he moves away. It is subtle — a player who is not looking at the relevant object will not see it in their peripheral vision.

**Tier 1 NPCs (bark-only)** do not show an interaction prompt. They fire automatically on proximity.

### Bark Overlay

When a Tier 1 or Tier 2 NPC fires a bark line (or Roland himself speaks an ambient observation), a small text overlay appears in the upper-left corner:

- Character portrait thumbnail (64×80 px) — small, unobtrusive
- One or two lines of text in a handwriting-style font
- Fades automatically after approximately 3.5 seconds
- New barks queue; they do not stack. If a second bark fires before the first fades, the first is replaced.

The bark overlay does not pause gameplay. It is informational, not interactive.

### Compass

A minimal compass strip at the top center — N/S/E/W markers only, no waypoints, no icons. Roland's facing direction is indicated by a small mark on the strip.

**No minimap.** See `design/WORLD_NAVIGATION.md` — the journal map tab fills this role for players who want orientation, and the world is designed to be readable without a persistent map on screen.

---

## Journal Overlay (J Key)

Opening the journal pauses the game. The journal is a full-screen overlay rendered as actual parchment pages with handwriting and sketches — not a menu panel.

Five tabs: **Quests / Map / Items / Crafting / Codex**

A sixth tab — **Skills** — is a future addition pending `design/SKILLS_AND_PROGRESSION.md` → Skill Screen Presentation.

Closing the journal returns to the exact game state the player left. No loading.

Full layout and content: `design/JOURNAL_UI.md`.

---

## Inventory Screen (I Key)

Full-screen overlay accessed from the journal Items tab or directly with I.

- Left panel: equipment slots (visual Roland silhouette with slots labeled)
- Right panel: pack contents (grid of item icons with names on hover)
- Bottom bar: total weight / max weight
- Quick slot assignment: drag items from pack to the four slot positions shown at screen bottom

The inventory screen does not pause the game. Roland is vulnerable while the player has it open. (Design intent: the player should feel the cost of rifling through their pack mid-fight — just as Roland would. The correct time to manage inventory is at camp.)

---

## Camp Menu

Opened by pressing E near a campfire or valid rest point. Does not pause — time continues at 1/4 rate.

Four tabs: **Rest / Craft / Companions / Gear**

Full layout: `design/REST_AND_CAMP.md` → The Camp Menu.

---

## Dialogue UI

Managed entirely by Dialogic 2. During a Dialogic timeline:

- Character portraits appear in designated left/right portrait areas (256×320 px)
- Character name plate appears below the portrait
- Dialogue text renders in a box at the bottom of the screen
- Player choices (if any) appear as numbered text options
- The HUD (HP, Endurance, quick slots, compass) is hidden during dialogue
- The game does not pause — world events continue. NPCs can move; time passes.

For character voice styling, portrait format, and TTS integration: `design/CONVERSATION_SYSTEM.md` and `dialogue/STYLE.md`.

---

## Investigation Observation Overlay

When Roland examines an investigation point, the observation text appears as a world-space floating text (near Roland's position, slightly above and ahead of him) in his handwriting style.

- Type 1 observations: text only, fades after ~4 seconds
- Type 2 observations: text + small **"Noted"** icon with a quill stamp in the lower right; a brief journal indicator flash
- Deduction triggers: a slightly different framing — the text shifts to a full-sentence internal conclusion in italics

The overlay does not interrupt gameplay. Full spec: `design/INVESTIGATION_SYSTEM.md` → The Examination Interface.

---

## Pause Menu (ESC)

Pressing ESC during play opens the pause menu. The game freezes. Options:

- **Resume**
- **Journal** (shortcut to the journal overlay)
- **Settings** (audio, controls, display)
- **Save** (disabled unless Roland has a Wanderer's Seal; see `design/CRAFTING.md`)
- **Quit to Main Menu**
- **Quit to Desktop**

The pause menu does not open during Dialogic timelines. ESC during dialogue advances or closes the dialogue (per Dialogic's default behavior).

---

## Debug Overlay (F1)

Developer/testing only. Toggle with F1.

Displays:
- Current scene name
- Player position (Vector3)
- Current WorldClock time (hour, day, time-of-day period)
- Active GameState flags (scrollable list)
- Active NPC inspector: name, tier, current schedule block, disposition value
- FPS counter

This overlay should never appear in a shipped build. It is controlled by a `ProjectSettings` constant: `debug/overlay_enabled`.

---

## Main Menu

The game's main menu is a full-screen environment render — not a static image. The camera rests on Roland's campfire from a low angle, fire flickering, wind through trees or cave stone (depending on what the starting environment is).

Options:
- **Continue** (most recent save) — shown only if a save exists
- **New Game**
- **Load Game** (opens save slot picker)
- **Settings**
- **Credits**
- **Quit**

The main menu does not play a trailer or cinematic. The world is the title screen.

---

## GDScript Notes

### Bark overlay node

```gdscript
# BarkOverlay must be in the "bark_overlay" group for BarkManager to find it.
# BarkManager calls:
func show_bark(speaker_id: String, text: String) -> void:
    # Sets portrait from speaker_id, sets text, plays fade-in animation,
    # starts a timer for auto-hide (~3.5 seconds).
    pass
```

### Interaction prompt

```gdscript
# "Press E to talk" world-space prompt.
# NPC.gd (lines 149 and 154 — TODO placeholders) should call:
InteractionPrompt.show_at(global_position + Vector3(0, 2.0, 0), "Talk")
InteractionPrompt.hide()
```

### Endurance cap (wound HP)

```gdscript
# PlayerStats.gd — the grey cap line position:
func get_endurance_cap_ratio() -> float:
    var wound_fraction: float = PlayerStats.wound_hp / PlayerStats.max_hp
    return clamp(1.0 - (wound_fraction * 0.4), 0.4, 1.0)
    # A Roland at full wound HP still has 60% endurance capacity.
```

### Save-disabled state for pause menu

```gdscript
# The Save option is grayed unless the player has a Wanderer's Seal in inventory.
func _refresh_save_button() -> void:
    var has_seal: bool = InventoryManager.has_item("wanderers_seal")
    save_button.disabled = not has_seal
```
