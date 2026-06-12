# Destructible Voxel Trees

Generator-emitted, fully destructible trees for World3D (Mira). Trees are
**real CHANNEL_TYPE voxels** — a square `log` (id 10) trunk under an eroded
ellipsoid `leaves` (id 11) canopy — laid down by the C++ heightmap generator
as a pure deterministic function of (lattice cell, seed, biome tree params).
Because they are ordinary solid voxels, they mine, fall, sever, and float
through the systems that already exist; nothing tree-specific runs at play
time.

**Status:** built + green on the headless `trees` gate; emits in-game on the
**biome path only** (the generator needs per-biome `tree_density`). Gated by
the same `World3DBootstrap.biome_framework_enabled` flag as the biome
framework (now default ON). The legacy single-recipe path (and any build with
no biome profiles) emits **zero** trees, so the pinned `gen` baseline is
untouched.

---

## Why "trees are just voxels"

A tree is not an entity, a scene, or a prop. It is a deterministic pattern of
`log` and `leaves` voxels written into the terrain buffer at generation time,
exactly like the ground or the ocean. That single decision buys every gameplay
behaviour for free:

- **Mining** — a `log` voxel is a normal voxel with `yield_item_id =
  "raw_log"`; chopping it routes through `VoxelEditManager` like any dig.
- **Felling = the existing sever system.** Cut the trunk and the
  `SeverFollowLib` BFS floods the connected non-air/non-water voxels (logs +
  leaves are outside the `FloraMaterial.is_passthrough()` 24..28 range, so they
  read as SOLID) and the whole crown drops as ONE cluster via
  `VoxelGravityManager`. No tree-fall code was written — it is the same
  upward-follow that already carries a severed stone overhang.
- **Floating** — a felled cluster of `log` voxels that lands in water obeys
  the same buoyancy/settle the gravity + finite-water systems already apply to
  any solid cluster.
- **Determinism** — no RNG state, no per-chunk noise. Regen, save-reload, and
  two players streaming the same chunk all reproduce the identical forest.

---

## File map

| File | Role |
|---|---|
| `extensions/voxel_gen/src/heightmap_generator_base.{h,cpp}` | `resolve_tree(lattice_x, lattice_z)` (the pure shape resolver) + `tree_max_reach_voxels()` + the **tree pass** in `generate_block_into_buffer` that stamps the trunk + canopy voxels. Wired ids/knobs: `tree_log_material_id`, `tree_leaves_material_id`, `tree_seed`, `tree_lattice_voxels`, `tree_max_lod`, `tree_spawn_free_radius_voxels`. |
| `extensions/voxel_gen/src/biome_field.{h,cpp}` | `BiomeProfilePOD` carries the seven tree params; `set_biome_profiles` reads them out of the flattened dict. |
| `scripts/BiomeProfile.gd` | The seven designer-editable `@export` tree fields + heavy tooltips; `to_pod_dict()` flattens them. |
| `assets/biomes/*.tres` | Per-biome tree density + species ranges (below). |
| `scripts/_dev/CubicHeightmapGeneratorAdapter.gd` | `set_tree_materials(log_id, leaves_id)` forwarder. |
| `scripts/World3DBootstrap.gd` | `--- TREES BLOCK ---`: reads `log`/`leaves` ids from `VoxelMaterialRegistry` and pushes them to the generator (0-default-disabled, like flora). |
| `scripts/_dev/TreeReference.gd` | Pure-GD mirror of `resolve_tree` + the per-voxel stamp (`tree_voxel_at`) — the `trees` gate's parity reference. |
| `tools/headless/runner.gd` | The `trees` selector. |
| `assets/voxels/materials/log.tres` (id 10), `leaves.tres` (id 11) | The two VoxelMaterials. |

### Worker-thread safety + legacy fallback

All tree state is value-typed (ints + the biome POD vector). The tree pass runs
inside `generate_block_into_buffer` on the Zylann worker thread with no
SceneTree access. With `tree_log_material_id == 0` (no bootstrap wiring) **or**
no biome profiles loaded, `resolve_tree` returns "no tree" and the pass is
skipped entirely — that is what keeps the `gen` baseline tree-free.

