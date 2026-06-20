// VoxelNaniteCrust.cpp — runtime streamer for the baked Nanite crust tiles.
#include "VoxelNaniteCrust.h"
#include "VoxelBakeManifest.h"
#include "VoxelWorld.h"             // AVoxelWorld::AreCoveredColumnsReady (handoff readiness)

#include "Components/StaticMeshComponent.h"
#include "Components/SceneComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/AssetManager.h"
#include "Engine/StreamableManager.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/Pawn.h"

#include "Core/NaniteBakeTiling.h"   // which_tiles_in_band / tile math
#include "Core/ChunkCoords.h"        // coords::CHUNK / floor_div
#include "MiraVoxelMesh.h"           // VoxelToUU — voxel -> UE units, same as the live path

AVoxelNaniteCrust::AVoxelNaniteCrust()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = false; // enabled in BeginPlay only if we have a manifest
	USceneComponent* Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	RootComponent = Root;
	RootComponent->SetMobility(EComponentMobility::Static);
}

void AVoxelNaniteCrust::BeginPlay()
{
	Super::BeginPlay();

	// No manifest assigned -> do nothing (the safe default before any bake exists).
	if (Manifest.IsNull())
	{
		return;
	}

	// Load the (small) manifest synchronously — it only holds soft pointers, not meshes.
	LoadedManifest = Manifest.LoadSynchronous();
	if (!LoadedManifest)
	{
		UE_LOG(LogTemp, Warning, TEXT("[MiraThalCrust] manifest failed to load; crust disabled."));
		return;
	}

	// Build the tile-key -> entry-index lookup once.
	TileIndex.Reset();
	for (int32 i = 0; i < LoadedManifest->Tiles.Num(); ++i)
	{
		const FVoxelBakeTileEntry& E = LoadedManifest->Tiles[i];
		TileIndex.Add(FIntPoint(E.TileX, E.TileZ), i);
	}

	SetActorTickEnabled(true);
}

void AVoxelNaniteCrust::EndPlay(const EEndPlayReason::Type Reason)
{
	// Drop every live tile component (the actor's own destruction would too, but be tidy).
	for (auto& Pair : TileComponents)
	{
		if (Pair.Value) { Pair.Value->DestroyComponent(); }
	}
	TileComponents.Reset();
	PendingLoads.Reset();
	Super::EndPlay(Reason);
}

bool AVoxelNaniteCrust::GetFocusChunkXZ(mira::Vec2i& OutChunkXZ) const
{
	FVector FocusWorld;
	if (FocusActor)
	{
		FocusWorld = FocusActor->GetActorLocation();
	}
	else if (APawn* Pawn = UGameplayStatics::GetPlayerPawn(this, 0))
	{
		FocusWorld = Pawn->GetActorLocation();
	}
	else
	{
		return false;
	}

	// World cm -> voxels (1 voxel = VoxelToUU units), relative to this actor's origin (the
	// crust positions are baked actor-LOCAL, matching the live PositionToUE convention).
	const FVector Local = FocusWorld - GetActorLocation();
	const int32 VoxelX = FMath::FloorToInt(Local.X / MiraVoxelMesh::VoxelToUU);
	// UE Y maps back to voxel Z (PositionToUE swapped Y<->Z).
	const int32 VoxelZ = FMath::FloorToInt(Local.Y / MiraVoxelMesh::VoxelToUU);
	OutChunkXZ = mira::Vec2i(mira::coords::floor_div(VoxelX, mira::coords::CHUNK),
	                         mira::coords::floor_div(VoxelZ, mira::coords::CHUNK));
	return true;
}

void AVoxelNaniteCrust::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	if (!LoadedManifest) { return; }

	mira::Vec2i FocusChunk;
	if (!GetFocusChunkXZ(FocusChunk)) { return; }

	const int32 TileSpan = FMath::Max(1, LoadedManifest->TileSpanVoxels);

	// Which tiles SHOULD be shown this tick (pure ring math, harness-locked).
	const std::vector<mira::Vec2i> Want = mira::nanitebake::which_tiles_in_band(
		FocusChunk, TileSpan, InnerChunks, OuterChunks);

	// Set membership for fast "is wanted?" checks.
	TSet<FIntPoint> WantSet;
	WantSet.Reserve(static_cast<int32>(Want.size()));
	for (const mira::Vec2i& T : Want)
	{
		WantSet.Add(FIntPoint(T.x, T.y));
	}

	int32 Budget = MaxOpsPerTick;

	// ENSURE wanted tiles that exist in the manifest and aren't shown yet.
	for (const mira::Vec2i& T : Want)
	{
		if (Budget <= 0) { break; }
		const FIntPoint Key(T.x, T.y);
		if (TileComponents.Contains(Key) || PendingLoads.Contains(Key)) { continue; }
		if (!TileIndex.Contains(Key)) { continue; } // no baked tile here (all-air during bake)
		EnsureTile(Key);
		--Budget;
	}

	// RELEASE shown tiles that are no longer wanted — but (HANDOFF) only once the LIVE voxels
	// that replace a tile are actually meshed, so the crust->voxel swap never leaves a hole. A
	// tile whose near voxels aren't ready is simply KEPT this tick (a harmless overlap — it's
	// sunk below the surface) and re-checked next tick. Flag off -> the old blind distance release.
	AVoxelWorld* VW = bHoldTilesUntilVoxelsReady ? ResolveVoxelWorld() : nullptr;
	TArray<FIntPoint> ToRelease;
	for (auto& Pair : TileComponents)
	{
		if (WantSet.Contains(Pair.Key)) { continue; }
		if (VW)
		{
			const mira::nanitebake::TileChunkBounds CB =
				mira::nanitebake::tile_chunk_bounds(mira::Vec2i(Pair.Key.X, Pair.Key.Y), TileSpan);
			if (!VW->AreCoveredColumnsReady(CB.minCx, CB.maxCx, CB.minCz, CB.maxCz))
			{
				continue; // near voxels not meshed yet — keep the crust tile (overlap, no hole)
			}
		}
		ToRelease.Add(Pair.Key);
	}
	for (const FIntPoint& Key : ToRelease)
	{
		if (Budget <= 0) { break; }
		ReleaseTile(Key);
		--Budget;
	}

	// DIAGNOSTIC (~1 Hz): the crust tile count — the counter the perf forensics was missing, so
	// "is the crust actually streaming?" is answered by DATA, not a live component dump.
	StatLogAccum += DeltaSeconds;
	if (StatLogAccum >= 1.0f)
	{
		StatLogAccum = 0.0f;
		UE_LOG(LogTemp, Display, TEXT("[MiraThalCrust] tiles=%d pendingLoads=%d focusChunk=(%d,%d) hold=%d"),
			TileComponents.Num(), PendingLoads.Num(), FocusChunk.x, FocusChunk.y,
			bHoldTilesUntilVoxelsReady ? 1 : 0);
	}
}

