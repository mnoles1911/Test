// VoxelWorld.cpp — M2 multi-chunk world: generate + carve + re-mesh.
//                  M3 adds an imported-EXR terrain source (see ConfigureGenerator).
#include "VoxelWorld.h"
#include "VoxelChunkActor.h"
#include "HeightmapImport.h"          // MiraHeightmapImport::LoadHeightmapImage
#include "Engine/World.h"
#include "Materials/MaterialInterface.h"
#include "Misc/Paths.h"

// Engine-agnostic Core (no Unreal types below this line's logic).
#include "Core/MiraVec.h"            // Vec3i, Vec3
#include "Core/ChunkCoords.h"        // coords::CHUNK, floor_div, chunk_origin_voxel
#include "Core/VoxelChunk.h"         // DenseGrid, APRON
#include "Core/Brickmap.h"           // Brickmap (authoritative store)
#include "Core/BrickmapMeshing.h"    // extract_mesh_slab, apply_writes, affected_chunks
#include "Core/HeightmapGenerator.h" // HeightmapGenerator, ColumnInfo
#include "Core/MaterialIds.h"        // mat::*
#include "Core/WaterByteCodec.h"     // WaterByteCodec::SOURCE_BYTE
#include "Core/MiningCarve.h"        // mining::compute_carve_box / compute_carve, VoxelWrite

AVoxelWorld::AVoxelWorld()
{
	PrimaryActorTick.bCanEverTick = false;
}

void AVoxelWorld::BeginPlay()
{
	Super::BeginPlay();
	// Auto-build the world when play starts if nothing has been generated yet.
	if (ChunkActors.Num() == 0)
	{
		GenerateWorld();
	}
}

void AVoxelWorld::EndPlay(const EEndPlayReason::Type Reason)
{
	ClearWorld();
	Super::EndPlay(Reason);
}

// ---------------------------------------------------------------------------
// Generation: fill the brickmap from the Core generator, then mesh each chunk.
// ---------------------------------------------------------------------------
void AVoxelWorld::GenerateWorld()
{
	ClearWorld();
	LoadHeightmapIfNeeded();
	GenerateRegion();
}

// ---------------------------------------------------------------------------
// Terrain source plumbing (M3): load the EXR + build a configured generator.
// ---------------------------------------------------------------------------
bool AVoxelWorld::LoadHeightmapIfNeeded()
{
	ImportedHeightmap = mira::ImageHeightmap(); // reset to invalid each (re)generate
	if (HeightSource != EVoxelHeightSource::HeightmapEXR)
	{
		return true; // procedural path needs no image
	}

	// Resolve the path (allow project-relative entries for convenience).
	FString Path = HeightmapFile.FilePath;
	if (!Path.IsEmpty() && FPaths::IsRelative(Path))
	{
		Path = FPaths::ConvertRelativePathToFull(FPaths::ProjectDir(), Path);
	}

	FString LoadError;
	if (Path.IsEmpty() || !MiraHeightmapImport::LoadHeightmapImage(Path, ImportedHeightmap, LoadError))
	{
		UE_LOG(LogTemp, Error,
			TEXT("[MiraThal] EXR heightmap load failed (%s) — falling back to procedural."),
			Path.IsEmpty() ? TEXT("no file set") : *LoadError);
		ImportedHeightmap = mira::ImageHeightmap();
		return false;
	}

	// Apply georeferencing from the designer knobs. 10 voxels per metre is the
	// world scale (VoxelScale single source of truth). A 5 km map => 50,000 voxels.
	constexpr double VoxelsPerMetre = 10.0;
	const double SpanVoxels = static_cast<double>(MapSpanMeters) * VoxelsPerMetre;
	ImportedHeightmap.set_centered_extent(SpanVoxels, SpanVoxels);
	ImportedHeightmap.vertical_scale_voxels = static_cast<double>(HeightmapAltitudeMeters) * VoxelsPerMetre;
	ImportedHeightmap.vertical_base_voxels  = static_cast<double>(HeightmapBaseMeters) * VoxelsPerMetre;
	ImportedHeightmap.flip_z = bFlipHeightmapZ;

	UE_LOG(LogTemp, Display,
		TEXT("[MiraThal] EXR heightmap loaded: %dx%d px over %.0f m (%.1f vox/px), "
		     "altitude %.0f m, base %.0f m."),
		ImportedHeightmap.width, ImportedHeightmap.height, MapSpanMeters,
		ImportedHeightmap.voxels_per_pixel, HeightmapAltitudeMeters, HeightmapBaseMeters);
	return true;
}

