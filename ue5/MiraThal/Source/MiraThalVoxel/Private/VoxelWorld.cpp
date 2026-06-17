// VoxelWorld.cpp — M2 multi-chunk world: generate + carve + re-mesh.
//                  M3 adds an imported-EXR terrain source (see ConfigureGenerator).
#include "VoxelWorld.h"
#include "VoxelChunkActor.h"
#include "HeightmapImport.h"          // MiraHeightmapImport::LoadHeightmapImage
#include "WorldEditPersistence.h"     // region delta-file I/O (P2)
#include "Core/RegionFormat.h"        // encode/decode_delta_log (P2)
#include "Engine/World.h"
#include "Materials/MaterialInterface.h"
#include "Misc/Paths.h"
#include "Kismet/GameplayStatics.h"   // GetPlayerPawn (streaming focus)
#include "GameFramework/Pawn.h"
#include <climits>                    // INT_MAX / INT_MIN

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
#include "Core/FiniteWaterCore.h"    // FiniteWaterCore — the dynamic water sim (M3b)
#include "Core/VoxelGravity.h"       // analyze_bubble — gravity-on-dig (M3c)

AVoxelWorld::AVoxelWorld()
{
	// Tickable so streaming can page columns around the focus; the tick is only
	// actually enabled in BeginPlay when bEnableStreaming is set.
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = false;
}

// Out-of-line dtor: TUniquePtr<FiniteWaterCore> needs the complete type to destruct,
// and it's only forward-declared in the header (kept light).
AVoxelWorld::~AVoxelWorld() = default;

void AVoxelWorld::BeginPlay()
{
	Super::BeginPlay();

	if (bEnableStreaming)
	{
		// Streaming owns generation: load the heightmap once, then the tick pages
		// columns in around the focus. Don't pre-build the fixed region.
		LoadHeightmapIfNeeded();
		SetActorTickEnabled(true);
		return;
	}

	// Non-streaming: auto-build the fixed region when play starts if empty.
	if (ChunkActors.Num() == 0)
	{
		GenerateWorld();
	}

	// The water sim also needs ticking (independently of streaming).
	if (bEnableWaterSim)
	{
		EnsureWaterSim();
		SetActorTickEnabled(true);
	}
}

void AVoxelWorld::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (bEnableStreaming)
	{
		TickStreaming();
	}
	if (bEnableWaterSim && WaterSim.IsValid())
	{
		// Fire the sim at WaterSimHz regardless of frame rate (deterministic ticks).
		WaterSimAccum += DeltaSeconds;
		const float Period = 1.0f / FMath::Max(1.0f, WaterSimHz);
		int Steps = 0;
		while (WaterSimAccum >= Period && Steps < 4) // cap catch-up to avoid spirals
		{
			WaterSimAccum -= Period;
			++Steps;
		}
		if (Steps > 0)
		{
			StepWaterSim(Steps, WaterStepBudget);
		}
	}
}

void AVoxelWorld::EndPlay(const EEndPlayReason::Type Reason)
{
	SaveEdits(); // flush the player's journalled edits before tearing down
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
	// Build the fixed preview region. Fill the radius PLUS a one-column skirt so
	// every meshed chunk's 1-voxel apron has real neighbour data (seamless), then
	// mesh only the inner radius.
	const int R = ChunkRadiusXZ;
	for (int ccx = -R - 1; ccx <= R + 1; ++ccx)
	for (int ccz = -R - 1; ccz <= R + 1; ++ccz)
	{
		FillChunkColumn(ccx, ccz);
	}
	for (int ccx = -R; ccx <= R; ++ccx)
	for (int ccz = -R; ccz <= R; ++ccz)
	{
		MeshChunkColumn(ccx, ccz);
	}
}

