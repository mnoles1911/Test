// VoxelEditSubsystem.h — THE single gateway for every voxel write.
//
// Ported contract from Godot scripts/VoxelEditManager.gd. In the Godot build,
// nothing was allowed to call raw VoxelTool — every carve/fill/place went
// through VoxelEditManager so it could (1) reject edits inside NoEditZones,
// (2) spread big edits across frames on a voxel budget, (3) track edited chunks,
// (4) fire an edit-applied event, and (5) route through multiplayer RPCs.
//
// This subsystem preserves that contract on UE. It is the ONLY thing that calls
// into the Voxel Plugin's edit API. Gameplay (mining, explosions, water, gravity
// re-deposits) queues edits here; it never touches the voxel world directly.
//
// Multiplayer (Phase 4): on a client these calls become a server RPC request;
// the server validates + applies + multicasts. Mirrors the Godot MP-3 routing.
#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "Core/MiraVec.h"
#include "VoxelEditSubsystem.generated.h"

// One queued voxel write. Shapes mirror the Godot queue_edit_* family.
USTRUCT()
struct FVoxelEditCommand
{
	GENERATED_BODY()

	enum class EShape : uint8 { Sphere, Box, Single };

	EShape Shape = EShape::Sphere;
	FVector WorldMin = FVector::ZeroVector; // box min, or sphere centre
	FVector WorldMax = FVector::ZeroVector; // box max (unused for sphere/single)
	double  RadiusM  = 0.0;                  // sphere radius (metres)
	int32   Value    = 0;                    // material id / 0 = air (carve)
};

// Broadcast after a batch of edits is actually applied to the world. Gravity,
// water-settle, and the LOD-bake invalidation all subscribe (as the Godot
// edit_applied signal subscribers did).
DECLARE_MULTICAST_DELEGATE_OneParam(FOnVoxelEditsApplied, const TArray<FVoxelEditCommand>& /*Applied*/);

UCLASS()
class MIRATHALVOXEL_API UVoxelEditSubsystem : public UWorldSubsystem
{
	GENERATED_BODY()

public:
	// ---- Canonical write API (the only sanctioned way to change voxels) ----

	// Carve (Value=0) or fill a sphere of world-space radius (metres).
	void QueueEditSphere(const FVector& WorldCenter, double RadiusMeters, int32 Value);

	// Carve or fill an axis-aligned box in world space.
	void QueueEditBox(const FVector& WorldMin, const FVector& WorldMax, int32 Value);

	// Set one voxel (precision placement).
	void QueueSetVoxel(const FVector& WorldPos, int32 Value);

	FOnVoxelEditsApplied OnEditsApplied;

	// ---- NoEditZone gate (settlements / landmarks are write-protected) ----
	void RegisterNoEditZone(const FBox& WorldBox);
	bool IsInNoEditZone(const FVector& WorldPos) const;

	// UWorldSubsystem
	virtual void Tick(float DeltaSeconds);

protected:
	// Drain up to VoxelsPerFrame worth of queued work and apply to the Voxel
	// Plugin world. Implemented in the .cpp against the plugin API once the
	// licensed plugin is installed; until then it logs + no-ops so the rest of
	// the gameplay layer can be exercised.
	void DrainQueue(float DeltaSeconds);

	UPROPERTY()
	TArray<FVoxelEditCommand> PendingEdits;

	UPROPERTY()
	TArray<FBox> NoEditZones;

	// Per-frame voxel budget. Ported intent from VoxelEditManager.voxels_per_frame
	// (926000 at 10 vox/m). Tuned on-device in Phase 0.
	int64 VoxelsPerFrame = 926000;
};
