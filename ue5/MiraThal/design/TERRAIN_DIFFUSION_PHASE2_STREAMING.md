# TerrainDiffusion — Phase 2: Streaming / Infinite (design + interface scaffold)

**Status:** DESIGN + SCAFFOLD ONLY (authored 2026-06-28). No shared engine files are modified by this
document. The only new file shipped alongside it is the interface header
`Source/MiraThalVoxel/Public/Core/IHeightSource.h`. Everything below is the plan others implement against,
with exact file:line targets and an ordered checklist. Companion: `TERRAIN_DIFFUSION_RUNTIME_PLAN.md`
(Phase 2 section, lines 79-83), memory `project_terrain_diffusion`.

> Plain-English: Phase 1 makes the AI paint ONE bounded patch of ground into a single image
> (`ImageHeightmap`) and hands it to the voxel world. Phase 2 removes the "one patch" limit: as the player
> walks, the world keeps asking for ground heights in places the single image never covered. We need the
> height to come from a *cache of region tiles* that fills in on demand — invented by the AI on a
> background thread, never blocking the game, never running on a column worker — and stitched together so
> there are no holes or cliffs at the seams between tiles.

---

## 0. The one load-bearing fact (why this is cheap)

Every column's height flows through ONE chokepoint:
`mira::HeightmapGenerator::compute_ground_y(wx,wz)` (`Private/Core/HeightmapGenerator.cpp:377`), which, when
an override is installed, does exactly one thing (`HeightmapGenerator.cpp:381-383`):

```cpp
if (height_source_active()) {
    return height_src_->height_voxels_at(world_x, world_z);
}
```

`height_src_` is today a `const ImageHeightmap*` (`HeightmapGenerator.h:258`). Cliffs (`column_is_cliff`,
`.cpp:401-408`), banding/water/flora (`resolve_column`, `.cpp:421-...`) and the per-voxel `material_at` all
re-derive off `compute_ground_y`, so **whatever** we make `height_src_` point at, the entire downstream
generator follows for free — in the live streaming path AND the Nanite cold-bake (both build the same
generator via `BuildGen`, `VoxelGenParams.h:63`). Phase 2 is therefore: (a) widen that one pointer's static
type to an interface, and (b) add a streaming implementation behind it. No generator logic changes.

---

## 1. Extract `IHeightSource` (the minimal interface) — DONE (this scaffold)

`Source/MiraThalVoxel/Public/Core/IHeightSource.h` (NEW, shipped with this doc) is a pure-C++17,
engine-free, header-only abstract base in namespace `mira`. It declares exactly the three methods
`ImageHeightmap` already exposes, with byte-identical signatures so adoption is additive:

| `IHeightSource` (pure virtual)                              | `ImageHeightmap` (existing) | matches at |
|------------------------------------------------------------|-----------------------------|------------|
| `virtual bool valid() const = 0;`                          | `bool valid() const`        | `ImageHeightmap.h:83` |
| `virtual float sample_value(double x,double z) const = 0;` | `float sample_value(double,double) const` | `ImageHeightmap.h:94` |
| `virtual int height_voxels_at(int x,int z) const = 0;`    | `int height_voxels_at(int,int) const` | `ImageHeightmap.h:131` |

Verified: `IHeightSource.h` compiles standalone under `clang++ -std=c++17`, and an adapter subclass
forwarding to `ImageHeightmap`'s existing methods compiles + links clean (proves the signatures are
adoption-compatible without touching `ImageHeightmap.h`).

`compute_ground_y` calls **only** `height_voxels_at()`. `sample_value()` stays in the contract because it
is part of `ImageHeightmap`'s public surface and tests/callers read the pre-vertical-map value; keeping it
makes the interface a faithful 1:1 and avoids a future widening.

---

## 2. The EXACT minimal refactor to `HeightmapGenerator` (described, NOT applied)

This is the only edit to a shared engine file, deferred to the implementation step under review. It is a
**pure type-widening refactor** — no behaviour change, no logic moved.

### 2a. `HeightmapGenerator.h`

1. **Replace the forward-decl** at `HeightmapGenerator.h:55`:
   - from `class ImageHeightmap;`
   - to   `class IHeightSource;`  (and `#include "Core/IHeightSource.h"` near the other Core includes
     at `HeightmapGenerator.h:46-47`; the header is tiny and engine-free, so the include is free).
   - `ImageHeightmap` no longer needs to be named here at all (the generator only ever needed the override
     as an opaque pointer; the comment at `:52-55` updates to "an abstract height source").

