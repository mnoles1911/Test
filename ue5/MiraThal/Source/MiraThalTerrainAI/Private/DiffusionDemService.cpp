// DiffusionDemService.cpp — implementation of the coarse-DEM -> ImageHeightmap service.
// See DiffusionDemService.h for the full design notes. Phase 1: synchronous, stubbed
// coarse provider, ImageHeightmap-bilinear "detail bridge".

#include "DiffusionDemService.h"

#include "Misc/FileHelper.h"   // FFileHelper::LoadFileToArray — golden-tensor stub loader
#include "Logging/LogMacros.h"
#include "Async/Async.h"       // Async(EAsyncExecution::Thread, ...) — Phase-4 background inference
#include "Misc/ScopeLock.h"    // FScopeLock — guards the async in-flight/completed state
#include "HAL/PlatformProcess.h" // FPlatformProcess::Sleep — DrainTiles wait loop

DEFINE_LOG_CATEGORY_STATIC(LogMiraDemService, Log, All);

// ---------------------------------------------------------------------------
// Construction / provider management
// ---------------------------------------------------------------------------
FDiffusionDemService::FDiffusionDemService(FCoarseDemProvider InProvider)
	: Provider(MoveTemp(InProvider))
{
	// Default to the always-available analytic stub so the service is functional with no
	// setup (Phase 1). A caller can SetProvider() the real AI runner later.
	if (!Provider)
	{
		Provider = MakeAnalyticStubProvider();
	}
}

void FDiffusionDemService::SetProvider(FCoarseDemProvider InProvider)
{
	Provider = InProvider ? MoveTemp(InProvider) : MakeAnalyticStubProvider();
	ClearCache(); // stub tiles must not survive a provider swap
}

// ---------------------------------------------------------------------------
// Core resolve: region -> ImageHeightmap (cache-aware, synchronous)
// ---------------------------------------------------------------------------
bool FDiffusionDemService::TryGetRegionHeightmap(int64 Seed, const FIntRect& RegionInVoxels,
                                                 mira::ImageHeightmap& Out)
{
	// Reject a degenerate region up front (zero/negative span has no terrain to fill).
	const int32 WidthVox  = RegionInVoxels.Max.X - RegionInVoxels.Min.X;
	const int32 HeightVox = RegionInVoxels.Max.Y - RegionInVoxels.Min.Y;
	if (WidthVox <= 0 || HeightVox <= 0)
	{
		UE_LOG(LogMiraDemService, Warning,
			TEXT("[Tdiff] TryGetRegionHeightmap: degenerate region %dx%d voxels — ignored."),
			WidthVox, HeightVox);
		return false;
	}

	// Cache hit? Copy the resident surface out and we're done.
	const FRegionKey Key = MakeKey(Seed, RegionInVoxels);
	if (const TSharedPtr<mira::ImageHeightmap>* Found = Cache.Find(Key))
	{
		if (Found->IsValid() && (*Found)->valid())
		{
			Out = *Found->Get();
			return true;
		}
	}

	// Cache miss: ask the provider for a coarse grid (Phase 1 = stub; later = AI inference).
	FCoarseDem Dem;
	if (!Provider || !Provider(Seed, RegionInVoxels, Dem) || !Dem.IsValid())
	{
		UE_LOG(LogMiraDemService, Warning,
			TEXT("[Tdiff] coarse-DEM provider returned no valid grid for region "
			     "[%d,%d]..[%d,%d] (seed %lld)."),
			RegionInVoxels.Min.X, RegionInVoxels.Min.Y,
			RegionInVoxels.Max.X, RegionInVoxels.Max.Y, static_cast<long long>(Seed));
		return false;
	}

	// Run the detail bridge: coarse grid -> ImageHeightmap that spans the region.
	TSharedPtr<mira::ImageHeightmap> Hm = MakeShared<mira::ImageHeightmap>();
	BuildHeightmapFromCoarse(Dem, Seed, RegionInVoxels, *Hm);
	if (!Hm->valid())
	{
		UE_LOG(LogMiraDemService, Warning,
			TEXT("[Tdiff] built an INVALID ImageHeightmap from a %dx%d coarse grid — ignored."),
			Dem.CoarseW, Dem.CoarseH);
		return false;
	}

	Cache.Add(Key, Hm);
	Out = *Hm;

	UE_LOG(LogMiraDemService, Display,
		TEXT("[Tdiff] region heightmap built: %dx%d px (coarse %dx%d), %.1f vox/px, "
		     "origin voxel (%d, %d), seed %lld. Cache now %d region(s)."),
		Hm->width, Hm->height, Dem.CoarseW, Dem.CoarseH, Hm->voxels_per_pixel,
		RegionInVoxels.Min.X, RegionInVoxels.Min.Y, static_cast<long long>(Seed), Cache.Num());
	return true;
}

