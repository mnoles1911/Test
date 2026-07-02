// DiffusionCoarseProvider.cpp - implementation of the GPU-backed coarse-DEM provider.
// See DiffusionCoarseProvider.h for the full design + the one-line post-Gate-3 wiring note.

#include "DiffusionCoarseProvider.h"

#include "Core/Tdiff/InfiniteTiler.h"   // mira::tdiff::InfiniteTiler (multi-tile blend)
#include "Core/Tdiff/SyntheticMap.h"    // mira::tdiff::SyntheticMap / SyntheticMapStats / loader
#include "Containers/StringConv.h"      // TCHAR_TO_UTF8
#include "Logging/LogMacros.h"
#include "HAL/IConsoleManager.h"        // TAutoConsoleVariable (the MiraThal.Tdiff.PerfLog switch)
#include "HAL/PlatformTime.h"           // FPlatformTime::Seconds() (the per-tile stopwatch)

#include <vector>
#include <string>
#include <array>

DEFINE_LOG_CATEGORY_STATIC(LogMiraCoarseProvider, Log, All);

// =========================================================================================
// CONDITIONING COORD-SCALE (the terrain-shape root fix). The diffusion coarse net has 64 cells
// whose native footprint is decoder_tile_size/coarse_tile = 512/64 = 8 model-pixels each (~240 m).
// Our provider samples the SyntheticMap conditioning at 1 model-pixel (30 m) per cell — 8x too
// fine — so the coarse net sees 8x-too-high-frequency conditioning and emits ~8x too much relief
// per tile (the "7 km over 2 km" cliffs). We fix it by LOWERING the SyntheticMap frequency so the
// conditioning varies at its intended physical scale. Base multipliers are the reference's
// _prep_stats values [1.5,3,3,3,3]; CondScale (default 1/8) applies the coarse->decoder correction.
// Tunable live: set MiraThal.Tdiff.CondScale, then re-run MiraThal.Tdiff.Stream. Lower = gentler.
static const std::array<float, 5> GTdiffRefFreqMul = { 1.5f, 3.0f, 3.0f, 3.0f, 3.0f };
static TAutoConsoleVariable<float> CVarTdiffCondScale(
	TEXT("MiraThal.Tdiff.CondScale"),
	1.0f, // 1.0 now that ModelPixelVoxels=2400 places coarse cells at their native 240 m footprint,
	      // so the conditioning already samples at the right scale (freq = reference [1.5,3,3,3,3]).
	TEXT("AI conditioning frequency scale. 1.0 (default) matches the reference now that coarse cells "
	     "are at native 240 m; lower = gentler/larger features. Applied at the next MiraThal.Tdiff.Stream."),
	ECVF_Default);

// =========================================================================================
// PERFORMANCE LOGGING (added so we can SEE how fast the AI terrain actually runs on the GPU).
//
// Plain English: the runner already prints one "RunSync OK ... in X ms" line for each of the
// ~23 neural-net calls it makes, but nobody was adding those up. So we had no idea how long a
// WHOLE ~1.9 km tile takes, nor how that time splits between the GPU inference, the CPU erosion
// pass, and the final copy. The block below fixes that: it times the whole Fill() (and its
// cleanly-separated sub-stages) and prints a compact summary once per tile, plus a rolling
// average every few tiles so throughput (tiles/min) is visible at a glance.
//
// The verbose per-tile line is gated behind a console variable so it can be silenced live from
// the editor console; the rolling summary is cheap and always prints.
//   Console:  MiraThal.Tdiff.PerfLog 0   (silence the per-tile line)
//             MiraThal.Tdiff.PerfLog 1   (default - print it)
// =========================================================================================
static TAutoConsoleVariable<int32> CVarTdiffPerfLog(
	TEXT("MiraThal.Tdiff.PerfLog"),
	1, // default ON: the line is cheap (one string per multi-second tile) and very useful.
	TEXT("Log a per-tile [Tdiff][Perf] timing line (total ms + pipeline/erosion/store breakdown) ")
	TEXT("from FDiffusionCoarseProvider::Fill. 1 = on (default), 0 = off. The rolling average ")
	TEXT("summary is unaffected by this switch and always logs."),
	ECVF_Default);

