# Copper Isles World-Bake — Implementation Notes

Companion to `~/.claude/plans/make-plan-to-implement-buzzing-frost.md`.

This document records empirical findings about Zylann VoxelTools' GDExtension
APIs as they're discovered, plus design decisions and gotchas encountered while
building the bake pipeline.

The Zylann plugin in `addons/zylann.voxel/` is a binary GDExtension — no source
to read. Many of its API behaviors had to be probed at runtime. Findings live
here so future passes don't re-litigate the same questions.

---

## Voxel-resolution constants — change all together or none

If you ever want to bump the world from 6 vox/m to 8 or 10 (finer detail per
metre, larger SQLite cache, longer bake), every constant in this table has to
move proportionally. Updating only some of them produces inconsistent state:
the player's spawn coords sit on different terrain than expected, the skirt
floats above or below the live LOD0 voxels, the cache contains chunks the
runtime won't read, and so on.

| Constant | Where | At 6 vox/m | At 8 vox/m | At 10 vox/m |
|---|---|---|---|---|
| `terrain.transform.scale` | `scenes/CopperIslesTest.tscn` and `scenes/_dev/BakeWorld.tscn` (uniform 3-axis scale on the VoxelLodTerrain node) | 0.1667 | 0.125 | 0.1 |
| `extent_x_voxels` / `extent_z_voxels` | `assets/voxel/copper_isles_generator.tres` | 30 000 | 40 000 | 50 000 |
| `origin_x_voxels` / `origin_z_voxels` | `assets/voxel/copper_isles_generator.tres` | -15 000 | -20 000 | -25 000 |
| `elevation_above_at_white_voxels` | `assets/voxel/copper_isles_generator.tres` | 15 000 | 20 000 | 25 000 |
| `elevation_below_at_black_voxels` | `assets/voxel/copper_isles_generator.tres` | 240 | 320 | 400 |
| `sea_level_voxels` | `assets/voxel/copper_isles_generator.tres` | 720 | 960 | 1200 |
| `beach_y_threshold` | `assets/voxel/copper_isles_generator.tres` | 732 | 976 | 1220 |
| `GEN_SEA_LEVEL_VOXELS` | `scripts/CopperIslesTestBootstrap.gd` | 720.0 | 960.0 | 1200.0 |
| `GEN_PEAK_ABOVE_SEA_VOXELS` | `scripts/CopperIslesTestBootstrap.gd` | 15000.0 | 20000.0 | 25000.0 |
| `VOXELS_PER_METRE` | `scripts/_dev/WorldBakeController.gd` | 6.0 | 8.0 | 10.0 |
| `WORLD_FLOOR_VOXEL_Y` | three places: `CubicHeightmapGenerator.gd`, `CopperIslesHeightmapGenerator.gd`, `VoxelEditManager.gd` | -300 | -400 | -500 |
| Walker `TILE_SIZE_M` | `scripts/_dev/WorldBakeController.gd` (depends on `lod_distance` — at the **Zylann-capped lod_distance=128 vox**, LOD0 radius = 128/vox_per_m, walker spacing ≤ radius × √2) | 30 m | ~22 m | ~18 m |

> **Zylann lod_distance ceiling:** Empirically verified via the
> "Probe lod_distance accepted range" button in BakeWorld.tscn —
> Zylann silently clamps `lod_distance` to a max of **128 voxels**.
> Asking for 256 / 384 / 768 / 1024 all result in 128. To increase
> the visible LOD0 area, the only lever is dropping voxel resolution
> (vox/m table above): at 3 vox/m the same 128 cap gives 42 m LOD0
> radius. The bake controller's `_enforce_lod_config` now reads back
> the actual property value and prints `CLAMP DETECTED` whenever the
> setter doesn't take — catches this class of bug for any future
> Zylann property change.

### What re-bakes are needed after a vox/m change

- **Voxel SQLite cache** — INVALID. Chunks are keyed by absolute voxel-grid
  coords. Different `extent_*_voxels` and `sea_level_voxels` mean the same
  world XZ resolves to a DIFFERENT chunk-coord, and the old entries become
  unreferenceable. Delete and re-bake from BakeWorld.
