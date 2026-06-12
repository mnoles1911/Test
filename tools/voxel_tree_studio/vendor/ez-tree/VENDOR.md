# Vendored: ez-tree (forked)

Source: https://github.com/dgreenheck/ez-tree — `src/lib/` — **MIT License**
(© 2024 Daniel Greenheck; see `LICENSE`). Vendored from `main` (v1.1.0 line).

This is the `src/lib` core only (the generation library), not the editor app.
We run it directly in the browser with **no build step**; `three` resolves via the
host page's `<script type="importmap">`.

## Our modifications (kept minimal so re-syncing upstream is easy)

1. **`tree.js` — skeleton capture (additive, ~3 small blocks).**
   `generate()` initialises `this.skeleton = []` and `this.leafAnchors = []`.
   `generateBranch()` pushes each branch's centerline polyline
   (`{ level, points:[[x,y,z]...], radii:[...] }`) built from the section origins
   it already computes. `generateLeaf()` pushes each leaf origin `[x,y,z]`.
   These feed our voxelizer and do **not** change ez-tree's mesh output.

2. **Relative imports given explicit `.js` extensions.** Upstream uses
   extensionless specifiers (`from './tree'`) that Vite resolves; native browser
   ESM needs `./tree.js`. Purely mechanical.

3. **`presets/index.js` loads `presets/data.js` instead of importing JSON.**
   Browsers can't bare-import JSON without a bundler. `data.js` is generated from
   the original preset JSONs (kept alongside for provenance); the `TreePreset`
   map + `loadPreset()` behave identically to upstream.

Nothing else is changed. To re-sync: re-copy `src/lib`, re-apply the three edits
above (or diff against this tree).
