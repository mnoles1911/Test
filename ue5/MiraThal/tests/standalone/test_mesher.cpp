// test_mesher.cpp — standalone harness for the cubic greedy mesher
// (Core/GreedyMesher.{h,cpp}).
//   cd tests/standalone && ./build.sh mesher
//
// Mirrors the headless verification role of the other Core selectors: it runs
// under clang (no Unreal needed) and asserts the meshing CONTRACT, not pixels:
//   * culling: hidden interior faces are never emitted
//   * greedy merge: identical adjacent faces collapse to one quad (a flat patch
//     becomes a single rectangle; a solid 32^3 chunk becomes exactly 6 quads)
//   * class routing: opaque terrain -> Opaque section, leaves -> Cutout section,
//     water + flora emit NOTHING here (other meshers own them)
//   * leaves are non-culling (Cutout never occludes)
//   * atlas UV: a merged quad carries the right per-face tile rect
//   * winding/normal: an emitted +Y quad's geometric normal points +Y
//
// Prints "[mesher  ] PASS" / "[mesher  ] FAIL"; returns 0 on success, 1 on any
// failure (matches the other tests/standalone harnesses).

#include <cstdio>
#include <cmath>

#include "Core/GreedyMesher.h"
#include "Core/VoxelChunk.h"
#include "Core/MeshTypes.h"
#include "Core/AtlasUV.h"
#include "Core/MaterialIds.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

static bool approx(float a, float b) { return std::fabs(a - b) < 1e-5f; }

using namespace mira;

// Convenience: section quad counts.
static int opaque_quads(const MeshBuffers& m) { return m.section(FaceClass::Opaque).quad_count(); }
static int cutout_quads(const MeshBuffers& m) { return m.section(FaceClass::Cutout).quad_count(); }
static int water_quads (const MeshBuffers& m) { return m.section(FaceClass::Water ).quad_count(); }
static int flora_quads (const MeshBuffers& m) { return m.section(FaceClass::Flora ).quad_count(); }

// Place a voxel at CHUNK-LOCAL coords [0..31] into an apron'd slab (shift +APRON).
static void set_local(DenseGrid& slab, int x, int y, int z, uint8_t id) {
    slab.set_type(x + APRON, y + APRON, z + APRON, id);
}

