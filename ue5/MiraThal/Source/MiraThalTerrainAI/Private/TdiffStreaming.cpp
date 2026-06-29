// TdiffStreaming.cpp — Phase 2: wire the streaming AI height source into AVoxelWorld so the
// world generates INFINITELY as the player explores (not just one bounded FillRegion patch).
//
// PLAIN ENGLISH:
// FillRegion (TdiffWorldHook) paints ONE bounded patch and stops. This file makes the terrain
// keep coming: it owns a streaming FDiffusionDemService (a cache of ~1.9 km region tiles that
// fill in on demand) + a mira::DiffusionHeightSource over it, and binds two game-thread
// callbacks into AVoxelWorld:
//   * EnsureFn(focusChunk)  — each TickStreaming, make the tile under the player (+ its ring)
//     resident (synchronous GPU inference, BUDGETED to a few tiles/tick — never on a worker).
//   * ColumnReadyFn(column) — true once the column's covering tile is resident, so the streamer
//     only enqueues columns whose ground data exists (others defer + retry next tick).
// The height source then samples the resident coarse tiles through the detail bridge. Because
// the diffusion noise is WORLD-POSITIONED (shipped earlier), independently-generated tiles line
// up — the world is seamless and deterministic per seed.
//
// DEP DIRECTION: this lives in MiraThalTerrainAI (which depends on MiraThalVoxel). AVoxelWorld
// only ever sees a const mira::IHeightSource* + two TFunctions (SetStreamingHeightSource), so the
// voxel module never names an AI type — the one-way dependency root is preserved.
//
// KNOWN FOLLOW-UPS (documented, not yet done — runtime polish that needs in-editor tuning):
//  (A) APRON: EnsureTileResident currently builds each tile over its exact rect with no overlap,
//      so the bicubic/slope stencil clamps at a tile's edge -> a faint seam every TileSpanVoxels.
//      The seam test (test_tdiff_streamsource) proves tiles are bit-identical GIVEN a >=2px apron;
//      add an apron to EnsureTileResident's rect + the source georef to make edges perfect.
//  (B) GenerateRegion (the immediate bounded fill in GenerateWorld) does not honour the
//      ColumnReadyFn gate, so columns generated before their tile streams in fall back flat until
//      re-gen. StartStreaming pre-warms the central ring to mask this; full gating of the bounded
//      fill is the clean fix.

#include "DiffusionDemService.h"
#include "DiffusionHeightSource.h"
#include "DiffusionCoarseProvider.h"   // FDiffusionCoarseProvider::Make — real GPU provider
#include "Core/Tdiff/DetailBridge.h"   // mira::tdiff::DetailBridgeParams

#include "VoxelWorld.h"
#include "EngineUtils.h"               // TActorIterator
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"
#include "Templates/UniquePtr.h"
#include "Logging/LogMacros.h"

DEFINE_LOG_CATEGORY_STATIC(LogMiraTdiffStream, Log, All);

namespace
{
	// Same export location the bounded path uses (TdiffWorldHook GTdiffOnnxDir/StatsPath).
	static const TCHAR* GStreamOnnxDir   = TEXT("D:/terrain-diffusion/onnx_export");
	static const TCHAR* GStreamStatsPath = TEXT("D:/terrain-diffusion/synthetic_map_stats.json");

	constexpr int32 kChunkVox       = 32;   // coords::CHUNK — voxels per chunk axis
	constexpr int32 kRingTiles      = 1;    // ensure the focus tile + its 8-neighbour ring (apron)
	constexpr int32 kEnsurePerTick  = 1;    // tiles generated per TickStreaming (spread the GPU cost)
	constexpr int32 kInitRingTiles  = 1;    // pre-warm radius at StartStreaming (synchronous)

	// The streaming state lives for the whole module (mirrors TdiffWorldHook's GetDemService):
	// one service + one source, recreated per StartStreaming (per seed). Held in TUniquePtr so the
	// non-owning pointers handed to AVoxelWorld stay valid until the next StartStreaming/teardown.
	struct FStreamState
	{
		TUniquePtr<FDiffusionDemService>        Service;
		TUniquePtr<mira::DiffusionHeightSource> Source;
		int64 Seed = 0;
		bool  bActive = false;
	};
	FStreamState& Stream()
	{
		static FStreamState S;
		return S;
	}

	// chunk column -> world voxel centre (matches GetFocusChunkXZ's chunk*CHUNK mapping).
	FORCEINLINE void ChunkToWorldVoxel(FIntPoint Chunk, int64& OutX, int64& OutZ)
	{
		OutX = static_cast<int64>(Chunk.X) * kChunkVox + kChunkVox / 2;
		OutZ = static_cast<int64>(Chunk.Y) * kChunkVox + kChunkVox / 2;
	}
}

