# Menu Background Images

Drop concept-art images in this folder. On every game launch, the
**MainMenu** picks one at random and shows it full-screen behind
the title. A semi-transparent dark tint (50% opacity) is layered
over the image so the title and buttons stay readable against
busy art.

## Supported file types

`.png` · `.jpg` · `.jpeg` · `.webp`

## Recommended specs

- **Resolution:** 1920×1080 minimum. Higher is fine — the image
  is stretched with `STRETCH_KEEP_ASPECT_COVERED`, so it always
  fills the screen and crops the side that overhangs. Different
  aspect ratios crop predictably.
- **Aspect ratio:** 16:9 ideal. Other ratios work; the image
  fills the viewport and crops the longer dimension.
- **Composition:** keep your "important" subject (Roland, a key
  landmark, a focal piece of architecture) in the middle two-
  thirds horizontally and below the top quarter — the title
  "GAME ONE" sits roughly in the upper third.

## How to add new images

1. Drop the image file into this folder.
2. Commit it: `git add assets/menu_backgrounds/<filename>` and
   commit. Godot picks them up automatically on next launch — no
   .tscn or code change needed.
3. (Optional but tidy) name files with descriptive slugs:
   `aldenholt_dawn.png`, `roland_at_the_archive.png`,
   `drun_khazad_volcano.jpg`, etc. Filenames don't show in-game
   but they help when you're managing the collection in Finder.

## Sending images to Claude

There are three ways:

1. **Drop them directly into the folder via Finder**, then commit.
   Claude doesn't need to see the image bytes — once it's in
   `assets/menu_backgrounds/` and committed, the loader picks it
   up at random alongside the others.
2. **Paste the image into chat** with Claude Code. Claude writes
   it to disk via the Write tool. Best for one or two at a time.
3. **Reference an external URL** if the image is hosted online —
   Claude can fetch and save it.

## What gets shown when the folder is empty

The fallback dark `Background` ColorRect from `MainMenu.tscn`
shows by itself. The console prints
`[MainMenu] No menu backgrounds found — using dark fallback.`
to flag the empty state.