// ---------------------------------------------------------------------------
// Per-column generation primitives (shared by the fixed region + streaming).
// ---------------------------------------------------------------------------
void AVoxelWorld::FillChunkColumn(int32 ccx, int32 ccz)
{
	using namespace mira;

	const FIntPoint Key(ccx, ccz);
	if (FilledColumns.Contains(Key))
	{
		return; // already generated
	}

	Brickmap& BM = WorldStore;
	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);

	const Vec3i ChunkOrigin = coords::chunk_origin_voxel(Vec3i(ccx, 0, ccz));
	const int DepthVoxels = ChunkDepthBelow * coords::CHUNK; // soil thickness below surface

	int FilledMinY = INT_MAX;
	int FilledMaxY = INT_MIN;

	for (int lx = 0; lx < coords::CHUNK; ++lx)
	for (int lz = 0; lz < coords::CHUNK; ++lz)
	{
		const int wx = ChunkOrigin.x + lx;
		const int wz = ChunkOrigin.z + lz;
		const ColumnInfo Col = Gen.resolve_column(wx, wz);

		// Solid column from a per-column dig floor (follows the terrain) up to the
		// surface. We fill ONE EXTRA CHUNK of solid BELOW the visible floor and do
		// NOT mesh it: that hidden solid is the apron that lets the lowest *visible*
		// chunk cull its underside. Without it, the band's bottom faces (the "dig
		// floor", which mirrors the surface contours) render as a phantom second
		// layer ~DepthVoxels below the surface — the "terrain sandwich". Deeper
		// terrain is generated on demand when the player digs through the floor.
		const int YBottom      = Col.ground_y - DepthVoxels;     // lowest VISIBLE/meshed voxel
		const int YBottomApron = YBottom - coords::CHUNK;        // hidden solid below (apron only)
		for (int wy = YBottomApron; wy <= Col.ground_y; ++wy)
		{
			const int Id = Gen.material_at(wx, wy, wz, Col);
			if (Id != mat::AIR)
			{
				BM.set_type(Vec3i(wx, wy, wz), static_cast<uint8_t>(Id));
			}
		}
		// Mesh range stops at YBottom; the apron chunk below stays filled-but-unmeshed
		// so the floor is hidden, not rendered as a separate layer.
		FilledMinY = FMath::Min(FilledMinY, YBottom);
		FilledMaxY = FMath::Max(FilledMaxY, Col.ground_y + 1);

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

	// P2: replay the player's saved edits for this column on top of the generated
	// terrain (load-on-demand from disk), so a previously-dug hole comes back.
	if (bPersistEdits)
	{
		ApplyEditsToColumn(ccx, ccz);
	}

	// Empty column guard (shouldn't happen on land, but keep the map sane).
	if (FilledMaxY < FilledMinY)
	{
		FilledMinY = FilledMaxY = 0;
	}

	const int ChunkYLo = coords::floor_div(FilledMinY, coords::CHUNK);
	const int ChunkYHi = coords::floor_div(FilledMaxY, coords::CHUNK);
	ColumnYRange.Add(Key, FIntPoint(ChunkYLo, ChunkYHi));
	FilledColumns.Add(Key);
}

void AVoxelWorld::MeshChunkColumn(int32 ccx, int32 ccz)
{
	const FIntPoint Key(ccx, ccz);
	if (MeshedColumns.Contains(Key))
	{
		return;
	}
	const FIntPoint* Range = ColumnYRange.Find(Key);
	if (!Range)
	{
		return; // not filled yet — caller must FillChunkColumn first
	}
	for (int32 ccy = Range->X; ccy <= Range->Y; ++ccy)
	{
		RemeshChunk(FIntVector(ccx, ccy, ccz));
	}
	MeshedColumns.Add(Key);
}

void AVoxelWorld::UnmeshChunkColumn(int32 ccx, int32 ccz)
{
	const FIntPoint Key(ccx, ccz);
	if (!MeshedColumns.Contains(Key))
	{
		return;
	}
	const FIntPoint* Range = ColumnYRange.Find(Key);
	if (Range)
	{
		for (int32 ccy = Range->X; ccy <= Range->Y; ++ccy)
		{
			DestroyChunkActor(FIntVector(ccx, ccy, ccz));
		}
	}
	MeshedColumns.Remove(Key);
}

