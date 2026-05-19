# GATE 0 RESULTS — Zylann native fluid API (binding facts)

Run 2026-05-18, headless, Godot 4.6.2.stable, via
`tools/headless/runner.gd -- gate0`. **RESULT = PASS** — the native-fluid
pivot is UNBLOCKED. These facts parameterise every downstream phase; do
not guess the API, use this.

## Classes (both registered)

- **`VoxelBlockyFluid`** extends `Resource` — the *shared* fluid def.
  - `material : Object` (`set_material`/`get_material`) — shared surface material.
  - `dip_when_flowing_down : bool` — Minecraft-style dip on downward flow
    (this is the native waterfall/dip behaviour; #12 leans on it).
- **`VoxelBlockyModelFluid`** extends `VoxelBlockyModel` — one model *per level*.
  - `const MAX_LEVELS = 256` (engine cap — NOT our N).
  - `fluid : Object` (`set_fluid`/`get_fluid`) — link to the shared `VoxelBlockyFluid`.
  - `level : int` (`set_level`/`get_level`) — this model's fluid level.
  - `color : Color`.
  - `transparency_index : int` — transparency/sort class (set above solids).
  - `culls_neighbors : bool`, `random_tickable : bool`, `tags_mask : int`,
    `lod_skirts_enabled : bool`.
  - `set_material_override()` / `get_material_override()` — per-model material
    override (same lever the cube water uses today).
  - `collision_aabbs : Array` (`set_collision_aabbs`), `collision_mask : int`
    (`set_collision_mask`), `set_mesh_collision_enabled()` — full collision
    disable path, mirrors the cube-water bootstrap exactly.
  - `set_mesh_ortho_rotation_index()` / `rotate_90()`.

## Decisions bound by these facts

- **N = 8 fluid levels.** `WaterByteCodec` LEVEL is 4-bit, `MAX_LEVEL = 8`
  (0 = air, 1..8 = water, 8 = full). So we register **8** `VoxelBlockyModelFluid`
  models with `level = 1..8`. Minecraft-faithful, zero codec change, no waste
  of the 256 engine cap. (Fidelity lever later = raise N + shader detail, never
  grid resolution — see the approved plan's Resolution Decision.)
- **One shared `VoxelBlockyFluid`** holds `material` (the new water shader,
  Phase 6) + `dip_when_flowing_down = true` (waterfall dip, #12).
- **8 contiguous TYPE ids** in the free 16–254 range (do NOT reuse 5). Old
  saves' literal `5` stays unambiguous for Phase-7 migration.
- **Collision off** per model via `set_collision_aabbs([])` +
  `set_mesh_collision_enabled(0,false)` + `set_collision_mask(0)` — identical
  belt-and-suspenders to the current cube-water block in `World3DBootstrap`.
- **`transparency_index`** set so fluid sorts after opaque solids (exact value
  validated visually at the Phase 2 designer gate; cube water used 2).
- Auto-slope between levels and the UV flow encoding are **native to
  `VoxelMesherBlocky`** when models carry `fluid` + `level` — no custom mesher,
  no slope code on our side (the entire point of the pivot).
