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
#include "TdiffWorldHook.h"            // UTdiffWorldHook::SnapPlayerToLand (shared land-spawn)
#include "TdiffAutoStreamSubsystem.h"  // auto-start on Play
#include "Core/Tdiff/DetailBridge.h"   // mira::tdiff::DetailBridgeParams
#include "TimerManager.h"              // FTimerHandle — delayed auto-start

#include "VoxelWorld.h"
#include "EngineUtils.h"               // TActorIterator
#include "Engine/World.h"
#include "GameFramework/Pawn.h"        // APawn — spawn on highest land
#include "Kismet/GameplayStatics.h"    // UGameplayStatics::GetPlayerPawn
#include "HAL/IConsoleManager.h"
#include "Templates/UniquePtr.h"
#include "Logging/LogMacros.h"

DEFINE_LOG_CATEGORY_STATIC(LogMiraTdiffStream, Log, All);

// PHASE 4 toggle. 0 (default) = the proven SYNCHRONOUS per-tile inference on the game thread.
// 1 = generate tiles on a background thread (FDiffusionDemService::RequestTile/HarvestTiles) so
// the ~1.6 s/tile GPU inference no longer freezes the game thread. EXPERIMENTAL: DirectML-off-
// thread is unproven in this build, so this stays OFF until validated in PIE. Read once at
// StartStreaming (change it, then re-run MiraThal.Tdiff.Stream to apply).
static TAutoConsoleVariable<int32> CVarTdiffAsyncTiles(
	TEXT("MiraThal.Tdiff.AsyncTiles"),
	0,
	TEXT("AI terrain tile generation: 0 = synchronous on the game thread (default, proven); "
	     "1 = asynchronous on a background thread (Phase 4, experimental). Applied at the next "
	     "MiraThal.Tdiff.Stream."),
	ECVF_Default);

// TERRAIN DRAMA knob: voxels of render-height per real AI metre. 10 = true 1:1 scale — dramatic,
// near-vertical mountains (the coarse DEM is 30 m/px, so real relief renders very steep up close).
// LOWER compresses the heights into gentler rolling hills (4 ≈ a good rolling default). Sea line is
// unaffected (base is fixed). Read once at StartStreaming — set it, then re-run MiraThal.Tdiff.Stream.
static TAutoConsoleVariable<float> CVarTdiffVerticalScale(
	TEXT("MiraThal.Tdiff.VerticalScale"),
	4.0f,
	TEXT("AI terrain vertical scale (voxels of height per real metre). 10 = true/steep, "
	     "lower = gentler rolling hills. Clamped [0.5,20]. Applied at the next MiraThal.Tdiff.Stream."),
	ECVF_Default);

namespace
{
	// Same export location the bounded path uses (TdiffWorldHook GTdiffOnnxDir/StatsPath).
	static const TCHAR* GStreamOnnxDir   = TEXT("D:/terrain-diffusion/onnx_export");
	static const TCHAR* GStreamStatsPath = TEXT("D:/terrain-diffusion/synthetic_map_stats.json");

	constexpr int32 kChunkVox       = 32;   // coords::CHUNK — voxels per chunk axis
	constexpr int32 kRingTiles      = 1;    // ensure the focus tile + its 8-neighbour ring (apron)
	constexpr int32 kEnsurePerTick  = 1;    // tiles generated per TickStreaming (spread the GPU cost)
	constexpr int32 kInitRingTiles  = 1;    // pre-warm radius at StartStreaming (synchronous)

	// --- Phase 4 async knobs (only used when bAsyncTileGen). Because async no longer BLOCKS the
	// game thread, we can request a slightly wider ring + harvest several tiles/tick without a
	// hitch. Kept modest: the real concurrency is still capped by MaxTileJobsInFlight (=2).
	constexpr int32 kAsyncRequestRing = 2;   // request focus + a 2-ring (5x5) so jobs stay queued ahead
	constexpr int32 kHarvestPerTick   = 4;   // resident-map promotions per tick (cheap — just map adds)

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

