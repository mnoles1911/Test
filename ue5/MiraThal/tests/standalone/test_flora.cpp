// test_flora.cpp — standalone harness for Core/FloraMesher.h
//   cd tests/standalone && ./build.sh flora
//
// Tests the append_flora() contract:
//   * flora ids (24..26) produce the correct cross structure in the Flora section
//   * surface-detail ids (27..28) produce a flat ground quad in the Flora section
//   * non-flora ids (stone, air, water 16) emit nothing
//   * hash3() is deterministic (same input -> same output, different inputs differ)
//   * jitter offsets stay inside the cell's XZ footprint
//   * two grass voxels at different coords produce different vertex positions
//
// QUAD COUNT CONVENTION (matches FloraMesher.h emit_double_sided_quad):
//   Every "visual quad" = 4 unique vertices + 12 indices (double-sided: 2 front
//   tris + 2 back tris). MeshSection::quad_count() = indices.size() / 6.
//   So a single double-sided quad => quad_count() == 2.
//   A grass-blade CROSS = 2 visual quads => 8 verts, 24 indices => quad_count() == 4.
//   A ground quad (pebble/twig) = 1 visual quad => 4 verts, 12 indices => quad_count() == 2.
//
// Prints "[flora   ] PASS" / "[flora   ] FAIL"; returns 0 on success, 1 on failure.

#include <cstdio>
#include <cmath>
#include <cstdint>
#include <limits>

#include "Core/FloraMesher.h"
#include "Core/VoxelChunk.h"
#include "Core/MeshTypes.h"
#include "Core/MaterialIds.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL  %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

static bool approx(float a, float b, float eps = 1e-5f) {
    return std::fabs(a - b) < eps;
}

using namespace mira;

// ---------------------------------------------------------------------------
// Helper: place a voxel at CHUNK-LOCAL coords [0..31] into an apron'd slab.
// (Same pattern as test_mesher.cpp.)
// ---------------------------------------------------------------------------
static void set_local(DenseGrid& slab, int x, int y, int z, uint8_t id) {
    slab.set_type(x + APRON, y + APRON, z + APRON, id);
}

// Convenience accessors for the Flora section.
static int flora_quads  (const MeshBuffers& m) { return m.section(FaceClass::Flora ).quad_count(); }
static int opaque_quads (const MeshBuffers& m) { return m.section(FaceClass::Opaque).quad_count(); }
static int cutout_quads (const MeshBuffers& m) { return m.section(FaceClass::Cutout).quad_count(); }
static int water_quads  (const MeshBuffers& m) { return m.section(FaceClass::Water ).quad_count(); }

