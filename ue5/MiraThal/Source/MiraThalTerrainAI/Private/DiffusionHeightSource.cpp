// DiffusionHeightSource.cpp — streaming IHeightSource over FDiffusionDemService's tile cache.
// See DiffusionHeightSource.h for the design + threading model.

#include "DiffusionHeightSource.h"
#include "DiffusionDemService.h"   // FDiffusionDemService + FCoarseDem + kMaxSurfaceVoxels

#include <cmath>                   // std::floor

namespace mira {

DiffusionHeightSource::DiffusionHeightSource(const FDiffusionDemService* InSvc, int64 InSeed,
                                             mira::tdiff::DetailBridgeParams InDetail,
                                             double InVerticalScaleVoxels, double InVerticalBaseVoxels,
                                             int32 InTileSpanVoxels)
	: Svc(InSvc)
	, Seed(InSeed)
	, Detail(InDetail)
	, VerticalScaleVoxels(InVerticalScaleVoxels)
	, VerticalBaseVoxels(InVerticalBaseVoxels)
	, TileSpanVoxels(InTileSpanVoxels > 0 ? InTileSpanVoxels : 1)
{
	// Fix the detail field's seed to the world seed, EXACTLY as BuildHeightmapFromCoarse
	// does (`Params.seed = Seed`). This makes the streaming fBm field bit-identical to the
	// bounded path's and keeps it continuous across tile boundaries (it is world-keyed).
	Detail.seed = static_cast<int64_t>(Seed);
}

bool DiffusionHeightSource::valid() const
{
	// Ready to sample once the service is set. Per-tile residency is guaranteed upstream
	// (the game thread makes tiles resident before enqueuing the columns that read them).
	return Svc != nullptr;
}

double DiffusionHeightSource::SampleContinuous(int WorldX, int WorldZ) const
{
	// SAFE FALLBACK: a flat, clamped base height. Returned whenever we cannot sample a
	// real tile so we NEVER produce a hole/NaN (design risk R4). Uses the SAME clamp the
	// metres->voxel conversion uses, with sea level anchored at VerticalBaseVoxels.
	const double Fallback =
		FMath::Clamp(VerticalBaseVoxels, 0.0, FDiffusionDemService::kMaxSurfaceVoxels);

	if (Svc == nullptr)
	{
		return Fallback;
	}

	// 1) Which tile covers this column? (Same floor-div the streamer used on the game
	//    thread to make the tile resident, so we look up the right one.)
	const FIntPoint TileCoord =
		FDiffusionDemService::TileCoordOf(WorldX, WorldZ, TileSpanVoxels);

	// 2) Grab the resident coarse DEM as a snapshot (null if not resident).
	const TSharedPtr<const FCoarseDem> Tile = Svc->GetResidentTile(Seed, TileCoord);
	if (!Tile.IsValid() || !Tile->IsValid())
	{
		return Fallback; // tile missing — degrade to flat, never a hole
	}
	const FCoarseDem& Dem = *Tile;

	// 3) Convert the tile's normalised coarse cells into ABSOLUTE VOXEL HEIGHTS using the
	//    EXACT same formula + clamp as BuildHeightmapFromCoarse (risk R9):
	//        voxelY = clamp(VerticalBaseVoxels + cell * VerticalScaleVoxels, 0, kMaxSurfaceVoxels)
	//    The bridge sampler wants a contiguous float* of voxel heights. To avoid a heap
	//    allocation on every column, reuse a per-thread scratch buffer (workers each have
	//    their own; sampling is read-only so there is no cross-thread sharing).
	static thread_local TArray<float> Scratch;
	const int32 N = Dem.Cells.Num();
	Scratch.SetNumUninitialized(N);
	for (int32 i = 0; i < N; ++i)
	{
		const double Y =
			VerticalBaseVoxels + static_cast<double>(Dem.Cells[i]) * VerticalScaleVoxels;
		Scratch[i] =
			static_cast<float>(FMath::Clamp(Y, 0.0, FDiffusionDemService::kMaxSurfaceVoxels));
	}

	// 4) Tile georef. Prefer the tile's SELF-DESCRIBING georef (set by EnsureTileResident),
	//    which accounts for the tile's APRON (overlap into neighbours) so the bicubic/slope
	//    stencil reads real neighbour data at edges -> seamless tiles (test_tdiff_streamsource).
	//    Fall back to the apron-free derivation for any tile produced without a georef.
	double OriginX, OriginZ, CoarsePitch;
	if (Dem.HasGeoref())
	{
		OriginX     = Dem.OriginVoxelX;
		OriginZ     = Dem.OriginVoxelZ;
		CoarsePitch = Dem.VoxelsPerCoarsePixel;
	}
	else
	{
		OriginX = static_cast<double>(static_cast<int64>(TileCoord.X) * static_cast<int64>(TileSpanVoxels));
		OriginZ = static_cast<double>(static_cast<int64>(TileCoord.Y) * static_cast<int64>(TileSpanVoxels));
		CoarsePitch = static_cast<double>(TileSpanVoxels) / static_cast<double>(Dem.CoarseW - 1);
	}

	// 5) Run the SAME bridge the bounded path runs. (Detail.seed was fixed to Seed in the
	//    ctor.) Returns the continuous ground height in voxels; the caller floors it.
	return mira::tdiff::sample_height_voxels(
		Scratch.GetData(), Dem.CoarseW, Dem.CoarseH,
		OriginX, OriginZ, CoarsePitch,
		WorldX, WorldZ, Detail);
}

float DiffusionHeightSource::sample_value(double world_x, double world_z) const
{
	// The same pre-floor height as a float. A voxel column is integer-addressed, so floor
	// the (possibly fractional) request to the covering column before sampling.
	const int WX = static_cast<int>(std::floor(world_x));
	const int WZ = static_cast<int>(std::floor(world_z));
	return static_cast<float>(SampleContinuous(WX, WZ));
}

int DiffusionHeightSource::height_voxels_at(int world_x, int world_z) const
{
	// floor() the continuous height so material banding sits exactly on the surface,
	// matching ImageHeightmap's height_voxels_at contract.
	return static_cast<int>(std::floor(SampleContinuous(world_x, world_z)));
}

} // namespace mira