---

## The shape / lattice math (as implemented)

### Anchor lattice

Candidate trees live on an **8 m grid** (`tree_lattice_voxels = 80` at
10 vox/m): one candidate per `80×80`-voxel cell. The block-fill loop, after
laying terrain, scans every lattice cell whose tree could reach the block's XZ
footprint — the scan window is widened by `tree_max_reach_voxels()` (the
largest canopy radius across loaded biomes, +1) so a canopy whose **trunk is in
a neighbouring block** is still stamped here. This is the chunk-spanning
correctness: a block emits the intersecting voxels of *every* tree whose anchor
is within reach, so two adjacent blocks emit identical voxels for a shared
tree.

### `resolve_tree(lattice_x, lattice_z)` — pure function

All hashes are `VoxelGenerationMath.hash3(x, salt, z, seed) → [0,1)` (the same
hash the flora scatter uses; the GD reference preloads the same file).

1. **Disabled checks.** `tree_log_material_id == 0` or no biome profiles → no
   tree.
2. **Jittered trunk.** `trunk = lattice*grid + floor(hash·grid)` with salts 1
   (x) and 2 (z) — pushes the trunk off the grid node so forests don't
   grid-align.
3. **Spawn-free disc.** Trunk within `tree_spawn_free_radius_voxels` (60 vox ≈
   6 m) of world origin → no tree (never bury the player at spawn).
4. **Biome pick.** `pick_surface_biome(trunk_x, trunk_z)` — the SAME
   weighted-hash that dithers the ground material, so a tree on a forest border
   reads as the dominant biome there. `tree_density <= 0` → no tree (desert,
   mountains).
5. **Existence roll.** `hash(salt 0) >= tree_density` → no tree. (So
   `tree_density` is literally trees-per-cell.)
6. **Ground gate.** `ground_y = compute_ground_y(trunk)` — the same per-column
   surface the terrain uses, so the trunk sits exactly on the ground. Trunk at
   or below sea level → no tree (no trees standing in the ocean). Top material
   must be `grass` (id 3) → no trees on sand/snow/stone tops that fall inside a
   grassy biome's border.
7. **Species params** from independent hashes (salts 3,4,5):
   - `height_vox = (height_min_m + hash·Δheight) · vpm`
   - `trunk_radius = round(trunk_r_min + hash·Δtrunk_r)` (square column,
     `2r+1` voxels across)
   - `canopy_radius = round(canopy_r_min + hash·Δcanopy_r)`
   - `canopy_half_height = round(canopy_radius · 0.8)` (a slightly squashed
     ball, not a perfect sphere)
   - `canopy_center_y = trunk_top - canopy_half_height/2` (leaves wrap the top
     third of the trunk)
   - `shape_salt` (salt 6) — per-tree salt for canopy-edge erosion.

### Per-voxel stamp (the tree pass)

For each loaded buffer voxel at world `(wx,wy,wz)` within a tree's reach:

- **Never below ground.** `wy <= ground_y` → skip (trees only overwrite AIR).
- **Trunk:** inside the square `trunk_radius` AND `ground+1 <= wy <=
  ground+height` → `log` (10).
- **Canopy:** ellipsoid test
  `norm = (ddx²+ddz²)/canopy_radius² + ddy²/canopy_half_height²`. `norm <= 1`
  → a leaf, EXCEPT near the rim (`norm > 0.55`) where a per-voxel
  `hash(wx,wy,wz, shape_salt)` punches holes (erosion ramps 0→0.5 from
  `norm 0.55→1.0`) so the silhouette is ragged, not a clean ball. Inner leaves
  are solid so the crown isn't see-through → `leaves` (11).
- **Air-only write.** The voxel is only written where the cell is still air, so
  the tree never carves ground, water, or flora the column loop already wrote.

### LOD

Trees emit at `lod 0..tree_max_lod` (default 2 — through the ~51 m collision
ring). At `lod>0` each coarse voxel spans `stride` fine units; the shape is
sampled at each coarse voxel's centre (fine-world coord), the same way the
terrain band samples `ground_y`. So distant forests still read as forests.

