// test_tdiff_tiler.cpp - harness for the multi-tile InfiniteDiffusion windowing/stitching
// layer (Core/Tdiff/InfiniteTiler.h): the layer that lets the single-tile WorldPipeline
// spine cover an arbitrarily large/infinite region by tiling with overlap + seamless
// weight-window blending.
//
// Validates the four InfiniteDiffusion invariants the task pins down:
//   (a) SEAMLESSNESS   - with a deterministic, world-coordinate stub field, a pixel covered
//                        by two overlapping tiles blends to the SAME value a single tile
//                        gives there (the weight-window blend is a partition of unity).
//   (b) DETERMINISM    - same seed + same region => byte-identical output.
//   (c) RANDOM ACCESS  - reading a sub-region directly equals the corresponding slice of a
//                        larger region (the O(1) random-access invariant), tested BOTH on
//                        the pure-blend path AND on the real WorldPipeline get_region path.
//   (d) TILE COUNT     - a region sized to 4 coarse tiles (size 64 / stride 48) drives
//                        exactly 4 single-tile WorldPipeline runs (= 80 coarse-net calls),
//                        matching the reference's "4 coarse tiles for [0,0,8,8]".
//
// Everything runs against a STUB runner (no real model) so it is fast + GPU-free. Mirrors
// the PASS/return convention of test_tdiff_rng.cpp / test_tdiff_pipeline.cpp. Discovered +
// run by build.sh.
#include "Core/Tdiff/InfiniteTiler.h"

#include <cstdio>
#include <cstdint>
#include <cmath>
#include <vector>

using mira::tdiff::InfiniteTiler;
using mira::tdiff::WorldPipelineConfig;
using mira::tdiff::IUNetRunner;
using mira::tdiff::NetTensor;
using mira::tdiff::ENet;
using mira::tdiff::ElevTile;

// ---------------------------------------------------------------------------
// A deterministic, smoothly-varying function of WORLD coordinate. The seamlessness +
// random-access blend tests use this as the per-tile field: because every tile reports
// g(worldY, worldX) at a given world pixel - identical no matter which tile - the
// partition-of-unity blend must return g(worldY, worldX) EXACTLY (within fp tol), and a
// sub-region read must match the larger read pixel-for-pixel.
// ---------------------------------------------------------------------------
static double worldField(int y, int x)
{
	return 3.0 * std::sin(0.13 * y) + 2.0 * std::cos(0.07 * x)
	     + 0.01 * static_cast<double>(y) - 0.005 * static_cast<double>(x) + 1.0;
}

// ---------------------------------------------------------------------------
// Counting stub runner for the WorldPipeline path (matches test_tdiff_pipeline's stub
// contract). Returns zeros of the correct output shape and tallies calls per net. Zeros
// keep every downstream weight channel >0 so the elevation is finite + deterministic.
// ---------------------------------------------------------------------------
struct CountingStub : IUNetRunner
{
	int coarse = 0, base = 0, decoder = 0;

	bool Run(ENet model, const std::vector<NetTensor>& inputs,
	         std::vector<NetTensor>& outputs) override
	{
		int outChan = 0;
		switch (model)
		{
		case ENet::Coarse:  outChan = 6; ++coarse;  break;
		case ENet::Base:    outChan = 5; ++base;    break;
		case ENet::Decoder: outChan = 1; ++decoder; break;
		}
		const NetTensor& x = inputs[0]; // (1, C, H, W)
		const int H = x.shape[2];
		const int W = x.shape[3];
		NetTensor out(std::vector<int>{1, outChan, H, W}); // zero-initialised
		outputs.clear();
		outputs.push_back(std::move(out));
		return true;
	}
	int total() const { return coarse + base + decoder; }
};

