// VoxelScaleSettings.cpp — initialize the editor mirror FROM the Core authority.
#include "VoxelScaleSettings.h"
#include "Core/VoxelScale.h"

UVoxelScaleSettings::UVoxelScaleSettings()
{
	// Pull every value from the compile-time Core authority so the two can
	// never drift. Changing the scale is still a one-place edit (Core/VoxelScale.h).
	VoxelsPerMeter  = mira::scale::VoxelsPerMeter;
	VoxelSizeM      = mira::scale::VoxelSizeM;
	VoxelSizeUnreal = mira::scale::VoxelSizeM * 100.0; // metres -> UE centimetres
}

const UVoxelScaleSettings* UVoxelScaleSettings::Get()
{
	return GetDefault<UVoxelScaleSettings>();
}
