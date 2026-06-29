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

		// PARALLEL BAKE SHARDING. To bake a huge resolution fast, run ShardCount processes, each
		// with a distinct ShardIndex; each handles only the tiles whose flat grid index mod
		// ShardCount == ShardIndex and writes a TEXT manifest-shard instead of the .uasset. A final
		// VoxelCrustBaker::MergeShards pass combines the shards into the real Manifest.uasset.
		// ShardCount<=1 = single process bakes everything + writes the manifest (the default).
		int32 ShardIndex = 0;
		int32 ShardCount = 1;

		// Nanite on the baked tiles. true (default) for FINE/near tiers (lots of geometry to LOD).
		// false builds plain static meshes — much faster (Nanite's hierarchy build is the per-tile
		// bottleneck) and fine for COARSE far tiers (few triangles, never need sub-pixel LOD).
		bool bEnableNanite = true;

		// REGION PACKING — dodge the one-file-per-tile "file wall" that makes 10/20cm impractical.
		// When > 0, tiles are grouped into RegionTilesPerSide x RegionTilesPerSide blocks and each
		// block's tile meshes are saved into ONE package (/Game/VoxelBake/<world>/Region_RX_RZ),
		// cutting the FILE count by ~RegionTilesPerSide^2 (e.g. 8 -> 64x fewer files; a 10cm whole
		// map drops from ~270k files to ~4k). Each tile keeps its own mesh + the exact runtime
		// placement (no geometry merge), so the manifest + crust streamer are unchanged — only the
		// mesh's package path differs. Sharding is done BY REGION when this is on, so parallel
		// processes never write the same region package. 0 = one package per tile (original).
		int32 RegionTilesPerSide = 0;

		// GEOMETRY MERGE — the heavier sibling of region packing, for SHIPPING-scale asset counts.
		// Region packing cuts the FILE count but each tile is still its OWN mesh ASSET (a 10cm whole
		// map = ~270k assets — the Asset Registry is keyed per-asset, so the cook still chokes). When
		// this is true (and RegionTilesPerSide > 0), every tile in a region is instead FUSED into ONE
		// merged mesh (mira::merge_region_tiles), so a region becomes a single asset AND a single
		// manifest entry — collapsing both file and asset count by ~RegionTilesPerSide^2. The runtime
		// needs NO change: a merged region is just a bigger "tile", so the manifest's TileSpanVoxels
		// is set to RegionTilesPerSide * TileSpan and the existing crust streamer bands at region
		// granularity automatically. Tradeoff: coarser streaming/culling granularity (a whole region
		// loads or unloads as one), so use it for the FAR/coarse tiers, not the near editable band.
		// false = region packing keeps per-tile meshes (the default; finer streaming).
		bool bGeometryMerge = false;
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

	// Combine the per-process text shards (Saved/BakeShards/<world>_shard*.txt) written by a
	// sharded parallel bake into the final /Game/VoxelBake/<world>/Manifest.uasset, then delete
	// the shards. Run once after all bake processes finish. Returns true on a successful save.
	bool MergeShards(const FString& WorldSaveName);
}

#endif // WITH_EDITOR