- **Horizon skirt mesh** — INVALID. `SkirtBaker.bake_mesh` writes vertex Y
  values via `voxel_Y / voxels_per_metre`. If runtime vox/m differs from the
  bake-time value the skirt floats above (or sinks below) the live LOD0
  terrain. Re-bake the skirt with the matching `VOXELS_PER_METRE`.
- **Player spawn (`Player3D.SPAWN_POSITION`)** — re-pick after each resolution
  change. The world-meter coords land on different heightmap pixels (and so
  different terrain) at different vox/m settings.
- **Cache size grows nonlinearly.** 8 vox/m typically lands at 1.5-2.5× the
  6 vox/m cache size; 10 vox/m at 3-5×. Bake walltime grows similarly because
  `TILE_SIZE_M` shrinks (the LOD0 radius is the binding constraint).

---

## Probe results

> Last updated 2026-05-06 from the BakeWorld diagnostics panel run.

| Question | Status | Finding |
|---|---|---|
| Can `VoxelViewer` be instantiated at runtime, parented to any node, and have its `view_distance` honored from a position 2 km from the player? | CONFIRMED | `ClassDB.class_exists('VoxelViewer')` → true; `instantiate()` → returns Node OK; `view_distance` is writable (probe set it to 1500). Bake walker can spawn its own viewer freely. |
| Does `terrain.save_modified_blocks()` return an awaitable / signal? | PARTIAL | `has_method('save_modified_blocks')` → true. Return-type / signal behaviour not surfaced by property/signal listing — still need to test by call. Defensive `await` remains the right shape. |
| Does `save_generator_output = true` auto-persist generator-only blocks, or only after `save_modified_blocks`? | UNVERIFIED | Property exists on `VoxelStreamSQLite` (probe shows `save_generator_output = true`). Persistence semantics need a runtime test (write generator-only chunk, kill process without `save_modified_blocks`, reload, see if it survived). |
| Is `VoxelStreamScript` exposed for GDScript subclassing? | CONFIRMED | `ClassDB.class_exists('VoxelStreamScript')` → true. **Two-tier cache via `VoxelStreamFallthrough` is on the table.** Decision-gate cleared. |
| Property names on `VoxelStreamSQLite` for read-only / journal-mode / cache-size. | PARTIAL | Probe enumerated: `database_path`, `preferred_coordinate_format` (= 2), `save_generator_output` (= true), `compression_mode` (= 1). **No read-only, journal-mode, or cache-size properties exposed.** Implications: read-only protection of the baseline SQLite has to come from the OS (`res://` is read-only at runtime) or by opening the file separately; SQLite-level tuning isn't available through the plugin. |
| "Stream is idle" signal or queue-depth probe on `VoxelLodTerrain`? | NEGATIVE | Probe lists only Node-base signals (`tree_entered`, `ready`, `script_changed`, …) — no stream-specific signal. The walker's "no new SQLite rows for N frames" heuristic is the only path. |

Other findings worth recording:

- **`VoxelLodTerrain` properties** (relevant ones): `lod_count = 6`, `lod_distance = 96.0`, `secondary_lod_distance = 48.0`, `lod_fade_duration = 0.0`, `normalmap_begin_lod_index = 2`, `collision_lod_count = 0`, `mesh_block_size = 16`, `cache_generated_blocks = false`, `threaded_update_enabled = true`, `streaming_system = 0`, `process_thread_group = 0`, `process_thread_messages = 0`. The lack of any `view_distance` on the terrain itself confirms that view distance is owned by `VoxelViewer`.
- **`run_stream_in_editor = false`** — the bake tool must run in-game (F5) to actually stream chunks; nothing happens if BakeWorld.tscn is opened in the editor without running.
- **`debug_draw_*` properties** are exposed for runtime toggle; consider wiring them into the bake-tool UI for a "show streamed blocks" overlay.

The BakeWorld scene exposes a **Run Diagnostics** button that re-probes on
demand; re-run it after Zylann updates to catch API changes.

---