// ---------------------------------------------------------------------------
// Streaming (M4): page columns in/out around the focus, throttled per tick.
// ---------------------------------------------------------------------------
bool AVoxelWorld::GetFocusChunkXZ(FIntPoint& OutColumn) const
{
	FVector FocusWorld;
	if (StreamFocusActor)
	{
		FocusWorld = StreamFocusActor->GetActorLocation();
	}
	else if (APawn* Pawn = UGameplayStatics::GetPlayerPawn(this, 0))
	{
		FocusWorld = Pawn->GetActorLocation();
	}
	else
	{
		return false; // no focus available yet
	}

	// UE world (cm) -> core voxel XZ. PositionToUE maps core (vx,vy,vz) ->
	// (vx, vz, vy)*10, so UE.X = core-x*10 and UE.Y = core-z*10.
	const FVector Local = FocusWorld - GetActorLocation();
	const int vx = FMath::FloorToInt(Local.X / 10.0f);
	const int vz = FMath::FloorToInt(Local.Y / 10.0f);
	OutColumn = FIntPoint(mira::coords::floor_div(vx, mira::coords::CHUNK),
	                      mira::coords::floor_div(vz, mira::coords::CHUNK));
	return true;
}

void AVoxelWorld::TickStreaming()
{
	FIntPoint Focus;
	if (!GetFocusChunkXZ(Focus))
	{
		return;
	}

	const int R = StreamRadiusChunks;
	int Budget = MaxColumnOpsPerTick;

	// 1) FILL the radius + 1-column skirt (nearest-first), so meshed aprons are
	//    satisfied. Throttled by the per-tick budget.
	for (int ring = 0; ring <= R + 1 && Budget > 0; ++ring)
	{
		for (int dx = -ring; dx <= ring && Budget > 0; ++dx)
		for (int dz = -ring; dz <= ring && Budget > 0; ++dz)
		{
			// Only the shell at chebyshev distance == ring (inner shells done already).
			if (FMath::Max(FMath::Abs(dx), FMath::Abs(dz)) != ring)
			{
				continue;
			}
			const FIntPoint Col(Focus.X + dx, Focus.Y + dz);
			if (!FilledColumns.Contains(Col))
			{
				FillChunkColumn(Col.X, Col.Y);
				--Budget;
			}
		}
	}

	// 2) MESH the inner radius (nearest-first) for columns whose skirt is filled.
	for (int ring = 0; ring <= R && Budget > 0; ++ring)
	{
		for (int dx = -ring; dx <= ring && Budget > 0; ++dx)
		for (int dz = -ring; dz <= ring && Budget > 0; ++dz)
		{
			if (FMath::Max(FMath::Abs(dx), FMath::Abs(dz)) != ring)
			{
				continue;
			}
			const FIntPoint Col(Focus.X + dx, Focus.Y + dz);
			if (FilledColumns.Contains(Col) && !MeshedColumns.Contains(Col))
			{
				MeshChunkColumn(Col.X, Col.Y);
				--Budget;
			}
		}
	}

	// 3) EVICT meshed columns that drifted beyond radius + hysteresis. (Brick data
	//    is kept for now; CPU-store eviction is a follow-up — see UE5_TECH_STACK.)
	const int EvictDist = R + StreamEvictPaddingChunks;
	TArray<FIntPoint> ToEvict;
	for (const FIntPoint& Col : MeshedColumns)
	{
		const int d = FMath::Max(FMath::Abs(Col.X - Focus.X), FMath::Abs(Col.Y - Focus.Y));
		if (d > EvictDist)
		{
			ToEvict.Add(Col);
		}
	}
	for (const FIntPoint& Col : ToEvict)
	{
		UnmeshChunkColumn(Col.X, Col.Y);
	}
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

	// Journal each carved voxel's final state so the dig survives reload (P2).
	if (bPersistEdits)
	{
		for (const VoxelWrite& W : Writes) { RecordEdit(W.pos); }
	}

	for (const Vec3i& C : affected_chunks(Writes))
	{
		RemeshChunk(FIntVector(C.x, C.y, C.z));
	}

	// If the dig opened space next to water, let the parent volume flood in.
	FloodCarveFromNeighbours(Writes);

	// Drop any loose material that lost its support.
	ApplyGravityAfterCarve(Centre);
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

	// Journal each carved voxel's final state so the dig survives reload (P2).
	if (bPersistEdits)
	{
		for (const VoxelWrite& W : Writes) { RecordEdit(W.pos); }
	}

	for (const Vec3i& C : affected_chunks(Writes))
	{
		RemeshChunk(FIntVector(C.x, C.y, C.z));
	}

	// If the dig opened space next to water, let the parent volume flood in.
	FloodCarveFromNeighbours(Writes);

	// Drop any loose material that lost its support.
	ApplyGravityAfterCarve(CentreVoxel);
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

	// Reset the authoritative store (default-constructed brickmap = empty) and the
	// streaming bookkeeping so a regenerate starts from a clean slate.
	WorldStore = mira::Brickmap();
	FilledColumns.Empty();
	MeshedColumns.Empty();
	ColumnYRange.Empty();

	// Drop the water sim — it captured the old brickmap; a fresh one binds lazily.
	WaterSim.Reset();
	WaterSimAccum = 0.0f;
}

