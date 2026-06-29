// test_seams.cpp — parity harness for Core/SeamSkirt.h.
//   cd tests/standalone && ./build.sh seams

#include <cstdio>
#include <cmath>
#include "Core/SeamSkirt.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)
static bool approx(float a, float b) { return std::fabs(a - b) < 1e-5f; }

using namespace mira;

// Geometric normal of quad `q` from its FIRST triangle as actually wound (read
// through the index list, so the winding flip is reflected — not storage order).
static void quad_geo_normal(const MeshSection& sec, size_t q, float n[3]) {
    const size_t t = q * 6; // 6 indices per quad
    const MeshVertex& a = sec.vertices[sec.indices[t + 0]];
    const MeshVertex& b = sec.vertices[sec.indices[t + 1]];
    const MeshVertex& c = sec.vertices[sec.indices[t + 2]];
    const float e1[3] = { b.px - a.px, b.py - a.py, b.pz - a.pz };
    const float e2[3] = { c.px - a.px, c.py - a.py, c.pz - a.pz };
    n[0] = e1[1]*e2[2] - e1[2]*e2[1];
    n[1] = e1[2]*e2[0] - e1[0]*e2[2];
    n[2] = e1[0]*e2[1] - e1[1]*e2[0];
}

int main() {
    // ---- the no-gap invariant ----
    CHECK(seam::skirt_bottom(20, 4) == 16, "skirt drops depth voxels");
    CHECK(seam::covers_gap(20, 18, 4), "depth 4 covers a 2-voxel LOD step");
    CHECK(seam::covers_gap(20, 16, 4), "depth 4 covers exactly to the bottom");
    CHECK(!seam::covers_gap(20, 15, 4), "depth 4 does NOT cover a 5-voxel drop");
    // The design rule: depth >= worst LOD step => always covered.
    for (int step = 0; step <= 4; ++step)
        CHECK(seam::covers_gap(20, 20 - step, 4), "depth >= step always covers");

    // ---- a flat border merges to ONE skirt quad ----
    {
        int surface[coords::CHUNK];
        for (int k = 0; k < coords::CHUNK; ++k) surface[k] = 20;
        MeshBuffers out;
        seam::append_side_skirt(out, FACE_NEG_X, surface, 4, mat::STONE);
        const MeshSection& sec = out.section(FaceClass::Opaque);
        CHECK(sec.quad_count() == 1, "flat border -> single merged skirt quad");
        // Spans Y [16,20] on the x=0 plane.
        bool y_ok = true, x_ok = true;
        for (const auto& mv : sec.vertices) {
            if (!(approx(mv.py, 16.0f) || approx(mv.py, 20.0f))) y_ok = false;
            if (!approx(mv.px, 0.0f)) x_ok = false;
        }
        CHECK(y_ok, "skirt Y spans surface..surface-depth (16..20)");
        CHECK(x_ok, "NEG_X skirt sits on the x=0 plane");
        // Outward normal is -X.
        float n[3]; quad_geo_normal(sec, 0, n);
        CHECK(n[0] < 0 && approx(n[1], 0.0f) && approx(n[2], 0.0f), "NEG_X skirt faces -X");
    }

    // ---- a stepped border makes two quads (one per equal-height run) ----
    {
        int surface[coords::CHUNK];
        for (int k = 0; k < coords::CHUNK; ++k) surface[k] = (k < 16) ? 20 : 18;
        MeshBuffers out;
        seam::append_side_skirt(out, FACE_POS_Z, surface, 3, mat::DIRT);
        const MeshSection& sec = out.section(FaceClass::Opaque);
        CHECK(sec.quad_count() == 2, "stepped border -> two skirt quads");
        // POS_Z skirts sit on z=CHUNK and face +Z.
        bool z_ok = true;
        for (const auto& mv : sec.vertices) if (!approx(mv.pz, (float)coords::CHUNK)) z_ok = false;
        CHECK(z_ok, "POS_Z skirt sits on the z=CHUNK plane");
        float n[3]; quad_geo_normal(sec, 0, n);
        CHECK(n[2] > 0 && approx(n[0], 0.0f) && approx(n[1], 0.0f), "POS_Z skirt faces +Z");
    }

    // ---- empty columns (no terrain) produce no skirt ----
    {
        int surface[coords::CHUNK];
        for (int k = 0; k < coords::CHUNK; ++k) surface[k] = 0; // all air columns
        MeshBuffers out;
        seam::append_side_skirt(out, FACE_NEG_X, surface, 4, mat::STONE);
        CHECK(out.total_quads() == 0, "all-empty border -> no skirt geometry");
    }

    // ---- the four vertical sides each land on their own plane / normal ----
    {
        int surface[coords::CHUNK];
        for (int k = 0; k < coords::CHUNK; ++k) surface[k] = 10;
        struct Case { FaceDir side; int axis; float sign; float plane; };
        const Case cases[4] = {
            { FACE_NEG_X, 0, -1.0f, 0.0f },
            { FACE_POS_X, 0, +1.0f, (float)coords::CHUNK },
            { FACE_NEG_Z, 2, -1.0f, 0.0f },
            { FACE_POS_Z, 2, +1.0f, (float)coords::CHUNK },
        };
        for (const auto& c : cases) {
            MeshBuffers out;
            seam::append_side_skirt(out, c.side, surface, 2, mat::STONE);
            const MeshSection& sec = out.section(FaceClass::Opaque);
            CHECK(sec.quad_count() == 1, "side skirt merges flat profile to 1 quad");
            float n[3]; quad_geo_normal(sec, 0, n);
            CHECK(n[c.axis] * c.sign > 0, "side skirt faces outward");
        }
    }

    std::printf("[seams   ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