// ---------------------------------------------------------------------------
// The 30 m -> 10 cm detail bridge.
//
// Two modes (selected by bUseDetailBridge):
//   * bUseDetailBridge == false (legacy Phase-1): store the coarse grid raw and let
//     mira::ImageHeightmap's own bilinear sampler upsample it — plain smooth ramps.
//   * bUseDetailBridge == true  (default): synthesise a FINER heightmap grid through
//     mira::tdiff::sample_height_voxels (Catmull-Rom bicubic macro upsample + slope/
//     altitude-keyed fBm detail) and store THAT. The downstream compute_ground_y
//     bilinear path then renders crisp, detailed terrain with no further changes.
// ---------------------------------------------------------------------------
void FDiffusionDemService::BuildHeightmapFromCoarse(const FCoarseDem& Dem, int64 Seed,
                                                    const FIntRect& RegionInVoxels,
                                                    mira::ImageHeightmap& Out) const
{
	// Region span in world voxels. FCoarseDem::IsValid() guarantees CoarseW/H > 1, and
	// TryGetRegionHeightmap rejected non-positive spans, so both are > 0 here.
	const double WidthVox  = static_cast<double>(RegionInVoxels.Max.X - RegionInVoxels.Min.X);
	const double HeightVox = static_cast<double>(RegionInVoxels.Max.Y - RegionInVoxels.Min.Y);

	// =====================================================================
	// LEGACY PATH — store the coarse grid raw (plain bilinear upsample).
	// =====================================================================
	if (!bUseDetailBridge)
	{
		Out.width  = Dem.CoarseW;
		Out.height = Dem.CoarseH;
		// Copy the normalised elevations into the Core surface (TArray -> std::vector).
		Out.data.assign(Dem.Cells.GetData(), Dem.Cells.GetData() + Dem.Cells.Num());
		Out.flip_z = false;       // coarse grid is already in world +Z order (z-major)

		// Georeference so cell (0,0) sits on the region's MIN corner and (W-1,H-1) on its MAX.
		Out.voxels_per_pixel = WidthVox / static_cast<double>(Dem.CoarseW - 1);
		Out.origin_voxel_x   = static_cast<double>(RegionInVoxels.Min.X);
		Out.origin_voxel_z   = static_cast<double>(RegionInVoxels.Min.Y);

		// Vertical mapping (normalised value -> voxel-Y), mirroring the EXR path.
		Out.vertical_scale_voxels = VerticalScaleVoxels;
		Out.vertical_base_voxels  = VerticalBaseVoxels;
		return;
	}

	// =====================================================================
	// DETAIL-BRIDGE PATH (default).
	// =====================================================================

	// --- 1) Convert the coarse grid from normalised [0,1] into ABSOLUTE VOXEL HEIGHTS.
	// The bridge contract (DetailBridge.h) is that the coarse grid carries heights in
	// voxels: its bicubic macro height, its slope estimate (rise/run) and its altitude
	// keying all assume voxel units. We apply the SAME vertical mapping the EXR path uses
	// (voxel_y = base + value * scale) up front, so the synthesised grid is already in
	// final voxel-Y. (This is why the fine surface below uses an identity vertical map.)
	// SAFETY CLAMP (2026-06-29): Cells now carry ABSOLUTE metres (sea-anchored mapping), so a
	// true-scale 2 km peak becomes a ~21,660-voxel column and a -5 km trench a -50,320 one. The
	// SYNCHRONOUS GenerateWorld fills full columns and FREEZES on columns that tall (the earlier
	// normalised path capped ~7,120 voxels and never froze). So clamp the surface to a sane band:
	// floor at y=0 (deep ocean bottoms out, no negative columns) and a ceiling near the world's
	// working budget. Sea level stays aligned (0 m -> VerticalBaseVoxels). NOTE: this flattens the
	// AI's biggest peaks for now; raise kMaxSurfaceVoxels once streaming/LOD renders tall columns
	// without a full synchronous fill (Phase 4) instead of capping them here.
	// (kMaxSurfaceVoxels is now the shared FDiffusionDemService::kMaxSurfaceVoxels class constant,
	//  so the Phase-2 streaming sampler clamps to the EXACT same ceiling — risk R9.)
	TArray<float> CoarseVox;
	CoarseVox.SetNumUninitialized(Dem.Cells.Num());
	for (int32 i = 0; i < Dem.Cells.Num(); ++i)
	{
		const double Y = VerticalBaseVoxels + static_cast<double>(Dem.Cells[i]) * VerticalScaleVoxels;
		CoarseVox[i] = static_cast<float>(FMath::Clamp(Y, 0.0, kMaxSurfaceVoxels));
	}

	// Coarse-grid georef: pixel (0,0)'s centre is the region MIN corner; one coarse pixel
	// spans CoarsePitch voxels so the last cell lands on the region's MAX corner.
	const double OriginX     = static_cast<double>(RegionInVoxels.Min.X);
	const double OriginZ     = static_cast<double>(RegionInVoxels.Min.Y);
	const double CoarsePitch = WidthVox / static_cast<double>(Dem.CoarseW - 1);

	// --- 2) Choose the FINE heightmap resolution (memory lever, capped).
	// Aim for DetailPixelVoxels voxels per fine pixel; land the last pixel on the far edge
	// (so +1). Clamp the pixel COUNT to [2, DetailMaxDim] so a huge region can't OOM — if
	// the cap bites, the effective pitch just grows (detail softens) instead of allocating
	// a giant grid. We derive a SINGLE square pitch from X and size Z to match it, because
	// mira::ImageHeightmap samples both axes with one voxels_per_pixel (regions are square
	// in practice, so this is exact; any tiny Z residual is absorbed by edge clamping).
	const double DesiredPitch = FMath::Max(1.0, DetailPixelVoxels);
	int32 FineW = FMath::Clamp(FMath::RoundToInt(WidthVox / DesiredPitch) + 1, 2, DetailMaxDim);
	const double FinePitch = WidthVox / static_cast<double>(FineW - 1);
	int32 FineH = FMath::Clamp(FMath::RoundToInt(HeightVox / FinePitch) + 1, 2, DetailMaxDim);

	// --- 3) Per-resolve bridge params: copy the tunables, fix the seed for determinism.
	mira::tdiff::DetailBridgeParams Params = DetailParams;
	Params.seed = static_cast<int64_t>(Seed);

	// SPIKINESS FIX (2026-06-29): the stock detail-bridge defaults (slopeBoost=2.0,
	// detailAmpVoxels=40) made AI terrain a chaotic spiky mess near the player. The killer is
	// slopeBoost amplifying the safety-clamp's ocean/land CLIFFS by up to ~7.7x -> 30 m fractal
	// spikes at every coast. We tame the AI path here (NOT the shared struct default, so the EXR
	// world is untouched): much lower slope keying, smaller base bumps, slightly finer grain.
	Params.slopeBoost     = 0.25;  // was 2.0 — stop cliff-boundary blow-up (primary fix)
	Params.detailAmpVoxels = 12.0; // was 40.0 — 1.2 m micro-relief instead of 4 m bumps
	Params.detailFreq     = 0.02;  // was 0.01 — finer wavelength so residual bumps read as texture

	// --- 4) Bake the fine grid. For each fine pixel we ask the bridge for the ground
	// height (in voxels) at the corresponding ABSOLUTE world voxel column — using true
	// world coords keeps the fBm detail field seamless across neighbouring regions.
	Out.width  = FineW;
	Out.height = FineH;
	Out.data.resize(static_cast<size_t>(FineW) * static_cast<size_t>(FineH));
	for (int32 fz = 0; fz < FineH; ++fz)
	{
		const int32 WorldZ = RegionInVoxels.Min.Y
			+ FMath::RoundToInt(static_cast<double>(fz) * FinePitch);
		for (int32 fx = 0; fx < FineW; ++fx)
		{
			const int32 WorldX = RegionInVoxels.Min.X
				+ FMath::RoundToInt(static_cast<double>(fx) * FinePitch);

			const double H = mira::tdiff::sample_height_voxels(
				CoarseVox.GetData(), Dem.CoarseW, Dem.CoarseH,
				OriginX, OriginZ, CoarsePitch,
				WorldX, WorldZ, Params);

			Out.data[static_cast<size_t>(fz) * static_cast<size_t>(FineW) + static_cast<size_t>(fx)]
				= static_cast<float>(H);
		}
	}

	// --- 5) Georef + vertical map. The fine grid SPANS the region (origin = MIN corner,
	// pitch = FinePitch). data already holds ABSOLUTE voxel heights, so the vertical map is
	// the identity (height_voxels_at = floor(value)); compute_ground_y's bilinear blend
	// between these ~1 m samples is what renders the per-column ground.
	Out.flip_z           = false;
	Out.voxels_per_pixel = FinePitch;
	Out.origin_voxel_x   = OriginX;
	Out.origin_voxel_z   = OriginZ;
	Out.vertical_scale_voxels = 1.0;
	Out.vertical_base_voxels  = 0.0;
}