// Lazily find the single live voxel world in the level (the crust draws the FAR band; the world
// owns the NEAR editable band). Cached weakly so a level teardown can't dangle.
AVoxelWorld* AVoxelNaniteCrust::ResolveVoxelWorld()
{
	if (CachedVoxelWorld.IsValid()) { return CachedVoxelWorld.Get(); }
	if (AActor* Found = UGameplayStatics::GetActorOfClass(this, AVoxelWorld::StaticClass()))
	{
		CachedVoxelWorld = Cast<AVoxelWorld>(Found);
	}
	return CachedVoxelWorld.Get();
}

void AVoxelNaniteCrust::EnsureTile(const FIntPoint& TileKey)
{
	const int32* IdxPtr = TileIndex.Find(TileKey);
	if (!IdxPtr) { return; }
	const FVoxelBakeTileEntry& Entry = LoadedManifest->Tiles[*IdxPtr];
	if (Entry.Mesh.IsNull()) { return; }

	// Already loaded into memory? Place immediately. Otherwise kick an async load and
	// place in the callback (so a tile entering range never hitches the frame).
	if (UStaticMesh* Already = Entry.Mesh.Get())
	{
		PlaceTile(TileKey, Already);
		return;
	}

	PendingLoads.Add(TileKey);
	const FSoftObjectPath Path = Entry.Mesh.ToSoftObjectPath();
	FStreamableManager& Streamable = UAssetManager::GetStreamableManager();
	Streamable.RequestAsyncLoad(Path, FStreamableDelegate::CreateWeakLambda(this,
		[this, TileKey, Path]()
		{
			PendingLoads.Remove(TileKey);
			// The actor may have moved on (tile left the band before the load finished),
			// or this tile may already be shown — re-check before placing.
			if (TileComponents.Contains(TileKey)) { return; }
			UStaticMesh* Mesh = Cast<UStaticMesh>(Path.ResolveObject());
			if (!Mesh) { Mesh = Cast<UStaticMesh>(Path.TryLoad()); }
			if (Mesh) { PlaceTile(TileKey, Mesh); }
		}));
}

void AVoxelNaniteCrust::PlaceTile(const FIntPoint& TileKey, UStaticMesh* Mesh)
{
	if (!Mesh || TileComponents.Contains(TileKey)) { return; }
	const int32* IdxPtr = TileIndex.Find(TileKey);
	if (!IdxPtr) { return; }
	const FVoxelBakeTileEntry& Entry = LoadedManifest->Tiles[*IdxPtr];

	UStaticMeshComponent* Comp = NewObject<UStaticMeshComponent>(this);
	if (!Comp) { return; }
	Comp->SetStaticMesh(Mesh);
	Comp->SetMobility(EComponentMobility::Static);
	Comp->SetCollisionEnabled(ECollisionEnabled::NoCollision); // visual far terrain only
	Comp->SetupAttachment(RootComponent);

	// PLACEMENT — mirror AVoxelWorld::SuperChunkActorLocation. The baked mesh positions are
	// in COARSE-cell units (one cell = Stride fine voxels), apron'd, with cell (0,0,0) at
	// fine voxel (origin - APRON*Stride, baseFineY - APRON*Stride, ...). Map fine voxels to
	// UE with PositionToUE: (vx,vy,vz)->(vx,vz,vy)*VoxelToUU. We sink the crust by
	// VerticalBiasVoxels to avoid z-fighting at the near-band seam (same trick as the vista).
	const int32 Stride = FMath::Max(1, Entry.Stride);
	const int32 A = mira::APRON * Stride;
	const int32 Ox = Entry.MinVoxelX - A;
	const int32 Oy = (Entry.BaseFineY - VerticalBiasVoxels) - A;
	const int32 Oz = Entry.MinVoxelZ - A;
	const float U = MiraVoxelMesh::VoxelToUU;
	const FVector Local(Ox * U, Oz * U, Oy * U); // (vx, vz, vy) swap
	Comp->SetRelativeLocation(Local);
	// Positions are in coarse cells -> scale by Stride fine voxels (like the super path).
	Comp->SetWorldScale3D(FVector(static_cast<float>(Stride)));

	Comp->RegisterComponent();
	TileComponents.Add(TileKey, Comp);
}

void AVoxelNaniteCrust::ReleaseTile(const FIntPoint& TileKey)
{
	if (TObjectPtr<UStaticMeshComponent>* Found = TileComponents.Find(TileKey))
	{
		if (UStaticMeshComponent* Comp = *Found)
		{
			Comp->DestroyComponent();
		}
		TileComponents.Remove(TileKey);
	}
}
