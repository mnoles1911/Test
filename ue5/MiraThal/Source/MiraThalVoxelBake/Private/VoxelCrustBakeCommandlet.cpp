// VoxelCrustBakeCommandlet.cpp — headless cook-time entry for the Nanite crust bake.
// (UCLASS lives in the header so UHT generates the .generated.h; see VoxelCrustBakeCommandlet.h.)
#include "VoxelCrustBakeCommandlet.h"

#if WITH_EDITOR

#include "VoxelCrustBaker.h"
#include "VoxelBakeManifest.h"
#include "VoxelWorld.h"
#include "Engine/World.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"               // TActorIterator
#include "FileHelpers.h"               // FEditorFileUtils::LoadMap
#include "Editor.h"                    // GEditor

int32 UVoxelCrustBakeCommandlet::Main(const FString& Params)
{
	// --- Parse the command line ------------------------------------------------
	TArray<FString> Tokens, Switches;
	TMap<FString, FString> ParamMap;
	UCommandlet::ParseCommandLine(*Params, Tokens, Switches, ParamMap);

	FString MapPath;
	if (const FString* S = ParamMap.Find(TEXT("Map"))) { MapPath = *S; }
	FString WorldSaveName = TEXT("DefaultWorld");
	if (const FString* S = ParamMap.Find(TEXT("WorldSaveName"))) { WorldSaveName = *S; }

	// MERGE mode (-Merge): combine the parallel bake's text shards into the final Manifest.uasset
	// and exit. Pure asset work — no map load / generator needed. Run after all -Shards processes.
	if (Switches.Contains(TEXT("Merge")))
	{
		const bool bMerged = VoxelCrustBaker::MergeShards(WorldSaveName);
		return bMerged ? 0 : 1;
	}

	VoxelCrustBaker::FBakeSettings Settings;
	if (const FString* S = ParamMap.Find(TEXT("Tile")))   { Settings.TileSpanVoxels   = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("Stride"))) { Settings.Stride           = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("Skirt")))  { Settings.SkirtDepthVoxels = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("Radius"))) { Settings.TileRadius       = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("MaxTiles")))     { Settings.MaxTilesPerBake      = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("TestRing")))     { Settings.TestBakeRadiusChunks = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("Shards")))       { Settings.ShardCount = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("Shard")))        { Settings.ShardIndex = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("Region")))       { Settings.RegionTilesPerSide  = FCString::Atoi(**S); }
	if (const FString* S = ParamMap.Find(TEXT("Nanite")))       { Settings.bEnableNanite = (FCString::Atoi(**S) != 0); }
	// -GeoMerge (a bare switch, or -GeoMerge=1): fuse each region's tiles into ONE merged mesh +
	// ONE manifest entry (shipping-scale asset-count reduction; needs -Region>0). Default off.
	if (Switches.Contains(TEXT("GeoMerge")))                    { Settings.bGeometryMerge = true; }
	if (const FString* S = ParamMap.Find(TEXT("GeoMerge")))     { Settings.bGeometryMerge = (FCString::Atoi(**S) != 0); }

	// --- Find (or make) the AVoxelWorld to bake --------------------------------
	AVoxelWorld* World = nullptr;

	if (!MapPath.IsEmpty() && GEditor)
	{
		// Load the map, then find the first AVoxelWorld in it.
		FEditorFileUtils::LoadMap(MapPath, /*bLoadAsTemplate=*/false, /*bShowProgress=*/false);
		if (UWorld* EditorWorld = GEditor->GetEditorWorldContext().World())
		{
			for (TActorIterator<AVoxelWorld> It(EditorWorld); It; ++It)
			{
				World = *It;
				break;
			}
		}
		if (!World)
		{
			UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] No AVoxelWorld found in map %s."), *MapPath);
			return 1;
		}
	}
	else
	{
		// No map: bake a transient procedural world (CI smoke-bake) using default knobs.
		UWorld* HostWorld = GEditor ? GEditor->GetEditorWorldContext().World() : nullptr;
		if (!HostWorld)
		{
			UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] No editor world to host a transient AVoxelWorld."));
			return 1;
		}
		World = HostWorld->SpawnActor<AVoxelWorld>();
		if (!World)
		{
			UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] Failed to spawn transient AVoxelWorld."));
			return 1;
		}
	}

	UVoxelBakeManifest* Manifest =
		VoxelCrustBaker::BakeWorldCrust(World, WorldSaveName, Settings);

	if (!Manifest)
	{
		UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] Headless crust bake FAILED."));
		return 1;
	}

	UE_LOG(LogTemp, Display, TEXT("[MiraThalBake] Headless crust bake done: %d tiles."),
		Manifest->Tiles.Num());
	return 0;
}

#else // !WITH_EDITOR

int32 UVoxelCrustBakeCommandlet::Main(const FString& /*Params*/)
{
	UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] VoxelCrustBake commandlet is editor-only."));
	return 1;
}

#endif // WITH_EDITOR