2. **Member type** at `HeightmapGenerator.h:258`:
   - from `const ImageHeightmap* height_src_ = nullptr;`
   - to   `const IHeightSource*  height_src_ = nullptr;`

3. **Setter/getter** at `HeightmapGenerator.h:217-218`:
   - from `void set_height_source(const ImageHeightmap* hm) { height_src_ = hm; }`
   - to   `void set_height_source(const IHeightSource* hm) { height_src_ = hm; }`
   - from `const ImageHeightmap* height_source() const { return height_src_; }`
   - to   `const IHeightSource*  height_source() const { return height_src_; }`
   - The doc-comment at `:211-217` keeps its meaning (non-owning, caller keeps it alive) — just say
     "height source" instead of "imported heightmap".

`height_source_active()` (`.h:219` / `.cpp:373-375`), `compute_ground_y` (`.cpp:377-383`),
`column_is_cliff`, `resolve_column`, `material_at` are **untouched** — they already call only
`height_src_->valid()` and `height_src_->height_voxels_at(...)`, both now resolved virtually.

### 2b. `HeightmapGenerator.cpp`

Only the include comment at `.cpp:19` (`// the EXR-import override consulted by compute_ground_y`) is now
inaccurate; `#include "Core/ImageHeightmap.h"` can stay (harmless) or be dropped — `.cpp` no longer names
`ImageHeightmap`. No code lines change. `height_src_->height_voxels_at` at `.cpp:382` now dispatches
through the vtable; for `ImageHeightmap` it lands on the same inlined-equivalent body.

### 2c. `ImageHeightmap.h` (the adoption — also deferred, also additive)

- Add `#include "Core/IHeightSource.h"` and change `class ImageHeightmap {` → `class ImageHeightmap : public IHeightSource {`.
- Mark the three methods `override` (`valid()` `:83`, `sample_value()` `:94`, `height_voxels_at()` `:131`).
  No body changes. `ImageHeightmap` gains a vtable (8 bytes) — see risk R3.

> NOTE: `IHeightSource.h` documents this adoption but does **not** perform it, per the task constraint.
> Items 2a-2c are the reviewed implementation step.

### Why no other caller changes (verified usage sweep)

`set_height_source` is called from 7 sites; **every one passes a `const ImageHeightmap*` or `nullptr`**,
all of which convert implicitly to `const IHeightSource*` once `ImageHeightmap : public IHeightSource`
(standard derived-to-base pointer conversion):

- `VoxelGenParams.h:73` — `Gen.set_height_source(P.Heightmap)` (`P.Heightmap` is `const ImageHeightmap*`)
- `VoxelWorld.cpp:353` — `&ImportedHeightmap`
- `VoxelWorld.cpp:363` — `&DiffusionHeightmap`
- `VoxelFarHeightmesh.cpp:77` — `&Heightmap`
- `Private/Tests/HeightmapImportTest.cpp:101`, `tests/standalone/test_coarsegen.cpp:239,292`,
  `tests/standalone/test_imageheightmap.cpp:152,153,174,190` (incl. `nullptr`)

The `height_source()` **getter** return type also widens (`const ImageHeightmap*` → `const IHeightSource*`).
Sweep shows **no caller reads the getter** (only the declaration appears), so widening the return type
breaks nothing. This is the only place a concrete-type dependency *could* have hidden; it doesn't.

---

## 3. The streaming `DiffusionHeightSource` (NEW, in MiraThalTerrainAI)

A new concrete `IHeightSource` that, unlike `ImageHeightmap` (one fixed grid), answers from a **resident
region-tile cache**. It lives in `MiraThalTerrainAI` (which already depends on `MiraThalVoxel`, so it can
see `IHeightSource.h`); `MiraThalVoxel` never references it (dep root intact, same one-way wiring as
`TdiffWorldHook.h:9-12`).

### 3a. Data model

- The world is partitioned into fixed **region tiles** on a grid in world-voxel space. A tile covers
  `RegionSpanVoxels × RegionSpanVoxels` voxels (e.g. a coarse 64×64 DEM at 300 vox/px = 19200 vox ≈ 1.9 km).
  Tile coord `(tx,tz) = floor_div(world, RegionSpanVoxels)`.
