// DiffusionDemService.h — the runtime "coarse DEM -> ImageHeightmap" service (Phase 1).
//
// WHAT THIS IS (plain English):
// The AI terrain plan has two halves. The HARD half (running the diffusion neural net
// on the GPU and porting its Python orchestration) is owned elsewhere. THIS file is the
// EASY, load-bearing half: the plumbing that takes a COARSE elevation grid for a bounded
// region (one elevation number every ~30 m) and turns it into a mira::ImageHeightmap —
// the exact same "georeferenced float surface" the imported-Gaea-EXR path already feeds
// into the voxel generator. Once we hand that ImageHeightmap to the AVoxelWorld, the
// EXISTING voxel generator + Nanite bake render it with no further changes (cliffs,
// water, material banding, flora all ride on top of whatever ground height we supply).
//
// WHERE THE COARSE GRID COMES FROM (the injection seam):
// We do NOT run the AI here. Instead the service is handed a "coarse-DEM provider" — a
// callable that, given (seed, region), returns a coarse elevation grid. In Phase 1 we
// inject a STUB provider (a smooth analytic surface, or the captured golden tensor on
// disk) so the WHOLE path compiles and is exercisable in PIE before the real GPU
// inference lands. When the other agent's ITdiffUNetRunner-backed inference is ready,
// it simply becomes a different provider (run on a background task) with ZERO change to
// the code below — that is the point of the injection.
//
// PHASE 1 SCOPE: synchronous resolve, one bounded region at a time, a simple LRU-free
// region cache. The 30 m -> 10 cm "detail bridge" is, for now, the ImageHeightmap's own
// bilinear upsampling (identical to how an EXR pixel spans many voxels). See
// BuildHeightmapFromCoarse() for the single, clearly-marked seam where the richer
// mira::tdiff detail bridge (slope/altitude fractal noise over the coarse grid) slots in.
//
// This is engine-SIDE (it uses UE containers + file IO), but it touches NO GPU and NO
// UObject state, so it stays a plain class that is cheap to construct and easy to test.

#pragma once

#include "CoreMinimal.h"
#include "HAL/CriticalSection.h"      // FCriticalSection — guards the Phase-4 async in-flight/completed state
#include "Core/ImageHeightmap.h"      // mira::ImageHeightmap — the surface we fill + hand off
#include "Core/Tdiff/DetailBridge.h"  // mira::tdiff::sample_height_voxels — the 30 m -> 10 cm bridge
#include "Core/Tdiff/Erosion.h"       // mira::tdiff::erode — hydraulic+thermal drainage carving

// =============================================================================
// FCoarseDem — a low-resolution elevation grid for a bounded region.
//
// One float per coarse cell, row-major (z-major: index = z*CoarseW + x). Values are
// NORMALISED elevation in [0,1] (0 = the region's floor, 1 = its tallest point); the
// service maps them to voxel-Y via the configurable vertical scale/base, exactly like a
// normalised EXR. The grid is understood to SPAN the requested region: cell (0,0) sits
// on the region's min corner and cell (CoarseW-1, CoarseH-1) on its max corner.
// =============================================================================
struct FCoarseDem
{
	int32         CoarseW = 0;            // cells across (world +X)
	int32         CoarseH = 0;            // cells down  (world +Z)
	TArray<float> Cells;                  // CoarseW*CoarseH normalised elevations, row-major

	// Optional self-describing georef (Phase-2 streaming): the world-voxel position of cell
	// (0,0) and how many world voxels one cell spans. The bounded path leaves these 0 and
	// derives georef from the region rect; the STREAMING path sets them in EnsureTileResident
	// so a tile carries its own georef INCLUDING its apron (overlap into neighbours), letting
	// the height source sample edge columns with real neighbour data -> seamless tiles.
	double OriginVoxelX = 0.0;            // world-voxel X of cell (0,0)
	double OriginVoxelZ = 0.0;            // world-voxel Z of cell (0,0)
	double VoxelsPerCoarsePixel = 0.0;    // world voxels per coarse cell (0 = unset)