// ===========================================================================
// Dynamic water (M3b) — FiniteWaterCore pour-and-settle.
//
// The ledger-based sim flows water DOWN first, then sideways toward lower
// neighbours, conserving every unit. The mesher draws a cell's level (1..8) as a
// partial-height cubic water voxel, so a settling pool reads as discrete water
// cubes filling bottom-up — the look in the reference screenshots. The generated
// ocean is the infinite SOURCE; carving next to it seeds finite water so the
// parent volume floods the opening (FloodCarveFromNeighbours).
// ===========================================================================
void AVoxelWorld::EnsureWaterSim()
{
	if (WaterSim.IsValid())
	{
		return;
	}
	using namespace mira;
	const Brickmap* BM = &WorldStore;
	// solid = any non-air terrain blocks water; source = ocean SOURCE bytes.
	auto SolidFn  = [BM](const Vec3i& p) { return BM->type_at(p) != mat::AIR; };
	auto SourceFn = [BM](const Vec3i& p) { return WaterByteCodec::is_source(BM->water_at(p)); };
	WaterSim = MakeUnique<FiniteWaterCore>(SolidFn, SourceFn);
}

int AVoxelWorld::StepWaterSim(int32 steps, int32 budget)
{
	using namespace mira;
	if (!WaterSim.IsValid() || steps <= 0)
	{
		return 0;
	}

	// Collect the chunks any change touched across all the steps, then re-mesh
	// each once (a cell can change several times; we only need one re-mesh).
	TSet<FIntVector> Dirty;
	for (int32 s = 0; s < steps; ++s)
	{
		FiniteWaterCore::StepResult R = WaterSim->step(budget);
		for (const FiniteWaterCore::Change& C : R.changes)
		{
			// Write the projected byte into the authoritative store.
			WorldStore.set_water(C.pos, static_cast<uint8_t>(C.byte));
			// Every chunk this voxel borders (apron-aware) needs a re-mesh.
			std::vector<Vec3i> Touched;
			chunks_touched_by_voxel(C.pos, Touched);
			for (const Vec3i& T : Touched)
			{
				Dirty.Add(FIntVector(T.x, T.y, T.z));
			}
		}
		if (R.changes.empty())
		{
			break; // settled — nothing left to do
		}
	}

	for (const FIntVector& C : Dirty)
	{
		RemeshChunk(C);
	}
	return Dirty.Num();
}

void AVoxelWorld::PourWaterAtWorld(const FVector& WorldPos, int32 Units)
{
	using namespace mira;
	EnsureWaterSim();

	// UE world (cm) -> core voxel (same mapping as CarveAtWorld).
	const FVector Local = WorldPos - GetActorLocation();
	const Vec3i Cell(
		FMath::FloorToInt(Local.X / 10.0f),
		FMath::FloorToInt(Local.Z / 10.0f),
		FMath::FloorToInt(Local.Y / 10.0f));

	WaterSim->place(Cell, FMath::Max(1, Units));

	// In the editor (no play tick) settle synchronously so it's visible at once.
	if (!GetWorld() || !GetWorld()->IsGameWorld())
	{
		StepWaterSim(120, WaterStepBudget);
	}
}

