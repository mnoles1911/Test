// test_tdiff_rng.cpp - Gate 2: prove the C++ PortableRng port is BIT-EXACT vs the repo's
// portable_rng algorithm. Compares the C++ stream against golden values captured by
// tdiff/rng_reference.py (a faithful pure-Python copy of the upstream numba kernels).
// Discovered + run by build.sh (the green gate). Regenerate the golden with:
//   python tdiff/rng_reference.py
#include "Core/Tdiff/PortableRng.h"
#include "tdiff/golden_rng.inc"

#include <cstdio>
#include <cstring>
#include <cstdint>

static uint32_t f32bits(float f)
{
	uint32_t b;
	std::memcpy(&b, &f, sizeof(b));
	return b;
}

int main()
{
	int fails = 0;
	for (int e = 0; e < kGoldenRngCount; ++e)
	{
		const GoldenRng& g = kGoldenRng[e];

		// 1) raw PCG64 32-bit stream
		uint64_t st = g.seed;
		for (int i = 0; i < kGoldenK; ++i)
		{
			const uint32_t o = mira::tdiff::pcg64_next(st);
			if (o != g.raw[i])
			{
				std::printf("seed %llu raw[%d]: got %u want %u\n",
					(unsigned long long)g.seed, i, o, g.raw[i]);
				++fails;
			}
		}

		// 2) standard normals - compare float32 bit patterns (exact)
		float buf[64];
		mira::tdiff::fill_standard_normal(g.seed, buf, (size_t)kGoldenK);
		for (int i = 0; i < kGoldenK; ++i)
		{
			const uint32_t b = f32bits(buf[i]);
			if (b != g.normbits[i])
			{
				std::printf("seed %llu norm[%d] bits: got %u want %u\n",
					(unsigned long long)g.seed, i, b, g.normbits[i]);
				++fails;
			}
		}

		// 3) next_seed
		const uint64_t ns = mira::tdiff::next_seed(g.seed);
		if (ns != g.next_seed)
		{
			std::printf("seed %llu next_seed: got %llu want %llu\n",
				(unsigned long long)g.seed, (unsigned long long)ns,
				(unsigned long long)g.next_seed);
			++fails;
		}
	}

	if (fails == 0)
	{
		std::printf("test_tdiff_rng: ALL PASS (%d seeds x %d values, bit-exact)\n",
			kGoldenRngCount, kGoldenK);
		return 0;
	}
	std::printf("test_tdiff_rng: %d FAILURE(S)\n", fails);
	return 1;
}
