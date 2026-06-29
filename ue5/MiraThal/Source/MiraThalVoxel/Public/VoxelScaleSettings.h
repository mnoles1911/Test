// VoxelScaleSettings.h — editor-exposed mirror of the Core scale authority.
//
// The compile-time authority is mira::scale (Core/VoxelScale.h). This
// UDeveloperSettings surfaces those values in Project Settings so designers can
// SEE them and so Blueprints can read them — but it is INITIALIZED from the Core
// constants, never the other way around. Core stays the single source of truth,
// matching the Godot VoxelScale.gd discipline ("never hardcode the scale").
#pragma once

#include "CoreMinimal.h"
#include "Engine/DeveloperSettings.h"
#include "VoxelScaleSettings.generated.h"

UCLASS(config = Game, defaultconfig, meta = (DisplayName = "Mira-Thal Voxel Scale"))
class MIRATHALVOXEL_API UVoxelScaleSettings : public UDeveloperSettings
{
	GENERATED_BODY()

public:
	UVoxelScaleSettings();

	// How many voxels span one metre of world space (10 = 10cm cubes).
	// Read-only mirror of mira::scale::VoxelsPerMeter.
	UPROPERTY(VisibleAnywhere, config, Category = "Voxel Scale")
	double VoxelsPerMeter = 10.0;

	// Edge length of one voxel in metres (0.1). Mirror of mira::scale::VoxelSizeM.
	UPROPERTY(VisibleAnywhere, config, Category = "Voxel Scale")
	double VoxelSizeM = 0.1;

	// Unreal works in centimetres; this is VoxelSizeM * 100 = the cubic voxel
	// world's voxel size in UE units. Convenience for world setup.
	UPROPERTY(VisibleAnywhere, config, Category = "Voxel Scale")
	double VoxelSizeUnreal = 10.0;

	static const UVoxelScaleSettings* Get();
};