// ---------------------------------------------------------------------------
// Stub provider #1 — a smooth, deterministic analytic surface.
// ---------------------------------------------------------------------------
FCoarseDemProvider FDiffusionDemService::MakeAnalyticStubProvider(int32 CoarseCellVoxels)
{
	const int32 Cell = FMath::Max(1, CoarseCellVoxels);
	return [Cell](int64 Seed, const FIntRect& R, FCoarseDem& Out) -> bool
	{
		const int32 WidthVox  = R.Max.X - R.Min.X;
		const int32 HeightVox = R.Max.Y - R.Min.Y;
		if (WidthVox <= 0 || HeightVox <= 0)
		{
			return false;
		}

		// At least a 2x2 grid (bilinear needs two cells each way); one extra cell so the
		// grid's last cell lands on the region's far edge.
		Out.CoarseW = FMath::Max(2, WidthVox  / Cell + 1);
		Out.CoarseH = FMath::Max(2, HeightVox / Cell + 1);
		Out.Cells.SetNumUninitialized(Out.CoarseW * Out.CoarseH);

		// Seed -> a couple of deterministic phase offsets so different seeds give different
		// (but stable) landscapes. Cheap sum of sinusoids: rolling hills + a diagonal ridge.
		const double Ph = static_cast<double>(Seed & 0xFFFF) * 0.0009765625; // seed/1024-ish
		for (int32 z = 0; z < Out.CoarseH; ++z)
		{
			const double Fz = static_cast<double>(z) / static_cast<double>(Out.CoarseH - 1);
			const double Wz = static_cast<double>(R.Min.Y) + Fz * static_cast<double>(HeightVox);
			for (int32 x = 0; x < Out.CoarseW; ++x)
			{
				const double Fx = static_cast<double>(x) / static_cast<double>(Out.CoarseW - 1);
				const double Wx = static_cast<double>(R.Min.X) + Fx * static_cast<double>(WidthVox);

				double V = 0.5
					+ 0.25 * FMath::Sin(Wx * 0.00008 + Ph) * FMath::Cos(Wz * 0.00008 - Ph)
					+ 0.15 * FMath::Sin((Wx + Wz) * 0.00017 + Ph * 2.0);
				V = FMath::Clamp(V, 0.0, 1.0);
				Out.Cells[z * Out.CoarseW + x] = static_cast<float>(V);
			}
		}
		return true;
	};
}

