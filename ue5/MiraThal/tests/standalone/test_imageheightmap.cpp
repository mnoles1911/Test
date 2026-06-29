// test_imageheightmap.cpp — parity harness for Core/ImageHeightmap.h and the
// HeightmapGenerator EXR-override seam (M3 heightmap import).
//   cd tests/standalone && ./build.sh imageheightmap
//
// Asserts the CONTRACT an imported Gaea EXR must satisfy (not real pixels — we
// feed a synthetic float grid so no .exr decoder is needed headless):
//   * exact pixel-centre reads return the stored value;
//   * bilinear blend halfway between two pixels is their average;
//   * off-map reads clamp to the edge (flat extension, no wrap/explode);
//   * georef: voxels_per_pixel + origin map world voxels to the right pixel;
//   * set_centered_extent centres a square map on the world origin;
//   * vertical map: ground_y = base + value*scale, floored;
//   * flip_z mirrors rows;
//   * the GENERATOR override: set_height_source makes compute_ground_y read the
//     image, and the banding (resolve_column / material_at) re-derives off it —
//     a column whose imported height dips below sea level reports below_sea, a
//     high column bands grass-over-dirt-over-stone at the imported surface.
//
// Prints "[imageheightmap] PASS/FAIL"; returns 0 on success, 1 on any failure.

#include <cstdio>
#include <cmath>
#include <vector>

#include "Core/ImageHeightmap.h"
#include "Core/HeightmapGenerator.h"
#include "Core/MaterialIds.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;

static bool approx(double a, double b, double eps = 1e-4) { return std::fabs(a - b) <= eps; }

// Build a tiny image with an explicit value grid (row-major, width*height).
static ImageHeightmap make_grid(int w, int h, std::vector<float> vals) {
    ImageHeightmap hm;
    hm.width = w; hm.height = h; hm.data = std::move(vals);
    return hm;
}

