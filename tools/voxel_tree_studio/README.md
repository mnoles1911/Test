# Voxel Tree Studio

In-browser sandbox for designing the **shape** of voxel trees for Mira-Thal,
using Three.js. Drag sliders → the tree rebuilds live → spin it to judge the
silhouette → **Export** a winner as JSON.

## How to use

1. Open `index.html` in any modern browser (needs internet the first time — it
   pulls Three.js from a CDN).
2. Tune trunk / branches / canopy. Hit **🎲 Randomize** to jump seeds.
3. When you like one, hit **⬇ Export JSON**. It downloads
   `tree_seed<N>.json`.

## Reference-image → design loop

The main workflow: design a tree to match a reference picture.

1. **Send Claude a reference image** of a voxel tree (in chat).
2. Claude saves it under `references/` and adds a **preset** to `presets.js` —
   its read of the trunk/canopy translated into slider values, plus the image
   path and notes.
3. In the studio, pick that preset from the **Design preset** dropdown. It
   loads the tree **and** ghosts the reference over the 3D render. Use the
   **Overlay opacity** slider to fade the reference in/out and judge the match.
4. Tell Claude what's off ("canopy too round", "trunk too tall") — Claude
   adjusts the numbers in `presets.js`, you reload and re-compare.

You can also **drag any image onto the view** (or use *Load image…*) to set a
reference on the fly without a preset.

- `presets.js` — saved designs (reference-backed param sets). Editable by hand.
- `references/` — the reference images themselves.

## What you're looking at (and what you're NOT)

- **Judge here:** overall shape, height, canopy density, silhouette.
- **Do NOT judge here:** final color or lighting. The browser colors are
  stand-ins, not the real pixel-art atlas. Final look gets approved in the
  Godot editor with the actual `blocky_library.tres` material.
- Everything is opaque cubes — that's honest to how leaf voxels render
  in-engine (alpha-scissor cutout, one cube per leaf cell).

## Scale: 10 cm per voxel

All voxel assets are authored at **10 cm per voxel (10 voxels per meter)**. The
studio labels trunk height, canopy radius, and overall size in **meters** so you
design at real-world scale, and the scale is written into the export.

> ⚠ The live terrain engine is currently **6 vox/m (16.7 cm)**. Until that's
> migrated to 10 cm, an exported tree will import ~67% larger than designed.
> Tracked in `DESIGNER_TODO.md` → Section 8 ("Voxel scale migration").

## Export format (the bridge to Godot)

```json
{
  "format": "mira-thal-voxel-tree",
  "version": 1,
  "voxel_size_m": 0.1,          // 10 cm per voxel
  "size":   [w, h, d],          // bounding box in voxels
  "size_m": [w, h, d],          // bounding box in meters
  "params": { ...the slider values... },
  "voxels": [ { "x": 0, "y": 0, "z": 0, "m": 10 }, ... ]
}
```

- `m` is a **VoxelMaterialRegistry id**: `10` = log, `11` = leaves — the same
  ids `tools/build_blocky_library.gd` uses.
- Trunk base sits at the origin `(0,0,0)`, `+y` is up.

## Next step (not built yet)

A small Godot importer that reads one of these JSON files and stamps the
voxels into the world via `VoxelEditManager` (or bakes a `VoxelBlockyModel`).
That's the "deploy into the game" half — kept separate so shape iteration and
engine integration stay decoupled.