void AVoxelWorld::ConfigureGenerator(mira::HeightmapGenerator& Gen) const
{
	Gen.set_seed(static_cast<int64_t>(Seed));
	Gen.height_range_voxels  = MacroRangeVoxels;
	Gen.mid_amplitude_voxels = MidAmplitudeVoxels;
	Gen.height_offset_voxels = HeightOffsetVoxels;
	Gen.macro_frequency      = MacroFrequency;

	// Attach the imported surface when in EXR mode and it loaded successfully.
	// compute_ground_y then reads the EXR and the banding/water/flora follow.
	if (HeightSource == EVoxelHeightSource::HeightmapEXR && ImportedHeightmap.valid())
	{
		Gen.set_height_source(&ImportedHeightmap);
	}
}

void AVoxelWorld::GenerateRegion()
{
	using namespace mira;

	Brickmap& BM = WorldStore;

	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);

	// Dig floor: fill from this Y up. Anchored to the centre surface so the band
	// has a consistent bottom; the TOP is discovered per-column (terrain amplitude
	// is large, so we mesh the real ground range rather than a fixed band — no
	// clipped peaks, no valley holes).
	const int GroundCentre = Gen.compute_ground_y(0, 0);
	const int SurfChunkY   = coords::floor_div(GroundCentre, coords::CHUNK);
	const int YBottomVoxel = (SurfChunkY - ChunkDepthBelow) * coords::CHUNK;

	// Track the actual filled vertical extent so we mesh exactly the populated band.
	int FilledMaxY = YBottomVoxel;
	int FilledMinY = GroundCentre;

	// --- Fill: one resolve_column per (wx,wz), then a vertical sweep. ---
	for (int ccx = -ChunkRadiusXZ; ccx <= ChunkRadiusXZ; ++ccx)
	for (int ccz = -ChunkRadiusXZ; ccz <= ChunkRadiusXZ; ++ccz)
	{
		const Vec3i ChunkOrigin = coords::chunk_origin_voxel(Vec3i(ccx, 0, ccz));
		for (int lx = 0; lx < coords::CHUNK; ++lx)
		for (int lz = 0; lz < coords::CHUNK; ++lz)
		{
			const int wx = ChunkOrigin.x + lx;
			const int wz = ChunkOrigin.z + lz;
			const ColumnInfo Col = Gen.resolve_column(wx, wz);

			// Solid column from the dig floor up to the surface.
			for (int wy = YBottomVoxel; wy <= Col.ground_y; ++wy)
			{
				const int Id = Gen.material_at(wx, wy, wz, Col);
				if (Id != mat::AIR)
				{
					BM.set_type(Vec3i(wx, wy, wz), static_cast<uint8_t>(Id));
				}
			}
			FilledMaxY = FMath::Max(FilledMaxY, Col.ground_y + 1);
			FilledMinY = FMath::Min(FilledMinY, Col.ground_y);

			// Water fills air below sea level for dipped columns.
			if (Col.below_sea)
			{
				for (int wy = Col.ground_y + 1; wy <= Gen.sea_level_voxels; ++wy)
				{
					BM.set_water(Vec3i(wx, wy, wz), static_cast<uint8_t>(WaterByteCodec::SOURCE_BYTE));
				}
				FilledMaxY = FMath::Max(FilledMaxY, Gen.sea_level_voxels);
			}

			// One flora/detail voxel sitting on the surface, if the column has one.
			if (Col.flora_id != 0)
			{
				BM.set_type(Vec3i(wx, Col.ground_y + 1, wz), static_cast<uint8_t>(Col.flora_id));
			}
		}
	}

	// --- Mesh every chunk across the real filled band (empties skipped). ---
	const int ChunkYLo = coords::floor_div(YBottomVoxel, coords::CHUNK);
	const int ChunkYHi = coords::floor_div(FilledMaxY, coords::CHUNK);
	for (int ccx = -ChunkRadiusXZ; ccx <= ChunkRadiusXZ; ++ccx)
	for (int ccz = -ChunkRadiusXZ; ccz <= ChunkRadiusXZ; ++ccz)
	for (int ccy = ChunkYLo; ccy <= ChunkYHi; ++ccy)
	{
		RemeshChunk(FIntVector(ccx, ccy, ccz));
	}
	(void)FilledMinY;
}

