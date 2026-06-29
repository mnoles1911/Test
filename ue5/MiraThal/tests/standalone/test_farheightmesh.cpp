// test_farheightmesh.cpp — parity harness for Core/FarHeightmesh.h (P4 vista mesh).
//   cd tests/standalone && ./build.sh farheightmesh
//
// Asserts the contract of the whole-map heightmesh builder (feeding it a synthetic
// ImageHeightmap + simple callbacks, no real EXR needed):
//   * grid dimensions: grid_n^2 vertices, (grid_n-1)^2 * 2 triangles;
//   * the four corner vertices sit at the heightmap's world extent and read the
//     height/color the callbacks returned there;
//   * a FLAT map -> all vertices at the same height, all normals straight up;
//   * a SLOPED map -> normals tilt the right way (downhill +X => normal leans -X);
//   * colors come from the color callback (palette match);
//   * invalid inputs (grid_n < 2, empty heightmap) return an invalid mesh.
//
// Prints "[farheightmesh] PASS/FAIL"; returns 0 on success, 1 on any failure.

#include <cstdio>
#include <cmath>
#include <vector>

#include "Core/FarHeightmesh.h"
#include "Core/ImageHeightmap.h"
#include "Core/VoxelColor.h"
#include "Core/MaterialIds.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;

static bool approx(double a, double b, double eps = 1e-3) { return std::fabs(a - b) <= eps; }

// A heightmap with a known georef: 2x2 px, 10 vox/px, centred -> extent [-10,10].
static ImageHeightmap make_hm() {
    ImageHeightmap hm;
    hm.width = 2; hm.height = 2; hm.data = {0.f, 0.f, 0.f, 0.f};
    hm.voxels_per_pixel = 10.0;
    hm.origin_voxel_x = -10.0; hm.origin_voxel_z = -10.0;
    return hm;
}

