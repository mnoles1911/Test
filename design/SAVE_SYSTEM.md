# Save System Design

How the game saves, loads, and manages progress.

> Cross-reference: `design/REST_AND_CAMP.md` for the full rest autosave trigger.
> `design/CRAFTING.md` for the Wanderer's Seal (manual save consumable).
> `design/HUD_AND_UI.md` for the pause menu save option and save-disabled state.
> `design/DEATH_AND_RESPAWN.md` for where Roland returns on death.

---

## Design Philosophy

**Saving is diegetic.** Roland does not push F5 and get a quicksave. He sleeps in a real bed, which creates an autosave — a record of the night's end. He drinks a Wanderer's Seal, which creates a manual save — the act of marking a moment before stepping into uncertainty. Both have weight. Neither is instantaneous or free.

**Saves are commitments.** The player cannot spam saves before a decision and reload until they get the outcome they want without cost. A Wanderer's Seal requires crafting or purchase — it is limited. Rest autosaves happen on Roland's schedule, not the player's. This is intentional: choices should feel final because they largely are.

**Three save slots.** The player can maintain up to three separate playthroughs simultaneously. Slot selection happens at the main menu. Within a slot, there is one active save per slot (overwritten on each new save), plus one backup save (the previous save before the most recent overwrite). This provides a recovery path if a player saves in an unrecoverable state.

---

## Save Triggers

### Autosave — Full Rest

When Roland completes a **Full Rest** (inn bed or established camp cot), the game autosaves automatically. See `design/REST_AND_CAMP.md` → GDScript Notes for the `resolve_rest()` function.

Autosave happens:
1. After the rest resolution calculations (HP restored, time advanced)
2. Before the fade-in to the new time of day
3. With a brief "Seal" icon appearing in the corner — the same icon used for the Wanderer's Seal, signaling that this moment is now recorded

The player cannot interrupt an autosave. The save completes before the fade-in.

### Manual Save — Wanderer's Seal

The Wanderer's Seal is a crafted consumable (see `design/CRAFTING.md` → item #36 in Section 4). When consumed, it creates a manual save at Roland's current location and state.

Consuming the Seal:
1. Plays the drinking animation (short, identical to using a potion — Roland is briefly vulnerable)
2. The same "Seal" icon appears in the corner
3. Save completes; the Seal is consumed from inventory

**Maximum carry:** Roland can carry a maximum of 3 Wanderer's Seals at a time. This limit is hardcoded — not a weight issue, a design constraint. The Seal is not a casual item to stockpile.

**Pause menu save:** The pause menu has a Save option that is enabled only when Roland has at least one Wanderer's Seal in inventory. Selecting it consumes the Seal and saves. This is a convenience path (player does not have to navigate inventory to use it) but not a different mechanic — it still consumes the item.

---

## Save File Contents

Each save records the complete game state:

- **Current scene** — the `.tscn` file name and Roland's position/rotation in it
- **GameState flags** — the entire flag dictionary (quests, faction dispositions, story progress, investigation findings, skill XP, camp upgrades, etc.)
- **InventoryManager state** — Roland's current inventory, equipment, quick slot assignments, Wanderer's Seal count
- **Companion state** — which companions are active, their HP, wound HP, inventory, and equipment
- **WorldClock state** — current in-game day, hour, and time-of-day period
- **Play time** — total in-game time elapsed (for player reference; not used mechanically)
- **Metadata** — save slot, save type (autosave / manual), real-world timestamp, act/chapter label for display in the load screen

### Save File Location

Godot's default user data directory: `user://saves/slot_{0,1,2}/save.dat`

The backup is written to `user://saves/slot_{0,1,2}/save_backup.dat` — the previous save before the most recent overwrite.

---

## Loading

### Continue

The main menu's "Continue" option loads the most recent save across all three slots (the one with the most recent real-world timestamp). This is the default for players who use one slot.

### Load Game

Opens the save slot picker. Each slot shows:
- Slot number
- Act/chapter label (e.g., "Act I — Aldenholt")
- Play time
- Real-world save date
- A screenshot of the moment the save was created (taken at save time)

The player selects a slot, then optionally chooses between the active save and the backup save (labeled with their timestamps).

### Scene Load on Return

When a save is loaded, the game restores:
1. The saved scene (loads the `.tscn`)
2. Roland's position and rotation
3. All GameState flags (NPCs, world objects, and quest state all respond to these flags immediately on scene load)
4. Inventory and companion state
5. WorldClock time

NPCs in the scene re-establish their positions based on the restored WorldClock time and their schedule (see `design/NPC_SYSTEM.md` → Schedules). The world is not frozen at the save moment — it is recalculated for the restored time.

---

## Save on Quit

When the player quits to the main menu or to desktop from the pause menu, the game does **not** autosave. The player's progress since the last save is not preserved. This is consistent with the design intent: saves are diegetic events, not automatic checkpoints.

A warning appears in the quit confirmation dialog: *"Progress since your last rest or Seal will be lost."* This is informational, not alarming — it is part of the design contract with the player.

---

## Relationship to Death

When Roland dies, the game loads the most recent save (not the backup — the active save). The player is returned to where they were when they last rested or used a Seal.

See `design/DEATH_AND_RESPAWN.md` for the full death sequence and what the player sees.

---

## GDScript Notes

### Save function in GameState

```gdscript
# GameState.gd — save_game() is called by:
# - resolve_rest("full") in CampMenu.gd / RestSystem.gd
# - Wanderer's Seal consumption in ItemUseHandler.gd
# - The pause menu Save button (which checks for Seal first)

func save_game() -> void:
    var save_data: Dictionary = {
        "scene": get_tree().current_scene.scene_file_path,
        "player_pos": PlayerNode.global_position,
        "player_rot": PlayerNode.global_rotation,
        "flags": _flags.duplicate(),
        "inventory": InventoryManager.serialize(),
        "companions": CompanionManager.serialize(),
        "world_clock": WorldClock.serialize(),
        "play_time": play_time_seconds,
        "save_type": _pending_save_type,  # "autosave" or "manual"
        "timestamp": Time.get_unix_time_from_system(),
        "act_label": _get_act_label(),
    }
    _rotate_backup()
    var file := FileAccess.open(_save_path(), FileAccess.WRITE)
    file.store_var(save_data)
    file.close()
    SaveNotification.show_save_icon()

func _rotate_backup() -> void:
    # Copy current save to backup before overwriting
    if FileAccess.file_exists(_save_path()):
        DirAccess.copy_absolute(_save_path(), _backup_path())
```

### Wanderer's Seal check for pause menu

```gdscript
# In PauseMenu.gd:
func _on_menu_opened() -> void:
    save_button.disabled = not InventoryManager.has_item("wanderers_seal")
```

### Screenshot on save

```gdscript
# Taken immediately before save_game() executes:
func _capture_save_screenshot() -> void:
    var img: Image = get_viewport().get_texture().get_image()
    img.resize(320, 180)  # thumbnail size
    img.save_png("user://saves/slot_%d/screenshot.png" % current_slot)
```