- Each resident tile holds its **coarse DEM** (`FCoarseDem`, `DiffusionDemService.h:45-56`) plus the
  georef needed to bicubic-sample it. A tile is **NOT** stored as a fat per-voxel `ImageHeightmap`;
  Phase 2 samples the coarse grid directly through the detail bridge
  (`Core/Tdiff/DetailBridge.h::sample_height_voxels`, `DetailBridge.h:199-244`) so memory stays in the
  coarse domain (the Phase-1 service even flags this exact swap as its `*** SEAM ***`,
  `DiffusionDemService.h:117-124`).

### 3b. Implementation shape (header to be authored under `MiraThalTerrainAI/Public/`)

```cpp
// DiffusionHeightSource.h  (NEW — Phase 2; sketch, not shipped by this doc)
class FDiffusionDemService;                 // resident-tile owner (sec. 4)

namespace mira {
class DiffusionHeightSource final : public IHeightSource {
public:
    // Non-owning: the service outlives the source (mirrors set_height_source's
    // "caller keeps it alive" contract). Holds the vertical mapping + detail knobs.
    DiffusionHeightSource(const FDiffusionDemService* svc, int64 seed,
                          mira::tdiff::DetailBridgeParams detail,
                          double verticalScaleVoxels, double verticalBaseVoxels);

    bool  valid() const override;                              // svc set AND >=1 tile resident
    float sample_value(double wx, double wz) const override;   // detail-bridged continuous height (voxels)
    int   height_voxels_at(int wx, int wz) const override;     // floor(sample_value)
private:
    const FDiffusionDemService* Svc;   // resident tile lookup (lock-free read snapshot)
    // ... seed, DetailBridgeParams, vertical map ...
};
} // namespace mira
```

- `height_voxels_at(wx,wz)`: find the covering tile `(tx,tz)`; ask the service for its resident coarse DEM;
  call `mira::tdiff::sample_height_voxels(dem.Cells.GetData(), dem.CoarseW, dem.CoarseH, tileOriginVoxelX,
  tileOriginVoxelZ, voxelsPerCoarsePixel, wx, wz, detailParams)`; floor to int. Same detail bridge the
  Phase-1 `BuildHeightmapFromCoarse` seam will adopt — so Phase-1 bounded output and Phase-2 streaming
  output are **identical for the same tile** (no visual discontinuity when the mode flips).
- **CRITICAL INVARIANT:** by the time a worker calls `height_voxels_at` for column `c`, the tile covering
  `c` (and its 1-tile neighbour ring, sec. 5) is GUARANTEED resident. Residency is established on the game
  thread *before* the column job is enqueued (sec. 4). The source therefore never blocks, never runs
  inference, never allocates on the hot path — it does an array read + arithmetic. If a tile is somehow
  missing it must **not** invent a hole: it returns the clamped border height of the nearest resident tile
  (degrade to flat, never NaN/hole), which the assertions in sec. 6 catch in dev.

---

## 4. `FDiffusionDemService` gains async request-queue + resident-check + defer-and-retry

Phase 1's service (`DiffusionDemService.h`) is synchronous and bounded-region: `TryGetRegionHeightmap`
(`:94`) builds one `ImageHeightmap` on the calling thread. Phase 2 generalises it to a **tile cache + async
producer** that mirrors the column-gen back-pressure pattern exactly (`VoxelWorld.cpp:497-604`).

### 4a. New service surface (additive; Phase-1 API kept for the bounded path)

```cpp
// Added to FDiffusionDemService (Phase 2):
enum class ETileState : uint8 { Missing, InFlight, Resident };

// Game-thread: is the tile covering this world voxel ready to sample?
ETileState GetTileState(int64 Seed, FIntPoint TileCoord) const;

// Game-thread: ensure a tile (and optionally its neighbour ring) is being produced.
// Enqueues an async inference job iff Missing AND under the in-flight budget. Cheap +
// idempotent — safe to call every tick for every tile the streamer wants.
void RequestTile(int64 Seed, FIntPoint TileCoord);

// Game-thread, once per tick: move finished inference jobs into the resident cache.
// Mirrors HarvestColumnGen — drains ready TFutures, applies under a budget. Returns
// how many tiles became resident this tick.
int32 HarvestTiles(int32 Budget);

// Lock-free read used by DiffusionHeightSource on a worker: the resident coarse DEM
// for a tile, or nullptr if not resident. Backed by a TSharedPtr snapshot so a
// concurrent HarvestTiles add cannot free it mid-read.
TSharedPtr<const FCoarseDem> GetResidentTile(int64 Seed, FIntPoint TileCoord) const;
```

