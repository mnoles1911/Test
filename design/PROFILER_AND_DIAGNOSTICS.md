# Profiler + Diagnostics Workflow

Reference for in-game performance profiling and perf-issue diagnosis.
**Future-session Claude:** read this before guessing at perf issues —
the profiler captures usually contain the answer.

## TL;DR — fast path to a diagnosis

1. User runs the game with `Profiler.capture_on_startup = true`
   (`scripts/Profiler.gd` @export, flip before `F6`).
2. Capture lands at `C:\Users\Matt Noles\AppData\Roaming\Godot\app_userdata\Game One\profile_capture_<msec>.json`.
3. **Only one JSON exists at a time** — `capture_start()` auto-wipes
   prior captures. You don't need to guess which file is latest.
4. User pastes the file path (or contents) AND the `[PERF]` / `[DIAG]`
   lines from the Output panel.
5. Read JSON directly (use `Bash python -c` for aggregation), pair
   with the log lines, propose the next change.

The JSON tells you which **wrapped GD scripts** ate frame time.
The `[PERF]` / `[DIAG]` log lines tell you what **engine and Zylann**
were doing. You need both to see the full picture.

## Tooling

### Autoloads

- **`Profiler`** (`scripts/Profiler.gd`) — single source of truth for
  per-system timing. API:
  - `Profiler.record(category, name, usec)` — primary recording call
  - `Profiler.scope(category, name) → Scope` — begin/end token, call
    `.close()` to record
  - `Profiler.frame_finalize()` — called by HUDOverlay every frame
  - `Profiler.capture_start() / capture_stop(path)` — JSON dump
  - `Profiler.set_enabled(bool)` — toggle off for zero cost
- **`ProfilerOverlay`** (`scripts/ProfilerOverlay.gd`) — F3-toggled
  CanvasLayer at layer 90. Three pages: Overview (top-20 systems by
  max µs), Timeline (120-frame bar chart), GPU (engine + Zylann
  counters).

### Overlay controls (keyboard-only, the project's GUI dispatch is
unreliable per CLAUDE.md)

| Key | Action |
|---|---|
| `F3` | Toggle overlay |
| `Tab` | Cycle pages (Overview → Timeline → GPU) |
| `P` | Pause/resume sampling |
| `C` | Start/stop a capture (writes JSON on stop) |
| `S` | Save in-progress capture immediately |
| `Q` | Clear stats |
| `← →` | Move timeline cursor (Timeline page only) |

### Capture-on-startup

For profiling spawn handoff (which happens before the user can hit
F3+C), edit `scripts/Profiler.gd`:

```gdscript
@export var capture_on_startup: bool = true   # flip to true
@export_range(5.0, 120.0, 1.0) var startup_capture_seconds: float = 30.0
```

F6 the target scene. Output shows:
```
[Profiler] capture started
[Profiler] startup auto-capture armed; will stop in 30 s
...
[Profiler] startup auto-capture stopped → user://profile_capture_NNNNN.json
```

**Flip back to false** after — every F6 fires a fresh capture
otherwise, and the auto-wipe will clobber a capture you wanted to
keep across runs.

## Water diagnostics (`WaterDiag` autoload — F4/F5/F6)

`scripts/WaterDiag.gd` (CanvasLayer autoload, layer 6) is the standing
surface for **all** water work — the distant dark-grid fix, the flow-Y
bug, waterline jitter, the deferred flow sim. **Read this before
hand-bisecting water with throwaway shader tweaks.** All dev-only,
default OFF, keyboard-toggled, read-only (never mutates water).

| Key | Action |
|---|---|
| `F4` | Toggle the on-screen Water panel. While visible, also prints a consolidated `[WaterDiag]` line once/sec (pasteable into a diagnosis). |
| `F5` | One-shot `[WaterInspect]` dump of the column + 3×3 mesh-block neighbourhood under the camera. |
| `F6` | Cycle the water shader `debug_mode` 0→1→2→3→4→5→0 live. |

