// VoxelBakeManifest.h — the index the baker WRITES and the runtime crust READS.
//
// WHAT THIS IS (plain English):
// The cold-bake produces one Nanite static-mesh .uasset per terrain TILE. The runtime
// crust needs to know, for a given player position, WHICH tile assets exist and where
// each one sits in the world — without scanning the disk. So the baker also writes this
// small data asset: a list of tile entries (the tile's X/Z key, its world-voxel bounds,
// and a SOFT pointer to its baked mesh). "Soft" = the manifest references the mesh by
// path and only actually loads it when the streamer asks — so opening the manifest
// doesn't pull every tile mesh into memory.
//
// It's a UDataAsset so the designer can see it in the content browser and the runtime
// can load it by soft path on BeginPlay.

#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Engine/StaticMesh.h"
#include "VoxelBakeManifest.generated.h"

// One baked tile's record. POD-ish UStruct so it serialises into the data asset.
USTRUCT(BlueprintType)
struct FVoxelBakeTileEntry
{
	GENERATED_BODY()

	// Tile key (X,Z) in TILE units (world voxel = tile * TileSpanVoxels + local).
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 TileX = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 TileZ = 0;

	// Inclusive world-voxel XZ bounds this tile covers (min corner / max corner). The
	// runtime uses these to place the static-mesh component and to compute band distance.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 MinVoxelX = 0;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 MinVoxelZ = 0;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 MaxVoxelX = 0;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 MaxVoxelZ = 0;

	// The fine-voxel Y the baked mesh's local origin sits at (the shell anchor —
	// sample_crust_slab's base_fine_y). The runtime offsets the component by this so the
	// crust lands on the same world grid as the near voxels.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 BaseFineY = 0;

	// Fine voxels per coarse cell the tile was baked at (the downsample stride). The
	// runtime scales the component by this (positions are in COARSE-cell units), exactly
	// like the super-chunk path scales by Stride.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 Stride = 1;

	// SOFT pointer to the baked Nanite mesh. Loaded on demand by the streamer.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	TSoftObjectPtr<UStaticMesh> Mesh;
};

// The whole index for one baked world. Lives at /Game/VoxelBake/<world>/Manifest.
UCLASS(BlueprintType)
class MIRATHALVOXELBAKE_API UVoxelBakeManifest : public UDataAsset
{
	GENERATED_BODY()

public:
	// The save-slot name this manifest was baked for (matches AVoxelWorld::WorldSaveName).
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	FString WorldSaveName;

	// Tile edge in voxels the bake used (default 512). The runtime needs it to convert a
	// world position into a tile key for the streaming ring.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	int32 TileSpanVoxels = 512;

	// Every baked tile.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "MiraThal|Bake")
	TArray<FVoxelBakeTileEntry> Tiles;
};
