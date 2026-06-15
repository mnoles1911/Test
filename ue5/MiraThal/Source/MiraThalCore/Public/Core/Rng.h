// Rng.h — tiny deterministic random number generator for the gameplay Core.
//
// WHY THIS EXISTS:
// Engine-agnostic Core can't call Unreal's FMath::Rand or Godot's randf(). But
// systems like the enemy attack pool need weighted random choices, and the
// headless harness needs those choices to be REPRODUCIBLE (a seeded run must
// produce the same sequence every time so tests assert real behaviour, not luck).
//
// This is a SplitMix64 generator: a single 64-bit state, one cheap mix per draw,
// excellent statistical quality for game use. Seed it and the whole sequence is
// determined — exactly what the tests want, and fine for gameplay RNG too.

#pragma once

#include <cstdint>

namespace mira {

struct Rng {
    uint64_t state;

    explicit Rng(uint64_t seed = 0x9E3779B97F4A7C15ull) : state(seed) {}

    // Next raw 64-bit value (SplitMix64).
    uint64_t next_u64() {
        uint64_t z = (state += 0x9E3779B97F4A7C15ull);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
        return z ^ (z >> 31);
    }

    // Float in [0, 1). Mirrors GDScript randf() / UE FMath::FRand().
    float next_float() {
        // Top 24 bits -> [0,1) with full float precision.
        return static_cast<float>(next_u64() >> 40) / static_cast<float>(1u << 24);
    }

    // Integer in [0, n). Returns 0 if n <= 0.
    int next_int(int n) {
        if (n <= 0) return 0;
        return static_cast<int>(next_u64() % static_cast<uint64_t>(n));
    }
};

} // namespace mira
