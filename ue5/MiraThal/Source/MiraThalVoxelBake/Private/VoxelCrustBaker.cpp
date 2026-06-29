// VoxelCrustBaker.cpp — the editor-time loop that bakes every tile's Nanite crust.
//
// FLOW (plain English):
//   1. Refuse to run if PIE is active (saving assets during play is a known crash).
//   2. Snapshot the world's generator knobs into a plain FGenParams (the SHARED one,
//      so the crust uses the EXACT same generator as the live near voxels -> seam match).
//   3. For every tile in the bake radius, on WORKER THREADS: sample the surface shell
//      (mira::nanitebake::sample_crust_slab, fed by the generator) and greedy-mesh it
//      (AVoxelChunkActor::BuildMeshBuffers). This is PURE — no UObject, no actor state.
//   4. Back on the GAME/EDITOR THREAD (UObject creation + save are not thread-safe),
//      consume each finished payload: build the Nanite UStaticMesh
//      (VoxelNaniteBaker::BuildNaniteStaticMeshFromMesh) into a fresh package
//      /Game/VoxelBake/<world>/Tile_X_Z, register + save it, and record a manifest entry.
//   5. Save the manifest.

#include "VoxelCrustBaker.h"

#if WITH_EDITOR

#include <exception>                 // std::exception (per-tile fault isolation)

#include "VoxelNaniteBaker.h"        // BuildNaniteStaticMeshFromMesh
#include "VoxelBakeManifest.h"       // UVoxelBakeManifest / FVoxelBakeTileEntry

// MiraThalVoxel (the live engine) — shared generator + the mesher + the world actor.
#include "VoxelWorld.h"
#include "VoxelGenParams.h"          // FGenParams / BuildGen / SnapshotGenParams (SHARED)
#include "VoxelChunkActor.h"         // AVoxelChunkActor::SampleAndMeshCrustTile + FCrustTileMesh

// Core math.
#include "Core/NaniteBakeTiling.h"   // which_tiles / tile_bounds (loop bookkeeping)
#include "Core/MeshTypes.h"          // mira::MeshBuffers
#include "Core/MiraVec.h"            // Vec2i
#include "Core/RegionMerge.h"        // mira::merge_region_tiles (geometry-merge mode)

// Engine / editor.
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInterface.h"
#include "Async/Async.h"
#include "Async/Future.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "Misc/PackageName.h"
#include "AssetRegistry/AssetRegistryModule.h"
#include "Editor.h"                  // GEditor (PlayWorld guard)
#include "HAL/PlatformTime.h"        // FPlatformTime (elapsed-seconds summary)
#include "Math/UnrealMathUtility.h"  // FMath::IsFinite (degenerate-mesh guard)
#include "Misc/FileHelper.h"         // FFileHelper (parallel-bake shard text read/write)
#include "Misc/Paths.h"              // FPaths::ProjectSavedDir
#include "HAL/FileManager.h"         // IFileManager (shard file find/delete on merge)

namespace
{
	// VALIDATE one tile's meshed geometry BEFORE we hand it to the UStaticMesh build.
	// Building a UStaticMesh from a 0-vertex / 0-triangle, out-of-range-index, or
	// NaN/Inf-position FMeshDescription is a classic hard crash inside engine UObject
	// land (the access violation we saw). We catch all three here, on the pure
	// mira::MeshBuffers, so a bad first tile is SKIPPED instead of crashing the editor.
	//
	// Returns true if the buffers are safe to build. On false, *OutReason names why
	// (for the BAKE log line) and *OutVerts/*OutTris carry the counts we did read.
	bool ValidateMeshBuffers(const mira::MeshBuffers& Mb, int32& OutVerts, int32& OutTris,
	                         const TCHAR** OutReason)
	{
		using namespace mira;

		OutVerts = Mb.total_vertices();
		OutTris  = Mb.total_quads() * 2; // 6 indices per quad == 2 triangles
		*OutReason = TEXT("ok");

		if (OutVerts == 0 || OutTris == 0)
		{
			*OutReason = TEXT("empty");
			return false;
		}

		// Per-section: every triangle index must be < that section's vertex count, the
		// index list must be a whole number of triangles, and every position finite.
		for (int s = 0; s < static_cast<int>(FaceClass::Count); ++s)
		{
			const MeshSection& Sec = Mb.sections[s];
			if (Sec.indices.empty())
			{
				continue;
			}

			if (Sec.indices.size() % 3 != 0)
			{
				*OutReason = TEXT("bad-index-count");
				return false;
			}

			const uint32_t VertCount = static_cast<uint32_t>(Sec.vertices.size());
			for (uint32_t Idx : Sec.indices)
			{
				if (Idx >= VertCount)
				{
					*OutReason = TEXT("index-out-of-range");
					return false;
				}
			}

			for (const MeshVertex& V : Sec.vertices)
			{
				if (!FMath::IsFinite(V.px) || !FMath::IsFinite(V.py) || !FMath::IsFinite(V.pz) ||
				    !FMath::IsFinite(V.nx) || !FMath::IsFinite(V.ny) || !FMath::IsFinite(V.nz))
				{
					*OutReason = TEXT("non-finite-position");
					return false;
				}
			}
		}

		return true;
	}

	// Save one finished UStaticMesh into a package on disk. Returns true on success.
	bool SaveBakedMeshPackage(UPackage* Package, UStaticMesh* Mesh, const FString& PackageName)
	{
		FAssetRegistryModule::AssetCreated(Mesh);
		Mesh->MarkPackageDirty();

		FString Filename;
		if (!FPackageName::TryConvertLongPackageNameToFilename(
				PackageName, Filename, FPackageName::GetAssetPackageExtension()))
		{
			UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] bad package path %s"), *PackageName);
			return false;
		}

		FSavePackageArgs SaveArgs;
		SaveArgs.TopLevelFlags = RF_Public | RF_Standalone;
		SaveArgs.SaveFlags = SAVE_NoError;
		const bool bSaved = UPackage::SavePackage(Package, Mesh, *Filename, SaveArgs);
		if (!bSaved)
		{
			UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] SavePackage failed for %s"), *PackageName);
		}
		return bSaved;
	}

	// RE-ENTRANCY GUARD: true while a bake is in progress. A bake can build+save many
	// UStaticMesh assets; letting a second bake start (e.g. a double-clicked button)
	// while one is running would interleave package work and is unsafe. This flag plus
	// the RAII helper below make a second concurrent call refuse cleanly.
	static bool GBakeInProgress = false;

	struct FBakeReentrancyGuard
	{
		bool bOwns = false;
		FBakeReentrancyGuard()
		{
			if (!GBakeInProgress) { GBakeInProgress = true; bOwns = true; }
		}
		~FBakeReentrancyGuard()
		{
			if (bOwns) { GBakeInProgress = false; }
		}
	};
}

