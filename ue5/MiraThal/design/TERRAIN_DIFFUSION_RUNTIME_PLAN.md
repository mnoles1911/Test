# TerrainDiffusion — Live Runtime Procedural Terrain (design + phase plan)

**Status:** APPROVED, in development (started 2026-06-28). Engine-side master plan lives here; the working
plan file is `C:\Users\Matt Noles\.claude\plans\partitioned-gliding-mitten.md`. Companion memory:
`project_terrain_diffusion`, `project-ue5-nanite-bake-plan`.

> Plain-English: we are teaching the game to *imagine* terrain with an AI model instead of reading it from
> a pre-made image or hand-tuned noise. The player picks a **seed + region** at new-game; the game runs the
> **TerrainDiffusion** ("InfiniteDiffusion") model **on the local GPU** to produce realistic elevation
> heightmaps live as they explore — infinite, deterministic, Minecraft-style — while we keep our 10 cm
> cubic-voxel look. The AI provides the *macro* landforms (mountains, rivers, coasts); our own
> noise/erosion fills in everything finer than 30 m.

## Why this approach (the two load-bearing facts)

1. **The integration seam already exists.** Every voxel column's height flows through ONE chokepoint —
   `mira::HeightmapGenerator::compute_ground_y(wx,wz)` (`Core/HeightmapGenerator.cpp:377`) — which already
   branches to a swappable **height source** (today: imported Gaea EXR via `mira::ImageHeightmap`). The AI
   becomes a *new height source*. `resolve_column`/`material_at` (cliffs, water, material banding) ride on
   top of whatever height we return, unchanged. The SAME path feeds runtime streaming AND the Nanite bake
   (`VoxelCrustBaker.cpp:202`), so the AI feeds both for free.
2. **The hard part is the model's Python "glue," not the engine wiring.** The model repo
   (github.com/xandergos/terrain-diffusion) `onnx/export.py` exports only the **3 UNets** (coarse, latent,
   consistency-decoder). The orchestration (`world_pipeline.py::WorldPipeline.get`), the seeded RNG
   (`portable_rng.py`, numba), and the seam blending (`linear_weight_window`) are NOT exported and must be
   **reimplemented in deterministic C++17**.

## Hardware / runtime (verified 2026-06-28, Day-0 gate PASSED)

- Dev/player GPU: AMD Radeon RX 7800 XT (RDNA3, 16 GB), Windows, **no CUDA**.
- Engine build `D:/UE5/UE_5.7` ships: `NNE`, **`NNERuntimeORT`** (ONNX Runtime v1.20 + **DirectML** —
  confirmed `onnxruntime.dll` + `Engine/Binaries/Win64/DML/x64/DirectML.dll`), and `NNERuntimeRDG`.
- **Primary inference path = NNERuntimeORT + DirectML EP** (broad ONNX op coverage, runs on AMD via DX12).
  `NNERuntimeRDG` (frame-aligned, vendor-agnostic, *limited op set*) is a later optimization, not Phase 1.
- Finest model output = **30 m/px** (no finer without retraining). 30 m ÷ 0.1 m = **1 px = 300 voxels** →
  AI = macro shape only; **we synthesize sub-30 m detail** (noise + erosion).

## Architecture (target)

- **New module `MiraThalTerrainAI`** (Runtime, LoadingPhase `Default`; template = `MiraThalVoxelBake`).
  Deps: Public `Core, CoreUObject, Engine, MiraThalVoxel`; Private `NNE, RenderCore, RHI, Renderer, Projects`.
  `MiraThalVoxel` (PreDefault root) does NOT depend on it — the AI module *registers* a height-source
  provider `AVoxelWorld` consults (no circular dep). `.uproject` enables `NNE`, `NNERuntimeORT`, `NNERuntimeRDG`.
- **Pure orchestration `mira::tdiff`** (C++17 under `Core/`, headlessly testable). NNE calls injected via
  `struct ITdiffUNetRunner { RunCoarse/RunLatent/RunConsistencyDecoder(in,out); }` so tests run GPU-free.
- **`FDiffusionDemService`** (subsystem): owns the 3 `UNNEModelData` + ORT-DML instances (the real runner),
  a region tile cache (30 m/px elevation, system RAM), an async request queue. Inference never runs on a
  column worker and never blocks the game thread.
- **`mira::DiffusionHeightSource`**: implements the height-source interface, samples the tile cache,
  applies the 30 m→10 cm detail bridge, returns a voxel height.

## Phases

### Phase 1 — in-engine GPU inference + runtime-DEM (bounded region)  ← CURRENT
Scope cuts: one fixed bounded region (no streaming); fill an `ImageHeightmap` with the AI DEM (no core
interface refactor); macro upsample + simple noise detail (no erosion); ORT-DML on a background task;
single-player determinism only. Ordered with de-risk gates:

0. **Day-0 check — DONE ✅** NNE + NNERuntimeORT(+DirectML) + NNERuntimeRDG present in the engine build.
1. **Module scaffold** — `MiraThalTerrainAI` (Build.cs + IMPLEMENT_MODULE + `.uproject` descriptor + plugin
   enables). Compiles, loads, no behavior.
2. **Model prep (offline)** — run `onnx/export.py` → 3 `.onnx`; import as `UNNEModelData`; pin opset + fixed
   tile shapes; capture **golden input/output tensors** from Python (the parity oracle).