// Begin (or restart) infinite streaming centred on the player, for a given seed.
static void StartStreaming(AVoxelWorld* World, int64 Seed)
{
	if (!World)
	{
		UE_LOG(LogMiraTdiffStream, Warning, TEXT("[Tdiff] Stream: no AVoxelWorld."));
		return;
	}

	FStreamState& S = Stream();

	// 1) Fresh service backed by the real GPU provider (falls back to the analytic stub if the
	//    ONNX export is absent — same contract as the bounded path).
	const bool bHaveStats = FPaths::FileExists(FString(GStreamStatsPath));
	S.Service = MakeUnique<FDiffusionDemService>(
		FDiffusionCoarseProvider::Make(FString(GStreamOnnxDir),
		                               bHaveStats ? FString(GStreamStatsPath) : FString()));
	S.Seed = Seed;

	// 2) Vertical mapping: sea-anchored, identical to TdiffWorldHook::FillRegion so streaming and
	//    bounded output agree (voxelY = SeaLevelMeters*10 + metres*10, clamped to kMaxSurfaceVoxels).
	constexpr double VoxelsPerMetre = 10.0;
	S.Service->SetVerticalMapping(/*scale=*/ VoxelsPerMetre,
	                              /*base=*/  static_cast<double>(World->SeaLevelMeters) * VoxelsPerMetre);

	// 3) Detail-bridge params with the AI smoothing overrides (R9 parity with the bounded path,
	//    which applies these inside BuildHeightmapFromCoarse).
	mira::tdiff::DetailBridgeParams Detail;
	Detail.slopeBoost      = 0.25;
	Detail.detailAmpVoxels = 12.0;
	Detail.detailFreq      = 0.02;
	Detail.seed            = static_cast<int64_t>(Seed);

	S.Source = MakeUnique<mira::DiffusionHeightSource>(
		S.Service.Get(), Seed, Detail,
		S.Service->GetVerticalScaleVoxels(), S.Service->GetVerticalBaseVoxels(),
		S.Service->TileSpanVoxels);

	// 4) Bind the two game-thread callbacks (capture raw service ptr — owned by FStreamState,
	//    outlives the world's use of them; reset only on the next StartStreaming).
	FDiffusionDemService* Svc = S.Service.Get();
	const int64 Sd   = Seed;
	const int32 Span = S.Service->TileSpanVoxels;

	auto EnsureFn = [Svc, Sd, Span](FIntPoint FocusChunk)
	{
		int64 wx, wz; ChunkToWorldVoxel(FocusChunk, wx, wz);
		const FIntPoint FT = FDiffusionDemService::TileCoordOf(wx, wz, Span);
		Svc->SetTileFocus(FT); // eviction keeps tiles near the player

		// Make the focus tile + ring resident, nearest-first, budgeted so the GPU cost spreads
		// across ticks instead of one big freeze. Already-resident tiles are skipped (cheap).
		int32 Budget = kEnsurePerTick;
		for (int32 r = 0; r <= kRingTiles && Budget > 0; ++r)
		{
			for (int32 dz = -r; dz <= r && Budget > 0; ++dz)
			for (int32 dx = -r; dx <= r && Budget > 0; ++dx)
			{
				if (FMath::Max(FMath::Abs(dx), FMath::Abs(dz)) != r) { continue; } // ring shell only
				const FIntPoint TC(FT.X + dx, FT.Y + dz);
				if (!Svc->GetResidentTile(Sd, TC).IsValid())
				{
					Svc->EnsureTileResident(Sd, TC);
					--Budget;
				}
			}
		}
	};

	auto ReadyFn = [Svc, Sd, Span](FIntPoint Col) -> bool
	{
		int64 wx, wz; ChunkToWorldVoxel(Col, wx, wz);
		const FIntPoint TC = FDiffusionDemService::TileCoordOf(wx, wz, Span);
		// A column is "ready" once its covering tile is resident. (Edge columns also want the
		// neighbour ring for a perfect apron — follow-up A; for now the covering tile gates gen.)
		return Svc->GetResidentTile(Sd, TC).IsValid();
	};

	// 5) Pre-warm the central tile(s) synchronously so the world isn't empty on the first frame.
	{
		int64 wx, wz; ChunkToWorldVoxel(FIntPoint(0, 0), wx, wz);
		const FIntPoint FT = FDiffusionDemService::TileCoordOf(wx, wz, Span);
		for (int32 dz = -kInitRingTiles; dz <= kInitRingTiles; ++dz)
		for (int32 dx = -kInitRingTiles; dx <= kInitRingTiles; ++dx)
		{
			Svc->EnsureTileResident(Sd, FIntPoint(FT.X + dx, FT.Y + dz));
		}
		Svc->SetTileFocus(FT);
	}

	// 6) Install + switch the world to the streaming AI source and (re)build around the player.
	World->SetStreamingHeightSource(S.Source.Get(), EnsureFn, ReadyFn);
	World->HeightSource = EVoxelHeightSource::DiffusionAI;
	World->GenerateWorld();
	S.bActive = true;

	UE_LOG(LogMiraTdiffStream, Display,
		TEXT("[Tdiff] STREAMING started: seed %lld, tileSpan %d vox (~%.1f km), %d resident tile(s). "
		     "Walk anywhere — terrain streams in. (conditioning=%s)"),
		static_cast<long long>(Seed), Span, Span / 10000.0, Svc->NumResidentTiles(),
		bHaveStats ? TEXT("on") : TEXT("zero"));
}

// Console: MiraThal.Tdiff.Stream [Seed]  — start infinite streaming for the level's AVoxelWorld.
static void TdiffStreamConsole(const TArray<FString>& Args, UWorld* World)
{
	if (!World) { return; }
	int64 Seed = 1337;
	if (Args.Num() >= 1) { Seed = FCString::Atoi64(*Args[0]); }

	AVoxelWorld* VoxelWorld = nullptr;
	for (TActorIterator<AVoxelWorld> It(World); It; ++It) { VoxelWorld = *It; break; }
	if (!VoxelWorld)
	{
		UE_LOG(LogMiraTdiffStream, Warning, TEXT("[Tdiff] Stream: no AVoxelWorld in the level."));
		return;
	}
	StartStreaming(VoxelWorld, Seed);
}

static FAutoConsoleCommandWithWorldAndArgs GTdiffStreamCmd(
	TEXT("MiraThal.Tdiff.Stream"),
	TEXT("Start INFINITE AI terrain streaming centred on the player (Phase 2). "
	     "Usage: MiraThal.Tdiff.Stream [Seed]"),
	FConsoleCommandWithWorldAndArgsDelegate::CreateStatic(&TdiffStreamConsole));
