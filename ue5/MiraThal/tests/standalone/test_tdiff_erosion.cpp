// test_tdiff_erosion.cpp — self-validating gate for the deterministic terrain
// EROSION module (mira::tdiff::erode_* in Core/Tdiff/Erosion.h). This is the
// foundation of Phase 3 (erosion maturity).
//
// This is OUR design, not a port, so there is no captured golden to diff against.
// Instead we assert the PROPERTIES the module must hold:
//   (a) DETERMINISM      — same (grid, params, seed) -> BIT-identical output;
//                          a different seed -> a different result.
//   (b) THERMAL MASS     — erode_thermal moves material but never creates/destroys
//                          it: sum(grid) before == after (tight tolerance).
//   (c) HYDRAULIC CARVES — droplets on a smooth cone cut channels (post-erosion
//                          local height variance goes UP) while staying FINITE and
//                          without the total relief exploding.
//   (d) NO EXPLOSION     — every output is finite and bounded.
//   (e) BORDER SAFETY    — a tiny 8x8 grid erodes without reading out of bounds
//                          (clamped edges; no wrap, no crash).
//
// Mirrors test_tdiff_detail.cpp: own main(), prints "ALL PASS", returns 0/nonzero.
// Discovered + run by build.sh:  ./build.sh tdiff_erosion

#include "Core/Tdiff/Erosion.h"

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <vector>
#include <cmath>

using mira::tdiff::ErosionParams;
using mira::tdiff::erode;
using mira::tdiff::erode_hydraulic;
using mira::tdiff::erode_thermal;

static int g_fails = 0;

// Tiny assert helpers that report instead of aborting (so we see every failure).
static void check(bool cond, const char* msg) {
    if (!cond) { std::printf("  FAIL: %s\n", msg); ++g_fails; }
}

// Exact float32 bit comparison (determinism must be bit-identical, not "close").
static uint32_t f32bits(float f) {
    uint32_t b; std::memcpy(&b, &f, sizeof(b)); return b;
}
static bool grids_bit_identical(const std::vector<float>& a, const std::vector<float>& b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i)
        if (f32bits(a[i]) != f32bits(b[i])) return false;
    return true;
}

static bool all_finite(const std::vector<float>& g) {
    for (float v : g) if (!std::isfinite(v)) return false;
    return true;
}

static double sum_d(const std::vector<float>& g) {
    double s = 0.0;
    for (float v : g) s += static_cast<double>(v);
    return s;
}

// Mean absolute local slope (|h - right| + |h - down|), a proxy for fine channels.
static double mean_local_slope(const std::vector<float>& g, int W, int H) {
    double s = 0.0; int n = 0;
    for (int z = 0; z < H; ++z)
        for (int x = 0; x < W; ++x) {
            const float h = g[z * W + x];
            if (x + 1 < W) { s += std::fabs(h - g[z * W + x + 1]); ++n; }
            if (z + 1 < H) { s += std::fabs(h - g[(z + 1) * W + x]); ++n; }
        }
    return n > 0 ? s / n : 0.0;
}

// Mean |discrete Laplacian| = |4*h - up - down - left - right| over interior cells.
// A SMOOTH surface (cone, plane, dome) has a near-zero Laplacian everywhere, so
// this cleanly isolates the high-frequency "channel + bank" structure that carving
// introduces, independent of the terrain's overall slope. Higher = more carved.
static double mean_laplacian(const std::vector<float>& g, int W, int H) {
    double s = 0.0; int n = 0;
    for (int z = 1; z < H - 1; ++z)
        for (int x = 1; x < W - 1; ++x) {
            const float h = g[z * W + x];
            const float lap = 4.0f * h
                - g[z * W + (x - 1)] - g[z * W + (x + 1)]
                - g[(z - 1) * W + x] - g[(z + 1) * W + x];
            s += std::fabs(lap); ++n;
        }
    return n > 0 ? s / n : 0.0;
}