	// PHASE 4: mirror the CVar onto the service. FALSE (default) keeps the proven synchronous
	// EnsureTileResident path below unchanged; TRUE routes the per-tile inference onto a background
	// thread via RequestTile/HarvestTiles. Read once here so a mid-session flip needs a re-Stream.
	const bool bAsync = CVarTdiffAsyncTiles.GetValueOnGameThread() != 0;
	S.Service->bAsyncTileGen = bAsync;

	// 2) Vertical mapping: voxelY = SeaVoxBase + metres * VerticalScale, clamped to kMaxSurfaceVoxels.
	//    BASE is fixed at SeaLevelMeters*10 vox so the AI sea line matches the generator's
	//    sea_level_voxels (= water fills to the right height). SCALE is a TUNABLE knob (voxels of
	//    render-height per real AI metre): 10 = true 1:1 scale (dramatic, near-vertical mountains
	//    because the coarse grid is 30 m/px); LOWER = gentler rolling hills. Decoupled from base so
	//    tuning drama never moves the sea line. Read once here — change the CVar, then re-Stream.
	const double SeaVoxBase    = static_cast<double>(World->SeaLevelMeters) * 10.0; // == generator sea line
	const double VoxelsPerMetre = FMath::Clamp(CVarTdiffVerticalScale.GetValueOnGameThread(), 0.5, 20.0);
	S.Service->SetVerticalMapping(/*scale=*/ VoxelsPerMetre, /*base=*/ SeaVoxBase);
	UE_LOG(LogMiraTdiffStream, Display,
		TEXT("[Tdiff] vertical scale = %.1f vox/m (10=true 1:1/steep, lower=rolling); sea base = %.0f vox."),
		VoxelsPerMetre, SeaVoxBase);

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
		S.Service->TileSpanVoxels, S.Service->VerticalFloorVoxels());

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

		// ---- PHASE 4 ASYNC PATH ------------------------------------------------------------
		// Non-blocking: promote any finished background jobs into the resident map FIRST (game
		// thread, BEFORE this tick's columns enqueue — the same timing the sync add has, so the
		// game-thread-only-writer invariant is preserved), then fire off requests for the focus +
		// ring. RequestTile is cheap + idempotent and self-caps at MaxTileJobsInFlight, so a wider
		// ring just keeps the queue primed; only a couple of jobs actually run at once.
		if (Svc->bAsyncTileGen)
		{
			Svc->HarvestTiles(kHarvestPerTick);

			for (int32 r = 0; r <= kAsyncRequestRing; ++r)
			{
				for (int32 dz = -r; dz <= r; ++dz)
				for (int32 dx = -r; dx <= r; ++dx)
				{
					if (FMath::Max(FMath::Abs(dx), FMath::Abs(dz)) != r) { continue; } // ring shell only
					const FIntPoint TC(FT.X + dx, FT.Y + dz);
					if (!Svc->GetResidentTile(Sd, TC).IsValid())
					{
						Svc->RequestTile(Sd, TC); // non-blocking; skips if resident/in-flight/at-cap
					}
				}
			}
			return;
		}

		// ---- SYNCHRONOUS PATH (default, unchanged) -----------------------------------------
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
	//    NOTE (Phase 4): this synchronous pre-warm runs the provider on the GAME THREAD, which
	//    triggers the runner's lazy model load (NewObject<UNNEModelData> + DDC) HERE — before any
	//    async job exists. That is the natural mitigation for the "first inference off-thread"
	//    risk: by the time RequestTile fires a background job, all 3 UNets are already loaded, so
	//    the worker only calls RunSync on already-constructed instances (no UObject creation).
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
	UTdiffWorldHook::RemoveBakedTerrain(World); // clear legacy baked-EXR crust/far-mesh overlays
	// SPAWN ON THE HIGHEST AI LAND (not origin, which may be ocean): scan the pre-warmed tiles
	// for the tallest land cell and drop the player there (a mountain). Streaming focus follows,
	// so chunks fill in under them. Falls back to the origin land-search if it is all ocean.
	{
		double LandX = 0.0, LandZ = 0.0, LandHVox = 0.0;
		const double SeaVox = static_cast<double>(World->SeaLevelMeters) * 10.0;
		// Only teleport to the highest land if it is NEAR origin (inside the region GenerateWorld
		// already filled synchronously) — otherwise the player would hang in the sky waiting for
		// far chunks to stream. ~800 m box. Far/oceanic seeds fall back to the safe near-origin snap.
		const double NearVox = 8000.0;
		if (Svc->HighestResidentLand(Sd, LandX, LandZ, LandHVox) && LandHVox > SeaVox + 50.0
			&& FMath::Abs(LandX) < NearVox && FMath::Abs(LandZ) < NearVox)
		{
			// CRITICAL: the coarse-cell height (LandHVox) is only an ESTIMATE. The actual voxel
			// surface the player stands on comes from the SAME sampler the columns use (detail
			// bridge + apron + floor clamp). Re-sample it at the chosen XZ so we place the pawn ON
			// the real ground, not floating above a coarse guess (that mismatch was the "floating
			// high above the terrain" bug). Log both so any remaining disagreement is visible.
			const double RealVox = static_cast<double>(S.Source->sample_value(LandX, LandZ));
			const FVector Spawn(LandX * 10.0, LandZ * 10.0, RealVox * 10.0 + 200.0); // +2 m, feet on ground
			if (APawn* Pawn = UGameplayStatics::GetPlayerPawn(World->GetWorld(), 0))
			{
				Pawn->SetActorLocation(Spawn, false, nullptr, ETeleportType::TeleportPhysics);
			}
			Svc->SetTileFocus(FDiffusionDemService::TileCoordOf(static_cast<int64>(LandX),
			                                                    static_cast<int64>(LandZ), Span));
			UE_LOG(LogMiraTdiffStream, Display,
				TEXT("[Tdiff] spawned on highest AI land at world (%.0f,%.0f) vox: coarse est %.0f vox "
				     "(%.0f m), REAL sampled %.0f vox (%.0f m). Sea %.0f vox, seabed floor %.0f vox."),
				LandX, LandZ, LandHVox, LandHVox / 10.0, RealVox, RealVox / 10.0,
				SeaVox, Svc->VerticalFloorVoxels());
		}
		else
		{
			UTdiffWorldHook::SnapPlayerToLand(World); // all ocean nearby — sit at sea level
		}
	}
	S.bActive = true;

	UE_LOG(LogMiraTdiffStream, Display,
		TEXT("[Tdiff] STREAMING started: seed %lld, tileSpan %d vox (~%.1f km), %d resident tile(s). "
		     "Walk anywhere — terrain streams in. (conditioning=%s, tilegen=%s)"),
		static_cast<long long>(Seed), Span, Span / 10000.0, Svc->NumResidentTiles(),
		bHaveStats ? TEXT("on") : TEXT("zero"),
		bAsync ? TEXT("ASYNC (background thread)") : TEXT("synchronous (game thread)"));
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

