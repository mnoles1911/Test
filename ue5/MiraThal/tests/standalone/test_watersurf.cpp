// test_watersurf.cpp — standalone harness for the water surface mesher
// (Core/WaterSurfaceMesher.h).
//   cd tests/standalone && ./build.sh watersurf
//
// Runs under clang (no Unreal). Asserts the water-meshing CONTRACT, not pixels:
//   * a full (level 8) surface cell -> one sloped-but-flat top (all corners at
//     y+1.0) + 4 side quads against air; everything in the Water section.
//   * a submerged cell (water directly above) -> NO top quad.
//   * two adjacent cells of different level (8 & 4) -> the SHARED-edge top corners
//     blend to a height strictly between 0.5 and 1.0 (proving the slope).
//   * water-vs-air side emits; water-vs-water side is culled.
//   * an empty slab -> zero quads.
//   * the solid sections (Opaque/Cutout/Flora) stay empty — water lives alone.
//
// Prints "[watersurf] PASS" / "[watersurf] FAIL"; returns 0 on success, 1 on any
// failure (matches the other tests/standalone harnesses).

#include <cstdio>
#include <cmath>

#include "Core/WaterSurfaceMesher.h"
#include "Core/VoxelChunk.h"
#include "Core/MeshTypes.h"
#include "Core/WaterByteCodec.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

static bool approx(float a, float b) { return std::fabs(a - b) < 1e-5f; }

using namespace mira;

static int water_quads (const MeshBuffers& m) { return m.section(FaceClass::Water ).quad_count(); }
static int opaque_quads(const MeshBuffers& m) { return m.section(FaceClass::Opaque).quad_count(); }
static int cutout_quads(const MeshBuffers& m) { return m.section(FaceClass::Cutout).quad_count(); }
static int flora_quads (const MeshBuffers& m) { return m.section(FaceClass::Flora ).quad_count(); }

// Set a WATER byte at CHUNK-LOCAL coords [0..31] into an apron'd slab (+APRON).
static void set_water_local(DenseGrid& slab, int x, int y, int z, int level) {
    const int byte = WaterByteCodec::pack(level, /*source=*/false, WaterByteCodec::DIR_STILL);
    slab.set_water(x + APRON, y + APRON, z + APRON, static_cast<uint8_t>(byte));
}

// Find the FIRST +Y (top) quad in the Water section; return its base vertex index
// (the 00 corner) via out_v, or -1 if none. Quads are 4 verts each, in order.
static int find_top_quad(const MeshBuffers& m) {
    const MeshSection& sec = m.section(FaceClass::Water);
    for (size_t v = 0; v < sec.vertices.size(); v += 4) {
        if (approx(sec.vertices[v].ny, 1.0f)) return static_cast<int>(v);
    }
    return -1;
}

// Count quads in the Water section whose normal matches the given axis component.
static int count_quads_with_normal(const MeshBuffers& m, float nx, float ny, float nz) {
    const MeshSection& sec = m.section(FaceClass::Water);
    int n = 0;
    for (size_t v = 0; v < sec.vertices.size(); v += 4) {
        if (approx(sec.vertices[v].nx, nx) &&
            approx(sec.vertices[v].ny, ny) &&
            approx(sec.vertices[v].nz, nz)) ++n;
    }
    return n;
}