// Build a smooth radial cone/peak of the given size (heights in voxels).
static std::vector<float> make_cone(int W, int H, float peak) {
    std::vector<float> g(static_cast<size_t>(W) * H);
    const float cx = (W - 1) * 0.5f;
    const float cz = (H - 1) * 0.5f;
    const float maxR = std::sqrt(cx * cx + cz * cz);
    for (int z = 0; z < H; ++z)
        for (int x = 0; x < W; ++x) {
            const float dx = x - cx, dz = z - cz;
            const float r = std::sqrt(dx * dx + dz * dz);
            g[z * W + x] = peak * (1.0f - r / maxR); // 0 at the rim, peak at centre
        }
    return g;
}

int main() {
    // -------------------------------------------------------------------------
    // (a) DETERMINISM — same seed -> bit-identical, different seed -> differs.
    // -------------------------------------------------------------------------
    {
        const int W = 48, H = 40;
        std::vector<float> base = make_cone(W, H, 300.0f);
        ErosionParams p; // defaults

        std::vector<float> a = base, b = base, c = base;
        erode(a.data(), W, H, p, /*seed*/ 0xABCDEF12ULL);
        erode(b.data(), W, H, p, /*seed*/ 0xABCDEF12ULL);
        erode(c.data(), W, H, p, /*seed*/ 0x00000042ULL);

        check(grids_bit_identical(a, b),
              "determinism: same seed produced different output");
        check(!grids_bit_identical(a, c),
              "determinism: different seed produced identical output (suspicious)");

        // Just the hydraulic stage on its own must also be bit-deterministic.
        std::vector<float> h1 = base, h2 = base;
        erode_hydraulic(h1.data(), W, H, p, 777ULL);
        erode_hydraulic(h2.data(), W, H, p, 777ULL);
        check(grids_bit_identical(h1, h2),
              "determinism: erode_hydraulic not bit-identical for same seed");
    }

    // -------------------------------------------------------------------------
    // (b) THERMAL CONSERVES MASS — sum unchanged by erode_thermal.
    // -------------------------------------------------------------------------
    {
        const int W = 33, H = 27;
        // A jagged surface with plenty of over-steep slopes to relax.
        std::vector<float> g(static_cast<size_t>(W) * H);
        for (int z = 0; z < H; ++z)
            for (int x = 0; x < W; ++x)
                g[z * W + x] = 100.0f
                    + 60.0f * std::sin(0.9f * x)
                    + 45.0f * std::cos(1.3f * z)
                    + ((x * 7 + z * 13) % 5) * 20.0f; // sharp steps -> slumping

        const double before = sum_d(g);
        ErosionParams p;
        p.thermalIterations = 20; // lots of movement to stress conservation
        erode_thermal(g.data(), W, H, p);
        const double after = sum_d(g);

        check(all_finite(g), "thermal: produced non-finite values");
        // Tight RELATIVE tolerance: only float round-off in the delta sum should
        // separate before/after (all transfers are per-cell exactly balanced).
        const double tol = 1e-3 * std::fabs(before) + 1e-3;
        check(std::fabs(after - before) <= tol,
              "thermal: mass not conserved");
        std::printf("  thermal mass: before=%.4f after=%.4f |diff|=%.6f tol=%.6f\n",
                    before, after, std::fabs(after - before), tol);

        // Sanity: thermal actually DID something (reduced the steepest slopes).
        // Rebuild the same surface and compare max local slope.
        std::vector<float> g2(static_cast<size_t>(W) * H);
        for (int z = 0; z < H; ++z)
            for (int x = 0; x < W; ++x)
                g2[z * W + x] = 100.0f
                    + 60.0f * std::sin(0.9f * x)
                    + 45.0f * std::cos(1.3f * z)
                    + ((x * 7 + z * 13) % 5) * 20.0f;
        check(mean_local_slope(g, W, H) < mean_local_slope(g2, W, H),
              "thermal: did not reduce average slope (no smoothing happened)");
    }

    // -------------------------------------------------------------------------
    // (c) HYDRAULIC CARVES — smooth cone gains channels, stays finite/bounded.
    // -------------------------------------------------------------------------
    {
        const int W = 64, H = 64;
        const float peak = 400.0f;
        std::vector<float> cone = make_cone(W, H, peak);
        std::vector<float> eroded = cone;

        ErosionParams p;
        p.dropletsPerCell = 0.75f; // a good rain soak so channels are clear

        const double lapBefore = mean_laplacian(cone, W, H);
        const double lapAfter0 = lapBefore; // captured for the print below

        erode_hydraulic(eroded.data(), W, H, p, 20260630ULL);

        const double lapAfter = mean_laplacian(eroded, W, H);
        (void)lapAfter0;

        check(all_finite(eroded), "hydraulic: produced NaN/Inf");

        // A smooth cone has an almost-zero Laplacian (no fine structure); after rain
        // there must be visibly MORE high-frequency channel/bank structure. This is
        // slope-independent, so a steep cone's uniform grade doesn't mask the carving.
        check(lapAfter > lapBefore * 2.0,
              "hydraulic: did not carve channels (Laplacian roughness did not rise)");
        std::printf("  hydraulic carve: |Laplacian| %.5f -> %.5f (x%.2f), "
                    "localSlope %.3f -> %.3f\n",
                    lapBefore, lapAfter,
                    (lapBefore > 0.0 ? lapAfter / lapBefore : 0.0),
                    mean_local_slope(cone, W, H), mean_local_slope(eroded, W, H));

        // Relief must not EXPLODE: post-erosion span stays within a sane multiple
        // of the original peak (erosion redistributes, it doesn't blow up).
        float lo = eroded[0], hi = eroded[0];
        for (float v : eroded) { if (v < lo) lo = v; if (v > hi) hi = v; }
        const float relief = hi - lo;
        check(relief < peak * 3.0f,
              "hydraulic: total relief exploded beyond a sane bound");
        std::printf("  hydraulic relief: [%.2f .. %.2f] span=%.2f (peak was %.1f)\n",
                    lo, hi, relief, peak);
    }

    // -------------------------------------------------------------------------
    // (d) NO EXPLOSION / FINITE — full erode() pipeline stays finite + bounded.
    // -------------------------------------------------------------------------
    {
        const int W = 50, H = 50;
        std::vector<float> g = make_cone(W, H, 500.0f);
        ErosionParams p;
        erode(g.data(), W, H, p, 12345ULL);
        check(all_finite(g), "full erode: produced non-finite values");
        float lo = g[0], hi = g[0];
        for (float v : g) { if (v < lo) lo = v; if (v > hi) hi = v; }
        check(hi - lo < 2000.0f, "full erode: relief exploded");
    }

    // -------------------------------------------------------------------------
    // (e) BORDER SAFETY — small grids erode without OOB (clamped edges, no wrap).
    //     If any read stepped outside the buffer, ASan/UBSan or a stray NaN would
    //     show; here we simply require finite output on the smallest sane sizes.
    // -------------------------------------------------------------------------
    {
        const int sizes[][2] = { {8, 8}, {8, 3}, {3, 8}, {2, 2}, {5, 9} };
        for (auto& s : sizes) {
            const int W = s[0], H = s[1];
            std::vector<float> g(static_cast<size_t>(W) * H);
            for (int z = 0; z < H; ++z)
                for (int x = 0; x < W; ++x)
                    g[z * W + x] = 50.0f + 20.0f * x - 10.0f * z; // a tilted ramp
            ErosionParams p;
            p.erosionRadius = 3; // brush bigger than the grid -> must still clamp safely
            erode(g.data(), W, H, p, 99ULL);
            check(all_finite(g), "border: small grid produced non-finite values");
        }
        // Degenerate sizes must be safe no-ops (not crash).
        std::vector<float> one(1, 42.0f);
        ErosionParams p;
        erode(one.data(), 1, 1, p, 1ULL);
        erode_thermal(one.data(), 1, 1, p);
        check(all_finite(one) && one[0] == 42.0f, "border: 1x1 grid was not a safe no-op");
    }

    // -------------------------------------------------------------------------
    if (g_fails == 0) {
        std::printf("test_tdiff_erosion: ALL PASS "
                    "(determinism + thermal mass + hydraulic carve + finite + border)\n");
        return 0;
    }
    std::printf("test_tdiff_erosion: %d FAILURE(S)\n", g_fails);
    return 1;
}