namespace VoxelCrustBaker
{

UVoxelBakeManifest* BakeWorldCrust(AVoxelWorld* World,
                                   const FString& WorldSaveName,
                                   const FBakeSettings& Settings)
{
	using namespace mira;

	if (World == nullptr)
	{
		UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] BakeWorldCrust: null world."));
		return nullptr;
	}

	// REFUSE during PIE — saving assets while a play world exists is a known crash.
	if (GEditor && GEditor->PlayWorld != nullptr)
	{
		UE_LOG(LogTemp, Error,
			TEXT("[MiraThalBake] Stop PIE first — baking saves assets, which crashes during play."));
		return nullptr;
	}

	// RE-ENTRANCY: refuse a second bake while one is already running (double-clicked
	// button, etc.). The guard releases the flag automatically when this scope exits.
	FBakeReentrancyGuard ReentrancyGuard;
	if (!ReentrancyGuard.bOwns)
	{
		UE_LOG(LogTemp, Error,
			TEXT("[MiraThalBake] A crust bake is already running — ignoring this request."));
		return nullptr;
	}

	const double BakeStartSeconds = FPlatformTime::Seconds();

	// Make sure the world's heightmap (if any) is loaded before we snapshot the generator.
	World->LoadHeightmapIfNeeded();

	// SHARED snapshot: the crust must use the SAME generator as the live near voxels.
	// GenLod 0 / coarse-gen off (the crust samples at its own stride, like super-chunks).
	const FGenParams P = SnapshotGenParams(*World, /*GenLod=*/0, /*bCoarseFarGen=*/false);

	// GENERATOR FINGERPRINT: boil the generator knobs we just snapshotted down to one
	// stable 64-bit id. We stamp it into the manifest (single-process path) and into each
	// shard's header (sharded path) so the runtime crust can later detect a stale bake.
	const uint64 GenFingerprint = FingerprintGenParams(P);

	const int32 TileSpan = FMath::Max(1, Settings.TileSpanVoxels);
	const int32 Stride   = FMath::Max(1, Settings.Stride);
	const int32 Skirt    = FMath::Max(0, Settings.SkirtDepthVoxels);
	const int32 Radius   = FMath::Max(0, Settings.TileRadius);

	// SAFETY KNOBS (default 0 = "no limit" -> original full-band behaviour):
	//   MaxTiles      — 0 = bake every non-empty tile; >0 = stop after N saved tiles.
	//   TestRingChunks— 0 = full [-Radius..+Radius] square; >0 = only tiles within this
	//                   many CHUNKS of the focus (world origin chunk 0,0). The chunk
	//                   distance uses the SAME math the runtime ring uses
	//                   (mira::nanitebake::tile_chunk_distance), so the test ring matches
	//                   what the streamer would consider "near".
	const int32 MaxTiles       = FMath::Max(0, Settings.MaxTilesPerBake);
	const int32 TestRingChunks = FMath::Max(0, Settings.TestBakeRadiusChunks);
	const Vec2i FocusChunkXZ(0, 0); // the bake square is centred on the world origin

	// PARALLEL SHARDING: a multi-process bake splits the tile grid across N processes — each handles
	// only the tiles whose flat grid index mod ShardCount == ShardIndex (even load balance), writes
	// them to the shared folder, and emits a TEXT manifest-shard. A final -Merge pass combines the
	// shards into the real Manifest.uasset. ShardCount<=1 = one process bakes everything (unchanged).
	const int32 ShardCount = FMath::Max(1, Settings.ShardCount);
	const int32 ShardIndex = FMath::Clamp(Settings.ShardIndex, 0, ShardCount - 1);

	// REGION PACKING: group RegionSize x RegionSize tiles into one shared package (floor-div the tile
	// key to its region key — correct for negatives). 0 = one package per tile (the original).
	const bool  bNanite    = Settings.bEnableNanite; // false = plain static meshes (faster, coarse tiers)
	const int32 RegionSize = FMath::Max(0, Settings.RegionTilesPerSide);
	auto RegionOf = [RegionSize](const Vec2i& t) -> Vec2i {
		const int rs = FMath::Max(1, RegionSize); // guard div-by-zero even if mis-called at RegionSize 0
		return Vec2i(coords::floor_div(t.x, rs), coords::floor_div(t.y, rs));
	};

	// GEOMETRY MERGE: fuse each region's tiles into ONE mesh + ONE manifest entry (shipping-scale
	// asset-count reduction). Only meaningful with region packing on; if asked for without a region
	// size we warn and fall back to the normal per-tile path (safe — changes nothing). A merged
	// region is just a bigger "tile": the manifest's TileSpanVoxels becomes RegionSize * TileSpan so
	// the runtime crust bands at region granularity with no streamer change. (See RegionMerge.h.)
	const bool bGeoMerge = Settings.bGeometryMerge && (RegionSize > 0);
	const int32 RegionSpan = RegionSize * TileSpan; // voxel edge of one region (only used when bGeoMerge)
	if (Settings.bGeometryMerge && RegionSize <= 0)
	{
		UE_LOG(LogTemp, Warning,
			TEXT("[MiraThal] BAKE -GeoMerge ignored: it needs -Region > 0 (got %d). Baking per-tile."),
			RegionSize);
	}

	// BOUNDED-MAP CLIP: the world is a finite MapSpanMeters square centred on the voxel origin; past
	// the coastline is (future) open ocean, not terrain. Asked for a height out there the generator
	// returns a flat base, which would bake spurious flat slabs over the sea (the "floating squares"
	// bug). At 10 voxels/metre the map half-extent is MapSpanMeters/2 * 10 = MapSpanMeters * 5 voxels.
	// We pass it into the sampler so edge-straddling tiles mesh only their in-map part (clean coast),
	// AND skip wholly-outside tiles below so no worker is even spawned for them.
	const int32 MapHalfExtentVox = FMath::Max(0, FMath::RoundToInt(World->MapSpanMeters * 5.0f));

	UMaterialInterface* TerrainMaterial = World->TerrainMaterial;

	// The asset folder for this world: /Game/VoxelBake/<world>/...
	const FString BaseDir = FString::Printf(TEXT("/Game/VoxelBake/%s"), *WorldSaveName);