// ===========================================================================
// (a) SEAMLESSNESS - partition of unity over a world-coordinate field.
// ===========================================================================
static int testSeamlessness()
{
	std::printf("-- (a) seamlessness / partition-of-unity --\n");
	int fails = 0;

	// Small overlapping tiles so a modest region has genuine multi-tile overlaps.
	InfiniteTiler tiler(/*size=*/8, /*stride=*/6, /*offset=*/0); // 2px overlap
	const uint64_t seed = 42;

	auto field = [](uint64_t, int, int, int ry0, int rx0, int sz, std::vector<float>& out)
	{
		out.resize(static_cast<size_t>(sz) * sz);
		for (int y = 0; y < sz; ++y)
			for (int x = 0; x < sz; ++x)
				out[static_cast<size_t>(y) * sz + x] =
					static_cast<float>(worldField(ry0 + y, rx0 + x));
	};

	const int i1 = 0, j1 = 0, i2 = 20, j2 = 20;
	std::vector<float> blended = tiler.blend(seed, i1, j1, i2, j2, field);

	// Every output pixel must equal g(world) within tol - this is the blend recovering the
	// underlying field through the weighted overlap-add + divide.
	const int W = j2 - j1;
	double maxAbs = 0.0;
	for (int y = i1; y < i2; ++y)
		for (int x = j1; x < j2; ++x)
		{
			const double got  = blended[static_cast<size_t>(y - i1) * W + (x - j1)];
			const double want = worldField(y, x);
			maxAbs = std::max(maxAbs, std::fabs(got - want));
		}
	const double tol = 1e-4;
	if (maxAbs <= tol)
		std::printf("  ok: blended field == world field everywhere (max|diff|=%.2e)\n", maxAbs);
	else { std::printf("  FAIL: blend != field, max|diff|=%.2e > %.0e\n", maxAbs, tol); ++fails; }

	// Explicit "two overlapping tiles == single-tile value" check at a known overlap pixel.
	// With size 8 / stride 6, pixel (7,7) lies in tile 0 ([0,8)) AND tile 1 ([6,14)) on
	// both axes -> covered by 4 tiles. Confirm coverage, then confirm the blend equals the
	// single-tile value (g(7,7)).
	const int py = 7, px = 7;
	const int cover = tiler.tile_count(py, px, py + 1, px + 1);
	if (cover < 2)
	{ std::printf("  FAIL: pixel (7,7) covered by %d tiles, expected >=2\n", cover); ++fails; }
	else
	{
		const double blendedHere = blended[static_cast<size_t>(py - i1) * W + (px - j1)];
		const double single = worldField(py, px); // what one tile alone reports there
		if (std::fabs(blendedHere - single) <= tol)
			std::printf("  ok: overlap pixel (7,7) covered by %d tiles blends to single-tile "
			            "value (|diff|=%.2e)\n", cover, std::fabs(blendedHere - single));
		else
		{ std::printf("  FAIL: overlap pixel (7,7) blend %.6f != single %.6f\n",
			blendedHere, single); ++fails; }
	}
	return fails;
}

// ===========================================================================
// (b) DETERMINISM - same seed + region => identical output (WorldPipeline path).
// ===========================================================================
static int testDeterminism()
{
	std::printf("-- (b) determinism --\n");
	int fails = 0;

	const uint64_t seed = 987654321ULL;
	const int i1 = 0, j1 = 0, i2 = 16, j2 = 16;

	InfiniteTiler a;        // fresh instance (cold cache)
	CountingStub sa;
	ElevTile ta = a.get_region(seed, i1, j1, i2, j2, sa);

	InfiniteTiler b;        // independent fresh instance
	CountingStub sb;
	ElevTile tb = b.get_region(seed, i1, j1, i2, j2, sb);

	bool same = (ta.elev.size() == tb.elev.size()) && !ta.elev.empty();
	for (size_t i = 0; same && i < ta.elev.size(); ++i)
		if (ta.elev[i] != tb.elev[i]) same = false;

	bool finite = true;
	for (float v : ta.elev) if (!std::isfinite(v)) { finite = false; break; }

	if (!finite) { std::printf("  FAIL: non-finite elevation\n"); ++fails; }
	if (same) std::printf("  ok: two cold runs byte-identical (%zu px) + finite\n", ta.elev.size());
	else { std::printf("  FAIL: same seed produced different output\n"); ++fails; }
	return fails;
}

// ===========================================================================
// (c) RANDOM ACCESS - sub-region read == slice of larger read.
//   c1: pure-blend path (world-coordinate field) - exact partition-of-unity slicing.
//   c2: real WorldPipeline get_region path - the strong InfiniteDiffusion invariant:
//       any pixel is the blend of the SAME global tiles regardless of the request rect,
//       so a direct sub-read is bit-identical to cropping a larger read.
// ===========================================================================
static int testRandomAccess()
{
	std::printf("-- (c) random access (sub-region == slice of larger) --\n");
	int fails = 0;

	// --- c1: pure-blend field path -----------------------------------------
	{
		auto field = [](uint64_t, int, int, int ry0, int rx0, int sz, std::vector<float>& out)
		{
			out.resize(static_cast<size_t>(sz) * sz);
			for (int y = 0; y < sz; ++y)
				for (int x = 0; x < sz; ++x)
					out[static_cast<size_t>(y) * sz + x] =
						static_cast<float>(worldField(ry0 + y, rx0 + x));
		};
		const uint64_t seed = 7;
		InfiniteTiler big(8, 6, 0);
		std::vector<float> bigBuf = big.blend(seed, 0, 0, 32, 32, field);
		const int bigW = 32;

		InfiniteTiler sub(8, 6, 0);
		const int si1 = 8, sj1 = 8, si2 = 20, sj2 = 20;
		std::vector<float> subBuf = sub.blend(seed, si1, sj1, si2, sj2, field);
		const int subW = sj2 - sj1;

		double maxAbs = 0.0;
		for (int y = si1; y < si2; ++y)
			for (int x = sj1; x < sj2; ++x)
			{
				const double s = subBuf[static_cast<size_t>(y - si1) * subW + (x - sj1)];
				const double g = bigBuf[static_cast<size_t>(y) * bigW + x];
				maxAbs = std::max(maxAbs, std::fabs(s - g));
			}
		if (maxAbs == 0.0)
			std::printf("  ok: c1 pure-blend sub == slice, bit-identical\n");
		else { std::printf("  FAIL: c1 sub != slice, max|diff|=%.2e\n", maxAbs); ++fails; }
	}

	// --- c2: real WorldPipeline path ---------------------------------------
	{
		const uint64_t seed = 0xABCDEF12ULL;
		InfiniteTiler big;          // default 64/48
		CountingStub sBig;
		ElevTile bigT = big.get_region(seed, 0, 0, 16, 16, sBig);
		const int bigW = 16;

		InfiniteTiler sub;
		CountingStub sSub;
		const int si1 = 4, sj1 = 4, si2 = 12, sj2 = 12;
		ElevTile subT = sub.get_region(seed, si1, sj1, si2, sj2, sSub);
		const int subW = sj2 - sj1;

		double maxAbs = 0.0;
		for (int y = si1; y < si2; ++y)
			for (int x = sj1; x < sj2; ++x)
			{
				const double s = subT.elev[static_cast<size_t>(y - si1) * subW + (x - sj1)];
				const double g = bigT.elev[static_cast<size_t>(y) * bigW + x];
				maxAbs = std::max(maxAbs, std::fabs(s - g));
			}
		if (maxAbs == 0.0)
			std::printf("  ok: c2 WorldPipeline sub == slice, bit-identical (O(1) random access)\n");
		else { std::printf("  FAIL: c2 sub != slice, max|diff|=%.2e\n", maxAbs); ++fails; }
	}
	return fails;
}

