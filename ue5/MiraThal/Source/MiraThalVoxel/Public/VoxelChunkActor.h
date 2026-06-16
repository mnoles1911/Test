// VoxelChunkActor.h — M1: generate ONE chunk, mesh it with the Core, render it.
//
// Drop this actor into an empty Lumen level and it builds a 32^3 voxel chunk on
// construction (and on BeginPlay): fill a slab -> greedy_mesh + water + flora ->
// ProceduralMesh. This is the first proof the engine-agnostic Core renders, and
// the perf "Baseline" the later milestones measure against.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "VoxelChunkActor.generated.h"

class UProceduralMeshComponent;
class UMaterialInterface;

// Engine-agnostic Core slab type (pure C++; real include lives in the .cpp).
namespace mira { struct DenseGrid; }

UCLASS()
class MIRATHALVOXEL_API AVoxelChunkActor : public AActor
{
	GENERATED_BODY()

public:
	AVoxelChunkActor();

	// The mesh this actor builds into.
	UPROPERTY(VisibleAnywhere, Category = "MiraThal|Voxel")
	UProceduralMeshComponent* Mesh = nullptr;

	// Default OFF: the Y/Z basis swap turned out NOT to need a winding flip
	// (verified visually). Tick this only if a chunk ever renders inside-out.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel")
	bool bReverseWinding = false;

	// false = a hand-built test pattern (flat ground + pillar + water pool + flora,
	// the safest first-light shape). true = sample the real Core HeightmapGenerator
	// for ChunkCoord.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel")
	bool bUseGenerator = false;

	// Which chunk to generate (only used when bUseGenerator). Y=3 puts the chunk's
	// 32-voxel band around the generator's ~y100-120 ground so you see a surface.
	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel")
	FIntVector ChunkCoord = FIntVector(0, 3, 0);

	UPROPERTY(EditAnywhere, Category = "MiraThal|Voxel")
	int32 Seed = 1337;

	// When true, this chunk is driven by AVoxelWorld: it does NOT auto-rebuild on
	// construction/BeginPlay; the world calls RenderManaged() directly with a slab
	// it extracted from the authoritative brickmap. (M2 multi-chunk world.)
	UPROPERTY()
	bool bWorldManaged = false;

	// Rebuild from the editor without PIE (button in the Details panel). Standalone
	// (non-world-managed) path only — builds from test pattern or the generator.
	UFUNCTION(CallInEditor, Category = "MiraThal|Voxel")
	void Rebuild();

	// World-managed render entry: greedy-mesh a pre-filled apron'd slab (the world
	// extracted it from the brickmap), upload it, and assign per-FaceClass materials.
	// Opaque/Cutout share the terrain material; Water/Flora get their own.
	void RenderManaged(const mira::DenseGrid& Slab,
	                   UMaterialInterface* OpaqueMat,
	                   UMaterialInterface* WaterMat,
	                   UMaterialInterface* FloraMat,
	                   bool bCollision,
	                   bool bReverse);

protected:
	virtual void BeginPlay() override;
	virtual void OnConstruction(const FTransform& Transform) override;
};
