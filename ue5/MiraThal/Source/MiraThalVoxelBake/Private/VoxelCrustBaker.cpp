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

	UMaterialInterface* TerrainMaterial = World->TerrainMaterial;

	// The asset folder for this world: /Game/VoxelBake/<world>/...
	const FString BaseDir = FString::Printf(TEXT("/Game/VoxelBake/%s"), *WorldSaveName);

	// ---- STEP A: fan the PURE sample+mesh work out across worker threads. The actual
	//      generator-backed sampling + greedy-mesh lives in MiraThalVoxel (exported
	//      AVoxelChunkActor::SampleAndMeshCrustTile) so the generator's Core symbols link;
	//      this module just drives the loop + the (serial) UObject build/save. ----
	struct FInFlight { Vec2i Tile; TFuture<FCrustTileMesh> Future; };
	TArray<FInFlight> Jobs;
	for (int32 tz = -Radius; tz <= Radius; ++tz)
	for (int32 tx = -Radius; tx <= Radius; ++tx)
	{
		const Vec2i Tile(tx, tz);

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

		FInFlight Job;
		Job.Tile = Tile;
		Job.Future = Async(EAsyncExecution::ThreadPool,
			[Tile, P, TileSpan, Stride, Skirt]()
			{
				return AVoxelChunkActor::SampleAndMeshCrustTile(
					P, Tile.x, Tile.y, TileSpan, Stride, Skirt);
			});
		Jobs.Add(MoveTemp(Job));
	}

	// ---- STEP B: SERIALLY consume payloads on the game/editor thread (UObject build +
	//      package save are not thread-safe). Build the Nanite mesh, save it, record it. ----
	// RF_Public | RF_Standalone so SavePackage actually persists the manifest. Without these
	// flags the save is skipped ("does not have any of the provided object flags ... would cause
	// data loss") and the runtime streamer then has no manifest to load the baked tiles from.
	// Created in the transient package, then Rename()d into the real manifest package before save.
	UVoxelBakeManifest* Manifest = NewObject<UVoxelBakeManifest>(
		GetTransientPackage(), NAME_None, RF_Public | RF_Standalone);
	Manifest->WorldSaveName  = WorldSaveName;
	Manifest->TileSpanVoxels = TileSpan;

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

			const FCrustTileMesh Payload = Job.Future.Get(); // blocks until this tile is meshed

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
			else
			{
				// One package + one asset per tile: /Game/VoxelBake/<world>/Tile_X_Z.
				const FString PackageName = FString::Printf(TEXT("%s/%s"), *BaseDir, *AssetName);

				UE_LOG(LogTemp, Display,
					TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=package pkg=%s"),
					TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *PackageName);

				UPackage* Package = CreatePackage(*PackageName);
				if (Package == nullptr)
				{
					UE_LOG(LogTemp, Error,
						TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) -> FAILED (CreatePackage %s)"),
						TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *PackageName);
					++FailedTiles;
				}
				else
				{
					Package->FullyLoad();

					UE_LOG(LogTemp, Display,
						TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=build verts=%d tris=%d"),
						TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, ThisVerts, ThisTris);

					UStaticMesh* Mesh = VoxelNaniteBaker::BuildNaniteStaticMeshFromMesh(
						Payload.Mb, TerrainMaterial, Package, FName(*AssetName));
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
							TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=built mesh=%s step=save pkg=%s"),
							TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *Mesh->GetName(), *PackageName);

						if (!SaveBakedMeshPackage(Package, Mesh, PackageName))
						{
							UE_LOG(LogTemp, Error,
								TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) -> FAILED (SavePackage %s)"),
								TileIndex, NumQueued, Job.Tile.x, Job.Tile.y, *PackageName);
							++FailedTiles;
						}
						else
						{
							UE_LOG(LogTemp, Display,
								TEXT("[MiraThal] BAKE tile %d/%d key=(%d,%d) step=saved"),
								TileIndex, NumQueued, Job.Tile.x, Job.Tile.y);

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
	}

	// ---- STEP C: save the manifest data asset alongside the tiles. ----
	const FString ManifestPkgName = FString::Printf(TEXT("%s/Manifest"), *BaseDir);
	UPackage* ManifestPkg = CreatePackage(*ManifestPkgName);
	if (ManifestPkg)
	{
		ManifestPkg->FullyLoad();
		// Re-home the manifest from the transient package into its saved package.
		Manifest->Rename(TEXT("Manifest"), ManifestPkg, REN_DontCreateRedirectors | REN_NonTransactional);
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

} // namespace VoxelCrustBaker

#endif // WITH_EDITOR
