// test_tdiff_detail.cpp — self-validating gate for the 30 m -> 10 cm detail bridge
// (mira::tdiff::sample_height_voxels in Core/Tdiff/DetailBridge.h).
//
// This is OUR design, not a port, so there is no captured golden to diff against.
// Instead we assert the PROPERTIES the bridge must hold:
//   (a) DETERMINISM   — same (seed, x, z) → byte-identical output across calls.
//   (b) MACRO FIDELITY — with detail off, bicubic reproduces the coarse grid at
//                        pixel centres, and is smooth + monotone on a ramp.
//   (c) DETAIL PRESENCE — with detail on over a FLAT coarse grid, neighbouring
//                        columns differ (std-dev > 0) and stay within the
//                        expected amplitude bound.
//   (d) SLOPE KEYING   — a steep coarse region gets MORE detail variance than a
//                        flat one.
// Mirrors test_tdiff_rng.cpp: own main(), prints "ALL PASS", returns 0/nonzero.
// Discovered + run by build.sh:  ./build.sh tdiff_detail

#include "Core/Tdiff/DetailBridge.h"

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <vector>
#include <cmath>

using mira::tdiff::DetailBridgeParams;
using mira::tdiff::sample_height_voxels;

static int g_fails = 0;

// Tiny assert helpers that report instead of aborting (so we see every failure).
static void check(bool cond, const char* msg) {
    if (!cond) { std::printf("  FAIL: %s\n", msg); ++g_fails; }
}
static void check_near(double got, double want, double tol, const char* msg) {
    if (std::fabs(got - want) > tol) {
        std::printf("  FAIL: %s (got %.6f want %.6f tol %.6f)\n", msg, got, want, tol);
        ++g_fails;
    }
}

// Exact float64 bit comparison (determinism must be bit-identical, not "close").
static uint64_t f64bits(double d) {
    uint64_t b; std::memcpy(&b, &d, sizeof(b)); return b;
}

// Scale constants used throughout: 30 m/px * 10 vox/m = 300 voxels per coarse pixel.
static const double kPitch = 300.0;