	// ---- STEP A: fan the PURE sample+mesh work out across worker threads. The actual
	//      generator-backed sampling + greedy-mesh lives in MiraThalVoxel (exported
	//      AVoxelChunkActor::SampleAndMeshCrustTile) so the generator's Core symbols link;
	//      this module just drives the loop + the (serial) UObject build/save. ----
	struct FInFlight { Vec2i Tile; TFuture<FCrustTileMesh> Future; };
	TArray<FInFlight> Jobs;

	// GEOMETRY-MERGE memory fix: tally how many tiles we EXPECT each region to receive in the
	// consume loop, so we can flush a region the instant its last tile is consumed (bounding peak
	// RAM to ~one in-progress region instead of the whole shard). We count EVERY tile that passes
	// the SAME filters as Jobs.Add below (shard / map-bounds / test-ring) — i.e. every tile that
	// actually gets queued — keyed by the tile's region. We can't yet know which of these will turn
	// out empty/failed, so we count them all; the consume loop increments its per-region processed
	// tally on EVERY consumed tile (stashed, skipped, OR failed), so processed reaches expected
	// exactly. (Only built when bGeoMerge; harmless empty map otherwise.)
	TMap<FIntPoint, int32> RegionExpected;

	for (int32 tz = -Radius; tz <= Radius; ++tz)
	for (int32 tx = -Radius; tx <= Radius; ++tx)
	{
		const Vec2i Tile(tx, tz);

		// PARALLEL SHARDING: each process handles only its share. Shard key is the TILE flat index
		// normally, but the REGION flat index when region-packing — so a region's tiles never split
		// across processes (they share one package and two processes must not write the same file).
		// Both indices are >= 0 (offset by the radius), so the modulo partition is stable.
		int32 ShardKey;
		if (RegionSize > 0)
		{
			const Vec2i rk = RegionOf(Tile);
			const int32 rR = Radius / FMath::Max(1, RegionSize) + 1;
			ShardKey = (rk.y + rR) * (2 * rR + 1) + (rk.x + rR);
		}
		else
		{
			ShardKey = (tz + Radius) * (2 * Radius + 1) + (tx + Radius);
		}
		if (ShardCount > 1 && (ShardKey % ShardCount) != ShardIndex) { continue; }

		// MAP-BOUNDS SKIP: don't queue a tile whose ENTIRE voxel footprint is outside the map
		// square — it would sample as all-air (the sampler clips out-of-map columns) and be skipped
		// anyway, so dropping it here saves spawning a worker. Edge-straddling tiles are KEPT (the
		// sampler meshes only their in-map part).
		if (MapHalfExtentVox > 0)
		{
			const nanitebake::TileBounds tb = nanitebake::tile_bounds(Tile, TileSpan);
			if (tb.maxX < -MapHalfExtentVox || tb.minX > MapHalfExtentVox ||
			    tb.maxZ < -MapHalfExtentVox || tb.minZ > MapHalfExtentVox)
			{
				continue;
			}
		}

		// TEST RING: when TestRingChunks > 0, skip tiles whose chunk-distance to the focus
		// exceeds it (a tiny ring near the player). At the default 0 this filter is OFF and
		// every tile in the square is queued, exactly as before.
		if (TestRingChunks > 0)
		{
			const int32 ChunkDist =
				nanitebake::tile_chunk_distance(FocusChunkXZ, Tile, TileSpan);
			if (ChunkDist > TestRingChunks)
			{
				continue;
			}
		}

		// This tile has cleared every queue filter, so the consume loop WILL see it. Count it
		// toward its region's expected total (geo-merge only — drives the incremental flush).
		if (bGeoMerge)
		{
			const Vec2i rk = RegionOf(Tile);
			RegionExpected.FindOrAdd(FIntPoint(rk.x, rk.y)) += 1;
		}

		FInFlight Job;
		Job.Tile = Tile;
		Job.Future = Async(EAsyncExecution::ThreadPool,
			[Tile, P, TileSpan, Stride, Skirt, MapHalfExtentVox]()
			{
				return AVoxelChunkActor::SampleAndMeshCrustTile(
					P, Tile.x, Tile.y, TileSpan, Stride, Skirt, MapHalfExtentVox);
			});
		Jobs.Add(MoveTemp(Job));
	}

	// ---- STEP B: SERIALLY consume payloads on the game/editor thread (UObject build +
	//      package save are not thread-safe). Build the Nanite mesh, save it, record it. ----
	// RF_Public | RF_Standalone so SavePackage actually persists the manifest. Without these
	// flags the save is skipped ("does not have any of the provided object flags ... would cause
	// data loss") and the runtime streamer then has no manifest to load the baked tiles from.
	//
	// RE-BAKE SAFE: build the manifest DIRECTLY in its target package, reusing the existing
	// manifest object if a prior bake already left one. The old code built the manifest in the
	// transient package and Rename()'d it onto the target at the end — but CreatePackage +
	// FullyLoad loads any PRIOR on-disk manifest into memory, and Rename()ing a fresh object on
	// top of a live existing one is a HARD FATAL (Obj.cpp "Renaming ... on top of an existing
	// object is not allowed"). That crash bit on the SECOND bake of a world — the first bake had
	// no prior manifest, so it was never seen. Find-or-create in place (exactly how the per-tile
	// UStaticMesh path already overwrites loaded tiles) and clear stale entries so the saved
	// manifest reflects ONLY this bake.
	const FString ManifestPkgName = FString::Printf(TEXT("%s/Manifest"), *BaseDir);
	UPackage* ManifestPkg = CreatePackage(*ManifestPkgName);
	ManifestPkg->FullyLoad(); // pulls a prior manifest (if any) into memory so we reuse it below
	UVoxelBakeManifest* Manifest = FindObject<UVoxelBakeManifest>(ManifestPkg, TEXT("Manifest"));
	if (Manifest == nullptr)
	{
		Manifest = NewObject<UVoxelBakeManifest>(
			ManifestPkg, FName(TEXT("Manifest")), RF_Public | RF_Standalone);
	}
	Manifest->Tiles.Reset();          // drop any prior bake's entries — refilled by the loop below
	Manifest->WorldSaveName  = WorldSaveName;
	// Stamp the generator fingerprint so the runtime can detect a stale crust (single-process
	// save uses this directly; the sharded path re-stamps it in MergeShards from the shard header).
	Manifest->GenFingerprint = GenFingerprint;
	// In geo-merge mode each manifest entry is a whole REGION, so the runtime must band at region
	// granularity — set the span to one region's voxel edge. (Per-tile bakes keep the tile span.)
	Manifest->TileSpanVoxels = bGeoMerge ? RegionSpan : TileSpan;

