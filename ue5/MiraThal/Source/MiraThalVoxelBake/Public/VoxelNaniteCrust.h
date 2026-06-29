// VoxelNaniteCrust.h — the RUNTIME streamer for the baked Nanite crust tiles.
//
// WHAT THIS IS (plain English):
// The baker (editor-time) produced a folder of Nanite static-mesh tiles + a manifest.
// THIS actor is the runtime side: drop it in the level, point it at the manifest, and
// on BeginPlay it reads the manifest. Each tick (budgeted, like AVoxelWorld's streaming
// tick) it ENSURES a UStaticMeshComponent exists for every tile in the crust band
// [InnerChunks .. OuterChunks] around the focus, and RELEASES components for tiles that
// drifted out of band. Tile meshes are SOFT-loaded asynchronously so a tile coming into
// range doesn't hitch the frame. No collision — the crust is purely visual far terrain;
// Nanite does its own cull/LOD, so we don't manage per-mesh LOD ourselves.
//
// This mirrors AVoxelWorld::EnsureSuperActor / DestroySuperActor ring logic, but with
// static-mesh COMPONENTS on one actor instead of separate chunk actors (the crust is
// static and never re-meshes, so it doesn't need full actors).
//
// SAFETY: with no manifest assigned (the default, and the only state before a bake has
// been run) this actor does NOTHING — so adding it changes no behaviour. It is the
// runtime counterpart of the experimental, default-OFF AVoxelWorld::bEnableNaniteCrust.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/MiraVec.h"             // mira::Vec2i (tile keys)
#include "VoxelNaniteCrust.generated.h"

class UVoxelBakeManifest;
class UStaticMeshComponent;
class AVoxelWorld;

UCLASS()
class MIRATHALVOXELBAKE_API AVoxelNaniteCrust : public AActor
{
	GENERATED_BODY()

public:
	AVoxelNaniteCrust();

	// The baked index to stream from (written by VoxelCrustBaker). SOFT so assigning it
	// doesn't pull every tile mesh into memory — we load tiles on demand.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust")
	TSoftObjectPtr<UVoxelBakeManifest> Manifest;

	// What the band is measured from. If null, falls back to the local player pawn.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust")
	TObjectPtr<AActor> FocusActor = nullptr;

