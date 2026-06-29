// WorldPipeline.h - header-only C++17 port of terrain-diffusion's InfiniteDiffusion
// orchestration (terrain_diffusion/inference/world_pipeline.py).
//
// PLAIN ENGLISH (for the designer):
// This is the SPINE of the AI terrain brain. Given a world seed and a rectangular
// region, it produces a real elevation map (a "DEM" - digital elevation model, a
// grid of ground heights in metres). It does that by running three small neural
// networks in sequence and stitching their outputs together:
//
//     1. COARSE   - paints the rough "lay of the land" (a 6-channel latent) by
//                   running a 20-step EDM DPM-Solver++ denoise loop.
//     2. BASE     - refines that into a detailed 6-channel latent using a "trigflow"
//                   (consistency-model) update of 1 or 2 steps.
//     3. DECODER  - turns the latent into a high-frequency elevation residual with a
//                   single trigflow step.
//
//   ...then _compute_elev() reconstructs the final elevation from the decoder's
//   residual plus the latent's low-frequency channel via a Laplacian pyramid decode,
//   and finally un-does the model's sqrt encoding (elev = sign(x) * x^2).
//
// This header is the GLUE. It does NOT re-implement the math that was already ported
// and validated elsewhere - it CALLS those pieces:
//     * mira::tdiff::EdmDpmScheduler  (Core/Tdiff/EdmDpmScheduler.h) - the coarse loop.
//     * mira::tdiff::fill_standard_normal / standard_normal (PortableRng.h) - noise.
//     * mira::tdiff::linear_weight_window (WeightWindow.h) - tile seam blending.
//     * mira::tdiff::laplacianDenoise / laplacianDecode (Laplacian.h) - final decode.
// The model evaluation itself is injected through a runner interface (see IUNetRunner
// below), exactly mirroring mira::tdiff::ITdiffUNetRunner from the MiraThalTerrainAI
// module - the real runner talks to NNE + DirectML; a test hands in a stub.
//
// SCOPE NOTE (read this):
// The upstream world_pipeline.py is an "infinite" tiled generator: it lays each stage
// down as an InfiniteTensor and streams overlapping tiles across the plane, blending
// them with the weight window. THIS header faithfully ports the PER-TILE denoise
// control flow (the part the task calls "the SPINE" - lines ~909-1313 of the Python),
// running ONE aligned tile per stage to cover the requested region. The multi-tile
// InfiniteTensor windowing and the Perlin "synthetic_map_factory" geographic
// conditioning are NOT ported here (they live in other, unported modules); the coarse
// conditioning is supplied through the overridable sampleCoarseConditioning() seam,
// defaulting to zeros. For a single tile the weight window multiply/divide CANCELS
// inside the normalisation steps (residual[0]/residual[1], latent[:-1]/latent[-1:]),
// so the reconstructed elevation is exact regardless of tile size; the weight window
// only matters once multiple tiles overlap.
//
// Every step below is annotated with the world_pipeline.py line it came from.
//
// Pure C++17, no engine headers -> lives in Core/ so the standalone clang harness
// (tests/standalone/build.sh, test_tdiff_pipeline.cpp) can verify it headlessly.
#pragma once

#include <cstdint>
#include <cstddef>
#include <cmath>
#include <vector>
#include <string>
#include <algorithm>

#include "Core/Tdiff/PortableRng.h"
#include "Core/Tdiff/EdmDpmScheduler.h"
#include "Core/Tdiff/WeightWindow.h"
#include "Core/Tdiff/Laplacian.h"

namespace mira {
namespace tdiff {

// =============================================================================
// Net I/O types - the engine-agnostic mirror of MiraThalTerrainAI's
// mira::tdiff::FTensorData / EUNetModel / ITdiffUNetRunner.
//
// We cannot include TdiffUNetRunner.h here: it pulls in CoreMinimal.h (TArray etc.),
// an Unreal header the standalone clang harness does not have. So Core defines its
// own pure-C++ mirror with the SAME memory layout (flat row-major float buffer +
// shape) and the SAME call contract; a thin adapter on the engine side bridges
// std::vector <-> TArray. Goldens captured as .f32.bin drop straight into either.
// =============================================================================

// One N-dimensional tensor: flat, row-major (NCHW) floats + its shape.
// Mirror of FTensorData (Values/Shape -> data/shape).
struct NetTensor
{
	std::vector<float> data;  // flat, row-major
	std::vector<int>   shape; // e.g. {1, 11, 64, 64}

	NetTensor() = default;
	explicit NetTensor(std::vector<int> s) : shape(std::move(s))
	{
		data.assign(static_cast<size_t>(volume()), 0.0f);
	}
	NetTensor(std::vector<int> s, std::vector<float> v)
		: data(std::move(v)), shape(std::move(s)) {}

	// Product of all dims = number of floats. 0 for an empty shape (mirrors FTensorData).
	long long volume() const
	{
		if (shape.empty()) return 0;
		long long v = 1;
		for (int d : shape) v *= d;
		return v;
	}
	bool consistent() const { return static_cast<long long>(data.size()) == volume(); }
};

// Which of the three exported networks. Values match EUNetModel (Coarse=0,Base=1,Decoder=2).
enum class ENet : uint8_t { Coarse = 0, Base = 1, Decoder = 2 };

// THE CONTRACT - mirror of ITdiffUNetRunner::Run. Inputs are given in the model's
// declared input order:
//   Coarse : x, noise_labels, cond_0, cond_1, cond_2, cond_3, cond_4   (7 inputs)
//   Base   : x, noise_labels, cond_0                                   (3 inputs)
//   Decoder: x, noise_labels                                           (2 inputs)
// and each call fills 'outputs' with a single output tensor. Returns true on success.
class IUNetRunner
{
public:
	virtual ~IUNetRunner() = default;
	virtual bool Run(ENet model,
	                 const std::vector<NetTensor>& inputs,
	                 std::vector<NetTensor>& outputs) = 0;
};

// =============================================================================
// WorldPipelineConfig - the frozen constants the pipeline uses. Defaults are the
// exact values world_pipeline.py's __init__ assigns (lines ~290-362) for the
// shipping config (T=2, coarse_pooling=1, latent_compression=8, onestep_latent=False).
// =============================================================================
struct WorldPipelineConfig
{
	// EDM scheduler config (line 972/1141/1249: sigma_min/max/data; rho default 7).
	double sigma_min  = 0.002;
	double sigma_max  = 80.0;
	double sigma_data = 0.5;
	double rho        = 7.0;

	// Coarse denoise: scheduler.set_timesteps(20) (line 934).
	int coarse_steps = 20;