### 4b. The three-thread dance (who does what, and the rule that is never broken)

```
GAME THREAD (AVoxelWorld::TickStreaming, before EnqueueColumnGen)
  for each column the streamer wants this tick:
     tile = TileCoordOf(column)
     if Svc->GetTileState(seed,tile) != Resident
         OR any neighbour-ring tile != Resident:        // sec.5 seam guarantee
         Svc->RequestTile(seed, tile + ring...)          // kick async inference
         DEFER this column (do NOT EnqueueColumnGen yet) // <-- defer-and-retry
     else:
         EnqueueColumnGen(column, genLod)                // tile resident -> safe to gen

  Svc->HarvestTiles(TileBudget)                          // promote finished tiles
  HarvestColumnGen(ColumnBudget)                         // existing, unchanged

BACKGROUND TASK POOL (owned by the service, SEPARATE from the column ThreadPool)
  RequestTile -> Async(EAsyncExecution::Thread or a dedicated 1-2 thread pool):
     run ITdiffUNetRunner inference (coarse->latent->decoder) -> FCoarseDem
     (NEVER EAsyncExecution::ThreadPool — that's the column-gen pool; keep them apart)

COLUMN WORKER (EnqueueColumnGen's ThreadPool lambda, VoxelWorld.cpp:515)
  ONLY runs AFTER its tile is resident. Calls DiffusionHeightSource::height_voxels_at,
  which is a pure array read of the resident DEM. NO inference here, EVER.
```

**The rule (stated once, enforced everywhere):** inference runs only on the service's own background
task(s); column workers only *read* resident tiles; the game thread only *checks residency and harvests*.
This is the same decoupling the runtime plan calls out as risk-3 mitigation
(`TERRAIN_DIFFUSION_RUNTIME_PLAN.md:110-112`).

### 4c. Back-pressure (reuse the `MaxColumnJobsInFlight` shape verbatim)

- Add `MaxTileJobsInFlight` (small — inference is heavy + VRAM-bound; start at 1-2). `RequestTile` early-
  outs when `PendingTiles.Num() >= MaxTileJobsInFlight` (exact mirror of `VoxelWorld.cpp:503-506`), so a
  flood of requests cannot spawn unbounded GPU jobs. The deferred columns simply retry next tick — same
  "try again next tick" contract as `EnqueueColumnGen` (`VoxelWorld.cpp:506`).
- `HarvestTiles` drains ready `TFuture<FCoarseDem>`s nearest-first to the player focus (copy
  `HarvestColumnGen`'s focus-sort, `VoxelWorld.cpp:541-560`) under `TileBudget`, applying each into the
  resident cache as a `TSharedPtr<const FCoarseDem>`. Far-finished tiles wait — near tiles win.
- **Drain on teardown:** add `DrainTiles()` mirroring `DrainColumnGen` (`VoxelWorld.cpp:594-604`) — block
  on in-flight inference before clearing the cache, so no background job outlives the seed/world it
  captured. Called from `ClearWorld`/reseed alongside `DrainColumnGen`.
- **Epoch guard:** stamp each tile job with the `GenEpoch` (as column jobs do, `VoxelWorld.cpp:519,582`);
  `HarvestTiles` discards tiles whose epoch != current, so a reseed mid-flight cannot install a stale tile.

### 4d. Eviction (keep it bounded; defer the policy to Phase 4)

Phase 2 ships a simple cap: evict the farthest-from-focus resident tile when the cache exceeds
`MaxResidentTiles`. Never evict a tile that any in-flight column job still needs — guard by not evicting any
tile within the column streamer's active ring. (The VRAM ceiling / prefetch ring is Phase 4,
`TERRAIN_DIFFUSION_RUNTIME_PLAN.md:89-91`; Phase 2 only needs "doesn't grow forever").

---

## 5. Seam / blend correctness across region boundaries (no holes, no cliffs)

Two independent failure modes; both have concrete fixes.

### 5a. NO HOLES — residency must cover the sample footprint, not just the column

