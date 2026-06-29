// TdiffNewGame.cpp — the player-facing "new game" entry for the AI terrain.
//
// WHAT THIS IS (plain English):
// This is the original vision's "Start a fresh world" button, expressed as a console
// command. You type:
//
//     MiraThal.NewGame [Seed]
//
// and it builds a brand-new procedurally-generated AI world centred on the player and
// drops the player onto it. If you give a Seed, the world is reproducible (same seed =>
// same world). If you OMIT the Seed, we pick a RANDOM one (and log it loudly) so you can
// note it down and come back to the same world later.
//
// HOW IT WORKS:
// It finds the level's AVoxelWorld and calls the existing, already-tested hook
// UTdiffWorldHook::FillCenteredRegion(World, Seed, HalfExtent, /*bRegenerate=*/true).
// That one call does everything: run the diffusion model -> install the DEM -> rebuild
// the terrain -> snap the player onto dry land. We deliberately do NOT duplicate any of
// that logic here; this file is purely the "new game" front door and a good default
// world size. It does not touch TdiffWorldHook.cpp/.h at all — it only CALLS its API.
//
// WHY A SEPARATE FILE: keeping this in its own .cpp means the world-hook stays untouched.
// It's a plain .cpp inside an existing module's Private/ folder, so Unreal's source globbing
// picks it up automatically — NO MiraThalTerrainAI.Build.cs change is needed.

#include "TdiffWorldHook.h"          // the API we call: UTdiffWorldHook::FillCenteredRegion

#include "VoxelWorld.h"              // AVoxelWorld — the actor we install the world onto
#include "EngineUtils.h"            // TActorIterator — find the AVoxelWorld in the level
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"     // FAutoConsoleCommandWithWorldAndArgs
#include "HAL/PlatformTime.h"        // FPlatformTime::Cycles64 — entropy for a random seed
#include "Misc/DateTime.h"           // FDateTime::Now — more entropy for a random seed
#include "Logging/LogMacros.h"

DEFINE_LOG_CATEGORY_STATIC(LogMiraNewGame, Log, All);

// A good default world half-extent in voxels. At 10 voxels/metre, 30000 voxels ≈ ±3 km
// each way from origin (a ~6 km square playfield) — a generous "fresh world" footprint.
static constexpr int32 GNewGameHalfExtentVoxels = 30000;

// ---------------------------------------------------------------------------
// Pick a RANDOM, runtime-only seed. This is NOT on the deterministic generation path —
// it's just the "surprise me" dice roll for a new game. We mix the high-resolution CPU
// cycle counter with the wall-clock ticks so two new-games in the same second still differ,
// then fold it into the positive int32 range so it reads cleanly in logs and re-types easily.
// ---------------------------------------------------------------------------
static int64 PickRandomSeed()
{
	const uint64 Cycles = FPlatformTime::Cycles64();
	const uint64 Ticks  = static_cast<uint64>(FDateTime::Now().GetTicks());
	uint64 Mixed = Cycles ^ (Ticks * 0x9E3779B97F4A7C15ULL); // golden-ratio mix for spread

	// Keep it in [1 .. INT32_MAX] so the seed is a small, human-friendly, re-typable number.
	const int64 Seed = static_cast<int64>(Mixed % 2147483647ULL) + 1;
	return Seed;
}

// ---------------------------------------------------------------------------
// Console command: MiraThal.NewGame [Seed]
// Starts a fresh AI world. Seed optional (random if omitted). Fire it from the in-game
// console or live over the mcp-unreal bridge (run_console_command).
// ---------------------------------------------------------------------------
static void TdiffNewGameConsole(const TArray<FString>& Args, UWorld* World)
{
	if (!World)
	{
		UE_LOG(LogMiraNewGame, Warning, TEXT("[NewGame] no UWorld context — run this in PIE/game."));
		return;
	}

	// Seed: use the supplied one if given, otherwise roll a random one.
	int64 Seed;
	bool bRandom = false;
	if (Args.Num() >= 1 && !Args[0].IsEmpty())
	{
		Seed = FCString::Atoi64(*Args[0]);
	}
	else
	{
		Seed = PickRandomSeed();
		bRandom = true;
	}

	// Find the first voxel world actor in the level (same discovery the FillRegion command uses).
	AVoxelWorld* VoxelWorld = nullptr;
	for (TActorIterator<AVoxelWorld> It(World); It; ++It)
	{
		VoxelWorld = *It;
		break;
	}
	if (!VoxelWorld)
	{
		UE_LOG(LogMiraNewGame, Warning,
			TEXT("[NewGame] no AVoxelWorld found in the current level — cannot start a world."));
		return;
	}

	// Log the chosen seed LOUDLY before we build, so it's captured even if generation hitches.
	// This is the reproducibility record: note this number to revisit the same world.
	UE_LOG(LogMiraNewGame, Display,
		TEXT("=================================================================="));
	UE_LOG(LogMiraNewGame, Display,
		TEXT("[NewGame] Starting a fresh AI world.  SEED = %lld  (%s)"),
		static_cast<long long>(Seed), bRandom ? TEXT("RANDOM") : TEXT("chosen"));
	UE_LOG(LogMiraNewGame, Display,
		TEXT("[NewGame] half-extent = %d voxels (~%d km square). Re-run with this seed to get "
		     "the SAME world."),
		GNewGameHalfExtentVoxels, (GNewGameHalfExtentVoxels * 2) / 10000);
	UE_LOG(LogMiraNewGame, Display,
		TEXT("=================================================================="));

	// One call does it all: generate -> install -> rebuild -> snap player onto land.
	const bool bOk = UTdiffWorldHook::FillCenteredRegion(
		VoxelWorld, Seed, GNewGameHalfExtentVoxels, /*bRegenerate=*/true);

	if (bOk)
	{
		UE_LOG(LogMiraNewGame, Display,
			TEXT("[NewGame] World ready. SEED = %lld. Welcome to Mira-Thal."),
			static_cast<long long>(Seed));
	}
	else
	{
		UE_LOG(LogMiraNewGame, Warning,
			TEXT("[NewGame] FillCenteredRegion failed for seed %lld (see [Tdiff] log above)."),
			static_cast<long long>(Seed));
	}
}

static FAutoConsoleCommandWithWorldAndArgs GTdiffNewGameCmd(
	TEXT("MiraThal.NewGame"),
	TEXT("Start a FRESH procedurally-generated AI world centred on the player and drop the "
	     "player onto it. Usage: MiraThal.NewGame [Seed]  — Seed optional (RANDOM if omitted; "
	     "the chosen seed is logged so you can reproduce the world)."),
	FConsoleCommandWithWorldAndArgsDelegate::CreateStatic(&TdiffNewGameConsole));