	// Tile + resolution geometry.
	int coarse_tile        = 64; // TILE_SIZE, coarse stage (line 911/963).
	int latent_tile_stride = 32; // TILE_STRIDE = TILE_SIZE//2, latent stage (line 1055).
	int latent_compression = 8;  // lc / "scale" (line 299) - latent cell = lc full-res px.
	int decoder_tile_size   = 512; // decoder_tile_size default (line 313).
	int decoder_tile_stride = 384; // decoder_tile_stride default (line 314), for noise tiling.

	// Latent stage steps.
	int  T = 2;                  // T=2 -> init step + one intermediate step (line 295/1174).
	bool onestep_latent = false; // (line 312) - if true, skip the T_INTER step.

	// Coarse normalisation (kwargs['coarse_means'/'coarse_stds']). The source __init__
	// defaults (lines 360-361) differ slightly from the shipping checkpoint
	// "xandergos/terrain-diffusion-30m"; we use the CHECKPOINT values. (Coarse denorm
	// only feeds the coarse->latent conditioning, so it does not affect the single-tile
	// playback elevation, but the runtime should match the real world.)
	double coarse_means[6] = { -37.70000792952155, 1.1403065255556186, 18.102486588653473,
	                            332.8342598198454, 1332.2078969994473, 52.660088206981435 };
	double coarse_stds[6]  = {  39.741999742263, 1.7681844104569366, 8.92146918789914,
	                            321.7660336396054, 842.9293648884745, 31.079985318715785 };

	// Coarse geographic conditioning SNR. NOTE: world_pipeline.py's __init__ DEFAULT is
	// [0.3,0.1,1.0,0.1,1.0] (line 353), but the shipping checkpoint
	// "xandergos/terrain-diffusion-30m" OVERRIDES it via from_pretrained to [0.5]*5 -
	// confirmed against the golden trace (coarse cond_0..4 == log(0.5/8) == -2.7725887).
	// We default to the checkpoint value so the runtime matches the real generated world.
	double cond_snr[5] = { 0.5, 0.5, 0.5, 0.5, 0.5 };

	// Latent conditioning normalisation (COND_INPUT_MEAN/STD, lines 1137-1138) and
	// histogram_raw (line 357).
	double cond_input_mean[7] = { 14.99, 11.65, 15.87, 619.26, 833.12, 69.40, 0.66 };
	double cond_input_std[7]  = { 21.72, 21.78, 10.40, 452.29, 738.09, 34.59, 0.47 };
	double histogram_raw[5]   = { 0.0, 0.0, 0.0, 0.0, 0.0 };

	// _compute_elev constants. LOWFREQ_MEAN/STD are hard-coded in the pipeline
	// (lines 1279-1280). residual_mean/std come from kwargs: NOTE the source __init__
	// default is residual_std=1.1678 (line 307), but the shipping checkpoint
	// "xandergos/terrain-diffusion-30m" OVERRIDES it to 0.7 (confirmed against the
	// single-tile golden: with 1.1678 the residual is ~1.668x too large). We default to
	// the checkpoint value so the runtime matches the real generated world.
	double lowfreq_mean  = -31.4;
	double lowfreq_std   = 38.6;
	double residual_mean = 0.0;
	double residual_std  = 0.7;
	double laplacian_sigma = 5.0;
};

// The result of get(): a flat row-major elevation buffer in metres + its dims.
struct ElevTile
{
	std::vector<float> elev; // row-major H*W, metres
	int H = 0;
	int W = 0;
};

// =============================================================================
// WorldPipeline - the orchestrator.
// =============================================================================
class WorldPipeline
{
public:
	explicit WorldPipeline(const WorldPipelineConfig& cfg = WorldPipelineConfig())
		: cfg_(cfg) {}
	virtual ~WorldPipeline() = default;

	// Bookkeeping the structural test inspects: which nets were called, in order.
	// (The pipeline records the ENet of every runner.Run() it issues.)
	const std::vector<ENet>& call_log() const { return call_log_; }

