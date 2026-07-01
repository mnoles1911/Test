// DiffusionCoarseProvider.cpp - implementation of the GPU-backed coarse-DEM provider.
// See DiffusionCoarseProvider.h for the full design + the one-line post-Gate-3 wiring note.

#include "DiffusionCoarseProvider.h"

#include "Core/Tdiff/InfiniteTiler.h"   // mira::tdiff::InfiniteTiler (multi-tile blend)
#include "Core/Tdiff/SyntheticMap.h"    // mira::tdiff::SyntheticMap / SyntheticMapStats / loader
#include "Containers/StringConv.h"      // TCHAR_TO_UTF8
#include "Logging/LogMacros.h"

#include <vector>
#include <string>

DEFINE_LOG_CATEGORY_STATIC(LogMiraCoarseProvider, Log, All);

namespace
{
	// =====================================================================================
	// A WorldPipeline subclass whose ONLY change is to feed the coarse net REAL geographic
	// conditioning from a SyntheticMap (the spine's sampleCoarseConditioning() seam) instead
	// of the default zeros. Everything else - the denoise control flow - is the validated base.
	//
	// World-positioning: each tile constructs one of these with its world origin (in model
	// pixels). WorldPipeline re-centres its own noise at local (0,0), but it passes the
	// conditioning request through here, so we add the tile origin to make the conditioning a
	// continuous function of world coordinate across tile seams.
	//
	// *** SEAM (documented): conditioning coordinate scale. *** We sample the SyntheticMap at
	// integer MODEL-PIXEL coordinates (1 unit = one coarse cell). The reference pipeline samples
	// its Perlin field in its own coarse-tile units; the exact frequency/coordinate match is part
	// of the world-positioned-conditioning parity that Gate 3 validates separately. The plumbing
	// (real stats -> SyntheticMap -> the 5 conditioning channels in the right order) is what this
	// class delivers; if the scale needs tuning it changes ONLY here.
	// =====================================================================================
	class FSyntheticConditionedPipeline final : public mira::tdiff::WorldPipeline
	{
	public:
		FSyntheticConditionedPipeline(const mira::tdiff::WorldPipelineConfig& InCfg,
		                              const mira::tdiff::SyntheticMap* InSynth,
		                              int InWorldRow0, int InWorldCol0)
			: mira::tdiff::WorldPipeline(InCfg)
			, Synth(InSynth)
			, WorldRow0(InWorldRow0)
			, WorldCol0(InWorldCol0)
		{}

	protected:
		// Fill a flat (5, h, w) row-major channel-major conditioning buffer for the requested
		// local window [i1,i2) rows x [j1,j2) cols. The 5 SyntheticMap channels (elev, temp,
		// temp_std, precip, precip_std) map 1:1 onto the 5 conditioning channels the spine then
		// normalises by coarse_means/stds[[0,2,3,4,5]] (confirmed in SyntheticMap.h's header).
		void sampleCoarseConditioning(int i1, int j1, int /*i2*/, int /*j2*/,
		                              int h, int w, std::vector<float>& out5) const override
		{
			out5.assign(static_cast<size_t>(5) * h * w, 0.0f);
			if (Synth == nullptr)
			{
				return; // no stats loaded -> zeros (base WorldPipeline behaviour).
			}

			// SampleFull(i1,j1,i2,j2): out[ch][k] with k = row*W + col, sampled at
			// (x = i1 + col, y = j1 + row). So pass the X-axis (varies with COLUMN) first and
			// the Y-axis (varies with ROW) second. Our row==world-Z, col==world-X.
			const int WorldColStart = WorldCol0 + j1; // X start
			const int WorldRowStart = WorldRow0 + i1; // Z start

			std::array<std::vector<float>, 5> Synthetic;
			Synth->SampleFull(WorldColStart, WorldRowStart,
			                  WorldColStart + w, WorldRowStart + h, Synthetic);

			// Synthetic[ch] is already row-major (row*w + col), length w*h -> copy straight into
			// the matching channel block of out5.
			const size_t N = static_cast<size_t>(h) * static_cast<size_t>(w);
			for (int c = 0; c < 5; ++c)
			{
				const size_t Copy = (Synthetic[c].size() < N) ? Synthetic[c].size() : N;
				for (size_t k = 0; k < Copy; ++k)
				{
					out5[static_cast<size_t>(c) * N + k] = Synthetic[c][k];
				}
			}
		}

