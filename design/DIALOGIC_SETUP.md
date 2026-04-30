# Dialogic 2 — Setup Guide

> **Updated for 3D pivot (2026-04-30).** The project now renders at **1920×1080** (no pixel resolution target — 3D renders at display resolution). All Dialogic layout sizing has been revised accordingly. The 320×180 viewport is gone.

This guide covers installing Dialogic 2, creating character definitions, configuring the dialogue box layout for 1920×1080, and wiring triggers in 3D scenes.

---

## Step 1 — Install Dialogic 2

1. Open Godot 4.3 with this project loaded.
2. Click the **AssetLib** tab at the top of the editor.
3. Search for **Dialogic**.
4. Click the result by **Jowan Resso & emilio** (Dialogic 2).
5. Click **Download**, then **Install**. Leave all files checked.

Alternatively: download the latest release from https://github.com/dialogic-godot/dialogic and copy `addons/dialogic/` into `res://addons/`.

---

## Step 2 — Enable the Plugin

1. **Project → Project Settings → Plugins** tab.
2. Find **Dialogic** and check **Enable**.
3. Godot reloads and adds Dialogic's autoload singletons automatically.
4. A **Dialogic** tab appears in the bottom panel.

---

## Step 3 — Configure the Layout for 1920×1080

This is the step that was designed for the old 320×180 viewport. All sizes below are for the **new 3D 1920×1080 resolution**.

### Create or Edit the Default Layout

1. Go to **Dialogic tab → Layouts**.
2. Click **Create Default Layout** (or select an existing one).
3. Dialogic saves the layout as a `.tres` resource — open it for editing.

### Dialogue Box Sizing (1920×1080)

| Setting | Old 320×180 value | New 1920×1080 value |
|---|---|---|
| Box width | ~280 px | **1400 px** |
| Box height | ~65 px | **220 px** |
| Box anchor | bottom-center | **bottom-center** |
| Box margin from bottom | ~4 px | **40 px** |
| Box margin left/right | ~20 px | **260 px** (centers the 1400px box on 1920) |
| Corner radius | small | **8 px** |
| Box background opacity | ~0.85 | **0.88** |
| Box background color | dark blue-black | `Color(0.08, 0.08, 0.12, 0.88)` — same dark blue-black, scaled up |

### Portrait Sizing

| Setting | Old value | New value |
|---|---|---|
| Portrait size | ~40×60 px | **256×320 px** |
| Portrait position | left inside box | **left of the box, anchored to box baseline** |
| Portrait margin | flush with box edge | **20 px from left box edge** |

Portrait files live in `res://assets/portraits/`. Painted at **256×320 px** — this is the game's standard portrait resolution and should not be changed.

### Text and Name Label

| Setting | Old value | New value |
|---|---|---|
| Font size (dialogue body) | 6–8 px | **20 px** |
| Font size (character name) | 7–9 px | **22 px** |
| Name label position | top-left of box | **top-left of text area, 8 px padding** |
| Name label color | character color tint | character color tint (same) |
| Text area padding | ~4 px | **20 px** all sides inside box |
| Text area left offset | past portrait | **296 px from box left** (portrait 256 + 40 padding) |
| Characters per line | ~32 (narrow box) | **~80** |
| Auto-advance timing | per character | per character (unchanged) |

### Font

Use Godot's default font or a legible serif/slab at 20px. The game's tone is epic fantasy — a slightly worn serif fits better than a clean sans-serif. Avoid pixel fonts: at 1920×1080 they read fine but feel incongruous with the 3D world.

Suggested approach: use a `.ttf` or `.otf` in `res://assets/fonts/`. Import into Godot as a `FontFile` resource. The Dialogic layout's text node takes a `FontFile` directly.

---

## Step 4 — Create Character Definitions

1. **Dialogic tab → Characters → New Character**.
2. For each character:

| Character | Display Name | Color | Portrait file |
|---|---|---|---|
| Henrietta | `Henrietta` | `#c9a060` | `res://assets/portraits/henrietta_placeholder.svg` |
| Roland | `Roland` | `#8B7B6B` (weathered grey-brown) | `res://assets/portraits/roland_placeholder.svg` (when made) |
| Dame Calla | `Dame Calla` | `#8B3A1A` (Iron Chalice red-brown) | TBD |
| Bromrin | `Bromrin` | `#6B5A4A` (stone grey) | TBD |

Save each character resource to `res://dialogue/characters/`.

---

## Step 5 — Wire Triggers in 3D Scenes

For 3D scenes, use `scripts/DialogueTrigger3D.gd` (not the 2D `DialogueTrigger.gd`).

```
DialogueTriggerArea (Area3D)
└── CollisionShape3D (BoxShape3D — 2×2×2 m conversation reach)
    script: DialogueTrigger3D.gd
    timeline_name: "henrietta_archive"
```

In `DialogueTrigger3D.gd`:
```gdscript
if get_node_or_null("/root/Dialogic"):
    Dialogic.start(timeline_name)
```

The `interact` input action (key E) fires the trigger when the player is inside the Area3D. This action must be registered in **Project → Project Settings → Input Map** as `interact → Key E`.

---

## Step 6 — Test

1. Run `scenes/World3D.tscn`.
2. Walk into the blue trigger area near X=4.
3. Press **E**.
4. Dialogic box should appear at the bottom of the 1920×1080 viewport.
5. Press **E** to advance. Dialogic closes at the end of the timeline.

---

## Troubleshooting (3D)

| Problem | Fix |
|---|---|
| `Dialogic` not found error | Plugin not enabled — check Step 2 |
| Dialogue box appears tiny | Layout was sized for 320×180 — redo sizing per Step 3 |
| Dialogue box appears huge/off-screen | Same issue, different direction — redo sizing |
| Text overflows portrait | Text area left offset is wrong — set to 296 px from box left |
| E key does nothing in 3D | Confirm `interact` action registered in Input Map; confirm Area3D has `body_entered` connected via DialogueTrigger3D.gd |
| Portrait missing | File path wrong or character Display Name doesn't match timeline character name |
| Layout only shows in 2D world | Dialogic layout is a CanvasLayer — it renders on top of the 3D viewport automatically. No change needed. |
| Font too small at 1080p | Font size set to 6–8 px from old 320×180 setup. Set body font to 20 px, name label to 22 px. |

---

## What Changed from the 2D Version

| 2D (320×180) | 3D (1920×1080) |
|---|---|
| Box width ~280 px | Box width 1400 px |
| Font 6–8 px | Font 20–22 px |
| Portrait ~40×60 px | Portrait 256×320 px |
| `DialogueTrigger.gd` (Area2D) | `DialogueTrigger3D.gd` (Area3D) |
| Scene: `scenes/World.tscn` | Scene: `scenes/World3D.tscn` |
| Dialogic default layout works | Layout must be manually resized |
