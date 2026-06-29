// InfiniteTiler.h - header-only C++17 port of terrain-diffusion's "InfiniteDiffusion"
// multi-tile windowing + seam-blending layer (the `infinite_tensor` package:
// InfiniteTensor / TensorWindow / MemoryTileStore, used by world_pipeline.py).
//
// PLAIN ENGLISH (for the designer):
// WorldPipeline.h is the single-tile "brain" - hand it a seed and a small rectangle and
// it paints one patch of terrain. By itself it can only cover one aligned tile. THIS file
// is the layer that makes the world feel ENDLESS: it lays a grid of OVERLAPPING tiles
// across whatever (arbitrarily large) region you ask for, runs the single-tile pipeline on
// each one, and stitches the overlaps together so there are no visible seams. Because every
// tile is generated from a deterministic per-tile seed and every output pixel is the blend
// of exactly the same set of tiles no matter how you slice the world, you get the two magic
// InfiniteDiffusion properties for free:
//   * O(1) RANDOM ACCESS  - ask for any sub-rectangle directly and get the identical answer
//                           you'd get by generating a huge region and cropping it.
//   * DETERMINISM         - same seed + same coordinates => byte-identical terrain, forever.
//
// HOW THE UPSTREAM MATH WORKS (ported faithfully here):
//   * A TensorWindow is a sliding window with `size`, `stride`, `offset`. Window index w
//     covers pixel range [w*stride + offset, w*stride + size + offset). Overlap happens
//     whenever stride < size. world_pipeline.py's coarse stage uses size=64, stride=48
//     (TILE_SIZE=64, TILE_STRIDE=TILE_SIZE-16=48) -> 16px of overlap between neighbours.
//   * TensorWindow.intersecting_windows([start,stop)) returns every window touching a
//     requested range. The exact integer math (tensor_window.py lines 118-134) is:
//         low  = ceil((start - offset - size + 1) / stride)
//         high = floor((stop  - 1 - offset)       / stride)
//     We reproduce it bit-for-bit with ceilDiv/floorDiv below.
//   * Each tile's generator returns cat([sample * weight_window, weight_window]) - i.e. the
//     data PRE-MULTIPLIED by a soft weight window (linear_weight_window, ~1 in the centre,
//     ~eps at the edges) AND the weight window itself as an extra channel.
//   * MemoryTileStore.read_pixels (tilestore/__init__.py lines 304-352) ADDS every
//     intersecting tile's output into the requested region (overlap-add). So after reading
//     you hold  sum_i(value_i * w_i)  in the data channels and  sum_i(w_i)  in the weight
//     channel. Dividing the first by the second (the `x[:-1] / x[-1:]` normalisation the
//     downstream stages do) yields the weighted average = a partition-of-unity blend. THAT
//     is the seam blend. We do the same here: accumulate weighted sums + weights, divide
//     at the end.
//
// SCOPE / WHAT THIS PORTS:
//   We port the tiling/windowing/blending MATH and an IN-MEMORY tile store (no HDF5 disk
//   store). The blend operates at the ELEVATION level: get_region() runs the whole
//   single-tile WorldPipeline per tile and blends the resulting elevation patches. (The
//   upstream code instead keeps three separate InfiniteTensors - coarse/base/decoder - each
//   tiled independently and blended at the LATENT level; collapsing that into "one pipeline
//   per elevation tile, blend the elevations" is the deliberate runtime simplification
//   noted in WorldPipeline.h's scope block.)
//
//   ===> SEAM (clearly marked): per-tile seeding. =========================================
//   world_pipeline.py draws every tile's noise from ONE infinite, world-positioned field
//   via gaussian_noise_patch(seed, world_y0, world_x0, ...) + _tile_seed(seed, ty, tx)
//   (world_pipeline.py lines 58-115). Overlapping windows therefore read the SAME noise in
//   their shared pixels, so the model outputs already nearly agree and the weight window
//   only smooths a small residual. BUT the already-ported single-tile WorldPipeline::get()
//   always re-centres its noise at local origin (0,0) (it ignores the absolute i1/j1 for
//   noise) - so it is not world-translatable. To keep determinism + random access we give
//   each global tile its OWN seed, _tile_seed(seed, ty, tx) (the SAME mixing function the
//   upstream uses, ported in tileSeed() below), and generate that tile once. Consequences:
//     - Determinism, random access and tile-count match the reference exactly.
//     - In tile OVERLAPS, independently-seeded tiles do not share a noise field, so the
//       weight-window blend smooths between two different fields rather than averaging two
//       near-identical ones. For the production model this is a soft cross-fade; for a
//       generator that is a pure function of world coordinate (see blend() below) the blend
//       is an EXACT partition of unity (the seamlessness the test pins down).
//   The generator passed to blend() receives each tile's world origin (ry0, rx0), so a
//   future world-positioned generator can close this seam WITHOUT changing the blend math.
//   ======================================================================================
//
// Pure C++17, no engine headers -> lives in Core/ so the standalone clang harness
// (tests/standalone/build.sh, test_tdiff_tiler.cpp) can verify it headlessly. Mirrors the
// header-only, mira::tdiff conventions of PortableRng.h / WorldPipeline.h.
#pragma once