void AVoxelWorld::PourTestWater()
{
	using namespace mira;
	EnsureWaterSim();

	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);
	const int GroundCentre = Gen.compute_ground_y(0, 0);

	// Drop a column a few voxels above the centre surface; it collapses + spreads.
	const Vec3i Top(0, GroundCentre + 6, 0);
	WaterSim->place(Top, FMath::Max(1, TestPourUnits));

	// Settle synchronously so the editor button shows the result immediately.
	StepWaterSim(160, WaterStepBudget);
}

void AVoxelWorld::FloodCarveFromNeighbours(const std::vector<mira::VoxelWrite>& Writes)
{
	using namespace mira;
	if (!bEnableWaterSim)
	{
		return; // water flooding is opt-in
	}
	EnsureWaterSim();

	// Sea level from the configured generator (cheap; defaults to 120 = 12 m).
	HeightmapGenerator Gen;
	ConfigureGenerator(Gen);
	const int SeaY = Gen.sea_level_voxels;

	static const Vec3i N6[6] = {
		{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}
	};

	bool bSeeded = false;
	for (const VoxelWrite& W : Writes)
	{
		if (W.value != mat::AIR)
		{
			continue; // only newly-opened air can take water
		}
		const Vec3i P = W.pos;
		if (P.y > SeaY)
		{
			continue; // never flood above sea level
		}
		if (WorldStore.type_at(P) != mat::AIR || WaterByteCodec::is_water(WorldStore.water_at(P)))
		{
			continue; // still solid, or already water
		}
		// Any face-neighbour that already holds water? Then the parent volume can
		// feed this opening — seed it full and let the sim flow it down + level.
		bool bWaterAdjacent = false;
		for (const Vec3i& D : N6)
		{
			if (WaterByteCodec::is_water(WorldStore.water_at(P + D)))
			{
				bWaterAdjacent = true;
				break;
			}
		}
		if (bWaterAdjacent)
		{
			WaterSim->place(P, WaterByteCodec::MAX_LEVEL);
			bSeeded = true;
		}
	}

	if (bSeeded && (!GetWorld() || !GetWorld()->IsGameWorld()))
	{
		// Editor (no tick): settle now so the flood is visible from the button.
		StepWaterSim(160, WaterStepBudget);
	}
}

// ===========================================================================
// Persistence (P2) — journal the player's edits, replay them on load.
// ===========================================================================
void AVoxelWorld::RecordEdit(const mira::Vec3i& Voxel)
{
	// Store the voxel's FINAL state (post-carve/place) so replay reproduces it.
	EditStore.record(Voxel, WorldStore.type_at(Voxel), WorldStore.water_at(Voxel));
}

void AVoxelWorld::EnsureEditRegionLoaded(const FIntPoint& Region)
{
	using namespace mira;
	if (LoadedEditRegions.Contains(Region))
	{
		return; // already attempted this session
	}
	LoadedEditRegions.Add(Region);

	std::vector<uint8_t> Bytes;
	if (!MiraWorldPersist::LoadRegion(WorldSaveName, Region, Bytes))
	{
		return; // no file = never-edited region (normal)
	}
	std::vector<region::VoxelEdit> Edits;
	if (region::decode_delta_log(Bytes, Edits))
	{
		EditStore.load_region(Vec3i(Region.X, 0, Region.Y), Edits);
	}
	else
	{
		UE_LOG(LogTemp, Warning,
			TEXT("[MiraThal] corrupt region delta r_%d_%d.delta — ignored"),
			Region.X, Region.Y);
	}
}