int main() {
    // ---------------------------------------------------------------------
    // 1. Grid dimensions + corner placement + height/color from callbacks.
    //    Flat height = 100; color = grass everywhere.
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_hm();
        const int N = 5;
        auto height = [](int, int) { return 100; };
        auto color  = [](int, int) { return base_color(mat::GRASS); };
        FarHeightmesh m = build_far_heightmesh(hm, N, height, color);

        CHECK(m.valid(), "mesh is valid");
        CHECK(m.grid_n == N, "grid_n preserved");
        CHECK(m.vertex_count() == N * N, "vertex count = grid_n^2");
        CHECK(m.triangle_count() == (N - 1) * (N - 1) * 2, "triangle count = (n-1)^2 * 2");
        CHECK(m.indices.size() == static_cast<size_t>((N - 1) * (N - 1) * 6), "index count = (n-1)^2 * 6");

        // Corner (0,0) sits at world extent min (-10,-10); last at (+10,+10).
        const FarMeshVertex& v00 = m.vertices[0];
        const FarMeshVertex& vNN = m.vertices[N * N - 1];
        CHECK(approx(v00.px, -10.0) && approx(v00.pz, -10.0), "vertex 0 at extent min (-10,-10)");
        CHECK(approx(vNN.px,  10.0) && approx(vNN.pz,  10.0), "last vertex at extent max (10,10)");
        CHECK(approx(v00.py, 100.0), "height from the callback (100)");

        const Rgb8 g = base_color(mat::GRASS);
        CHECK(v00.r == g.r && v00.g == g.g && v00.b == g.b, "color from the callback (grass)");
    }

    // ---------------------------------------------------------------------
    // 2. Flat map -> all equal height, all normals straight up (0,1,0).
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_hm();
        const int N = 6;
        FarHeightmesh m = build_far_heightmesh(hm, N,
            [](int, int) { return 64; },
            [](int, int) { return base_color(mat::STONE); });
        bool flat = true, up = true;
        for (const FarMeshVertex& v : m.vertices) {
            if (!approx(v.py, 64.0)) flat = false;
            if (!(approx(v.nx, 0.0) && approx(v.ny, 1.0) && approx(v.nz, 0.0))) up = false;
        }
        CHECK(flat, "flat map: every vertex at height 64");
        CHECK(up, "flat map: every normal points straight up");
    }

    // ---------------------------------------------------------------------
    // 3. Sloped map (height rises with world X) -> normals lean -X (downhill).
    //    height(wx,wz) = wx  (so dh/dx = +1 => normal.x = -slope < 0).
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_hm();
        const int N = 5;
        FarHeightmesh m = build_far_heightmesh(hm, N,
            [](int wx, int) { return wx; },                 // ramp up toward +X
            [](int, int) { return base_color(mat::GRASS); });
        // Pick an interior vertex (not on the X edge) so central diff is symmetric.
        // Interior column i=2, row j=2 -> index 2*N+2.
        const FarMeshVertex& v = m.vertices[2 * N + 2];
        CHECK(v.nx < -0.5, "uphill-toward-+X slope: normal leans -X");
        CHECK(v.ny > 0.0, "normal still points generally up");
        CHECK(approx(v.nz, 0.0, 1e-2), "no Z slope: normal.z ~ 0");
        // Height at that vertex equals its world X.
        CHECK(approx(v.py, v.px), "sloped height matches world X");
    }

    // ---------------------------------------------------------------------
    // 3b. CONSERVATIVE (always-below) sampling — the poke-through fix.
    //   On a CONVEX synthetic terrain (a smooth ridge), the min-over-footprint
    //   height must be <= the single-point sample at every vertex, must EQUAL it
    //   on a flat map, and must never exceed the true ground at any fine column
    //   inside the vertex's footprint (the no-overshoot invariant).
    // ---------------------------------------------------------------------
    {
        // A convex ridge: height(wx) peaks at wx=0 and falls off as -(wx^2 scaled).
        // Concave-up between samples is the worst case for the coarse mesh bulging.
        auto ridge = [](int wx, int) {
            // Inverted parabola -> convex hilltop; integer voxels.
            const double h = 1000.0 - 0.5 * static_cast<double>(wx) * static_cast<double>(wx) * 0.001;
            return static_cast<int>(std::floor(h));
        };
        auto grass = [](int, int) { return base_color(mat::GRASS); };

        // Use a big map so cells span many voxels (footprint actually scans a range).
        ImageHeightmap hm;
        hm.width = 64; hm.height = 64; hm.data.assign(64 * 64, 0.f);
        hm.voxels_per_pixel = 50.0;          // 3200-voxel span
        hm.set_centered_extent(3200.0, 3200.0);
        const int N = 17;                    // coarse grid -> ~200 vox/cell

        FarHeightmesh single = build_far_heightmesh(hm, N, ridge, grass, /*footprint*/1);
        FarHeightmesh minM   = build_far_heightmesh(hm, N, ridge, grass, /*footprint*/3);
        CHECK(single.valid() && minM.valid(), "both meshes valid");
        CHECK(single.vertex_count() == minM.vertex_count(), "same vertex count");

        // (a) min-over-footprint <= single-sample at EVERY vertex on a convex map.
        bool min_le_single = true;
        // (b) strictly lower at SOME interior vertex (proves the min actually bit).
        bool strictly_lower_somewhere = false;
        for (int k = 0; k < single.vertex_count(); ++k) {
            if (minM.vertices[k].py > single.vertices[k].py + 1e-3f) min_le_single = false;
            if (minM.vertices[k].py < single.vertices[k].py - 1e-3f) strictly_lower_somewhere = true;
        }
        CHECK(min_le_single, "convex: min-over-footprint <= single-sample everywhere");
        CHECK(strictly_lower_somewhere, "convex: min is strictly lower at some vertex");

        // (c) NO-OVERSHOOT INVARIANT: each conservative vertex height must be <= the
        //     true ground at its OWN world point (the chord can only go lower than the
        //     vertices, and each vertex is at/below the real surface there).
        bool no_overshoot = true;
        for (const FarMeshVertex& v : minM.vertices) {
            const int true_ground = ridge(static_cast<int>(std::llround(v.px)),
                                           static_cast<int>(std::llround(v.pz)));
            if (v.py > true_ground + 1e-3f) no_overshoot = false;
        }
        CHECK(no_overshoot, "no-overshoot: every vertex sits at/below true ground");

        // (d) FLAT map: min == single (min of equal values changes nothing).
        ImageHeightmap flat = hm;
        auto level = [](int, int) { return 250; };
        FarHeightmesh fSingle = build_far_heightmesh(flat, N, level, grass, 1);
        FarHeightmesh fMin    = build_far_heightmesh(flat, N, level, grass, 4);
        bool flat_equal = true;
        for (int k = 0; k < fSingle.vertex_count(); ++k) {
            if (!approx(fSingle.vertices[k].py, fMin.vertices[k].py)) flat_equal = false;
        }
        CHECK(flat_equal, "flat map: conservative min equals single-sample");
    }

    // ---------------------------------------------------------------------
    // 4. Invalid inputs -> invalid mesh.
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_hm();
        FarHeightmesh tooSmall = build_far_heightmesh(hm, 1,
            [](int, int) { return 0; }, [](int, int) { return Rgb8{0,0,0}; });
        CHECK(!tooSmall.valid(), "grid_n < 2 -> invalid mesh");

        ImageHeightmap empty; // width/height 0
        FarHeightmesh noHm = build_far_heightmesh(empty, 4,
            [](int, int) { return 0; }, [](int, int) { return Rgb8{0,0,0}; });
        CHECK(!noHm.valid(), "empty heightmap -> invalid mesh");
    }

    std::printf("[farheightmesh] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
