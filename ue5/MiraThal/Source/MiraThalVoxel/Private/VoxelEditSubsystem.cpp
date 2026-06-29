// VoxelEditSubsystem.cpp — edit gateway implementation.
//
// ⚠️ SUPERSEDED / DORMANT (do NOT wire DrainQueue to a store). This subsystem was an
// early contract for the gameplay layer to queue edits against BEFORE the cubic mesher
// landed. The mesher is now in place and the ACTUAL, live voxel-edit path went a
// different way: the player (MiraFPCharacter) calls AVoxelWorld::CarveAtWorld, which
// applies writes to WorldStore (the brickmap) and journals them for reload-persistence.
// That is the project's SINGLE edit gateway (a non-negotiable: all voxel writes go
// through AVoxelWorld). DrainQueue is intentionally left a no-op broadcast — completing
// it to mutate a store would create a SECOND, competing edit path and break the
// single-gateway invariant (and the brickmap's authoritative-store guarantee). If this
// subsystem is ever truly needed, it must FORWARD to CarveAtWorld, never write directly.
// Kept (not deleted) only because the NoEditZone gate + queue contract may still be
// referenced by gameplay tests. Treat as dead-by-default.
//
// NOTE (historical): the QUEUEING, NoEditZone gate, budget, and edit-applied broadcast
// below are the original live-but-storeless contract.
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

	// TODO(Phase 0, step 3-4): apply against the cubic mesher's chunk store here,
	// spreading across frames on VoxelsPerFrame. For now drain everything and
	// broadcast so subscribers (gravity/water/LOD) can be exercised end-to-end.
	TArray<FVoxelEditCommand> Applied = MoveTemp(PendingEdits);
	PendingEdits.Reset();

	OnEditsApplied.Broadcast(Applied);
}