// ============================================================================================
// DIAGNOSTIC: MiraThal.Tdiff.Diag — dump the player's exact terrain situation so we can SEE
// (not guess) why terrain looks wrong: pawn height vs the REAL sampled surface + sea + seabed
// floor, whether the covering tile is resident, and the ocean/land verdict at the pawn's spot.
// ============================================================================================
static void TdiffDiagConsole(const TArray<FString>& Args, UWorld* World)
{
	if (!World) { return; }
	FStreamState& S = Stream();
	if (!S.bActive || !S.Service.IsValid() || !S.Source.IsValid())
	{
		UE_LOG(LogMiraTdiffStream, Warning,
			TEXT("[Tdiff][Diag] streaming is not active — run MiraThal.Tdiff.Stream <seed> first."));
		return;
	}

	APawn* Pawn = UGameplayStatics::GetPlayerPawn(World, 0);
	if (!Pawn) { UE_LOG(LogMiraTdiffStream, Warning, TEXT("[Tdiff][Diag] no player pawn.")); return; }

	const FVector Loc = Pawn->GetActorLocation();
	const int64 WX = static_cast<int64>(FMath::RoundToDouble(Loc.X / 10.0)); // UU -> world voxel
	const int64 WZ = static_cast<int64>(FMath::RoundToDouble(Loc.Y / 10.0));
	const double SurfVox = static_cast<double>(S.Source->sample_value(static_cast<double>(WX),
	                                                                   static_cast<double>(WZ)));
	const int32  Span    = S.Service->TileSpanVoxels;
	const FIntPoint TC   = FDiffusionDemService::TileCoordOf(WX, WZ, Span);
	const bool bResident = S.Service->GetResidentTile(S.Seed, TC).IsValid();

	UE_LOG(LogMiraTdiffStream, Display,
		TEXT("[Tdiff][Diag] pawn UU(%.0f,%.0f,%.0f) = vox(%lld,%lld) Z=%.1f vox | surface here = %.1f vox "
		     "(%.1f m) | sea=%.0f floor=%.0f | %s | tile (%d,%d) resident=%s | residentTiles=%d | tilegen=%s"),
		Loc.X, Loc.Y, Loc.Z, (long long)WX, (long long)WZ, Loc.Z / 10.0,
		SurfVox, SurfVox / 10.0,
		S.Service->GetVerticalBaseVoxels(), S.Service->VerticalFloorVoxels(),
		SurfVox < S.Service->GetVerticalBaseVoxels() ? TEXT("UNDER SEA (water column here)") : TEXT("dry land"),
		TC.X, TC.Y, bResident ? TEXT("YES") : TEXT("NO (column defers -> hole/flat)"),
		S.Service->NumResidentTiles(),
		S.Service->bAsyncTileGen ? TEXT("ASYNC") : TEXT("sync"));
}

