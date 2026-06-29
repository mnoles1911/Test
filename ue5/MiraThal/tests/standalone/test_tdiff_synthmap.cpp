// test_tdiff_synthmap.cpp - parity gate for the SyntheticMap C++ port.
//
// Proves mira::tdiff::SyntheticMap reproduces the REAL terrain-diffusion synthetic-map
// conditioning (synthetic_map.py / make_synthetic_map_factory). Compares the C++ output
// against golden values captured by tdiff/synthmap_reference.py (which runs the actual
// Python pipeline). Discovered + run by build.sh. Regenerate the golden with:
//   PYTHONPATH=D:/terrain-diffusion D:/terrain-diffusion/.venv/Scripts/python.exe \
//     tdiff/synthmap_reference.py
//
// Both sides LOAD the same synthetic_map_stats.json, so the quantile/finalize transforms
// match by construction; the noise comes from the vendored upstream FastNoiseLite the
// Python binding wraps. Mirrors test_tdiff_rng.cpp's PASS/return convention.
#include "Core/Tdiff/SyntheticMap.h"
#include "tdiff/synthmap_golden.inc"

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <cmath>
#include <array>
#include <vector>
#include <string>

// Same committed stats copy the golden generator used.
static const char* kStatsPath = "D:\\terrain-diffusion\\trace_singletile\\synthetic_map_stats.json";

static uint32_t f32bits(float f)
{
	uint32_t b;
	std::memcpy(&b, &f, sizeof(b));
	return b;
}

// One golden region: pointers into the [5][n] tables (row-major contiguous).
struct GoldenRegion { const float* full; const float* raw; int n; };

int main()
{
	// 1) Load the stats exactly as the Python factory did.
	mira::tdiff::SyntheticMapStats stats;
	if (!mira::tdiff::LoadSyntheticMapStats(kStatsPath, stats))
	{
		std::printf("test_tdiff_synthmap: FAILED to load/parse stats at %s\n", kStatsPath);
		return 1;
	}
	if (!stats.IsValid())
	{
		std::printf("test_tdiff_synthmap: stats invalid (nQuantiles=%d)\n", stats.nQuantiles);
		return 1;
	}

	// 2) Build the generator with the same seed and verify seed derivation.
	mira::tdiff::SyntheticMap gen(stats, kSynthSeed);
	int fails = 0;
	for (int i = 0; i < 5; ++i)
	{
		if (gen.Seeds()[i] != kSynthActualSeeds[i])
		{
			std::printf("seed[%d]: got %d want %d\n", i, gen.Seeds()[i], kSynthActualSeeds[i]);
			++fails;
		}
	}

	const GoldenRegion golden[] = {
		{ &kSynthFull_0[0][0], &kSynthRaw_0[0][0], kSynthRegions[0].n },
		{ &kSynthFull_1[0][0], &kSynthRaw_1[0][0], kSynthRegions[1].n },
		{ &kSynthFull_2[0][0], &kSynthRaw_2[0][0], kSynthRegions[2].n },
	};

	// 3) Compare each region, both the raw stack and the full (finalized) map.
	double worstAbs = 0.0;     // largest absolute diff seen anywhere
	double worstRel = 0.0;     // largest relative diff (for large-magnitude channels)
	long   total = 0;          // total scalars compared
	long   exact = 0;          // how many were bit-identical float32

	for (int rgi = 0; rgi < kSynthRegionCount; ++rgi)
	{
		const int i1 = kSynthRegions[rgi].i1, j1 = kSynthRegions[rgi].j1;
		const int i2 = kSynthRegions[rgi].i2, j2 = kSynthRegions[rgi].j2;
		const int n = kSynthRegions[rgi].n;

		std::array<std::vector<float>, 5> full, raw;
		gen.SampleFull(i1, j1, i2, j2, full);
		gen.SampleRaw(i1, j1, i2, j2, raw);

		const float* gfull = golden[rgi].full;
		const float* graw = golden[rgi].raw;

		for (int pass = 0; pass < 2; ++pass) // 0 = raw, 1 = full
		{
			for (int ch = 0; ch < 5; ++ch)
			{
				const std::vector<float>& got = (pass == 0) ? raw[ch] : full[ch];
				const float* want = (pass == 0) ? (graw + (size_t)ch * n)
				                                : (gfull + (size_t)ch * n);
				if ((int)got.size() != n)
				{
					std::printf("region %d %s ch%d: size %zu want %d\n",
						rgi, pass ? "full" : "raw", ch, got.size(), n);
					++fails;
					continue;
				}
				for (int k = 0; k < n; ++k)
				{
					const float a = got[k];
					const float w = want[k];
					++total;
					if (f32bits(a) == f32bits(w)) { ++exact; continue; }
					const double d = std::fabs((double)a - (double)w);
					if (d > worstAbs) worstAbs = d;
					const double denom = std::fabs((double)w);
					const double rel = denom > 1e-12 ? d / denom : 0.0;
					if (rel > worstRel) worstRel = rel;
				}
			}
		}
	}

	std::printf("test_tdiff_synthmap: compared %ld scalars across %d regions (raw+full, 5ch)\n",
		total, kSynthRegionCount);
	std::printf("  bit-exact: %ld / %ld (%.4f%%)\n",
		exact, total, total ? 100.0 * (double)exact / (double)total : 0.0);
	std::printf("  worst abs diff: %.3e   worst rel diff: %.3e\n", worstAbs, worstRel);

	// Tolerance: noise + quantile interp are float-exact; finalize is elementwise
	// float32. Anything beyond a couple ULPs would indicate a real divergence.
	const double ABS_TOL = 1e-3;
	const double REL_TOL = 1e-5;
	if (fails == 0 && (worstAbs <= ABS_TOL || worstRel <= REL_TOL))
	{
		std::printf("test_tdiff_synthmap: ALL PASS (within abs<=%.0e or rel<=%.0e)\n", ABS_TOL, REL_TOL);
		return 0;
	}
	std::printf("test_tdiff_synthmap: %d structural failure(s); abs/rel over tolerance\n", fails);
	return 1;
}
