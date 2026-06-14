// MiraThal.Target.cs — game/runtime build target (packaged game + dedicated server share this).
using UnrealBuildTool;
using System.Collections.Generic;

public class MiraThalTarget : TargetRules
{
	public MiraThalTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_4;

		ExtraModuleNames.AddRange(new string[]
		{
			"MiraThalVoxel",
			"MiraThalCore",
			"MiraThalNet",
		});
	}
}
