// PortableRng.h - faithful C++17 port of terrain-diffusion's portable_rng.py.
//
// COPIED + REFACTORED from the public repo (terrain_diffusion/inference/portable_rng.py).
// PCG64 (64-bit LCG + XSH-RR 64/32) + standard normals via the Marsaglia polar method.
// The whole point of the upstream module is that "the same algorithm can be implemented in
// C++/Java for identical streams" - this is that C++ implementation. It MUST produce the
// byte-identical stream the Python model uses, or the generated world will differ from the
// reference (and across machines). Verified against a captured Python golden in
// tests/standalone/test_tdiff_rng.cpp.
//
// Pure C++17, no engine headers -> lives in Core/ so the standalone clang harness can test it.
#pragma once

#include <cstdint>
#include <cstddef>
#include <cmath>
#include <vector>

namespace mira {
namespace tdiff {

// PCG64 64/32 constants (single 64-bit seed -> same stream everywhere). From portable_rng.py.
constexpr uint64_t PCG64_MULT = 6364136223846793005ULL;
constexpr uint64_t PCG64_INC  = 1442695040888963407ULL;

// One step: advance state in place, return the 32-bit output.
// Mirror of _pcg64_next / _pcg64_next_numba: state = state*MULT + INC (mod 2^64);
// x = (((state>>18) ^ state) >> 27) & 0xFFFFFFFF; rot = state>>59; out = rotr32(x, rot).
inline uint32_t pcg64_next(uint64_t& state)
{
	state = state * PCG64_MULT + PCG64_INC; // unsigned wraparound == mod 2^64
	const uint32_t x = static_cast<uint32_t>((((state >> 18) ^ state) >> 27) & 0xFFFFFFFFULL);
	const unsigned rot = static_cast<unsigned>(state >> 59) & 31u;
	// rotate-right by rot, with ((32-rot)&31) so rot==0 shifts by 0 (matches Python, avoids UB).
	const uint32_t out32 = static_cast<uint32_t>((x >> rot) | (x << ((32u - rot) & 31u)));
	return out32;
}

// Derive a new 64-bit seed from a parent seed (two PCG64 outputs -> 64 bits).
// Mirror of next_seed() for the seed != 0 path. Deterministic worlds always pass a nonzero
// seed; the Python seed==0 "use wall-clock time" branch is intentionally NOT ported (it is
// non-deterministic and never used on the generation path).
inline uint64_t next_seed(uint64_t seed)
{
	uint64_t state = seed;
	const uint32_t lo = pcg64_next(state);
	const uint32_t hi = pcg64_next(state);
	return (static_cast<uint64_t>(hi) << 32) | static_cast<uint64_t>(lo);
}

// Fill out[0..n) with standard normals. Faithful port of _fill_standard_normal_impl:
// Marsaglia polar - draw two uint32, map to (-1,1], keep pairs with 0 < S=v1^2+v2^2 < 1,
// then X = v * sqrt(-2 ln S / S). All intermediate math is float64 (double); the store to a
// float buffer truncates to float32 exactly as numpy does when out is a float32 array.
inline void fill_standard_normal(uint64_t seed, float* out, size_t n)
{
	uint64_t state = seed;
	size_t i = 0;
	const double inv_2p32 = 1.0 / 4294967296.0; // 1 / 2^32
	while (i < n)
	{
		const uint32_t u1 = pcg64_next(state);
		const uint32_t u2 = pcg64_next(state);
		const double v1 = 2.0 * (static_cast<double>(u1) + 1.0) * inv_2p32 - 1.0;
		const double v2 = 2.0 * (static_cast<double>(u2) + 1.0) * inv_2p32 - 1.0;
		const double s = v1 * v1 + v2 * v2;
		if (0.0 < s && s < 1.0)
		{
			const double f = std::sqrt(-2.0 * std::log(s) / s);
			out[i++] = static_cast<float>(v1 * f);
			if (i < n)
			{
				out[i++] = static_cast<float>(v2 * f);
			}
		}
	}
}

// Convenience: allocate + fill (matches standard_normal()).
inline std::vector<float> standard_normal(uint64_t seed, size_t size)
{
	std::vector<float> out(size);
	if (size != 0)
	{
		fill_standard_normal(seed, out.data(), size);
	}
	return out;
}

} // namespace tdiff
} // namespace mira
