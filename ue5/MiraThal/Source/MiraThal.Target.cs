// MiraThal.Target.cs — game/runtime build target (packaged game + dedicated server share this).
using UnrealBuildTool;
using System.Collections.Generic;

public class MiraThalTarget : TargetRules
{
	public MiraThalTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
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