	// -------------------------------------------------------------------------
	// get(seed, i1,j1,i2,j2, runner) - the public entry, mirroring
	// WorldPipeline.get() (line 1367) for the elevation path.
	//
	// Returns the elevation tile for full-resolution region [i1:i2) x [j1:j2)
	// (row-major, metres). with_climate is intentionally not ported (the elevation
	// DEM is the deliverable); _compute_climate (line 1315) is out of scope.
	// -------------------------------------------------------------------------
	//
	// WORLD-POSITIONED NOISE (additive; opt-in via worldOriginI/J):
	// PLAIN ENGLISH: by default this draws each stage's seeded Gaussian noise at the
	// tile's LOCAL origin (0,0). That is fine for ONE isolated tile, but when an infinite
	// world is built from many overlapping tiles, every tile would draw the SAME local
	// noise -> adjacent tiles' fine detail does not line up and the same world point yields
	// different terrain depending on how the region was sliced. To fix that, the multi-tile
	// caller passes the tile's WORLD origin in full-resolution pixels; we then position
	// every stage's noise at that world coordinate (converted into each stage's own grid
	// scale: coarse-grid units, latent-cell units, full-res px), so the gaussian field is
	// ONE continuous, world-keyed function - neighbouring tiles read the SAME field in
	// their overlap and the weight-window blend averages MATCHING data. The caller must
	// also feed ONE shared world seed to every tile (NOT a per-tile reseed).
	// DEFAULT (0,0): every converted offset is 0, so the noise draws fall back to exactly
	// the local-origin behaviour - byte-for-byte IDENTICAL to the validated path. Purely
	// additive: getSingleTile() and the golden parity are untouched.
	ElevTile get(uint64_t seed, int i1, int j1, int i2, int j2, IUNetRunner& runner,
	             int worldOriginI = 0, int worldOriginJ = 0)
	{
		call_log_.clear();
		seed_ = seed;

		const int scale = cfg_.latent_compression;

		// --- World-origin -> per-stage noise grid offsets -----------------------
		// worldOriginI/J are full-resolution pixels (same units as i1..i2). Convert to
		// each stage's grid; when the origin is (0,0) every offset is 0 -> identical to
		// the pre-existing local-origin noise draws.
		//   coarseUnit = scale * (coarse_tile / cond_window) full-res px per coarse cell.
		//   cond_window is the fixed 4x4 coarse->latent conditioning crop: coarse_tile(64)/4
		//   = 16 latent cells per coarse cell, * scale px per latent cell = 128 px.
		const int coarseUnit = scale * (cfg_.coarse_tile / 4); // 8 * 16 = 128 px / coarse cell
		const int woCoarseI  = floorDiv(worldOriginI, coarseUnit);
		const int woCoarseJ  = floorDiv(worldOriginJ, coarseUnit);
		const int woLatI     = floorDiv(worldOriginI, scale);  // latent cell = scale px
		const int woLatJ     = floorDiv(worldOriginJ, scale);
		// decoder noise is full-res -> worldOriginI/J used directly below.

		// --- _compute_elev padding maths (lines 1284-1298) ---------------------
		// kernel_size for sigma=5 -> 11; pad_lr = 11//2 + 1 = 6; pad_hr = 6*scale.
		const int kernel_size = ((static_cast<int>(cfg_.laplacian_sigma * 2) / 2) * 2) + 1;
		const int pad_lr = kernel_size / 2 + 1;
		const int pad_hr = pad_lr * scale;

		// Padded full-res region, snapped to multiples of 'align' (>= scale).
		// PHASE-2 / dynamic-ONNX requirement: the base UNet downsamples by 8, so its latent input
		// lH = pH/scale MUST be a multiple of 8 or the dynamic-axis ONNX errors mid-graph on a
		// Concat (verified empirically: base@20 FAILS; @16/@24/@32 OK). The repo snaps to 'scale'
		// (8) which yields lH like 20 -> broken. We snap to scale*8 (=64) so pH is a multiple of 64
		// => lH a multiple of 8 (base OK) and pH a multiple of 32 (decoder OK). The extra padding is
		// just more halo that computeElev crops back off, so the returned region extent is unchanged.
		const int align = scale * 8;
		const int pi1 = floorDiv(i1 - pad_hr, align) * align;
		const int pj1 = floorDiv(j1 - pad_hr, align) * align;
		const int pi2 = ceilDiv (i2 + pad_hr, align) * align;
		const int pj2 = ceilDiv (j2 + pad_hr, align) * align;

		const int pH = pi2 - pi1;          // residual / decoder full-res dims
		const int pW = pj2 - pj1;
		const int lH = pH / scale;         // latent-cell dims (latent cell = scale px)
		const int lW = pW / scale;

		// --- STAGE 1: COARSE ---------------------------------------------------
		// Produce the 7-channel coarse tile (6 latent channels + 1 weight). The
		// latent stage only needs a 4x4 window of coarse conditioning per tile, so
		// we run one coarse tile and crop the central 4x4 window from it.
		const int CT = cfg_.coarse_tile; // 64
		std::vector<float> coarse7 = coarseTile(/*ci=*/0, /*cj=*/0, CT, runner,
		                                        /*noiseWorldI=*/woCoarseI, /*noiseWorldJ=*/woCoarseJ); // (7,CT,CT)

		// Crop the central 4x4 coarse window the latent net expects (cond_img is a
		// (7,4,4) patch; line 1147 coarse_window size (7,4,4)). For a single tile we
		// take the centre; exact world-coordinate windowing is the deferred
		// InfiniteTensor part.
		std::vector<float> coarseWin = cropCentre(coarse7, 7, CT, CT, 4, 4); // (7,4,4)

		// --- STAGE 2: BASE / LATENT -------------------------------------------
		// t_init = atan(sigmas[0]/sigma_data); sigmas[0] is the Karras max = sigma_max
		// (line 1145; the scheduler's __init__ sets sigmas[0]=sigma_max before any
		// set_timesteps). T_INTER = [atan(0.35/0.5)] (line 1144).
		const double t_init  = std::atan(cfg_.sigma_max / cfg_.sigma_data);
		const double t_inter = std::atan(0.35 / 0.5);

		// Init latent step (seed_offset=5819, sample=None) -> 6-channel tile (5+weight).
		std::vector<float> latent6 = latentTile(coarseWin, /*prev=*/nullptr,
		                                         lH, lW, t_init, /*seed_offset=*/5819, runner,
		                                         /*noiseWorldI=*/woLatI, /*noiseWorldJ=*/woLatJ);

		// Intermediate step (seed_offset=5820), unless onestep_latent (lines 1188-1201).
		if (cfg_.T == 2 && !cfg_.onestep_latent)
		{
			latent6 = latentTile(coarseWin, &latent6, lH, lW, t_inter,
			                     /*seed_offset=*/5820, runner,
			                     /*noiseWorldI=*/woLatI, /*noiseWorldJ=*/woLatJ);
		}

		// --- STAGE 3: DECODER --------------------------------------------------
		// t_list = [atan(sigmas[0]/sigma_data)] (line 1252) - same value as t_init.
		std::vector<float> residual2 = decoderTile(latent6, lH, lW, pH, pW,
		                                            t_init, /*idx=*/0, runner,
		                                            /*noiseWorldI=*/worldOriginI,
		                                            /*noiseWorldJ=*/worldOriginJ); // (2,pH,pW)

		// --- FINAL: _compute_elev (lines 1277-1313) ---------------------------
		return computeElev(residual2, latent6, pH, pW, lH, lW,
		                   /*oi=*/i1 - pi1, /*oj=*/j1 - pj1,
		                   /*H=*/i2 - i1, /*W=*/j2 - j1);
	}