	bool IsValid() const
	{
		return CoarseW > 1 && CoarseH > 1
			&& Cells.Num() == CoarseW * CoarseH;
	}
	bool HasGeoref() const { return VoxelsPerCoarsePixel > 0.0; }
};

// The injected coarse-DEM provider. Given the world seed + the region (in world VOXELS),
// fill Out with a coarse elevation grid and return true; return false to signal "no DEM
// for this region" (the service then fails the resolve, leaving the world untouched).
//
// ASYNC NOTE: Phase 1 calls this synchronously on whatever thread asks. The real
// AI-backed provider will run inference on a BACKGROUND TASK and only resolve this
// callable once the tensor is ready — the service's TryGetRegionHeightmap is the
// boundary that a future async wrapper (request queue + resident-check) will sit behind.
using FCoarseDemProvider = TFunction<bool(int64 Seed, const FIntRect& RegionInVoxels, FCoarseDem& Out)>;

// =============================================================================
// FDiffusionDemService — owns the coarse-DEM provider + a per-region ImageHeightmap cache.
// =============================================================================
class MIRATHALTERRAINAI_API FDiffusionDemService
{
public:
	// Construct with a coarse-DEM provider. If none is supplied, the analytic stub is
	// used so the service is always functional out of the box (Phase 1 convenience).
	explicit FDiffusionDemService(FCoarseDemProvider InProvider = nullptr);

	// Swap the provider at runtime (e.g. replace the stub with the real AI runner once
	// it is ready). Clears the region cache so old stub tiles don't leak through.
	void SetProvider(FCoarseDemProvider InProvider);

	// --- Vertical mapping knobs (normalised coarse value -> voxel-Y) -----------
	// Mirror the EXR path: voxel_y = VerticalBaseVoxels + value * VerticalScaleVoxels.
	// Defaults match the EXR designer defaults at 10 voxels/m (peaks ~700 m, base ~12 m).
	void SetVerticalMapping(double InScaleVoxels, double InBaseVoxels)
	{
		VerticalScaleVoxels = InScaleVoxels;
		VerticalBaseVoxels  = InBaseVoxels;
	}

	// --- Detail-bridge tunables (the 30 m -> 10 cm upsample) -------------------
	// Master switch for the richer detail bridge. When TRUE (default), the service
	// synthesises a higher-resolution heightmap from the coarse grid via
	// mira::tdiff::sample_height_voxels (Catmull-Rom macro upsample + slope/altitude-
	// keyed fBm detail) and stores THAT in the ImageHeightmap, so the existing
	// compute_ground_y bilinear path renders crisp, detailed terrain. When FALSE, the
	// service falls back to the original Phase-1 behaviour (store the coarse grid raw
	// and let the image's own bilinear sampling do plain upsampling) — handy for A/B.
	bool bUseDetailBridge = true;

	// Knobs forwarded to the bridge (detail amplitude, octaves, frequency, slope &
	// altitude keying — see mira::tdiff::DetailBridgeParams for each field's meaning).
	// Sensible 30 m->10 cm defaults already live in the struct; the designer tweaks
	// fields here. `seed` is overwritten per-resolve with the world seed (so the same
	// region always regenerates identical detail) — no need to set it by hand.
	mira::tdiff::DetailBridgeParams DetailParams;

	// Resolution of the FINE heightmap we bake: how many world voxels one fine pixel
	// spans. 10 voxels = 1 m, i.e. we store a ground height roughly every metre. This
	// is the memory lever — halving it quadruples the pixel count. ~1 m comfortably
	// captures the macro surface plus the coarser detail bands; sub-pixel detail is
	// gently smoothed by the downstream bilinear sample (the documented trade-off we
	// accept to avoid materialising a per-voxel grid).
	double DetailPixelVoxels = 10.0;

