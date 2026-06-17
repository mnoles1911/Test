// VoxelFarHeightmesh.h — the whole-map vista actor (T3 / P4).
//
// Draws ONE coarse mesh of the entire 5 km EXR so you can stand on a high point
// and see the full map silhouette out to the horizon. It is NOT voxels — it's a
// smooth low-resolution heightfield (Core/FarHeightmesh) coloured with the same
// palette as the cubes, sitting a couple of voxels BELOW the true surface so the
// near voxel terrain always renders on top of it without z-fighting.
//
// Standalone actor with its own EXR knobs (mirrors AVoxelWorld's heightmap import)
// so it can be dropped into a level on its own. Press Build Far Mesh in the
// Details panel (or it builds on BeginPlay).

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/ImageHeightmap.h"   // mira::ImageHeightmap (held directly)
#include "VoxelFarHeightmesh.generated.h"

class UProceduralMeshComponent;
class UMaterialInterface;

UCLASS()
class MIRATHALVOXEL_API AVoxelFarHeightmesh : public AActor
{
	GENERATED_BODY()

public:
	AVoxelFarHeightmesh();

	// --- EXR source (same meaning as AVoxelWorld's heightmap knobs) ---
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh", meta = (FilePathFilter = "exr"))
	FFilePath HeightmapFile;

	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh", meta = (ClampMin = "10", ClampMax = "50000"))
	float MapSpanMeters = 5000.0f;

	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh", meta = (ClampMin = "1", ClampMax = "9000"))
	float HeightmapAltitudeMeters = 700.0f;

	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh", meta = (ClampMin = "0", ClampMax = "1000"))
	float HeightmapBaseMeters = 12.0f;

	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh")
	bool bFlipHeightmapZ = true;

	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh")
	int32 Seed = 1337;

	// Vertices per side over the WHOLE map. 512 -> ~10 m/vertex on a 5 km map;
	// 1024 -> ~5 m. Higher = sharper silhouette, more triangles (one static mesh).
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh", meta = (ClampMin = "8", ClampMax = "2048"))
	int32 GridResolution = 512;

	// Sink the vista this many voxels below the true surface so near voxels win.
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh", meta = (ClampMin = "0", ClampMax = "50"))
	int32 VerticalBiasVoxels = 2;

	// Flip triangle winding if the surface renders inside-out (faces downward).
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh")
	bool bReverseWinding = true;

	// Vertex-color terrain material (reuse M_VoxelTerrainV2 so far hue == near hue).
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh")
	TObjectPtr<UMaterialInterface> Material;

	// Build it on play (so a shipped level shows the vista without a button press).
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh")
	bool bBuildOnBeginPlay = true;

	// Decode the EXR, build the whole-map mesh, upload it. CallInEditor button.
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|FarMesh")
	void BuildFarMesh();

	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|FarMesh")
	void ClearFarMesh();

protected:
	virtual void BeginPlay() override;

private:
	UPROPERTY(Transient)
	TObjectPtr<UProceduralMeshComponent> Mesh;

	// The decoded EXR (georeferenced), held for the build.
	mira::ImageHeightmap Heightmap;

	// Load + georeference HeightmapFile into Heightmap. False (and logs) on failure.
	bool LoadHeightmap();
};