#include <cstdint>
#include <cstddef>
#include <map>
#include <tuple>
#include <vector>

#include "Core/Tdiff/WeightWindow.h"
#include "Core/Tdiff/WorldPipeline.h"

namespace mira {
namespace tdiff {

// =============================================================================
// InfiniteTiler - the multi-tile accumulator + blender.
//
// One instance owns:
//   * the tile geometry (size / stride / offset) - the TensorWindow spec, and
//   * an in-memory tile cache keyed by (seed, ty, tx) - the MemoryTileStore stand-in.
// Reusing a cached tile across reads is what guarantees a sub-region read returns the
// identical bytes as the corresponding slice of a larger read (random access). The cache
// is purely an optimisation: generation is deterministic, so a cold instance produces the
// same result, just recomputing tiles.
// =============================================================================
class InfiniteTiler
{
public:
	// Defaults match world_pipeline.py's coarse stage: TILE_SIZE=64, TILE_STRIDE=48
	// (= 64 - 16, i.e. 16px of overlap), offset 0. With these, the region [0,0,8,8] tiles
	// into exactly a 2x2 = 4-window grid - the "4 coarse tiles" the reference reports.
	explicit InfiniteTiler(int tile_size = 64, int tile_stride = 48, int offset = 0,
	                       const WorldPipelineConfig& cfg = WorldPipelineConfig())
		: size_(tile_size), stride_(tile_stride), offset_(offset), cfg_(cfg) {}

	// ---- geometry accessors -------------------------------------------------
	int size()   const { return size_; }
	int stride() const { return stride_; }
	int offset() const { return offset_; }

	// How many single-tile WorldPipeline runs the LAST get_region() issued (for tests).
	int pipeline_runs() const { return pipeline_runs_; }

	// Drop the in-memory tile cache (mirrors MemoryTileStore.clear_cache).
	void clear_cache() { cache_.clear(); }
	std::size_t cached_tiles() const { return cache_.size(); }

	// =========================================================================
	// Tile-grid windowing math - the exact TensorWindow.intersecting_windows port.
	// windowRange([start,stop)) -> inclusive window-index range [lo,hi]; lo>hi means none.
	// =========================================================================
	void windowRange(int start, int stop, int& lo, int& hi) const
	{
		if (stop <= start) { lo = 0; hi = -1; return; } // empty request -> no windows
		// low  = ceil((start - offset - size + 1) / stride)
		// high = floor((stop  - 1 - offset)       / stride)
		lo = ceilDiv(start - offset_ - size_ + 1, stride_);
		hi = floorDiv(stop - 1 - offset_, stride_);
	}

	// Number of tiles (windows) covering region [i1:i2) x [j1:j2). 2-D product of the
	// per-axis window ranges - matches itertools.product over the two intersecting ranges.
	int tile_count(int i1, int j1, int i2, int j2) const
	{
		int rlo, rhi, clo, chi;
		windowRange(i1, i2, rlo, rhi);
		windowRange(j1, j2, clo, chi);
		const int nr = (rhi >= rlo) ? (rhi - rlo + 1) : 0;
		const int nc = (chi >= clo) ? (chi - clo + 1) : 0;
		return nr * nc;
	}