	private:
		const mira::tdiff::SyntheticMap* Synth;
		int WorldRow0; // tile world origin, model-pixel rows (world +Z)
		int WorldCol0; // tile world origin, model-pixel cols (world +X)
	};
} // anonymous namespace

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------
FDiffusionCoarseProvider::FDiffusionCoarseProvider(const FConfig& InConfig)
	: Config(InConfig)
{
	// The GPU runner + the engine<->pure adapter. Models load lazily on first Run().
	Runner  = MakeUnique<mira::tdiff::FNNEUNetRunner>(Config.OnnxDir);
	Adapter = MakeUnique<mira::tdiff::FTdiffRunnerAdapter>(*Runner);

	// Load the SyntheticMap conditioning stats, if a path was given. Failure is non-fatal:
	// we simply run with zero conditioning (same as the spine's default stub).
	if (!Config.SyntheticStatsPath.IsEmpty())
	{
		Stats = MakeUnique<mira::tdiff::SyntheticMapStats>();
		const std::string PathUtf8(TCHAR_TO_UTF8(*Config.SyntheticStatsPath));
		bStatsValid = mira::tdiff::LoadSyntheticMapStats(PathUtf8, *Stats);
		if (!bStatsValid)
		{
			UE_LOG(LogMiraCoarseProvider, Warning,
				TEXT("[Tdiff] could not load synthetic_map_stats from '%s' - running with ZERO "
				     "coarse conditioning."), *Config.SyntheticStatsPath);
			Stats.Reset();
		}
		else
		{
			UE_LOG(LogMiraCoarseProvider, Display,
				TEXT("[Tdiff] SyntheticMap conditioning ACTIVE (stats '%s')."),
				*Config.SyntheticStatsPath);
		}
	}
	else
	{
		UE_LOG(LogMiraCoarseProvider, Display,
			TEXT("[Tdiff] no synthetic stats path - coarse conditioning is ZERO (stub parity)."));
	}
}

FDiffusionCoarseProvider::~FDiffusionCoarseProvider() = default;

