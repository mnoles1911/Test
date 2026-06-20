// VoxelCrustBaker.h — the EDITOR-TIME caller that bakes the whole far "crust".
//
// WHAT THIS IS (plain English):
// VoxelNaniteBaker.h knows how to turn ONE meshed slab into ONE Nanite UStaticMesh.
// THIS file is the loop around it: it walks every TILE of the map (default 512-voxel
// squares), samples each tile's surface shell from the SAME generator the live voxels
// use (so the crust lines up at the seam), greedy-meshes it, builds the Nanite mesh,
// and SAVES it as a .uasset under /Game/VoxelBake/<world>/Tile_X_Z. It also writes a
// UVoxelBakeManifest the runtime crust reads.
//
// THREADING: sampling + greedy-meshing each tile is PURE (no UObject, no actor state),
// so we fan that out across worker threads (like MeshSuperPure). UObject creation and
// package save are NOT thread-safe, so the UStaticMesh build + SavePackage happen
// SERIALLY on the game/editor thread, consuming the finished worker payloads.
//
// EDITOR-ONLY: this whole file is compiled only WITH_EDITOR (the bake produces saved
// assets — a build/cook-time step, never a shipping runtime one).

#pragma once

#include "CoreMinimal.h"

#if WITH_EDITOR

#include "Core/NaniteBakeTiling.h"   // mira::nanitebake::DEFAULT_TILE_SPAN_VOXELS / SKIRT

class AVoxelWorld;
class UVoxelBakeManifest;

namespace VoxelCrustBaker
{
	// Designer-tunable bake settings.
	struct FBakeSettings
	{
		// Tile edge in VOXELS. 512 (= 51.2 m) keeps the asset count sane on a 5 km map.
		int32 TileSpanVoxels = mira::nanitebake::DEFAULT_TILE_SPAN_VOXELS;

		// Fine voxels below the surface the shell stays solid (cliff/seam thickness).
		int32 SkirtDepthVoxels = mira::nanitebake::DEFAULT_SKIRT_DEPTH_VOXELS;

		// Fine voxels per coarse cell (downsample). Pick so TileSpan/Stride <= CHUNK(32):
		// 512/16 = 32. Bigger stride = coarser crust = fewer triangles.
		int32 Stride = 16;

		// Half-extent of the bake region, in TILES, around the world origin (0,0). The
		// bake covers tiles [-TileRadius .. +TileRadius] on each axis. The designer sizes
		// this to the playable map. (A focused/region bake can shrink it.)
		int32 TileRadius = 8;

		// SAFETY CAP — max tiles to actually build+save THIS run. 0 = no cap (bake every
		// non-empty tile in the band, the original behaviour). >0 = stop after that many
		// tiles have been SAVED, so a first run can be tiny and observable (e.g. 4 or 9).
		// A capped run writes a manifest covering EXACTLY the tiles it baked, so the
		// runtime never asks for a tile that doesn't exist on disk.
		int32 MaxTilesPerBake = 0;

		// SAFETY RING — bake ONLY tiles whose chunk-distance to the focus (world origin
		// chunk 0,0) is <= this. 0 = use the full [-TileRadius..+TileRadius] square (the
		// original behaviour). >0 = a tiny test ring near the player: only the central
		// tiles within this many chunks are sampled+saved. Combine with MaxTilesPerBake
		// for a guaranteed-small first bake.
		int32 TestBakeRadiusChunks = 0;
	};

	// Bake the whole crust for `World`. Loads the world's generator settings, loops the
	// tile grid, bakes + saves each non-empty tile's Nanite mesh, and writes the manifest.
	//
	// Returns the created manifest (also saved to disk), or nullptr on failure (e.g. PIE
	// is running — asset save during PIE is a known crash, so we REFUSE in that case).
	//
	//   World        — the configured AVoxelWorld (its knobs drive the generator).
	//   WorldSaveName— the save slot / asset folder name (/Game/VoxelBake/<name>/...).
	//   Settings     — tile span / skirt / stride / radius.
	UVoxelBakeManifest* BakeWorldCrust(AVoxelWorld* World,
	                                   const FString& WorldSaveName,
	                                   const FBakeSettings& Settings);
}

#endif // WITH_EDITOR
