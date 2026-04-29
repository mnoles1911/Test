# Dialogic 2 — Setup Guide for Milestone 2

This guide walks through installing Dialogic 2, creating the Henrietta character
definition, and wiring the portrait placeholder. Do this before running the
Henrietta scene.

---

## Step 1 — Install Dialogic 2

1. Open Godot 4.3 with this project loaded.
2. Click the **AssetLib** tab at the top of the editor.
3. Search for **Dialogic**.
4. Click the result by **Jowan Resso & emilio** (or "Dialogic 2").
5. Click **Download**, then **Install**.
6. When the install popup appears, leave all files checked. Click **Install**.

Alternatively: download the latest release from
https://github.com/dialogic-godot/dialogic and copy the `addons/dialogic/`
folder into your project's `addons/` directory.

---

## Step 2 — Enable the Plugin

1. Go to **Project → Project Settings → Plugins** tab.
2. Find **Dialogic** in the list.
3. Check the **Enable** checkbox.
4. Godot will reload and add Dialogic's autoload singletons automatically.

After enabling, you should see a **Dialogic** tab appear in the bottom panel,
next to Output and Debugger.

---

## Step 3 — Create the Henrietta Character

Dialogic needs a character resource file that maps the name "Henrietta" to a
portrait image. This must be done through the Dialogic editor.

1. Click the **Dialogic** tab at the bottom of the editor.
2. Click **Characters** in the left sidebar (or top menu).
3. Click **New Character** (the + button or menu option).
4. Set the **Display Name** to exactly: `Henrietta`
   (This must match the name used in `dialogue/henrietta_archive.dtl`.)
5. Set the **Color** to something warm and amber — e.g. `#c9a060`.
   This color tints the dialogue name label.
6. Under **Portraits**, click **Add Portrait**.
7. Set the portrait name to `default`.
8. Set the portrait image to:
   `res://assets/portraits/henrietta_placeholder.svg`
9. Save the character. Dialogic saves it as a `.dch` resource file.
   Suggested save path: `res://dialogue/characters/Henrietta.dch`

Repeat this process for Roland when ready, using `Roland` as the display name.
For Milestone 2 Roland doesn't need a portrait — his lines can appear
without one.

---

## Step 4 — Open the Timeline

1. In the **FileSystem** panel, navigate to `dialogue/henrietta_archive.dtl`.
2. Double-click it — it will open in the Dialogic timeline editor.
3. You should see the dialogue lines already populated from the text file.
4. If any lines show errors (usually a missing character reference),
   re-link the character by clicking the character icon on that event.

---

## Step 5 — Test It

1. Run `scenes/World.tscn`.
2. Walk the player into the blue trigger zone on the right.
3. Press **E**.
4. The Dialogic dialogue box should appear over the scene with the first
   Henrietta line.
5. Press Enter or E to advance through lines. Dialogic closes automatically
   at the end of the timeline.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Dialogic` not found error on run | Plugin not enabled — check Step 2 |
| Dialogue box doesn't appear | Dialogic may need a layout. Go to Dialogic → Layouts → Create Default Layout |
| Character portrait missing | Check that Display Name matches exactly (case-sensitive) |
| Text shows but no portrait box | The Dialogic layout needs a portrait layer — add one in the Layout editor |
| E key does nothing | Make sure `scripts/DialogueTrigger.gd` on the current branch is loaded |

---

## Dialogic Layout Note

Dialogic 2 ships with a default dialogue box layout but it may not be
pre-configured. If the dialogue box doesn't appear:

1. Go to Dialogic tab → **Layouts**.
2. Click **Create Default Layout** (or select one from the built-in options).
3. Dialogic will add a layout scene to your project.
4. Run the game again — the layout is loaded automatically by Dialogic.
