# Voxel Tree Studio

A **fork of [ez-tree](https://github.com/dgreenheck/ez-tree)** (MIT) that renders
realistic trees as **cubic voxels** and exports **game-ready assets** for the
Godot/Zylann voxel game (Mira-Thal). Designers tune dials, pick a species,
randomize, overlay a reference image, and export voxels.

## Open it

Open via the githack URL (ES modules need HTTP, not a local `file://` double-click):

```
https://raw.githack.com/mnoles1911/Test/claude/voxel-threejs-rendering-oc4akx/tools/voxel_tree_studio/index.html
```

Hard-refresh (Ctrl/Cmd+Shift+R) after each push.

## How it works

1. **ez-tree** grows a realistic recursive branch skeleton from the dials
   (trunk flow, recursive forking, tropism/wind). Our fork captures the branch
   centerlines + leaf anchors (see `vendor/ez-tree/VENDOR.md`).
2. **`tree_voxelizer.js`** rasterizes the skeleton into cubes using a strictly
   **6-connected** walk, and grows leaf clumps *outward from the wood*. This
   guarantees the tree is one connected body — so it chops correctly in-engine
   (mirrors `scripts/_dev/SeverFollowLib.gd`). A built-in connectivity check
   reports any stragglers ("Highlight disconnected").
3. Export writes the voxels as JSON for the (future) Godot importer.

## Controls

- **Species preset** — ez-tree's built-in species (Oak/Pine/Ash/Aspen/Bush,
  small/medium/large). Loads the dials, then tweak.
- **Grouped dials** (Trunk / Branches / Forces / Foliage / Materials) — each
  param has a **🔒 lock**; each group + the global button has a **🎲 randomize**
  that only moves *unlocked* dials.
- **Reference overlay** — drag an image onto the view (or *Image…*) and fade it
  in with the opacity slider to match a silhouette.
- **Show ez-tree smooth mesh** — overlays ez-tree's own mesh to compare the
  voxel version against the smooth original.
- **Export JSON** — rich palette by default; tick *Export as log/leaves only*
  to collapse to the materials today's engine has.

Scale is **10 cm/voxel**; sizes show in meters.

## Materials (rich palette)

| id | name | family |
|----|------|--------|
| 24 | bark | wood |
| 25 | heartwood | wood |
| 26 | deadwood | wood |
| 27 | leaf_dark | leaves |
| 28 | leaf_light | leaves |

(16–23 are taken by native fluid models.) Until textures are authored these
render with preview colors in the studio only; export can collapse them to
`10`=log / `11`=leaves. See `DESIGNER_TODO.md` for the texture/registry steps.

## Export format

```json
{
  "format": "mira-thal-voxel-tree",
  "version": 1,
  "voxel_size_m": 0.1,
  "species": "Oak Medium",
  "palette": { "24": "bark", "25": "heartwood", ... },
  "size":   [w, h, d],
  "size_m": [w, h, d],
  "params": { ...the dials... },
  "voxels": [ { "x":0, "y":0, "z":0, "m":24 }, ... ]
}
```

Trunk base at the origin, `+y` up.

## Files

- `index.html` — UI + Three.js rendering + export.
- `tree_voxelizer.js` — pure 6-connected voxelizer + connectivity check (the
  part a Godot importer mirrors).
- `vendor/ez-tree/` — our MIT fork of ez-tree's `src/lib` (see `VENDOR.md`).
- `references/` — reference images for the overlay.

## Other features

- **Fit dials with Claude vision** — paste your Anthropic API key, drop a
  reference image, and Claude (`claude-opus-4-8`) analyzes it and sets the dials
  via strict tool use (shared `../voxel_studio_common/claude_vision.js`). The
  call goes **directly from your browser** with your key (stored only in
  localStorage) — fine for a local tool you run yourself; don't host with a
  shared key.
- **Space colonization** growth mode — organic attractor-based growth
  (`space_colonization.js`); switch via the **Growth** dropdown.
- **Web Worker** — voxelization runs off-thread (`tree.worker.js`) so big trees
  stay responsive; inline fallback if workers are unavailable.
- **Mobile** — responsive layout + a panel show/hide toggle.

## Deploying into Godot

- **Importer:** `scripts/_dev/VoxelTreeImporter.gd` reads an exported JSON and
  stamps it via `VoxelEditManager.queue_set_voxels_bulk`. Runtime only (needs
  the autoload) — see its header for usage. *Needs in-editor verification
  (`DESIGNER_TODO.md`).*
- **Materials:** ids 24–28 are wired with **placeholder** tiles + `.tres`
  resources. Bake them with `python tools/build_texture_atlas.py default` then
  `tools/build_blocky_library.gd` in-editor, and replace the placeholder PNGs
  with real pixel art. Until then, export with *log/leaves only*.

## Future (v2)

- Iterative reference optimizer (silhouette/colour fitting, not just heuristic).
- Real authored textures + the 6→10 vox/m engine scale migration.
