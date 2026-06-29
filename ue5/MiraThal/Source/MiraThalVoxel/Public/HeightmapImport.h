// HeightmapImport.h — decode a heightmap image file (EXR/PNG/HDR) into a Core
// mira::ImageHeightmap's float grid.
//
// WHAT THIS IS (plain English):
// The artist exports a terrain from Gaea as an .exr — a big grid of float
// "height" numbers. The Core ImageHeightmap knows how to SAMPLE that grid, but
// it deliberately can't READ the file (decoding EXR needs an image library).
// This tiny UE-side helper does the decode using Unreal's ImageWrapper module
// and pours the raw floats into the ImageHeightmap. The caller then sets the
// georeferencing (how pixels map to world voxels, how values map to height).
//
// Kept in its own translation unit so both AVoxelWorld (M3 generate) and the
// streaming pager (M4) can load the same map without duplicating decode code.

#pragma once

#include "CoreMinimal.h"

namespace mira { class ImageHeightmap; }

namespace MiraHeightmapImport
{
	// Decode an image file at AbsolutePath into Out (fills width/height/data with
	// the RED channel as the height value; gray EXRs expand so R == the height).
	// Leaves Out's georef + vertical-mapping fields untouched — the caller sets
	// those from the world's size/scale knobs. Returns false and writes a
	// human-readable reason into OutError on any failure (missing file, bad
	// format, empty image). The format is chosen from the file extension; .exr,
	// .hdr, .png and .tiff are supported by the engine's ImageWrapper.
	bool LoadHeightmapImage(const FString& AbsolutePath,
	                        mira::ImageHeightmap& Out,
	                        FString& OutError);
}
