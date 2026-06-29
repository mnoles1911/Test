// DiffusionCoarseProvider.h - the REAL, GPU-backed coarse-DEM provider.
//
// PLAIN ENGLISH (for the designer):
// FDiffusionDemService (DiffusionDemService.h) is the plumbing that turns a "coarse DEM"
// (one ground-height number every ~30 m for a region) into the voxel world. In Phase 1 it
// was fed a STUB coarse DEM (a few sinusoids). THIS file is the thing that replaces the stub
// with the actual AI: it owns the GPU neural-net runner and runs the ported terrain-diffusion
// orchestration to PAINT a real coarse elevation grid for the requested region.
//
// THE WHOLE CHAIN, end to end:
//   FDiffusionDemService  -- asks for a coarse grid ->
//     FDiffusionCoarseProvider::Fill(seed, region)   (this class)
//       -> SyntheticMap      : cheap deterministic geography (elev/temp/precip) = CONDITIONING
//       -> InfiniteTiler     : lays overlapping tiles over the region, blends seams
//            -> WorldPipeline: per tile, runs Coarse->Base->Decoder denoise = the real net
//                 -> FTdiffRunnerAdapter -> FNNEUNetRunner -> NNE + DirectML on the GPU
//       -> normalises the blended elevation to [0,1] -> FCoarseDem
//
// WHAT EACH OWNED PIECE IS:
//   * FNNEUNetRunner     - the working GPU runner (Gate 1 PASSED with it).
//   * FTdiffRunnerAdapter- translates the engine runner into the pure-C++ IUNetRunner the
//                          Core WorldPipeline calls (see TdiffRunnerAdapter.h).
//   * SyntheticMapStats  - loaded once from synthetic_map_stats.json; drives SyntheticMap.
//                          If the stats file is absent, conditioning falls back to ZEROS
//                          (exactly WorldPipeline's default stub) and we still produce a DEM.
//
// ============================================================================================
// *** POST-GATE-3 WIRING (the parent flips this ONE line; do NOT edit DiffusionDemService) ***
//
// Today DiffusionDemService's constructor defaults to the analytic stub:
//     Provider = MakeAnalyticStubProvider();                                 // (current)
//
// Once WorldPipeline parity is signed off (Gate 3), make the live AI the default by swapping
// that for the line below (e.g. in FDiffusionDemService::FDiffusionDemService, or - cleaner -
// at the service's construction site so the ONNX/stats paths come from config):
//
//     Provider = FDiffusionCoarseProvider::Make(
//                    /*OnnxDir=*/        TEXT("D:/terrain-diffusion/onnx"),
//                    /*SyntheticStats=*/ TEXT("D:/terrain-diffusion/synthetic_map_stats.json"));
//
// or, if a service instance already exists:  Service.SetProvider(FDiffusionCoarseProvider::Make(...));
// Nothing else changes - FDiffusionCoarseProvider::Make returns a plain FCoarseDemProvider.
// ============================================================================================
//
// LATENCY / ASYNC RISK (read this): one Fill() runs the FULL pipeline PER TILE, and each tile
// is ~23 synchronous GPU calls (20 coarse + 2 base + 1 decoder). A region of a few tiles is
// therefore many seconds on the game thread. Phase 1 is intentionally synchronous; the async
// boundary is FDiffusionDemService::TryGetRegionHeightmap (a future request-queue/worker sits
// behind it). See the note above Fill() for exactly where threading goes.
#pragma once

#include "CoreMinimal.h"
#include "Templates/UniquePtr.h"

#include "DiffusionDemService.h"        // FCoarseDem / FCoarseDemProvider (the contract we satisfy)
#include "NNEUNetRunner.h"              // mira::tdiff::FNNEUNetRunner (the GPU runner we own)
#include "TdiffRunnerAdapter.h"         // mira::tdiff::FTdiffRunnerAdapter (engine<->pure bridge)
#include "Core/Tdiff/WorldPipeline.h"   // mira::tdiff::WorldPipelineConfig (config we carry)

