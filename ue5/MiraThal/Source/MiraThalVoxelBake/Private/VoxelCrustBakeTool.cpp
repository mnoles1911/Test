// VoxelCrustBakeTool.cpp — the editor button implementation.
#include "VoxelCrustBakeTool.h"

AVoxelCrustBakeTool::AVoxelCrustBakeTool()
{
	PrimaryActorTick.bCanEverTick = false;
}

#if WITH_EDITOR
#include "VoxelCrustBaker.h"     // VoxelCrustBaker::BakeWorldCrust (editor-only)
#include "VoxelBakeManifest.h"   // UVoxelBakeManifest (the return type)
#include "VoxelWorld.h"
#endif

void AVoxelCrustBakeTool::BakeNaniteCrust()
{
#if WITH_EDITOR
	if (!TargetWorld)
	{
		UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] Set TargetWorld before baking."));
		return;
	}

	VoxelCrustBaker::FBakeSettings Settings;
	Settings.TileSpanVoxels       = TileSpanVoxels;
	Settings.Stride               = Stride;
	Settings.SkirtDepthVoxels     = SkirtDepthVoxels;
	Settings.TileRadius           = TileRadius;
	Settings.MaxTilesPerBake      = MaxTilesPerBake;
	Settings.TestBakeRadiusChunks = TestBakeRadiusChunks;

	UVoxelBakeManifest* Manifest =
		VoxelCrustBaker::BakeWorldCrust(TargetWorld, WorldSaveName, Settings);
	if (Manifest)
	{
		UE_LOG(LogTemp, Display, TEXT("[MiraThalBake] Crust bake complete for '%s'."), *WorldSaveName);
	}
	else
	{
		UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] Crust bake failed (see log; stop PIE if running)."));
	}
#else
	UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] BakeNaniteCrust is editor-only."));
#endif
}
