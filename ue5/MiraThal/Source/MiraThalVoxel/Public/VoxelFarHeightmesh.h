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

	// Sink the vista this many voxels below the true surface so near voxels win. The
	// vista is COARSE (one vertex per ~13 m at GridResolution 384); between samples it
	// linearly interpolates, so on steep terrain it can bulge ABOVE the per-voxel near
	// surface and poke through. A bigger sink keeps the near voxels on top everywhere.
	// 24 voxels = 2.4 m below; from a distance the silhouette drop is imperceptible.
	// (Concave valleys are the worst case for the coarse mesh bulging up; a finer
	// GridResolution plus this sink is what keeps near voxels on top there.)
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh", meta = (ClampMin = "0", ClampMax = "80"))
	int32 VerticalBiasVoxels = 24;

	// CONSERVATIVE (always-below) vista height — FIXES the bug where the smooth vista
	// silhouette pokes THROUGH the near voxel cubes at ridges/peaks. When ON, each
	// grid vertex takes the LOWEST ground over the little square of terrain it covers
	// (instead of one centre point), so the coarse mesh can never bulge above the true
	// per-voxel surface and the near cubes always render on top. Default ON because it
	// fixes a named visual bug; flip OFF to recover the original single-sample look.
	// (VerticalBiasVoxels still applies on top as an extra safety sink.)
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh")
	bool bConservativeVistaHeight = true;

	// How many fine sub-samples per axis to scan across each cell when
	// bConservativeVistaHeight is ON (so this^2 height reads per vertex). 3 (=9 reads)
	// is enough to catch the worst-case bulge between grid vertices; higher is more
	// conservative but costs a slightly lower silhouette and more build-time reads.
	// Ignored when bConservativeVistaHeight is OFF.
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh", meta = (ClampMin = "2", ClampMax = "9", EditCondition = "bConservativeVistaHeight"))
	int32 ConservativeFootprintSamples = 3;

	// Flip triangle winding if the surface renders inside-out (faces downward).
	// Default false = front faces point UP (correct: the voxel->UE axis swap already
	// keeps the Core's +Y winding facing up once mapped). Verified in-editor.
	UPROPERTY(EditAnywhere, Category = "MiraThal|FarMesh")
	bool bReverseWinding = false;

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