	// Hard cap on the fine grid's width/height in pixels, so a large region can never
	// blow up RAM. At the 2048 default a region surface is at most 2048*2048*4 B = 16 MB.
	// If honouring DetailPixelVoxels would exceed this, the pixel pitch is coarsened
	// (pixels grow) until the grid fits — detail softens gracefully rather than OOMing.
	int32 DetailMaxDim = 2048;

	// --- Erosion (Phase 3): carve realistic drainage into the coarse DEM ---------
	// When ON (default), the coarse elevation grid is run through mira::tdiff::erode
	// (hydraulic droplet + thermal talus) BEFORE the detail bridge upsamples it, so the
	// AI macro terrain gains river valleys / ridgelines / basins instead of only smooth
	// bicubic slopes. Applied identically in the bounded and streaming paths (same coarse
	// grid) so both agree. Deterministic (seeded from the world seed via PortableRng).
	// NOTE (streaming): per-tile erosion is not yet perfectly seamless across tile edges
	// (droplets retire at the grid border); the tile apron mitigates it and a world-
	// positioned droplet pass is the clean fix — tracked as a follow-up.
	bool bErodeCoarse = true;

	// Erosion tunables. Defaults are set for the COARSE grid where one cell spans
	// ModelPixelVoxels/10 metres (~30 m) and cell values are METRES: the talus is a
	// stable inter-cell height delta in the coarse grid's own units. The designer tweaks
	// these; the seed is overwritten per-resolve. See mira::tdiff::ErosionParams.
	mira::tdiff::ErosionParams ErosionParams;

	// THE CORE API. Build (or fetch from cache) the ImageHeightmap covering the bounded
	// region for this seed, and COPY it into Out. Returns false (Out left untouched) if
	// the region is degenerate or the provider has no DEM for it. Synchronous in Phase 1.
	bool TryGetRegionHeightmap(int64 Seed, const FIntRect& RegionInVoxels, mira::ImageHeightmap& Out);

	// Drop all cached region heightmaps (free the RAM). Called on world teardown / reseed.
	void ClearCache() { Cache.Empty(); }
	int32 NumCachedRegions() const { return Cache.Num(); }

	// =============================================================================
	// PHASE 2 — STREAMING TILE CACHE (additive; the Phase-1 bounded API above is
	// untouched). An *infinite* AI world cannot be one bounded ImageHeightmap: as the
	// player walks, the world keeps asking for ground heights the single image never
	// covered. So we partition world-voxel space into a fixed GRID of square "stream
	// tiles" (TileSpanVoxels on a side) and keep a small, bounded cache of the COARSE
	// DEMs that fall under/near the player. mira::DiffusionHeightSource reads those
	// resident DEMs on column workers (read-only) and runs the SAME detail bridge the
	// bounded path uses, so streaming output matches the bounded output for the same
	// coarse data (design risk R9).
	//
	// THREADING MODEL (required for safety — see the Phase-2 design, sec. 4):
	//   * EnsureTileResident() builds tiles SYNCHRONOUSLY and runs ONLY on the game
	//     thread (it may call the provider, which later becomes GPU inference). The
	//     game thread makes every tile a column needs resident BEFORE enqueuing that
	//     column's worker job.
	//   * GetResidentTile() is the worker-side read: it only ever runs on a column
	//     whose covering tile (+ its 8-neighbour ring) was already made resident on the
	//     game thread, so it never overlaps in time with an EnsureTileResident() add.
	//     That temporal separation is what makes the lock-free TMap read safe; the
	//     returned TSharedPtr copy then keeps the DEM alive even if a later eviction
	//     drops it from the map mid-frame.
	// =============================================================================

	// One stream tile spans this many world voxels on each side. 19200 vox = 1920 m
	// (~1.9 km) = a coarse 64-interval DEM at 300 vox/px (= 30 m/px, the AI model pitch).
	int32 TileSpanVoxels = 19200;

	// Bounded cache size: when more than this many tiles are resident, the farthest tile
	// from the current focus is evicted (never the focus tile or its 8-neighbour ring).
	int32 MaxResidentTiles = 64;

