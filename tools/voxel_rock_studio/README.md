# Voxel Rock Studio

Sibling of the Voxel Tree Studio. Procedurally generates **rocks as cubic
voxels** (10 cm/voxel) and exports game-ready JSON — boulders, angular slabs,
cliffs, spires, pebble fields, and piles.

## Open it

```
https://raw.githack.com/mnoles1911/Test/claude/voxel-threejs-rendering-oc4akx/tools/voxel_rock_studio/index.html
```

Hard-refresh (Ctrl/Cmd+Shift+R) after each push.

## How it works

Rocks are **solid volumes**, so instead of a skeleton we sample an implicit
"rock field" at every voxel cell (`rock_voxelizer.js`):

```
field = superquadric base (boxiness)
      + FBM simplex noise (surface roughness, eroded)
      + Worley/Voronoi (angular facets)
      − random scrape planes (flat cleaves)
      clamped to a flat bottom (+ optional top taper for spires)
inside (field ≤ 1) → solid stone voxel
```

Materials are assigned by noise + height strata (stone / dark stone / marble
veins / gravel / ore pockets), and **moss** grows on up-facing surfaces. A
connectivity check confirms the rock is one solid body.

Shared math lives in `../voxel_studio_common/` (`noise.js`, `voxel_core.js`).

## Controls

- **Rock type** preset (Boulder / Angular / Cliff / Spire / Pebbles / Pile) +
  grouped dials (size, shape, faceting/cuts, scatter, materials), each with a
  **🔒 lock** and **🎲 randomize** (group + global, unlocked only).
- **Reference overlay** — drag an image onto the view; fade it in to compare.
- **✨ Fit dials with Claude vision** — paste your Anthropic API key, then let
  Claude analyze the reference image and set the dials (see below).
- **Export JSON** — voxels with engine material ids; deployable as-is.

## Materials (no new art needed except moss)

Rocks use **existing** engine materials: stone (1), gravel (7), marble (9),
copper ore (12), dark stone (14), iron ore (15) — plus **moss (32)**, the one
new material (placeholder tile wired like the vegetation set; see
`DESIGNER_TODO.md`).

## Claude vision fit (bonus)

The **Fit** button calls the Anthropic Messages API **directly from your
browser** with your API key, sends the reference image, and Claude returns rock
parameters via strict tool use (`claude_vision.js`, model `claude-opus-4-8`).

> ⚠ **Your API key is used in the browser** (the request carries it). That's
> fine for a local design tool you run yourself — do not host this with a shared
> key. The key is stored only in your browser's localStorage.

## Export format

```json
{
  "format": "mira-thal-voxel-rock",
  "version": 1,
  "voxel_size_m": 0.1,
  "rock_type": "Boulder",
  "palette": { "1": "stone", "14": "stone_dark", "32": "moss", ... },
  "size": [w, h, d],
  "size_m": [w, h, d],
  "params": { ...the dials... },
  "voxels": [ { "x":0, "y":0, "z":0, "m":1 }, ... ]
}
```

Imports through the same `scripts/_dev/VoxelTreeImporter.gd` (it accepts both
tree and rock formats).