---

## Per-biome tuning (`assets/biomes/*.tres`)

| Biome | `tree_density` | Height (m) | Trunk r (vox) | Canopy r (vox) | Reads as |
|---|---|---|---|---|---|
| deciduous_forest | 0.55 | 9–14 | 3–5 | 16–26 | dense oak woodland (~1 tree / 6×6 m) |
| rolling_hills | 0.10 | 8–13 | 3–5 | 15–24 | sparse lone trees (~1 / 25×25 m) |
| flat_plains | 0.02 | 8–12 | 3–4 | 15–22 | rare lone trees on open field |
| rocky_desert | 0.0 | — | — | — | none |
| mountains | 0.0 | — | — | — | none (stone top would reject anyway) |

All seven fields are `@export` on `BiomeProfile.gd` with designer tooltips —
tune a `.tres` in the Inspector and restart; no code edit. Re-run
`run.ps1 trees` after a change (it re-checks the determinism / seam / density
invariants).

---

## Gate (`run.ps1 trees`)

Configures a real `CubicHeightmapGeneratorCpp` exactly like the bootstrap, then:

| Check | What it proves | Result |
|---|---|---|
| (a) determinism | a forest block generated twice is bit-identical | PASS |
| (b) seam | every tree voxel in two ADJACENT blocks matches `TreeReference`'s canonical per-voxel stamp at that world coord (so the blocks agree on the boundary) | PASS (7548 voxels) |
| (c) density ordering | forest tree voxels > plains; desert == 0; mountains == 0 | PASS (forest 1064, plains 0, desert 0, mtn 0) |
| (d) legacy path | no-profiles generator emits 0 tree voxels (`gen` baseline clean) | PASS |
| (e) lod1 | forest region emits trees at lod 1 | PASS (6462 voxels) |
| (f) parity | every GD-resolved forest tree has a C++ `log` at the trunk base (`TreeReference` ≡ C++ shape math) | PASS (7 trees) |

The `gen` + `distant` baselines stay PASS because both pin the legacy
no-profiles path (the orchestrator's pin clears profiles in those gates).

---

## Follow-ups (logged, NOT built here)

1. **Species variety.** `BiomeProfile.tree_table` (the `{kind, weight}` list)
   is still carried but unread — v1 emits one broadleaf species per biome. A
   later pass can pick species/shape per-tree from the table.
2. **Conifers / shaped canopies.** Only the squashed-ellipsoid broadleaf crown
   exists. A `canopy_shape` enum (cone for pines, etc.) is the natural
   extension.
3. **Root flare / stumps.** The trunk is a clean square column from `ground+1`.
   A widened base or a leftover stump after felling is cosmetic polish.
4. **Distant-skirt + far-grass biome gating** (already logged in
   `BIOME_FRAMEWORK.md`) interacts with trees: the distant smooth shell does
   not render trees, so a forest's canopy pops in at the LOD2→3 boundary. A
   distant tree-impostor layer (like `FarGrassManager`) is the fix.
5. **Tree-aware NoEditZones / spawn polish.** The 6 m spawn-free disc keeps the
   trunk out of the player; a settlement could additionally want a tree-free
   buffer (the existing NoEditZone system doesn't yet gate generation).

---

## Designer acceptance bullets

- [ ] With `biome_framework_enabled = true`, walk into a `deciduous_forest`
  region: thick varied-height trunks (`log`) under organic green
  (`leaves`) crowns, dense enough to read as a forest, sparse-to-none in
  hills/plains, none in desert/mountains.
- [ ] **Chop a trunk → the whole tree falls as ONE cluster.** Mine through the
  base logs; the connected crown severs and drops via the existing
  gravity/sever system (logs + leaves are solid, so the BFS carries them
  together).
- [ ] **Fell a tree into a pond → the logs float.** A landed cluster on water
  behaves like any solid cluster the gravity + finite-water systems settle.
- [ ] No trees within ~6 m of world spawn.
- [ ] Tune any biome's tree fields in `assets/biomes/<name>.tres` (Inspector,
  tooltips) and restart — no code edit. Re-run `run.ps1 trees` after a change.
