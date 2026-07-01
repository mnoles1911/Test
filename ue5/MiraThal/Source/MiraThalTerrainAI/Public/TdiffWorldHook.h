// TdiffWorldHook.h — the thin bridge that pushes an AI diffusion DEM onto an AVoxelWorld.
//
// WHAT THIS IS (plain English):
// FDiffusionDemService knows how to turn (seed, region) into a mira::ImageHeightmap. This
// file is the little "go button" that wires that to the live game: given an AVoxelWorld,
// a seed, and a region, it asks the service for the heightmap and INSTALLS it on the world
// (via AVoxelWorld::SetDiffusionHeightmap), then rebuilds the terrain so you can SEE it.
//
// DEPENDENCY DIRECTION (important): this lives in MiraThalTerrainAI, which depends on
// MiraThalVoxel. MiraThalVoxel does NOT depend on us. So the wiring is one-way: WE reach
// INTO the voxel world and hand it a finished ImageHeightmap (a type it already
// understands). The voxel module never references the AI module — the dep root is intact.
//
// HOW TO TRIGGER IT IN PIE (the ask): the .cpp registers a console command
//     MiraThal.Tdiff.FillRegion [Seed] [HalfExtentVoxels]
// so you can fire it live over the mcp-unreal bridge (run_console_command / execute the
// console) with no Blueprint setup. The BlueprintCallable functions below are the same
// path for designer/BP use.

#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "TdiffWorldHook.generated.h"

class AVoxelWorld;

UCLASS()
class MIRATHALTERRAINAI_API UTdiffWorldHook : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	// Build the AI DEM for the explicit voxel rectangle [MinX..MaxX] x [MinZ..MaxZ] and
	// install it on World as its DiffusionAI height source. When bRegenerate is true the
	// world is rebuilt immediately (GenerateWorld) so the new terrain is visible at once.
	// Returns false if World is null or the service couldn't produce a heightmap. Phase 1
	// uses the service's STUB coarse provider (analytic surface) — see DiffusionDemService.
	UFUNCTION(BlueprintCallable, Category = "MiraThal|Tdiff")
	static bool FillRegion(AVoxelWorld* World, int64 Seed,
	                       int32 MinX, int32 MinZ, int32 MaxX, int32 MaxZ,
	                       bool bRegenerate = true);

	// Convenience: a square region centred on the world origin, HalfExtentVoxels each way.
	// (E.g. 16384 ≈ a ±1.6 km bounded region.) Same install + rebuild behaviour as above.
	UFUNCTION(BlueprintCallable, Category = "MiraThal|Tdiff")
	static bool FillCenteredRegion(AVoxelWorld* World, int64 Seed,
	                               int32 HalfExtentVoxels = 16384, bool bRegenerate = true);

	// Move the player pawn ONTO the freshly-generated AI surface: spiral-search the nearby
	// (already-streamed) area for dry land (surface above sea) and place the pawn there; if
	// it is all ocean, drop to the water surface at the current XY. Shared by the bounded
	// FillRegion and the streaming MiraThal.Tdiff.Stream path so you never start floating
	// above / below the new terrain. No-op if World or the pawn is null.
	static void SnapPlayerToLand(AVoxelWorld* World);

	// Remove the LEGACY baked-EXR terrain layers that the test map still carries from the
	// earlier Nanite-bake milestone (AVoxelNaniteCrust x N + the far AVoxelFarHeightmesh), so
	// they do not render OVER the live AI terrain. Matched by class NAME (this module cannot
	// reference those types across the one-way dep), then destroyed. Idempotent. Called by
	// FillRegion + the streaming path so the AI terrain is cleanly THE world.
	static void RemoveBakedTerrain(AVoxelWorld* World);
};
