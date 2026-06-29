// TdiffWorldHook.cpp — install an AI DEM onto an AVoxelWorld + the PIE console command.
// See TdiffWorldHook.h for the contract and dependency-direction notes.

#include "TdiffWorldHook.h"

#include "DiffusionDemService.h"
#include "DiffusionCoarseProvider.h"    // FDiffusionCoarseProvider::Make — the real GPU provider
#include "VoxelWorld.h"                 // AVoxelWorld::SetDiffusionHeightmap / GenerateWorld
#include "Core/ImageHeightmap.h"

#include "EngineUtils.h"               // TActorIterator — find the AVoxelWorld in a level
#include "Engine/World.h"
#include "GameFramework/Pawn.h"        // APawn — player snap-to-surface
#include "Kismet/GameplayStatics.h"    // UGameplayStatics::GetPlayerPawn
#include "HAL/IConsoleManager.h"       // FAutoConsoleCommandWithWorldAndArgs
#include "Misc/Paths.h"               // FPaths::FileExists — probe for the exported ONNX models
#include "Logging/LogMacros.h"

DEFINE_LOG_CATEGORY_STATIC(LogMiraTdiffHook, Log, All);

// Where the offline ONNX export + (optional) conditioning stats live. If you move the
// export, change these two paths. The coarse model's presence is the switch between "real
// GPU AI" and "analytic stub" — see GetDemService().
static const TCHAR* GTdiffOnnxDir   = TEXT("D:/terrain-diffusion/onnx_export");
static const TCHAR* GTdiffStatsPath = TEXT("D:/terrain-diffusion/synthetic_map_stats.json");

// One persistent service for the whole module, so its region cache survives across calls
// (a second FillRegion of the same seed+region is a cache hit). Function-local static =
// constructed on first use, never before.
//
// GATE 3 PASSED -> we now install the REAL, GPU-backed coarse provider (FDiffusionCoarseProvider)
// the FIRST time the service is touched, PROVIDED the exported ONNX models are on disk. If they
// aren't (e.g. a machine without the export), we leave the default analytic STUB in place so the
// path is still exercisable. The synthetic_map_stats.json is optional: present -> real
// large-scale geography conditioning; absent -> zero conditioning (still real diffusion output).
static FDiffusionDemService& GetDemService()
{
	static FDiffusionDemService Service; // default ctor installs the analytic stub provider
	static bool bProviderInitialised = false;
	if (!bProviderInitialised)
	{
		bProviderInitialised = true; // runs on the game thread (console/BP) — single-shot is fine

		const FString CoarseModel = FString(GTdiffOnnxDir) / TEXT("coarse_model.onnx");
		if (FPaths::FileExists(CoarseModel))
		{
			const bool bHaveStats = FPaths::FileExists(FString(GTdiffStatsPath));
			Service.SetProvider(FDiffusionCoarseProvider::Make(
				FString(GTdiffOnnxDir),
				bHaveStats ? FString(GTdiffStatsPath) : FString()));
			UE_LOG(LogMiraTdiffHook, Display,
				TEXT("[Tdiff] REAL GPU AI provider installed (ONNX '%s', conditioning=%s). "
				     "First FillRegion will run ~23 GPU calls/tile — expect a multi-second hitch."),
				GTdiffOnnxDir, bHaveStats ? TEXT("ON") : TEXT("ZERO (no stats file)"));
		}
		else
		{
			UE_LOG(LogMiraTdiffHook, Warning,
				TEXT("[Tdiff] ONNX models not found at '%s' — using analytic STUB provider. "
				     "Export the models or fix GTdiffOnnxDir to get real AI terrain."),
				GTdiffOnnxDir);
		}
	}
	return Service;
}

// ---------------------------------------------------------------------------
// BlueprintCallable: build + install + (optionally) rebuild.
// ---------------------------------------------------------------------------
bool UTdiffWorldHook::FillRegion(AVoxelWorld* World, int64 Seed,
                                 int32 MinX, int32 MinZ, int32 MaxX, int32 MaxZ,
                                 bool bRegenerate)
{
	if (!World)
	{
		UE_LOG(LogMiraTdiffHook, Warning, TEXT("[Tdiff] FillRegion: no AVoxelWorld supplied."));
		return false;
	}

	const FIntRect Region(MinX, MinZ, MaxX, MaxZ);

	FDiffusionDemService& Service = GetDemService();
	// VERTICAL ANCHORING (2026-06-29 fix): the provider now hands us ABSOLUTE elevation in
	// METRES (it no longer normalises the region to [0,1] - that floated the whole AI surface
	// ~375 m above the player's sea-level spawn). So map metres -> voxel-Y anchored at the
	// world's SEA LEVEL: voxelY = seaLevelVox + metres * 10. Then AI 0 m == world sea level and
	// the player spawns ON the surface. scale = 10 vox/m, base = sea level in voxels.
	constexpr double VoxelsPerMetre = 10.0;
	Service.SetVerticalMapping(
		/*scaleVoxels=*/ VoxelsPerMetre,
		/*baseVoxels=*/  static_cast<double>(World->SeaLevelMeters) * VoxelsPerMetre);

	mira::ImageHeightmap Hm;
	if (!Service.TryGetRegionHeightmap(Seed, Region, Hm))
	{
		UE_LOG(LogMiraTdiffHook, Warning,
			TEXT("[Tdiff] FillRegion: service produced no heightmap for region "
			     "[%d,%d]..[%d,%d] (seed %lld)."),
			MinX, MinZ, MaxX, MaxZ, static_cast<long long>(Seed));
		return false;
	}

	// Hand the finished surface to the voxel world (it copies it in + flips HeightSource to
	// DiffusionAI). The existing generator/bake then render it via the EXR plumbing.
	if (!World->SetDiffusionHeightmap(Hm, Seed))
	{
		return false;
	}

	if (bRegenerate)
	{
		// Rebuild the previewed region so the AI terrain is visible immediately. In play
		// with streaming on, newly streamed columns also pick up the new source.
		World->GenerateWorld();

		// Drop the player ONTO the freshly-installed surface (shared with the streaming path).
		SnapPlayerToLand(World);
	}

	UE_LOG(LogMiraTdiffHook, Display,
		TEXT("[Tdiff] FillRegion DONE: installed AI DEM on '%s' for region [%d,%d]..[%d,%d] "
		     "(seed %lld), regenerate=%s."),
		*World->GetName(), MinX, MinZ, MaxX, MaxZ, static_cast<long long>(Seed),
		bRegenerate ? TEXT("yes") : TEXT("no"));
	return true;
}