// ---------------------------------------------------------------------------
// The work: region -> real coarse DEM.
//
// *** ASYNC SEAM ***: this whole method runs synchronously and issues ~23 GPU calls PER TILE.
// When the async wrapper lands, THIS call moves onto a background task (the runner's RunSync is
// the only game-thread-sensitive bit - construct/use the runner on the worker), and
// FDiffusionDemService::TryGetRegionHeightmap resolves the FCoarseDemProvider once the result
// is ready. The provider state touched per call (Adapter->bRunFailed, the per-seed SyntheticMap)
// must then be made per-task / locked - today it is single-threaded by contract.
// ---------------------------------------------------------------------------
bool FDiffusionCoarseProvider::Fill(int64 Seed, const FIntRect& RegionInVoxels, FCoarseDem& Out)
{
	const int32 WidthVox  = RegionInVoxels.Max.X - RegionInVoxels.Min.X;
	const int32 HeightVox = RegionInVoxels.Max.Y - RegionInVoxels.Min.Y;
	if (WidthVox <= 0 || HeightVox <= 0)
	{
		return false; // degenerate region
	}
	if (!Runner.IsValid() || !Adapter.IsValid())
	{
		return false;
	}

	// --- 1) Model-pixel origin of the region (world-positioned conditioning). -------------
	// Integer floor division (handles negative world coords; exact for large voxel coordinates
	// where a float cast would lose precision beyond 2^24).
	const int32 Cell = FMath::Max(1, Config.ModelPixelVoxels);
	auto FloorDivI = [](int32 a, int32 b) -> int32
	{
		int32 q = a / b, r = a % b;
		if (r != 0 && ((r < 0) != (b < 0))) { --q; }
		return q;
	};
	const int32 ColOrigin = FloorDivI(RegionInVoxels.Min.X, Cell); // X
	const int32 RowOrigin = FloorDivI(RegionInVoxels.Min.Y, Cell); // Z

	// --- 2) Build the per-seed SyntheticMap (cheap: just configures 5 noise generators). --
	TUniquePtr<mira::tdiff::SyntheticMap> Synth;
	if (bStatsValid && Stats.IsValid())
	{
		Synth = MakeUnique<mira::tdiff::SyntheticMap>(*Stats, static_cast<int64_t>(Seed));
	}
	const mira::tdiff::SyntheticMap* SynthPtr = Synth.Get();

	// --- 3) PHASE 2: tile + seam-blend the region at native model resolution. -------------
	//
	// Now that base/decoder are re-exported with DYNAMIC spatial axes (verified base@24/decoder@192
	// run on DirectML) AND WorldPipeline::get() snaps its latent tile to a multiple of 8 (the base
	// UNet's downsample factor; base@20 errored, @24 is fine), the multi-tile get() path works. We
	// lay overlapping TileSize tiles (stride TileStride) across the region and InfiniteTiler::blend
	// feathers the seams -> a seamless coarse DEM at NATIVE 30 m/px (no single-tile stretch). This
	// is the seamless/infinite-capable path (Phase 1's single 512-tile stretch is retired).
	const int32 Cols = FMath::Max(2, WidthVox  / Cell + 1); // world +X model-px
	const int32 Rows = FMath::Max(2, HeightVox / Cell + 1); // world +Z model-px

	mira::tdiff::InfiniteTiler Tiler(Config.TileSize, Config.TileStride, /*offset=*/0, Config.Pipeline);

	mira::tdiff::FTdiffRunnerAdapter& Ad = *Adapter;
	Ad.bRunFailed = false; // latch reset; checked after the blend

	const mira::tdiff::WorldPipelineConfig PipelineCfg = Config.Pipeline;

	// Per-tile generator: a SyntheticMap-conditioned pipeline at this tile's WORLD model-pixel
	// origin (RowOrigin+ry0, ColOrigin+rx0), running the full coarse->base->decoder chain.
	//
	// WORLD-CONTINUOUS NOISE (2026-06-29): we now pass the SAME global seed `s` to EVERY tile
	// (NOT a per-tile reseed) AND hand WorldPipeline::get() the tile's world origin. get()
	// positions each stage's gaussian noise at that world coordinate, so the noise is ONE
	// continuous, world-keyed field: overlapping tiles read the SAME noise in their shared
	// pixels and InfiniteTiler::blend feathers MATCHING data (instead of two unrelated fields).
	// The conditioning is still world-positioned by FSyntheticConditionedPipeline as before.
	// (Previously each tile drew identical LOCAL-origin noise under a per-tile tileSeed -> seams
	// could not align and the same world point depended on region size.)
	auto Gen = [&](uint64_t s, int /*ty*/, int /*tx*/, int ry0, int rx0, int sz,
	               std::vector<float>& OutTile)
	{
		FSyntheticConditionedPipeline Wp(PipelineCfg, SynthPtr, RowOrigin + ry0, ColOrigin + rx0);
		mira::tdiff::ElevTile Et = Wp.get(s, 0, 0, sz, sz, Ad,
		                                  /*worldOriginI=*/RowOrigin + ry0,
		                                  /*worldOriginJ=*/ColOrigin + rx0);
		OutTile = std::move(Et.elev);
	};

	// blend() returns a row-major (Rows x Cols) elevation buffer in metres, index = row*Cols+col.
	std::vector<float> Elev = Tiler.blend(static_cast<uint64_t>(Seed),
	                                      RowOrigin, ColOrigin,
	                                      RowOrigin + Rows, ColOrigin + Cols, Gen);

	if (Ad.bRunFailed)
	{
		UE_LOG(LogMiraCoarseProvider, Warning,
			TEXT("[Tdiff] inference FAILED while filling region [%d,%d]..[%d,%d] (seed %lld) - "
			     "a UNet run failed (see LogMiraTerrainNNE above). Rejecting region."),
			RegionInVoxels.Min.X, RegionInVoxels.Min.Y,
			RegionInVoxels.Max.X, RegionInVoxels.Max.Y,
			static_cast<long long>(Seed));
		return false;
	}

	if (static_cast<int32>(Elev.size()) != Rows * Cols || Elev.empty())
	{
		UE_LOG(LogMiraCoarseProvider, Warning,
			TEXT("[Tdiff] unexpected blended size %d (wanted %dx%d) - rejecting region."),
			static_cast<int32>(Elev.size()), Cols, Rows);
		return false;
	}

	// --- 3b) PHASE 3: deterministic EROSION of the blended coarse DEM. --------------------
	// The AI net paints plausible large-scale landmasses but has no hydrology - no carved river
	// valleys, no branching drainage, no talus-limited ridgelines. We add that here by running the
	// Core erosion pipeline (mira::tdiff::erode) directly on the ABSOLUTE-METRE `Elev` grid, in
	// place, BEFORE it is copied into Out.Cells. It is keyed on `Seed`, and the Core module's ONLY
	// randomness is the portable PCG64 droplet stream, so this is fully DETERMINISTIC per seed -
	// the same region+seed erodes byte-identically on every machine (multiplayer-safe).
	//
	// UNITS: `Elev` is metres of absolute elevation at ~30 m per cell; the Config.Erosion params
	// are retuned for exactly that (see FConfig::DefaultErosionParams in the header - talus in
	// metres-per-30m-cell, gentle rates so we get subtle drainage, not a moonscape).
	//
	// *** SEAMLESSNESS (documented, NOT solved here) ***: this erosion pass runs per-REGION on the
	// grid we just blended, and droplets RETIRE at the grid border (Erosion.h clamps every read to
	// the edge and never flows across it). So erosion is not perfectly seamless across independent
	// streaming-tile regions - a river carved to the edge of one tile won't be guaranteed to line up
	// pixel-for-pixel with its neighbour. This is MITIGATED because the Phase-2 streaming path
	// generates each tile with a large (~1200-voxel) APRON of overlap, so the elevation fed here
	// already carries cross-tile context and droplets see the neighbour's terrain within the apron.
	// A fully world-positioned erosion pass (one continuous droplet field keyed to world coords,
	// like the world-continuous noise) is a future refinement; we intentionally do NOT attempt it now.
	if (Config.bErode)
	{
		// Capture the pre-erosion range so the log shows the effect at a glance.
		float PreLo = Elev[0], PreHi = Elev[0];
		for (float V : Elev) { PreLo = FMath::Min(PreLo, V); PreHi = FMath::Max(PreHi, V); }

		mira::tdiff::erode(Elev.data(), Cols, Rows, Config.Erosion, static_cast<uint64_t>(Seed));

		float PostLo = Elev[0], PostHi = Elev[0];
		for (float V : Elev) { PostLo = FMath::Min(PostLo, V); PostHi = FMath::Max(PostHi, V); }

		UE_LOG(LogMiraCoarseProvider, Display,
			TEXT("[Tdiff] erosion applied (seed %lld): elev %.1f..%.1f m -> %.1f..%.1f m "
			     "(droplets/cell %.2f, talus %.1f m, thermal x%d)."),
			static_cast<long long>(Seed), PreLo, PreHi, PostLo, PostHi,
			Config.Erosion.dropletsPerCell, Config.Erosion.thermalTalus,
			Config.Erosion.thermalIterations);
	}

	// --- 4) Store ABSOLUTE elevation in METRES into FCoarseDem (z-major, row*Cols+col). ----
	// *** VERTICAL ANCHORING (2026-06-29 fix) ***: we deliberately do NOT normalise the region
	// to [0,1] any more. Normalising threw away absolute altitude, so the service mapped 0 m
	// (true sea level) to ~72% up the world's height band -> the whole AI surface floated ~375 m
	// ABOVE the player's sea-level spawn ("a crust above the player's head"). Instead we hand the
	// service real metres; it maps them to voxel-Y anchored at the world's SEA LEVEL
	// (voxelY = seaLevelVox + metres * 10), so AI 0 m == world sea and the player spawns ON the
	// surface. The service's vertical mapping is set accordingly in TdiffWorldHook::FillRegion.
	float Lo = Elev[0], Hi = Elev[0]; // for the log line only
	for (float V : Elev)
	{
		Lo = FMath::Min(Lo, V);
		Hi = FMath::Max(Hi, V);
	}

	Out.CoarseW = Cols;
	Out.CoarseH = Rows;
	Out.Cells.SetNumUninitialized(Rows * Cols);
	for (int32 i = 0; i < Rows * Cols; ++i)
	{
		Out.Cells[i] = Elev[static_cast<size_t>(i)]; // absolute metres
	}

	const int32 TileCount = Tiler.tile_count(RowOrigin, ColOrigin, RowOrigin + Rows, ColOrigin + Cols);
	UE_LOG(LogMiraCoarseProvider, Display,
		TEXT("[Tdiff] coarse DEM generated: %dx%d cells (%d blended tiles), elev %.1f..%.1f m, "
		     "region [%d,%d]..[%d,%d], seed %lld, conditioning=%s."),
		Cols, Rows, TileCount, Lo, Hi,
		RegionInVoxels.Min.X, RegionInVoxels.Min.Y,
		RegionInVoxels.Max.X, RegionInVoxels.Max.Y, static_cast<long long>(Seed),
		(SynthPtr ? TEXT("synthetic") : TEXT("zero")));
	return true;
}

// ---------------------------------------------------------------------------
// Factories - wrap a shared instance in an FCoarseDemProvider callable.
// ---------------------------------------------------------------------------
FCoarseDemProvider FDiffusionCoarseProvider::Make(const FConfig& InConfig)
{
	TSharedRef<FDiffusionCoarseProvider> Provider = MakeShared<FDiffusionCoarseProvider>(InConfig);
	return [Provider](int64 Seed, const FIntRect& RegionInVoxels, FCoarseDem& Out) -> bool
	{
		return Provider->Fill(Seed, RegionInVoxels, Out);
	};
}

FCoarseDemProvider FDiffusionCoarseProvider::Make(const FString& OnnxDir,
                                                  const FString& SyntheticStatsPath,
                                                  int32 ModelPixelVoxels)
{
	FConfig Cfg;
	Cfg.OnnxDir            = OnnxDir;
	Cfg.SyntheticStatsPath = SyntheticStatsPath;
	Cfg.ModelPixelVoxels   = ModelPixelVoxels;
	return Make(Cfg);
}