	// The pixel bounds a single tile (ty,tx) covers: rows [ry0, ry0+size), cols [rx0, ...).
	// Mirrors TensorWindow.get_bounds.
	void tileOrigin(int ty, int tx, int& ry0, int& rx0) const
	{
		ry0 = ty * stride_ + offset_;
		rx0 = tx * stride_ + offset_;
	}

	// =========================================================================
	// blend() - the GENERIC windowing + overlap-add + partition-of-unity core.
	//
	// For region [i1:i2) x [j1:j2): enumerate every intersecting tile, ask `gen` to fill
	// that tile's size x size field, multiply by the weight window, accumulate the weighted
	// sums and the weights, then divide. Returns a row-major (i2-i1) x (j2-j1) buffer.
	//
	// `gen` signature:  void gen(uint64_t seed, int ty, int tx, int ry0, int rx0,
	//                            int size, std::vector<float>& out);
	// It must resize/fill `out` to size*size (row-major). It receives the tile's world
	// origin (ry0,rx0) so a world-positioned generator can be plugged in later (see the
	// SEAM note up top) without touching this blend code.
	//
	// Accumulation is in double for numerical stability of the divide (the data is float).
	// =========================================================================
	template <class Gen>
	std::vector<float> blend(uint64_t seed, int i1, int j1, int i2, int j2, Gen&& gen)
	{
		const int H = (i2 > i1) ? (i2 - i1) : 0;
		const int W = (j2 > j1) ? (j2 - j1) : 0;
		std::vector<float> result(static_cast<size_t>(H) * W, 0.0f);
		if (H == 0 || W == 0) return result;

		std::vector<double> accSum(static_cast<size_t>(H) * W, 0.0); // sum_i value_i * w_i
		std::vector<double> accW(static_cast<size_t>(H) * W, 0.0);   // sum_i w_i

		// The soft seam window, shared by every tile (square size x size). >= eps>0 so the
		// weight sum can never be zero where any tile covers a pixel.
		const std::vector<float> ww = linear_weight_window(size_);

		int rlo, rhi, clo, chi;
		windowRange(i1, i2, rlo, rhi);
		windowRange(j1, j2, clo, chi);

		for (int ty = rlo; ty <= rhi; ++ty)
		{
			for (int tx = clo; tx <= chi; ++tx)
			{
				int ry0, rx0;
				tileOrigin(ty, tx, ry0, rx0);

				const std::vector<float>& tile = fetchTile(seed, ty, tx, ry0, rx0, gen);

				// Overlap of this tile's pixel rect with the requested region.
				const int oy0 = (ry0 > i1) ? ry0 : i1;
				const int oy1 = (ry0 + size_ < i2) ? (ry0 + size_) : i2;
				const int ox0 = (rx0 > j1) ? rx0 : j1;
				const int ox1 = (rx0 + size_ < j2) ? (rx0 + size_) : j2;

				for (int y = oy0; y < oy1; ++y)
				{
					const int ly = y - ry0;          // tile-local row
					const int orow = (y - i1) * W;    // output row offset
					for (int x = ox0; x < ox1; ++x)
					{
						const int lx = x - rx0;      // tile-local col
						const double w = static_cast<double>(ww[static_cast<size_t>(ly) * size_ + lx]);
						const double v = static_cast<double>(tile[static_cast<size_t>(ly) * size_ + lx]);
						const size_t oi = static_cast<size_t>(orow + (x - j1));
						accSum[oi] += v * w;
						accW[oi]   += w;
					}
				}
			}
		}

		// Divide: weighted sum / weight sum = blended value (partition of unity).
		for (size_t p = 0; p < result.size(); ++p)
			result[p] = (accW[p] > 0.0) ? static_cast<float>(accSum[p] / accW[p]) : 0.0f;
		return result;
	}