// Forward declaration keeps the heavy SyntheticMap.h (it pulls in FastNoiseLite) confined to
// the .cpp - the header only needs to NAME the stats struct for a TUniquePtr member.
namespace mira { namespace tdiff { struct SyntheticMapStats; } }

/**
 * FDiffusionCoarseProvider - owns the GPU runner + adapter and produces a real coarse DEM.
 *
 * Construct it once (heavy: it holds the runner that lazily loads the ONNX models), then call
 * Fill() per region - or, more usually, hand the whole thing to the DEM service via Make(),
 * which wraps a shared instance in an FCoarseDemProvider callable.
 *
 * Non-copyable / non-movable (owns TUniquePtr resources); always heap-own it (Make() does).
 */
class MIRATHALTERRAINAI_API FDiffusionCoarseProvider
{
public:
	// Tunables for one provider instance.
	struct FConfig
	{
		// Folder containing coarse_model.onnx / base_model.onnx / decoder_model.onnx.
		FString OnnxDir;

		// Absolute path to synthetic_map_stats.json. EMPTY -> zero conditioning (stub parity).
		FString SyntheticStatsPath;

		// How many world voxels one model full-resolution pixel spans. The shipping checkpoint
		// is "terrain-diffusion-30m": 30 m/pixel = 300 voxels at 10 vox/m. This sets the coarse
		// grid resolution (region voxels / this) and the world->model coordinate scale used to
		// position the SyntheticMap conditioning.
		int32 ModelPixelVoxels = 300;

		// InfiniteTiler geometry (defaults match the coarse stage: 64 tile, 48 stride, 16 overlap).
		int32 TileSize   = 64;
		int32 TileStride = 48;

		// The frozen pipeline constants (means/stds/steps). Defaults are the shipping config.
		mira::tdiff::WorldPipelineConfig Pipeline;
	};

	explicit FDiffusionCoarseProvider(const FConfig& InConfig);
	~FDiffusionCoarseProvider(); // out-of-line: SyntheticMapStats is incomplete in this header.

	FDiffusionCoarseProvider(const FDiffusionCoarseProvider&) = delete;
	FDiffusionCoarseProvider& operator=(const FDiffusionCoarseProvider&) = delete;

	// The work. Matches the FCoarseDemProvider signature exactly:
	//   given (seed, region in world VOXELS) fill Out with a normalised [0,1] coarse grid and
	//   return true; return false on a degenerate region or an inference failure.
	bool Fill(int64 Seed, const FIntRect& RegionInVoxels, FCoarseDem& Out);

	// True if the runner exists (construction always succeeds; the ONNX models load lazily on
	// the first Fill(), and a load/inference failure surfaces as Fill() returning false).
	bool IsReady() const { return Runner.IsValid(); }

	// Whether real (non-zero) SyntheticMap conditioning is active (stats loaded OK).
	bool HasConditioning() const { return bStatsValid; }

	// ----- Factories: wrap a shared instance in an FCoarseDemProvider callable. -----
	// The returned TFunction OWNS the provider (TSharedRef capture), so it lives exactly as
	// long as the service holds the provider.
	static FCoarseDemProvider Make(const FConfig& InConfig);
	static FCoarseDemProvider Make(const FString& OnnxDir,
	                               const FString& SyntheticStatsPath = FString(),
	                               int32 ModelPixelVoxels = 300);

private:
	FConfig Config;

	TUniquePtr<mira::tdiff::FNNEUNetRunner>     Runner;  // the GPU runner (owns ONNX models)
	TUniquePtr<mira::tdiff::FTdiffRunnerAdapter> Adapter; // wraps Runner as a pure IUNetRunner
	TUniquePtr<mira::tdiff::SyntheticMapStats>  Stats;   // loaded conditioning stats (or null)
	bool bStatsValid = false;
};
