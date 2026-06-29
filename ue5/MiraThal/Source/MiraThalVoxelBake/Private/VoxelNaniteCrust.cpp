// VoxelNaniteCrust.cpp — runtime streamer for the baked Nanite crust tiles.
#include "VoxelNaniteCrust.h"
#include "VoxelBakeManifest.h"
#include "VoxelWorld.h"             // AVoxelWorld::AreCoveredColumnsReady (handoff readiness)
#include "VoxelGenParams.h"         // SnapshotGenParams / FingerprintGenParams (stale-bake check)

#include "Components/StaticMeshComponent.h"
#include "Components/SceneComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/AssetManager.h"
#include "Engine/StreamableManager.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/Pawn.h"
#include "HAL/IConsoleManager.h"     // IConsoleManager — Nanite streaming-pool cvar tuning

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

	// STALE-BAKE GUARD: confirm this crust was baked with the SAME generator settings the live
	// world is using right now. If a designer changed the seed / sea level / amplitude / EXR map
	// etc. since the bake, the frozen crust geometry no longer matches the near voxels and a seam
	// appears. We recompute the generator fingerprint from the LIVE voxel world (the same way the
	// baker did — GenLod 0 / coarse-gen off) and compare to the one stamped in the manifest.
	//
	// This is a WARN-ONLY check: we never refuse to run. A 0 fingerprint means a legacy bake from
	// before this field existed ("unknown" — can't compare, so just note it once).
	if (AVoxelWorld* World = ResolveVoxelWorld())
	{
		// Make sure the world's heightmap (if any) is loaded before snapshotting, so the EXR georef
		// fields are real — otherwise an EXR world would fingerprint differently here than at bake.
		World->LoadHeightmapIfNeeded();
		const FGenParams LiveParams = SnapshotGenParams(*World, /*GenLod=*/0, /*bCoarseFarGen=*/false);
		const uint64 LiveFingerprint  = FingerprintGenParams(LiveParams);
		const uint64 BakedFingerprint = LoadedManifest->GenFingerprint;

		if (BakedFingerprint == 0)
		{
			// Legacy manifest (baked before fingerprinting existed) — we can't tell if it matches.
			UE_LOG(LogTemp, Warning,
				TEXT("[MiraThalCrust] crust manifest has no generator fingerprint (legacy bake) — ")
				TEXT("cannot verify it matches the live world's generator. Re-bake to enable the check ")
				TEXT("(live fingerprint is %llu)."),
				LiveFingerprint);
		}
		else if (BakedFingerprint != LiveFingerprint)
		{
			UE_LOG(LogTemp, Warning,
				TEXT("[MiraThalCrust] crust was baked with DIFFERENT generator settings ")
				TEXT("(fingerprint %llu != world %llu) — the far terrain may not line up with the near ")
				TEXT("voxels; re-bake the crust."),
				BakedFingerprint, LiveFingerprint);
		}
		// Matching fingerprints => no log (silent success is the common, healthy case).
	}
	else
	{
		// No live voxel world in the level — nothing to compare against (crust-only test map, etc.).
		UE_LOG(LogTemp, Display,
			TEXT("[MiraThalCrust] no AVoxelWorld found — skipping generator fingerprint check."));
	}

	// We have a real manifest => the crust is ACTIVE. Now (and only now) it's worth widening the
	// Nanite streaming pool so a big crust doesn't thrash. A level without a crust never reaches
	// this line, so it keeps the engine/project defaults untouched.
	ApplyNaniteStreamingTuning();

	// Force the first Tick to do a real rescan (no cached focus yet). After that, Tick only
	// rescans when the focus chunk changes or there's outstanding load work — see Tick().
	bHasLastFocus = false;
	RescanAccum   = RescanIntervalSec; // allow an immediate first rescan, don't wait the interval

	SetActorTickEnabled(true);
}