	// -------------------------------------------------------------------------
	// getSingleTile(seed, runner) - the ISOLATED per-tile denoise unit.
	//
	// This is the exact thing capture_singletile.py records (Gate 3 parity oracle):
	// ONE origin-aligned tile chained 1->1->1 with NO multi-tile InfiniteTensor
	// stitching and NO _compute_elev padding:
	//     coarse tile ctx (0,0,0) -> (7,64,64)
	//     latent cond crop = coarse_out[:, 0:4, 0:4]  (TOP-LEFT 4x4, not the centre)
	//     latent init (seed_offset 5819, t_init) then intermediate (5820, atan(0.35/0.5))
	//     decoder tile ctx (0,0,0), size = decoder_tile_size (512) -> (2,512,512)
	//     final elev = laplacianDenoise+Decode of this single tile (no crop).
	// Real WorldPipeline.get() can never collapse to one tile per stage (overlapping
	// windows always blend >=2 neighbours), so this is a dedicated unit entry point;
	// the per-tile math it runs is identical to what get() runs per tile.
	//
	// Returns the full (decoder_tile_size x decoder_tile_size) elevation tile, metres.
	// -------------------------------------------------------------------------
	ElevTile getSingleTile(uint64_t seed, IUNetRunner& runner)
	{
		call_log_.clear();
		seed_ = seed;

		const int CT = cfg_.coarse_tile;        // 64
		const int LT = CT;                       // latent tile = TILE_SIZE = 64 cells
		const int DT = cfg_.decoder_tile_size;   // 512 full-res px

		// STAGE 1: coarse tile at ctx (0,0,0).
		std::vector<float> coarse7 = coarseTile(/*ci=*/0, /*cj=*/0, CT, runner); // (7,CT,CT)

		// Latent conditioning window: TOP-LEFT 4x4 of the coarse tile (capture line 131:
		// coarse_out[:, 0:4, 0:4]) - the isolated unit, NOT get()'s neighbour window.
		std::vector<float> coarseWin = cropTopLeft(coarse7, 7, CT, CT, 4, 4); // (7,4,4)

		// STAGE 2: base/latent, T=2 (init + intermediate).
		const double t_init  = std::atan(cfg_.sigma_max / cfg_.sigma_data);
		const double t_inter = std::atan(0.35 / 0.5);
		std::vector<float> latent6 = latentTile(coarseWin, /*prev=*/nullptr,
		                                         LT, LT, t_init, /*seed_offset=*/5819, runner);
		if (cfg_.T == 2 && !cfg_.onestep_latent)
			latent6 = latentTile(coarseWin, &latent6, LT, LT, t_inter,
			                     /*seed_offset=*/5820, runner);

		// STAGE 3: decoder, 1 step. t = atan(sigmas[0]/sigma_data) == t_init (capture line 147).
		std::vector<float> residual2 = decoderTile(latent6, LT, LT, DT, DT,
		                                            t_init, /*idx=*/0, runner); // (2,DT,DT)

		// FINAL: _compute_elev with NO padding (oi=oj=0, full DTxDT).
		return computeElev(residual2, latent6, DT, DT, LT, LT,
		                   /*oi=*/0, /*oj=*/0, /*H=*/DT, /*W=*/DT);
	}

protected:
	// Geographic conditioning for the coarse net: a 5-channel (5,h,w) tile.
	// In upstream this is the Perlin synthetic_map_factory (line 900/924); that
	// generator is not ported, so the default is zeros. Override to inject the real
	// conditioning later without touching the spine.
	virtual void sampleCoarseConditioning(int /*i1*/, int /*j1*/, int /*i2*/, int /*j2*/,
	                                      int h, int w, std::vector<float>& out5) const
	{
		out5.assign(static_cast<size_t>(5) * h * w, 0.0f);
	}

private:
	WorldPipelineConfig cfg_;
	uint64_t seed_ = 0;
	std::vector<ENet> call_log_;

	// ---- small integer helpers (Python floor // and ceil division) ----------
	static int floorDiv(int a, int b)
	{
		int q = a / b, r = a % b;
		if (r != 0 && ((r < 0) != (b < 0))) --q;
		return q;
	}
	static int ceilDiv(int a, int b)
	{
		// Mirrors world_pipeline's ceil_div: -((-a)//b) (line 1289-1290).
		return -floorDiv(-a, b);
	}

	// ---- portable tile seed: _tile_seed(base_seed, ty, tx) (lines 58-63) ------
	static uint64_t tileSeed(uint64_t base_seed, int ty, int tx)
	{
		const uint64_t K = 0x9E3779B9ULL; // golden-ratio mixing constant (32-bit)
		uint64_t h = base_seed * K;                                   // mod 2^64 (wraps)
		h = h + static_cast<uint64_t>(static_cast<uint32_t>(ty));     // (ty & 0xFFFFFFFF)
		h = h * K + static_cast<uint64_t>(static_cast<uint32_t>(tx)); // (tx & 0xFFFFFFFF)
		return h;
	}

	// ---- gaussian_noise_patch(base_seed, y0,x0,h,w,channels,tile_h,tile_w) -----
	// Faithful port (lines 66-115). Returns a flat (channels,h,w) row-major buffer
	// drawn from the infinite, tile-seeded portable-RNG Gaussian field. Each covered
	// tile is filled with fill_standard_normal(_tile_seed(...), channels*tile_h*tile_w);
	// the overlapping window is copied out. Handles negative coordinates.
	std::vector<float> drawGaussianPatch(uint64_t base_seed, int y0, int x0,
	                                     int h, int w, int channels,
	                                     int tile_h, int tile_w) const
	{
		std::vector<float> out(static_cast<size_t>(channels) * h * w, 0.0f);

		const int ty0 = floorDiv(y0, tile_h);
		const int ty1 = floorDiv(y0 + h - 1, tile_h);
		const int tx0 = floorDiv(x0, tile_w);
		const int tx1 = floorDiv(x0 + w - 1, tile_w);

		std::vector<float> tile(static_cast<size_t>(channels) * tile_h * tile_w);

		for (int ty = ty0; ty <= ty1; ++ty)
		{
			const int tile_y0 = ty * tile_h;
			for (int tx = tx0; tx <= tx1; ++tx)
			{
				const int tile_x0 = tx * tile_w;

				const int oy0 = std::max(y0, tile_y0);
				const int oy1 = std::min(y0 + h, tile_y0 + tile_h);
				const int ox0 = std::max(x0, tile_x0);
				const int ox1 = std::min(x0 + w, tile_x0 + tile_w);

				const uint64_t s = tileSeed(base_seed, ty, tx);
				fill_standard_normal(s, tile.data(), tile.size());

				for (int c = 0; c < channels; ++c)
				{
					for (int yy = oy0; yy < oy1; ++yy)
					{
						const int out_y = yy - y0;
						const int t_y   = yy - tile_y0;
						for (int xx = ox0; xx < ox1; ++xx)
						{
							const int out_x = xx - x0;
							const int t_x   = xx - tile_x0;
							out[(static_cast<size_t>(c) * h + out_y) * w + out_x] =
								tile[(static_cast<size_t>(c) * tile_h + t_y) * tile_w + t_x];
						}
					}
				}
			}
		}
		return out;
	}

	// Crop the central (oc x oh x ow ...) window. Here used to pull the central
	// (C x dh x dw) window out of a (C x sh x sw) channel-major buffer.
	static std::vector<float> cropCentre(const std::vector<float>& src, int C,
	                                     int sh, int sw, int dh, int dw)
	{
		std::vector<float> out(static_cast<size_t>(C) * dh * dw, 0.0f);
		const int oy = (sh - dh) / 2;
		const int ox = (sw - dw) / 2;
		for (int c = 0; c < C; ++c)
			for (int y = 0; y < dh; ++y)
				for (int x = 0; x < dw; ++x)
					out[(static_cast<size_t>(c) * dh + y) * dw + x] =
						src[(static_cast<size_t>(c) * sh + (oy + y)) * sw + (ox + x)];
		return out;
	}

	// Crop the TOP-LEFT (C x dh x dw) window of a (C x sh x sw) channel-major buffer
	// (i.e. src[:, 0:dh, 0:dw]). Used by getSingleTile to match capture_singletile.py's
	// coarse_out[:, 0:4, 0:4] conditioning crop.
	static std::vector<float> cropTopLeft(const std::vector<float>& src, int C,
	                                      int sh, int sw, int dh, int dw)
	{
		std::vector<float> out(static_cast<size_t>(C) * dh * dw, 0.0f);
		for (int c = 0; c < C; ++c)
			for (int y = 0; y < dh; ++y)
				for (int x = 0; x < dw; ++x)
					out[(static_cast<size_t>(c) * dh + y) * dw + x] =
						src[(static_cast<size_t>(c) * sh + y) * sw + x];
		return out;
	}