int main() {

    // =========================================================================
    // 1. Grass blade (id 24) — cross structure
    //
    // CONVENTION REMINDER:
    //   A cross = 2 double-sided quads.
    //   Each double-sided quad: 4 verts, 12 indices -> quad_count contribution = 2.
    //   Total for a cross: 8 verts, 24 indices, quad_count() == 4.
    // =========================================================================
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 5, 5, 5, static_cast<uint8_t>(mat::GRASS_BLADE_ID));
        MeshBuffers m;
        append_flora(slab, m);

        // Cross geometry should be entirely in the Flora section.
        CHECK(flora_quads(m)  == 4, "grass blade: quad_count == 4 (2 double-sided quads for cross)");
        CHECK(opaque_quads(m) == 0, "grass blade: Opaque section empty");
        CHECK(cutout_quads(m) == 0, "grass blade: Cutout section empty");
        CHECK(water_quads(m)  == 0, "grass blade: Water section empty");

        // Vertex count: 2 visual quads × 4 verts = 8 verts.
        const MeshSection& sec = m.section(FaceClass::Flora);
        CHECK(sec.vertices.size() == 8,  "grass blade: 8 verts (2 quads × 4)");
        CHECK(sec.indices.size()  == 24, "grass blade: 24 indices (2 quads × 12)");

        // Every vertex should have ao == 1.0 (flora is unoccluded).
        bool ao_ok = true;
        for (const auto& v : sec.vertices) ao_ok &= approx(v.ao, 1.0f);
        CHECK(ao_ok, "grass blade: all vertices have ao == 1.0");

        // Vertices should span the full Y height of the cell [5, 6].
        float min_y =  std::numeric_limits<float>::max();
        float max_y = -std::numeric_limits<float>::max();
        for (const auto& v : sec.vertices) {
            if (v.py < min_y) min_y = v.py;
            if (v.py > max_y) max_y = v.py;
        }
        CHECK(approx(min_y, 5.0f), "grass blade: bottom vertex at y == 5.0 (cell floor)");
        CHECK(approx(max_y, 6.0f), "grass blade: top vertex at y == 6.0 (cell top)");
    }

    // =========================================================================
    // 2. Flower red (id 25) — same cross structure as grass blade
    // =========================================================================
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 10, 3, 7, static_cast<uint8_t>(mat::FLOWER_RED_ID));
        MeshBuffers m;
        append_flora(slab, m);

        CHECK(flora_quads(m)  == 4,  "flower red: quad_count == 4 (cross structure)");
        const MeshSection& sec = m.section(FaceClass::Flora);
        CHECK(sec.vertices.size() == 8,  "flower red: 8 verts");
        CHECK(sec.indices.size()  == 24, "flower red: 24 indices");

        // Y span should be [3, 4].
        float min_y =  std::numeric_limits<float>::max();
        float max_y = -std::numeric_limits<float>::max();
        for (const auto& v : sec.vertices) {
            if (v.py < min_y) min_y = v.py;
            if (v.py > max_y) max_y = v.py;
        }
        CHECK(approx(min_y, 3.0f), "flower red: bottom at y == 3.0");
        CHECK(approx(max_y, 4.0f), "flower red: top at y == 4.0");
    }

    // =========================================================================
    // 3. Flower blue (id 26) — cross structure, different atlas UV
    // =========================================================================
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 2, 2, 2, static_cast<uint8_t>(mat::FLOWER_BLUE_ID));
        MeshBuffers m;
        append_flora(slab, m);

        CHECK(flora_quads(m)  == 4, "flower blue: quad_count == 4 (cross)");
        const MeshSection& sec = m.section(FaceClass::Flora);
        CHECK(sec.vertices.size() == 8, "flower blue: 8 verts");
    }

    // =========================================================================
    // 4. Pebble (id 27) — single flat ground quad, normal +Y
    //
    // CONVENTION:
    //   Ground quad = 1 double-sided quad -> 4 verts, 12 indices, quad_count() == 2.
    // =========================================================================
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 8, 8, 8, static_cast<uint8_t>(mat::PEBBLE_ID));
        MeshBuffers m;
        append_flora(slab, m);

        CHECK(flora_quads(m)  == 2,  "pebble: quad_count == 2 (1 double-sided ground quad)");
        CHECK(opaque_quads(m) == 0,  "pebble: Opaque section empty");
        CHECK(water_quads(m)  == 0,  "pebble: Water section empty");

        const MeshSection& sec = m.section(FaceClass::Flora);
        CHECK(sec.vertices.size() == 4,  "pebble: 4 verts");
        CHECK(sec.indices.size()  == 12, "pebble: 12 indices");

        // All vertices should have normal +Y (flat ground quad).
        bool normal_ok = true;
        for (const auto& v : sec.vertices) {
            normal_ok &= approx(v.nx, 0.0f) && approx(v.ny, 1.0f) && approx(v.nz, 0.0f);
        }
        CHECK(normal_ok, "pebble: all vertices have normal (0, +1, 0)");

        // All vertices should be close to y = 8.02 (cell floor + 0.02 offset).
        bool y_ok = true;
        for (const auto& v : sec.vertices) y_ok &= approx(v.py, 8.02f, 1e-4f);
        CHECK(y_ok, "pebble: all vertices at y == cell_floor + 0.02");
    }

    // =========================================================================
    // 5. Twig (id 28) — single flat ground quad, normal +Y (elongated vs pebble)
    // =========================================================================
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 15, 1, 15, static_cast<uint8_t>(mat::TWIG_ID));
        MeshBuffers m;
        append_flora(slab, m);

        CHECK(flora_quads(m)  == 2,  "twig: quad_count == 2 (1 double-sided ground quad)");
        const MeshSection& sec = m.section(FaceClass::Flora);
        CHECK(sec.vertices.size() == 4,  "twig: 4 verts");
        CHECK(sec.indices.size()  == 12, "twig: 12 indices");

        // Vertices should have normal +Y.
        bool normal_ok = true;
        for (const auto& v : sec.vertices) {
            normal_ok &= approx(v.nx, 0.0f) && approx(v.ny, 1.0f) && approx(v.nz, 0.0f);
        }
        CHECK(normal_ok, "twig: all vertices have normal (0, +1, 0)");

        // Y at cell floor + 0.02.
        bool y_ok = true;
        for (const auto& v : sec.vertices) y_ok &= approx(v.py, 1.02f, 1e-4f);
        CHECK(y_ok, "twig: vertices at y == 1 + 0.02");
    }

    // =========================================================================
    // 6. Non-flora ids emit nothing: stone (1), air (0), water (16)
    // =========================================================================
    {
        // Stone
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 5, 5, 5, static_cast<uint8_t>(mat::STONE));
        MeshBuffers m;
        append_flora(slab, m);
        CHECK(m.total_quads() == 0, "stone: append_flora emits nothing");
        CHECK(flora_quads(m) == 0,  "stone: Flora section empty");
    }
    {
        // Air (all-zero slab is already air — test explicitly anyway)
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 10, 10, 10, static_cast<uint8_t>(mat::AIR));
        MeshBuffers m;
        append_flora(slab, m);
        CHECK(m.total_quads() == 0, "air: append_flora emits nothing");
    }
    {
        // Water id 16 (WATER_FLUID_BASE_ID)
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 7, 7, 7, static_cast<uint8_t>(mat::WATER_FLUID_BASE_ID));
        MeshBuffers m;
        append_flora(slab, m);
        CHECK(m.total_quads() == 0, "water id 16: append_flora emits nothing");
        CHECK(flora_quads(m) == 0,  "water id 16: Flora section empty");
    }

    // =========================================================================
    // 7. hash3 determinism
    //    Same (x,y,z) must ALWAYS return the same value (no internal state).
    //    Different (x,y,z) inputs should GENERALLY return different values —
    //    we check several pairs that should hash differently.
    // =========================================================================
    {
        // Determinism: call hash3 twice on the same inputs.
        const uint32_t h0 = hash3(5, 5, 5);
        CHECK(hash3(5, 5, 5) == h0,   "hash3: deterministic for (5,5,5)");
        CHECK(hash3(0, 0, 0) == hash3(0, 0, 0), "hash3: deterministic for (0,0,0)");
        CHECK(hash3(31,31,31) == hash3(31,31,31), "hash3: deterministic for (31,31,31)");

        // Variation: check several distinct inputs produce distinct outputs.
        // NOTE: hash collisions CAN happen but are astronomically unlikely for
        // adjacent integer inputs with a good hash. We check 6 independent pairs.
        bool all_distinct = true;
        const uint32_t h[6] = {
            hash3(0,0,0), hash3(1,0,0), hash3(0,1,0),
            hash3(0,0,1), hash3(7,3,5), hash3(31,31,31)
        };
        // Simple N^2 distinctness check — 6 values, 15 pairs.
        for (int i = 0; i < 6; ++i)
            for (int j = i+1; j < 6; ++j)
                if (h[i] == h[j]) all_distinct = false;
        CHECK(all_distinct, "hash3: 6 distinct coords produce 6 distinct hash values");
    }

    // =========================================================================
    // 8. Jitter bounds: emitted vertices of a flora voxel stay within
    //    the cell's XZ footprint [x, x+1] x [z, z+1].
    //
    //    We test several voxel positions across the chunk to cover different hash
    //    values (different jitter offsets and yaw rotations).
    // =========================================================================
    {
        // We test 4 different positions. For each, check ALL Flora vertices have
        // px in [x, x+1] and pz in [z, z+1].
        struct TestCase { int x, y, z; };
        const TestCase cases[] = {
            {0, 0, 0}, {15, 5, 15}, {31, 31, 31}, {7, 10, 22}
        };
        for (const auto& tc : cases) {
            DenseGrid slab = make_mesh_slab();
            set_local(slab, tc.x, tc.y, tc.z, static_cast<uint8_t>(mat::GRASS_BLADE_ID));
            MeshBuffers m;
            append_flora(slab, m);

            const MeshSection& sec = m.section(FaceClass::Flora);
            const float x_min = static_cast<float>(tc.x);
            const float x_max = static_cast<float>(tc.x) + 1.0f;
            const float z_min = static_cast<float>(tc.z);
            const float z_max = static_cast<float>(tc.z) + 1.0f;

            bool in_bounds = true;
            for (const auto& v : sec.vertices) {
                // Allow a tiny epsilon for float arithmetic on the boundary.
                if (v.px < x_min - 1e-4f || v.px > x_max + 1e-4f) in_bounds = false;
                if (v.pz < z_min - 1e-4f || v.pz > z_max + 1e-4f) in_bounds = false;
            }
            char msg[128];
            std::snprintf(msg, sizeof(msg),
                "jitter bounds: grass at (%d,%d,%d) stays in cell XZ footprint",
                tc.x, tc.y, tc.z);
            CHECK(in_bounds, msg);
        }
    }

    // =========================================================================
    // 9. Two grass voxels at DIFFERENT coords produce different vertex positions
    //    (the jitter actually varies between cells, so the field isn't gridded).
    // =========================================================================
    {
        // Voxel A at (0,0,0).
        DenseGrid slabA = make_mesh_slab();
        set_local(slabA, 0, 0, 0, static_cast<uint8_t>(mat::GRASS_BLADE_ID));
        MeshBuffers mA;
        append_flora(slabA, mA);

        // Voxel B at (1,0,0) — one step in X.
        DenseGrid slabB = make_mesh_slab();
        set_local(slabB, 1, 0, 0, static_cast<uint8_t>(mat::GRASS_BLADE_ID));
        MeshBuffers mB;
        append_flora(slabB, mB);

        const MeshSection& secA = mA.section(FaceClass::Flora);
        const MeshSection& secB = mB.section(FaceClass::Flora);

        // Both should have 8 vertices (sanity).
        CHECK(secA.vertices.size() == 8, "jitter variation: voxel A has 8 verts");
        CHECK(secB.vertices.size() == 8, "jitter variation: voxel B has 8 verts");

        // Compute the centre-X of each voxel's cross (average of all vertex X values).
        // The raw cell centres are 0.5 and 1.5 respectively; jitter offsets them.
        // If jitter is applied correctly they should be DIFFERENT from each other
        // (not necessarily from the raw centre, though they very likely are).
        float cx_A = 0, cx_B = 0;
        for (const auto& v : secA.vertices) cx_A += v.px;
        for (const auto& v : secB.vertices) cx_B += v.px;
        cx_A /= 8.0f;
        cx_B /= 8.0f;

        // The centres should differ by roughly 1 voxel (the cell offset) PLUS
        // possibly different jitter. They must NOT be identical (that would mean
        // jitter is the same for both cells, which is the whole problem we solve).
        // We check that the difference is NOT exactly 1.0 (meaning jitter varied).
        // Note: we allow some tolerance for float equality to avoid false positives
        // on rare exact-collision hashes (astronomically unlikely with these inputs).
        const float diff = std::fabs(cx_B - cx_A);
        const bool jitter_varied = !approx(diff, 1.0f, 1e-3f);
        CHECK(jitter_varied,
            "jitter variation: adjacent grass voxels have different centre-X offsets");

        // Also confirm: the first vertices of A and B are not identical.
        const MeshVertex& vA = secA.vertices[0];
        const MeshVertex& vB = secB.vertices[0];
        const bool verts_differ = !approx(vA.px, vB.px) || !approx(vA.py, vB.py)
                                || !approx(vA.pz, vB.pz);
        CHECK(verts_differ, "jitter variation: first vertices of adjacent grass voxels differ");
    }

    // =========================================================================
    // 10. Multiple flora voxels in one pass: ensure each is handled independently
    //     and the counts accumulate correctly.
    // =========================================================================
    {
        DenseGrid slab = make_mesh_slab();
        // 2 grass blades + 1 pebble.
        set_local(slab, 0, 0,  0,  static_cast<uint8_t>(mat::GRASS_BLADE_ID));
        set_local(slab, 5, 5,  5,  static_cast<uint8_t>(mat::GRASS_BLADE_ID));
        set_local(slab, 10, 2, 10, static_cast<uint8_t>(mat::PEBBLE_ID));

        MeshBuffers m;
        append_flora(slab, m);

        // 2 crosses × 4 quad_count each = 8; 1 ground quad × 2 quad_count = 2; total 10.
        CHECK(flora_quads(m) == 10, "multi-voxel: 2 grass + 1 pebble -> quad_count == 10");
        // 2 crosses × 8 verts + 1 pebble × 4 verts = 20.
        const MeshSection& sec = m.section(FaceClass::Flora);
        CHECK(sec.vertices.size() == 20,  "multi-voxel: 2 grass + 1 pebble -> 20 verts");
        CHECK(sec.indices.size()  == 60,  "multi-voxel: 2 grass + 1 pebble -> 60 indices");
    }

    // =========================================================================
    // 11. Flora atlas UVs are non-degenerate and different between ids
    // =========================================================================
    {
        // Each flora id must map to a non-zero-area UV rect.
        using namespace flora_atlas;
        const int flora_ids[] = {
            mat::GRASS_BLADE_ID, mat::FLOWER_RED_ID, mat::FLOWER_BLUE_ID,
            mat::PEBBLE_ID,      mat::TWIG_ID
        };
        for (int id : flora_ids) {
            const FloraUVRect r = uv_for_id(id);
            CHECK(r.u1 > r.u0, "flora UV: u1 > u0 (non-degenerate U range)");
            CHECK(r.v1 > r.v0, "flora UV: v1 > v0 (non-degenerate V range)");
            CHECK(r.u0 >= 0.0f && r.u1 <= 1.0f, "flora UV: U in [0,1]");
            CHECK(r.v0 >= 0.0f && r.v1 <= 1.0f, "flora UV: V in [0,1]");
        }

        // Distinct ids must produce distinct UV rects (each gets a unique tile).
        bool uvs_distinct = true;
        for (int i = 0; i < 5; ++i) {
            for (int j = i+1; j < 5; ++j) {
                const FloraUVRect a = uv_for_id(flora_ids[i]);
                const FloraUVRect b = uv_for_id(flora_ids[j]);
                if (approx(a.u0, b.u0) && approx(a.v0, b.v0)) uvs_distinct = false;
            }
        }
        CHECK(uvs_distinct, "flora UV: each flora id maps to a unique tile rect");
    }

    // =========================================================================
    // Done
    // =========================================================================
    std::printf("[flora   ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
