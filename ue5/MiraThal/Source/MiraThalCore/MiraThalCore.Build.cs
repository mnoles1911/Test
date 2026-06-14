// MiraThalCore.Build.cs — gameplay module (player, combat, skills, entities, UI glue).
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
			"InputCore",
			"EnhancedInput",   // free-aim camera + directional-melee mouse sampling
			"MiraThalVoxel",   // gameplay queues edits through the voxel subsystem
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"UMG",             // HUD direction arrows / combat radar
			"Slate",
			"SlateCore",
			"GameplayTags",
		});
	}
}
