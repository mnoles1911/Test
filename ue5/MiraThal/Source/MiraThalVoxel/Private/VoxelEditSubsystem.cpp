// VoxelEditSubsystem.cpp — edit gateway implementation.
//
// NOTE: the actual voxel-world mutation calls are stubbed until Voxel Plugin Pro
// is installed on the build machine (see MiraThalVoxel.Build.cs). The QUEUEING,
// NoEditZone gate, budget, and edit-applied broadcast are all live now so the
// gameplay layer (mining tool, explosions, water, gravity) can be wired and
// tested against this contract before the plugin is dropped in.
#include "VoxelEditSubsystem.h"

void UVoxelEditSubsystem::QueueEditSphere(const FVector& WorldCenter, double RadiusMeters, int32 Value)
{
	if (IsInNoEditZone(WorldCenter))
	{
		return; // rejected — mirrors VoxelEditManager NoEditZone short-circuit
	}
	FVoxelEditCommand Cmd;
	Cmd.Shape    = FVoxelEditCommand::EShape::Sphere;
	Cmd.WorldMin = WorldCenter;
	Cmd.RadiusM  = RadiusMeters;
	Cmd.Value    = Value;
	PendingEdits.Add(Cmd);
}

void UVoxelEditSubsystem::QueueEditBox(const FVector& WorldMin, const FVector& WorldMax, int32 Value)
{
	const FVector Center = (WorldMin + WorldMax) * 0.5;
	if (IsInNoEditZone(Center))
	{
		return;
	}
	FVoxelEditCommand Cmd;
	Cmd.Shape    = FVoxelEditCommand::EShape::Box;
	Cmd.WorldMin = WorldMin;
	Cmd.WorldMax = WorldMax;
	Cmd.Value    = Value;
	PendingEdits.Add(Cmd);
}

void UVoxelEditSubsystem::QueueSetVoxel(const FVector& WorldPos, int32 Value)
{
	if (IsInNoEditZone(WorldPos))
	{
		return;
	}
	FVoxelEditCommand Cmd;
	Cmd.Shape    = FVoxelEditCommand::EShape::Single;
	Cmd.WorldMin = WorldPos;
	Cmd.Value    = Value;
	PendingEdits.Add(Cmd);
}

void UVoxelEditSubsystem::RegisterNoEditZone(const FBox& WorldBox)
{
	NoEditZones.Add(WorldBox);
}

bool UVoxelEditSubsystem::IsInNoEditZone(const FVector& WorldPos) const
{
	for (const FBox& Zone : NoEditZones)
	{
		if (Zone.IsInsideOrOn(WorldPos))
		{
			return true;
		}
	}
	return false;
}

void UVoxelEditSubsystem::Tick(float DeltaSeconds)
{
	DrainQueue(DeltaSeconds);
}

void UVoxelEditSubsystem::DrainQueue(float /*DeltaSeconds*/)
{
	if (PendingEdits.Num() == 0)
	{
		return;
	}

	// TODO(Phase 0, step 3-4): apply against the Voxel Plugin world here,
	// spreading across frames on VoxelsPerFrame. For now drain everything and
	// broadcast so subscribers (gravity/water/LOD) can be exercised end-to-end.
	TArray<FVoxelEditCommand> Applied = MoveTemp(PendingEdits);
	PendingEdits.Reset();

	OnEditsApplied.Broadcast(Applied);
}
