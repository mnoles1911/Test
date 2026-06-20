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

	// Max tile ensure/release ops per tick — caps per-frame streaming cost.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "1", ClampMax = "64"))
	int32 MaxOpsPerTick = 4;

	// Sink the crust this many VOXELS below the true surface, to avoid z-fighting at the
	// near-band seam (VerticalBiasVoxels-style — the same trick the far vista mesh uses).
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|NaniteCrust", meta = (ClampMin = "0", ClampMax = "64"))
	int32 VerticalBiasVoxels = 3;

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