// ---------------------------------------------------------------------------
// Stub provider #2 — drive the path from a captured golden tensor on disk.
// ---------------------------------------------------------------------------
FCoarseDemProvider FDiffusionDemService::MakeGoldenFileStubProvider(const FString& AbsPath,
                                                                    int32 GridW, int32 GridH)
{
	const int32 W = FMath::Max(2, GridW);
	const int32 H = FMath::Max(2, GridH);
	const FString Path = AbsPath;
	// Analytic fallback used if the file can't be read (keeps the path exercisable).
	FCoarseDemProvider Fallback = MakeAnalyticStubProvider();

	return [W, H, Path, Fallback](int64 Seed, const FIntRect& R, FCoarseDem& Out) -> bool
	{
		TArray<uint8> Bytes;
		if (!FFileHelper::LoadFileToArray(Bytes, *Path)
			|| Bytes.Num() < static_cast<int32>(W * H * sizeof(float)))
		{
			UE_LOG(LogMiraDemService, Warning,
				TEXT("[Tdiff] golden DEM '%s' missing/too-small — using analytic stub."), *Path);
			return Fallback(Seed, R, Out);
		}

		// Reinterpret the first W*H float32s (channel 0 of the (1,6,64,64) coarse tensor)
		// as a coarse grid, then normalise to [0,1] so the vertical mapping behaves.
		const float* F = reinterpret_cast<const float*>(Bytes.GetData());
		const int32 N = W * H;
		Out.CoarseW = W;
		Out.CoarseH = H;
		Out.Cells.SetNumUninitialized(N);

		float Lo = F[0], Hi = F[0];
		for (int32 i = 0; i < N; ++i) { Lo = FMath::Min(Lo, F[i]); Hi = FMath::Max(Hi, F[i]); }
		const float Range = Hi - Lo;
		const float Inv = (Range > 1e-8f) ? (1.0f / Range) : 0.0f;
		for (int32 i = 0; i < N; ++i)
		{
			Out.Cells[i] = (Range > 1e-8f) ? (F[i] - Lo) * Inv : 0.5f;
		}
		return true;
	};
}

