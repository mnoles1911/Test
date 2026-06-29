// WeightWindow.h - faithful C++17 port of terrain-diffusion's linear_weight_window.
//
// COPIED + REFACTORED from the public repo (terrain_diffusion/inference/world_pipeline.py),
// function linear_weight_window(size, device, dtype) at lines 117-125.
//
// PURPOSE: seam blending for stitching adjacent diffusion-model inference tiles in the
// Mira-Thal runtime. Each tile is multiplied by this weight window before overlap-add,
// so contributions near tile edges (weight ~ eps) are nearly zero while the centre
// (weight near 1) dominates. Exactly replicates the Python model's blending schedule
// so on-device inference matches the reference checkpoint output.
//
// FORMULA (from upstream, row-major output, indices 0-based):
//   mid = (size - 1) / 2.0
//   eps = 1e-3
//   for each (y, x) in [0, size):
//     wy = 1 - (1 - eps) * clamp(|y - mid| / mid, 0, 1)
//     wx = 1 - (1 - eps) * clamp(|x - mid| / mid, 0, 1)
//     out[y * size + x] = wy * wx
//
// All intermediate arithmetic is in double (matching Python float64), then each
// product is cast to float32 on store - exactly what struct.pack('<f', v) does in
// the reference Python golden, so results are bit-for-bit identical.
//
// For size == 1, mid == 0 and the formula would divide by zero; we return {1.0f}
// (full weight for the single element), which is the logical extension.
//
// Verified against a captured Python golden in tests/standalone/test_tdiff_window.cpp.
// Pure C++17, no engine headers - lives in Core/ for the headless clang harness.
#pragma once

#include <cmath>
#include <cstddef>
#include <vector>

namespace mira {
namespace tdiff {

// Returns a row-major (size x size) float vector of seam-blending weights.
// Element [y * size + x] holds the weight for row y, column x.
// All values lie in [eps, 1.0] where eps = 1e-3.
inline std::vector<float> linear_weight_window(int size)
{
    const int s = size;
    std::vector<float> out(static_cast<size_t>(s * s), 0.0f);
    if (s <= 0) return out;

    // mid: the floating-point centre index. Matches Python's (s-1)/2 exactly.
    const double mid = (s - 1) * 0.5;

    // eps and its complement, computed in double as Python does.
    const double eps = 1e-3;
    const double one_minus_eps = 1.0 - eps; // == 0.999 in double

    for (int y = 0; y < s; ++y)
    {
        // wy = 1 - (1-eps) * clamp(|y - mid| / mid, 0, 1)
        // Guard: when mid == 0 (only for size == 1) the division is undefined;
        // treat the result as 1.0 (full weight, no blending needed).
        double wy;
        if (mid == 0.0)
        {
            wy = 1.0;
        }
        else
        {
            // Compute ratio in double, clamp to [0, 1], apply weight formula.
            double ratio = std::abs(static_cast<double>(y) - mid) / mid;
            if (ratio > 1.0) ratio = 1.0;
            if (ratio < 0.0) ratio = 0.0;
            wy = 1.0 - one_minus_eps * ratio;
        }

        for (int x = 0; x < s; ++x)
        {
            double wx;
            if (mid == 0.0)
            {
                wx = 1.0;
            }
            else
            {
                double ratio = std::abs(static_cast<double>(x) - mid) / mid;
                if (ratio > 1.0) ratio = 1.0;
                if (ratio < 0.0) ratio = 0.0;
                wx = 1.0 - one_minus_eps * ratio;
            }

            // Multiply in double then truncate to float32 on store.
            // This matches Python's struct.pack('<f', wy * wx) exactly.
            out[y * s + x] = static_cast<float>(wy * wx);
        }
    }
    return out;
}

} // namespace tdiff
} // namespace mira