A column at the very edge of tile `(tx,tz)` is sampled by the detail bridge using a **4×4 coarse-pixel
neighbourhood** (`DetailBridge.h:136-154` bicubic) plus a central-difference **slope** stencil
(`DetailBridge.h:161-183`). Near a tile edge that stencil reaches into the *adjacent* tile. Two-part fix:

1. **Neighbour-ring residency gate (primary):** the game-thread check in sec. 4b requires the column's tile
   **and its 8-neighbour ring** to be resident before `EnqueueColumnGen`. So any sample's 4×4 + slope
   footprint always lands on resident data. This is the "defer-and-retry" condition.
2. **Tile apron / overlap (belt-and-braces):** each tile's `FCoarseDem` is produced with a 2-pixel APRON
   of overlap into its neighbours (the diffusion `WorldPipeline` already blends with a
   `linear_weight_window`, `TERRAIN_DIFFUSION_RUNTIME_PLAN.md:25-26`), so even an edge sample that reads
   the apron gets the neighbour's actual values, not a clamped border. The bridge's existing clamp
   (`dbridge_grid_at`, `DetailBridge.h:115-119`) becomes the *last-resort* fallback, not the normal edge
   path.

### 5b. NO CLIFFS — adjacent tiles must agree on the shared boundary height

If two tiles were inferred independently they could disagree by metres along their shared edge → a wall.
Guarantees, in order of strength:

1. **Deterministic, position-keyed inference.** Tiles are produced from `(seed, tileCoord)` deterministically
   (the ported `WorldPipeline.get` + `portable_rng`, gates 5-6 of Phase 1). The overlap-blend
   (`linear_weight_window`) makes neighbouring tiles **converge to the same values in the apron**, so the
   shared boundary is identical from either side — this is exactly what that windowing exists for.
2. **Shared continuous detail field.** The detail bridge's fBm uses **world coordinates** and the **world
   seed** (`DetailBridge.h:238-240` — `worldX*detailFreq`, `p.seed`), NOT tile-local coords. So the sub-30 m
   detail is one continuous field across the whole world; it cannot jump at a tile edge. Phase 2 must pass
   the SAME `DetailBridgeParams` (seed + freqs + amps) to every tile's sampling — store it once on the
   `DiffusionHeightSource`, never per-tile.
3. **Identical macro sampler both sides.** Both tiles use the same Catmull-Rom bicubic
   (`DetailBridge.h:124-154`), which passes exactly through coarse pixel centres; with matching apron values
   (5a.2) the interpolated edge height is bit-identical from either tile.

**Verification of seam continuity** is a pure-logic test (sec. 6): sample `height_voxels_at` along a shared
edge from tile A's data and from tile B's data; assert max |Δ| == 0 (or within the float-floor tolerance).

---

## 6. Implementation checklist (exact files, functions, order) + how to verify

Ordered so each step compiles + is verifiable before the next. Steps marked **[Core/headless]** are
clang-harness-gated; **[engine/PIE]** are verified live via mcp-unreal.

