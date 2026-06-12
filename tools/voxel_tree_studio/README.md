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

## What you're looking at (and what you're NOT)

- **Judge here:** overall shape, height, canopy density, silhouette.
- **Do NOT judge here:** final color or lighting. The browser colors are
  stand-ins, not the real pixel-art atlas. Final look gets approved in the
  Godot editor with the actual `blocky_library.tres` material.
- Everything is opaque cubes — that's honest to how leaf voxels render
  in-engine (alpha-scissor cutout, one cube per leaf cell).

## Export format (the bridge to Godot)

```json
{
  "format": "mira-thal-voxel-tree",
  "version": 1,
  "size": [w, h, d],
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