**Panel / `[WaterDiag]` fields:** `pos`; `in_water` + `submerged`
(head); `level` 0–8; `surface Y` (world-Y of the topmost water voxel in
the player column) + `Δ` to the player (the number #3 flow-Y and #4
waterline-jitter need); `sea level` / `horizon` Y; `flow sim` on/off
(reads `WaterFlowManager._FLOW_SIM_ENABLED` via the script constant
map); `shader dbg`; `query us` (smoothed `is_position_in_water` cost);
`expected LOD @ dist`.

**`[WaterInspect]` (F5) — the dark-grid measurer.** Prints 3×3 sample
columns spaced one mesh-block (16 vox) apart so adjacent samples land
in neighbouring mesh blocks. Each cell: `top=` (water-top voxelY),
`n=` (TYPE-5 count in that block slab — the no-C++-rebuild proxy for
"what the generator/mesher produced here"), `Δ±` (top vs centre).
*Read:* equal `top=` across neighbours = water coplanar (good);
differing `top=` / nonzero `Δ` at the block step = the distant
**dark-grid LOD-seam mismatch** (root-caused 2026-05-17: per-block
water slabs whose tops aren't coplanar across LOD boundaries → exposed
vertical side faces → depth-fade paints them `deep_water_color`).

**Shader `debug_mode` (F6 cycles; also settable in
`water_material.tres`):** `0` normal · `1` depth_t (white = deep) ·
`2` fresnel · `3` thickness as opaque grey (no blend/Fresnel — isolates
geometry from transparency) · `4` surface-facing (white = up-facing
water top, black = vertical side/riser) · `5` **flow vector** (hue =
native-fluid flow direction, brightness = flow strength; still water =
black — added by the native-fluid pivot 2026-05-18; confirms the Zylann
fluid mesher's flow matches the visible slope / `[FlowDiag]` DIR).
**These five are permanent diagnostics — do not remove them from
`water.gdshader`.** The 2026-05-17
bisection that root-caused the dark grid is the reference recipe: 0
(confirm) → fade off (is depth-fade the amplifier?) → mode 3 (is it
geometry vs transparency blend?) → mode 4 (side faces vs stepped tops?).

**`[FlowDiag]` (WaterFlowManager, ~2 s throttle) — the flow-Y measurer.**
Prints only while the v2 sim does work (`flood`/`gravity` writes or a
non-empty dirty set), so it's sparse but easy to lose under the per-frame
`[DIAG]`/`[WaterDiag]` spam — **filter the Output panel for `FlowDiag`.**
Fields: `dirty_chunks`, `flood`/`gravity` (writes this window),
`edit_ttl_cells` (carve-permission cells still live; decays ~1 s after
you stop digging), `last` (last write voxel), `sea_voxY`, and the #3
trio: **`maxWriteY`** (highest Y any flow write touched — `n/a` if none),
**`above_sea`** (count of writes strictly above sea level — the bug,
quantified), **`worst`** (the offending voxel, if any). *Read:* clean run
= `maxWriteY` == `sea_voxY`, `above_sea=0`. **#3 ("dig near water creates
water above the start plane") was VERIFIED CLOSED 2026-05-17:** 78
flood+gravity writes in one window, `maxWriteY=72` (== sea), `above_sea=0`
— V2's `wpos.y <= sea_y` flood gate + downward-only gravity fixed it by
construction; the pre-V2 DATA5 automaton was the original cause.
*Not* #3 and still open: flood **coverage** stalls partway through a
large multi-chunk dug-out volume (the `edit_ttl_cells` ~1 s window +
own-chunk-only re-dirty outrun by big digs) — a deferred dynamic-flood
refinement, a hard waterline not an above-plane error.

**Profiler `WATER` category** groups: `WaterFlowManager` (flow tick,
wrapped in `_physics_process`), `WaterQuery` (every player
`is_position_in_water`/`get_water_level_at` — wrapped at the
`_read_water_byte_at` chokepoint with a cached Profiler ref), and
`WaterDiag` (the panel poll). Watch these in the F3 overlay's WATER row.

## File locations

`user://` in Godot maps to `%APPDATA%\Godot\app_userdata\<project-name>\`
on Windows. For this project (`config/name = "Game One"`):

- **Capture JSONs:** `C:\Users\Matt Noles\AppData\Roaming\Godot\app_userdata\Game One\profile_capture_*.json`
- **Save SQLite:** same folder, `voxel_deltas.sqlite`
- **Settings:** same folder, `settings.json`

Direct from Godot: **Project → Open User Data Folder**.

The Profiler **auto-wipes prior captures** when `capture_start()` runs,
so the folder only ever contains one `profile_capture_*.json` after a
test cycle. No need to guess which is the latest.

## JSON schema

Top-level:
```json
{
  "version": 1,
  "frames": 1234,
  "duration_ms": 30000,
  "records": [ {...}, {...} ]
}
```

Per-frame record:
```json
{
  "frame": 89,
  "total_us": 18923,
  "attribution": {
    "WATER.WaterChunkMesher": 8431,
    "WORLD.VoxelEditManager": 3201,
    "PHYS.Player3D": 1844,
    "PHYS.Player3D_move_and_slide": 1402,
    "PHYS.Player3D_viewer_lookahead": 87,
    "PHYS.Player3D_camera_smooth": 12,
    "PHYS.PrefetchViewer": 234,
    "WEATHER.WeatherManager": 612,
    "WEATHER.DayNightCycle": 89,
    "WORLD.WorldClock": 8
  },
  "engine": {
    "proc_us": 4500,
    "phys_us": 1200,
    "draws": 142,
    "prims": 10737884,
    "vram_mb": 247
  },
  "zylann": {
    "detect_us": 8,
    "io_us": 0,
    "mesh_us": 1,
    "update_us": 0,
    "blocked_lods": 0,
    "dropped_loads": 0,
    "dropped_meshs": 0
  }
}
```

- `total_us` is the sum of `attribution` values — covers only
  wrapped GD scripts. Typically 1-5% of frame time.
- `engine.proc_us + phys_us` covers ALL `_process` /
  `_physics_process` work (including unwrapped GD + engine internals).
  This is where the "missing 96%" lives.
- `zylann.*` is Zylann's main-thread budget. `detect_us` is the
  octree/CLIPBOX scan; `mesh_us` / `io_us` / `update_us` are mostly
  worker-thread synchronization overhead.
- `dropped_loads` / `dropped_meshs` rise when Zylann gives up on
  pending requests because the chunk set was invalidated faster
  than it could process. High values indicate streaming pressure
  or main-thread saturation.

Categories used: `WORLD`, `WATER`, `WEATHER`, `PHYS`, `OTHER`.

## Analyzing captures — Python recipes

### Top contributors by total time

```python
import json
from collections import defaultdict

with open('profile_capture_NNNNN.json') as f:
    d = json.load(f)

sums = defaultdict(int)
maxes = defaultdict(int)
counts = defaultdict(int)
for r in d['records']:
    for name, us in r['attribution'].items():
        sums[name] += us
        counts[name] += 1
        if us > maxes[name]:
            maxes[name] = us

ranked = sorted(sums.items(), key=lambda x: -x[1])
total_cap_us = sum(r['total_us'] for r in d['records'])
print(f"{'System':<40} {'total_ms':>10} {'avg/f_us':>10} {'max/f_us':>10} {'%cap':>6}")
for name, tot in ranked[:25]:
    avg = tot // max(1, counts[name])
    pct = (tot / max(1, total_cap_us)) * 100
    print(f"{name:<40} {tot//1000:>10} {avg:>10} {maxes[name]:>10} {pct:>5.1f}%")
```

### Frame distribution + spike count

```python
totals = sorted(r['total_us'] for r in d['records'])
n = len(totals)
print(f"p50 wrapped: {totals[n//2]} us")
print(f"p90 wrapped: {totals[int(n*0.9)]} us")
print(f"p99 wrapped: {totals[int(n*0.99)]} us")
print(f"max wrapped: {totals[-1]} us")
spikes = [r for r in d['records'] if r['total_us'] > 33000]
print(f"frames > 33ms wrapped: {len(spikes)}/{n}")
```

### Engine + Zylann correlation (only if `engine` / `zylann` fields exist)

```python
for r in d['records']:
    eng = r.get('engine', {})
    zyl = r.get('zylann', {})
    if zyl.get('detect_us', 0) > 50000:  # >50ms detect → Zylann saturation
        print(f"Frame {r['frame']}: detect={zyl['detect_us']}us "
              f"dropped_loads={zyl['dropped_loads']} "
              f"proc={eng.get('proc_us', 0)}us "
              f"prims={eng.get('prims', 0)}")
```

## Common patterns and what they mean

### Pattern 1: wrapped GD scripts < 5% of frame budget

That's healthy. Don't bother optimizing them. Look at `engine.proc_us`
and `zylann.*` for the real cost.

### Pattern 2: `zylann.detect_us` > 50,000 µs (50ms+)

Zylann is saturated on the main thread. Either:
- Too many viewers (check `Player3D.PrefetchViewer` is collapsing
  to view_distance=0 when idle)
- Wiggle is too aggressive (see "Spawn wiggle" below)
- View distance set too high for hardware

`dropped_loads` simultaneously > 1000 confirms saturation. Cure:
slow down whatever is invalidating the chunk box.

### Pattern 3: `total_us` low but `engine.proc_us` high

Unwrapped GD code is eating frame time. Find the autoload missing a
profile wrapper (see CLAUDE.md "Per-autoload performance attribution").

### Pattern 4: Spike during chunk stream-in (`worst=80-145ms`)

Three contributors compound:
- Zylann main-thread detect (`zylann.detect_us` spike)
- GPU mesh upload (`engine.prims` jumps, `engine.draws` rises)
- Collision shape rebuild (PhysicsServer3D, not directly visible
  in our JSON but correlates with `engine.phys_us` rising)

Mitigations: `lod_fade_duration` (smooths upload — Zylann clamps
this in our build, see LESSONS_LEARNED), bigger `lod_distance` so
transitions are less frequent, Forward+ renderer (Vulkan staging
buffers can stream mesh data off the main thread).

### Pattern 5: `PHYS.Player3D_move_and_slide` spike correlated with jumps

Expected. Some jump frames cost 5-10ms in CharacterBody3D collision
work. Mitigations: tune `floor_snap_length`, simpler collision shape,
reduce nearby chunk count. Usually not worth fixing unless it's
visible as a stutter.

## Spawn-freeze + wiggle workflow

Reference for the World3D / CopperIslesTest spawn-fall-through bug.

### Symptom

Player spawns at scene's default Y (e.g. 120) above terrain. Loading
screen closes. Player falls forever (or until collision builds, which
may be too late).

### Root cause

Zylann's CLIPBOX (`streaming_system = 1`) only re-evaluates the chunk
set when the **viewer's transform changes**. A frozen viewer
(`_spawn_freeze = true` in Player3D) is perfectly stationary →
Zylann never builds the chunks under the player → no collision →
raycast misses → freeze times out → fall.

### Fix pattern (both bootstraps implement this)

1. **Pre-snap analytically:** call
   `generator.get_ground_voxel_y_at(world_x, world_z)` to find ground
   voxel-Y, convert via terrain scale, teleport player to ground+3m.
2. **Spawn-freeze:** set `Player3D._spawn_freeze = true` so gravity
   doesn't run during chunk streaming.
3. **Per-N-frame wiggle:** in the bootstrap's `_physics_process`,
   nudge `player.global_position.x` by ±1 mm every 6 frames (~10 Hz).
   Microscopic enough to be invisible; enough position-delta to
   keep Zylann's detect loop firing chunk requests.
4. **Raycast every frame:** check for collision below. On hit, snap
   to ground+1m and clear `_spawn_freeze`.
5. **Failsafe at 15 s:** clear `_spawn_freeze` anyway if raycast
   never hits. Pre-snap placed player at ground+3m so worst-case
   fall is small.

### Tunables — what fails

- **Wiggle every frame (60 Hz):** Zylann saturates. `detect_us`
  hits 200,000 µs. `dropped_block_loads` exceeds 15,000. No chunks
  ever finish. **Always use the per-N-frame gate.**
- **10 mm or larger amplitude:** invalidates chunk box more aggressively
  than Zylann can finish processing. Same saturation failure mode.
- **Multi-axis (X+Z) wiggle:** doubles the invalidation rate. Same
  saturation.

### Proven config (in `World3DBootstrap.gd` and `CopperIslesTestBootstrap.gd`)

```gdscript
const SPAWN_WIGGLE_MAX_S: float = 15.0
const SPAWN_WIGGLE_AMPLITUDE_M: float = 0.001      # 1 mm
const SPAWN_WIGGLE_FRAME_INTERVAL: int = 6         # every 6th frame
```

Single-axis X. Expected spawn time: 5-12 seconds.

## What's instrumented (current wrapped autoloads)

| Category | Systems |
|---|---|
| `WORLD` | `VoxelEditManager`, `VoxelGravityManager`, `WorldClock` |
| `WATER` | `WaterFlowManager`, `WaterChunkMesher` |
| `WEATHER` | `WeatherManager`, `DayNightCycle` |
| `PHYS` | `Player3D`, `Player3D_move_and_slide`, `Player3D_viewer_lookahead`, `Player3D_camera_smooth`, `PrefetchViewer` |

Wrapper pattern (see CLAUDE.md "Per-autoload performance attribution"):

```gdscript
func _process(delta: float) -> void:
    var _t0 := Time.get_ticks_usec()
    _process_inner(delta)
    var _elapsed: int = Time.get_ticks_usec() - _t0
    HUDOverlay.profile_record("AutoloadName", _elapsed)
    var prof := get_node_or_null("/root/Profiler")
    if prof != null:
        prof.record("CATEGORY", "AutoloadName", _elapsed)
```

Adding a new wrapper: pick a category from above (or extend the list
in this doc), wrap the body, both calls. The HUDOverlay call feeds
the always-on `[PERF]` log; the Profiler call feeds the F3 overlay
and JSON capture.

## How to ask a future Claude session for a fast diagnosis

Paste two things:

1. **The capture JSON path** (or contents if small enough) —
   typically `C:\Users\Matt Noles\AppData\Roaming\Godot\app_userdata\Game One\profile_capture_*.json`.
2. **The trailing 20-30 lines** of the Godot Output panel covering the
   `[PERF]` and `[DIAG]` lines from the same session.

Future Claude should:

1. Read the JSON directly via `Bash python -c` aggregation (the
   recipes above).
2. Look for the patterns in the "Common patterns" section.
3. Correlate JSON spikes with `[PERF] worst=` and `[DIAG]
   time_detect_required_blocks=` values from the same window.
4. Propose ONE specific change, not a menu of options.

## Open follow-ups (as of 2026-05-12)

- **Forward+/Vulkan renderer migration:** estimated 30-60% reduction
  in chunk-stream-in spikes. Single biggest renderer-side win.
  **DONE 2026-05-13 (PR #207).** Migration shipped; the apparent p99
  "regression" we initially saw was a `TIME_PROCESS` plateau artifact,
  fixed by adding `engine.real_us` to capture records.
- **WaterChunkMesher C++ port:** consistently appears in `[PERF]`
  top-3. Greedy run-merge is pure buffer iteration; clean port.
  **Partial 2026-05-13:** GD time-budget throttle replaces the
  count-based throttle (caps single-frame spike at ~3 ms vs 9.2 ms
  observed in baseline). Full C++ port still wanted — eliminates the
  per-chunk variance entirely. See `scripts/WaterChunkMesher.gd`
  constants `MESH_BUILD_FRAME_BUDGET_US` / `MESH_BUILD_MIN_BUDGET_US`.
- **Distant-Horizons-style baked far-LOD atlas:** decouple visual
  far-distance terrain from gameplay simulation chunks. Path to
  5km+ vistas without Zylann's main thread melting.
- **Zylann fork to thread `detect_required_blocks`:** 3-10× cut on
  that specific cost, 1-2 weeks initial work + ongoing rebase pain.
  Only if Tier 1/2 changes are exhausted.

See CLAUDE.md "Voxel loading / LOD performance paths" for the full
roadmap.

## Voxel-streaming perf — anti-patterns (DO NOT DO)

When `zylann.detect_us` spikes or `dropped_loads` explodes (see the
Copper Isles capture below for a textbook example), the temptation
is to shrink the streaming radius so Zylann has less work per scan.
**Resist this — every option in the family destroys core game pillars:**

- **`terrain.lod_count` reduction** — fewer LODs means terrain ends
  abruptly at the streaming boundary. The world looks small. Mira's
  trilogy-scale open-world brief requires distant landmark visibility;
  cutting LODs sacrifices that.
- **`terrain.view_distance` reduction** — same problem at the visual
  layer. Distant peaks pop in late. The horizon-vista photography
  Copper Isles is designed around (5 km × 5 km archipelago, named
  islands visible from each other) breaks.
- **`terrain.mesh_block_size` increase** — fewer, larger chunks means
  longer mesh-build times per chunk AND coarser collision granularity.
  Trades a CPU spike pattern for a different CPU spike pattern AND
  loses geometric detail.

**`terrain.collision_lod_count` is already `0`** (LOD0-only collision)
in `World3DBootstrap.gd:868` and `CopperIslesTestBootstrap.gd:857`.
Cannot be tightened further. The Player3D physics-tick spike during
chunk streaming is the unavoidable cost of integrating new LOD0
collision shapes — fundamental to a streaming voxel game.

**Acceptable directions when chunk-streaming hurts:**

1. **Reduce per-chunk GPU prim count** (HorizonSkirt density, atlas
   tile-size tweaks) — same view distance, less work per frame.
2. **Cap player run/sprint speed in oversized worlds** (Copper Isles
   specifically) — the streamer can keep up at walking speeds.
3. **Defer collision shape generation** (would require Zylann fork
   or careful scene-tree hack — out of scope until streaming is the
   actual gating factor, not a transient spike).
4. **Pre-cache the LOD0 set around known spawn / hub locations** at
   game-load time so the player never crosses unstreamed terrain.
5. **Threadpool tuning** (`threads/count/minimum` in project.godot)
   if the bottleneck is Zylann's worker-thread starvation rather
   than main-thread `detect`.

See "Voxel loading / LOD performance paths" in CLAUDE.md.

## 2026-05-13 baseline capture — findings & follow-ups

First clean capture using the new `engine.real_us` measurement (PR
#207 fixed `TIME_PROCESS`'s frame-plateau bug). 60 s World3D walk,
Forward+ + shadow_q=2 on AMD RX 7800 XT, 22 789 frames.

**Real frame-time distribution** (the now-trustworthy number):

| metric | value |
|---|---:|
| median | 2.20 ms (≈ 455 fps) |
| p95 | 6.11 ms |
| p99 | 12.25 ms |
| p99.9 | 21.30 ms |
| max | 37.86 ms |
| frames > 16 ms / min | 68 (0.34 %) |
| frames > 33 ms / min | 2 (0.01 %) |
| frames > 100 ms / min | 0 |

**Top per-category CPU (wrapped GD only — about ~20 % of total CPU):**

| category | total over 60 s | max single frame | frames > 1 ms |
|---|---:|---:|---:|
| PHYS | 7.22 s (84.4 %) | 9.3 ms | 2287 |
| WEATHER | 846 ms (9.9 %) | 0.56 ms | 0 |
| WATER | 412 ms (4.8 %) | 9.2 ms | 142 |
| WORLD | 75 ms (0.9 %) | 0.08 ms | 0 |

### Item B — WeatherManager + DayNightCycle 10 Hz state gates

**Landed 2026-05-13.** Both autoloads ran their full body every render
frame (22 µs + 13 µs avg, 100 % hit rate). Sun moves at 0.0625°/real-s
under WorldClock's 240-real-s/game-hour rate; weather transitions span
30 s. 100 ms tick granularity is invisible at these timescales.

Implementation: accumulate delta, only call `_process_inner()` /
`_apply()` when accumulator ≥ `STATE_TICK_INTERVAL_S` (0.1 s). Delta
passed through so timer-based logic (lightning, wind resample,
story override countdown) stays frame-rate-independent.

Expected: WeatherManager 9.2 ms/sec → ~0.24 ms/sec (97 %),
DayNightCycle 4.9 ms/sec → ~0.13 ms/sec (97 %). Combined: ~13.7 ms/sec
of free CPU = 1.3 % wall-clock headroom.

### Item C — Player3D 6.5 ms physics tick at f12682

**Diagnosed, not yet fixed.** The worst single physics tick (3298 µs
Player3D + 3221 µs move_and_slide) is NOT a CharacterBody3D bug. It's
clustered between two chunk-streaming events:

```
f12680: zylann.detect_us=6299µs + io_us=1213µs  ← chunk-stream begins
f12682: PHYS.Player3D=3298µs + move_and_slide=3221µs ← physics integrates new collision shapes
f12683: zylann.detect_us=17390µs (worker thread, not main)
```

Zylann generates per-block StaticBody3D collision shapes when chunks
load. Adding many new collision shapes in one physics tick spikes
move_and_slide because the physics step has to integrate them all.

**Real fix would be on the chunk-streaming side**: stagger collision-
shape add operations across frames, OR reduce `terrain.collision_lod_count`
(currently 0 = all LODs get collision), OR defer collision generation
for distant LODs. Not a Player3D bug — out of scope until the chunk-
streaming path is touched anyway.

### Item A — WaterChunkMesher time-budget throttle

**Landed 2026-05-13.** Direct fix for the 9.2 ms single-frame spike
visible in the baseline. The old count-based throttle (`MESH_BUILDS_PER_FRAME_MAX = 6`)
allowed 6 × ~1.5 ms chunks to pile up in one render frame.

New approach: TIME-based throttle. Build chunks one at a time, measure
elapsed µs after each, stop when the per-frame budget is spent. Always
allow at least one chunk per frame so forward progress is guaranteed.

Constants in `scripts/WaterChunkMesher.gd`:
- `MESH_BUILD_FRAME_BUDGET_US = 3000` (3 ms / frame in fast mode)
- `MESH_BUILD_MIN_BUDGET_US = 500` (0.5 ms / frame under load)
- Lerp between by frame-delta as before.

Expected: caps WaterChunkMesher contribution at ~3-4 ms/frame even
on burst frames (vs 9.2 ms observed). Avg cost basically unchanged
because non-burst frames stay at 2 µs. The 142-frames-over-1ms count
should drop to roughly half.

Full C++ port is still the canonical long-term fix — moves the
per-chunk scan + ArrayMesh construction off the main thread entirely,
not just caps the spike. See the C++ perf opportunities section in
CLAUDE.md.
