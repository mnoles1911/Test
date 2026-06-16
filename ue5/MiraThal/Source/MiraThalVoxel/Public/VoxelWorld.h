// VoxelWorld.h — M2: the multi-chunk world manager.
//
// AVoxelWorld owns the single authoritative voxel store (a sparse mira::Brickmap)
// and a grid of AVoxelChunkActor renderers. It:
//   * GENERATES a region of terrain from the Core HeightmapGenerator (10 vox/m,
//     10cm cubes) into the brickmap, then meshes every non-empty chunk.
//   * EDITS the world (CarveTestHole / CarveAtWorld): apply Core MiningCarve
//     writes to the brickmap, then re-mesh only the chunks the edit touched
//     (including apron-neighbours) — the M2 "dig under Lumen" loop.
//
// The brickmap is the single source of truth; chunk actors are pure renderers
// that read apron'd slabs out of it (Core/BrickmapMeshing). This is the data
// model the docs describe and the foundation M4 streaming / M7 GPU mirror build on.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/Brickmap.h"   // mira::Brickmap — the authoritative store, held directly
#include "VoxelWorld.generated.h"

class UMaterialInterface;
class AVoxelChunkActor;

UCLASS()
class MIRATHALVOXEL_API AVoxelWorld : public AActor
{
	GENERATED_BODY()

public:
	AVoxelWorld();

	// World generation seed (fed to the Core HeightmapGenerator).
	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	int32 Seed = 1337;

	// --- Terrain shape (legacy generator knobs). The raw generator defaults swing
	//     ±75 m (height_range 1500) which makes vertical spires; these gentle values
	//     give rolling ~8 m hills with lakes at sea level. Tune to taste in editor. ---

	// Macro layer total range in voxels (the ± swing is half this). 140 -> ±7 m.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Terrain", meta = (ClampMin = "20", ClampMax = "2000"))
	float MacroRangeVoxels = 140.0f;

	// Mid-detail amplitude in voxels (smaller bumps on top of the macro relief).
	UPROPERTY(EditAnywhere, Category = "MiraThal|Terrain", meta = (ClampMin = "0", ClampMax = "200"))
	int32 MidAmplitudeVoxels = 14;

	// Base ground height in voxels. Sea level is 120, so 110 puts valleys underwater.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Terrain", meta = (ClampMin = "0", ClampMax = "400"))
	int32 HeightOffsetVoxels = 110;

	// Macro noise frequency (per voxel). Higher = hills repeat over a shorter
	// distance. 0.005/voxel ≈ a hill every ~20 m at 10 vox/m.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Terrain", meta = (ClampMin = "0.0005", ClampMax = "0.05"))
	float MacroFrequency = 0.005f;

	// Horizontal extent: chunks each way from centre in X and Z. 3 -> a 7x7 grid
	// of columns (7*32 = 224 voxels = 22.4 m across). Keep modest until streaming.
	UPROPERTY(EditAnywhere, Category = "MiraThal|World", meta = (ClampMin = "0", ClampMax = "16"))
	int32 ChunkRadiusXZ = 3;

	// Vertical extent below the surface chunk, in chunks. 2 -> ~64 voxels (6.4 m)
	// of dug-able depth meshed under the surface; deeper rock is generated on dig.
	UPROPERTY(EditAnywhere, Category = "MiraThal|World", meta = (ClampMin = "1", ClampMax = "8"))
	int32 ChunkDepthBelow = 2;

	// Chaos collision on the chunk meshes (so the player/physics interact + we can
	// line-trace for the dig cursor). On by default for M2.
	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	bool bCreateCollision = true;

	// Solid-colour terrain material (vertex-colour albedo + AO in alpha). Opaque
	// and cutout faces use this; water and flora get their own.
	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	TObjectPtr<UMaterialInterface> TerrainMaterial;

	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	TObjectPtr<UMaterialInterface> WaterMaterial;

	UPROPERTY(EditAnywhere, Category = "MiraThal|World")
	TObjectPtr<UMaterialInterface> FloraMaterial;

	// Build (or rebuild) the whole region from the generator. CallInEditor button.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|World")
	void GenerateWorld();

	// Destroy all chunk actors and clear the brickmap.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|World")
	void ClearWorld();

	// Editor convenience: dig a Full (5^3) box straight down into the surface at
	// the world centre, so the dig loop is visible from the Details panel with no
	// gameplay input. Demonstrates the M2 carve->re-mesh path.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|World")
	void CarveTestHole();

	// Programmatic carve at a UE world-space hit point (cm) with a surface normal,
	// removing an N^3 box (depth-biased into terrain). Applies to the brickmap and
	// re-meshes affected chunks. This is the entry a player tool / RPC will call.
	void CarveAtWorld(const FVector& WorldPos, const FVector& HitNormal, int32 SideVoxels);

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;

	// The spawned chunk renderers, keyed by chunk coord.
	UPROPERTY(Transient)
	TMap<FIntVector, TObjectPtr<AVoxelChunkActor>> ChunkActors;

private:
	// The single authoritative voxel store, held directly (pure C++; not a UPROPERTY
	// — it's not a UObject, just the sparse brick hash the renderers read from).
	// Named WorldStore (not "Brickmap") to avoid colliding with the mira::Brickmap type.
	mira::Brickmap WorldStore;

	// Fill the brickmap from the generator across the configured region.
	void GenerateRegion();

	// Extract the chunk's slab from the brickmap and (re)render it; skips/destroys
	// the actor when the chunk is fully empty.
	void RemeshChunk(const FIntVector& ChunkCoord);

	// Find or spawn the renderer actor for a chunk coord, positioned so its slab
	// tiles seamlessly with neighbours (apron offset folded into the transform).
	AVoxelChunkActor* EnsureChunkActor(const FIntVector& ChunkCoord);
	void DestroyChunkActor(const FIntVector& ChunkCoord);

	// UE world location for a chunk's renderer actor.
	FVector ChunkActorLocation(const FIntVector& ChunkCoord) const;
};