int main() {
    // -------------------------------------------------------------------------
    // (a) DETERMINISM
    // -------------------------------------------------------------------------
    {
        // A small smooth-ish coarse grid (heights in voxels).
        const int cw = 6, ch = 6;
        std::vector<float> grid(cw * ch);
        for (int z = 0; z < ch; ++z)
            for (int x = 0; x < cw; ++x)
                grid[z * cw + x] = 200.0f + 30.0f * x + 17.0f * z;

        DetailBridgeParams p;
        p.seed = 12345;
        p.detailAmpVoxels = 40.0;

        const int probes[][2] = { {0,0}, {1,1}, {137,42}, {-55,900}, {3000,-1200} };
        for (auto& pr : probes) {
            const double a = sample_height_voxels(grid.data(), cw, ch, 0.0, 0.0, kPitch,
                                                  pr[0], pr[1], p);
            const double b = sample_height_voxels(grid.data(), cw, ch, 0.0, 0.0, kPitch,
                                                  pr[0], pr[1], p);
            check(f64bits(a) == f64bits(b), "determinism: repeated call differs");
        }
        // A different seed should generally move the output (sanity, not strict).
        DetailBridgeParams p2 = p; p2.seed = 999;
        const double s1 = sample_height_voxels(grid.data(), cw, ch, 0.0, 0.0, kPitch, 137, 42, p);
        const double s2 = sample_height_voxels(grid.data(), cw, ch, 0.0, 0.0, kPitch, 137, 42, p2);
        check(s1 != s2, "determinism: different seed gave identical detail (suspicious)");
    }

    // -------------------------------------------------------------------------
    // (b) MACRO FIDELITY (detail OFF)
    // -------------------------------------------------------------------------
    {
        // Reproduce coarse values exactly at pixel centres.
        const int cw = 8, ch = 8;
        std::vector<float> grid(cw * ch);
        for (int z = 0; z < ch; ++z)
            for (int x = 0; x < cw; ++x) {
                // A non-trivial smooth surface so the test is meaningful.
                grid[z * cw + x] = 500.0f
                    + 40.0f * std::sin(0.5f * x)
                    + 25.0f * std::cos(0.4f * z);
            }

        DetailBridgeParams p;
        p.detailAmpVoxels = 0.0; // macro only

        for (int z = 0; z < ch; ++z) {
            for (int x = 0; x < cw; ++x) {
                const int wx = static_cast<int>(x * kPitch); // exact pixel centre
                const int wz = static_cast<int>(z * kPitch);
                const double got = sample_height_voxels(grid.data(), cw, ch, 0.0, 0.0, kPitch,
                                                        wx, wz, p);
                check_near(got, grid[z * cw + x], 1e-3,
                           "macro fidelity: bicubic != coarse at pixel centre");
            }
        }

        // Ramp: linear in x → Catmull-Rom must reproduce it exactly and be monotone.
        const int rw = 8, rh = 4;
        std::vector<float> ramp(rw * rh);
        for (int z = 0; z < rh; ++z)
            for (int x = 0; x < rw; ++x)
                ramp[z * rw + x] = 100.0f + 50.0f * x; // +50 voxels per coarse pixel

        // MONOTONE everywhere across the grid span (edges clamp but must not dip).
        double prev = -1e30;
        bool monotone = true;
        for (int wx = 0; wx <= static_cast<int>((rw - 1) * kPitch); wx += 13) {
            const double got = sample_height_voxels(ramp.data(), rw, rh, 0.0, 0.0, kPitch,
                                                    wx, 0, p);
            if (got < prev - 1e-9) monotone = false;
            prev = got;
        }
        check(monotone, "macro fidelity: bicubic ramp not monotone");

        // EXACT-LINEAR only in interior intervals [1 .. rw-2], where all four
        // Catmull-Rom control points genuinely lie on the line (at the clamped
        // edges the phantom control point intentionally breaks pure linearity).
        for (int wx = static_cast<int>(1 * kPitch); wx <= static_cast<int>((rw - 2) * kPitch); wx += 13) {
            const double got = sample_height_voxels(ramp.data(), rw, rh, 0.0, 0.0, kPitch,
                                                    wx, 0, p);
            const double want = 100.0 + 50.0 * (static_cast<double>(wx) / kPitch);
            check_near(got, want, 1e-3, "macro fidelity: bicubic ramp not linear (interior)");
        }
    }

    // -------------------------------------------------------------------------
    // (c) DETAIL PRESENCE (detail ON, FLAT coarse grid)
    // -------------------------------------------------------------------------
    {
        const int cw = 8, ch = 8;
        const float base = 500.0f;
        std::vector<float> flat(cw * ch, base);

        DetailBridgeParams p;
        p.seed = 4242;
        p.detailAmpVoxels = 40.0;
        p.slopeBoost = 2.0;   // slope is 0 on a flat grid → factor 1
        p.altitudeBoost = 0.0; // keep amplitude exactly detailAmpVoxels

        // Sample a block of columns; gather mean / extent / bound.
        double sum = 0.0, sumsq = 0.0;
        double maxAbsDev = 0.0;
        int n = 0;
        double lo = 1e30, hi = -1e30;
        for (int wz = 1000; wz < 1100; ++wz) {
            for (int wx = 1000; wx < 1100; ++wx) {
                const double h = sample_height_voxels(flat.data(), cw, ch, 0.0, 0.0, kPitch,
                                                      wx, wz, p);
                const double dev = h - static_cast<double>(base);
                sum += h; sumsq += h * h; ++n;
                if (h < lo) lo = h;
                if (h > hi) hi = h;
                if (std::fabs(dev) > maxAbsDev) maxAbsDev = std::fabs(dev);
            }
        }
        const double mean = sum / n;
        const double var = sumsq / n - mean * mean;
        const double sd = std::sqrt(var > 0.0 ? var : 0.0);

        check(sd > 1.0, "detail presence: std-dev ~0 (no detail variation)");
        check(hi - lo > 1.0, "detail presence: output identical across columns");
        // fbm2d ∈ [-1,1], slope 0, alt off → |dev| must stay within detailAmpVoxels.
        check(maxAbsDev <= p.detailAmpVoxels + 1e-6,
              "detail presence: amplitude exceeded detailAmpVoxels bound");
        // Mean should sit near the flat base (detail is roughly zero-mean).
        check(std::fabs(mean - base) < p.detailAmpVoxels,
              "detail presence: mean drifted far from flat base");
    }

    // -------------------------------------------------------------------------
    // (d) SLOPE KEYING — steep region varies more than flat region.
    // -------------------------------------------------------------------------
    {
        // Left half flat, right half a steep ramp (depends on x only → gz=0).
        const int cw = 16, ch = 16;
        std::vector<float> grid(cw * ch);
        for (int z = 0; z < ch; ++z) {
            for (int x = 0; x < cw; ++x) {
                float h;
                if (x < 8) h = 500.0f;                       // flat plateau
                else       h = 500.0f + 400.0f * (x - 8);    // steep: 400 vox/pixel
                grid[z * cw + x] = h;
            }
        }

        DetailBridgeParams pOn;
        pOn.seed = 77;
        pOn.detailAmpVoxels = 40.0;
        pOn.slopeBoost = 2.0;
        pOn.altitudeBoost = 0.0; // isolate slope keying from altitude keying

        DetailBridgeParams pOff = pOn;
        pOff.detailAmpVoxels = 0.0; // pure macro, to subtract out

        // Compute variance of the ISOLATED detail (= on - off) in each region.
        auto detail_variance = [&](int wx0, int wx1, int wz0, int wz1) {
            double sum = 0.0, sumsq = 0.0; int n = 0;
            for (int wz = wz0; wz < wz1; ++wz) {
                for (int wx = wx0; wx < wx1; ++wx) {
                    const double on  = sample_height_voxels(grid.data(), cw, ch, 0.0, 0.0,
                                                            kPitch, wx, wz, pOn);
                    const double off = sample_height_voxels(grid.data(), cw, ch, 0.0, 0.0,
                                                            kPitch, wx, wz, pOff);
                    const double d = on - off;
                    sum += d; sumsq += d * d; ++n;
                }
            }
            const double m = sum / n;
            const double v = sumsq / n - m * m;
            return v > 0.0 ? v : 0.0;
        };

        // Flat region: around coarse pixel x≈3 (worldX ≈ 900). Steep region: x≈12.
        const double varFlat  = detail_variance(800,  1000, 800, 1000);
        const double varSteep = detail_variance(3500, 3700, 800, 1000);

        check(varFlat > 0.0, "slope keying: flat region produced no detail");
        check(varSteep > 2.0 * varFlat,
              "slope keying: steep region not noticeably rougher than flat");
        // Report the ratio for visibility.
        std::printf("  slope keying: varFlat=%.3f varSteep=%.3f ratio=%.2fx\n",
                    varFlat, varSteep, (varFlat > 0.0 ? varSteep / varFlat : 0.0));
    }

    // -------------------------------------------------------------------------
    if (g_fails == 0) {
        std::printf("test_tdiff_detail: ALL PASS "
                    "(determinism + macro fidelity + detail presence + slope keying)\n");
        return 0;
    }
    std::printf("test_tdiff_detail: %d FAILURE(S)\n", g_fails);
    return 1;
}
