// VoxelCrustBakeCommandlet.h — headless cook-time entry for the Nanite crust bake.
//
// The editor BUTTON (AVoxelCrustBakeTool) is for a human; this is the same bake driven
// from the command line with no UI, e.g.:
//
//   UnrealEditor-Cmd MiraThal.uproject -run=VoxelCrustBake -Map=/Game/Maps/MyWorld
//        -WorldSaveName=MyWorld -Tile=512 -Stride=16 -Skirt=128 -Radius=8
//
// It loads the given map, finds the AVoxelWorld in it, and bakes. If no map is given it
// bakes a transient procedural world (CI smoke-bake). The UCLASS must live in a HEADER so
// UnrealHeaderTool emits the matching .generated.h (UHT does not generate one for a UCLASS
// declared only in a .cpp).

#pragma once

#include "CoreMinimal.h"
#include "Commandlets/Commandlet.h"
#include "VoxelCrustBakeCommandlet.generated.h"

UCLASS()
class UVoxelCrustBakeCommandlet : public UCommandlet
{
	GENERATED_BODY()

public:
	virtual int32 Main(const FString& Params) override;
};