int main() {
    // ---------------------------------------------------------------------
    // 1. A single FULL (level 8) water cell with air above -> one top quad (all
    //    4 corners at y_local + 1.0) + 4 side quads against air. Water-only.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_water_local(slab, 5, 5, 5, WaterByteCodec::MAX_LEVEL); // level 8
        MeshBuffers m;
        append_water_surface(slab, m);

        CHECK(water_quads(m) == 5, "full water cell -> 1 top + 4 side = 5 water quads");
        CHECK(opaque_quads(m) == 0 && cutout_quads(m) == 0 && flora_quads(m) == 0,
              "full water cell -> Opaque/Cutout/Flora sections empty");

        // The top quad: all 4 corners at height y_local + 1.0 (y_local = 5 -> 6.0).
        const int tv = find_top_quad(m);
        CHECK(tv >= 0, "full water cell -> a +Y top quad exists");
        if (tv >= 0) {
            const MeshSection& sec = m.section(FaceClass::Water);
            bool all_full = true;
            for (int k = 0; k < 4; ++k)
                if (!approx(sec.vertices[tv + k].py, 6.0f)) all_full = false;
            CHECK(all_full, "full cell top: all 4 corners at y_local+1.0 (=6.0)");
        }

        // Exactly one quad per +X/-X/+Z/-Z side direction.
        CHECK(count_quads_with_normal(m,  1, 0, 0) == 1, "full cell: one +X side quad");
        CHECK(count_quads_with_normal(m, -1, 0, 0) == 1, "full cell: one -X side quad");
        CHECK(count_quads_with_normal(m, 0, 0,  1) == 1, "full cell: one +Z side quad");
        CHECK(count_quads_with_normal(m, 0, 0, -1) == 1, "full cell: one -Z side quad");
        CHECK(count_quads_with_normal(m, 0, 1, 0) == 1, "full cell: one +Y top quad");
        CHECK(count_quads_with_normal(m, 0,-1, 0) == 0, "full cell: no -Y bottom quad");

        // A side quad rises from the cell bottom (y=5) to the top (y=6): check +X.
        const MeshSection& sec = m.section(FaceClass::Water);
        for (size_t v = 0; v < sec.vertices.size(); v += 4) {
            if (!approx(sec.vertices[v].nx, 1.0f)) continue;
            float ymin = 1e9f, ymax = -1e9f;
            for (int k = 0; k < 4; ++k) {
                ymin = std::fmin(ymin, sec.vertices[v + k].py);
                ymax = std::fmax(ymax, sec.vertices[v + k].py);
            }
            CHECK(approx(ymin, 5.0f) && approx(ymax, 6.0f),
                  "+X side spans cell bottom (5) to top (6)");
            break;
        }
    }

    // ---------------------------------------------------------------------
    // 2. A SUBMERGED water cell (water directly above) emits NO top quad.
    //    Stack two full cells; the LOWER one is submerged.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_water_local(slab, 8, 8, 8, WaterByteCodec::MAX_LEVEL); // lower (submerged)
        set_water_local(slab, 8, 9, 8, WaterByteCodec::MAX_LEVEL); // upper (surface)
        MeshBuffers m;
        append_water_surface(slab, m);

        // Only ONE top quad total (the upper cell's); the lower cell has none.
        CHECK(count_quads_with_normal(m, 0, 1, 0) == 1, "stacked water: exactly one top (upper cell)");

        // That single top sits at the UPPER cell's top: y_local 9 + 1 = 10.0.
        const int tv = find_top_quad(m);
        CHECK(tv >= 0, "stacked water: a top quad exists");
        if (tv >= 0) {
            const MeshSection& sec = m.section(FaceClass::Water);
            CHECK(approx(sec.vertices[tv].py, 10.0f), "stacked water: top at upper cell top (y=10)");
        }
    }

    // ---------------------------------------------------------------------
    // 3. Two adjacent cells, level 8 and level 4, air above both. The shared-edge
    //    top corners blend to a height STRICTLY between 0.5 and 1.0 (the slope).
    //    Layout: full cell at x=10, half cell (level 4) at x=11, same y=6,z=6.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_water_local(slab, 10, 6, 6, 8); // full
        set_water_local(slab, 11, 6, 6, 4); // half (level 4 -> 0.5)
        MeshBuffers m;
        append_water_surface(slab, m);

        // The shared edge is the plane x=11 (between cell 10's +X face and cell 11).
        // Find the level-4 cell's (x=11) TOP quad and inspect its corner heights.
        // The cell-11 top spans x in [11,12]; its corners at x=11 are the SHARED
        // edge (blend of the full cell-10 and half cell-11), corners at x=12 touch
        // only cell-11 (and air beyond) so are lower.
        const MeshSection& sec = m.section(FaceClass::Water);
        bool checked_shared = false, checked_outer = false;
        for (size_t v = 0; v < sec.vertices.size(); v += 4) {
            if (!approx(sec.vertices[v].ny, 1.0f)) continue; // top quads only
            for (int k = 0; k < 4; ++k) {
                const MeshVertex& vert = sec.vertices[v + k];
                // local height above the cell bottom (y_local = 6).
                const float h = vert.py - 6.0f;
                if (approx(vert.px, 11.0f)) {
                    // Shared edge between full(1.0) and half(0.5) columns.
                    // Corner touches columns: cell-10 (full=1.0) and cell-11 (0.5);
                    // diagonal/edge neighbours in Z are air. Blend avg of {1.0,0.5}
                    // = 0.75 -> strictly between 0.5 and 1.0.
                    CHECK(h > 0.5f + 1e-4f && h < 1.0f - 1e-4f,
                          "shared-edge top corner blends strictly between 0.5 and 1.0");
                    CHECK(approx(h, 0.75f), "shared-edge corner = avg(1.0,0.5) = 0.75");
                    checked_shared = true;
                } else if (approx(vert.px, 12.0f)) {
                    // Outer edge of the half cell: only cell-11 is water there.
                    CHECK(approx(h, 0.5f), "outer edge of half cell stays at its own 0.5");
                    checked_outer = true;
                }
            }
        }
        CHECK(checked_shared, "found shared-edge top corner to verify the slope");
        CHECK(checked_outer, "found outer half-cell top corner to verify it stays low");
    }

    // ---------------------------------------------------------------------
    // 4. Water-vs-water side culling: a level-8 cell whose +X neighbour is AIR
    //    has a +X side; whose +X neighbour is WATER has NONE.
    // ---------------------------------------------------------------------
    {
        // 4a. +X neighbour is air -> +X side exists.
        DenseGrid slab = make_mesh_slab();
        set_water_local(slab, 15, 10, 10, 8);
        MeshBuffers m;
        append_water_surface(slab, m);
        CHECK(count_quads_with_normal(m, 1, 0, 0) == 1, "lone cell: +X side vs air emitted");
    }
    {
        // 4b. +X neighbour is water -> the shared +X side is culled.
        DenseGrid slab = make_mesh_slab();
        set_water_local(slab, 15, 10, 10, 8);
        set_water_local(slab, 16, 10, 10, 8); // +X neighbour is water
        MeshBuffers m;
        append_water_surface(slab, m);
        // Cell 15's +X side AND cell 16's -X side are both interior -> culled.
        // Remaining X sides: cell 15's -X (1) and cell 16's +X (1) = 2 total in X.
        CHECK(count_quads_with_normal(m, 1, 0, 0) == 1,
              "two-wide body: only the outer +X (cell 16) survives, interior +X culled");
        CHECK(count_quads_with_normal(m, -1, 0, 0) == 1,
              "two-wide body: only the outer -X (cell 15) survives, interior -X culled");
        // Both cells are surface cells -> 2 tops.
        CHECK(count_quads_with_normal(m, 0, 1, 0) == 2, "two-wide body: each cell tops out (2 tops)");
    }

    // ---------------------------------------------------------------------
    // 5. No water in the slab -> zero quads in every section.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        MeshBuffers m;
        append_water_surface(slab, m);
        CHECK(m.total_quads() == 0, "empty slab -> zero quads");
        CHECK(water_quads(m) == 0, "empty slab -> empty Water section");
    }

    // ---------------------------------------------------------------------
    // 6. Apron safety: water placed at the very edge of the inner chunk (x=31)
    //    still meshes (its +X neighbour read reaches slab index 33, in-bounds) and
    //    only INNER cells emit (apron-only water never produces geometry).
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_water_local(slab, 31, 10, 10, 8); // last inner cell on +X edge
        MeshBuffers m;
        append_water_surface(slab, m);
        CHECK(water_quads(m) == 5, "edge inner cell still meshes (1 top + 4 sides)");
    }
    {
        // Water living ONLY in the apron shell (chunk-local -1) emits nothing,
        // because we only iterate inner cells [0..31].
        DenseGrid slab = make_mesh_slab();
        // slab index 0 == chunk-local -1 (the apron). Write raw.
        const int byte = WaterByteCodec::pack(8, false, WaterByteCodec::DIR_STILL);
        slab.set_water(0, 10, 10, static_cast<uint8_t>(byte));
        MeshBuffers m;
        append_water_surface(slab, m);
        CHECK(water_quads(m) == 0, "apron-only water emits nothing (inner cells only)");
    }

    std::printf("[watersurf] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