// ===========================================================================
// PHASE 2 — streaming tile cache (game-thread build, any-thread read).
// See DiffusionDemService.h for the threading model and risk notes.
// ===========================================================================

const FCoarseDem* FDiffusionDemService::EnsureTileResident(int64 Seed, FIntPoint TileCoord)
{
	// GAME THREAD ONLY. Idempotent: a valid cache hit returns the existing DEM as-is.
	const FTileKey Key = MakeTileKey(Seed, TileCoord);
	if (const TSharedPtr<const FCoarseDem>* Found = Tiles.Find(Key))
	{
		if (Found->IsValid() && (*Found)->IsValid())
		{
			return Found->Get();
		}
		// Stale/invalid entry — drop it and rebuild below.
		Tiles.Remove(Key);
	}

	// Cache miss: build the tile's world-voxel rect on the fixed grid and ask the same
	// provider the bounded path uses (Phase 1 = stub; later = AI inference). The build is
	// SYNCHRONOUS on this (game) thread — no background work, per the safety model.
	const int32 Span = FMath::Max(1, TileSpanVoxels);
	// APRON (seamless tiles): generate each tile over its core rect PLUS an overlap into the
	// neighbours, so the height source's bicubic (4x4) + slope (±1) stencil reads REAL neighbour
	// data at tile edges instead of clamping to a border. test_tdiff_streamsource proves tiles
	// then agree to ~1e-13 voxels. ~4 coarse pixels at 300 vox/px; world-positioned noise makes
	// the overlap identical to the neighbour's core, so there is no double-image.
	constexpr int32 ApronVox = 9600; // ~4 coarse cells at 2400 vox/cell (240 m) for edge-stencil context
	const FIntPoint Core(TileCoord.X * Span, TileCoord.Y * Span);
	const FIntPoint Min(Core.X - ApronVox, Core.Y - ApronVox);
	const FIntPoint Max(Core.X + Span + ApronVox, Core.Y + Span + ApronVox);
	const FIntRect TileRect(Min, Max);

	FCoarseDem Dem;
	if (!Provider || !Provider(Seed, TileRect, Dem) || !Dem.IsValid())
	{
		UE_LOG(LogMiraDemService, Warning,
			TEXT("[Tdiff] EnsureTileResident: provider returned no valid DEM for tile "
			     "(%d, %d) rect [%d,%d]..[%d,%d] (seed %lld)."),
			TileCoord.X, TileCoord.Y, Min.X, Min.Y, Max.X, Max.Y,
			static_cast<long long>(Seed));
		return nullptr;
	}

	// Self-describe the georef so the height source samples in this tile's own (apron'd) frame:
	// cell (0,0) sits on the apron'd Min corner; one cell spans (expanded width)/(cells-1) voxels.
	Dem.OriginVoxelX = static_cast<double>(Min.X);
	Dem.OriginVoxelZ = static_cast<double>(Min.Y);
	Dem.VoxelsPerCoarsePixel =
		static_cast<double>(Max.X - Min.X) / static_cast<double>(FMath::Max(1, Dem.CoarseW - 1));

	// Store as TSharedPtr<const> so a concurrent worker read can never mutate it and so a
	// later eviction frees the memory only after the last snapshot holder releases it.
	TSharedPtr<const FCoarseDem> Shared = MakeShared<FCoarseDem>(MoveTemp(Dem));
	Tiles.Add(Key, Shared);

	// Keep the cache bounded; never evict the tile we just made resident.
	EvictTilesIfNeeded(Key);

	return Shared.Get();
}