	// =========================================================================
	// get_region() - the PUBLIC production entry: blend WorldPipeline elevation tiles.
	//
	// Splits [i1:i2) x [j1:j2) into the overlapping tile grid, runs the single-tile
	// WorldPipeline once per tile (seeded by _tile_seed(seed, ty, tx)) and blends the
	// elevation patches with the weight window. Returns the blended elevation (metres)
	// for the exact requested region.
	// =========================================================================
	ElevTile get_region(uint64_t seed, int i1, int j1, int i2, int j2, IUNetRunner& runner)
	{
		pipeline_runs_ = 0;

		// Per-tile generator: run the whole single-tile pipeline for tile (ty,tx).
		// The seed is mixed per tile so neighbouring tiles differ; the WorldPipeline
		// re-centres its own noise at (0,0), so we run it over the LOCAL rect [0,size).
		// Unused params (seed/ty/tx are folded into the tile seed; ry0/rx0 unused because
		// WorldPipeline is not world-translatable - the documented seam) are left unnamed.
		auto gen = [&](uint64_t s, int ty, int tx, int /*ry0*/, int /*rx0*/,
		               int sz, std::vector<float>& out)
		{
			WorldPipeline wp(cfg_);
			const uint64_t ts = tileSeed(s, ty, tx);
			ElevTile et = wp.get(ts, 0, 0, sz, sz, runner);
			out = std::move(et.elev);
			++pipeline_runs_;
		};

		ElevTile out;
		out.H = (i2 > i1) ? (i2 - i1) : 0;
		out.W = (j2 > j1) ? (j2 - j1) : 0;
		out.elev = blend(seed, i1, j1, i2, j2, gen);
		return out;
	}

	// =========================================================================
	// tileSeed() - portable per-tile seed, _tile_seed(base_seed, ty, tx)
	// (world_pipeline.py lines 58-63). Identical mixing to WorldPipeline.h's private copy:
	//   h = base*K;  h = h + (ty & 0xFFFFFFFF);  h = h*K + (tx & 0xFFFFFFFF)   (all mod 2^64)
	// Public so callers/tests can reproduce a tile's seed.
	// =========================================================================
	static uint64_t tileSeed(uint64_t base_seed, int ty, int tx)
	{
		const uint64_t K = 0x9E3779B9ULL; // golden-ratio mixing constant (32-bit)
		uint64_t h = base_seed * K;                                   // mod 2^64 (wraps)
		h = h + static_cast<uint64_t>(static_cast<uint32_t>(ty));     // (ty & 0xFFFFFFFF)
		h = h * K + static_cast<uint64_t>(static_cast<uint32_t>(tx)); // (tx & 0xFFFFFFFF)
		return h;
	}

private:
	int size_;
	int stride_;
	int offset_;
	WorldPipelineConfig cfg_;
	int pipeline_runs_ = 0;

	// In-memory tile store: (seed, ty, tx) -> the tile's size*size field. NOTE: keyed
	// without a generator tag, so one InfiniteTiler instance assumes a STABLE generator
	// for a given seed (always true in production: the generator is always WorldPipeline).
	// Tests that mix generators use separate instances.
	std::map<std::tuple<uint64_t, int, int>, std::vector<float>> cache_;

	// Fetch (cache hit) or generate (cache miss) a tile's field.
	template <class Gen>
	const std::vector<float>& fetchTile(uint64_t seed, int ty, int tx,
	                                    int ry0, int rx0, Gen&& gen)
	{
		const auto key = std::make_tuple(seed, ty, tx);
		auto it = cache_.find(key);
		if (it != cache_.end()) return it->second;

		std::vector<float> field;
		gen(seed, ty, tx, ry0, rx0, size_, field);
		auto res = cache_.emplace(key, std::move(field));
		return res.first->second;
	}

	// Python floor-division and ceil-division for (possibly negative) numerator, positive
	// denominator - the integer math TensorWindow relies on.
	static int floorDiv(int a, int b)
	{
		int q = a / b, r = a % b;
		if (r != 0 && ((r < 0) != (b < 0))) --q;
		return q;
	}
	static int ceilDiv(int a, int b)
	{
		return -floorDiv(-a, b);
	}
};

} // namespace tdiff
} // namespace mira
