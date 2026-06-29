// test_tdiff_streamsource.cpp — proves the detail-bridge sampler is SEAMLESS
// across region-tile boundaries. This is THE correctness claim for streaming an
// infinite world out of finite, tile-by-tile coarse grids: a world column must
// get the SAME ground height no matter which tile happens to be "responsible"
// for it, or the player sees a cliff/crack at every tile seam.
//
// The thing under test is mira::tdiff::sample_height_voxels (Core/Tdiff/
// DetailBridge.h). Two facts about it make seamlessness POSSIBLE:
//
//   * The fractal DETAIL is keyed to WORLD coordinates (it feeds worldX*freq,
//     worldZ*freq straight into fbm2d). It is not tile-local, so the same world
//     column always gets the same detail wobble — automatically continuous.
//
//   * The smooth MACRO height is a Catmull-Rom bicubic of the coarse grid. To
//     evaluate a column it reaches a 4x4 footprint of coarse pixels (ix-1..ix+2)
//     plus a +/-1 central-difference for the slope key. So a tile can only
//     reproduce a neighbour's height NEAR the seam if it actually STORES those
//     neighbouring coarse pixels — i.e. each tile must carry a small APRON
//     (halo) of its neighbours' values. That is exactly how real seamless
//     streaming works, and it is what we model here.
//
// If a tile had NO apron, the 4x4/slope stencil near the edge would fall off the
// grid and CLAMP to the border (flat) instead of reading the neighbour's real
// values — and the two tiles would disagree at the seam. That would be a genuine
// discontinuity, and this test would catch it rather than hide it.
//
// Checks (each prints PASS/FAIL; main returns 0 only if all pass):
//   (1) SEAM CONTINUITY — two adjacent tiles A|B carved from ONE continuous
//       coarse field (with apron overlap), sampled with identical params, agree
//       to within a tight tolerance for every world column crossing the seam.
//   (2) SAMPLER DETERMINISM — same (world coord, params) gives bit-identical
//       output across repeated calls, AND is independent of which tile's
//       origin/grid offset produced it (world-positioned, not tile-local).
//   (3) CLAMP / DEGRADE — sampling well outside a tile's coarse grid clamps to
//       the border and returns a FINITE height (never NaN / garbage).
//
// Mirrors test_tdiff_detail.cpp: own main(), prints "ALL PASS", returns 0/nonzero.
// Discovered + run by build.sh:  ./build.sh tdiff_streamsource

#include "Core/Tdiff/DetailBridge.h"

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <vector>
#include <cmath>

using mira::tdiff::DetailBridgeParams;
using mira::tdiff::sample_height_voxels;

static int g_fails = 0;

// Report-don't-abort assert helpers (so we see EVERY failure in one run).
static void check(bool cond, const char* msg) {
    if (!cond) { std::printf("  FAIL: %s\n", msg); ++g_fails; }
}

// Exact float64 bit comparison (determinism must be bit-identical, not "close").
static uint64_t f64bits(double d) {
    uint64_t b; std::memcpy(&b, &d, sizeof(b)); return b;
}

// Scale constant: 30 m/px * 10 vox/m = 300 voxels per coarse pixel.
static const double kPitch = 300.0;

// -----------------------------------------------------------------------------
// THE shared continuous coarse field. Both tiles are filled from this ONE
// function, evaluated at GLOBAL coarse-pixel coordinates, so wherever two tiles
// overlap they hold byte-identical values — the precondition for a seamless
// stream. It is deliberately non-flat in BOTH axes (so the bicubic actually
// curves and the slope key is non-zero), and smooth (so neighbouring tiles
// genuinely share structure rather than noise).
// Returns a height in voxels.
// -----------------------------------------------------------------------------
static float coarse_field(int globalPixelX, int globalPixelZ) {
    const double gx = static_cast<double>(globalPixelX);
    const double gz = static_cast<double>(globalPixelZ);
    return static_cast<float>(
          800.0
        + 120.0 * std::sin(0.30 * gx)          // rolling hills in x
        +  90.0 * std::cos(0.21 * gz)          // rolling hills in z
        +  18.0 * gx                            // an overall +x tilt (real slope)
        +  40.0 * std::sin(0.11 * (gx + gz)));  // diagonal structure
}