// Rolling aggregate across successive tiles. This provider is serialized by the caller's
// ProviderLock (one Fill() at a time), so plain file-scope statics are safe here - no atomics
// needed. We keep a running tile COUNT and a running SUM of per-tile milliseconds, and every
// 8 tiles we emit an average + a tiles-per-minute throughput estimate.
static int64  GTdiffPerfTileCount = 0;   // how many tiles we have timed so far
static double GTdiffPerfSumMs     = 0.0; // summed wall-clock ms across those tiles

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
	// --- PERF: start the whole-tile stopwatch at the very top. ---------------------------
	// We only emit the timing line on the SUCCESS path (the early-return failure cases below
	// already print their own warning), so the degenerate-region returns cost nothing extra.
	const double FillStartSec = FPlatformTime::Seconds();

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
		// ROOT terrain-shape fix: scale the conditioning frequency by the coarse->decoder footprint
		// correction (CondScale, default 1/8) times the reference [1.5,3,3,3,3] multipliers, so the
		// coarse net sees conditioning at its intended ~240 m/cell scale instead of 8x too fine.
		const float CondScale = CVarTdiffCondScale.GetValueOnGameThread();
		const std::array<float, 5> FreqMul = {
			GTdiffRefFreqMul[0] * CondScale, GTdiffRefFreqMul[1] * CondScale,
			GTdiffRefFreqMul[2] * CondScale, GTdiffRefFreqMul[3] * CondScale,
			GTdiffRefFreqMul[4] * CondScale };
		Synth = MakeUnique<mira::tdiff::SyntheticMap>(*Stats, static_cast<int64_t>(Seed), FreqMul);
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
	// COHERENCE-CRITICAL UNIT CONVERSION. WorldPipeline::get() expects worldOriginI/J in the
	// model's NATIVE full-resolution pixels (the checkpoint is 30 m/px = 300 voxels), because that
	// is the grid its per-stage gaussian noise is world-positioned on. Our coarse-DEM cell is now
	// ModelPixelVoxels (2400 vox = 240 m = 8 native px), so a tile's coarse-cell origin must be
	// SCALED to native px before it becomes the noise world origin — otherwise adjacent tiles offset
	// their noise by only 1/8 of the real distance and the fields never line up (the "salami slices"
	// / flat slabs at different Z). The CONDITIONING (FSyntheticConditionedPipeline below) stays in
	// coarse-cell units on purpose (that is the intended gentler frequency). NativePxPerCell == 1
	// when ModelPixelVoxels==300, so this reduces to the original coherent behaviour.
	constexpr int32 kNativePixelVoxels = 300; // terrain-diffusion-30m native pixel = 30 m = 300 vox
	const int32 NativePxPerCell = FMath::Max(1, Cell / kNativePixelVoxels);
	auto Gen = [&](uint64_t s, int /*ty*/, int /*tx*/, int ry0, int rx0, int sz,
	               std::vector<float>& OutTile)
	{
		FSyntheticConditionedPipeline Wp(PipelineCfg, SynthPtr, RowOrigin + ry0, ColOrigin + rx0);
		mira::tdiff::ElevTile Et = Wp.get(s, 0, 0, sz, sz, Ad,
		                                  /*worldOriginI=*/(RowOrigin + ry0) * NativePxPerCell,
		                                  /*worldOriginJ=*/(ColOrigin + rx0) * NativePxPerCell);
		OutTile = std::move(Et.elev);
	};

	// --- PERF: bracket the PIPELINE stage. -----------------------------------------------
	// This one Tiler.blend() call is where ALL the GPU work happens: it drives the per-tile
	// coarse->base->decoder denoise (the ~23 net calls the runner logs individually) AND then
	// feathers the seams between overlapping tiles. Those two are FUSED inside blend(), so this
	// timer measures "inference + seam blend" together - we cannot cheaply split the coarse vs
	// base vs decoder share apart from here without refactoring the pipeline (we intentionally
	// don't). In practice this stage dominates the tile's wall-clock time.
	const double PipelineStartSec = FPlatformTime::Seconds();

	// blend() returns a row-major (Rows x Cols) elevation buffer in metres, index = row*Cols+col.
	std::vector<float> Elev = Tiler.blend(static_cast<uint64_t>(Seed),
	                                      RowOrigin, ColOrigin,
	                                      RowOrigin + Rows, ColOrigin + Cols, Gen);

	const double PipelineMs = (FPlatformTime::Seconds() - PipelineStartSec) * 1000.0;

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
	// --- PERF: bracket the EROSION stage. ------------------------------------------------
	// The erosion pass is the CPU half of a tile (droplet + thermal weathering). We time just
	// the erode() work here so the per-tile line shows how much of the wall-clock is GPU
	// inference vs CPU erosion. Declared out here so it stays 0.0 when erosion is toggled off.
	double ErosionMs = 0.0;
	if (Config.bErode)
	{
		// Capture the pre-erosion range so the log shows the effect at a glance.
		float PreLo = Elev[0], PreHi = Elev[0];
		for (float V : Elev) { PreLo = FMath::Min(PreLo, V); PreHi = FMath::Max(PreHi, V); }

		const double ErosionStartSec = FPlatformTime::Seconds();
		mira::tdiff::erode(Elev.data(), Cols, Rows, Config.Erosion, static_cast<uint64_t>(Seed));
		ErosionMs = (FPlatformTime::Seconds() - ErosionStartSec) * 1000.0;

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

	// --- PERF: bracket the STORE stage (copy the blended/eroded grid into FCoarseDem). ----
	const double StoreStartSec = FPlatformTime::Seconds();

	Out.CoarseW = Cols;
	Out.CoarseH = Rows;
	Out.Cells.SetNumUninitialized(Rows * Cols);
	for (int32 i = 0; i < Rows * Cols; ++i)
	{
		Out.Cells[i] = Elev[static_cast<size_t>(i)]; // absolute metres
	}

	const double StoreMs = (FPlatformTime::Seconds() - StoreStartSec) * 1000.0;

	const int32 TileCount = Tiler.tile_count(RowOrigin, ColOrigin, RowOrigin + Rows, ColOrigin + Cols);
	UE_LOG(LogMiraCoarseProvider, Display,
		TEXT("[Tdiff] coarse DEM generated: %dx%d cells (%d blended tiles), elev %.1f..%.1f m, "
		     "region [%d,%d]..[%d,%d], seed %lld, conditioning=%s."),
		Cols, Rows, TileCount, Lo, Hi,
		RegionInVoxels.Min.X, RegionInVoxels.Min.Y,
		RegionInVoxels.Max.X, RegionInVoxels.Max.Y, static_cast<long long>(Seed),
		(SynthPtr ? TEXT("synthetic") : TEXT("zero")));

	// --- PERF: stop the whole-tile stopwatch and report. ---------------------------------
	// TotalMs is the true end-to-end cost of generating this one tile. It will be a touch more
	// than pipeline+erosion+store because it also includes the cheap setup (origin math, the
	// SyntheticMap build, the elevation-range scans) - that's intentional; TotalMs is the number
	// the designer actually cares about ("how long did this tile take?").
	const double TotalMs = (FPlatformTime::Seconds() - FillStartSec) * 1000.0;

	// Verbose per-tile line - gated behind MiraThal.Tdiff.PerfLog (default on). Shows the total
	// plus the pipeline (GPU inference + seam blend) / erosion (CPU) / store split so it's obvious
	// where the time goes.
	if (CVarTdiffPerfLog.GetValueOnAnyThread() != 0)
	{
		UE_LOG(LogMiraCoarseProvider, Display,
			TEXT("[Tdiff][Perf] tile [%d,%d]..[%d,%d] generated in %.1f ms (%dx%d cells) - "
			     "pipeline(infer+blend) %.1f / erosion %.1f / store %.1f ms."),
			RegionInVoxels.Min.X, RegionInVoxels.Min.Y,
			RegionInVoxels.Max.X, RegionInVoxels.Max.Y,
			TotalMs, Cols, Rows, PipelineMs, ErosionMs, StoreMs);
	}

	// Rolling aggregate (always logs, every 8 tiles). Safe as plain statics because the caller
	// serializes Fill() under ProviderLock. avg ms/tile = sum/count; tiles/min = 60000 / avg.
	++GTdiffPerfTileCount;
	GTdiffPerfSumMs += TotalMs;
	if ((GTdiffPerfTileCount % 8) == 0)
	{
		const double AvgMs        = GTdiffPerfSumMs / static_cast<double>(GTdiffPerfTileCount);
		const double TilesPerMin  = (AvgMs > 0.0) ? (60000.0 / AvgMs) : 0.0;
		UE_LOG(LogMiraCoarseProvider, Display,
			TEXT("[Tdiff][Perf] rolling: %lld tiles, avg %.1f ms/tile (~%.1f tiles/min)."),
			static_cast<long long>(GTdiffPerfTileCount), AvgMs, TilesPerMin);
	}

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