	// REGION PACKING state: get-or-create the shared package for a tile's region. This first pass
	// holds all the run's region packages resident and saves them after the loop — fine for the
	// few-thousand regions region-packing targets (one shard only touches its own regions). Revisit
	// with per-region completion-save if a single huge bake ever runs out of memory.
	TMap<FString, UPackage*> RegionPackages;
	TMap<FString, UStaticMesh*> RegionRepMesh; // one mesh per region pkg, passed as the SavePackage asset

	// GEOMETRY-MERGE state: stash each region's finished tile payloads here (moved in, not copied)
	// and fuse them into ONE mesh after the tile loop. Memory parity with region packing — that path
	// already holds all of a shard's built meshes resident until its end-of-loop save; here we hold
	// the (smaller) raw meshes and free each region right after it's fused. RegionBaseFineY tracks
	// the LOWEST tile anchor in the region so merge offsets stay >= 0 (see RegionMerge.h).
	struct FGeoRegion
	{
		Vec2i RegionKey = Vec2i(0, 0);
		int32 Stride = 1;
		int32 RegionBaseFineY = 0;
		bool  bHasBase = false;
		TArray<FCrustTileMesh> Payloads; // moved-in tile meshes, fused at flush
	};
	TMap<FIntPoint, FGeoRegion> GeoRegions;

	auto GetRegionPackage = [&](const Vec2i& tile) -> UPackage*
	{
		const Vec2i rk = RegionOf(tile);
		const FString PkgName = FString::Printf(TEXT("%s/Region_%d_%d"), *BaseDir, rk.x, rk.y);
		if (UPackage** F = RegionPackages.Find(PkgName)) { return *F; }
		UPackage* P = CreatePackage(*PkgName);
		if (P) { P->FullyLoad(); RegionPackages.Add(PkgName, P); }
		return P;
	};

	// How many tiles we'll actually process this run (the cap, if any, applies to SAVED
	// tiles; this is just the queued count for the progress denominator).
	const int32 NumQueued = Jobs.Num();
	UE_LOG(LogTemp, Display,
		TEXT("[MiraThal] BAKE START n_tiles=%d band=square[-%d..%d] test_ring_chunks=%d max_tiles=%s world='%s' (span=%d stride=%d skirt=%d)"),
		NumQueued, Radius, Radius, TestRingChunks,
		(MaxTiles > 0 ? *FString::Printf(TEXT("%d"), MaxTiles) : TEXT("none")),
		*WorldSaveName, TileSpan, Stride, Skirt);

	int32 SavedTiles   = 0; // tiles built + saved + recorded in the manifest
	int32 FailedTiles  = 0; // tiles that errored (bad package/mesh/save/exception)
	int32 SkippedTiles = 0; // tiles with no content (all air / empty mesh) — expected, not a fault
	int32 TileIndex    = 0; // 1-based position in the queue, for the progress line

	// GEOMETRY-MERGE incremental flush bookkeeping (geo-merge only):
	//   RegionProcessed — how many of a region's expected tiles the consume loop has handled so far
	//                     (incremented on EVERY consumed tile of the region: stashed, skipped, OR
	//                     failed). When it reaches RegionExpected[region] the region is COMPLETE and
	//                     we flush it immediately, freeing its raw meshes before moving on.
	//   RegionsFlushed  — set of regions already flushed, so the end-of-loop safety-net pass never
	//                     double-flushes one (and the per-tile path is never touched).
	TMap<FIntPoint, int32> RegionProcessed;
	TSet<FIntPoint>        RegionsFlushed;
	int32 RegionsSavedCount = 0; // merged regions written (for the geo-merge summary line)