TSharedPtr<const FCoarseDem> FDiffusionDemService::GetResidentTile(int64 Seed, FIntPoint TileCoord) const
{
	// ANY THREAD, read-only. Lock-free snapshot read (safe by the temporal-separation
	// invariant documented in the header): returns a TSharedPtr copy or null.
	const FTileKey Key = MakeTileKey(Seed, TileCoord);
	if (const TSharedPtr<const FCoarseDem>* Found = Tiles.Find(Key))
	{
		return *Found;
	}
	return nullptr;
}

bool FDiffusionDemService::HighestResidentLand(int64 Seed, double& OutWorldX, double& OutWorldZ,
                                               double& OutHeightVoxels) const
{
	bool bFound = false;
	double BestH = -1.0;
	for (const TPair<FTileKey, TSharedPtr<const FCoarseDem>>& Pair : Tiles)
	{
		if (Pair.Key.Seed != Seed) { continue; }
		const TSharedPtr<const FCoarseDem>& T = Pair.Value;
		if (!T.IsValid() || !T->IsValid() || !T->HasGeoref()) { continue; }
		const FCoarseDem& Dem = *T;
		const int32 N = Dem.Cells.Num();
		for (int32 i = 0; i < N; ++i)
		{
			const double H = TileVoxelHeightAtCell(Dem, i);
			if (H > BestH)
			{
				BestH = H;
				const int32 Cx = i % Dem.CoarseW;
				const int32 Cz = i / Dem.CoarseW;
				OutWorldX = Dem.OriginVoxelX + static_cast<double>(Cx) * Dem.VoxelsPerCoarsePixel;
				OutWorldZ = Dem.OriginVoxelZ + static_cast<double>(Cz) * Dem.VoxelsPerCoarsePixel;
				OutHeightVoxels = H;
				bFound = true;
			}
		}
	}
	return bFound;
}

void FDiffusionDemService::EvictTilesIfNeeded(const FTileKey& KeepKey)
{
	// Drop the farthest-from-focus tile until the cache is back within budget. Never
	// evict the focus tile, its 8-neighbour ring, or the tile we just added (KeepKey).
	while (Tiles.Num() > FMath::Max(1, MaxResidentTiles))
	{
		FTileKey FarKey;
		double   FarDistSq = -1.0;
		bool     bFound    = false;

		for (const TPair<FTileKey, TSharedPtr<const FCoarseDem>>& Pair : Tiles)
		{
			const FTileKey& K = Pair.Key;

			const int32 Dx = K.Tx - TileFocus.X;
			const int32 Dz = K.Tz - TileFocus.Y;
			if (FMath::Abs(Dx) <= 1 && FMath::Abs(Dz) <= 1)
			{
				continue; // focus tile + its 8-neighbour ring are protected
			}
			if (K == KeepKey)
			{
				continue; // never evict the tile EnsureTileResident just added
			}

			const double DistSq = static_cast<double>(Dx) * Dx + static_cast<double>(Dz) * Dz;
			if (DistSq > FarDistSq)
			{
				FarDistSq = DistSq;
				FarKey    = K;
				bFound    = true;
			}
		}

		if (!bFound)
		{
			break; // everything left is protected — can't shrink further this call
		}
		Tiles.Remove(FarKey);
	}
}

// ===========================================================================
// PHASE 4 — ASYNC (off-game-thread) tile generation. Everything below is inert
// unless bAsyncTileGen == true; the synchronous EnsureTileResident path above is
// completely untouched. See the header for the threading invariant + safety notes.
// ===========================================================================

FDiffusionDemService::~FDiffusionDemService()
{
	// Block on any in-flight background job so a worker can never touch this object (or the
	// provider it captured) after we're destroyed. Cheap no-op when nothing is async.
	DrainTiles();
}