## Decisions log

### 2026-05-06 — Vertical extent cap (Phase A1)

`CopperIslesHeightmapGenerator._ensure_image()` now scans the EXR once for
`max_gray` and computes `_max_ground_y_voxels`. The per-block early-out uses
the actual scanned ceiling (~1500 vox for the current 8K EXR's brightest pixel)
instead of the theoretical `sea_level + elevation_above_at_white = 15001 vox`.

**Why:** Without this, every chunk allocation up to voxel-Y 15000 (~2500 m
world) would touch the per-voxel loop. With it, blocks above the actual
brightest pixel return in O(1).

**Diagnostic:** A one-shot print after the first 1000 blocks reports
`early-outs (NN%) — max_ground_y=NNNN vox`. Target ≥70%.

### 2026-05-06 — Drop `Image.load()` in shipped builds (Phase A2)

New export `require_heightmap_in_editor_only` on the generator. When true and
`OS.has_feature("template")`, `_ensure_image()` skips loading the EXR — saves
~30 MB of RAM and lets us drop the 8K EXR from the shipped PCK once the bake
covers every in-bounds chunk.

`CopperIslesTestBootstrap` sets the flag true unconditionally; the runtime
behavior switch is the `OS.has_feature` check inside `_ensure_image()`.

### 2026-05-06 — API probe results unblock two-tier cache (Phase 0)

The first BakeWorld diagnostics run (probe results table above) confirmed
the two decision-gates that were blocking the next phases:

1. **`VoxelStreamScript` is subclassable** → the planned `VoxelStreamFallthrough`
   GDScript class can be built. Two-tier cache (writable delta + read-only
   baseline) is the path; the "copy baseline into the slot" fallback is no
   longer needed.
2. **`VoxelViewer` instantiates and `view_distance` is writable at runtime**
   → the bake walker's phantom-viewer pattern works. No need to repurpose
   Player3D.

What the probe **didn't** answer (pending tests with explicit reload cycles):

- Whether `save_generator_output = true` persists generator-only chunks
  without an explicit `save_modified_blocks` call.
- Whether `save_modified_blocks` returns a signal/awaitable or just blocks.

These can't be answered by reflection — they need a runtime test that writes
chunks, exits the process without explicit save, and reloads. Defensive
behaviour stays in place until tested: walker calls `save_modified_blocks`
every 8 tiles, and `await`s the return value (a no-op if it's not awaitable).

What the probe **disproved** (and the design has to adapt to):

- **No SQLite tuning hooks.** `VoxelStreamSQLite` exposes only `database_path`,
  `preferred_coordinate_format`, `save_generator_output`, `compression_mode`.
  No journal-mode, no cache-size, no read-only flag. The "SQLite tuning lands
  as a separate phase" line in the original probe-result row is moot — there's
  nothing to tune. The shipped baseline is read-only by virtue of living in
  `res://`; the slot's delta DB uses defaults.
- **No stream-idle signal** on `VoxelLodTerrain`. The probe listed only the
  base Node signals — no stream-specific events. The walker's "no new SQLite
  rows for N frames" heuristic is the only path; keep it.

### 2026-05-06 — Bake LOD coverage was the real perf problem

After fixing `cache_generated_blocks` (below), the 1 km bake produced a
healthy 38.8 MB SQLite that the runtime correctly seeded into user://.
Bootstrap log + reopen log confirmed the file was being read. But perf
in the test scene was unchanged from before any baking — DIAG rate
prints showed sustained ~400 blocks/s of generator activity (essentially
100 % cache miss rate).

Root cause: **`lod_distance = 96` voxels gave LOD0 a radius of only 16 m
world**. The bake walker stepped at 200 m tiles, so each tile centre
cached LOD0 chunks within a 16 m radius — covering only ~5 % of the
LOD0 chunk surface area in the bake region. The runtime player asks for
LOD0 chunks within 16 m of their position, which mostly fell in the 95 %
the bake never touched → near-total cache miss.

Fix landed in this commit:

- `lod_distance` bumped to **384 voxels (64 m world)** in both
  `scenes/CopperIslesTest.tscn` and `scenes/_dev/BakeWorld.tscn`.
- `WorldBakeController.TILE_SIZE_M` shrunk from 200 → **80 m** so the
  walker's tile centres fall within 64 m of every point in the bake
  region (S × √2 ≤ R).
- Re-bake required: existing `assets/voxel/copper_isles_baseline.sqlite`
  is incompatible with the new lod_distance. Delete + re-run "Bake
  1 km central" → new size estimate 100-300 MB (more LOD0 chunks
  stored). Full 5 km is now ~3-4 hours; bring a book.

Diagnostic upgrade also landed: `_diag_record` now prints a generator
rate every 5 s (`DIAG rate: NN blocks/s ...`) so cache effectiveness
is visible in real time. Healthy populated cache should show ~0 blocks/s
once initial spawn-stream completes.

Trade-off: 16× more LOD0 triangles in view at runtime. Acceptable for
the test scene; revisit per-scene if frame time hurts.

### 2026-05-06 — `cache_generated_blocks` is the missing flag

The first 1 km bake hung at 96 % with the SQLite file stuck at 20 KB
(SQLite header + schema only — no voxel rows). Root cause:
**`VoxelLodTerrain.cache_generated_blocks` defaults to false.**

`save_generator_output = true` on the **stream** tells the stream "if you
receive a generator-output block, write it to disk." But the **terrain**
only forwards generator output to the stream when `cache_generated_blocks`
is true. Both flags must be set or generator output stays in memory and
gets thrown away when the chunk unloads.

Fix:
- `scenes/_dev/BakeWorld.tscn` and `scenes/CopperIslesTest.tscn` both set
  `cache_generated_blocks = true` on the VoxelLodTerrain.
- The bake walker now ends with `_park_viewer_far_and_drain()` which
  moves the phantom viewer 100 km away to force every loaded chunk to
  unload (and thereby trigger save-before-evict).
- `_flush_save()` is fire-and-forget instead of awaiting the return Signal
  — empirically, the Signal sometimes never fires when there's nothing
  to save, causing the previous "stuck at 96 %" hang.
- Added a "Force Save" button to the bake UI for debugging persistence
  issues without re-running a full bake.

### 2026-05-06 — Phase C lands as bake-as-seed (NOT two-tier wrapper)

The probe confirmed `VoxelStreamScript` is subclassable, but `VoxelStreamSQLite`'s
`_load_voxel_block` / `_save_voxel_block` methods are NOT exposed to GDScript —
the four properties enumerated by the probe (`database_path`,
`preferred_coordinate_format`, `save_generator_output`, `compression_mode`) are
the entire public API surface. A `VoxelStreamFallthrough` wrapper would have to
implement its own SQLite reader compatible with Zylann's undocumented schema —
high effort, brittle, and pointless given the simpler alternative below works.

**Implemented instead — bake-as-seed (Option 1):**

`CopperIslesTestBootstrap._seed_from_baseline_if_needed()` runs at the very top
of `_ready`. If `user://copper_isles_test.sqlite` doesn't exist AND
`res://assets/voxel/copper_isles_baseline.sqlite` does, the bootstrap copies the
baseline into the working SQLite path. The single existing `VoxelStreamSQLite`
then opens the populated DB, and `save_generator_output=true` keeps both the
seeded baseline state and player edits in the same file going forward.

**Trade-offs vs the two-tier plan:**

- (+) Zero new APIs needed. Works with stock Zylann + stock Godot.
- (+) Identical chunk fetch cost — single SQLite, single read path.
- (−) Each save slot is a full copy of the baseline (~1-3 GB per slot once
  the bake is full). For a single-slot dev scene, irrelevant; if the trilogy
  ever needs many slots sharing one baseline, revisit.
- (−) "Reset to baseline" is `delete user://copper_isles_test.sqlite + relaunch`
  rather than a runtime in-game action.

**Not done — Phase D1 (SQLite tuning):** Cancelled. The probe confirmed that
`VoxelStreamSQLite` exposes no `journal_mode`, `cache_size`, or `read_only`
properties. There's nothing to tune through the plugin. PRAGMA-level tuning
would require either a Godot SQLite addon (extra dependency) or modifying
Zylann's source (binary GDExtension; not feasible). Re-evaluate if Zylann
adds tuning hooks upstream.

### 2026-05-06 — Sea level Y bumped to 72 voxels

`CubicHeightmapGenerator.SEA_LEVEL_VOXELS` is now 72 (was 60). World Y at
the default 1/6 scale = 12 m (was 10 m). Done to give the player a more
visible water mass during the per-voxel ocean (Option B) bring-up.

Anything that mirrors the constant — `WaterChunkMesher._SEA_LEVEL_VOXELS`
(72), `World3DBootstrap.OCEAN_SURFACE_Y` (12.0) — must move together.
`CopperIslesHeightmapGenerator.GEN_SEA_LEVEL_VOXELS` is independent (the
Copper Isles bake uses its own generator scale).

---

## Architectural snapshots

### Two-tier cache (pending Phase 0 + Phase C)

```
VoxelLodTerrain.stream  →  VoxelStreamFallthrough  (custom GDScript, NEW)
                              ├── primary   = VoxelStreamSQLite("user://saves/slot_N/delta.sqlite", save_generator_output=true)
                              └── fallback  = VoxelStreamSQLite("res://assets/voxel/copper_isles_baseline.sqlite", read_only=true)
```

Read path: try primary → fall back → null (generator).
Write path: always primary.

Conditional on Phase 0 finding `VoxelStreamScript` subclassable. If not, the
fallback plan is to copy the entire baseline SQLite into the slot's user://
directory on first boot and treat it as the slot's writable DB — simpler,
costs ~baseline-size disk per slot.

### Bake walker

- Tile size: 200 m (1200 vox); view_distance is 1500 vox so each tile has ~50 m
  of streaming overlap with neighbours.
- Phantom `VoxelViewer` instead of repurposing Player3D's — bake scene has no
  player at all.
- Per tile, 4 vertical positions: floor (-50 m world), 0, mid-peak, peak.
- Pre-pass over EXR builds a "tile has land" bitmap; ocean-only tiles skipped.
- `save_modified_blocks` every 8 tiles for crash-safety + UI file-size update.
- Stream-idle heuristic: no new SQLite rows for 6 consecutive frames OR
  30-second timeout.

---

## 2026-05-07 — Movement-perf debugging session (World3D + CopperIslesTest)

Long-standing "FPS tanks the moment the player moves" symptom in both scenes
was finally traced after wiring a per-autoload profiler into `HUDOverlay`
(see CLAUDE.md → "Per-autoload performance attribution"). Root causes and
fixes, in order of impact:

**`WaterChunkMesher` was eating 700–1200 ms/sec of main-thread time.** The
profiler attributed almost the entire frame budget to it. Two compounding
causes: (1) `MESH_RENDER_RADIUS_M = 96` meant ~5,300 candidate chunks at the
sea-level row, with ~73 newly entered per chunk crossing; (2)
`_gather_surface_quads` called `tool.copy()` on every dirtied chunk —
which **blocks for 5+ ms** when Zylann hasn't streamed the chunk yet.
The mesher also competed with Zylann's main-thread mesh-apply queue, which
is why terrain failed to render while the mesher was working. Three-part
fix in `scripts/WaterChunkMesher.gd`:
- `MESH_RENDER_RADIUS_M` 96 → 32 (~9× fewer candidates).
- `MESH_BUILDS_PER_FRAME_MAX` 16 → 6 (per-frame ceiling).
- `tool.is_area_editable` (~1 µs) probe before `tool.copy` — skips
  unloaded chunks fast; they get re-dirtied on the next chunk crossing,
  by which time Zylann has had a chance to load them.

Result: mesher dropped from ~900 ms/sec to ~14 ms/sec; walking FPS went
from 38 (frame-budget-locked) to 200+.

**`set_player_chunk` rewritten as delta-only.** Was iterating the full
~5,300-chunk square on every chunk crossing. Replaced with leading-edge
strips only (~73 chunks per axis-aligned move, ~145 per diagonal). First
call and large jumps still take the ring-ordered full-fill so visible
water materialises around the player on initial load. Same optimisation
pattern as the 2026-05-05 fix (LESSONS_LEARNED #43) at a different scope.

**`collision_update_delay` is INT in this Zylann build.**
`terrain.set("collision_update_delay", 0.1)` silently truncated to 0,
firing immediate main-thread collision rebuilds on every streaming chunk.
Set to integer `100` (ms) in `World3DBootstrap.gd`,
`CopperIslesTestBootstrap.gd`, `WorldBakeController.gd`, with read-back
prints (`actual=N`) so the next regression catches itself.

**`cache_generated_blocks = true` was missing from World3D.tscn.** Already
documented for the bake pipeline (2026-05-06 section above) but the World3D
scene was authored before that finding. Generator was re-running on every
chunk eviction. Now added to the VoxelLodTerrain block in
`scenes/World3D.tscn`.

**`mesh_block_size = 32` cuts chunk count by ~8× on World3D.** Each mesh
chunk covers 32³ voxels instead of 16³. Set in both the .tscn AND
programmatically in `World3DBootstrap.gd` with read-back, because the
Godot editor has stripped the .tscn line on save more than once. Verify
via the `actual=32` readback — Zylann clamps to 16 in some configurations.
This is the only chunk-count lever available when `view_distance` and
`lod_count` are off-limits (e.g. shared with a baked scene).

**`lod_distance` bumped 96 → 128 (Zylann's hard cap).** Wider LOD shells
mean chunks transition LOD level less often as the player moves =
fewer mesh-uploads-during-backtracking. Bootstrap also sets this
programmatically with read-back.

**`streaming_system = 1` (CLIPBOX) broke World3D.** CLIPBOX treats
`terrain.view_distance` as a strict cap. World3D has the default 512-vox
view_distance (~85 m world at 1/6 scale); player spawns at Y=120 while
heightmap peaks at Y=33 — that's ~87 m below, JUST outside the cap. Result:
zero terrain streamed, player free-fell, worker threads burned CPU on
out-of-bounds chunks. Reverted to `streaming_system = 0` (octree, more
lenient). CopperIslesTest can use CLIPBOX because the SQLite is pre-baked
AND the player spawns inside the bake area. Re-evaluate CLIPBOX for
World3D when (a) `terrain.view_distance` is bumped, or (b) the spawn
moves closer to ground.

**`lod_count` for the bake/runtime trio trimmed 14 → 9.** With
`view_distance = 8000` and `lod_distance = 128`, only LODs 0–6 actually
stream. LODs 7–13 sat permanently outside view_distance. Both
`CopperIslesTestBootstrap.REQUIRED_LOD_COUNT` and
`WorldBakeController.REQUIRED_LOD_COUNT` updated. Existing baselines
baked at 14 remain readable (Zylann ignores LOD slots above the active
lod_count). `BakeWorld.tscn` lod_count is 14 in the working tree (the
Godot editor wrote it during a manual bake-control session); the
controller overrides to 9 at runtime regardless, so the .tscn value is
not load-bearing.

**Diagnostic infrastructure landed in `HUDOverlay.gd`.** A `[PERF]` line
emits once per second with FPS, spike count, top-3 autoload time buckets
(via `profile_record`), and engine-wide stats (draws, prims, nodes,
orphans, vram). Replaces the previous per-frame `[FRAME SPIKE]` flood that
was itself contributing to the spikes (each Output-panel print costs
0.5–2 ms at sub-10 FPS). Toggle off via `HUDOverlay.PERF_DIAG = false`
when not actively investigating perf.

---

## Open questions for future passes

- Does Zylann respect the same chunk size at LOD>0, or do higher LODs use larger blocks? Affects walker step size for the LOD pyramid.
- Can the SQLite DB be safely copied while Zylann has it open? (The "Copy to assets/voxel" UI button needs to know.)
- Is there a public API to LIST all chunks currently cached in the DB, or do we need to query SQLite directly via the Godot SQLite addon?
