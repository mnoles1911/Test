// MiraThalVoxel.Build.cs — generation / water / gravity / edit-routing module.
//
// Houses the engine-agnostic Core (Public/Core/*.h, pure C++17, no Unreal types)
// plus the thin UE wrapper layer (subsystems, settings) AND the custom cubic
// greedy mesher (no third-party voxel plugin — see
// design/UE5_VOXEL_BACKEND_EVALUATION.md).
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
			"DeveloperSettings", // UVoxelScaleSettings (UDeveloperSettings)
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"ProceduralMeshComponent", // chunk meshes from the custom cubic greedy mesher
			"GeometryCore",            // mesh build helpers
			"PhysicsCore",             // Chaos collision from the generated meshes
		});

		// Core/ is included via this module's Public dir; the standalone clang
		// harness (tests/standalone) compiles the SAME headers with no Unreal.
	}
}
