# TerrainDiffusion Phase 4 — GPU Scheduling & Perf (design)

**Status:** DESIGN ONLY (2026-06-28). No code written. Implements Phase 4 of
`TERRAIN_DIFFUSION_RUNTIME_PLAN.md` ("Perf / scheduling"). Read that master plan first;
this doc is the concrete build sheet for that one paragraph.

> Plain-English: the AI terrain model is *heavy* — one region needs ~23 neural-net calls
> and the big "base" net alone is ~1.9 GB of weights sitting in video memory. The same
> graphics card is also drawing the world (Lumen lighting, Nanite geometry) and running
> physics (Chaos). Phase 4 is about running the AI **off to the side** so it never makes
> the game stutter: generate terrain *ahead* of where the player is walking, cap how much
> AI work is "in flight" at once, keep video memory from overflowing, and measure all of
> it so we can prove it's smooth.

---

## 0. The load-bearing fact this whole phase rests on

**ORT-DML runs inference on its OWN D3D12 queue — NOT inside Unreal's RHI/RDG frame graph.**

- In the Gate-1 op-coverage commandlet, **`NNERuntimeRDG` (RHI D3D12) = "no"** for our op set,
  but **`NNERuntimeORTDml` (DirectML's own D3D12 device/queue) = "yes."** That is *why* ORT-DML
  is the primary path (master plan §"Hardware / runtime").
- Consequence: inference is **not** frame-aligned and does **not** block `FRHICommandList` /
  `RenderGraph`. It contends with Lumen/Nanite only at the **hardware** level (GPU compute units,
  memory bandwidth, VRAM), not at the **software** level (no RDG pass ordering, no game-thread or
  render-thread stall *unless we block on the result*).
- **Therefore our job is hardware-contention management, not frame-graph integration.** We never
  `RunSync` on the game thread (today's `FNNEUNetRunner` note at `NNEUNetRunner.h:60` says RunSync
  is fine "for Gate 1" only). Phase 4 moves every Run onto a background task and only ever touches
  UObject/voxel state when harvesting a *finished* result on the game thread.
- This also means **`stat GPU` will show the inference cost folded into total GPU time** but NOT
  attributed to a named RDG pass. We must measure inference latency ourselves (CPU-side wall clock
  around the async Run), because the frame profiler can't see inside DML's queue. (See §6.)

If a future build flips the cheap nets to `NNERuntimeRDG` (master plan Phase 6), revisit this — RDG
*would* be frame-aligned and would need RDG budgeting instead. Out of scope here.

---

## 1. Architecture: where Phase 4 sits

```
 Player moves ─▶ Prefetch Ring (predicts regions ahead, by travel dir)
                      │  enqueue region requests (deduped, priority-sorted)
                      ▼
              FDiffusionDemService  ◀── In-flight inference BUDGET (cap concurrent Runs)
                 │  (request queue + region cache, system RAM)
                 │  async task ─▶ FNNEUNetRunner.Run (coarse×20, base×2, decoder×1)
                 │                      │  ORT-DML, own D3D12 queue, OFF render path
                 ▼                      ▼
        ImageHeightmap (region)   VRAM budget + eviction (base_model ~1.9 GB resident)
                 │
                 ▼
   DiffusionHeightSource ─▶ compute_ground_y seam (HeightmapGenerator.cpp:377)
                 │
                 ▼
   EnqueueColumnGen / HarvestColumnGen  (existing async column pipeline, VoxelWorld.cpp:497/529)
```

**Key seam already in place** (from Phase 1/2 — verified in code, not aspirational):
- `FDiffusionDemService::TryGetRegionHeightmap(...)` (`DiffusionDemService.h:94`) is the boundary a
  request queue sits behind. The header *explicitly* anticipates this: "the service's
  TryGetRegionHeightmap is the boundary that a future async wrapper (request queue + resident-check)
  will sit behind" (`DiffusionDemService.h:62-66`).
- The coarse-DEM provider is injectable (`FCoarseDemProvider`, `DiffusionDemService.h:66`); the real
  GPU path "simply becomes a different provider (run on a background task)" — no change to the
  service's consumers.
- The column pipeline already has the throttle pattern we mirror: `MaxColumnJobsInFlight = 48`
  (`VoxelWorld.h:344`), checked in `EnqueueColumnGen` at `VoxelWorld.cpp:503` and the mesh harvest
  at `VoxelWorld.cpp:962`. Phase 4's inference budget is the *same idea* one level up.

---

## 2. Knob: Prefetch ring ahead of the player

**Goal:** the region the player is about to enter is already resolved (in the system-RAM cache)
before any column there asks for its height. One region covers a large area (region span ≫ stream
radius), so we typically only need 1–2 resident + 1–2 prefetching.

### Design
- A **ring** of region requests centered on the player's predicted position, biased forward along
  travel direction. Because regions are large, the "ring" is really "current + the few neighbours
  the player is heading toward."
- **Travel-direction bias:** sample player velocity (EMA-smoothed over `PrefetchVelWindowSec`); the
  forward neighbour region gets the highest prefetch priority, the two flanking neighbours next, the
  region behind lowest (or skipped).
- Prefetch requests are **low priority**: they must never starve a *needed-now* region (one the
  player has already entered with no resident tile). Needed-now jumps the queue.
- Dedupe against the cache (`FRegionKey`, `DiffusionDemService.h:129`) and against in-flight requests
  so we never enqueue the same region twice.

### Knobs + defaults
| Knob | Default | Meaning |
|---|---|---|
| `PrefetchRingRadiusRegions` | `1` | How many region rings ahead to keep resident (1 = current + immediate neighbours). Regions are large; 1 is usually enough. |
| `PrefetchForwardBias` | `2` | Forward neighbour gets this × priority weight vs lateral. |
| `PrefetchVelWindowSec` | `1.5` | EMA window for smoothing travel direction (avoids thrash when the player jiggles). |
| `PrefetchMinSpeedMps` | `1.0` | Below this speed, prefetch the full ring (no direction) — player is browsing, could go anywhere. |
| `bPrefetchEnabled` | `true` | Master switch. |
| `PrefetchMaxQueued` | `4` | Cap on queued (not yet running) prefetch requests. |

### Implementation note
Player focus already exists for column streaming: `GetFocusChunkXZ` (used in `HarvestColumnGen`
nearest-first sort, `VoxelWorld.cpp:~540`). Reuse it for the ring center. Convert focus chunk → region
rect with the same georef math `SnapshotGenParams` uses (`VoxelGenParams.h:206`).

---

## 3. Knob: In-flight inference budget

**Goal:** bound concurrent GPU inference so we never pile multiple ~1.9 GB base-model passes onto the
card at once (VRAM blowout) and never saturate compute so hard that Lumen/Nanite hitch.

### Design — mirror `MaxColumnJobsInFlight`
- `MaxRegionInferencesInFlight` caps how many region inferences run concurrently. **Default `1`.**
  Rationale: base_model is 1.9 GB; two concurrent base passes risk VRAM eviction churn against Lumen.
  Start serial, raise only if profiling shows headroom.
- A region inference is internally ~23 net calls (20 coarse + 2 base + 1 decoder; master plan + the
  `mira::tdiff::WorldPipeline` spine). Those run **sequentially within one region task** (they're data-
  dependent anyway: coarse→base→decoder). So the budget is *per region*, not per net call.
- Enqueue check, mirroring `VoxelWorld.cpp:503`:
  `if (InFlightRegionInferences >= MaxRegionInferencesInFlight) { defer; }`
- **Defer-and-retry**, not block. A deferred prefetch just waits a tick; a needed-now region falls
  back to the analytic stub provider (`MakeAnalyticStubProvider`, `DiffusionDemService.h:105`) for an
  immediate placeholder, then upgrades the tile when the real inference lands and re-meshes (bump
  `GenEpoch` for affected columns — the epoch mechanism already exists in `EnqueueColumnGen`).

### Knobs + defaults
| Knob | Default | Meaning |
|---|---|---|
| `MaxRegionInferencesInFlight` | `1` | Concurrent region inferences. The main GPU-contention lever. |
| `bStubWhileInferring` | `true` | Show analytic-stub terrain immediately, upgrade when real tile arrives. |
| `InferenceTaskPriority` | `BackgroundLow` | `Async()` execution priority — below column gen so streaming wins ties. |
| `MaxNetCallsPerRegionTask` | `23` | Sanity cap / assert; flags pipeline drift. |
| `InferenceRetryTicks` | `1` | Ticks to wait before re-checking a deferred request. |

---

## 4. VRAM budget model + eviction

**Card:** RX 7800 XT, **16 GB**. Shared by Lumen + Nanite + Chaos + our voxel meshes + ORT-DML.

### Budget (worst-case, fp32; halve weight figures if fp16 locked in op audit)
| Consumer | Est. VRAM | Notes |
|---|---|---|
| base_model weights (resident) | ~1.9 GB | The heavy one; keep resident while exploring. |
| coarse_model weights | ~22 MB | Tiny; keep resident. |
| decoder_model weights | ~224 MB | Keep resident. |
| Inference working tensors (peak, base pass) | ~0.5–1.5 GB | Activations/scratch; freed between passes. Measure (§6) — this is the uncertain term. |
| **AI subtotal (resident + 1 in-flight)** | **~2.7–3.7 GB** | At `MaxRegionInferencesInFlight=1`. |
| Lumen (surface cache, screen probes, radiance) | ~2–4 GB | Scene-dependent. |
| Nanite (cluster/page pool, streaming) | ~1–3 GB | `r.Nanite.Streaming.PoolSize` driven. |
| Voxel render meshes + textures + Chaos + RT | remainder | |

**Target ceiling for the AI subsystem: `InferenceVramBudgetMB = 4096` (4 GB).** This leaves ≥12 GB
for the renderer on a 16 GB card. If measured AI usage approaches the ceiling, eviction kicks in.

### Eviction strategy
1. **Weights stay resident by default** (load once, reuse across regions — `FNNEUNetRunner` already
   caches loaded models in `Loaded[3]`, `NNEUNetRunner.h:114`). Reloading 1.9 GB per region would be
   catastrophic; don't.
2. **Working tensors are transient** — released as each net pass completes (per region task). This is
   the main reclaim lever; serial inference (`MaxRegionInferencesInFlight=1`) keeps the transient peak
   to one pass.
3. **Optional base-model eviction under pressure:** if `InferenceVramBudgetMB` would be exceeded *and*
   no inference is in flight *and* no prefetch is queued, free the base model instance and reload on
   next demand. Gated behind `bEvictBaseModelWhenIdle = false` by default (reload cost is high; only
   enable if Lumen/Nanite are demonstrably starved). Coarse + decoder are small — never evict.
4. **Region tile cache (the OUTPUT) lives in SYSTEM RAM, not VRAM** — see §5. Evicting a tile costs
   nothing on the GPU.

### Knobs + defaults
| Knob | Default | Meaning |
|---|---|---|
| `InferenceVramBudgetMB` | `4096` | Soft ceiling for AI VRAM (weights + working set). |
| `bKeepBaseModelResident` | `true` | Don't unload the 1.9 GB net between regions. |
| `bEvictBaseModelWhenIdle` | `false` | Emergency reclaim; only if renderer starved. |
| `bLockAutoExposureDuringBake` | `true` | (Carry-over gotcha) lock auto-exposure so VRAM/perf reads aren't polluted by exposure churn. |

> How to read actual VRAM: there is no portable per-process VRAM query in-engine. Use
> `RHIGetTextureMemoryStats` for engine allocations, `stat RHI`, and on AMD read driver/Adapter
> budget via `IDXGIAdapter3::QueryVideoMemoryInfo` (DML uses the same adapter). Log the delta around
> model load + around a region inference to attribute the AI share. (See §6.)

---

## 5. Elevation tile cache stays in system RAM

Already true in Phase 1 and we keep it: `FDiffusionDemService` caches `ImageHeightmap` surfaces in a
`TMap<FRegionKey, TSharedPtr<mira::ImageHeightmap>>` (`DiffusionDemService.h:157`) — plain system-RAM
float grids, `TSharedPtr` so cache hits copy a pointer not the grid (`:155-156`).

- A region `ImageHeightmap` is small: at 30 m/px, even a multi-km region is a few-hundred-px grid
  (a 64×64 coarse golden is the reference shape, `DiffusionDemService.h:107-113`). Tens of KB to a
  few MB each. **Hundreds of regions fit in system RAM trivially.**
- **Cache policy:** add a simple LRU bound `DemCacheMaxRegions = 16` (Phase 1 has *no* eviction —
  `ClearCache` only, `:97`). With regions this large, 16 resident covers a huge play area.
- The **detail bridge** (`Core/Tdiff/DetailBridge.h` :: `sample_height_voxels`) upsamples 30 m→10 cm
  on the CPU per column at gen time — it does NOT store 10 cm grids. So the cache footprint is the
  *coarse* surface only. This is the seam noted at `DiffusionDemService.h:119-124`.

### Knobs + defaults
| Knob | Default | Meaning |
|---|---|---|
| `DemCacheMaxRegions` | `16` | LRU bound on resident region surfaces (system RAM). |
| `bDemCachePinCurrent` | `true` | Never evict the region the player is standing in. |

---

## 6. Measurement plan

### 6a. Extend the perf CSV
The writer is `AVoxelWorld::WritePerfCsvRow()` (`VoxelWorld.cpp:3654`), header string at
`VoxelWorld.cpp:3661-3668`, gated by `bWritePerfCsv` → `Saved/MiraThalPerf.csv`. Append these columns
to the header and the row (keep them at the END so existing CSV parsers/baselines don't shift):

| New column | Source | Meaning |
|---|---|---|
| `inferRegionsResident` | `DemService.NumCachedRegions()` (`:98`) | Region surfaces in RAM cache. |
| `inferInFlight` | new counter on the service | Concurrent region inferences (vs `MaxRegionInferencesInFlight`). |
| `inferQueued` | request-queue length | Prefetch + needed-now waiting. |
| `inferLastMs` | wall clock around last completed region Run | End-to-end region latency. |
| `inferBaseMs` | wall clock around the 2 base passes | Isolates the heavy net (the suspect). |
| `inferP95Ms` | rolling P95 over last N regions | Tail latency = what causes visible pop-in. |
| `inferStubUpgrades` | count of stub→real tile swaps this interval | How often the player saw placeholder terrain. |
| `inferVramMB` | DXGI adapter budget delta (AMD) | AI VRAM share. |
| `inferVramBudgetMB` | knob echo | For correlating evictions. |
| `inferEvictions` | base-model/idle evictions this interval | Should be ~0 in healthy runs. |

Pattern: mirror how `Far.*` stats are gathered into the row at `VoxelWorld.cpp:3704-3730`. Add a
`FInferPerfStats` struct the service fills, read it in `WritePerfCsvRow`.

### 6b. In-engine / live
- `stat GPU` — total GPU frame time; watch for inference bursts correlating with frame-time spikes.
  Remember: DML work shows in the **total** but NOT as a named pass (§0).
- `stat RHI`, `RHIGetTextureMemoryStats`, AMD `QueryVideoMemoryInfo` — VRAM headroom vs the 4 GB
  AI budget.
- `stat Unreal` / `t.MaxFPS 0` — confirm game-thread/render-thread stay flat *during* a region
  inference (proves §0: inference is off the render-critical path).
- Console hooks via `UTdiffWorldHook` (`TdiffWorldHook.h`, Blueprint/console bridge) — add cvars to
  trigger a region inference on demand and dump `inferLastMs`/`inferBaseMs` for A/B testing knobs.

### 6c. Headless
- Extend the Gate-1 commandlet (`TdiffGate1Commandlet`) into a **latency harness**: time `base_model`
  in isolation and a full 23-call region on the real GPU; write to a CSV the designer can diff across
  model variants (fp32 vs fp16 vs quantized). This is the data that decides §7 mitigations.

### 6d. Pass/fail gate for Phase 4
- No game-thread or render-thread hitch attributable to inference (frame-time flat in 6b).
- `inferP95Ms` < region-traversal time at walk speed (player never out-runs the prefetch ring), OR
  `inferStubUpgrades` shows graceful stub coverage when they do.
- AI VRAM stays under `InferenceVramBudgetMB`; `inferEvictions` ≈ 0 during normal exploration.

---

## 7. RISK: base_model latency may be too high for live streaming

This is the headline risk (master plan top-risk #3). base_model is ~1.9 GB and runs 2× per region;
on DML/RDNA3 a single region (~23 calls) could plausibly be **hundreds of ms to several seconds**. If
so, live per-region streaming as the player walks is not viable as-is. Mitigations, cheapest first:

1. **Coarser request cadence (FREE — leans on geometry).** One region covers a *large* area, so we
   request new regions rarely. Combined with the prefetch ring (§2), the player rarely waits. Often
   sufficient on its own. Measure first (§6) before doing anything heavier.
2. **Pre-generate the starting ring at new-game.** At seed/region selection (a natural loading
   moment), synchronously bake the player's start region + immediate neighbours into the cache before
   gameplay begins. Hides the worst first-region latency entirely. Cheap; do this regardless.
3. **Async over many frames.** Already the design (§3): inference on a background task, stub terrain
   meanwhile (`bStubWhileInferring`), upgrade on completion. The 23 calls are sequential but each
   returns to the task between passes — never one long GPU stall we wait on.
4. **Downsized / quantized base model.** If 1–3 aren't enough: export a smaller base UNet or quantize
   weights (fp16, or int8 where DML supports it) — cuts both VRAM (§4) and latency. Requires a new
   golden capture + re-running Gates 1–3 parity, and a **model-version bump** (see Phase 5 doc — this
   invalidates stale bakes via the fingerprint). Biggest win, biggest cost.
5. **Reduce coarse iteration count.** 20 coarse passes dominate call count; if the EDM/DPM scheduler
   (`Core/Tdiff/EdmDpmScheduler.h`) tolerates fewer steps with acceptable quality, that's a direct
   latency cut. Validate visually + against golden tolerance.

**Decision rule:** ship with 1+2+3 (all cheap, all in our control). Pursue 4/5 only if §6 data shows
P95 region latency exceeds traversal time *with* the prefetch ring active.

---

## 8. Ordered implementation checklist

1. **Async-ify the runner path.** Move `FNNEUNetRunner.Run` off the game thread: region inference runs
   via `Async(EAsyncExecution::ThreadPool, ...)` at `InferenceTaskPriority`, result harvested on the
   game thread (mirror `EnqueueColumnGen`/`HarvestColumnGen`, `VoxelWorld.cpp:497/529`). Never RunSync
   on the game thread (supersedes the Gate-1 note at `NNEUNetRunner.h:60`).
2. **Add the request queue + in-flight budget** behind `TryGetRegionHeightmap`
   (`DiffusionDemService.h:94`): dedupe by `FRegionKey`, cap by `MaxRegionInferencesInFlight`,
   defer-and-retry, needed-now priority, optional stub fallback.
3. **Add the prefetch ring** (§2): reuse `GetFocusChunkXZ` for center, velocity EMA for direction,
   enqueue low-priority region requests.
4. **Add the VRAM budget + eviction** (§4): keep weights resident, free working tensors per pass,
   optional idle base-model evict; wire `IDXGIAdapter3::QueryVideoMemoryInfo` read.
5. **Bound the RAM tile cache** (§5): LRU at `DemCacheMaxRegions`, pin current region.
6. **Extend the perf CSV** (§6a): `FInferPerfStats` struct + 10 new columns appended in
   `WritePerfCsvRow` (`VoxelWorld.cpp:3654`).
7. **Add console cvars** via `UTdiffWorldHook` to trigger inference + dump latency for tuning.
8. **Build the latency harness** in `TdiffGate1Commandlet` (§6c) and capture baseline numbers.
9. **Tune defaults** from the captured data; decide §7 mitigations from real latency.

## 9. Verification plan
- Headless: latency harness CSV shows base_model and full-region timings on the RX 7800 XT; assert
  parity unaffected (still matches golden within tolerance) — reuse Gate-1/Gate-3 oracles.
- PIE (mcp-unreal bridge): walk a long traverse with `bWritePerfCsv=true`; confirm `stat GPU` frame
  time is flat through region inferences (no render-path hitch — proves §0), `inferP95Ms` under
  traversal time, AI VRAM under budget, `inferEvictions≈0`.
- A/B: toggle `bPrefetchEnabled` and vary `MaxRegionInferencesInFlight`; confirm prefetch removes
  pop-in and the budget bounds VRAM without starving the renderer.
- Designer drives PIE; CLAUDE reads `Saved/MiraThalPerf.csv` to diagnose (per the headless-workflow
  and perf-CSV memory entries) — designer never opens the CSV.
