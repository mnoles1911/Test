// MiraThalNet.Build.cs — multiplayer / replication helpers (Phase 4).
//
// Rebuilds the Godot host-authoritative model (NetTransport/MultiplayerManager,
// MP-3 voxel-edit routing) on UE dedicated-server replication + Steam sessions.
// Thin for now; fleshed out in Phase 4.
using UnrealBuildTool;

public class MiraThalNet : ModuleRules
{
	public MiraThalNet(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"MiraThalVoxel", // server-authoritative voxel edits route through the subsystem
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"OnlineSubsystem",
			"OnlineSubsystemUtils",
		});
	}
}
