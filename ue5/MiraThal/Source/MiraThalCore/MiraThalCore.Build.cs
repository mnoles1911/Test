// MiraThalCore.Build.cs — primary game module (gameplay glue grows here later).
//
// Trimmed to the M1 minimum. Combat/skills/UI deps (EnhancedInput, UMG, …) come
// back as those systems land — keeping the first build's surface small.
using UnrealBuildTool;

public class MiraThalCore : ModuleRules
{
	public MiraThalCore(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"InputCore",      // legacy axis input (WASD/mouse) for the test pawn
			"EnhancedInput",  // button actions (Jump/Sprint/Crouch/Fly/Dig) via Enhanced Input
			"MiraThalVoxel",
		});
	}
}
