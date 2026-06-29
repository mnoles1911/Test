// MiraThalVoxelBake.Build.cs — the M6 "Nanite cold-bake" module.
//
// WHAT THIS MODULE IS FOR (plain English):
// Once a voxel chunk has been sitting still for a while and nobody is digging it,
// we want to stop paying the cost of a live, editable ProceduralMesh and instead
// "bake" that chunk's geometry into a permanent UStaticMesh with Nanite turned on.
// Nanite is Unreal's system for drawing huge, dense meshes cheaply by only ever
// rasterising about one triangle per pixel — perfect for far-away terrain.
//
// This module is the BAKER: it takes the same greedy mesh the live renderer uses
// (from the MiraThalVoxel module's engine-agnostic Core) and turns it into a
// Nanite-enabled static mesh. It deliberately reuses the exact same coordinate
// swap + scale + vertex-color packing as the live path (MiraVoxelMesh) so the
// baked chunk looks pixel-identical to the live one — same material, same colors.
//
// It is a RUNTIME module (not editor-only) because the bake happens during play
// as chunks go quiet. Note: building Nanite data at runtime relies on engine
// build paths; see VoxelNaniteBaker.cpp's // VERIFY: notes about the runtime-vs-
// editor build entrypoint.
using UnrealBuildTool;

public class MiraThalVoxelBake : ModuleRules
{
	public MiraThalVoxelBake(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",                  // UStaticMesh, UStaticMeshComponent, AActor
			"MiraThalVoxel",           // the Core meshers (mira::greedy_mesh) + MiraVoxelMesh swap/scale
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"RenderCore",              // render-data plumbing pulled in by the static-mesh build
			"MeshDescription",         // FMeshDescription — the engine's portable mesh container
			"StaticMeshDescription",   // FStaticMeshAttributes + FStaticMeshOperations (tangents)
			// "MeshConversion",       // not needed: the hand-rolled FStaticMeshAttributes path
			//                         //         below doesn't use FMeshDescriptionBuilder.
		});

		// EDITOR-ONLY deps — the COLD-BAKE side (package create + save + asset-registry
		// notify) only exists in editor/commandlet builds. The runtime crust streamer and
		// the BuildNaniteStaticMeshFromMesh helper need none of these, so we guard them so
		// a cooked/runtime build of this module doesn't drag in editor modules.
		if (Target.bBuildEditor)
		{
			PrivateDependencyModuleNames.AddRange(new string[]
			{
				"UnrealEd",        // GEditor->PlayWorld guard, editor-time build path
				"AssetRegistry",   // FAssetRegistryModule::AssetCreated (register the .uasset)
				"AssetTools",      // asset create/save helpers
			});
		}

		// MiraThalVoxel exposes Public/Core/*.h on its public include path, so we can
		// `#include "Core/GreedyMesher.h"` and friends straight from here, and we can
		// `#include "MiraVoxelMesh.h"` to reuse PositionToUE / NormalToUE / VoxelToUU.
	}
}