	// FLUSH ONE REGION — the existing fuse + validate + build + save + manifest-entry + free logic,
	// factored out so it can run INCREMENTALLY (the moment a region's last tile is consumed) AND as
	// an end-of-loop safety net for any region that somehow didn't reach its expected count. Byte-
	// identical to the old end-of-loop flush pass: same merge inputs, same anchor math, same manifest
	// fields (incl. TileSpanVoxels == RegionSpan via the per-entry RegionSpan bounds), same skip/fail
	// accounting, same "count merged region as saved", same free-after-fuse. A region with no stashed
	// payloads (all its tiles were empty/failed) is a clean no-op — exactly as today, where such a
	// region never appears in GeoRegions and so was never flushed.
	auto FlushGeoRegion = [&](const FIntPoint& RegionKeyPt)
	{
		if (RegionsFlushed.Contains(RegionKeyPt)) { return; } // already done — never double-flush
		RegionsFlushed.Add(RegionKeyPt);

		FGeoRegion* RPtr = GeoRegions.Find(RegionKeyPt);
		if (RPtr == nullptr || RPtr->Payloads.Num() == 0)
		{
			// No valid geometry stashed for this region (every tile was empty/bad/failed). Nothing
			// to fuse or save — matches the old behaviour where the region simply wasn't in GeoRegions.
			return;
		}
		FGeoRegion& R = *RPtr;
		const Vec2i rk = R.RegionKey;
		const int32 RStride = FMath::Max(1, R.Stride);

		// Region anchor = the NOMINAL min corner (rk * RegionSpan). Using the nominal corner (not
		// the clipped mesh min) means MaxVoxelX-MinVoxelX+1 == RegionSpan exactly, so MergeShards
		// recovers the right TileSpanVoxels for the runtime band. The merged verts are expressed
		// relative to THIS anchor, and the runtime places the mesh at THIS anchor — they cancel.
		const int32 RegionMinX = rk.x * RegionSpan;
		const int32 RegionMinZ = rk.y * RegionSpan;
		const int32 RegionBaseY = R.RegionBaseFineY;

		// Build the pure merge inputs. Pointers into R.Payloads are stable now (array fully
		// populated — no more Add()s), so &Pm.Mb is safe to hand to merge_region_tiles.
		std::vector<mira::RegionTileInput> Inputs;
		Inputs.reserve(R.Payloads.Num());
		for (const FCrustTileMesh& Pm : R.Payloads)
		{
			mira::RegionTileInput In;
			In.mesh      = &Pm.Mb;
			In.minVoxelX = Pm.MinVoxelX;
			In.minVoxelZ = Pm.MinVoxelZ;
			In.baseFineY = Pm.BaseFineY;
			Inputs.push_back(In);
		}
		mira::MeshBuffers Merged =
			mira::merge_region_tiles(Inputs, RegionMinX, RegionMinZ, RegionBaseY, RStride);

		// Validate the fused mesh just like a per-tile one (a bad merge shouldn't crash the build).
		const TCHAR* MR = TEXT("ok");
		int32 MV = 0, MT = 0;
		if (!ValidateMeshBuffers(Merged, MV, MT, &MR) || MV == 0 || MT == 0)
		{
			UE_LOG(LogTemp, Warning,
				TEXT("[MiraThal] BAKE geo-merge region (%d,%d) -> SKIPPED (merged verts=%d tris=%d reason=%s)"),
				rk.x, rk.y, MV, MT, MR);
			R.Payloads.Empty();
			return;
		}

		const FString PkgName = FString::Printf(TEXT("%s/Region_%d_%d"), *BaseDir, rk.x, rk.y);
		UPackage* Package = CreatePackage(*PkgName);
		if (Package == nullptr)
		{
			UE_LOG(LogTemp, Error, TEXT("[MiraThal] BAKE geo-merge region (%d,%d) -> FAILED (CreatePackage %s)"),
				rk.x, rk.y, *PkgName);
			++FailedTiles; R.Payloads.Empty(); return;
		}
		Package->FullyLoad();
		const FString MeshName = FString::Printf(TEXT("Region_%d_%d"), rk.x, rk.y);
		UStaticMesh* Mesh = VoxelNaniteBaker::BuildNaniteStaticMeshFromMesh(
			Merged, TerrainMaterial, Package, FName(*MeshName), bNanite);
		if (Mesh == nullptr || !SaveBakedMeshPackage(Package, Mesh, PkgName))
		{
			UE_LOG(LogTemp, Error, TEXT("[MiraThal] BAKE geo-merge region (%d,%d) -> FAILED (build/save %s)"),
				rk.x, rk.y, *PkgName);
			++FailedTiles; R.Payloads.Empty(); return;
		}

		FVoxelBakeTileEntry Entry;
		Entry.TileX = rk.x;
		Entry.TileZ = rk.y;
		Entry.MinVoxelX = RegionMinX;
		Entry.MinVoxelZ = RegionMinZ;
		Entry.MaxVoxelX = RegionMinX + RegionSpan - 1;
		Entry.MaxVoxelZ = RegionMinZ + RegionSpan - 1;
		Entry.BaseFineY = RegionBaseY;
		Entry.Stride    = RStride;
		Entry.Mesh      = TSoftObjectPtr<UStaticMesh>(Mesh);
		Manifest->Tiles.Add(Entry);
		++RegionsSavedCount;
		++SavedTiles;             // count merged regions as "saved" for the summary
		const int32 FusedFrom = static_cast<int32>(Inputs.size());
		R.Payloads.Empty();       // free this region's raw meshes now — bound memory
		UE_LOG(LogTemp, Display,
			TEXT("[MiraThal] BAKE geo-merge region (%d,%d) -> saved %s (verts=%d tris=%d from %d tiles)"),
			rk.x, rk.y, *PkgName, MV, MT, FusedFrom);
	};

	// Increment a region's processed tally for ONE consumed tile (any outcome) and flush the region
	// the instant it's complete. Called from every terminal outcome of the consume loop in geo-merge
	// mode (stash / skip-empty / skip-bad / fail / exception) so a region with some empty tiles still
	// reaches its expected count and flushes. No-op when not geo-merging.
	auto NoteGeoTileProcessed = [&](const Vec2i& Tile)
	{
		if (!bGeoMerge) { return; }
		const Vec2i rk = RegionOf(Tile);
		const FIntPoint Key(rk.x, rk.y);
		const int32 Done = (RegionProcessed.FindOrAdd(Key) += 1);
		const int32 Want = RegionExpected.FindRef(Key); // 0 if somehow unqueued — guarded below
		if (Want > 0 && Done >= Want)
		{
			FlushGeoRegion(Key); // region complete — fuse + save + free NOW, bounding peak RAM
		}
	};