	// Crust band in CHUNKS from the focus: tiles whose nearest covered chunk lies in
	// [InnerChunks .. OuterChunks] are shown. Inner usually = the near voxel StreamRadius.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "0"))
	int32 InnerChunks = 64;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "1"))
	int32 OuterChunks = 512;

	// SAFETY CLAMP on OuterChunks. The wanted-tile sweep in which_tiles_in_band runs
	// (2*reach+1)^2 iterations, and reach grows with OuterChunks. A bad OuterChunks (a
	// designer once typed 99999) made that loop run hundreds of millions of times EVERY
	// frame and froze the editor at 291 ms/frame. We never pass a value larger than this
	// to the band math — anything bigger is silently clamped to MaxOuterChunks. The Core
	// function also caps itself (belt and braces), but clamping here keeps the actor's own
	// numbers sane. 1024 chunks = 32768 voxels = ~3.3 km of crust reach, far past any view.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "1"))
	int32 MaxOuterChunks = 1024;

	// THROTTLE. Even when the focus chunk IS moving (flying fast), don't rebuild the wanted
	// set more often than this. The focus-chunk cache below already makes standing still free;
	// this just bounds the cost while flying so a rapid stream of chunk crossings can't run a
	// full rescan every single frame. A drain of in-flight loads still forces a rescan so tiles
	// finish coming in. 0.15 s = up to ~6-7 rescans/second, smooth enough for fast travel.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "0.0"))
	float RescanIntervalSec = 0.15f;

	// Max tile ensure/release ops per tick — caps per-frame streaming cost.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "1", ClampMax = "64"))
	int32 MaxOpsPerTick = 4;

	// ANTI-FREEZE knob #1 — the hard cap on how many tile meshes can be ASYNC-LOADING at once.
	// MaxOpsPerTick only limits how many loads we START per tick; without this, a huge band would
	// keep starting MaxOpsPerTick fresh loads EVERY tick and pile up thousands of in-flight loads
	// of heavy (up to ~1.6M-vert) meshes, which is what froze the editor. We refuse to kick a new
	// async load while PendingLoads.Num() is already at this number, so the burst is bounded no
	// matter how big the band gets. The loads still finish and place; we just feed them in steadily.
	// 8 is a safe default for heavy geo-merged tiles; raise it if streaming feels too slow on lighter bakes.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "1", ClampMax = "64"))
	int32 MaxConcurrentLoads = 8;

	// ANTI-FREEZE knob #2 — the hard cap on how many tile COMPONENTS can be live (placed) at once.
	// Even fully loaded, each placed UStaticMeshComponent costs memory + render cost; a giant band
	// could place far more than the GPU/CPU can hold. Because we now fill NEAREST-FIRST (see the
	// Tick), this cap keeps the closest tiles and simply stops ensuring the far ones once we're full
	// — the far tiles come in as near ones release. 0 = unlimited (the old behaviour). A few thousand
	// is plenty for a normal band; this is a safety ceiling, not the usual limiter.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "0"))
	int32 MaxLiveComponents = 4096;

	// Sink the crust this many VOXELS below the true surface, to avoid z-fighting at the
	// near-band seam (VerticalBiasVoxels-style — the same trick the far vista mesh uses).
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "0", ClampMax = "64"))
	int32 VerticalBiasVoxels = 3;

	// HANDOFF (kill transition holes): don't RELEASE a tile until the live voxel columns it
	// covers are meshed (proven by AVoxelWorld::AreCoveredColumnsReady). The tile is kept as a
	// harmless overlap — it's sunk VerticalBiasVoxels below the surface — until the near voxels
	// exist, so the crust->voxel swap never flashes a gap. OFF = the old blind distance release.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust")
	bool bHoldTilesUntilVoxelsReady = true;

	// ------------------------------------------------------------------------------------------
	// COMPONENT POOLING (improvement #1).
	// ------------------------------------------------------------------------------------------
	// As the player roams, tiles are constantly ensured (component created) and released
	// (component destroyed). Creating/destroying a UStaticMeshComponent every time churns the
	// render proxy and piles up garbage for the GC to sweep — exactly the kind of steady-state
	// cost we want to avoid on a streamer that runs forever. Instead, when a tile releases we
	// HIDE its component, clear the mesh, and park it on a free-list; when a tile ensures we
	// REUSE a parked component if one is waiting. The total component count stays roughly flat
	// and no render proxy is destroyed/recreated for a reused slot.
	//
	// This cap bounds how many idle (parked) components we keep around. A pool a bit larger than
	// the per-tick op budget is plenty — it only needs to absorb the normal release/ensure churn
	// of one roam. Anything beyond the cap is genuinely destroyed so we don't hoard memory if the
	// band suddenly shrinks. 0 = pooling OFF (always create/destroy, the old behaviour).
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "0", ClampMax = "256"))
	int32 MaxPooledComponents = 32;

	// ------------------------------------------------------------------------------------------
	// NANITE STREAMING POOL (improvement #3).
	// ------------------------------------------------------------------------------------------
	// Nanite streams its mesh data (the "pages") in and out of a fixed-size GPU pool. The default
	// pool is tuned for a normal level, not for a crust that can hold thousands of unique tiles
	// across a huge map — too small a pool and Nanite thrashes (visible LOD pop / detail churn as
	// it evicts pages it still needs). On BeginPlay, IF the crust is actually active (we have a
	// manifest), we bump two cvars so the big crust streams smoothly. We only touch them when the
	// crust runs, so a level without a crust keeps the engine defaults.
	//
	// IMPORTANT: these are the OVERRIDE values we set, not the engine defaults. The real 5.7
	// defaults should be verified in-engine (r.Nanite.Streaming.StreamingPoolSize has historically
	// defaulted around 512 MB; NumInitialRootPages around 2048) — set these at or above the default
	// for a big map and never below it. Negative / zero = "leave this cvar alone".

	// GPU streaming-pool size in MEGABYTES for r.Nanite.Streaming.StreamingPoolSize. Bigger = more
	// resident Nanite pages = less streaming thrash on a large crust, at the cost of VRAM.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "0"))
	int32 NaniteStreamingPoolSizeMB = 1024;

	// Root pages kept permanently resident (r.Nanite.Streaming.NumInitialRootPages). Every visible
	// Nanite mesh needs its root page resident; with thousands of crust tiles the default can be
	// too small, causing the lowest LOD to flicker. Bumping it keeps far tiles stable.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "0"))
	int32 NaniteNumInitialRootPages = 4096;

	// Master switch for the Nanite cvar tuning above. OFF = never touch the cvars (use whatever the
	// project/engine has set). ON = apply the two values on BeginPlay when the crust is active.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust")
	bool bTuneNaniteStreamingPool = true;

protected:
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;