void AVoxelWorld::ApplyEditsToColumn(int32 ccx, int32 ccz)
{
	using namespace mira;
	const Vec3i Origin = coords::chunk_origin_voxel(Vec3i(ccx, 0, ccz));
	const int x0 = Origin.x, x1 = Origin.x + coords::CHUNK;
	const int z0 = Origin.z, z1 = Origin.z + coords::CHUNK;

	// Make sure every region tile overlapping this column has been read from disk.
	const int RS = WorldEditStore::REGION_SIZE;
	const int rx0 = coords::floor_div(x0, RS), rx1 = coords::floor_div(x1 - 1, RS);
	const int rz0 = coords::floor_div(z0, RS), rz1 = coords::floor_div(z1 - 1, RS);
	for (int rx = rx0; rx <= rx1; ++rx)
	for (int rz = rz0; rz <= rz1; ++rz)
	{
		EnsureEditRegionLoaded(FIntPoint(rx, rz));
	}

	// Replay exactly the edits in this column's footprint onto the brickmap.
	EditStore.apply_xz_box(x0, x1, z0, z1, WorldStore);
}

void AVoxelWorld::SaveEdits()
{
	using namespace mira;
	if (!bPersistEdits)
	{
		return;
	}
	int Saved = 0;
	for (const Vec3i& R : EditStore.dirty_regions())
	{
		const std::vector<region::VoxelEdit> List = EditStore.region_edit_list(R);
		const std::vector<uint8_t> Bytes = region::encode_delta_log(List);
		if (MiraWorldPersist::SaveRegion(WorldSaveName, FIntPoint(R.x, R.z), Bytes))
		{
			EditStore.mark_clean(R);
			++Saved;
		}
	}
	if (Saved > 0)
	{
		UE_LOG(LogTemp, Display, TEXT("[MiraThal] saved %d edited region(s) -> %s"),
			Saved, *MiraWorldPersist::WorldDir(WorldSaveName));
	}
}

// ===========================================================================
// Gravity-on-dig (M3c) — loose material slides down when its support is gone.
// ===========================================================================
void AVoxelWorld::ApplyGravityAfterCarve(const mira::Vec3i& CarveCenterVoxel)
{
	using namespace mira;
	if (!bEnableGravity)
	{
		return;
	}

	// Analyse a cube around the dig. Anchor seed is the bubble's bottom face (y==0),
	// so place the bubble with solid ground below the carve: the carve sits ~3/4 up.
	constexpr int kSide = 32;
	const Vec3i Origin(CarveCenterVoxel.x - kSide / 2,
	                   CarveCenterVoxel.y - (kSide * 3) / 4,
	                   CarveCenterVoxel.z - kSide / 2);

	auto get_packed = [this, Origin](const Vec3i& local) -> int32_t {
		return static_cast<int32_t>(WorldStore.type_at(Origin + local));
	};
	auto fall_of = [](int id) -> int {
		// Only sand + gravel are loose; everything else holds (no rigid collapse v1).
		if (id == mat::SAND || id == 7 /*gravel*/) return FALL_LOOSE;
		return FALL_NEVER;
	};

	const GravityResult Res = analyze_bubble(kSide, get_packed, fall_of);
	if (Res.loose.empty())
	{
		return; // nothing slid
	}

	// Apply the slides into the brickmap: clear every source, then write every
	// destination (two passes so a cell that is both source and dest resolves).
	std::vector<Vec3i> Touched;
	Touched.reserve(Res.loose.size() * 2);
	for (const LooseMove& m : Res.loose)
	{
		const Vec3i From = Origin + m.from;
		WorldStore.set_type(From, static_cast<uint8_t>(mat::AIR));
		Touched.push_back(From);
		if (bPersistEdits) { RecordEdit(From); }
	}
	for (const LooseMove& m : Res.loose)
	{
		const Vec3i To = Origin + m.to;
		WorldStore.set_type(To, static_cast<uint8_t>(m.packed & 0xFF));
		Touched.push_back(To);
		if (bPersistEdits) { RecordEdit(To); }
	}

	// Re-mesh every chunk the moved voxels border (apron-aware), de-duplicated.
	TSet<FIntVector> Dirty;
	for (const Vec3i& V : Touched)
	{
		std::vector<Vec3i> Chunks;
		chunks_touched_by_voxel(V, Chunks);
		for (const Vec3i& C : Chunks) { Dirty.Add(FIntVector(C.x, C.y, C.z)); }
	}
	for (const FIntVector& C : Dirty)
	{
		RemeshChunk(C);
	}
}