	for (FInFlight& Job : Jobs)
	{
		++TileIndex;

		// CAP: once we've saved MaxTiles tiles, stop building/saving more this run. We
		// still drain the remaining futures (below) so worker threads aren't orphaned,
		// but we don't add them to the manifest -> the manifest covers EXACTLY the tiles
		// that exist on disk. (MaxTiles == 0 means no cap.)
		if (MaxTiles > 0 && SavedTiles >= MaxTiles)
		{
			Job.Future.Get(); // join the worker; discard the payload
			continue;
		}

		const FString AssetName = FString::Printf(TEXT("Tile_%d_%d"), Job.Tile.x, Job.Tile.y);

		// FAULT ISOLATION: wrap this one tile so a single bad tile logs + is skipped
		// instead of aborting the whole bake. We count three distinct outcomes:
		//   - SKIPPED: empty/all-air mesh (0 tris) — expected, not an error.
		//   - FAILED : package create/save failure, null mesh, or a thrown exception.
		//   - SAVED  : built + saved + recorded.
		bool bThisTileSaved = false;
		int32 ThisVerts = 0;
		int32 ThisTris  = 0;
		FString SavedPath;

#if PLATFORM_EXCEPTIONS_DISABLED
		// Exceptions are off in this build config: run the body directly. The explicit
		// null/failure checks below still isolate the common faults (the only thing we
		// lose is catching a hard throw, which this config asserts shouldn't happen).
		{
#else
		try
		{
#endif
			// GRANULAR STEP LOGGING. We emit one UE_LOG line IMMEDIATELY BEFORE each
			// substep of this tile. UE_LOG is auto-flushed, so if the NEXT run hard-crashes
			// (access violation -> RequestExit, which our try/catch can't catch), the LAST
			// line in MiraThal.log names the EXACT substep + this tile's vert/tri counts.
			// Read that last "BAKE tile ... step=..." line to see where it died.
			UE_LOG(LogTemp, Display,
				TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=sample"),
				TileIndex, NumQueued, Job.Tile.x, Job.Tile.y);

			FCrustTileMesh Payload = Job.Future.Get(); // blocks until this tile is meshed
			                                           // (non-const: geo-merge MOVES it into its region)

			ThisVerts = Payload.Mb.total_vertices();
			ThisTris  = Payload.Mb.total_quads() * 2;

			UE_LOG(LogTemp, Display,
				TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=meshed verts=%d tris=%d has_content=%d"),
				TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, ThisVerts, ThisTris, Payload.bHasContent ? 1 : 0);

			// GUARD 1 (empty/degenerate) — run on the PURE buffers BEFORE any UObject build.
			// Building a UStaticMesh from a 0-vert/0-tri, out-of-range-index, or NaN/Inf
			// description is the classic crash. ValidateMeshBuffers catches all three.
			const TCHAR* ValidateReason = TEXT("ok");
			int32 ValVerts = 0, ValTris = 0;
			const bool bMeshOk = ValidateMeshBuffers(Payload.Mb, ValVerts, ValTris, &ValidateReason);

			if (!Payload.bHasContent || ValVerts == 0 || ValTris == 0)
			{
				// Tile entirely above terrain (all air) or an empty mesh — nothing to bake.
				UE_LOG(LogTemp, Display,
					TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=skip-empty (verts=%d tris=%d) -> SKIPPED"),
					TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, ThisVerts, ThisTris);
				++SkippedTiles;
			}
			else if (!bMeshOk)
			{
				// Bad geometry (index out of range / non-finite position / odd index count).
				// Skipping protects the build from a guaranteed crash on this tile.
				UE_LOG(LogTemp, Warning,
					TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=skip-bad reason=%s (verts=%d tris=%d) -> SKIPPED"),
					TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, ValidateReason, ThisVerts, ThisTris);
				++SkippedTiles;
			}
			else if (bGeoMerge)
			{
				// GEOMETRY MERGE: don't build a per-tile mesh. Stash this valid tile's payload under
				// its region; the whole region is fused into ONE mesh after the loop (region-flush
				// pass below). We MOVE the payload (its vertex/index buffers) into the region store so
				// nothing is copied. Track the region's lowest tile anchor for the merge offset.
				const Vec2i rk = RegionOf(Job.Tile);
				FGeoRegion& R = GeoRegions.FindOrAdd(FIntPoint(rk.x, rk.y));
				R.RegionKey = rk;
				R.Stride    = Payload.Stride;
				R.RegionBaseFineY = R.bHasBase ? FMath::Min(R.RegionBaseFineY, Payload.BaseFineY)
				                               : Payload.BaseFineY;
				R.bHasBase  = true;
				UE_LOG(LogTemp, Display,
					TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=stash region=(%d,%d) verts=%d tris=%d"),
					TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, rk.x, rk.y, ThisVerts, ThisTris);
				R.Payloads.Add(MoveTemp(Payload)); // payload consumed — not referenced again this tile
			}
			else
			{
				// Package: one per tile (Tile_X_Z), OR a shared region package (Region_RX_RZ) when
				// region-packing. The mesh keeps its own name + the EXACT runtime placement either
				// way; only its package path changes. Region packages defer their disk save to the
				// end of the loop (many tiles share one) — that's the file-count win.
				const bool bRegion = (RegionSize > 0);
				const FString PackageName = bRegion
					? FString::Printf(TEXT("%s/Region_%d_%d"), *BaseDir, RegionOf(Job.Tile).x, RegionOf(Job.Tile).y)
					: FString::Printf(TEXT("%s/%s"), *BaseDir, *AssetName);

				UE_LOG(LogTemp, Display,
					TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=package pkg=%s"),
					TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *PackageName);

				UPackage* Package = bRegion ? GetRegionPackage(Job.Tile) : CreatePackage(*PackageName);
				if (Package == nullptr)
				{
					UE_LOG(LogTemp, Error,
						TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) -> FAILED (CreatePackage %s)"),
						TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *PackageName);
					++FailedTiles;
				}
				else
				{
					if (!bRegion) { Package->FullyLoad(); } // region packages are FullyLoaded in GetRegionPackage

					UE_LOG(LogTemp, Display,
						TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=build verts=%d tris=%d"),
						TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, ThisVerts, ThisTris);

					UStaticMesh* Mesh = VoxelNaniteBaker::BuildNaniteStaticMeshFromMesh(
						Payload.Mb, TerrainMaterial, Package, FName(*AssetName), bNanite);
					if (Mesh == nullptr)
					{
						UE_LOG(LogTemp, Error,
							TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) -> FAILED (null UStaticMesh)"),
							TileIndex, NumQueued, Job.Tile.x, Job.Tile.y);
						++FailedTiles;
					}
					else
					{
						UE_LOG(LogTemp, Display,
							TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=built mesh=%s step=%s pkg=%s"),
							TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *Mesh->GetName(),
							bRegion ? TEXT("pack") : TEXT("save"), *PackageName);

						// Per-tile packages save NOW; region packages register the mesh + defer the
						// package's disk save to the end-of-loop region pass.
						bool bSavedOk;
						if (bRegion)
						{
							FAssetRegistryModule::AssetCreated(Mesh);
							Mesh->MarkPackageDirty();
							RegionRepMesh.Add(PackageName, Mesh); // representative asset for the package save
							bSavedOk = true;
						}
						else
						{
							bSavedOk = SaveBakedMeshPackage(Package, Mesh, PackageName);
						}

						if (!bSavedOk)
						{
							UE_LOG(LogTemp, Error,
								TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) -> FAILED (SavePackage %s)"),
								TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *PackageName);
							++FailedTiles;
						}
						else
						{
							UE_LOG(LogTemp, Display,
								TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=%s"),
								TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, bRegion ? TEXT("packed") : TEXT("saved"));

							FVoxelBakeTileEntry Entry;
							Entry.TileX = Job.Tile.x;
							Entry.TileZ = Job.Tile.y;
							Entry.MinVoxelX = Payload.MinVoxelX;
							Entry.MinVoxelZ = Payload.MinVoxelZ;
							Entry.MaxVoxelX = Payload.MaxVoxelX;
							Entry.MaxVoxelZ = Payload.MaxVoxelZ;
							Entry.BaseFineY = Payload.BaseFineY;
							Entry.Stride    = Payload.Stride;
							Entry.Mesh      = TSoftObjectPtr<UStaticMesh>(Mesh);
							Manifest->Tiles.Add(Entry);
							++SavedTiles;
							bThisTileSaved = true;
							SavedPath = PackageName;
						}
					}
				}
			}
#if PLATFORM_EXCEPTIONS_DISABLED
		}
#else
		}
		catch (const std::exception& Ex)
		{
			UE_LOG(LogTemp, Error,
				TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) -> FAILED (exception: %hs)"),
				TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, Ex.what());
			++FailedTiles;
		}
		catch (...)
		{
			UE_LOG(LogTemp, Error,
				TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) -> FAILED (unknown exception)"),
				TileIndex, NumQueued, Job.Tile.x, Job.Tile.y);
			++FailedTiles;
		}