	// =========================================================================
	// STAGE 1: _coarse_inference (lines 909-959), pool_size=1.
	// Returns a flat (7, CT, CT) buffer: 6 denormalised latent channels weighted by
	// the seam window, plus the weight window itself as channel 6.
	// =========================================================================
	// noiseWorldI/J (default 0): world-grid offset, in COARSE-CELL units, added to the
	// noise draw origins so the coarse gaussian field is world-continuous across tiles.
	// 0,0 -> draws at the local tile origin (i1,j1) exactly as before (golden path).
	std::vector<float> coarseTile(int ci, int cj, int CT, IUNetRunner& runner,
	                              int noiseWorldI = 0, int noiseWorldJ = 0)
	{
		const int N = CT * CT;       // pixels per channel
		const double sd = cfg_.sigma_data;

		// Coarse conditioning: 5-channel synthetic geographic map (line 924).
		std::vector<float> synth; // (5,CT,CT)
		sampleCoarseConditioning(ci, cj, ci + CT, cj + CT, CT, CT, synth);

		// Normalise by MODEL_MEANS/STDS[[0,2,3,4,5]] (line 925).
		static const int condIdx[5] = { 0, 2, 3, 4, 5 };
		for (int c = 0; c < 5; ++c)
		{
			const double m = cfg_.coarse_means[condIdx[c]];
			const double s = cfg_.coarse_stds[condIdx[c]];
			for (int p = 0; p < N; ++p)
			{
				float& v = synth[static_cast<size_t>(c) * N + p];
				v = static_cast<float>((static_cast<double>(v) - m) / s);
			}
		}

		// cond_noise = gaussian_noise_patch(seed, i1, j1, 64,64, channels=5) (line 928).
		// (i1,j1) for this coarse tile come from ctx; for our single tile that's 0,0.
		// World-positioning: add the coarse-cell world offset so neighbouring tiles draw
		// from the SAME continuous field (noiseWorldI/J==0 -> local origin, golden path).
		const int i1 = ci * CT, j1 = cj * CT;
		const int ni = i1 + noiseWorldI, nj = j1 + noiseWorldJ; // world noise origin (coarse cells)
		std::vector<float> cond_noise = drawGaussianPatch(seed_, ni, nj, CT, CT, 5, CT, CT);

		// cond_img = cos(t_cond)*synthetic + sin(t_cond)*cond_noise, per channel
		// where t_cond = atan(cond_snr) (lines 975, 932).
		std::vector<float> cond_img(static_cast<size_t>(5) * N);
		double cond_in[5];
		for (int c = 0; c < 5; ++c)
		{
			const double tc = std::atan(cfg_.cond_snr[c]);
			const double cosv = std::cos(tc), sinv = std::sin(tc);
			for (int p = 0; p < N; ++p)
			{
				cond_img[static_cast<size_t>(c) * N + p] = static_cast<float>(
					cosv * static_cast<double>(synth[static_cast<size_t>(c) * N + p]) +
					sinv * static_cast<double>(cond_noise[static_cast<size_t>(c) * N + p]));
			}
			// cond_inputs = log(tan(t_cond)/8) = log(cond_snr/8)  (lines 976-977).
			cond_in[c] = std::log(std::tan(tc) / 8.0);
		}

		// Build the scheduler and the 20-step schedule (line 972 + 934).
		EdmDpmConfig sc;
		sc.sigma_min = cfg_.sigma_min; sc.sigma_max = cfg_.sigma_max;
		sc.sigma_data = cfg_.sigma_data; sc.rho = cfg_.rho;
		EdmDpmScheduler sch(sc);
		sch.set_timesteps(cfg_.coarse_steps);
		const std::vector<double>& sigmas = sch.sigmas();

		// sample_noise = gaussian_noise_patch(seed+1, i1,j1, 64,64, channels=6) (line 935);
		// sample = sample_noise * sigmas[0] (line 939).
		std::vector<float> sample = drawGaussianPatch(seed_ + 1, ni, nj, CT, CT, 6, CT, CT);
		for (float& v : sample) v = static_cast<float>(static_cast<double>(v) * sigmas[0]);

		// Denoise loop: for t,sigma in zip(timesteps, sigmas) -> coarse_steps iters
		// (lines 941-949). sigmas has coarse_steps+1 entries; zip stops at coarse_steps.
		const size_t count6 = static_cast<size_t>(6) * N;
		std::vector<float> scaled(count6), x_in(static_cast<size_t>(11) * N), prev(count6);
		for (int k = 0; k < cfg_.coarse_steps; ++k)
		{
			const double sigma = sigmas[static_cast<size_t>(k)];

			// scaled_in = scheduler.precondition_inputs(sample, sigma) (line 944).
			scaled = sample;
			sch.precondition_inputs(scaled.data(), count6, sigma);

			// cnoise = trigflow_precondition_noise(sigma) = atan(sigma/sigma_data) (line 945).
			// (The ported EdmDpmScheduler has the EDM precondition_noise=0.25*log(sigma)
			//  used for the timestep index; the model is fed the trigflow noise label.)
			const double cnoise = std::atan(sigma / sd);

			// x_in = cat([scaled_in(6ch), cond_img(5ch)], dim=1) -> 11 channels (line 947).
			std::copy(scaled.begin(), scaled.end(), x_in.begin());
			std::copy(cond_img.begin(), cond_img.end(), x_in.begin() + count6);

			// model_out = coarse_model(x_in, noise_labels=[cnoise], conditional_inputs=cond_in)
			// (line 948). Inputs in declared order: x, noise_labels, cond_0..cond_4.
			std::vector<NetTensor> inputs;
			inputs.reserve(7);
			inputs.emplace_back(std::vector<int>{1, 11, CT, CT}, x_in);
			inputs.emplace_back(std::vector<int>{1},
			                    std::vector<float>{ static_cast<float>(cnoise) });
			for (int c = 0; c < 5; ++c)
				inputs.emplace_back(std::vector<int>{1},
				                    std::vector<float>{ static_cast<float>(cond_in[c]) });

			std::vector<NetTensor> outputs;
			runner.Run(ENet::Coarse, inputs, outputs);
			call_log_.push_back(ENet::Coarse);
			const NetTensor& mo = outputs[0]; // (1,6,CT,CT)

			// sample = scheduler.step(model_out, t, sample).prev_sample (line 949).
			sch.step(mo.data.data(), sample.data(), prev.data(), count6);
			sample.swap(prev);
		}

		// sample = sample / sigma_data (line 951); denormalise by STDS/MEANS (line 952).
		for (int c = 0; c < 6; ++c)
		{
			const double m = cfg_.coarse_means[c], s = cfg_.coarse_stds[c];
			for (int p = 0; p < N; ++p)
			{
				double v = static_cast<double>(sample[static_cast<size_t>(c) * N + p]) / sd;
				v = v * s + m;
				sample[static_cast<size_t>(c) * N + p] = static_cast<float>(v);
			}
		}
		// sample[0,1] = sample[0,0] - sample[0,1] (line 953).
		for (int p = 0; p < N; ++p)
			sample[static_cast<size_t>(1) * N + p] =
				sample[p] - sample[static_cast<size_t>(1) * N + p];

		// output = cat([sample*weight_window, weight_window]) -> 7 channels (line 958).
		std::vector<float> ww = linear_weight_window(CT);
		std::vector<float> out(static_cast<size_t>(7) * N);
		for (int c = 0; c < 6; ++c)
			for (int p = 0; p < N; ++p)
				out[static_cast<size_t>(c) * N + p] =
					sample[static_cast<size_t>(c) * N + p] * ww[p];
		for (int p = 0; p < N; ++p) out[static_cast<size_t>(6) * N + p] = ww[p];
		return out;
	}

