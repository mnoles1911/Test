# UE5 Heightmap Import (M3) — bringing a hand-crafted Gaea map into the voxel world

**Status:** LIVE (2026-06-16). This is the designer-facing how-to for importing an `.exr` heightmap (e.g.
a 5 km map sculpted in **Gaea**) and turning it into real 10 cm voxel terrain you can walk on and dig.

Plain-English summary: instead of the game *inventing* the landscape with noise, you hand it a picture
where **brightness = height** (white = high mountains, black = low valleys). The game reads that picture
and builds the exact terrain you designed.

---

## 1. Export the heightmap from Gaea

- Build your terrain in Gaea as usual.
- Add an **Export** node (or use *Build*) and export the **height** output as:
  - **Format:** OpenEXR (`.exr`).
  - **Bit depth:** 32-bit float (16-bit half also works).
  - **Channels:** a single grayscale **height** channel is ideal. (Colour EXRs are fine too — we read the
    **red** channel as the height.)
  - **Range:** the usual Gaea **0..1 normalised** height is perfect. We map 0 and 1 to real elevations
    with the knobs below, so you don't need Gaea to bake in real-world metres.
- Note the **real-world size** of your map (e.g. **5 km × 5 km**) and roughly **how tall** the highest
  peak should stand above the lowest valley (e.g. **700 m**). You'll type those in.
- Put the `.exr` somewhere easy, e.g. `ue5/MiraThal/Content/Heightmaps/MyMap.exr` (any folder works; you
  pick the file in the editor).

> **Square maps.** The importer assumes a square map (width = height span). Gaea exports are square by
> default. A non-square image still loads, but the metre span is applied to both axes from the X size.

---

## 2. Point the world at it (in the Unreal editor)

1. In the level, select your **`AVoxelWorld`** actor (the terrain manager). If there isn't one, drag a
   **Voxel World** into the level from the Place Actors panel.
2. In its **Details** panel, find the **MiraThal | Heightmap** section and set:

| Knob | What it means | Example |
|---|---|---|
| **Height Source** | Switch from *Procedural Noise* to **Imported EXR Heightmap**. | Imported EXR Heightmap |
| **Heightmap File** | The `.exr` you exported. Click the **…** and pick the file. | `…/Content/Heightmaps/MyMap.exr` |
| **Map Span Meters** | How wide the map is in the real world, in metres (square). | `5000` (= 5 km) |
| **Heightmap Altitude Meters** | Elevation that a **white** (value 1.0) pixel represents — the height of the tallest peak above the base. | `700` |
| **Heightmap Base Meters** | Elevation that a **black** (value 0.0) pixel sits at — the map floor. `12` puts black right at sea level (lakes/oceans form below it). | `12` |
| **Flip Heightmap Z** | If the terrain comes out mirrored north/south vs how it looked in Gaea, toggle this. On by default (Gaea rows run top-down). | ✓ |

3. Press **Generate World** (a button in the Details panel under **MiraThal | World**). The centre region
   of your map builds immediately so you can preview it.

That's it — the grass/dirt/stone banding, the beaches, the lakes, and the scattered flora all follow the
shape of *your* map automatically.

---

## 3. Seeing the WHOLE 5 km map (streaming)

A 5 km map at 10 cm voxels is **50,000 × 50,000 voxels** — billions of them. The editor **Generate
World** button only builds a small preview region around the origin so you can eyeball the look. To
actually roam the full map:

1. On the `AVoxelWorld`, open the **MiraThal | Streaming** section and tick **Enable Streaming**.
2. (Optional) set **Stream Radius Chunks** — how far around you stays built (6 ≈ 40 m each way). Bigger =
   more visible terrain but more cost.
3. Press **Play**. As your character moves, terrain **pages in** around you and unloads behind you, so
   the whole 5 km is walkable without melting your GPU.

If **Stream Focus Actor** is empty it follows the **player pawn**. You can instead point it at any actor
(e.g. a flying camera) to preview streaming without a character.

---

## 4. Tuning the look

- **Mountains too tall / too flat?** Change **Heightmap Altitude Meters**. This is the single biggest
  lever — it stretches or squashes the vertical scale.
- **Everything underwater / no water at all?** Change **Heightmap Base Meters**. Sea level is **12 m**.
  Set Base below 12 to flood the low areas; set it at/above 12 to keep the map dry.
- **Terrain mirrored the wrong way?** Toggle **Flip Heightmap Z**.
- **Map looks stretched or wrong scale?** Check **Map Span Meters** matches your real Gaea map size.
- If the file can't be read, the world **falls back to procedural** and logs a line starting with
  `[MiraThal] EXR heightmap load failed` in the Output Log — check the path and that it's a real `.exr`.

---

## 5. How it works under the hood (for the curious / for future devs)

- **Decode (UE side, `HeightmapImport.cpp`):** Unreal's **ImageWrapper** module decodes the `.exr` to
  floating-point pixels; we copy the red channel into a `Core/ImageHeightmap`.
- **Sample (Core, `ImageHeightmap.h`):** a *georeferenced* float grid. It knows how many voxels one
  pixel spans (5 km / image-width) and bilinearly blends the four nearest pixels, so the ground is smooth
  even though one pixel covers ~tens of voxels. It maps a pixel value to a voxel height with
  `ground_y = base + value × altitude` (in voxels; 10 voxels = 1 m).
- **Drive generation (`HeightmapGenerator`):** `set_height_source()` attaches the grid; `compute_ground_y`
  reads it. Because cliff detection, material banding, the below-sea water flag, and flora scatter **all**
  ask `compute_ground_y` for the surface height, they re-derive off the imported terrain for free.
- **Verified headless:** the sampling + override math is unit-tested by the clang harness
  (`tests/standalone/test_imageheightmap.cpp`, 36 checks) — no editor needed.

Files: `Source/MiraThalVoxel/Public/Core/ImageHeightmap.h`,
`Source/MiraThalVoxel/Private/HeightmapImport.cpp`,
`Source/MiraThalVoxel/Public/VoxelWorld.h` (the Details-panel knobs).

---

## 6. Known limits / follow-ups

- **Square maps only** (width span used for both axes). Non-square support is a small follow-up.
- **One global material banding.** Imported terrain uses the default grass/dirt/stone + beach/sea rules;
  per-region painted materials (a splat/biome mask EXR alongside the height) is a future extension.
- **CPU memory on huge explores.** Streaming evicts the *meshes* but currently keeps the generated CPU
  voxel data for revisits; CPU-store eviction for very long sessions is a noted follow-up.
- **Vertical range.** Very extreme altitude settings (thousands of metres) generate very tall columns;
  keep Altitude sane (hundreds of metres) for sensible build times.
