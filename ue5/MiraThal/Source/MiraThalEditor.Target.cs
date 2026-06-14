// MiraThalEditor.Target.cs — editor build target (also runs headless Automation Specs).
using UnrealBuildTool;
using System.Collections.Generic;

public class MiraThalEditorTarget : TargetRules
{
	public MiraThalEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
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
