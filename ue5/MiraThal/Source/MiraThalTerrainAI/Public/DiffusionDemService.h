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
#include "Core/ImageHeightmap.h"      // mira::ImageHeightmap — the surface we fill + hand off
#include "Core/Tdiff/DetailBridge.h"  // mira::tdiff::sample_height_voxels — the 30 m -> 10 cm bridge

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

	bool IsValid() const
	{
		return CoarseW > 1 && CoarseH > 1
			&& Cells.Num() == CoarseW * CoarseH;
	}
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

	// THE CORE API. Build (or fetch from cache) the ImageHeightmap covering the bounded
	// region for this seed, and COPY it into Out. Returns false (Out left untouched) if
	// the region is degenerate or the provider has no DEM for it. Synchronous in Phase 1.
	bool TryGetRegionHeightmap(int64 Seed, const FIntRect& RegionInVoxels, mira::ImageHeightmap& Out);

	// Drop all cached region heightmaps (free the RAM). Called on world teardown / reseed.
	void ClearCache() { Cache.Empty(); }
	int32 NumCachedRegions() const { return Cache.Num(); }

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
};