int main() {
    // ---------------------------------------------------------------------
    // 1. Exact pixel-centre reads + horizontal bilinear blend.
    //    2x2 grid, 1 voxel/pixel, origin at (0,0):
    //      (0,0)=0   (1,0)=10
    //      (0,1)=20  (1,1)=30
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_grid(2, 2, {0.f, 10.f, 20.f, 30.f});
        hm.voxels_per_pixel = 1.0;
        hm.origin_voxel_x = 0.0; hm.origin_voxel_z = 0.0;

        CHECK(hm.valid(), "2x2 grid is valid");
        CHECK(approx(hm.sample_value(0, 0), 0.0),  "pixel (0,0) reads 0");
        CHECK(approx(hm.sample_value(1, 0), 10.0), "pixel (1,0) reads 10");
        CHECK(approx(hm.sample_value(0, 1), 20.0), "pixel (0,1) reads 20");
        CHECK(approx(hm.sample_value(1, 1), 30.0), "pixel (1,1) reads 30");

        // Halfway along +X between (0,0)=0 and (1,0)=10 -> 5.
        CHECK(approx(hm.sample_value(0.5, 0.0), 5.0), "bilinear midpoint X = 5");
        // Halfway along +Z between (0,0)=0 and (0,1)=20 -> 10.
        CHECK(approx(hm.sample_value(0.0, 0.5), 10.0), "bilinear midpoint Z = 10");
        // Centre of the 2x2: mean of all four = 15.
        CHECK(approx(hm.sample_value(0.5, 0.5), 15.0), "bilinear centre = 15");
    }

    // ---------------------------------------------------------------------
    // 2. Off-map reads clamp to the edge (no wrap, no NaN).
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_grid(2, 2, {0.f, 10.f, 20.f, 30.f});
        hm.voxels_per_pixel = 1.0;
        CHECK(approx(hm.sample_value(-50, -50), 0.0),  "far -X/-Z clamps to corner (0)");
        CHECK(approx(hm.sample_value( 50,  50), 30.0), "far +X/+Z clamps to corner (30)");
        CHECK(approx(hm.sample_value( 50,   0), 10.0), "far +X edge clamps to (1,0)=10");
    }

    // ---------------------------------------------------------------------
    // 3. Georef: pixel pitch + origin place world voxels on the right pixel.
    //    Same 2x2 grid but 10 voxels/pixel and origin (-5,-5): the pixel
    //    centres sit at world voxels -5 and +5.
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_grid(2, 2, {0.f, 10.f, 20.f, 30.f});
        hm.voxels_per_pixel = 10.0;
        hm.origin_voxel_x = -5.0; hm.origin_voxel_z = -5.0;
        CHECK(approx(hm.sample_value(-5, -5), 0.0),  "world (-5,-5) -> pixel (0,0)=0");
        CHECK(approx(hm.sample_value( 5, -5), 10.0), "world ( 5,-5) -> pixel (1,0)=10");
        CHECK(approx(hm.sample_value( 0, -5), 5.0),  "world ( 0,-5) -> midpoint 5");
    }

    // ---------------------------------------------------------------------
    // 4. set_centered_extent: a square map centred on the world origin.
    //    4 px over 40 voxels -> 10 vox/px, origin -20.
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_grid(4, 4, std::vector<float>(16, 0.f));
        hm.set_centered_extent(40.0, 40.0);
        CHECK(approx(hm.voxels_per_pixel, 10.0), "centered extent: 40/4 = 10 vox/px");
        CHECK(approx(hm.origin_voxel_x, -20.0),  "centered extent: origin_x = -20");
        CHECK(approx(hm.origin_voxel_z, -20.0),  "centered extent: origin_z = -20");
    }

    // ---------------------------------------------------------------------
    // 5. Vertical mapping: ground_y = base + value*scale, floored.
    //    value 0.5, scale 1000, base 120 -> 620.
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_grid(1, 1, {0.5f});
        hm.vertical_scale_voxels = 1000.0;
        hm.vertical_base_voxels  = 120.0;
        CHECK(hm.height_voxels_at(0, 0) == 620, "value 0.5 * 1000 + 120 = 620");

        ImageHeightmap hm2 = make_grid(1, 1, {0.1234f});
        hm2.vertical_scale_voxels = 10.0; hm2.vertical_base_voxels = 0.0;
        // 0.1234*10 = 1.234 -> floor 1.
        CHECK(hm2.height_voxels_at(0, 0) == 1, "floors toward the surface voxel");
    }

    // ---------------------------------------------------------------------
    // 6. flip_z mirrors image rows (Gaea row order vs world +Z).
    //    2x2: row0=(0,10) row1=(20,30). With flip_z, world +Z reads row0 last.
    // ---------------------------------------------------------------------
    {
        ImageHeightmap hm = make_grid(2, 2, {0.f, 10.f, 20.f, 30.f});
        hm.voxels_per_pixel = 1.0; hm.flip_z = true;
        // flip maps pz: world z=0 -> row (height-1 - 0) = row1; z=1 -> row0.
        CHECK(approx(hm.sample_value(0, 0), 20.0), "flip_z: world z=0 reads bottom row");
        CHECK(approx(hm.sample_value(0, 1), 0.0),  "flip_z: world z=1 reads top row");
    }

    // ---------------------------------------------------------------------
    // 7. Generator override: the imported height drives compute_ground_y, and
    //    the banding / water flag re-derive off it. A flat 4x4 image at value
    //    1.0, scale 100, base 0 -> ground_y 100 everywhere (above the default
    //    sea level 120? no — 100 < 120, so columns are below_sea). Use base 200
    //    for a dry highland column to check grass/dirt/stone banding.
    // ---------------------------------------------------------------------
    {
        // Dry highland: flat value 1.0, base 200, scale 0 -> ground_y = 200.
        ImageHeightmap dry = make_grid(4, 4, std::vector<float>(16, 1.0f));
        dry.set_centered_extent(40.0, 40.0);
        dry.vertical_scale_voxels = 0.0;   // flat
        dry.vertical_base_voxels  = 200.0; // well above sea (120) and beach (74)

        HeightmapGenerator gen;
        gen.set_seed(1337);
        CHECK(!gen.height_source_active(), "no source by default");
        gen.set_height_source(&dry);
        CHECK(gen.height_source_active(), "source active once set");

        CHECK(gen.compute_ground_y(0, 0) == 200, "imported flat height -> ground_y 200");
        CHECK(gen.compute_ground_y(7, -3) == 200, "imported height is flat across columns");

        ColumnInfo col = gen.resolve_column(0, 0);
        CHECK(col.ground_y == 200, "resolve_column uses the imported ground_y");
        CHECK(!col.below_sea, "highland column is above sea level");
        CHECK(col.top_id == mat::GRASS, "dry highland tops out as grass");

        // Banding down the column: depth 0 = grass, depth in dirt band = dirt,
        // deeper = stone. grass_thick defaults 1, dirt band +3 -> dirt at depth 1..3.
        CHECK(gen.material_at(0, 200, 0, col) == mat::GRASS, "surface voxel = grass");
        CHECK(gen.material_at(0, 199, 0, col) == mat::DIRT,  "1 below = dirt");
        // Deep band is the stone family (plain stone or its marble-jitter variants).
        const int deep = gen.material_at(0, 196, 0, col);
        CHECK(deep == mat::STONE || deep == mat::STONE_DARK || deep == mat::MARBLE,
              "deep = stone family (stone/dark/marble jitter)");
        CHECK(gen.material_at(0, 201, 0, col) == mat::AIR,   "above surface = air");

        // Clearing the source reverts to the procedural path.
        gen.set_height_source(nullptr);
        CHECK(!gen.height_source_active(), "cleared source reverts to procedural");
    }

    // ---------------------------------------------------------------------
    // 8. Generator override: a submerged column reports below_sea + sand top
    //    (the EXR can carve lakes/oceans the banding then floods).
    // ---------------------------------------------------------------------
    {
        ImageHeightmap low = make_grid(4, 4, std::vector<float>(16, 1.0f));
        low.set_centered_extent(40.0, 40.0);
        low.vertical_scale_voxels = 0.0;
        low.vertical_base_voxels  = 60.0; // below beach (74) and sea (120)

        HeightmapGenerator gen;
        gen.set_seed(1337);
        gen.set_height_source(&low);

        ColumnInfo col = gen.resolve_column(0, 0);
        CHECK(col.ground_y == 60, "submerged column ground_y from EXR");
        CHECK(col.below_sea, "ground below sea level flags below_sea (water fill)");
        CHECK(col.top_id == mat::SAND, "below the beach line tops out as sand");
    }

    std::printf("[imageheightmap] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