	// Hard ceiling the metres->voxel mapping clamps the coarse surface to. SHARED with
	// BuildHeightmapFromCoarse (Phase-1) so the bounded and streaming paths convert a
	// coarse cell to a voxel height by the EXACT same formula (risk R9). The synchronous
	// GenerateWorld freezes on columns taller than the world's working budget, so the AI
	// surface is clamped to this band (sea level stays at VerticalBaseVoxels).
	static constexpr double kMaxSurfaceVoxels = 8192.0;

	// Game-thread setter: which tile is the player/streamer centred on. Eviction keeps
	// this tile and its 8-neighbour ring resident and discards the farthest others.
	void SetTileFocus(FIntPoint InFocusTile) { TileFocus = InFocusTile; }

	// GAME THREAD ONLY. Ensure the tile at TileCoord is built + cached, then return a
	// borrowed pointer to its coarse DEM (owned by the cache). Idempotent: a cache hit
	// returns the existing DEM without rebuilding. Returns nullptr if the provider has
	// no DEM for the tile (the caller then defers that column). Builds the tile's voxel
	// rect (Min = TileCoord*TileSpanVoxels, Max = Min + TileSpanVoxels) and calls the
	// same Provider the bounded path uses, SYNCHRONOUSLY on the calling (game) thread.
	const FCoarseDem* EnsureTileResident(int64 Seed, FIntPoint TileCoord);

	// ANY THREAD, read-only. Return the cached coarse DEM for a tile as a TSharedPtr
	// snapshot (null if not resident). Safe to call from a column worker: see the
	// threading note above. The TSharedPtr copy keeps the DEM alive for the caller even
	// if the game thread evicts it from the map after this returns.
	TSharedPtr<const FCoarseDem> GetResidentTile(int64 Seed, FIntPoint TileCoord) const;

	// Drop the whole stream-tile cache (free the RAM). Called alongside ClearCache() on
	// world teardown / reseed so no stale tile survives a seed change.
	//
	// ASYNC NOTE (Phase 4): this only clears the RESIDENT map. It does NOT block on in-flight
	// async jobs — for a full teardown that also waits out background inference, call DrainTiles()
	// (the destructor does this automatically). We DO bump the async epoch + drop any parked
	// completed results here so a reseed can't install a stale tile that finished before the swap.
	void ClearTiles();
	int32 NumResidentTiles() const { return Tiles.Num(); }

	// =============================================================================
	// PHASE 4 — ASYNC (OFF-GAME-THREAD) TILE GENERATION (additive; default OFF).
	//
	// WHY: the real coarse-DEM provider runs ~1.6 s of DirectML inference PER TILE. Done on the
	// game thread (EnsureTileResident) that is a visible multi-hundred-ms freeze every time the
	// player crosses a tile boundary. This path moves that work onto a dedicated BACKGROUND
	// THREAD so the game thread only ever (a) fires a non-blocking request and (b) drains the
	// finished DEMs into the resident map. The heavy inference NEVER touches the game thread and
	// NEVER touches the voxel column ThreadPool.
	//
	// SAFETY: DirectML-off-thread is UNPROVEN in this build, so EVERYTHING async is gated behind
	// bAsyncTileGen. Default FALSE == the byte-for-byte-unchanged synchronous EnsureTileResident
	// path, so it can be A/B'd and instantly reverted from the console.
	//
	// THREADING INVARIANT (unchanged from Phase 2, preserved here): the resident `Tiles` map is
	// WRITTEN ONLY on the game thread — in the sync path by EnsureTileResident, in the async path
	// ONLY by HarvestTiles. Background workers NEVER write it; they only build an FCoarseDem in
	// isolation and park it in the lock-guarded completed queue. Column workers keep reading it
	// lock-free via GetResidentTile (TSharedPtr snapshot). So the game-thread-only-writer
	// invariant that makes the lock-free read safe is intact.
	// =============================================================================