// ---------------------------------------------------------------------------
// Editing: carve writes -> brickmap -> re-mesh only the touched chunks.
// ---------------------------------------------------------------------------
void AVoxelWorld::CarveTestHole()
{
	using namespace mira;

	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);
	const int GroundCentre = Gen.compute_ground_y(0, 0);

	// Dig a Full (5^3) box straight down into the surface at the world centre.
	const Vec3i Centre(0, GroundCentre, 0);
	const Vec3  Down(0.0f, 1.0f, 0.0f); // surface normal points up (Core Y-up)
	const mining::CarveBox Box =
		mining::compute_carve_box(Centre, Down, mining::DEFAULT_FULL_SIZE, mining::MiningAnchor::DepthBiased);

	std::vector<VoxelWrite> Writes = mining::compute_carve(Box);
	apply_writes(WorldStore, Writes);

	for (const Vec3i& C : affected_chunks(Writes))
	{
		RemeshChunk(FIntVector(C.x, C.y, C.z));
	}
}

void AVoxelWorld::CarveAtWorld(const FVector& WorldPos, const FVector& HitNormal, int32 SideVoxels)
{
	using namespace mira;

	// UE world (cm) -> Core voxel. Inverse of MiraVoxelMesh::PositionToUE
	// (px,py,pz) -> FVector(px, pz, py) * 10:  px = X/10, py = Z/10, pz = Y/10.
	const FVector Local = WorldPos - GetActorLocation();
	const Vec3i CentreVoxel(
		FMath::FloorToInt(Local.X / 10.0f),
		FMath::FloorToInt(Local.Z / 10.0f),
		FMath::FloorToInt(Local.Y / 10.0f));
	// Normal swaps the same way (Y/Z) but isn't scaled.
	const Vec3 CoreNormal(HitNormal.X, HitNormal.Z, HitNormal.Y);

	const mining::CarveBox Box =
		mining::compute_carve_box(CentreVoxel, CoreNormal, SideVoxels, mining::MiningAnchor::DepthBiased);

	std::vector<VoxelWrite> Writes = mining::compute_carve(Box);
	apply_writes(WorldStore, Writes);

	for (const Vec3i& C : affected_chunks(Writes))
	{
		RemeshChunk(FIntVector(C.x, C.y, C.z));
	}
}