	// =========================================================================
	// STAGE 2: _latent_inference (lines 1052-1131), single tile (batch 1).
	// coarseWin is the (7,4,4) coarse conditioning window. prev (or null) is the
	// previous 6-channel latent output. Returns a flat (6,lH,lW) buffer.
	// =========================================================================
	// noiseWorldI/J (default 0): world-grid offset, in LATENT-CELL units, added to the
	// noise draw origin so the latent gaussian field is world-continuous across tiles.
	// 0,0 -> draws at local origin (0,0) exactly as before (golden path).
	std::vector<float> latentTile(const std::vector<float>& coarseWin,
	                              const std::vector<float>* prev,
	                              int lH, int lW, double t, int seed_offset,
	                              IUNetRunner& runner,
	                              int noiseWorldI = 0, int noiseWorldJ = 0)
	{
		const int N = lH * lW;
		const double sd = cfg_.sigma_data;
		const double cosT = std::cos(t), sinT = std::sin(t);

		// sample: zeros (5ch) on the init step, else previous normalised by its weight
		// channel and rescaled by sigma_data (lines 1074-1078).
		std::vector<float> sample(static_cast<size_t>(5) * N, 0.0f);
		if (prev != nullptr)
		{
			// prev is (6,lH,lW): channels 0..4 sample, channel 5 weight.
			const float* w = prev->data() + static_cast<size_t>(5) * N;
			for (int c = 0; c < 5; ++c)
				for (int p = 0; p < N; ++p)
					sample[static_cast<size_t>(c) * N + p] = static_cast<float>(
						static_cast<double>((*prev)[static_cast<size_t>(c) * N + p]) /
						static_cast<double>(w[p]) * sd);
		}

		// Conditioning vector (length 58) from the 4x4 coarse window (lines 1080-1088).
		std::vector<float> cond_inputs = processLatentConditioning(coarseWin);
		const int condLen = static_cast<int>(cond_inputs.size());

		// noise = gaussian_noise_patch(seed+seed_offset, ctx*stride, ..., channels=5)
		// (line 1090). For our single tile ctx=(_,0,0) -> origin 0,0. World-positioning:
		// draw at the latent-cell world offset so neighbouring tiles share the field
		// (noiseWorldI/J==0 -> local origin (0,0), golden path).
		std::vector<float> noise = drawGaussianPatch(seed_ + static_cast<uint64_t>(seed_offset),
		                                             noiseWorldI, noiseWorldJ, lH, lW, 5, 64, 64);

		// z = noise*sigma_data; x_t = cos(t)*sample + sin(t)*z; model_in = x_t/sigma_data
		// (lines 1095-1098).
		std::vector<float> x_t(static_cast<size_t>(5) * N), model_in(static_cast<size_t>(5) * N);
		for (size_t i = 0; i < x_t.size(); ++i)
		{
			const double z = static_cast<double>(noise[i]) * sd;
			const double xt = cosT * static_cast<double>(sample[i]) + sinT * z;
			x_t[i] = static_cast<float>(xt);
			model_in[i] = static_cast<float>(xt / sd);
		}

		// pred = -base_model(model_in, noise_labels=t, conditional_inputs=[cond_inputs])
		// (line 1120). Inputs in declared order: x, noise_labels, cond_0.
		std::vector<NetTensor> inputs;
		inputs.reserve(3);
		inputs.emplace_back(std::vector<int>{1, 5, lH, lW}, model_in);
		inputs.emplace_back(std::vector<int>{1}, std::vector<float>{ static_cast<float>(t) });
		inputs.emplace_back(std::vector<int>{1, condLen}, cond_inputs);

		std::vector<NetTensor> outputs;
		runner.Run(ENet::Base, inputs, outputs);
		call_log_.push_back(ENet::Base);
		const NetTensor& pr = outputs[0]; // (1,5,lH,lW)

		// sample = cos(t)*x_t - sin(t)*sigma_data*pred  (pred negated -> note the minus
		// in front of base_model), then /sigma_data (lines 1128-1129).
		std::vector<float> outSample(static_cast<size_t>(5) * N);
		for (size_t i = 0; i < outSample.size(); ++i)
		{
			const double pred = -static_cast<double>(pr.data[i]); // pred = -model(...)
			const double s = cosT * static_cast<double>(x_t[i]) - sinT * sd * pred;
			outSample[i] = static_cast<float>(s / sd);
		}

		// output = cat([sample*weight_window, weight_window]) -> 6 channels (line 1130).
		std::vector<float> ww = linear_weight_window(lH); // square tile (lH==lW for aligned region)
		// Guard: if non-square, fall back to a per-pixel window via lW (rare). Use lH for size.
		std::vector<float> out(static_cast<size_t>(6) * N);
		for (int c = 0; c < 5; ++c)
			for (int p = 0; p < N; ++p)
				out[static_cast<size_t>(c) * N + p] = outSample[static_cast<size_t>(c) * N + p] * ww[p];
		for (int p = 0; p < N; ++p) out[static_cast<size_t>(5) * N + p] = ww[p];
		return out;
	}