	// MASTER SWITCH. FALSE (default) = synchronous EnsureTileResident (proven). TRUE = the async
	// RequestTile/HarvestTiles path below. Set on the game thread before/at StartStreaming; the
	// streamer also mirrors the CVar MiraThal.Tdiff.AsyncTiles onto it.
	bool bAsyncTileGen = false;

	// Cap on concurrent background inference jobs (mirror of the column-gen MaxColumnJobsInFlight).
	// Inference is heavy + VRAM-bound, so keep it small. RequestTile early-outs when this many
	// jobs are already in flight; the deferred tiles simply retry on the next tick.
	int32 MaxTileJobsInFlight = 2;

	// GAME THREAD, NON-BLOCKING. Ask for the tile at TileCoord to be produced asynchronously.
	// No-op if the tile is already resident, already in flight, or the in-flight cap is hit.
	// Otherwise launches ONE background job (a dedicated thread — never the column ThreadPool)
	// that runs the provider to build the tile's FCoarseDem and parks it in the completed queue.
	// Stamped with the current epoch so a reseed drops the result. If bAsyncTileGen is FALSE this
	// falls back to a synchronous EnsureTileResident so a caller can use it unconditionally.
	void RequestTile(int64 Seed, FIntPoint TileCoord);

	// GAME THREAD, once per tick. Drain up to Budget finished jobs from the completed queue into
	// the resident `Tiles` map (nearest-to-focus first). Stale-epoch results are discarded. This
	// is the ONLY place the resident map is written when async. Returns how many became resident.
	int32 HarvestTiles(int32 Budget);

	// GAME THREAD. Teardown: bump the epoch, drop parked results, then BLOCK until every in-flight
	// background job has finished touching this object, then clear the resident map. Mirrors the
	// column-gen DrainColumnGen. The destructor calls this so a background job can never outlive
	// the service (and the provider it captured) it was launched from.
	void DrainTiles();

	// Diagnostics (game thread): how many async jobs are currently in flight.
	int32 NumTileJobsInFlight() const;

	// Destructor blocks on any in-flight async job (see DrainTiles) so no worker outlives us.
	~FDiffusionDemService();

	// Convert ONE normalised coarse cell to an absolute voxel height using the EXACT
	// same formula + clamp as BuildHeightmapFromCoarse (the bounded path). Exposed so a
	// streaming sampler converts identically. CellIndex must be a valid Dem.Cells index.
	//   voxelY = clamp(VerticalBaseVoxels + cell * VerticalScaleVoxels, 0, kMaxSurfaceVoxels)
	double TileVoxelHeightAtCell(const FCoarseDem& Dem, int32 CellIndex) const
	{
		const double Y = VerticalBaseVoxels
			+ static_cast<double>(Dem.Cells[CellIndex]) * VerticalScaleVoxels;
		return FMath::Clamp(Y, 0.0, kMaxSurfaceVoxels);
	}

	// Vertical-mapping accessors so the wiring can construct a DiffusionHeightSource that
	// converts coarse cells with the SAME scale/base this service used (risk R9).
	double GetVerticalScaleVoxels() const { return VerticalScaleVoxels; }
	double GetVerticalBaseVoxels()  const { return VerticalBaseVoxels;  }

	// Scan every RESIDENT tile for this seed and return the world-voxel (X,Z) + voxel height
	// of the TALLEST land cell found. Lets the spawn drop the player onto the highest nearby
	// mountain the AI produced (instead of the first marginal coastline). Returns false if no
	// tile is resident. Game thread. Height uses the same clamp as TileVoxelHeightAtCell.
	bool HighestResidentLand(int64 Seed, double& OutWorldX, double& OutWorldZ,
	                         double& OutHeightVoxels) const;

