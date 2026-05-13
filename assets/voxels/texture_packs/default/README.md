# Default Texture Pack — Authoring Guide

This folder is a **discrete texture pack**: a self-contained set of source
images plus a packed atlas the game loads at startup. Swapping packs is a
matter of pointing the `VoxelBlockyLibrary` at a different folder's
`atlas.png` — no code changes.

## What's in here

| File / folder | Purpose |
|---|---|
| `pack.json` | Pack metadata — name, tile size, atlas size, version |
| `source/` | AI-generated source PNGs at 512×512 (or higher) |
| `atlas.png` | Generated atlas — **do not hand-edit**, run the builder instead |
| `manifest.json` | Generated UV-coordinate map per material — also do not hand-edit |

## Authoring workflow

1. Open `tools/AI_TEXTURE_PROMPTS.md` at the repo root.
2. For each prompt, generate the texture in your AI image generator
   (Midjourney, DALL-E, Stable Diffusion, etc.) at 512×512.
3. Save the PNG using the **exact filename** listed in the prompt doc into
   `source/`. Filenames are matched literally by the atlas builder.
4. Run the atlas builder from the repo root:

   ```
   python tools/build_texture_atlas.py default
   ```

   This requires `pip install Pillow`. The builder:
   - reads each source PNG and **nearest-neighbour-downscales** to 16×16
     (NEAREST, not LANCZOS — the source images are upscaled pixel art,
     so averaging would blur the grid; see `tools/build_texture_atlas.py`)
   - composites `grass_side.png` automatically from `dirt_all.png` and
     `grass_top.png` using a 2-row solid green band plus a 1-row
     dirt+green scatter (don't generate `grass_side` manually)
   - copies `log_top.png` into the bottom slot
   - leaves the water slot empty (water rendering is handled separately by
     `WaterChunkMesher`)
   - writes `atlas.png` (1024×1024) and `manifest.json`

5. In Godot, open `assets/voxels/blocky_library.tres`. The atlas texture is
   referenced by the library's material — when `atlas.png` updates on disk,
   the library picks up the change after a re-import.

## Tile coordinates (atlas grid, 16×16 px per tile)

Use these when filling out the `VoxelBlockyLibrary` model entries in
the Godot Inspector. Coordinates are **(column, row)** with (0, 0) in the
top-left of the atlas.

| Material ID | Material | Top tile | Side tile | Bottom tile |
|-------------|----------|----------|-----------|-------------|
| 1 | Stone | (0, 0) | (0, 0) | (0, 0) |
| 2 | Dirt | (1, 0) | (1, 0) | (1, 0) |
| 3 | Grass | (2, 0) | (3, 0) | (1, 0) |
| 4 | Sand | (4, 0) | (4, 0) | (4, 0) |
| 5 | Water | *(empty model — no tiles)* | | |
| 6 | Bedrock | (4, 1) | (4, 1) | (4, 1) |
| 7 | Gravel | (5, 0) | (5, 0) | (5, 0) |
| 8 | Clay | (6, 0) | (6, 0) | (6, 0) |
| 9 | Marble | (7, 0) | (7, 0) | (7, 0) |
| 10 | Log | (0, 1) | (1, 1) | (0, 1) |
| 11 | Leaves | (2, 1) | (2, 1) | (2, 1) |
| 12 | Copper Ore | (3, 1) | (3, 1) | (3, 1) |
| 13 | Snow | (8, 0) | (8, 0) | (8, 0) | *placeholder = marble copy* |
| 14 | Dark Stone | (9, 0) | (9, 0) | (9, 0) | *placeholder = bedrock copy* |
| 15 | Iron Ore | (10, 0) | (10, 0) | (10, 0) | *placeholder = copper_ore copy* |

**IDs 13–15** were added 2026-05-10 with the six-tier voxel-generation
plan. Source PNGs currently point at copies of similar existing
materials as placeholders (snow → marble, stone_dark → bedrock,
iron_ore → copper_ore). Paint proper 512×512 PNGs over
`source/{snow_all,stone_dark_all,iron_ore_all}.png` whenever convenient
and re-run the atlas + library builders to ship final art.

In atlas pixel coordinates: `(column × 16, row × 16)` is the top-left
corner of each tile.

## Building a new pack

To make a second pack (e.g. `copper_isles_v1` with maritime-specific art):

1. Copy this folder to `assets/voxels/texture_packs/<new_pack_name>/`.
2. Update `pack.json` with the new name and version.
3. Replace source PNGs.
4. Run `python tools/build_texture_atlas.py <new_pack_name>`.

The game loads whichever pack is set in `GameState.active_texture_pack`
(default: `"default"`). Switching packs is a single string change plus a
library re-import.
