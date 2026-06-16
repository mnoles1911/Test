// MiraThalVoxel.Build.cs — generation / water / gravity / edit-routing / mesher module.
//
// Houses the engine-agnostic Core (Public/Core/*.h, pure C++17, no Unreal types)
// plus the thin UE layer: settings, the chunk actor, and the MeshBuffers -> UE
// mesh upload. M1 uses the built-in ProceduralMeshComponent as the mesh backend;
// RealtimeMeshComponent swaps in later behind IVoxelMeshSink for perf.
using UnrealBuildTool;

public class MiraThalVoxel : ModuleRules
{
	public MiraThalVoxel(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"DeveloperSettings",        // UVoxelScaleSettings (UDeveloperSettings)
			"ProceduralMeshComponent",  // M1 mesh backend (AVoxelChunkActor's mesh)
		});

		// Public/Core/*.h is on the public include path automatically, so the UE
		// code does `#include "Core/GreedyMesher.h"` and the SAME headers the
		// standalone clang harness compiles drop straight into this module.
	}
}