	// Floor-divide a world voxel coordinate into its covering tile coord. Static + pure
	// so the streamer (game thread) and the height source (worker) compute the SAME tile
	// for a column. Handles negative coordinates (true floor division, not trunc-toward-0).
	static FIntPoint TileCoordOf(int64 WorldVoxelX, int64 WorldVoxelZ, int32 InTileSpanVoxels)
	{
		const int64 Span = (InTileSpanVoxels > 0) ? static_cast<int64>(InTileSpanVoxels) : 1;
		auto FloorDiv = [Span](int64 A) -> int64
		{
			int64 Q = A / Span;
			const int64 R = A % Span;        // Span > 0, so R has the sign of A
			if (R != 0 && R < 0) { --Q; }    // round toward negative infinity
			return Q;
		};
		return FIntPoint(static_cast<int32>(FloorDiv(WorldVoxelX)),
		                 static_cast<int32>(FloorDiv(WorldVoxelZ)));
	}

	// --- Stub coarse-DEM providers (Phase 1) ----------------------------------
	// A smooth, deterministic analytic surface (sum of a few sinusoids, phased by seed).
	// No file or GPU needed — always available, so the end-to-end path is exercisable.
	// CoarseCellVoxels = how many world voxels one coarse cell spans (300 = 30 m, the
	// finest AI model's pixel pitch); the grid resolution is derived from the region.
	static FCoarseDemProvider MakeAnalyticStubProvider(int32 CoarseCellVoxels = 300);

	// Load a captured golden tensor from disk and use its first 64x64 channel as the
	// coarse grid (normalised to [0,1]). Lets the real model's golden output drive the
	// path before live inference exists, e.g.
	// D:/terrain-diffusion/golden/coarse_model__output.f32.bin (shape (1,6,64,64)).
	// Returns an analytic-stub fallback if the file can't be read.
	static FCoarseDemProvider MakeGoldenFileStubProvider(const FString& AbsPath,
	                                                      int32 GridW = 64, int32 GridH = 64);

private:
	// The 30 m -> 10 cm "detail bridge" step (Phase 1 implementation). Maps a coarse grid
	// onto a mira::ImageHeightmap whose georef makes it SPAN the region, so the image's
	// own bilinear sampling upsamples the coarse cells to per-voxel ground heights — the
	// exact mechanism the EXR path uses. *** SEAM ***: when the richer detail bridge lands
	// (Core/Tdiff/DetailBridge.h :: mira::tdiff::sample_height_voxels), THIS is the one
	// function that changes — it would allocate a finer pixel grid and fill it via that
	// sampler (coarse macro + slope/altitude fractal detail) instead of storing the coarse
	// cells raw. Everything upstream/downstream is unaffected. Seed is passed through for
	// that future per-voxel detail synthesis.
	void BuildHeightmapFromCoarse(const FCoarseDem& Dem, int64 Seed,
	                              const FIntRect& RegionInVoxels, mira::ImageHeightmap& Out) const;

	// Cache key: a region heightmap is uniquely identified by its seed + voxel rectangle.
	struct FRegionKey
	{
		int64 Seed = 0;
		int32 MinX = 0, MinZ = 0, MaxX = 0, MaxZ = 0;

		bool operator==(const FRegionKey& O) const
		{
			return Seed == O.Seed && MinX == O.MinX && MinZ == O.MinZ
				&& MaxX == O.MaxX && MaxZ == O.MaxZ;
		}
		friend uint32 GetTypeHash(const FRegionKey& K)
		{
			uint32 H = ::GetTypeHash(K.Seed);
			H = HashCombine(H, ::GetTypeHash(K.MinX));
			H = HashCombine(H, ::GetTypeHash(K.MinZ));
			H = HashCombine(H, ::GetTypeHash(K.MaxX));
			H = HashCombine(H, ::GetTypeHash(K.MaxZ));
			return H;
		}
	};
	static FRegionKey MakeKey(int64 Seed, const FIntRect& R)
	{
		return FRegionKey{ Seed, R.Min.X, R.Min.Y, R.Max.X, R.Max.Y };
	}

	FCoarseDemProvider Provider;
	// Resident region surfaces. TSharedPtr so a cache hit copies the pointer, not the
	// (potentially large) pixel grid, until the caller asks for its own copy in Out.
	TMap<FRegionKey, TSharedPtr<mira::ImageHeightmap>> Cache;

