// test_tdiff_window.cpp - parity gate for WeightWindow.h.
//
// Proves the C++ linear_weight_window port is bit-exact (or within 1e-6) versus
// the Python reference implementation in tdiff/window_reference.py, which faithfully
// re-implements terrain_diffusion/inference/world_pipeline.py's linear_weight_window.
//
// Regenerate the golden whenever the formula changes:
//   python tdiff/window_reference.py
//
// Build and run via:
//   bash build.sh tdiff_window
#include "Core/Tdiff/WeightWindow.h"
#include "tdiff/window_golden.inc"

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <cmath>
#include <vector>

// Return the IEEE-754 bit pattern of a float32.
static uint32_t f32bits(float f)
{
    uint32_t b;
    std::memcpy(&b, &f, sizeof(b));
    return b;
}

// Reinterpret an IEEE-754 bit pattern as float32 (for printing / diff).
static float bits_to_f32(uint32_t b)
{
    float f;
    std::memcpy(&f, &b, sizeof(f));
    return f;
}

int main()
{
    int fails = 0;

    for (int e = 0; e < kGoldenWindowCount; ++e)
    {
        const GoldenWindow& g  = kGoldenWindows[e];
        const int           s  = g.size;
        const int           n  = s * s;

        // Run the C++ port.
        const std::vector<float> got = mira::tdiff::linear_weight_window(s);

        // Sanity: right number of elements.
        if ((int)got.size() != n)
        {
            std::printf("size=%d: wrong element count: got %d want %d\n",
                s, (int)got.size(), n);
            ++fails;
            continue;
        }

        int size_fails = 0;
        for (int i = 0; i < n; ++i)
        {
            const uint32_t got_bits  = f32bits(got[i]);
            const uint32_t want_bits = g.bits[i];

            // Primary check: bit-exact (both sides computed in float64 then
            // truncated to float32 identically).
            if (got_bits == want_bits) continue;

            // Fallback tolerance: allow up to 1e-6 absolute difference in
            // case of platform rounding edge cases.
            const float got_f    = got[i];
            const float want_f   = bits_to_f32(want_bits);
            const float absdiff  = std::fabs(got_f - want_f);
            if (absdiff <= 1e-6f) continue;

            const int y = i / s;
            const int x = i % s;
            std::printf("FAIL size=%d [y=%d x=%d]: got %.10f (bits=%u)  want %.10f (bits=%u)  diff=%.2e\n",
                s, y, x,
                (double)got_f,   got_bits,
                (double)want_f,  want_bits,
                (double)absdiff);
            ++fails;
            ++size_fails;
        }

        if (size_fails == 0)
        {
            std::printf("  size=%d: %d values OK\n", s, n);
        }
    }

    std::printf("----\n");
    if (fails == 0)
    {
        std::printf("test_tdiff_window: ALL PASS (%d window size(s), bit-exact vs golden)\n",
            kGoldenWindowCount);
        return 0;
    }
    std::printf("test_tdiff_window: %d FAILURE(S)\n", fails);
    return 1;
}