// Verify the Nanite streaming cvars are big enough for a large crust — WITHOUT mutating them.
//
// CRITICAL (2026-06-28 crash fix): r.Nanite.Streaming.StreamingPoolSize and NumInitialRootPages
// are INIT-TIME-ONLY. The Nanite streaming manager sizes its resident page pool + LRU from them
// ONCE at engine startup. Raising them at runtime (which this function used to do via CVar->Set on
// BeginPlay) leaves the LRU sized for the OLD pool while MaxStreamingPages reflects the NEW one, so
// the next streaming update trips `check(WriteIndex == MaxStreamingPages)` in
// FStreamingManager::CompactLRU — an instant crash the moment a big crust mesh installs. So we no
// longer touch the cvars here. The actual values are set at engine init in
// Config/DefaultEngine.ini under [ConsoleVariables]. This function now only WARNS if the live value
// is below the crust's desired floor, so a misconfigured project is loud instead of silently
// thrashing (or, worse, someone re-adding a runtime Set()).
void AVoxelNaniteCrust::ApplyNaniteStreamingTuning()
{
	if (!bTuneNaniteStreamingPool) { return; }

	IConsoleManager& CVars = IConsoleManager::Get();

	auto WarnIfBelow = [&CVars](const TCHAR* CVarName, int32 Desired, const TCHAR* Units)
	{
		if (Desired <= 0) { return; } // 0/negative = "don't care about this one"
		const IConsoleVariable* CVar = CVars.FindConsoleVariable(CVarName);
		if (CVar && CVar->GetInt() < Desired)
		{
			UE_LOG(LogTemp, Warning,
				TEXT("[MiraThalCrust] %s is %d%s but the crust wants >= %d%s. "
				     "Raise it in Config/DefaultEngine.ini [ConsoleVariables] (it is init-time-only "
				     "— it CANNOT be set safely at runtime)."),
				CVarName, CVar->GetInt(), Units, Desired, Units);
		}
		else if (CVar)
		{
			UE_LOG(LogTemp, Display, TEXT("[MiraThalCrust] %s = %d%s (>= desired %d%s) OK."),
				CVarName, CVar->GetInt(), Units, Desired, Units);
		}
	};

	WarnIfBelow(TEXT("r.Nanite.Streaming.StreamingPoolSize"), NaniteStreamingPoolSizeMB, TEXT(" MB"));
	WarnIfBelow(TEXT("r.Nanite.Streaming.NumInitialRootPages"), NaniteNumInitialRootPages, TEXT(""));
}