// Shared build core for the ASYNC path only. Byte-for-byte the same rect/apron/georef logic the
// synchronous EnsureTileResident uses — deliberately DUPLICATED (not refactored into the sync
// path) so the proven synchronous function stays untouched. Runs on a background thread under
// ProviderLock; touches only `Provider` + locals.
bool FDiffusionDemService::BuildTileDemAsync(int64 Seed, FIntPoint TileCoord, FCoarseDem& OutDem) const
{
	const int32 Span = FMath::Max(1, TileSpanVoxels);
	// APRON: keep IDENTICAL to EnsureTileResident (1200 vox = ~4 coarse pixels at 300 vox/px) so
	// async-built tiles are bit-identical to sync-built ones (the seam test's apron guarantee).
	constexpr int32 ApronVox = 9600; // ~4 coarse cells at 2400 vox/cell (240 m) for edge-stencil context
	const FIntPoint Core(TileCoord.X * Span, TileCoord.Y * Span);
	const FIntPoint Min(Core.X - ApronVox, Core.Y - ApronVox);
	const FIntPoint Max(Core.X + Span + ApronVox, Core.Y + Span + ApronVox);
	const FIntRect TileRect(Min, Max);

	if (!Provider || !Provider(Seed, TileRect, OutDem) || !OutDem.IsValid())
	{
		UE_LOG(LogMiraDemService, Warning,
			TEXT("[Tdiff] RequestTile(async): provider returned no valid DEM for tile "
			     "(%d, %d) rect [%d,%d]..[%d,%d] (seed %lld)."),
			TileCoord.X, TileCoord.Y, Min.X, Min.Y, Max.X, Max.Y,
			static_cast<long long>(Seed));
		return false;
	}

	// Self-describe the georef in the tile's own (apron'd) frame — identical to EnsureTileResident.
	OutDem.OriginVoxelX = static_cast<double>(Min.X);
	OutDem.OriginVoxelZ = static_cast<double>(Min.Y);
	OutDem.VoxelsPerCoarsePixel =
		static_cast<double>(Max.X - Min.X) / static_cast<double>(FMath::Max(1, OutDem.CoarseW - 1));
	return true;
}

void FDiffusionDemService::RequestTile(int64 Seed, FIntPoint TileCoord)
{
	// GAME THREAD, non-blocking. If async is off, behave exactly like the proven sync path so a
	// caller can invoke RequestTile unconditionally and get the current behaviour when the flag
	// is false.
	if (!bAsyncTileGen)
	{
		EnsureTileResident(Seed, TileCoord);
		return;
	}

	const FTileKey Key = MakeTileKey(Seed, TileCoord);

	// Already resident? (Tiles is written only on the game thread; this IS the game thread.)
	if (const TSharedPtr<const FCoarseDem>* Found = Tiles.Find(Key))
	{
		if (Found->IsValid() && (*Found)->IsValid())
		{
			return;
		}
	}

	// Reserve an in-flight slot (or bail if already in flight / at the cap). Snapshot the epoch so
	// the finished job can be dropped if a reseed happens while it runs.
	uint32 Epoch = 0;
	{
		FScopeLock Lock(&AsyncStateLock);
		if (InFlightTiles.Contains(Key))
		{
			return; // already being built
		}
		if (InFlightTiles.Num() >= FMath::Max(1, MaxTileJobsInFlight))
		{
			return; // at capacity — the streamer retries next tick
		}
		InFlightTiles.Add(Key);
		Epoch = TileEpoch;
	}

	// Launch on a DEDICATED background thread. Deliberately EAsyncExecution::Thread, NOT
	// ::ThreadPool — the voxel column generator uses the global thread pool and we must never
	// share it (the never-broken rule from the Phase-2 design). Capturing `this` is safe because
	// the destructor (DrainTiles) blocks until this job has cleared InFlightTiles.
	Async(EAsyncExecution::Thread, [this, Seed, TileCoord, Key, Epoch]()
	{
		FCoarseDem Dem;
		bool bOk = false;
		{
			// Serialise provider access: the provider (DirectML inference) is single-threaded by
			// contract, so at most one background job is ever inside it at a time even at cap 2.
			FScopeLock ProvLock(&ProviderLock);
			bOk = BuildTileDemAsync(Seed, TileCoord, Dem);
		}

		// Wrap as TSharedPtr<const> off-thread (pure allocation, no shared state) so the game
		// thread only has to move a pointer during HarvestTiles.
		TSharedPtr<const FCoarseDem> Shared =
			bOk ? TSharedPtr<const FCoarseDem>(MakeShared<FCoarseDem>(MoveTemp(Dem))) : nullptr;

		// Publish the result (or just clear the in-flight slot on failure). After this scope the
		// lambda touches `this` no further, so once InFlightTiles is empty DrainTiles is free to go.
		FScopeLock Lock(&AsyncStateLock);
		InFlightTiles.Remove(Key);
		if (bOk)
		{
			CompletedTiles.Add(FCompletedTile{ Key, Shared, Epoch });
		}
	});
}

