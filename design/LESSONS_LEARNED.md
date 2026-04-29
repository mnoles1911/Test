# Lessons Learned — Game One Development Log

Running log of bugs hit during development, their root causes, and fixes.
Add an entry whenever a confirmed fix is merged. Date format: YYYY-MM-DD.

---

## 2026-04-29

### GDScript warning: unused parameter `delta` in `_physics_process`
**File:** `scripts/Player.gd`  
**Error:** `UNUSED_PARAMETER` warning on `_physics_process(delta)`  
**Root cause:** `move_and_slide()` handles its own physics timing internally, so `delta` is never used. GDScript warns when a parameter is declared but unused.  
**Fix:** Rename `delta` to `_delta`. The leading underscore is GDScript's convention for "intentionally unused." No behaviour change.  
**PR:** #27

---

### GDScript warning: local variable `offset` shadows `PointLight2D.offset`
**File:** `scripts/CampfireFlicker.gd`  
**Error:** `SHADOWED_VARIABLE_BASE_CLASS` warning  
**Root cause:** `PointLight2D` has a built-in `offset` property (its position offset from the parent node). A local variable named `offset` in a script that `extends PointLight2D` masks it.  
**Fix:** Renamed local variable to `energy_offset` to make its purpose explicit and avoid the shadow. No behaviour change.  
**PR:** #27

---

### E key trigger did nothing (no output, no error)
**File:** `scripts/DialogueTrigger.gd`  
**Error:** Silent — trigger zone entry printed correctly but pressing E did nothing.  
**Root cause:** The trigger used `Input.is_action_just_pressed("interact")` in `_process()`. The `interact` action was defined in `project.godot` by hand in a complex `InputEventKey` object format. Godot likely failed to parse the hand-authored format and the action was never registered.  
**Fix:** Replaced the action-based check with `_unhandled_input(event)` and a direct keycode comparison: `event.keycode == KEY_E or event.physical_keycode == KEY_E`. This works regardless of project.godot input map configuration. Lesson: hand-authoring input actions in project.godot is fragile; use direct key checks in scripts, or define actions through the Godot editor UI.  
**PR:** #27

---

### `Engine.has_singleton("Dialogic")` always returned false
**File:** `scripts/DialogueTrigger.gd`  
**Error:** `[DialogueTrigger] Dialogic plugin not found` even with the plugin installed and enabled.  
**Root cause:** `Engine.has_singleton()` only checks native C++ engine singletons (e.g. `OS`, `Input`, `Engine`). Dialogic registers itself as a **GDScript autoload node**, which lives in the scene tree at `/root/Dialogic` — not in the C++ singleton registry.  
**Fix:** Replace `Engine.has_singleton("Dialogic")` with `get_node_or_null("/root/Dialogic") == null`. Lesson: GDScript autoloads (including all plugin singletons and GameState) are scene tree nodes, not C++ singletons. Always check for them via `get_node_or_null("/root/AutoloadName")`.  
**PR:** #29

---

### `timeline_ended` signal crash on `CanvasLayer`
**File:** `scripts/DialogueTrigger.gd`  
**Error:** `Invalid access to property or key 'timeline_ended' on a base object of type 'CanvasLayer'`  
**Root cause:** `Dialogic.start()` returns the dialogue **layout node** (a `CanvasLayer` — the visible dialogue box). We incorrectly tried to connect `timeline_ended` on that return value. The signal doesn't live there.  
**Fix:** `timeline_ended` is a signal on the **`Dialogic` autoload itself**. Connect it before calling `start()`, using `CONNECT_ONE_SHOT` so it auto-disconnects after firing (prevents duplicate connections on repeated trigger use): `Dialogic.timeline_ended.connect(_on_dialogue_ended, CONNECT_ONE_SHOT)`. Lesson: in Dialogic 2, lifecycle signals (`timeline_ended`, `signal_event`, etc.) are on the `Dialogic` singleton, not on the object returned by `start()`.  
**PR:** #30