	// _process_latent_conditioning (lines 1018-1050), NOISE_LEVEL=0, COND_MAX_NOISE=0.
	// Input: the (7,4,4) coarse window (already including the weight channel). Builds
	// the (1,7,4,4) cond_img (un-weight + append a ones mask channel), normalises by
	// COND_INPUT_MEAN/STD, then magnitude-preserving-concats the flattened crops into
	// the conditioning vector of length 16+16+4+16+5+1 = 58.
	std::vector<float> processLatentConditioning(const std::vector<float>& coarseWin) const
	{
		const int CW = 4, CH = 4, NW = CW * CH; // 4x4 window, 16 cells
		// cond_img = cond[:-1]/cond[-1:] (line 1080): channels 0..5 = coarse[0..5]/coarse[6].
		// Then append a mask channel of ones -> 7 channels (lines 1082-1083).
		std::vector<float> cond(static_cast<size_t>(7) * NW);
		const float* wch = coarseWin.data() + static_cast<size_t>(6) * NW; // weight channel
		for (int c = 0; c < 6; ++c)
			for (int p = 0; p < NW; ++p)
				cond[static_cast<size_t>(c) * NW + p] = static_cast<float>(
					static_cast<double>(coarseWin[static_cast<size_t>(c) * NW + p]) /
					static_cast<double>(wch[p]));
		for (int p = 0; p < NW; ++p) cond[static_cast<size_t>(6) * NW + p] = 1.0f; // mask

		// Normalise by COND_INPUT_MEAN/STD (line 1028).
		for (int c = 0; c < 7; ++c)
		{
			const double m = cfg_.cond_input_mean[c], s = cfg_.cond_input_std[c];
			for (int p = 0; p < NW; ++p)
			{
				double v = (static_cast<double>(cond[static_cast<size_t>(c) * NW + p]) - m) / s;
				cond[static_cast<size_t>(c) * NW + p] = static_cast<float>(v);
			}
		}
		// nan_to_num on channels 0/1 (lines 1030-1031): with finite inputs this is a no-op.

		// Crops (lines 1033-1036):
		//   means_crop = cond[0]          (16)
		//   p5_crop    = cond[1]          (16)
		//   climate_means_crop = mean over central 2x2 of cond[2..5]  (4)
		//   mask_crop  = cond[6]          (16)
		std::vector<float> means_crop(cond.begin(), cond.begin() + NW);
		std::vector<float> p5_crop(cond.begin() + NW, cond.begin() + 2 * NW);
		std::vector<float> mask_crop(cond.begin() + 6 * NW, cond.begin() + 7 * NW);

		std::vector<float> climate(4);
		for (int c = 0; c < 4; ++c) // channels 2..5
		{
			// central 2x2 = rows/cols [1:3] of the 4x4 window.
			double acc = 0.0;
			const float* ch = cond.data() + static_cast<size_t>(2 + c) * NW;
			for (int yy = 1; yy <= 2; ++yy)
				for (int xx = 1; xx <= 2; ++xx)
					acc += static_cast<double>(ch[yy * CW + xx]);
			climate[c] = static_cast<float>(acc / 4.0);
		}

		// histogram_raw (line 357/1139): 5 values.
		std::vector<float> hist(5);
		for (int i = 0; i < 5; ++i) hist[i] = static_cast<float>(cfg_.histogram_raw[i]);

		// noise_level_norm = (noise_level-0.5)*sqrt(12), noise_level=0 (line 1046).
		const float nln = static_cast<float>((0.0 - 0.5) * std::sqrt(12.0));

		// mp_concat (mira: magnitude-preserving concat, mp_layers.py:65-86) of the six
		// flattened pieces, all equally weighted (w=1/6). For k tensors with equal
		// weights: C = sqrt(sum_N / (k*(1/k)^2)) = sqrt(sum_N * k); each piece is scaled
		// by C/sqrt(N_i) * (1/k).
		std::vector<std::vector<float>> parts = {
			means_crop, p5_crop, climate, mask_crop, hist, { nln }
		};
		return mpConcat(parts);
	}

	// mp_concat with default equal weights (mp_layers.py:65-86).
	static std::vector<float> mpConcat(const std::vector<std::vector<float>>& parts)
	{
		const int k = static_cast<int>(parts.size());
		double sumN = 0.0;
		for (const auto& p : parts) sumN += static_cast<double>(p.size());
		const double w = 1.0 / k;                       // equal weights
		const double sumW2 = k * (w * w);               // = 1/k
		const double C = std::sqrt(sumN / sumW2);
		std::vector<float> out;
		for (const auto& p : parts)
		{
			const double scale = C / std::sqrt(static_cast<double>(p.size())) * w;
			for (float v : p) out.push_back(static_cast<float>(static_cast<double>(v) * scale));
		}
		return out;
	}