// ---------------------------------------------------------------------------
// Per-chunk render: extract the apron'd slab, skip if empty, else hand to actor.
// ---------------------------------------------------------------------------
void AVoxelWorld::RemeshChunk(const FIntVector& ChunkCoord)
{
	using namespace mira;

	const Vec3i Coord(ChunkCoord.X, ChunkCoord.Y, ChunkCoord.Z);
	DenseGrid Slab = extract_mesh_slab(WorldStore, Coord);

	// Is the inner (non-apron) region empty? If so, no mesh — drop any old actor.
	bool bHasContent = false;
	for (int z = APRON; z < APRON + coords::CHUNK && !bHasContent; ++z)
	for (int y = APRON; y < APRON + coords::CHUNK && !bHasContent; ++y)
	for (int x = APRON; x < APRON + coords::CHUNK && !bHasContent; ++x)
	{
		if (Slab.type_at(x, y, z) != mat::AIR || Slab.water_at(x, y, z) != 0)
		{
			bHasContent = true;
		}
	}

	if (!bHasContent)
	{
		DestroyChunkActor(ChunkCoord);
		return;
	}

	AVoxelChunkActor* Actor = EnsureChunkActor(ChunkCoord);
	if (Actor)
	{
		Actor->RenderManaged(Slab, TerrainMaterial, WaterMaterial, FloraMaterial,
		                     bCreateCollision, /*bReverse=*/false);
	}
}

// ---------------------------------------------------------------------------
// Chunk actor lifecycle + placement.
// ---------------------------------------------------------------------------
FVector AVoxelWorld::ChunkActorLocation(const FIntVector& ChunkCoord) const
{
	// The slab's cell (0,0,0) is world voxel (chunk_origin - APRON). Map that voxel
	// to UE via PositionToUE: (vx,vy,vz) -> (vx, vz, vy) * 10. So neighbours tile
	// seamlessly (the +APRON shift the mesher bakes in is cancelled here).
	const int32 Ox = ChunkCoord.X * mira::coords::CHUNK - mira::APRON;
	const int32 Oy = ChunkCoord.Y * mira::coords::CHUNK - mira::APRON;
	const int32 Oz = ChunkCoord.Z * mira::coords::CHUNK - mira::APRON;
	const float U  = 10.0f; // 1 voxel = 10 UE units (10 cm)
	return GetActorLocation() + FVector(Ox * U, Oz * U, Oy * U);
}

AVoxelChunkActor* AVoxelWorld::EnsureChunkActor(const FIntVector& ChunkCoord)
{
	if (TObjectPtr<AVoxelChunkActor>* Found = ChunkActors.Find(ChunkCoord))
	{
		return *Found;
	}

	UWorld* W = GetWorld();
	if (!W)
	{
		return nullptr;
	}

	const FTransform Xform(ChunkActorLocation(ChunkCoord));
	AVoxelChunkActor* Actor = W->SpawnActorDeferred<AVoxelChunkActor>(
		AVoxelChunkActor::StaticClass(), Xform, this);
	if (!Actor)
	{
		return nullptr;
	}
	Actor->bWorldManaged = true;       // suppress the standalone self-build
	Actor->FinishSpawning(Xform);
#if WITH_EDITOR
	Actor->SetActorLabel(FString::Printf(TEXT("Chunk_%d_%d_%d"),
		ChunkCoord.X, ChunkCoord.Y, ChunkCoord.Z));
#endif
	ChunkActors.Add(ChunkCoord, Actor);
	return Actor;
}

void AVoxelWorld::DestroyChunkActor(const FIntVector& ChunkCoord)
{
	if (TObjectPtr<AVoxelChunkActor>* Found = ChunkActors.Find(ChunkCoord))
	{
		if (AVoxelChunkActor* Actor = *Found)
		{
			Actor->Destroy();
		}
		ChunkActors.Remove(ChunkCoord);
	}
}

void AVoxelWorld::ClearWorld()
{
	for (TPair<FIntVector, TObjectPtr<AVoxelChunkActor>>& Pair : ChunkActors)
	{
		if (AVoxelChunkActor* Actor = Pair.Value)
		{
			Actor->Destroy();
		}
	}
	ChunkActors.Empty();

	// Reset the authoritative store (default-constructed brickmap = empty).
	WorldStore = mira::Brickmap();
}