	double VerticalScaleVoxels = 7000.0; // 700 m * 10 vox/m (matches EXR altitude default)
	double VerticalBaseVoxels  = 120.0;  // 12 m * 10 vox/m  (sea level floor)

	// --- Phase 2: stream-tile cache (mirrors the FRegionKey shape) -------------
	// A tile is uniquely identified by seed + integer tile coord on the world grid.
	struct FTileKey
	{
		int64 Seed = 0;
		int32 Tx = 0;
		int32 Tz = 0;

		bool operator==(const FTileKey& O) const
		{
			return Seed == O.Seed && Tx == O.Tx && Tz == O.Tz;
		}
		friend uint32 GetTypeHash(const FTileKey& K)
		{
			uint32 H = ::GetTypeHash(K.Seed);
			H = HashCombine(H, ::GetTypeHash(K.Tx));
			H = HashCombine(H, ::GetTypeHash(K.Tz));
			return H;
		}
	};
	static FTileKey MakeTileKey(int64 Seed, FIntPoint TileCoord)
	{
		return FTileKey{ Seed, TileCoord.X, TileCoord.Y };
	}

	// Resident coarse DEMs. const so a worker can never mutate one through its snapshot.
	TMap<FTileKey, TSharedPtr<const FCoarseDem>> Tiles;

	// The tile eviction keeps resident (with its 8-neighbour ring); set per tick by the
	// streamer via SetTileFocus(). Defaults to origin until the world sets it.
	FIntPoint TileFocus = FIntPoint::ZeroValue;

	// Game-thread helper: while the cache exceeds MaxResidentTiles, drop the farthest
	// tile from TileFocus, never evicting the focus tile, its 8-neighbour ring, or
	// KeepKey (the tile EnsureTileResident just added).
	void EvictTilesIfNeeded(const FTileKey& KeepKey);

	// --- Phase 4: async tile-gen internals ------------------------------------
	// Shared build core: construct the tile's world-voxel rect (+ apron), run the provider and
	// self-describe the georef into OutDem. Returns false if the provider had no valid DEM. Used
	// ONLY by the async worker (RequestTile's background task). The synchronous EnsureTileResident
	// keeps its OWN inline copy of this logic UNCHANGED so the proven path is untouched.
	//
	// IMPORTANT: this reads `Provider` and calls it. It is invoked under ProviderLock so provider
	// access stays serialised (the provider is single-threaded by contract — see
	// DiffusionCoarseProvider.cpp), and it touches NOTHING else on the object, so it is safe to
	// run on a background thread.
	bool BuildTileDemAsync(int64 Seed, FIntPoint TileCoord, FCoarseDem& OutDem) const;

	// One finished background job waiting to be harvested onto the game thread.
	struct FCompletedTile
	{
		FTileKey                     Key;
		TSharedPtr<const FCoarseDem> Dem;    // never null when parked (a failed build is dropped)
		uint32                       Epoch = 0;
	};

	// Guards ALL of: InFlightTiles, CompletedTiles, TileEpoch. Held only briefly (set/queue ops),
	// never across the provider call. `mutable` so const accessors (NumTileJobsInFlight) can lock.
	mutable FCriticalSection AsyncStateLock;

	// Serialises the (single-threaded-by-contract) provider so two background jobs never call it
	// concurrently. Held ONLY around BuildTileDemAsync, never together with AsyncStateLock.
	FCriticalSection ProviderLock;

	// Tiles with a background job currently building them (game-thread requested, worker clears).
	TSet<FTileKey> InFlightTiles;               // guarded by AsyncStateLock

	// Finished DEMs waiting for HarvestTiles to promote them onto the game thread.
	TArray<FCompletedTile> CompletedTiles;      // guarded by AsyncStateLock

	// Bumped by DrainTiles()/ClearTiles() on reseed/teardown; a job stamped with an older epoch is
	// discarded by HarvestTiles so a stale tile can never install after a seed change.
	uint32 TileEpoch = 0;                       // guarded by AsyncStateLock
};
