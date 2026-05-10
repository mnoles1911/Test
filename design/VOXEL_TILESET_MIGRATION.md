# Voxel Tileset Migration — Designer's Overview

## What changed

The terrain rendering pipeline migrated from **VoxelMesherCubes** (per-voxel
RGBA color cubes with per-cube color jitter) to **VoxelMesherBlocky**
(per-face textured blocks driven by a `VoxelBlockyLibrary`).

Why: per-face textures unlock the Minecraft-style grass-top vs grass-side
visual split, proper material identity (marble peaks read differently from
granite cliffs even though both are "stone-grey"), anti-tiling techniques
(variants, rotation, CTM), and a discrete texture-pack pipeline so we can
swap art styles without code changes.

## Architecture

```
                                 ┌─────────────────────────┐
                                 │ assets/voxels/          │
                                 │   texture_packs/        │
                                 │     default/            │
                                 │       source/*.png      │  ← AI-generated
                                 │       atlas.png         │  ← built by tool
                                 │       manifest.json     │
                                 └────────────┬────────────┘
                                              │
                                              ↓
                                 ┌─────────────────────────┐
                                 │ blocky_library.tres     │
                                 │   (VoxelBlockyLibrary)  │
                                 │   12 model entries      │  ← top/side/bottom
                                 │   atlas reference       │     tile coords per
                                 └────────────┬────────────┘     material
                                              │
                                              ↓
              ┌──────────────────────────────────────────────┐
              │ VoxelLodTerrain (every world scene)          │
              │   mesher = VoxelMesherBlocky                 │
              │   library = blocky_library.tres              │
              │   channel = CHANNEL_TYPE                     │
              └──────────────────────────────────────────────┘
                            ↑                       ↑
                            │                       │
              ┌─────────────┴───────────┐   ┌──────┴──────────────┐
              │ CubicHeightmapGenerator │   │ Copper Isles graph  │
              │ (procedural Mira)       │   │ (heightmap, future) │
              │ writes CHANNEL_TYPE     │   │ writes CHANNEL_TYPE │
              └─────────────────────────┘   └─────────────────────┘
```

Both generators write **integer material IDs** into `CHANNEL_TYPE`. Material
ID is now the type integer directly — no more packing colors. The library
maps material_id → texture atlas tile coordinates per face.

## Material ID table (canonical reference)

| ID | id_string | Faces | Role |
|----|-----------|-------|------|
| 0 | air | — | Reserved |
| 1 | stone | uniform | Cave walls, deep terrain |
| 2 | dirt | uniform | Grass sublayer |
| 3 | grass | top/side/bottom | Surface, forested slopes |
| 4 | sand | uniform | Beaches |
| 5 | water | empty model | Rendered by `WaterChunkMesher`, never written to CHANNEL_TYPE |
| 6 | bedrock | uniform | World floor, unbreakable |
| 7 | gravel | uniform | Rocky shores, shingle |
| 8 | clay | uniform | Tidal mudflats |
| 9 | marble | uniform | Island peaks above treeline |
| 10 | log | top/side/bottom | Tree trunks (upright) |
| 11 | leaves | partial-face | Tree canopy |
| 12 | copper_ore | uniform | Mineable ore seams |
| 13 | log_x | reserved | Future fallen log (X-axis) |
| 14 | log_z | reserved | Future fallen log (Z-axis) |

**Material IDs are stable forever.** Never reuse a slot — mark deprecated
entries instead.

## What you do as the designer

### Adding the textures (one-time setup)

1. Open `tools/AI_TEXTURE_PROMPTS.md`. Generate each texture in your AI
   image tool.
2. Save outputs at the exact filenames into
   `assets/voxels/texture_packs/default/source/`.
3. Run `python tools/build_texture_atlas.py default`. This packs the
   source images into `atlas.png` (2048×2048) and writes
   `manifest.json`.

### Wiring the library in Godot (automated)

The `VoxelBlockyLibrary` is built by an EditorScript — no manual
Inspector configuration required:

1. In the Godot editor, open the Script Editor (Ctrl+Shift+E).
2. **File → Open Script** → `res://tools/build_blocky_library.gd`
3. Press **Ctrl+Shift+X** (or **File → Run**).

The script reads `assets/voxels/texture_packs/default/pack.json` and
`atlas.png`, builds a 13-entry `VoxelBlockyLibrary` (slot 0 = air,
slots 1–12 = active materials) with per-face tile coordinates, and
saves it to `assets/voxels/blocky_library.tres`.

Re-run the script any time the material list changes (e.g. you add a
new `.tres` material file and update `MATERIAL_TILES` in the script).

`scenes/World3D.tscn` already references the library file — the mesher
on `VoxelLodTerrain` is `VoxelMesherBlocky` post-migration. The scene
loads with empty terrain if the library hasn't been populated yet (the
stub `blocky_library.tres` is committed to keep the scene's resource
references valid).

### Adding a new material

1. Add a `.tres` file under `assets/voxels/materials/` with a fresh
   `material_id` (≥ 13, never reuse 1–12).
2. Add new tile filenames to `ATLAS_LAYOUT` and `MATERIAL_FACES` in
   `tools/build_texture_atlas.py`.
3. Add a matching entry to `MATERIAL_TILES` in
   `tools/build_blocky_library.gd` with the same (col, row) coords.
4. Generate the source PNGs, drop them into `source/`, run
   `python tools/build_texture_atlas.py default`.
5. In Godot, re-run `tools/build_blocky_library.gd` to add the new
   library entry.
6. Update `CubicHeightmapGenerator.gd` (or whichever generator) to
   write the new material_id in the appropriate terrain band.

### Building a second texture pack

1. Copy `assets/voxels/texture_packs/default/` to a new folder
   (e.g. `copper_isles_v1/`).
2. Replace source PNGs.
3. Run `python tools/build_texture_atlas.py copper_isles_v1`.
4. In Godot, point the library's atlas reference at the new pack's
   `atlas.png`. Tile coordinates stay the same — only the texture
   changes.

## Save format compatibility

`WORLD_GENERATOR_VERSION` bumped from 12 → 13. Saves from older versions
have voxels packed as `CHANNEL_COLOR` RGBA, which the new mesher cannot
read. Pre-13 saves are invalid. Since no live saves shipped with the
older format, this is a clean break.

## What survives unchanged

- `VoxelStreamSQLite` — same delta storage, just storing TYPE values now
- `VoxelEditManager` async edit queue, NoEditZone gating
- `VoxelGravityManager` collapse detection (still scans for support)
- `WaterFlowManager` — water cells live in their own dictionary, not in
  any voxel channel
- `WaterChunkMesher` — separate transparent water surface, unaffected
- All gameplay autoloads (`GameState`, `InventoryManager`, `WorldClock`,
  `WeatherManager`, `BarkManager`, `NoEditZoneRegistry`)
- Material `.tres` color fields (`color_low`, `color_high`,
  `color_jitter`) — still used by `VoxelClusterBuilder` for falling
  cluster vertex tinting; the mesher itself ignores them