1. **[DONE] Ship `Core/IHeightSource.h`** (this scaffold). Verify: `tests/standalone/build.sh` still all-green
   (header is unused by Core yet, so it's a no-op compile check); the adapter compile-check in this doc's
   authoring already passed.

2. **[Core/headless] Adopt the interface — the type-widening refactor (sec. 2).** Edit `HeightmapGenerator.h`
   (forward-decl→`IHeightSource`, include, member `:258`, setter/getter `:217-218`), drop the stale comment
   in `HeightmapGenerator.cpp:19`, and make `ImageHeightmap : public IHeightSource` with `override`s
   (`ImageHeightmap.h`). **No other file changes.** Verify: `build.sh` (especially `test_imageheightmap`,
   `test_coarsegen`, `test_gen`) all-green — these already exercise `set_height_source(&img)` /
   `height_source_active()` and prove the virtual dispatch is behaviour-identical. This is the gate that the
   refactor is truly zero-change.

3. **[engine] Confirm the engine build is untouched in behaviour.** UBT build `MiraThalEditor`; the 7
   `set_height_source` call sites (sec. 2) should compile with no edits. If any fails it means a hidden
   concrete-type dependency — fix per sec. 2, not by reverting the interface. Verify: clean compile +
   existing EXR/Diffusion bounded path still renders (PIE `MiraThal.Tdiff.FillRegion`, `TdiffWorldHook.h:39`).

4. **[Core/headless] Author `DiffusionHeightSource.{h,cpp}`** in `MiraThalTerrainAI` (sec. 3) over a *stub*
   tile lookup (a `TFunction` returning a fixed analytic `FCoarseDem`, reusing
   `MakeAnalyticStubProvider`, `DiffusionDemService.h:105`). Keep the per-column math pure so it can be unit-
   tested. Verify: new `tests/standalone/test_tdiff_streamsource.cpp` —
   (a) `height_voxels_at` over a single tile == `mira::tdiff::sample_height_voxels` directly (the source adds
   no math); (b) **seam test (sec. 5b)**: build two adjacent tiles sharing an apron, assert edge heights
   agree to 0; (c) clamp/degrade test: missing tile returns nearest-resident border, never a sentinel hole.

5. **[Core or engine] Extend `FDiffusionDemService` with the tile cache + async queue (sec. 4).** Add
   `ETileState`, `RequestTile`, `HarvestTiles`, `GetResidentTile`, `GetTileState`, `DrainTiles`,
   `MaxTileJobsInFlight`, `MaxResidentTiles`, the `PendingTiles` array of `{TileCoord, Epoch, TFuture}`, and
   the resident `TMap<FTileKey, TSharedPtr<const FCoarseDem>>`. Reuse the Phase-1 `FRegionKey`/`GetTypeHash`
   shape (`DiffusionDemService.h:129-152`). Keep `TryGetRegionHeightmap` (Phase-1 bounded path) intact.
   Verify: a service-level unit test (engine automation, mirrors `HeightmapImportTest`) that drives
   `RequestTile`→tick→`HarvestTiles`→`GetResidentTile` with the analytic provider and asserts the in-flight
   cap (`MaxTileJobsInFlight`) and epoch-drop hold.

6. **[engine] Wire the streamer (sec. 4b) into `AVoxelWorld::TickStreaming`.** *(This edits VoxelWorld — it
   is the reviewed implementation step, NOT part of this scaffold.)* Before each `EnqueueColumnGen`
   (`VoxelWorld.cpp:497`), when `HeightSource == DiffusionAI` and streaming-mode is on, gate on tile+ring
   residency and defer-and-retry; install a `DiffusionHeightSource` (held on the world like
   `DiffusionHeightmap`, `VoxelWorld.h:991`) as the height source so `SnapshotGenParams`/`BuildGen`
   (`VoxelGenParams.h:206-240,63-75`) carry a pointer to it. Call `Svc->HarvestTiles` once per tick next to
   `HarvestColumnGen`; call `Svc->DrainTiles` in `ClearWorld` next to `DrainColumnGen`
   (`VoxelWorld.cpp:594`). Verify (PIE via mcp-unreal): walk past the Phase-1 bounded edge — terrain keeps
   appearing, no hitch (`stat unit` flat), no hole/cliff at tile seams (fly the boundary, capture viewport).

7. **[engine] Swap the stub producer for the real inference runner.** `RequestTile`'s background task calls
   the `ITdiffUNetRunner` (`TdiffUNetRunner.h`) on the service's own thread (NEVER the column ThreadPool).
   No `DiffusionHeightSource` or generator change — the producer is the only swap (the whole point of the
   injection seam, `DiffusionDemService.h:58-66`). Verify: PIE end-to-end matches a Python-rendered preview
   of the same seed for an *off-origin* region the bounded Phase-1 path never covered.

> Fingerprint note: `FingerprintGenParams` already folds the diffusion seed + region origin
> (`VoxelGenParams.h:189-194`). For streaming, per-tile origin differs; Phase 5 (saves/MP) extends the
> fingerprint with model-version + tile identity. Phase 2 may keep the single seed-level fingerprint (one
> seed = one infinite world) since the bake/crust still keys on seed + the tile it covers.

---

## 7. Risks → mitigations (esp. ABI / usage sites of `set_height_source`)

| # | Risk | Mitigation |
|---|------|-----------|
| R1 | **`set_height_source` call-site breakage.** 7 callers (`VoxelGenParams.h:73`, `VoxelWorld.cpp:353,363`, `VoxelFarHeightmesh.cpp:77`, 3 tests). | All pass `const ImageHeightmap*` or `nullptr` → implicit derived-to-base conversion once `ImageHeightmap : public IHeightSource`. **Zero call-site edits.** Verified by sweep (sec. 2). |
| R2 | **`height_source()` getter return-type change** could break a caller relying on the concrete `ImageHeightmap*`. | Sweep shows **no caller reads the getter** (only the decl). Safe to widen. If one appears later, it must `static_cast` or use the interface — flagged in review. |
| R3 | **`ImageHeightmap` gains a vtable** (it was a POD-ish value type, held *by value* on `AVoxelWorld` as `ImportedHeightmap`/`DiffusionHeightmap`, `VoxelWorld.h:991`, and copied in `TryGetRegionHeightmap` `Out`). +8 bytes, no longer trivially-copyable-as-POD but still copyable. | The class is still copy/move-correct (the added vptr is fine to copy; it has no `ImageHeightmap`-pointing state). It is never `memcpy`'d or serialized raw (the fingerprint hashes *fields*, not bytes — `VoxelGenParams.h:164-175`). Confirm no `std::is_trivially_copyable<ImageHeightmap>` assumption exists (none found). |
| R4 | **Worker samples a non-resident tile → hole or race.** | Residency is established on the game thread BEFORE `EnqueueColumnGen` (defer-and-retry, sec. 4b); neighbour-ring gate covers the bicubic/slope footprint (sec. 5a). Lock-free read via `TSharedPtr<const FCoarseDem>` snapshot (`GetResidentTile`) so a concurrent `HarvestTiles` add can't free mid-read. Dev assert in `DiffusionHeightSource` if a tile is missing at sample time. |
| R5 | **Inference accidentally lands on a column worker / blocks game thread.** | Service owns a SEPARATE background task (never `EAsyncExecution::ThreadPool`); `RequestTile`/`HarvestTiles` are the only inference touch-points; `MaxTileJobsInFlight` caps GPU jobs (mirror of `MaxColumnJobsInFlight`, `VoxelWorld.cpp:503`). Stated as the never-broken rule, sec. 4b. |
| R6 | **Seam cliff between independently-inferred tiles.** | Deterministic position-keyed inference + `linear_weight_window` apron blend (tiles converge in overlap) + world-space shared detail fBm (`DetailBridge.h:238-240`) + identical bicubic both sides (sec. 5b). Headless seam test asserts edge Δ == 0. |
| R7 | **Unbounded cache growth (RAM).** | `MaxResidentTiles` cap + farthest-from-focus eviction, never evicting a tile in the active column ring (sec. 4d). Tiles stored as coarse DEMs (KB), not per-voxel images. Full VRAM/prefetch policy deferred to Phase 4. |
| R8 | **Stale tile after reseed/teardown.** | `GenEpoch` stamp on every tile job + epoch-drop in `HarvestTiles`; `DrainTiles` blocks in-flight inference before clearing, mirroring `DrainColumnGen` (`VoxelWorld.cpp:594-604`). |
| R9 | **Phase-1 vs Phase-2 visual discontinuity** when the bounded image and the streaming source disagree on the same ground. | Both use the SAME detail bridge (`sample_height_voxels`); the Phase-1 `BuildHeightmapFromCoarse` seam adopts it too (`DiffusionDemService.h:117-124`). Same coarse tile + same `DetailBridgeParams` ⇒ identical height. |

---

## 8. Files this phase touches (summary)

- **NEW (shipped now):** `Source/MiraThalVoxel/Public/Core/IHeightSource.h` — the interface.
- **NEW (step 4):** `Source/MiraThalTerrainAI/Public/DiffusionHeightSource.h` + `Private/.cpp`.
- **NEW (step 4):** `tests/standalone/test_tdiff_streamsource.cpp` (Core seam + sampler parity).
- **EDIT under review (step 2):** `Core/HeightmapGenerator.h` (4 lines: fwd-decl, include, member, set/get),
  `Core/HeightmapGenerator.cpp` (1 comment), `Core/ImageHeightmap.h` (base + 3 `override`s).
- **EDIT under review (step 5):** `Source/MiraThalTerrainAI/Public/DiffusionDemService.h` + `.cpp`
  (tile cache + async queue; Phase-1 API preserved).
- **EDIT under review (step 6):** `Private/VoxelWorld.cpp` (`TickStreaming` gate + `HarvestTiles`/`DrainTiles`
  calls), `Public/VoxelWorld.h` (hold a `DiffusionHeightSource`).
- **NOT touched by Phase 2:** `VoxelGenParams.h` (works unchanged — `Heightmap` pointer + `BuildGen` already
  route through `set_height_source`; `DetailBridge.h` (consumed as-is).