#endif

		// Per-tile SAVED progress line (skipped/failed lines are logged inline above).
		if (bThisTileSaved)
		{
			UE_LOG(LogTemp, Display,
				TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) -> saved %s (verts=%d, tris=%d)"),
				TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *SavedPath, ThisVerts, ThisTris);
		}

		// GEOMETRY-MERGE incremental flush: this tile has now been fully CONSUMED, whatever its
		// outcome above (stashed / skipped-empty / skipped-bad / failed via exception). Bump its
		// region's processed tally; when the region's last expected tile is in, flush it RIGHT NOW
		// so we never hold more than one in-progress region's raw meshes resident. Reaching here is
		// guaranteed for every non-cap tile — the cap branch `continue`s above, before this point,
		// and no branch inside the try/catch uses `continue`. No-op when not geo-merging.
		NoteGeoTileProcessed(Job.Tile);
	}

	// GEOMETRY MERGE: the regions are fused + saved INCREMENTALLY inside the consume loop now
	// (FlushGeoRegion, fired by NoteGeoTileProcessed the instant a region's last tile is consumed),
	// so peak RAM is bounded to ~one in-progress region instead of the whole shard. This end-of-loop
	// pass is just a SAFETY NET: it flushes any region that — for any reason — never reached its
	// expected count and so wasn't flushed in the loop. In the normal case every region is already
	// in RegionsFlushed and this loop does nothing. Output is byte-identical to the old single
	// end-of-loop pass: same merged meshes, same manifest entries, same skip/fail accounting (the
	// fuse/validate/build/save/free logic lives in FlushGeoRegion and is shared by both call sites).
	if (bGeoMerge)
	{
		for (const TPair<FIntPoint, FGeoRegion>& RP : GeoRegions)
		{
			FlushGeoRegion(RP.Key); // no-op if already flushed (RegionsFlushed guards re-entry)
		}
		UE_LOG(LogTemp, Display,
			TEXT("[MiraThal] BAKE geo-merge: saved %d region meshes (RegionSize=%d span=%d) -> %d manifest entries"),
			RegionsSavedCount, RegionSize, RegionSpan, Manifest->Tiles.Num());
	}
	// REGION PACKING: save every region package built this run (the per-tile saves were deferred).
	// One SavePackage per region — each holds many tile meshes — which is the file-count win. The
	// nullptr asset arg saves the WHOLE package (all its standalone tile meshes).
	else if (RegionSize > 0)
	{
		int32 RegionsSaved = 0;
		for (const TPair<FString, UPackage*>& RP : RegionPackages)
		{
			FString RegionFilename;
			if (RP.Value && FPackageName::TryConvertLongPackageNameToFilename(
					RP.Key, RegionFilename, FPackageName::GetAssetPackageExtension()))
			{
				FSavePackageArgs RArgs;
				RArgs.TopLevelFlags = RF_Public | RF_Standalone;
				RArgs.SaveFlags = SAVE_NoError;
				UObject* RepAsset = RegionRepMesh.FindRef(RP.Key); // a mesh in the pkg (SavePackage saves all)
				// Skip a region whose tiles ALL failed to build (no mesh) — don't write an empty .uasset.
				if (RepAsset && UPackage::SavePackage(RP.Value, RepAsset, *RegionFilename, RArgs)) { ++RegionsSaved; }
			}
		}
		UE_LOG(LogTemp, Display,
			TEXT("[MiraThal] BAKE region-pack: saved %d region packages holding %d tiles (RegionSize=%d)"),
			RegionsSaved, Manifest->Tiles.Num(), RegionSize);
	}

	// ---- STEP C: persist the index. SHARDED bake (ShardCount>1): write THIS process's tile entries
	//      to a small text shard (N processes can't race on one .uasset); a later -Merge pass builds
	//      the real manifest. Single process (ShardCount<=1): save the Manifest.uasset directly. ----
	if (ShardCount > 1)
	{
		FString ShardText;
		// HEADER LINE: carry the generator fingerprint through the sharded path. MergeShards has
		// no world to recompute it from, so we write it here (as a "# fp <value>" comment line that
		// the tile parser ignores) and read it back during the merge. Every shard of one bake run
		// snapshots the SAME world, so they all carry the same fingerprint — MergeShards just takes
		// the first one it sees.
		ShardText += FString::Printf(TEXT("# fp %llu\n"), GenFingerprint);
		for (const FVoxelBakeTileEntry& E : Manifest->Tiles)
		{
			// 8 ints + the mesh's soft path (so merge is region-pack safe — the mesh may live in a
			// shared Region_RX_RZ package, not a per-tile Tile_X_Z one). Path has no spaces.
			ShardText += FString::Printf(TEXT("%d %d %d %d %d %d %d %d %s\n"),
				E.TileX, E.TileZ, E.MinVoxelX, E.MinVoxelZ, E.MaxVoxelX, E.MaxVoxelZ, E.BaseFineY, E.Stride,
				*E.Mesh.ToSoftObjectPath().ToString());
		}
		const FString ShardPath = FPaths::ProjectSavedDir() /
			FString::Printf(TEXT("BakeShards/%s_shard%d.txt"), *WorldSaveName, ShardIndex);
		FFileHelper::SaveStringToFile(ShardText, *ShardPath);
		UE_LOG(LogTemp, Display, TEXT("[MiraThal] BAKE SHARD %d/%d wrote %d entries -> %s"),
			ShardIndex, ShardCount, Manifest->Tiles.Num(), *ShardPath);
	}
	else
	{
		// The manifest object + package were created up front (re-bake safe, STEP B); register + save.
		FAssetRegistryModule::AssetCreated(Manifest);
		Manifest->MarkPackageDirty();
		FString ManifestFilename;
		if (FPackageName::TryConvertLongPackageNameToFilename(
				ManifestPkgName, ManifestFilename, FPackageName::GetAssetPackageExtension()))
		{
			FSavePackageArgs SaveArgs;
			SaveArgs.TopLevelFlags = RF_Public | RF_Standalone;
			SaveArgs.SaveFlags = SAVE_NoError;
			UPackage::SavePackage(ManifestPkg, Manifest, *ManifestFilename, SaveArgs);
		}
	}

	const double ElapsedSeconds = FPlatformTime::Seconds() - BakeStartSeconds;
	UE_LOG(LogTemp, Display,
		TEXT("[MiraThal] BAKE DONE saved=%d failed=%d skipped=%d (queued=%d) elapsed=%.1fs world='%s' manifest_tiles=%d"),
		SavedTiles, FailedTiles, SkippedTiles, NumQueued, ElapsedSeconds,
		*WorldSaveName, Manifest->Tiles.Num());

	return Manifest;
}