	// =========================================================================
	// STAGE 3: _decoder_inference (lines 1209-1242), single tile, t_list of length 1.
	// latent6 is the (6,lH,lW) latent tile. Returns a flat (2,pH,pW) residual buffer
	// (residual*weight, weight).
	// =========================================================================
	// noiseWorldI/J (default 0): world-grid offset, in FULL-RESOLUTION px (decoder scale
	// is 1:1), added to the noise draw origin so the decoder gaussian field is
	// world-continuous across tiles. 0,0 -> draws at local origin (0,0) (golden path).
	std::vector<float> decoderTile(const std::vector<float>& latent6, int lH, int lW,
	                               int pH, int pW, double t, int idx, IUNetRunner& runner,
	                               int noiseWorldI = 0, int noiseWorldJ = 0)
	{
		const int Nfull = pH * pW;
		const int Nlat  = lH * lW;
		const double sd = cfg_.sigma_data;
		const double cosT = std::cos(t), sinT = std::sin(t);
		const int scale = cfg_.latent_compression;

		// sample = zeros (1,pH,pW) (line 1221).
		std::vector<float> sample(static_cast<size_t>(Nfull), 0.0f);

		// latents = (latent[:-1]/latent[-1:])[:4] (line 1223): normalise by weight,
		// take the first 4 channels, then nearest-upsample by 'scale' to (pH,pW)
		// (line 1224, mode='nearest').
		std::vector<float> up(static_cast<size_t>(4) * Nfull);
		const float* w = latent6.data() + static_cast<size_t>(5) * Nlat; // weight channel
		for (int c = 0; c < 4; ++c)
		{
			const float* src = latent6.data() + static_cast<size_t>(c) * Nlat;
			for (int y = 0; y < pH; ++y)
			{
				const int sy = y / scale; // nearest (floor) upsample
				for (int x = 0; x < pW; ++x)
				{
					const int sx = x / scale;
					const double v = static_cast<double>(src[sy * lW + sx]) /
					                 static_cast<double>(w[sy * lW + sx]);
					up[(static_cast<size_t>(c) * pH + y) * pW + x] = static_cast<float>(v);
				}
			}
		}

		// noise = gaussian_noise_patch(seed+5819+idx, ctx*stride, TILE_SIZE,TILE_SIZE,
		// channels=1, tile_h=TILE_SIZE, tile_w=TILE_SIZE) (lines 1229-1232). For the
		// decoder, TILE_SIZE == decoder_tile_size (e.g. 512) - the noise field tiles at
		// the DECODER tile size, NOT 64 (unlike coarse/latent which tile at 64).
		// World-positioning: draw at the full-res world offset so neighbouring tiles share
		// the field (noiseWorldI/J==0 -> local origin (0,0), golden path).
		const int dtile = cfg_.decoder_tile_size;
		std::vector<float> noise = drawGaussianPatch(seed_ + 5819ULL + static_cast<uint64_t>(idx),
		                                             noiseWorldI, noiseWorldJ, pH, pW, 1, dtile, dtile);

		// z = noise*sigma_data; x_t = cos(t)*sample + sin(t)*z; model_in = x_t/sigma_data
		// (lines 1234-1236); then cat([model_in, upsampled_latents]) -> 5 channels (1237).
		std::vector<float> x_t(static_cast<size_t>(Nfull));
		std::vector<float> model_in(static_cast<size_t>(5) * Nfull);
		for (int p = 0; p < Nfull; ++p)
		{
			const double z = static_cast<double>(noise[p]) * sd;
			const double xt = cosT * static_cast<double>(sample[p]) + sinT * z;
			x_t[p] = static_cast<float>(xt);
			model_in[p] = static_cast<float>(xt / sd); // channel 0
		}
		std::copy(up.begin(), up.end(), model_in.begin() + Nfull); // channels 1..4

		// pred = -decoder_model(model_in, noise_labels=[t], conditional_inputs=[]) (line 1238).
		std::vector<NetTensor> inputs;
		inputs.reserve(2);
		inputs.emplace_back(std::vector<int>{1, 5, pH, pW}, model_in);
		inputs.emplace_back(std::vector<int>{1}, std::vector<float>{ static_cast<float>(t) });

		std::vector<NetTensor> outputs;
		runner.Run(ENet::Decoder, inputs, outputs);
		call_log_.push_back(ENet::Decoder);
		const NetTensor& pr = outputs[0]; // (1,1,pH,pW)

		// sample = cos(t)*x_t - sin(t)*sigma_data*pred, then /sigma_data (lines 1239,1241).
		std::vector<float> outSample(static_cast<size_t>(Nfull));
		for (int p = 0; p < Nfull; ++p)
		{
			const double pred = -static_cast<double>(pr.data[p]);
			const double s = cosT * static_cast<double>(x_t[p]) - sinT * sd * pred;
			outSample[p] = static_cast<float>(s / sd);
		}

		// output = cat([sample*weight_window, weight_window]) -> 2 channels (line 1242).
		std::vector<float> ww = linear_weight_window(pH); // square tile
		std::vector<float> out(static_cast<size_t>(2) * Nfull);
		for (int p = 0; p < Nfull; ++p)
		{
			out[p] = outSample[p] * ww[p];
			out[static_cast<size_t>(Nfull) + p] = ww[p];
		}
		return out;
	}

	// =========================================================================
	// FINAL: _compute_elev (lines 1277-1313).
	// residual2: (2,pH,pW) decoder output; latent6: (6,lH,lW) latent tile.
	// Returns the elevation cropped to the requested [oi:oi+H, oj:oj+W] window.
	// =========================================================================
	ElevTile computeElev(const std::vector<float>& residual2, const std::vector<float>& latent6,
	                     int pH, int pW, int lH, int lW,
	                     int oi, int oj, int H, int W) const
	{
		const int Nfull = pH * pW;
		const int Nlat  = lH * lW;

		// residual_p = (residual[0]/residual[1]) * RESIDUAL_STD + RESIDUAL_MEAN (line 1301).
		std::vector<float> residual_p(static_cast<size_t>(Nfull));
		{
			const float* r0 = residual2.data();
			const float* r1 = residual2.data() + Nfull;
			for (int p = 0; p < Nfull; ++p)
				residual_p[p] = static_cast<float>(
					(static_cast<double>(r0[p]) / static_cast<double>(r1[p])) *
					cfg_.residual_std + cfg_.residual_mean);
		}

		// latents_norm = latents[:-1]/latents[-1:]; lowfreq_p = latents_norm[4]*STD+MEAN
		// (lines 1303-1304). latent channel 4 is the low-frequency map.
		std::vector<float> lowfreq_p(static_cast<size_t>(Nlat));
		{
			const float* l4 = latent6.data() + static_cast<size_t>(4) * Nlat;
			const float* lw = latent6.data() + static_cast<size_t>(5) * Nlat; // weight channel
			for (int p = 0; p < Nlat; ++p)
				lowfreq_p[p] = static_cast<float>(
					(static_cast<double>(l4[p]) / static_cast<double>(lw[p])) *
					cfg_.lowfreq_std + cfg_.lowfreq_mean);
		}

		// residual_p, lowfreq_p = laplacian_denoise(residual_p, lowfreq_p, sigma=5) (line 1306).
		// (residual unchanged; lowfreq re-derived.) Then elev_p = laplacian_decode(...) (line 1307).
		int newLh = 0, newLw = 0;
		laplacianDenoiseLowresDims(pH, pW, lW, newLh, newLw);
		std::vector<float> newLowres(static_cast<size_t>(newLh) * newLw);
		laplacianDenoise(residual_p.data(), pH, pW, lowfreq_p.data(), lH, lW,
		                 cfg_.laplacian_sigma, newLowres.data(), newLh, newLw);

		std::vector<float> elev_p(static_cast<size_t>(Nfull));
		laplacianDecode(residual_p.data(), pH, pW, newLowres.data(), newLh, newLw,
		                elev_p.data(), /*extrapolate=*/false);

		// Crop [oi:oi+H, oj:oj+W] then elev = sign(x)*x^2 (the model stores sqrt-elev;
		// lines 1309-1312).
		ElevTile out;
		out.H = H; out.W = W;
		out.elev.assign(static_cast<size_t>(H) * W, 0.0f);
		for (int y = 0; y < H; ++y)
			for (int x = 0; x < W; ++x)
			{
				const double s = static_cast<double>(elev_p[(static_cast<size_t>(oi + y)) * pW + (oj + x)]);
				const double e = (s < 0.0 ? -1.0 : (s > 0.0 ? 1.0 : 0.0)) * s * s;
				out.elev[static_cast<size_t>(y) * W + x] = static_cast<float>(e);
			}
		return out;
	}
};

} // namespace tdiff
} // namespace mira
