# Copper Isles World-Bake — Implementation Notes

Companion to `~/.claude/plans/make-plan-to-implement-buzzing-frost.md`.

This document records empirical findings about Zylann VoxelTools' GDExtension
APIs as they're discovered, plus design decisions and gotchas encountered while
building the bake pipeline.

The Zylann plugin in `addons/zylann.voxel/` is a binary GDExtension — no source
to read. Many of its API behaviors had to be probed at runtime. Findings live
here so future passes don't re-litigate the same questions.

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

## Open questions for future passes

- Does Zylann respect the same chunk size at LOD>0, or do higher LODs use larger blocks? Affects walker step size for the LOD pyramid.
- Can the SQLite DB be safely copied while Zylann has it open? (The "Copy to assets/voxel" UI button needs to know.)
- Is there a public API to LIST all chunks currently cached in the DB, or do we need to query SQLite directly via the Godot SQLite addon?