void AVoxelNaniteCrust::EndPlay(const EEndPlayReason::Type Reason)
{
	// Drop every live tile component (the actor's own destruction would too, but be tidy).
	for (auto& Pair : TileComponents)
	{
		if (Pair.Value) { Pair.Value->DestroyComponent(); }
	}
	TileComponents.Reset();

	// Tear down the pooled (parked) components too — they're real UObjects we created.
	for (TObjectPtr<UStaticMeshComponent>& Pooled : ComponentPool)
	{
		if (Pooled) { Pooled->DestroyComponent(); }
	}
	ComponentPool.Reset();

	PendingLoads.Reset();

	// Drop every streamable handle so the loaded tile meshes can be garbage-collected on teardown.
	TileLoadHandles.Reset();

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

	// ---------------------------------------------------------------------------------------
	// SHOULD WE RESCAN THIS TICK? (the 291 ms/frame fix.)
	//
	// The wanted-tile set only changes when the player crosses into a new CHUNK (chunks are
	// 3.2 m). Standing still, or moving within one chunk, leaves the set identical — so before
	// this change the streamer was paying for a full sweep + TSet build + sort + ensure/release
	// scan EVERY frame for no reason. Now we skip all of that unless something actually needs it:
	//
	//   * FIRST tick (no cached focus yet)                            -> rescan,
	//   * the focus chunk CHANGED and the throttle interval elapsed   -> rescan,
	//   * there are in-flight loads still draining (PendingLoads)     -> rescan (so queued near
	//     tiles keep getting fed in nearest-first until the band is full).
	//
	// If none of those hold, we fall through to JUST the ~1 Hz diagnostic at the bottom and do
	// no heavy work. The RELEASE pass is inside this same gate on purpose: the band only moves
	// when the focus chunk moves, so tiles only ever leave the band on a focus change — there's
	// no other reason the set would change mid-chunk (Inner/Outer are fixed unless a designer
	// edits them, which is picked up on the next focus change or forced rescan; see the header).
	RescanAccum += DeltaSeconds;
	const bool bFocusChanged = (!bHasLastFocus) || !(FocusChunk == LastFocusChunk);
	const bool bHaveOutstanding = (PendingLoads.Num() > 0);
	const bool bThrottleElapsed = (RescanAccum >= RescanIntervalSec);
	const bool bDoRescan =
		(bFocusChanged && bThrottleElapsed) // moved to a new chunk (rate-limited while flying)
		|| bHaveOutstanding                 // still draining loads — keep feeding the band
		|| !bHasLastFocus;                  // very first scan after BeginPlay

	if (bDoRescan)
	{
		RescanAccum = 0.0f; // restart the throttle window from this real rescan

		// CLAMP the band before the sweep so a bad OuterChunks can never blow up the loop again
		// (one value of 99999 once froze the editor at 291 ms/frame). Inner is also clamped to
		// not exceed Outer. The Core which_tiles_in_band caps its own reach too (belt and braces).
		const int32 SafeOuter = FMath::Min(OuterChunks, FMath::Max(1, MaxOuterChunks));
		const int32 SafeInner = FMath::Clamp(InnerChunks, 0, SafeOuter);

		// Which tiles SHOULD be shown this tick (pure ring math, harness-locked).
		const std::vector<mira::Vec2i> Want = mira::nanitebake::which_tiles_in_band(
			FocusChunk, TileSpan, SafeInner, SafeOuter);

		// Set membership for fast "is wanted?" checks.
		TSet<FIntPoint> WantSet;
		WantSet.Reserve(static_cast<int32>(Want.size()));
		for (const mira::Vec2i& T : Want)
		{
			WantSet.Add(FIntPoint(T.x, T.y));
		}
	
		// NEAREST-FIRST ordering. which_tiles_in_band returns the band tiles in grid-sweep order
		// (row by row), NOT by distance — so without this the streamer could spend its whole per-tick
		// budget loading FAR tiles while the tiles right under the player are still missing. We copy
		// the wanted tiles into a local array and sort them by chunk-distance to the focus (the same
		// metric the ring uses), so the visible near band always fills before the far band. This is
		// the other half of the anti-freeze fix: combined with the concurrency cap below, the player's
		// surroundings come in first and the heavy far tiles trickle in behind them.
		TArray<mira::Vec2i> WantSorted;
		WantSorted.Reserve(static_cast<int32>(Want.size()));
		for (const mira::Vec2i& T : Want)
		{
			WantSorted.Add(T);
		}
		WantSorted.Sort([&FocusChunk, TileSpan](const mira::Vec2i& A, const mira::Vec2i& B)
		{
			const int32 DistA = mira::nanitebake::tile_chunk_distance(FocusChunk, A, TileSpan);
			const int32 DistB = mira::nanitebake::tile_chunk_distance(FocusChunk, B, TileSpan);
			return DistA < DistB; // smaller chunk-distance first => nearest tiles ensured first
		});
	
		int32 Budget = MaxOpsPerTick;
	
		// ENSURE wanted tiles that exist in the manifest and aren't shown yet — NEAREST-FIRST, and
		// bounded by both the in-flight load cap and the live-component cap so a huge band can never
		// burst-load thousands of heavy meshes (the bug that froze the editor twice).
		for (const mira::Vec2i& T : WantSorted)
		{
			if (Budget <= 0) { break; }
	
			// ANTI-FREEZE cap #1: never let too many heavy meshes be async-loading at once. If we're at
			// the in-flight ceiling we stop STARTING loads this tick (the queued near tiles we skipped
			// are still wanted, so the very next tick re-tries them, in nearest-first order, once a slot
			// frees up). This bounds the burst regardless of band size.
			if (PendingLoads.Num() >= MaxConcurrentLoads) { break; }
	
			const FIntPoint Key(T.x, T.y);
			if (TileComponents.Contains(Key) || PendingLoads.Contains(Key)) { continue; }
			if (!TileIndex.Contains(Key)) { continue; } // no baked tile here (all-air during bake)
	
			// ANTI-FREEZE cap #2: never exceed the live-component ceiling. Because we're going
			// nearest-first, the components we DO hold are always the closest ones; far tiles past the
			// cap simply wait until a near tile releases. 0 (or negative) = unlimited (old behaviour).
			// We count tiles already in flight too, so we don't overshoot once those loads land.
			if (MaxLiveComponents > 0 &&
				(TileComponents.Num() + PendingLoads.Num()) >= MaxLiveComponents)
			{
				break;
			}
	
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

		// Remember the chunk we just scanned at, so the next ticks at this chunk skip the whole
		// block above until the player crosses into a different chunk (or loads are still draining).
		LastFocusChunk = FocusChunk;
		bHasLastFocus  = true;
	} // end if (bDoRescan)

	// DIAGNOSTIC (~1 Hz): the crust tile count — the counter the perf forensics was missing, so
	// "is the crust actually streaming?" is answered by DATA, not a live component dump. This runs
	// EVERY tick on its OWN accumulator (outside the rescan gate) so the tile count keeps printing
	// even on the cheap ticks where we skipped the heavy scan.
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

	const FSoftObjectPath Path = Entry.Mesh.ToSoftObjectPath();
	FStreamableManager& Streamable = UAssetManager::GetStreamableManager();

	// Mark the tile in-flight BEFORE requesting the load. PendingLoads is our authoritative "this
	// tile is still wanted and loading" signal: ReleaseTile clears it, so the callback can use it to
	// detect a tile that left the band mid-load. We add it first so it's already correct even if the
	// load completes SYNCHRONOUSLY inside RequestAsyncLoad (which fires the callback before this
	// function returns — the case where the mesh was already resident).
	PendingLoads.Add(TileKey);

	// ASYNC-LOAD HANDLE LIFETIME (improvement #2). We ALWAYS take a streamable handle for the tile,
	// even when the mesh happens to be in memory already. The handle is what pins the mesh against
	// the garbage collector for as long as the tile is resident; we drop it in ReleaseTile so an
	// unloaded tile's mesh can actually be freed. Without a held handle, a mesh that nothing else
	// references could be GC'd while we're still showing it (flicker / crash). RequestAsyncLoad
	// returns the handle immediately and fires the callback when the load completes — if the mesh is
	// already loaded the callback may run synchronously, right here.
	TSharedPtr<FStreamableHandle> Handle = Streamable.RequestAsyncLoad(Path,
		FStreamableDelegate::CreateWeakLambda(this,
		[this, TileKey, Path]()
		{
			// If the tile was released while loading, ReleaseTile already cleared PendingLoads (and
			// dropped the handle) — bail so we don't place a tile nobody wants. Also covers a tile
			// that's somehow already shown.
			if (!PendingLoads.Contains(TileKey)) { return; }
			PendingLoads.Remove(TileKey);
			if (TileComponents.Contains(TileKey)) { return; }
			UStaticMesh* Mesh = Cast<UStaticMesh>(Path.ResolveObject());
			if (!Mesh) { Mesh = Cast<UStaticMesh>(Path.TryLoad()); }
			if (Mesh) { PlaceTile(TileKey, Mesh); }
			else      { TileLoadHandles.Remove(TileKey); } // load failed — don't leak the handle
		}));

	// Remember the handle (this is what keeps the mesh resident). If the callback already ran
	// synchronously above, the tile is placed and PendingLoads no longer contains it — but we still
	// want the handle stored so the mesh stays pinned while the tile is shown. If the request failed
	// to produce a handle, undo the pending mark so we'll retry next tick.
	if (Handle.IsValid())
	{
		TileLoadHandles.Add(TileKey, Handle);
	}
	else
	{
		PendingLoads.Remove(TileKey);
	}
}

void AVoxelNaniteCrust::PlaceTile(const FIntPoint& TileKey, UStaticMesh* Mesh)
{
	if (!Mesh || TileComponents.Contains(TileKey)) { return; }
	const int32* IdxPtr = TileIndex.Find(TileKey);
	if (!IdxPtr) { return; }
	const FVoxelBakeTileEntry& Entry = LoadedManifest->Tiles[*IdxPtr];

	// POOLING (improvement #1): reuse a parked component if one is waiting, else make a fresh one.
	// AcquireComponent has already configured Static mobility + NoCollision + attachment and (for a
	// fresh component) registered it — so here we only do the per-TILE work: give it this tile's
	// mesh, move it, and show it. We deliberately do NOT call SetMobility/SetCollisionEnabled here:
	// those can't be changed on an already-registered component, and a pooled one is already set up.
	UStaticMeshComponent* Comp = AcquireComponent();
	if (!Comp) { return; }
	Comp->SetStaticMesh(Mesh);

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

	// Show it (a pooled component comes back hidden; a fresh one is visible already, but setting it
	// again is harmless and keeps the two paths identical).
	Comp->SetVisibility(true);
	Comp->SetHiddenInGame(false);

	TileComponents.Add(TileKey, Comp);
}

// POOLING (improvement #1) — grab a parked component or make a new one. A pooled component is
// already registered (Static, NoCollision, attached) and just needs un-hiding by the caller; a
// fresh one we configure and register here so PlaceTile's per-tile path is the same either way.
UStaticMeshComponent* AVoxelNaniteCrust::AcquireComponent()
{
	// Reuse a parked component if the pool has one. Pop from the back (cheap, order doesn't matter).
	while (ComponentPool.Num() > 0)
	{
		UStaticMeshComponent* Pooled = ComponentPool.Pop();
		if (Pooled) { return Pooled; } // already registered + configured; PlaceTile sets mesh+show
		// null slot (component was GC'd despite the UPROPERTY, shouldn't happen) — skip it
	}

	// Pool empty -> make a fresh component and do the one-time setup that must happen BEFORE
	// RegisterComponent (mobility + attachment). Collision is set here too (visual far terrain only).
	//
	// MOBILITY = MOVABLE (not Static): a POOLED component is repositioned every time it's reused for a
	// different tile (PlaceTile calls SetRelativeLocation/SetWorldScale3D AFTER it's registered). Moving
	// a Static component post-registration spams "Mobility is Static but it's being moved" warnings and
	// can mis-cache Lumen. Movable is the correct mobility for a streamer that recycles components to new
	// positions. Nanite + Lumen handle Movable far terrain fine; the crust is visual-only and far away.
	UStaticMeshComponent* Comp = NewObject<UStaticMeshComponent>(this);
	if (!Comp) { return nullptr; }
	Comp->SetMobility(EComponentMobility::Movable);
	Comp->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Comp->SetupAttachment(RootComponent);
	Comp->RegisterComponent();
	return Comp;
}

// POOLING (improvement #1) — hide a component and park it for reuse, or destroy it if the pool is
// full (or pooling is disabled). Parking avoids recreating the render proxy on the next ensure.
void AVoxelNaniteCrust::RecycleComponent(UStaticMeshComponent* Comp)
{
	if (!Comp) { return; }

	// Pool full or pooling off -> just destroy it (don't hoard memory).
	if (MaxPooledComponents <= 0 || ComponentPool.Num() >= MaxPooledComponents)
	{
		Comp->DestroyComponent();
		return;
	}

	// Park it: clear the mesh (releases the heavy render data reference) and hide it. We keep the
	// component REGISTERED so reusing it doesn't pay the register/proxy-create cost again.
	Comp->SetStaticMesh(nullptr);
	Comp->SetVisibility(false);
	Comp->SetHiddenInGame(true);
	ComponentPool.Add(Comp);
}

void AVoxelNaniteCrust::ReleaseTile(const FIntPoint& TileKey)
{
	if (TObjectPtr<UStaticMeshComponent>* Found = TileComponents.Find(TileKey))
	{
		// POOLING (improvement #1): recycle instead of destroy where possible.
		RecycleComponent(*Found);
		TileComponents.Remove(TileKey);
	}

	// HANDLE LIFETIME (improvement #2): drop this tile's streamable handle. That removes our pin on
	// the mesh so, once nothing else references it, the GC can actually free the unloaded tile. Also
	// covers a tile released while its load was still in flight (the in-flight callback then bails
	// because TileLoadHandles no longer contains the key).
	TileLoadHandles.Remove(TileKey);
	PendingLoads.Remove(TileKey);
}