int main() {
    // =========================================================================
    // Tile layout. Two tiles laid on ONE global coarse grid, side by side in +X.
    //
    //   Each tile "owns" a kCore x kCore block of global coarse pixels, but the
    //   array it stores is padded by kApron pixels on every side (the halo of
    //   neighbour values). Tile A owns global pixels [0,kCore); tile B owns
    //   [kCore, 2*kCore). Their stored grids therefore OVERLAP in the apron band
    //   straddling the seam — which is precisely the region a column can be
    //   sampled from EITHER tile.
    //
    //   originVoxelX is the world voxel of the stored grid's pixel (0,0) centre,
    //   i.e. (firstGlobalPixelStored) * kPitch. Because both grids are filled
    //   from coarse_field() at the SAME global indices, a column inside the
    //   overlap maps to identical (global pixel, fractional offset) in both —
    //   so the bicubic/slope math is bit-for-bit identical.
    // =========================================================================
    const int kCore  = 16;   // each tile owns 16x16 coarse pixels (= 480 m square)
    const int kApron = 4;    // halo width; >= 2 covers the 4x4 bicubic + slope reach
    const int kGW    = kCore + 2 * kApron; // stored grid width  (24)
    const int kGH    = kCore + 2 * kApron; // stored grid height (24)

    // Global pixel index of each stored grid's pixel (0,0):
    const int aStartX = 0      - kApron;   // tile A grid covers global x [-4, 20)
    const int bStartX = kCore  - kApron;   // tile B grid covers global x [12, 36)
    const int startZ  = 0      - kApron;   // both share z range          [-4, 20)

    // World voxel of each grid's pixel-(0,0) centre.
    const double aOriginX = aStartX * kPitch; // -1200
    const double bOriginX = bStartX * kPitch; //  3600
    const double originZ  = startZ  * kPitch; // -1200

    // Build both tiles from the shared field.
    std::vector<float> tileA(static_cast<size_t>(kGW) * kGH);
    std::vector<float> tileB(static_cast<size_t>(kGW) * kGH);
    for (int lz = 0; lz < kGH; ++lz) {
        for (int lx = 0; lx < kGW; ++lx) {
            const int gz = startZ + lz;
            tileA[static_cast<size_t>(lz) * kGW + lx] = coarse_field(aStartX + lx, gz);
            tileB[static_cast<size_t>(lz) * kGW + lx] = coarse_field(bStartX + lx, gz);
        }
    }

    // ONE param set for both tiles. Detail is ON (so we prove the full macro +
    // slope-keyed fBm stack is seamless, not just the smooth part). Detail is
    // world-positioned, so identical params => identical detail per world column.
    DetailBridgeParams p;
    p.seed            = 20260629;
    p.detailAmpVoxels = 40.0;
    p.octaves         = 4;
    p.detailFreq      = 0.01;
    p.slopeBoost      = 2.0;
    p.altitudeBoost   = 0.0; // keep it simple; altitude keying is orthogonal here

    // The seam: the world-X boundary between tile A's owned block and tile B's.
    const int seamX = kCore * static_cast<int>(kPitch); // 16 * 300 = 4800

    // =========================================================================
    // (1) SEAM CONTINUITY — the important one.
    //
    // For a line of world columns crossing the A|B seam, sample each column once
    // using tile A's grid+georef and once using tile B's grid+georef, and assert
    // they agree. We restrict the sweep to +/-1.5 coarse pixels around the seam:
    // there every column's 4x4/slope stencil lands entirely inside BOTH stored
    // grids (real apron data, no clamping), so a correct sampler MUST return the
    // same height from either tile. The tolerance is tiny (1e-6 voxel) because
    // the underlying math is identical doubles — we expect essentially exact
    // agreement, far under the "1 voxel = no visible cliff" bar.
    // =========================================================================
    {
        const double kSeamTol = 1e-6;  // voxels; ~exact. (1 voxel = 10 cm = the cliff bar.)
        const int wxLo = seamX - 450;  // -1.5 coarse pixels
        const int wxHi = seamX + 450;  // +1.5 coarse pixels
        // worldZ values inside the owned core so the z-stencil stays in the apron.
        const int zProbes[] = { 1500, 2400, 3300 }; // global pz ~ 5, 8, 11

        double maxDiff = 0.0;
        int    worstX = 0, worstZ = 0;
        int    samples = 0;
        for (int wz : zProbes) {
            for (int wx = wxLo; wx <= wxHi; wx += 7) {
                const double hA = sample_height_voxels(
                    tileA.data(), kGW, kGH, aOriginX, originZ, kPitch, wx, wz, p);
                const double hB = sample_height_voxels(
                    tileB.data(), kGW, kGH, bOriginX, originZ, kPitch, wx, wz, p);
                const double diff = std::fabs(hA - hB);
                if (diff > maxDiff) { maxDiff = diff; worstX = wx; worstZ = wz; }
                ++samples;
            }
        }

        std::printf("  seam continuity: %d columns swept across x=%d; "
                    "max|hA-hB|=%.3e voxels (worst @ wx=%d wz=%d)\n",
                    samples, seamX, maxDiff, worstX, worstZ);

        check(maxDiff <= kSeamTol,
              "seam continuity: tiles A and B DISAGREE at the seam (real cliff!)");
        // Independent sanity: a healthy field varies a lot across this span, so a
        // ~0 diff means "genuinely identical", not "both returned a constant".
        {
            const double hLeft  = sample_height_voxels(
                tileA.data(), kGW, kGH, aOriginX, originZ, kPitch, wxLo, 2400, p);
            const double hRight = sample_height_voxels(
                tileB.data(), kGW, kGH, bOriginX, originZ, kPitch, wxHi, 2400, p);
            check(std::fabs(hRight - hLeft) > 1.0,
                  "seam continuity: field is suspiciously flat (test not meaningful)");
        }
    }

    // =========================================================================
    // (2) SAMPLER DETERMINISM — world-positioned, repeatable.
    //
    //   (a) Repeated calls with identical args are BIT-identical.
    //   (b) A column in the overlap gives a BIT-identical height whether tile A
    //       (origin -1200) or tile B (origin 3600) produced it: the answer is a
    //       function of WORLD position + params, not of tile origin offset.
    // =========================================================================
    {
        const int wx = seamX;     // dead on the seam, inside both grids' apron
        const int wz = 2400;

        // (a) repeatability
        const double r1 = sample_height_voxels(
            tileA.data(), kGW, kGH, aOriginX, originZ, kPitch, wx, wz, p);
        const double r2 = sample_height_voxels(
            tileA.data(), kGW, kGH, aOriginX, originZ, kPitch, wx, wz, p);
        check(f64bits(r1) == f64bits(r2),
              "determinism: repeated identical call differs");

        // (b) origin-independence (bit-identical across the two tiles)
        const double fromA = r1;
        const double fromB = sample_height_voxels(
            tileB.data(), kGW, kGH, bOriginX, originZ, kPitch, wx, wz, p);
        check(f64bits(fromA) == f64bits(fromB),
              "determinism: same world column differs by tile origin (not world-positioned)");
        std::printf("  determinism: seam column h=%.6f voxels identical from A and B "
                    "(bits %s)\n", fromA,
                    f64bits(fromA) == f64bits(fromB) ? "equal" : "DIFFER");

        // Bonus: a THIRD georef (a shifted sub-window holding the same global
        // pixels around this column) must also agree — proving it is purely the
        // world coordinate that matters, not any particular tiling.
        {
            // A 12x12 window centred so it still covers the column's stencil.
            const int subStartX = 16 - 6 - kApron + kApron; // == 16-6 = 10 (global)
            const int subStartZ = 8  - 6;                   // global pz 2
            const int subW = 12, subH = 12;
            std::vector<float> sub(static_cast<size_t>(subW) * subH);
            for (int lz = 0; lz < subH; ++lz)
                for (int lx = 0; lx < subW; ++lx)
                    sub[static_cast<size_t>(lz) * subW + lx] =
                        coarse_field(subStartX + lx, subStartZ + lz);
            const double subOriginX = subStartX * kPitch;
            const double subOriginZ = subStartZ * kPitch;
            const double fromSub = sample_height_voxels(
                sub.data(), subW, subH, subOriginX, subOriginZ, kPitch, wx, wz, p);
            check(f64bits(fromSub) == f64bits(fromA),
                  "determinism: shifted sub-window georef gave a different height");
        }
    }

    // =========================================================================
    // (3) CLAMP / DEGRADE — off-grid reads stay finite (border-clamp, no NaN).
    //
    // Stream loaders DO occasionally ask a tile for a column far outside its
    // coarse footprint (prefetch slop, edge-of-world, a missing neighbour). The
    // sampler must clamp to the border and return a usable finite number, never
    // NaN/Inf, or the mesher writes garbage geometry.
    // =========================================================================
    {
        const int kBig = 1000000; // ~1000 km out, vastly beyond the 24-pixel grid
        const int offProbes[][2] = {
            { -kBig,      2400 },   // far -X
            {  kBig,      2400 },   // far +X
            {  seamX,    -kBig },   // far -Z
            {  seamX,     kBig },   // far +Z
            { -kBig,     -kBig },   // far corner
            {  kBig,      kBig },   // far corner
        };
        bool allFinite = true;
        for (auto& pr : offProbes) {
            const double h = sample_height_voxels(
                tileA.data(), kGW, kGH, aOriginX, originZ, kPitch, pr[0], pr[1], p);
            if (!std::isfinite(h)) {
                std::printf("  FAIL: off-grid (%d,%d) -> non-finite %.6f\n",
                            pr[0], pr[1], h);
                allFinite = false;
            }
        }
        check(allFinite, "clamp/degrade: off-grid read produced NaN/Inf");

        // Degenerate inputs must degrade gracefully to 0 (the header's contract),
        // not crash or NaN.
        const double hNull = sample_height_voxels(
            nullptr, kGW, kGH, aOriginX, originZ, kPitch, seamX, 2400, p);
        check(std::isfinite(hNull) && hNull == 0.0,
              "clamp/degrade: null grid did not return finite 0");
        std::printf("  clamp/degrade: 6 off-grid corners finite + null-grid -> 0.0\n");
    }

    // =========================================================================
    if (g_fails == 0) {
        std::printf("test_tdiff_streamsource: ALL PASS "
                    "(seam continuity + determinism + clamp/degrade)\n");
        return 0;
    }
    std::printf("test_tdiff_streamsource: %d FAILURE(S)\n", g_fails);
    return 1;
}
