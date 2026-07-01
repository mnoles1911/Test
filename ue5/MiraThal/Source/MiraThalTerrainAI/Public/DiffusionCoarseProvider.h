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
#include "Core/Tdiff/Erosion.h"         // mira::tdiff::ErosionParams / erode() (Phase 3 weathering)

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

		// How many world voxels one model COARSE CELL spans. The InfiniteTiler requests 64x64
		// tiles and the pipeline returns the coarse-net's 64 cells, whose NATIVE footprint is
		// decoder_tile_size/coarse_tile = 512/64 = 8 native px = 8 * 30 m = 240 m each = 2400
		// voxels at 10 vox/m. (Using 300 — one native 30 m px per cell — ran the model 8x
		// zoomed-in, packing ~15 km of the model's intrinsic relief into ~2 km => near-vertical
		// cliffs. 2400 spreads that same relief over its intended distance => gentle rolling
		// terrain, and fewer inferences per tile.) Also the world->model scale for the conditioning.
		int32 ModelPixelVoxels = 2400;

		// InfiniteTiler geometry (defaults match the coarse stage: 64 tile, 48 stride, 16 overlap).
		int32 TileSize   = 64;
		int32 TileStride = 48;

		// The frozen pipeline constants (means/stds/steps). Defaults are the shipping config.
		mira::tdiff::WorldPipelineConfig Pipeline;

		// ----- PHASE 3: deterministic EROSION of the coarse DEM -----------------------------
		// After the diffusion net paints absolute-metre elevations, optionally weather the grid
		// so it grows real drainage: droplet (hydraulic) erosion carves river valleys + branching
		// channels, thermal (talus) erosion slumps over-steep cliffs into believable slopes. This
		// is ADDITIVE and fully toggleable - set bErode=false to get the raw AI surface back.
		bool bErode = true;

		// Erosion knobs. See DefaultErosionParams() below for the retune reasoning: the Core
		// defaults are tuned for a fine ~1 m/voxel grid, but OUR grid is ABSOLUTE METRES at
		// ~30 m per coarse cell, so those defaults are wrong here and must be scaled up/softened.
		mira::tdiff::ErosionParams Erosion = DefaultErosionParams();

		// Build the ErosionParams retuned for THIS grid (metres of elevation, ~30 m/cell spacing).
		//
		// WHY the Core defaults are wrong here:
		//   * Erosion.h's grid is documented as "heights in VOXELS" at 1 unit = 1 cell = ~1 m, so
		//     its thermalTalus=4 means "a 4-voxel (=0.4 m) step is the steepest stable slope". On
		//     OUR grid one cell is ~30 m wide and holds ABSOLUTE METRES, so "4" would mean a
		//     ludicrously flat 4 m rise across 30 m and would flatten every mountain.
		//   * We therefore express the talus as METRES of stable rise across one 30 m cell. A
		//     slope of ~25-35 deg is a believable natural talus/scree limit; tan(27 deg)*30 m ~= 15 m,
		//     so thermalTalus = 15.0 m. Slopes steeper than that slump; gentler AI hills are untouched.
		//
		// Everything below is deliberately GENTLE - this is MACRO terrain and the goal is subtle
		// drainage + ridge definition, NOT to obliterate the AI's continent shapes into a moonscape.
		// The designer can retune any field live via Config.Erosion.
		static mira::tdiff::ErosionParams DefaultErosionParams()
		{
			mira::tdiff::ErosionParams P; // start from Core defaults (fine-grid tuned)

			// --- HYDRAULIC (rain droplets carve valleys) ---
			// Keep the droplet budget modest: ~1 droplet per 5 cells is enough to etch clear
			// channels on a coarse grid without churning the whole surface (or costing much time).
			P.dropletsPerCell        = 0.2f;
			// A coarse cell is ~30 m, so a droplet needs a decent lifetime to travel across several
			// cells and connect a valley; 48 steps ~= a couple of km of run.
			P.maxDropletLifetime     = 48;
			// Soften how hard each droplet digs/dumps so metre-scale deltas don't gouge deep trenches.
			// (Capacity ~ deltaHeight, and deltaHeight is now in metres, so the raw numbers are large;
			// halving the capacity factor and lowering the rates keeps cuts shallow and believable.)
			P.sedimentCapacityFactor = 2.0f;
			P.erosionRate            = 0.15f;
			P.depositionRate         = 0.20f;
			// A wider brush spreads each cut over ~2 cells so valleys get smooth banks, not 1-cell spikes.
			P.erosionRadius          = 2;
			// Slightly quicker evaporation settles silt out before droplets wander the whole map.
			P.evaporation            = 0.02f;
			// inertia / gravity / initialWater / initialSpeed: Core defaults are fine.

			// --- THERMAL (talus slumping of over-steep cliffs) ---
			// 15 m of rise across one 30 m cell ~= a 27 deg slope: the steepest STABLE macro slope.
			// Anything steeper crumbles toward it; gentler AI terrain is left alone.
			P.thermalTalus      = 15.0f;
			// Just a few relaxation passes - enough to knock the sharpest AI edges into ridges/scree,
			// not so many that mountains melt flat. (Core default is 8; we go gentler at macro scale.)
			P.thermalIterations = 4;
			// Move half the excess per pass: stable + converges without overshoot (Core default).
			P.thermalStrength   = 0.5f;

			return P;
		}
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
	                               int32 ModelPixelVoxels = 2400);

private:
	FConfig Config;

	TUniquePtr<mira::tdiff::FNNEUNetRunner>     Runner;  // the GPU runner (owns ONNX models)
	TUniquePtr<mira::tdiff::FTdiffRunnerAdapter> Adapter; // wraps Runner as a pure IUNetRunner
	TUniquePtr<mira::tdiff::SyntheticMapStats>  Stats;   // loaded conditioning stats (or null)
	bool bStatsValid = false;
};
