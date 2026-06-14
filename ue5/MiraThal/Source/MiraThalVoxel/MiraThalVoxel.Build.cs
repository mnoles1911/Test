// MiraThalVoxel.Build.cs — generation / water / gravity / edit-routing module.
//
// Houses the engine-agnostic Core (Public/Core/*.h, pure C++17, no Unreal types)
// plus the thin UE wrapper layer (subsystems, settings) that adapts Unreal types
// to the Core and drives the Voxel Plugin world.
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
			// "Voxel" — Voxel Plugin Pro. Re-enable once the plugin is installed
			// into Plugins/Voxel on the build machine. The VoxelWorld + runtime
			// edit wrappers (VoxelEditSubsystem) link against it. Left commented
			// so the pure-Core + settings layer compiles even before the licensed
			// plugin is dropped in.
			// "Voxel",
		});

		// Core/ is included via this module's Public dir; the standalone clang
		// harness (tests/standalone) compiles the SAME headers with no Unreal.
	}
}
