// TdiffAutoStreamSubsystem.h — auto-start AI terrain streaming when a level begins play.
//
// PLAIN ENGLISH: without this you have to type `MiraThal.Tdiff.Stream 99` in the console every
// time you press Play. This little per-world subsystem does that for you: the moment a GAME world
// (PIE or a packaged build) begins play, it waits a beat for the player to spawn, then kicks off
// streaming with the default seed — which also destroys the legacy baked crust (that removal runs
// inside the stream path). You can still override the world any time with `MiraThal.Tdiff.Stream
// <seed>`, or disable the auto-start with `MiraThal.Tdiff.AutoStream 0`.
//
// A UWorldSubsystem auto-instantiates for each world via reflection (no module registration) and
// its OnWorldBeginPlay only fires for worlds that actually begin play (game/PIE, never the editor
// preview) — so it is naturally scoped to real play sessions.

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "TdiffAutoStreamSubsystem.generated.h"

UCLASS()
class UTdiffAutoStreamSubsystem : public UWorldSubsystem
{
	GENERATED_BODY()

public:
	// Fires once, when this world begins play. Starts AI streaming (after a short delay so the
	// player pawn + voxel world are ready) if MiraThal.Tdiff.AutoStream is enabled and the level
	// contains an AVoxelWorld. No-op otherwise.
	virtual void OnWorldBeginPlay(UWorld& InWorld) override;
};