// ---------------------------------------------------------------------------
// MERGE the per-process text shards (BakeShards/<world>_shard*.txt) into the final
// Manifest.uasset. Run once, after all parallel bake processes finish. Pure asset work
// (no map/generator needed) — reconstructs each tile's soft mesh pointer from its key.
// ---------------------------------------------------------------------------
bool MergeShards(const FString& WorldSaveName)
{
	const FString BaseDir   = FString::Printf(TEXT("/Game/VoxelBake/%s"), *WorldSaveName);
	const FString ShardDir  = FPaths::ProjectSavedDir() / TEXT("BakeShards");
	const FString Wildcard  = ShardDir / FString::Printf(TEXT("%s_shard*.txt"), *WorldSaveName);

	TArray<FString> ShardFiles;
	IFileManager::Get().FindFiles(ShardFiles, *Wildcard, /*Files=*/true, /*Directories=*/false);
	if (ShardFiles.Num() == 0)
	{
		UE_LOG(LogTemp, Error, TEXT("[MiraThalBake] MergeShards: no shard files for '%s' in %s"),
			*WorldSaveName, *ShardDir);
		return false;
	}

	// Find-or-create the manifest in its target package (re-bake safe, same as the bake path).
	const FString ManifestPkgName = FString::Printf(TEXT("%s/Manifest"), *BaseDir);
	UPackage* ManifestPkg = CreatePackage(*ManifestPkgName);
	ManifestPkg->FullyLoad();
	UVoxelBakeManifest* Manifest = FindObject<UVoxelBakeManifest>(ManifestPkg, TEXT("Manifest"));
	if (Manifest == nullptr)
	{
		Manifest = NewObject<UVoxelBakeManifest>(ManifestPkg, FName(TEXT("Manifest")), RF_Public | RF_Standalone);
	}
	Manifest->Tiles.Reset();
	Manifest->WorldSaveName = WorldSaveName;

	// GENERATOR FINGERPRINT: recovered from the shard header line ("# fp <value>") that the bake
	// wrote. All shards of one run carry the same value (same world), so we take the first non-zero
	// one we find. Stays 0 if no shard had a header (a legacy shard from before this field) — which
	// the runtime treats as "unknown" and only warns about, never refuses.
	uint64 MergedFingerprint = 0;

	for (const FString& ShardName : ShardFiles)
	{
		FString Text;
		if (!FFileHelper::LoadFileToString(Text, *(ShardDir / ShardName))) { continue; }
		TArray<FString> Lines;
		Text.ParseIntoArrayLines(Lines);
		for (const FString& Line : Lines)
		{
			// Header/comment line: "# fp <value>" carries the generator fingerprint. Parse it (once)
			// and skip — it is not a tile entry.
			if (Line.StartsWith(TEXT("#")))
			{
				TArray<FString> HdrTok;
				Line.ParseIntoArray(HdrTok, TEXT(" "), /*CullEmpty=*/true);
				if (HdrTok.Num() >= 3 && HdrTok[1] == TEXT("fp") && MergedFingerprint == 0)
				{
					MergedFingerprint = FCString::Strtoui64(*HdrTok[2], nullptr, 10);
				}
				continue;
			}
			TArray<FString> Tok;
			Line.ParseIntoArray(Tok, TEXT(" "), /*CullEmpty=*/true);
			if (Tok.Num() < 8) { continue; }
			FVoxelBakeTileEntry E;
			E.TileX     = FCString::Atoi(*Tok[0]); E.TileZ     = FCString::Atoi(*Tok[1]);
			E.MinVoxelX = FCString::Atoi(*Tok[2]); E.MinVoxelZ = FCString::Atoi(*Tok[3]);
			E.MaxVoxelX = FCString::Atoi(*Tok[4]); E.MaxVoxelZ = FCString::Atoi(*Tok[5]);
			E.BaseFineY = FCString::Atoi(*Tok[6]); E.Stride    = FCString::Atoi(*Tok[7]);
			// Mesh path: use the explicit path the shard stored (region-pack safe — may be a shared
			// Region_RX_RZ package); fall back to the per-tile Tile_X_Z path for old 8-field shards.
			const FString MeshPath = (Tok.Num() >= 9)
				? Tok[8]
				: FString::Printf(TEXT("%s/Tile_%d_%d.Tile_%d_%d"), *BaseDir, E.TileX, E.TileZ, E.TileX, E.TileZ);
			E.Mesh = TSoftObjectPtr<UStaticMesh>(FSoftObjectPath(MeshPath));
			Manifest->Tiles.Add(E);
		}
	}

	// TileSpanVoxels: every tile shares it; recover from any tile's bounds (max-min+1).
	if (Manifest->Tiles.Num() > 0)
	{
		const FVoxelBakeTileEntry& E0 = Manifest->Tiles[0];
		Manifest->TileSpanVoxels = E0.MaxVoxelX - E0.MinVoxelX + 1;
	}

	// Stamp the generator fingerprint recovered from the shard headers (0 if legacy shards).
	Manifest->GenFingerprint = MergedFingerprint;

	FAssetRegistryModule::AssetCreated(Manifest);
	Manifest->MarkPackageDirty();
	bool bSaved = false;
	FString ManifestFilename;
	if (FPackageName::TryConvertLongPackageNameToFilename(
			ManifestPkgName, ManifestFilename, FPackageName::GetAssetPackageExtension()))
	{
		FSavePackageArgs SaveArgs;
		SaveArgs.TopLevelFlags = RF_Public | RF_Standalone;
		SaveArgs.SaveFlags = SAVE_NoError;
		bSaved = UPackage::SavePackage(ManifestPkg, Manifest, *ManifestFilename, SaveArgs);
	}

	// Tidy up the shard files now that they're merged.
	for (const FString& ShardName : ShardFiles) { IFileManager::Get().Delete(*(ShardDir / ShardName)); }

	UE_LOG(LogTemp, Display,
		TEXT("[MiraThalBake] MergeShards: %d shards -> %d tiles, saved=%d (tileSpan=%d fp=%llu) world='%s'"),
		ShardFiles.Num(), Manifest->Tiles.Num(), bSaved ? 1 : 0, Manifest->TileSpanVoxels,
		Manifest->GenFingerprint, *WorldSaveName);
	return bSaved;
}

} // namespace VoxelCrustBaker

#endif // WITH_EDITOR