int main() {
    // ---------------------------------------------------------------------
    // 1. A single solid voxel in an all-air slab -> 6 quads, all Opaque.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 5, 5, 5, mat::STONE);
        MeshBuffers m = greedy_mesh(slab);
        CHECK(opaque_quads(m) == 6, "single voxel -> 6 opaque quads");
        CHECK(cutout_quads(m) == 0, "single voxel -> 0 cutout quads");
        CHECK(water_quads(m)  == 0, "single voxel -> 0 water quads");
        CHECK(flora_quads(m)  == 0, "single voxel -> 0 flora quads");
        CHECK(m.total_quads() == 6, "single voxel -> 6 total quads");
    }

    // ---------------------------------------------------------------------
    // 2. Two adjacent opaque voxels: interior shared face is culled.
    //    A 2x1x1 run has 10 outer faces (6+6 minus the 2 touching) not 12.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 5, 5, 5, mat::STONE);
        set_local(slab, 6, 5, 5, mat::STONE); // neighbour in +X
        MeshBuffers m = greedy_mesh(slab);
        // Greedy merge fuses the two +Y faces (and -Y, +Z, -Z) into one each, so
        // the count is even lower than 10; the load-bearing fact is < 12 (the two
        // isolated voxels would be 12) AND the internal face is gone.
        CHECK(m.total_quads() < 12, "2x1x1 run: fewer quads than two isolated voxels");
        // Exactly: -X(1) +X(1) and the 4 side directions merge 2->1 each = 6 quads.
        CHECK(opaque_quads(m) == 6, "2x1x1 run merges to 6 quads (shared face absent)");
    }

    // ---------------------------------------------------------------------
    // 3. Greedy merge: a flat 4x1x4 slab -> its +Y face is ONE merged quad.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        for (int x = 0; x < 4; ++x)
            for (int z = 0; z < 4; ++z)
                set_local(slab, x, 10, z, mat::GRASS);

        MeshBuffers m = greedy_mesh(slab);

        // Count the +Y faces specifically by scanning normals in the Opaque section.
        const MeshSection& sec = m.section(FaceClass::Opaque);
        int posY_quads = 0;
        for (size_t v = 0; v < sec.vertices.size(); v += 4) {
            if (approx(sec.vertices[v].ny, 1.0f)) ++posY_quads;
        }
        CHECK(posY_quads == 1, "flat 4x1x4: +Y top is a single merged quad (not 16)");
        // and the -Y bottom likewise merges to one.
        int negY_quads = 0;
        for (size_t v = 0; v < sec.vertices.size(); v += 4) {
            if (approx(sec.vertices[v].ny, -1.0f)) ++negY_quads;
        }
        CHECK(negY_quads == 1, "flat 4x1x4: -Y bottom is a single merged quad");
    }

    // ---------------------------------------------------------------------
    // 4. A fully solid 32^3 chunk (air apron) -> exactly 6 boundary quads,
    //    each a single 32x32 merged rectangle. The canonical result.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        // Fill ONLY the inner chunk [1..32] with stone; leave the apron shell air.
        for (int x = 0; x < coords::CHUNK; ++x)
            for (int y = 0; y < coords::CHUNK; ++y)
                for (int z = 0; z < coords::CHUNK; ++z)
                    set_local(slab, x, y, z, mat::STONE);

        MeshBuffers m = greedy_mesh(slab);
        CHECK(opaque_quads(m) == 6, "solid 32^3 chunk -> exactly 6 boundary quads");
        CHECK(m.total_quads() == 6, "solid 32^3 chunk -> 6 total quads");

        // Each boundary quad spans 32x32 voxels -> verify one face's extent.
        // Find a +X face and confirm its two in-plane edges are length 32.
        const MeshSection& sec = m.section(FaceClass::Opaque);
        bool found_posX_32 = false;
        for (size_t v = 0; v < sec.vertices.size(); v += 4) {
            if (!approx(sec.vertices[v].nx, 1.0f)) continue;
            // corners 00,10,11,01 — edges 00->10 and 00->01 should be length 32.
            const MeshVertex& a = sec.vertices[v + 0];
            const MeshVertex& b = sec.vertices[v + 1];
            const MeshVertex& d = sec.vertices[v + 3];
            const float e1 = std::sqrt((b.px-a.px)*(b.px-a.px) + (b.py-a.py)*(b.py-a.py) + (b.pz-a.pz)*(b.pz-a.pz));
            const float e2 = std::sqrt((d.px-a.px)*(d.px-a.px) + (d.py-a.py)*(d.py-a.py) + (d.pz-a.pz)*(d.pz-a.pz));
            if (approx(e1, 32.0f) && approx(e2, 32.0f)) found_posX_32 = true;
        }
        CHECK(found_posX_32, "solid 32^3: +X boundary quad spans 32x32 voxels");
    }

    // ---------------------------------------------------------------------
    // 5. Leaves vs air emit; stone next to leaves emits (leaves don't occlude);
    //    a stone voxel fully enclosed by stone emits nothing.
    // ---------------------------------------------------------------------
    {
        // 5a. A lone leaves voxel emits 6 quads into the Cutout section.
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 8, 8, 8, mat::LEAVES);
        MeshBuffers m = greedy_mesh(slab);
        CHECK(cutout_quads(m) == 6, "lone leaves voxel -> 6 cutout quads");
        CHECK(opaque_quads(m) == 0, "lone leaves voxel -> 0 opaque quads");
    }
    {
        // 5b. Stone touching leaves: the stone face toward the leaves STILL emits
        //     (leaves are Cutout, non-occluding). Stone + leaves side by side in X.
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 5, 5, 5, mat::STONE);
        set_local(slab, 6, 5, 5, mat::LEAVES);
        MeshBuffers m = greedy_mesh(slab);
        // Stone keeps all 6 faces (its +X face is NOT culled by the non-occluding
        // leaves — this is the "leaves don't occlude" rule):
        CHECK(opaque_quads(m) == 6, "stone next to leaves keeps all 6 faces (leaves non-occluding)");
        // The leaves, however, ARE occluded BY the opaque stone: the leaf's -X face
        // (toward the stone) is culled, so leaves keep 5 faces, not 6. Occlusion is
        // a one-way rule keyed on whether the NEIGHBOUR is an opaque solid.
        CHECK(cutout_quads(m) == 5, "leaves next to stone: -X face culled by opaque stone -> 5 faces");
    }
    {
        // 5c. A stone voxel fully enclosed by stone (3x3x3 block) -> the center
        //     voxel contributes zero faces; only the outer shell is meshed.
        DenseGrid slab = make_mesh_slab();
        for (int x = 0; x < 3; ++x)
            for (int y = 0; y < 3; ++y)
                for (int z = 0; z < 3; ++z)
                    set_local(slab, 10 + x, 10 + y, 10 + z, mat::STONE);
        MeshBuffers m = greedy_mesh(slab);
        // The enclosed 3x3x3 surface is 6 merged 3x3 faces (the inner voxel hides).
        CHECK(opaque_quads(m) == 6, "3x3x3 block -> 6 merged faces (center voxel hidden)");
        // Sanity: had the center contributed, we'd see interior faces. Confirm the
        // total vertex count is 6 quads * 4 = 24 (no stray inner geometry).
        CHECK(m.section(FaceClass::Opaque).vertices.size() == 24, "3x3x3 block -> 24 verts (6 quads, no interior)");
    }

    // ---------------------------------------------------------------------
    // 6. Water (id 16) and flora (id 24) voxels emit nothing from this mesher.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 4, 4, 4, 16);                  // a full-ish fluid id
        set_local(slab, 7, 7, 7, mat::GRASS_BLADE_ID); // flora id 24
        MeshBuffers m = greedy_mesh(slab);
        CHECK(m.total_quads() == 0, "water + flora voxels emit nothing");
        CHECK(water_quads(m) == 0 && flora_quads(m) == 0, "water/flora sections stay empty");
    }

    // ---------------------------------------------------------------------
    // 7. Atlas UV: a grass voxel's +Y face carries the grass-TOP tile rect.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 9, 9, 9, mat::GRASS);
        MeshBuffers m = greedy_mesh(slab);
        const atlas::UVRect want = atlas::uv_for(mat::GRASS, FACE_POS_Y);

        const MeshSection& sec = m.section(FaceClass::Opaque);
        bool checked = false;
        for (size_t v = 0; v < sec.vertices.size(); v += 4) {
            if (!approx(sec.vertices[v].ny, 1.0f)) continue; // the +Y quad
            // Corner 00 carries (u0,v0); corner 11 carries (u1,v1).
            const MeshVertex& c00 = sec.vertices[v + 0];
            const MeshVertex& c11 = sec.vertices[v + 2];
            CHECK(approx(c00.u, want.u0) && approx(c00.v, want.v0), "grass +Y UV min = grass-top tile u0,v0");
            CHECK(approx(c11.u, want.u1) && approx(c11.v, want.v1), "grass +Y UV max = grass-top tile u1,v1");
            checked = true;
        }
        CHECK(checked, "grass +Y face found for UV check");
    }

    // ---------------------------------------------------------------------
    // 8. Winding / normal: for one emitted +Y quad, the geometric normal from the
    //    triangle winding (edge cross product) points +Y, matching FACE_NORMAL.
    // ---------------------------------------------------------------------
    {
        DenseGrid slab = make_mesh_slab();
        set_local(slab, 3, 3, 3, mat::STONE);
        MeshBuffers m = greedy_mesh(slab);
        const MeshSection& sec = m.section(FaceClass::Opaque);

        bool checked = false;
        // Walk the index list a triangle (3 indices) at a time; find a triangle
        // whose vertices all have +Y normals and check its geometric winding.
        for (size_t t = 0; t + 2 < sec.indices.size(); t += 3) {
            const MeshVertex& a = sec.vertices[sec.indices[t + 0]];
            const MeshVertex& b = sec.vertices[sec.indices[t + 1]];
            const MeshVertex& c = sec.vertices[sec.indices[t + 2]];
            if (!(approx(a.ny, 1.0f) && approx(b.ny, 1.0f) && approx(c.ny, 1.0f))) continue;

            // edge1 = b-a, edge2 = c-a; geometric normal = edge1 x edge2 (CCW from outside).
            const float e1[3] = { b.px - a.px, b.py - a.py, b.pz - a.pz };
            const float e2[3] = { c.px - a.px, c.py - a.py, c.pz - a.pz };
            const float gx = e1[1]*e2[2] - e1[2]*e2[1];
            const float gy = e1[2]*e2[0] - e1[0]*e2[2];
            const float gz = e1[0]*e2[1] - e1[1]*e2[0];
            CHECK(gy > 0.0f && approx(gx, 0.0f) && approx(gz, 0.0f),
                  "+Y quad winding's geometric normal points +Y");
            checked = true;
            break;
        }
        CHECK(checked, "+Y triangle found for winding check");
    }

    std::printf("[mesher  ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