bool UTdiffWorldHook::FillCenteredRegion(AVoxelWorld* World, int64 Seed,
                                         int32 HalfExtentVoxels, bool bRegenerate)
{
	const int32 H = FMath::Max(1, HalfExtentVoxels);
	return FillRegion(World, Seed, -H, -H, H, H, bRegenerate);
}

// Spiral-search the nearby surface for dry land and stand the pawn there (else at sea level).
// Shared by FillRegion + the streaming path so the player never starts floating above/under the
// new terrain. UU: 1 voxel = 10 UU, 1 m = 100 UU.
void UTdiffWorldHook::SnapPlayerToLand(AVoxelWorld* World)
{
	if (!World) { return; }
	UWorld* W = World->GetWorld();
	if (!W) { return; }
	APawn* Pawn = UGameplayStatics::GetPlayerPawn(W, 0);
	if (!Pawn) { return; }

	const FVector Loc = Pawn->GetActorLocation();
	const double SeaUU = static_cast<double>(World->SeaLevelMeters) * 100.0;
	const double LandMarginUU = 500.0; // 5 m above sea = solid land

	FVector Target(Loc.X, Loc.Y, FMath::Max(World->SurfaceWorldZAt(Loc.X, Loc.Y), SeaUU) + 200.0);
	bool bFoundLand = false;
	const double StepUU = 8000.0;   // ~80 m sampling
	const double MaxRUU = 150000.0; // search ~1.5 km (inside the stream radius)
	for (double r = 0.0; r <= MaxRUU && !bFoundLand; r += StepUU)
	{
		const int NumPts = (r < 1.0) ? 1 : FMath::Max(8, FMath::RoundToInt((2.0 * PI * r) / StepUU));
		for (int k = 0; k < NumPts; ++k)
		{
			const double ang = (2.0 * PI * static_cast<double>(k)) / static_cast<double>(NumPts);
			const double x = Loc.X + r * FMath::Cos(ang);
			const double y = Loc.Y + r * FMath::Sin(ang);
			const double s = static_cast<double>(World->SurfaceWorldZAt(x, y));
			if (s > SeaUU + LandMarginUU)
			{
				Target = FVector(x, y, s + 200.0);
				bFoundLand = true;
				break;
			}
		}
	}
	Pawn->SetActorLocation(Target, false, nullptr, ETeleportType::TeleportPhysics);
	UE_LOG(LogMiraTdiffHook, Display,
		TEXT("[Tdiff] player spawned %s at (%.0f,%.0f,%.0f) UU (was Z %.0f, sea %.0f)."),
		bFoundLand ? TEXT("ON LAND") : TEXT("at sea (no land within 1.5km)"),
		Target.X, Target.Y, Target.Z, Loc.Z, SeaUU);
}

// ---------------------------------------------------------------------------
// PIE console command: MiraThal.Tdiff.FillRegion [Seed] [HalfExtentVoxels]
// Finds the first AVoxelWorld in the current world and fills a centred region. Triggerable
// live over the mcp-unreal bridge (run_console_command).
// ---------------------------------------------------------------------------
static void TdiffFillRegionConsole(const TArray<FString>& Args, UWorld* World)
{
	if (!World)
	{
		UE_LOG(LogMiraTdiffHook, Warning, TEXT("[Tdiff] console: no UWorld context."));
		return;
	}

	// Parse optional args (defaults: seed 1337, half-extent 16384 voxels ≈ ±1.6 km).
	int64 Seed = 1337;
	int32 HalfExtent = 16384;
	if (Args.Num() >= 1) { Seed = FCString::Atoi64(*Args[0]); }
	if (Args.Num() >= 2) { HalfExtent = FCString::Atoi(*Args[1]); }

	// Find the first voxel world actor in the level.
	AVoxelWorld* VoxelWorld = nullptr;
	for (TActorIterator<AVoxelWorld> It(World); It; ++It)
	{
		VoxelWorld = *It;
		break;
	}
	if (!VoxelWorld)
	{
		UE_LOG(LogMiraTdiffHook, Warning,
			TEXT("[Tdiff] console: no AVoxelWorld found in the current level."));
		return;
	}

	UTdiffWorldHook::FillCenteredRegion(VoxelWorld, Seed, HalfExtent, /*bRegenerate=*/true);
}

static FAutoConsoleCommandWithWorldAndArgs GTdiffFillRegionCmd(
	TEXT("MiraThal.Tdiff.FillRegion"),
	TEXT("Run the diffusion model (GPU if ONNX present, else analytic stub) to build a DEM "
	     "and install it on the level's AVoxelWorld. "
	     "Usage: MiraThal.Tdiff.FillRegion [Seed] [HalfExtentVoxels]"),
	FConsoleCommandWithWorldAndArgsDelegate::CreateStatic(&TdiffFillRegionConsole));