3. **Op-coverage audit** — create each model on `NNERuntimeORTDml`; log unsupported ops; lock fp32 vs fp16.
4. **GATE 1 (spike)** — one UNet runs in-engine on the RX 7800 XT via ORT-DML and matches the Python golden
   (max-abs-err < tol). Proves the AI runs on this GPU inside UE. Do not proceed until green.
5. **GATE 2 (RNG port)** — `portable_rng.py` → bit-exact C++; headless test == captured Python stream (≥3 seeds).
6. **GATE 3 (orchestration port)** — reimplement `WorldPipeline.get` (coarse→latent→decoder loop + blending)
   in `mira::tdiff`; headless **playback-runner** parity test == Python within tol.
7. **Wire it** — real runner + `FDiffusionDemService` → one elevation tile → 30 m→10 cm bridge (bicubic
   upsample + slope/altitude noise via `Core/Noise.h`) → fill `ImageHeightmap` → set via `SnapshotGenParams`/
   `BuildGen` (add `EVoxelHeightSource::DiffusionAI`) → existing voxel gen renders under Lumen.

**Success:** Gates 1-3 green; in PIE the bounded region matches a Python-rendered preview of the same
seed/region, voxels blocky/correct, cliffs/water/banding present, no game-thread hitch.
**Verify:** headless clang harness (`tests/standalone/`, add `test_tdiff_rng.cpp`, `test_tdiff_pipeline.cpp`)
for Gates 2-3; PIE via the mcp-unreal bridge for Gate 1 + end-to-end.

### Phase 2 — Streaming / infinite
Extract a tiny `IHeightSource` base (make `ImageHeightmap` implement it; `height_src_` → `const IHeightSource*`);
`DiffusionHeightSource` samples the tile cache; `FDiffusionDemService` gains request-queue + resident-check
+ defer-and-retry integrated with `EnqueueColumnGen`/`HarvestColumnGen` back-pressure; verify seamless
cross-region blending (no seams).

### Phase 3 — Detail synthesis maturity
Designer-facing slope/altitude noise knobs; optional hydraulic/thermal **erosion** as a region post-process
(possibly a `/MiraVoxel` `.usf` compute pass in `MiraThalVoxelRender`).

### Phase 4 — Perf / scheduling
Prefetch ring ahead of player; in-flight budget; VRAM ceiling (~2 GB model) + eviction; hide latency behind
travel; validate vs Lumen/Nanite with `stat GPU`.

### Phase 5 — Determinism & saves / multiplayer parity
int16-metre quantization + **server-authoritative DEM replication** (GPU floats differ across vendors —
don't rely on per-client inference parity); extend `FingerprintGenParams` (seed/region/model-version); disk
tile cache keyed by fingerprint; saves store seed+region+model-version only.

### Phase 6 — Optional RDG inference path
Evaluate `NNERuntimeRDG` op coverage; port cheapest net or the detail/erosion compute for frame-aligned
co-scheduling — only if ORT-DML contention proves a real shipping problem.

### Phase 7 — Shipping / licensing
Cook/package with NNE; **confirm the model-weights license permits commercial redistribution** (fallback =
retrain our own weights); cross-vendor validation (NVIDIA / Intel).

## Top risks → mitigations
1. ONNX op coverage on DirectML/AMD → op audit + Gate-1 spike first; ORT-DML default; fixed shapes/opset.
2. **Orchestration-port correctness vs Python (top effort risk)** → bit-exact RNG test + playback-runner
   parity test, both headless, both before GPU end-to-end; inject `ITdiffUNetRunner`.
3. Per-region inference latency vs streaming → decouple inference from column gen; resident-check +
   defer-and-retry (reuse `MaxColumnJobsInFlight`); prefetch; never infer on a column worker.
4. VRAM contention with Lumen/Nanite → hard VRAM ceiling + evict between bursts; tile cache in system RAM.
5. 30 m→10 cm softness (300 voxels/px) → bicubic macro upsample + slope/altitude fractal detail + erosion.
6. GPU fp non-determinism breaks MP parity → server-authoritative DEM + int16 quantization; CPU/integer detail.
7. Weights license for commercial ship → confirm in Phase 1 (cheap, blocking-if-bad).

## Critical files (engine side)
- `Source/MiraThalVoxel/Public/Core/HeightmapGenerator.h` + `Private/Core/HeightmapGenerator.cpp` — the
  `set_height_source` / `compute_ground_y` seam (~lines 217 / 377).
- `Source/MiraThalVoxel/Public/Core/ImageHeightmap.h` — height-source shape (P1 fill; P2 base for `IHeightSource`).
- `Source/MiraThalVoxel/Public/VoxelGenParams.h` — `FGenParams`/`BuildGen`/`SnapshotGenParams`/`FingerprintGenParams`.
- `Source/MiraThalVoxel/Private/VoxelWorld.cpp` — `EnqueueColumnGen`/`HarvestColumnGen` (~460-519, async model).
- `Source/MiraThalVoxelBake/…Build.cs`, `Source/MiraThalVoxelRender/…Build.cs`, `MiraThal.uproject` — module + plugin templates.
- NEW: `Source/MiraThalTerrainAI/`, `Core/Tdiff/` (pure C++17 orchestration + RNG), `tests/standalone/test_tdiff_*.cpp`.