// ===========================================================================
// (d) TILE COUNT - region sized to 4 coarse tiles drives 4 single-tile runs.
// ===========================================================================
static int testTileCount()
{
	std::printf("-- (d) tile count --\n");
	int fails = 0;

	InfiniteTiler tiler; // default 64 / 48 / 0 == coarse stage geometry

	// Pure geometry: [0,0,8,8] must decompose into the reference's 2x2 = 4 coarse tiles
	// (window indices {-1,0} x {-1,0}, exactly TensorWindow.intersecting_windows).
	const int tc = tiler.tile_count(0, 0, 8, 8);
	if (tc == 4) std::printf("  ok: region [0,0,8,8] -> %d tiles (matches '4 coarse tiles')\n", tc);
	else { std::printf("  FAIL: region [0,0,8,8] -> %d tiles, expected 4\n", tc); ++fails; }

	// Per-axis range sanity: indices {-1,0}.
	int lo, hi;
	tiler.windowRange(0, 8, lo, hi);
	if (lo == -1 && hi == 0)
		std::printf("  ok: window range for [0,8) is [%d,%d] (= indices -1,0)\n", lo, hi);
	else { std::printf("  FAIL: window range [%d,%d], expected [-1,0]\n", lo, hi); ++fails; }

	// Driving the real pipeline: 4 tiles => 4 single-tile WorldPipeline runs => each does
	// 20 coarse + 2 base + 1 decoder net calls. So 80 coarse, 8 base, 4 decoder (92 total).
	// (The reference's flat multi-tile run reports 90 net calls for [0,0,8,8] because it
	// tiles coarse/base/decoder as three SEPARATE infinite tensors - 80 coarse + 6 base +
	// 4 decoder; here the per-elevation-tile pipeline nests them, so base/decoder counts
	// differ while the headline 4-tile / 80-coarse decomposition matches exactly.)
	CountingStub stub;
	ElevTile t = tiler.get_region(0xC0FFEEULL, 0, 0, 8, 8, stub);
	(void)t;

	if (tiler.pipeline_runs() == 4)
		std::printf("  ok: get_region issued %d single-tile WorldPipeline runs\n",
		            tiler.pipeline_runs());
	else { std::printf("  FAIL: %d pipeline runs, expected 4\n", tiler.pipeline_runs()); ++fails; }

	if (stub.coarse == 80)
		std::printf("  ok: %d coarse-net calls (4 tiles x 20 steps) - matches reference coarse\n",
		            stub.coarse);
	else { std::printf("  FAIL: %d coarse-net calls, expected 80\n", stub.coarse); ++fails; }

	if (stub.base == 8 && stub.decoder == 4)
		std::printf("  ok: %d base + %d decoder calls (4 tiles x [2 base, 1 decoder]); total %d\n",
		            stub.base, stub.decoder, stub.total());
	else { std::printf("  FAIL: base %d / decoder %d, expected 8 / 4\n", stub.base, stub.decoder); ++fails; }

	return fails;
}

int main()
{
	int fails = 0;
	fails += testSeamlessness();
	fails += testDeterminism();
	fails += testRandomAccess();
	fails += testTileCount();

	std::printf("====================\n");
	if (fails == 0)
	{
		std::printf("test_tdiff_tiler: ALL PASS "
		            "(seamless + deterministic + random-access + tile-count)\n");
		return 0;
	}
	std::printf("test_tdiff_tiler: %d FAILURE(S)\n", fails);
	return 1;
}