static FAutoConsoleCommandWithWorldAndArgs GTdiffDiagCmd(
	TEXT("MiraThal.Tdiff.Diag"),
	TEXT("Dump the player's terrain diagnostics (surface height, sea/floor, tile residency)."),
	FConsoleCommandWithWorldAndArgsDelegate::CreateStatic(&TdiffDiagConsole));

// ============================================================================================
// AUTO-START on Play (UTdiffAutoStreamSubsystem::OnWorldBeginPlay, declared in the header).
// Default ON. Waits a beat for the player pawn to spawn, then streams the default seed — which
// also destroys the legacy baked crust. Disable with MiraThal.Tdiff.AutoStream 0.
// ============================================================================================
static TAutoConsoleVariable<int32> CVarTdiffAutoStream(
	TEXT("MiraThal.Tdiff.AutoStream"), 1,
	TEXT("1 (default) = auto-start AI terrain streaming when a level begins play. "
	     "0 = off (start it manually with MiraThal.Tdiff.Stream)."),
	ECVF_Default);

static TAutoConsoleVariable<int32> CVarTdiffAutoStreamSeed(
	TEXT("MiraThal.Tdiff.AutoStreamSeed"), 99,
	TEXT("Seed the auto-start uses when a level begins play (MiraThal.Tdiff.AutoStream)."),
	ECVF_Default);

void UTdiffAutoStreamSubsystem::OnWorldBeginPlay(UWorld& InWorld)
{
	Super::OnWorldBeginPlay(InWorld);

	if (CVarTdiffAutoStream.GetValueOnGameThread() == 0) { return; }
	if (!InWorld.IsGameWorld()) { return; }

	// Only auto-start if the level actually has a voxel world to stream into.
	AVoxelWorld* VoxelWorld = nullptr;
	for (TActorIterator<AVoxelWorld> It(&InWorld); It; ++It) { VoxelWorld = *It; break; }
	if (!VoxelWorld) { return; }

	const int64 Seed = static_cast<int64>(CVarTdiffAutoStreamSeed.GetValueOnGameThread());
	UE_LOG(LogMiraTdiffStream, Display,
		TEXT("[Tdiff] AutoStream: level begun play — starting AI streaming (seed %lld) in ~0.6s."),
		(long long)Seed);

	// Wait a beat so the player pawn + voxel world are fully initialised, then start streaming.
	TWeakObjectPtr<AVoxelWorld> WeakVW(VoxelWorld);
	FTimerHandle Th;
	InWorld.GetTimerManager().SetTimer(Th, [WeakVW, Seed]()
	{
		if (AVoxelWorld* VW = WeakVW.Get())
		{
			StartStreaming(VW, Seed);
		}
	}, 0.6f, false);
}