int32 FDiffusionDemService::HarvestTiles(int32 Budget)
{
	// GAME THREAD ONLY — this is the sole writer of the resident `Tiles` map in the async path.
	if (Budget <= 0)
	{
		return 0;
	}

	// Pull the whole completed queue out under the lock (cheap: pointers only), plus the current
	// epoch so we can drop stale results. We re-queue anything we don't promote this tick.
	TArray<FCompletedTile> Ready;
	uint32 CurrentEpoch = 0;
	{
		FScopeLock Lock(&AsyncStateLock);
		if (CompletedTiles.Num() == 0)
		{
			return 0;
		}
		Ready = MoveTemp(CompletedTiles);
		CompletedTiles.Reset();
		CurrentEpoch = TileEpoch;
	}

	// Nearest-to-focus first, so tiles under the player win the budget over far ones.
	const FIntPoint Focus = TileFocus;
	Ready.Sort([Focus](const FCompletedTile& A, const FCompletedTile& B)
	{
		const int64 Adx = A.Key.Tx - Focus.X, Adz = A.Key.Tz - Focus.Y;
		const int64 Bdx = B.Key.Tx - Focus.X, Bdz = B.Key.Tz - Focus.Y;
		return (Adx * Adx + Adz * Adz) < (Bdx * Bdx + Bdz * Bdz);
	});

	int32 Made = 0;
	TArray<FCompletedTile> Requeue;
	for (FCompletedTile& C : Ready)
	{
		// Reseed happened after this job started -> stale, drop it (never installs).
		if (C.Epoch != CurrentEpoch)
		{
			continue;
		}
		if (Made >= Budget)
		{
			Requeue.Add(MoveTemp(C)); // over budget this tick — try again next tick
			continue;
		}
		if (!C.Dem.IsValid() || !C.Dem->IsValid())
		{
			continue; // defensive: a null/invalid DEM is simply dropped
		}

		// Promote onto the resident map (game-thread write — the invariant) and keep it bounded.
		Tiles.Add(C.Key, C.Dem);
		EvictTilesIfNeeded(C.Key);
		++Made;
	}

	// Return the leftovers to the queue for next tick (preserving them).
	if (Requeue.Num() > 0)
	{
		FScopeLock Lock(&AsyncStateLock);
		CompletedTiles.Append(MoveTemp(Requeue));
	}

	return Made;
}

void FDiffusionDemService::DrainTiles()
{
	// Bump the epoch + drop parked results first, so anything that finishes DURING the wait is
	// stamped stale and can never install.
	{
		FScopeLock Lock(&AsyncStateLock);
		++TileEpoch;
		CompletedTiles.Reset();
	}

	// Block until every in-flight background job has cleared its slot. Jobs are ~1.6 s of GPU
	// work; teardown is rare, so a short poll is fine (no game-thread work depends on precision).
	for (;;)
	{
		{
			FScopeLock Lock(&AsyncStateLock);
			if (InFlightTiles.Num() == 0)
			{
				break;
			}
		}
		FPlatformProcess::Sleep(0.005f);
	}

	// Now safe to clear everything — no worker is running.
	Tiles.Empty();
	{
		FScopeLock Lock(&AsyncStateLock);
		CompletedTiles.Reset();
	}
}

int32 FDiffusionDemService::NumTileJobsInFlight() const
{
	FScopeLock Lock(&AsyncStateLock);
	return InFlightTiles.Num();
}

void FDiffusionDemService::ClearTiles()
{
	// Reseed/teardown WITHOUT blocking on in-flight inference. Bump the epoch + drop parked
	// results so a job that finished before this call can't be harvested onto the new seed, then
	// clear the resident map (game thread — the map's only writer). In-flight jobs keep running
	// but their results are now stale-epoch and will be discarded by HarvestTiles; a full block-
	// and-clear teardown is DrainTiles() (also run by the destructor).
	{
		FScopeLock Lock(&AsyncStateLock);
		++TileEpoch;
		CompletedTiles.Reset();
	}
	Tiles.Empty();
}
