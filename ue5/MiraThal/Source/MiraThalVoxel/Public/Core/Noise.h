// Noise.h — a tiny, self-contained, deterministic 2D value-noise for the
// engine-agnostic Core layer.
//
// WHY THIS EXISTS (plain English):
// The Godot build's terrain generator samples Godot's own `FastNoiseLite`
// for its three height layers and for the biome relief/moisture control
// fields. FastNoiseLite is a whole library that lives inside Godot — we
// can't (and don't want to) drag it into the Unreal Core, which is supposed
// to be PURE C++17 with no engine of any kind attached. So this header
// stands in for it: a small smooth-interpolated value noise we own outright,
// committed in-tree, zero external dependencies.
//
// HONEST DIVERGENCE NOTE (read this):
// This is NOT a bit-exact clone of Godot's FastNoiseLite. FastNoiseLite is
// an OpenSimplex2 implementation with its own gradient tables and its own
// internal coordinate hashing; reproducing its exact float output would mean
// vendoring the whole library. The task explicitly permits this: we port the
// ALGORITHM STRUCTURE of the generator (the three macro/mid/detail layers,
// the quantize-to-metres flag, the sea-level offset, the biome relief blend,
// the material-banding rules, and the hash3-based flora/ore scatter) and make
// our tests assert STRUCTURAL + DETERMINISM properties rather than
// bit-for-bit parity against Godot.
//
// What this noise DOES guarantee, which is what the generator actually needs:
//   * Determinism: noise2d(x, z, seed) returns the EXACT same double every
//     time, on every platform, for the same inputs. (Pure integer hashing +
//     deterministic float arithmetic — no RNG state, no global tables built
//     at runtime, no platform-dependent transcendental functions.)
//   * Output range: returns a value in [-1, 1], same contract the generator
//     expects from FastNoiseLite::get_noise_2d (the callers remap to [0,1]
//     or scale by an amplitude exactly as they did before).
//   * Smoothness: continuous across cell boundaries (smoothstep-interpolated
//     lattice value noise), so heightfields read as rolling terrain rather
//     than blocky per-cell steps.
//
// Keep this header dependency-free (only <cstdint> + <cmath>).

#pragma once

#include <cstdint>
#include <cmath>

namespace mira {
namespace noise {

// ---- Integer hash → unit double -----------------------------------------
//
// A 64-bit integer mix (SplitMix64-style finalizer). Deterministic and
// well-distributed; we use it to give every integer lattice node a stable
// pseudo-random value. NOT the same primes as the generator's gameplay
// hash3 (that one stays in HeightmapGenerator for ore/flora parity) — this
// one is purely the noise field's internal lattice hash.
inline uint64_t hash_u64(uint64_t v) {
    v ^= v >> 30;
    v *= 0xBF58476D1CE4E5B9ull;
    v ^= v >> 27;
    v *= 0x94D049BB133111EBull;
    v ^= v >> 31;
    return v;
}

// Hash a 2D integer lattice node + seed into a double in [-1, 1].
inline double lattice_value(int64_t ix, int64_t iz, int64_t seed) {
    // Fold the three integers together, then finalize. The large odd
    // multipliers decorrelate the axes before the avalanche mix.
    uint64_t h = static_cast<uint64_t>(ix) * 0x9E3779B97F4A7C15ull;
    h ^= static_cast<uint64_t>(iz) * 0xC2B2AE3D27D4EB4Full;
    h ^= static_cast<uint64_t>(seed) * 0x165667B19E3779F9ull;
    h = hash_u64(h);
    // Top 53 bits → [0,1) double, then remap to [-1, 1].
    const double unit = static_cast<double>(h >> 11) * (1.0 / 9007199254740992.0); // 2^53
    return unit * 2.0 - 1.0;
}

// Smoothstep fade curve (3t² − 2t³). Gives C1 continuity at cell edges so
// the interpolated field has no visible lattice grid.
inline double fade(double t) {
    return t * t * (3.0 - 2.0 * t);
}

// ---- 2D smooth value noise ----------------------------------------------
//
// Sample the noise field at a real-valued (x, z) with the given seed.
// Returns a deterministic double in [-1, 1]. This is the drop-in replacement
// for FastNoiseLite::get_noise_2d at the generator call sites.
//
// Implementation: bilinear-interpolate the four surrounding integer lattice
// node values, with each axis faded by smoothstep. Classic value noise.
inline double noise2d(double x, double z, int64_t seed = 0) {
    const double fx = std::floor(x);
    const double fz = std::floor(z);
    const int64_t ix = static_cast<int64_t>(fx);
    const int64_t iz = static_cast<int64_t>(fz);
    const double tx = fade(x - fx);
    const double tz = fade(z - fz);

    const double v00 = lattice_value(ix,     iz,     seed);
    const double v10 = lattice_value(ix + 1, iz,     seed);
    const double v01 = lattice_value(ix,     iz + 1, seed);
    const double v11 = lattice_value(ix + 1, iz + 1, seed);

    const double a = v00 + (v10 - v00) * tx;  // lerp along x, bottom edge
    const double b = v01 + (v11 - v01) * tx;  // lerp along x, top edge
    return a + (b - a) * tz;                  // lerp along z
}

// ---- Fractal (fBm) sample ------------------------------------------------
//
// FastNoiseLite is usually configured with a few fBm octaves; a single
// value-noise octave reads a bit too smooth for macro relief. This stacks
// `octaves` octaves at doubling frequency / halving amplitude and renormalizes
// back into [-1, 1]. The generator's MACRO layer uses this for richer relief;
// the mid/detail layers and the biome control fields use the single-octave
// noise2d directly (matching how the source layered its OWN frequencies).
inline double fbm2d(double x, double z, int64_t seed, int octaves = 4) {
    if (octaves < 1) octaves = 1;
    double sum = 0.0;
    double amp = 1.0;
    double freq = 1.0;
    double norm = 0.0;
    for (int i = 0; i < octaves; ++i) {
        // Offset the seed per octave so the octaves don't self-correlate.
        sum += amp * noise2d(x * freq, z * freq, seed + static_cast<int64_t>(i) * 1013);
        norm += amp;
        amp *= 0.5;
        freq *= 2.0;
    }
    return (norm > 0.0) ? (sum / norm) : 0.0;
}

} // namespace noise
} // namespace mira
