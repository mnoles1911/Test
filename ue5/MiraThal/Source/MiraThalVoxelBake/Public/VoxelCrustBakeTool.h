// VoxelCrustBakeTool.h — the EDITOR BUTTON that triggers the Nanite crust bake.
//
// WHY THIS IS A SEPARATE OBJECT (plain English / architecture):
// The bake lives in the EDITOR-only MiraThalVoxelBake module. The live voxel module
// MiraThalVoxel must NOT depend on the editor bake module (that would be a circular /
// editor-into-runtime dependency). So the "Bake Nanite Crust" button can't go on
// AVoxelWorld directly. Instead it lives HERE, on a small editor utility actor that
// holds a pointer to the AVoxelWorld to bake. The designer drops one of these in the
// level (or uses it transiently), points TargetWorld at their AVoxelWorld, sets the
// tile/skirt/stride knobs, and clicks "Bake Nanite Crust".
//
// EDITOR-ONLY by construction (the bake produces saved assets). The CallInEditor
// function body is guarded WITH_EDITOR.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "VoxelCrustBakeTool.generated.h"

class AVoxelWorld;

UCLASS()
class MIRATHALVOXELBAKE_API AVoxelCrustBakeTool : public AActor
{
	GENERATED_BODY()

public:
	AVoxelCrustBakeTool();

	// The world whose far terrain to cold-bake into Nanite crust tiles. Set this in the
	// level details panel before clicking the button.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Bake")
	TObjectPtr<AVoxelWorld> TargetWorld = nullptr;

	// Asset folder / save slot name: tiles land at /Game/VoxelBake/<WorldSaveName>/...
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Bake")
	FString WorldSaveName = TEXT("DefaultWorld");

	// Tile edge in VOXELS (512 = 51.2 m). Bigger = fewer, larger assets.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Bake", meta = (ClampMin = "64", ClampMax = "4096"))
	int32 TileSpanVoxels = 512;

	// Fine voxels per coarse cell (downsample). Keep TileSpan/Stride <= 32 (512/16 = 32).
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Bake", meta = (ClampMin = "1", ClampMax = "64"))
	int32 Stride = 16;

	// Fine voxels of skirt below the surface (cliff / seam thickness).
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Bake", meta = (ClampMin = "0", ClampMax = "256"))
	int32 SkirtDepthVoxels = 128;

	// Half-extent of the bake region in TILES around the origin: tiles [-R..R] each axis.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Bake", meta = (ClampMin = "0", ClampMax = "256"))
	int32 TileRadius = 8;

	// SAFETY CAP — max tiles to build+save THIS run. 0 = no cap (bake the whole band).
	// Set a small number (e.g. 4 or 9) for a safe, observable first bake; watch the
	// Output Log for the per-tile "BAKE tile X/Y ..." lines, then bump it up once happy.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Bake|Safety", meta = (ClampMin = "0", ClampMax = "100000"))
	int32 MaxTilesPerBake = 0;

	// SAFETY RING — bake ONLY tiles within this many CHUNKS of the world origin. 0 = the
	// full TileRadius square. Set this small (e.g. 0 or 1) together with MaxTilesPerBake
	// to bake just a tiny ring of tiles near the player for a first smoke test.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MiraThal|Bake|Safety", meta = (ClampMin = "0", ClampMax = "1024"))
	int32 TestBakeRadiusChunks = 0;

	// THE BUTTON. Bakes the crust for TargetWorld. (Refuses to run during PIE.)
	UFUNCTION(CallInEditor, BlueprintCallable, Category = "MiraThal|Bake")
	void BakeNaniteCrust();
};
