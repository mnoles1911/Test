// MiraThalEditor.Target.cs — editor build target (also runs headless Automation Specs).
using UnrealBuildTool;
using System.Collections.Generic;

public class MiraThalEditorTarget : TargetRules
{
	public MiraThalEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;

		ExtraModuleNames.AddRange(new string[]
		{
			"MiraThalVoxel",
			"MiraThalCore",
			"MiraThalNet",
			"MiraThalVoxelBake",
			"MiraThalVoxelRender", // P7/P8 GPU raymarch — gated off by default (r.MiraThal.GpuRaymarch)
			"MiraThalTerrainAI",   // live-runtime TerrainDiffusion (NNE + DirectML) -> voxel height source
		});
	}
}