private:
	// The loaded manifest (resolved from the soft pointer on BeginPlay).
	UPROPERTY(Transient)
	TObjectPtr<UVoxelBakeManifest> LoadedManifest = nullptr;

	// Live tile components, keyed by tile (X,Z). One UStaticMeshComponent per shown tile.
	TMap<FIntPoint, TObjectPtr<UStaticMeshComponent>> TileComponents;

	// Fast lookup from tile key -> manifest entry index (built on BeginPlay).
	TMap<FIntPoint, int32> TileIndex;

	// Tiles we've kicked an async soft-load for but haven't placed yet (so we don't
	// re-request every tick while the load is in flight).
	TSet<FIntPoint> PendingLoads;

	// COMPONENT POOL (improvement #1) — parked, hidden UStaticMeshComponents waiting to be
	// reused. ReleaseTile pushes here (after clearing the mesh + hiding) instead of destroying;
	// EnsureTile/PlaceTile pops from here instead of NewObject. Marked UPROPERTY so the GC keeps
	// the parked components alive while they sit idle (a bare TArray<UStaticMeshComponent*> would
	// not root them and they could be collected out from under us).
	UPROPERTY(Transient)
	TArray<TObjectPtr<UStaticMeshComponent>> ComponentPool;

	// ASYNC-LOAD HANDLE LIFETIME (improvement #2) — the streamable handle for each tile whose mesh
	// is loaded (or loading). Holding the handle is what KEEPS the mesh from being garbage-collected
	// while the tile is resident; dropping the handle on release is what lets an unloaded mesh
	// actually be freed. Keyed by tile so we can release exactly the right one. We keep the handle
	// from the moment we request the load (covers the in-flight window) right through residency, and
	// only drop it in ReleaseTile.
	TMap<FIntPoint, TSharedPtr<struct FStreamableHandle>> TileLoadHandles;

	// Apply the Nanite streaming-pool cvars (improvement #3). Called once from BeginPlay when the
	// crust is active and bTuneNaniteStreamingPool is on.
	void ApplyNaniteStreamingTuning();

	// Hide a component and return it to the pool (or destroy it if the pool is full / pooling off).
	void RecycleComponent(UStaticMeshComponent* Comp);

	// Take a pooled component if one is available (un-hidden, ready to receive a mesh), else create
	// a fresh one. Returns null only if NewObject fails.
	UStaticMeshComponent* AcquireComponent();

	// The live voxel world (owns the near editable band). Resolved lazily; used to gate tile
	// RELEASE on near-terrain readiness so the handoff overlaps instead of leaving a hole.
	TWeakObjectPtr<AVoxelWorld> CachedVoxelWorld;
	AVoxelWorld* ResolveVoxelWorld();

	// ~1 Hz throttle for the "[MiraThalCrust] tiles=N" diagnostic (the previously-missing crust
	// tile counter — so the perf forensics can confirm the crust is actually streaming).
	float StatLogAccum = 0.0f;

	// FOCUS-CHUNK CACHE (perf fix). The crust band only MOVES when the player crosses into a new
	// chunk (chunks are 3.2 m). Standing still — or walking around within one chunk — means the
	// exact same set of wanted tiles, so re-running the whole sweep+sort+ensure+release every frame
	// was pure waste (the 291 ms/frame bug). We remember the last chunk we actually rescanned at;
	// if the focus hasn't changed chunk AND there's no outstanding load work, Tick skips the heavy
	// scan entirely. NOTE: because the set only depends on the focus chunk and the fixed Inner/Outer
	// band, a designer who edits Inner/Outer live won't see it picked up until the focus chunk
	// changes (or the next forced rescan) — an acceptable trade for killing the per-frame cost.
	mira::Vec2i LastFocusChunk = mira::Vec2i(0, 0);
	bool bHasLastFocus = false;          // false until the first rescan runs (forces a BeginPlay scan)

	// THROTTLE accumulator — seconds since the last real rescan. Compared against RescanIntervalSec
	// so a fast flier doesn't rescan every frame even as it crosses many chunks per second.
	float RescanAccum = 0.0f;

	// Where the band centres this tick (the focus's chunk XZ). Returns false if no focus.
	bool GetFocusChunkXZ(mira::Vec2i& OutChunkXZ) const;

	// Ensure a tile's component exists (async-load its mesh, then place it). May no-op
	// this tick if the soft load isn't ready yet.
	void EnsureTile(const FIntPoint& TileKey);

	// Destroy a tile's component (it drifted out of band).
	void ReleaseTile(const FIntPoint& TileKey);

	// Place a freshly-loaded tile mesh: spawn the component, scale by stride, offset by
	// the tile origin + sunk base-Y, register it.
	void PlaceTile(const FIntPoint& TileKey, class UStaticMesh* Mesh);
};
