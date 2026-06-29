// test_lodmesh.cpp — geometry/scale lock for the voxel LOD RENDER pipeline.
//   cd tests/standalone && ./build.sh lodmesh
//
// WHY THIS EXISTS (plain English):
// The UE render layer is about to draw far-away terrain at lower detail. The plan
// is: take the full-resolution voxel grid, DOWNSAMPLE it (Core/LodDownsample.h),
// then GREEDY-MESH the coarse grid (Core/GreedyMesher.h). Before writing any UE
// code against that path, we prove the *Core math* is correct and — critically —
// that LOD preserves WORLD SIZE (a far chunk occupies the same physical box, just
// with fewer triangles). If that invariant holds in pure C++, the UE side is "just"
// a multiply-by-voxel-size upload and a transform; the risky geometry is de-risked.
//
// This harness asserts CONTRACTS, not pixels. It runs under clang with no Unreal.
//
// THE REAL LOD CONTRACT THIS TEST LOCKS (discovered by reading the headers):
//   * Function:  mira::lod::downsample_half(const DenseGrid&) -> DenseGrid
//                (side halves; each output voxel = a 2x2x2 block of the input).
//                mira::lod::downsample_to_lod(src, lod) chains it: side / 2^lod.
//   * Scale:     LOD level N means each coarse voxel REPRESENTS 2^N fine voxels per
//                axis. So when you render LOD N, each coarse voxel must be drawn at
//                voxel_size * 2^N to cover the same world space. This test proves
//                that by meshing the coarse grid and scaling positions by 2.
//   * Material:  "solid survives" (any non-air/non-passthrough voxel makes the cell
//                solid; flora/passthrough ids 24..28 count as air). Surface-preserving
//                rule: the coarse voxel takes the material of the TOP-MOST solid fine
//                voxel along world-up (grid Y), so a 1-voxel grass cap stays green.
//
// Prints "[lodmesh ] PASS" / "[lodmesh ] FAIL"; returns 0 on success, 1 on failure
// (matches every other tests/standalone harness exactly).

#include <cstdio>
#include <cmath>
#include <limits>

#include "Core/LodDownsample.h"  // downsample_half / downsample_to_lod (unit under test)
#include "Core/GreedyMesher.h"   // greedy_mesh(slab) -> MeshBuffers
#include "Core/VoxelChunk.h"     // DenseGrid, make_mesh_slab, MESH_SLAB_SIDE, APRON
#include "Core/MeshTypes.h"      // MeshBuffers / MeshSection / FaceClass / FaceDir
#include "Core/MaterialIds.h"    // mat::STONE, mat::DIRT, mat::AIR, ...
#include "Core/VoxelColor.h"     // shaded_color (top-face color assertion)

// ---------------------------------------------------------------------------
// Harness boilerplate (identical macro style to test_lod.cpp / test_mesher.cpp)
// ---------------------------------------------------------------------------
static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

static bool approx(float a, float b) { return std::fabs(a - b) < 1e-5f; }

using namespace mira;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Place a voxel at CHUNK-LOCAL coords into an apron'd slab (shift by +APRON so the
// inner [1..32] region is the chunk and the index-0 / index-33 shell is the apron).
static void set_local(DenseGrid& slab, int x, int y, int z, uint8_t id) {
    slab.set_type(x + APRON, y + APRON, z + APRON, id);
}

// Copy a plain (apron-less) DenseGrid into a fresh apron'd mesh slab so the greedy
// mesher can run on it. The grid's voxel (gx,gy,gz) lands at slab (gx+1,gy+1,gz+1);
// the surrounding 1-voxel shell stays AIR (so every outer face of the block is
// exposed — exactly the "chunk floating in air" case we want to measure). The grid
// must fit inside the inner [1..CHUNK] region (side <= coords::CHUNK).
static DenseGrid slab_from_grid(const DenseGrid& g) {
    DenseGrid slab = make_mesh_slab();             // side 34, all AIR
    for (int z = 0; z < g.side; ++z)
        for (int y = 0; y < g.side; ++y)
            for (int x = 0; x < g.side; ++x)
                set_local(slab, x, y, z, g.type_at(x, y, z));
    return slab;
}

// Axis-aligned bounding box of every emitted vertex in the Opaque section, in the
// mesher's VOXEL UNITS. (Greedy meshing only emits surface vertices, but for a
// solid box the surface verts touch all 6 extreme planes, so this box == the
// block's full extent.) Returns false if the section emitted no geometry.
struct BBox {
    float minx, miny, minz, maxx, maxy, maxz;
};
static bool opaque_bbox(const MeshBuffers& m, BBox& out) {
    const MeshSection& sec = m.section(FaceClass::Opaque);
    if (sec.vertices.empty()) return false;
    float big = std::numeric_limits<float>::max();
    out = { big, big, big, -big, -big, -big };
    for (const MeshVertex& v : sec.vertices) {
        out.minx = std::min(out.minx, v.px); out.maxx = std::max(out.maxx, v.px);
        out.miny = std::min(out.miny, v.py); out.maxy = std::max(out.maxy, v.py);
        out.minz = std::min(out.minz, v.pz); out.maxz = std::max(out.maxz, v.pz);
    }
    return true;
}

static int opaque_quads(const MeshBuffers& m) { return m.section(FaceClass::Opaque).quad_count(); }
static int opaque_verts(const MeshBuffers& m) { return (int)m.section(FaceClass::Opaque).vertices.size(); }
static int opaque_idx  (const MeshBuffers& m) { return (int)m.section(FaceClass::Opaque).indices.size(); }

int main() {

    // =======================================================================
    // TEST a — SCALE / BOUNDS AT LOD0 (the baseline the LOD path is measured
    //          against).
    //
    // Build an apron'd slab with a solid 8x8x8 STONE cube sitting in the inner
    // region with all neighbours air, mesh it at LOD0 (no downsample), and check:
    //   * the geometry's bounding box exactly equals the block's extent in voxel
    //     units (a cube from local (4,4,4) to (12,12,12) -> box 4..12 = 8 wide),
    //   * the merged-quad count is exactly 6 (a clean solid box with all-air
    //     neighbours collapses to one rectangle per face — the greedy-mesher
    //     signature). This proves the mesher reports honest world bounds.
    // =======================================================================
    {
        DenseGrid slab = make_mesh_slab();
        const int lo = 4, hi = 12; // inner-local cube spans [lo, hi)  -> 8 voxels/axis
        for (int z = lo; z < hi; ++z)
            for (int y = lo; y < hi; ++y)
                for (int x = lo; x < hi; ++x)
                    set_local(slab, x, y, z, mat::STONE);

        MeshBuffers m = greedy_mesh(slab);

        CHECK(opaque_quads(m) == 6, "LOD0 8^3 solid cube -> exactly 6 merged quads (clean box)");

        BBox b{};
        CHECK(opaque_bbox(m, b), "LOD0 8^3 cube produced opaque geometry");
        // Positions are chunk-local (slab index - APRON), so the box is [lo, hi].
        CHECK(approx(b.minx, (float)lo) && approx(b.maxx, (float)hi),
              "LOD0 cube X extent == block extent (4..12 voxel units)");
        CHECK(approx(b.miny, (float)lo) && approx(b.maxy, (float)hi),
              "LOD0 cube Y extent == block extent (4..12 voxel units)");
        CHECK(approx(b.minz, (float)lo) && approx(b.maxz, (float)hi),
              "LOD0 cube Z extent == block extent (4..12 voxel units)");
        // The box is 8 voxels on every side, matching the 8x8x8 input.
        CHECK(approx(b.maxx - b.minx, 8.0f) &&
              approx(b.maxy - b.miny, 8.0f) &&
              approx(b.maxz - b.minz, 8.0f),
              "LOD0 cube bounding box is 8x8x8 voxels");
    }

    // =======================================================================
    // TEST b — DOWNSAMPLE CORRECTNESS FEEDING THE MESHER + WORLD-SIZE INVARIANCE.
    //
    // Take a fine 16x16x16 solid STONE grid. Two paths:
    //   FINE:   mesh the fine grid directly (its box is 16 voxels/axis at scale 1).
    //   COARSE: downsample one LOD level (16 -> 8 of the SAME material), mesh that,
    //           then SCALE the coarse positions by the LOD voxel size (2x).
    //
    // Assertions:
    //   (i)   the coarse solid is 8x8x8 STONE (downsample produced what we expect),
    //   (ii)  scaled coarse box == fine box  -> LOD PRESERVES WORLD SIZE,
    //   (iii) the coarse mesh has FEWER vertices/indices than the fine mesh
    //         (detail dropped — the whole point of LOD).
    //
    // This is THE invariant the UE render code relies on: render a coarse voxel at
    // voxel_size * 2^lod and the far chunk lands in exactly the same world box.
    // =======================================================================
    {
        const int FINE = 16;
        const int LOD_SCALE = 2; // one halving => each coarse voxel covers 2 fine voxels/axis

        // ---- Fine grid: solid 16^3 STONE -----------------------------------
        DenseGrid fine(FINE);
        fine.fill_type((uint8_t)mat::STONE);
        fine.fill_water(0);

        // ---- Coarse grid: downsample one LOD level -------------------------
        DenseGrid coarse = lod::downsample_half(fine);

        // (i) the coarse solid is 8x8x8 of the same material.
        CHECK(coarse.side == FINE / 2, "downsample 16^3 -> coarse side 8");
        bool all_stone = (coarse.side == FINE / 2);
        for (int z = 0; z < coarse.side && all_stone; ++z)
            for (int y = 0; y < coarse.side && all_stone; ++y)
                for (int x = 0; x < coarse.side && all_stone; ++x)
                    if (coarse.type_at(x, y, z) != mat::STONE) all_stone = false;
        CHECK(all_stone, "downsampled coarse grid is a solid 8^3 block of STONE");

        // ---- Mesh both, measure boxes --------------------------------------
        MeshBuffers m_fine   = greedy_mesh(slab_from_grid(fine));
        MeshBuffers m_coarse = greedy_mesh(slab_from_grid(coarse));

        BBox bf{}, bc{};
        CHECK(opaque_bbox(m_fine, bf),   "fine grid meshed to geometry");
        CHECK(opaque_bbox(m_coarse, bc), "coarse grid meshed to geometry");

        // Both blocks were placed with their corner at chunk-local (0,0,0), so the
        // min corner is 0 in both meshes; the world box is therefore defined by the
        // max corner. Fine: 16 voxels at scale 1 -> 16. Coarse: 8 voxels at scale 2
        // -> 16. Same world box.
        CHECK(approx(bf.minx, 0.0f) && approx(bf.miny, 0.0f) && approx(bf.minz, 0.0f),
              "fine block min corner at origin");
        CHECK(approx(bc.minx, 0.0f) && approx(bc.miny, 0.0f) && approx(bc.minz, 0.0f),
              "coarse block min corner at origin");

        // (ii) scaled coarse box == fine box -> world size preserved.
        CHECK(approx(bc.maxx * LOD_SCALE, bf.maxx) &&
              approx(bc.maxy * LOD_SCALE, bf.maxy) &&
              approx(bc.maxz * LOD_SCALE, bf.maxz),
              "LOD invariant: coarse box * 2 == fine box (world size preserved)");
        // And concretely: both occupy a 16-voxel-unit world cube.
        CHECK(approx(bf.maxx, 16.0f) && approx(bc.maxx * LOD_SCALE, 16.0f),
              "both fine and scaled-coarse span 16 world voxel units");

        // (iii) the coarse mesh is genuinely cheaper. For these clean solid boxes
        // greedy meshing collapses each to 6 quads, so quad COUNT is equal — the
        // real, measurable LOD saving here is that the QUADS THEMSELVES are smaller
        // (fewer covered voxels) AND, crucially for the UE upload, the coarse path
        // describes the same world volume with half-resolution source data. We
        // assert the meshes are not larger, and that the coarse source grid holds
        // 8x fewer voxels than the fine one (the density drop LOD buys).
        CHECK(opaque_verts(m_coarse) <= opaque_verts(m_fine),
              "coarse mesh has no more vertices than fine mesh");
        CHECK(opaque_idx(m_coarse) <= opaque_idx(m_fine),
              "coarse mesh has no more indices than fine mesh");
        const long fine_vox   = (long)fine.side   * fine.side   * fine.side;   // 4096
        const long coarse_vox = (long)coarse.side * coarse.side * coarse.side; // 512
        CHECK(coarse_vox * 8 == fine_vox,
              "coarse source grid holds 8x fewer voxels than fine (LOD density drop)");
    }

    // =======================================================================
    // TEST b2 — DETAIL ACTUALLY DROPS (vertex/index count strictly falls when the
    //           fine grid has surface detail that the coarse grid smooths away).
    //
    // The clean-box case above can't show a strict count drop (both are 6 quads).
    // So here we give the FINE grid a bumpy top surface — a checkerboard of +1-tall
    // STONE pillars — which forces MANY little quads. After one downsample the bumps
    // collapse into a flat top, and the coarse mesh has STRICTLY fewer verts/indices.
    // This is the concrete "triangle count drops at LOD" proof.
    // =======================================================================
    {
        const int N = 16;
        DenseGrid fine(N);
        fine.fill_type((uint8_t)mat::AIR);
        fine.fill_water(0);

        // Solid base: bottom 8 layers fully STONE.
        for (int z = 0; z < N; ++z)
            for (int y = 0; y < 8; ++y)
                for (int x = 0; x < N; ++x)
                    fine.set_type(x, y, z, (uint8_t)mat::STONE);
        // Bumpy top: every other (x,z) column gets one extra STONE voxel at y=8.
        // This 1-voxel checkerboard cannot greedy-merge, so it explodes the quad
        // count on the fine mesh.
        for (int z = 0; z < N; ++z)
            for (int x = 0; x < N; ++x)
                if (((x + z) & 1) == 0)
                    fine.set_type(x, 8, z, (uint8_t)mat::STONE);

        DenseGrid coarse = lod::downsample_half(fine);

        MeshBuffers m_fine   = greedy_mesh(slab_from_grid(fine));
        MeshBuffers m_coarse = greedy_mesh(slab_from_grid(coarse));

        CHECK(opaque_quads(m_fine) > opaque_quads(m_coarse),
              "bumpy surface: fine mesh has MORE quads than coarse (detail dropped)");
        CHECK(opaque_verts(m_coarse) < opaque_verts(m_fine),
              "bumpy surface: coarse mesh has strictly FEWER vertices than fine");
        CHECK(opaque_idx(m_coarse) < opaque_idx(m_fine),
              "bumpy surface: coarse mesh has strictly FEWER indices than fine");
    }

    // =======================================================================
    // TEST c — SURFACE-PRESERVING MATERIAL ("top-most solid voxel wins").
    //
    // A coarse voxel straddling mixed fine materials must take the material of
    // the HIGHEST solid fine voxel along world-up (grid Y). This is what keeps a
    // 1-voxel grass cap green at distance. Occupancy is unchanged: any solid fine
    // voxel makes the cell solid; flora/passthrough (24..28) count as air.
    // We build deterministic 2x2x2 fine grids and downsample each to a single
    // coarse voxel, asserting the winner.
    // =======================================================================
    {
        // c1: top row GRASS (id 3), bottom row DIRT (id 2) -> top-wins -> GRASS.
        // Old majority/tie rule would have picked DIRT (smaller id on a 4-4 tie).
        DenseGrid g(2);
        g.fill_type((uint8_t)mat::DIRT);
        g.fill_water(0);
        g.set_type(0,1,0, mat::GRASS); g.set_type(1,1,0, mat::GRASS);
        g.set_type(0,1,1, mat::GRASS); g.set_type(1,1,1, mat::GRASS); // top row grass
        DenseGrid c = lod::downsample_half(g);
        CHECK(c.side == 1 && c.type_at(0,0,0) == mat::GRASS,
              "top-wins: GRASS(top)+DIRT(bottom) -> coarse cell is GRASS");
    }
    {
        // c2: a single GRASS in the top row beats a 7-voxel DIRT majority.
        DenseGrid g(2);
        g.fill_type((uint8_t)mat::DIRT);
        g.fill_water(0);
        g.set_type(0,1,0, mat::GRASS); // one grass voxel in the TOP row
        DenseGrid c = lod::downsample_half(g);
        CHECK(c.type_at(0,0,0) == mat::GRASS,
              "top-wins: lone top GRASS beats 7-voxel DIRT majority");
    }
    {
        // c3: "solid survives" — 7 AIR + 1 STONE -> STONE (a far hill never holes).
        DenseGrid g(2);
        g.fill_type((uint8_t)mat::AIR);
        g.fill_water(0);
        g.set_type(0,0,0, mat::STONE);
        DenseGrid c = lod::downsample_half(g);
        CHECK(c.type_at(0,0,0) == mat::STONE,
              "solid survives: 7 AIR + 1 STONE -> STONE (no LOD holes)");
    }
    {
        // c4: flora is passthrough (== air for LOD) — 7 AIR + 1 GRASS_BLADE -> AIR.
        DenseGrid g(2);
        g.fill_type((uint8_t)mat::AIR);
        g.fill_water(0);
        g.set_type(0,0,0, (uint8_t)mat::GRASS_BLADE_ID); // id 24, passthrough
        DenseGrid c = lod::downsample_half(g);
        CHECK(c.type_at(0,0,0) == mat::AIR,
              "passthrough: 7 AIR + 1 flora -> AIR (flora doesn't survive LOD)");
    }

    // =======================================================================
    // TEST c5 — GREEN REACHES THE RENDERED TOP FACE.
    //
    // The decisive render-path proof: build a grass-capped column, downsample,
    // greedy-mesh the coarse grid, and assert that the +Y (top) face quad's
    // vertex color == shaded_color(GRASS, FACE_POS_Y). This proves the green
    // grass material survives downsample AND lands on the actual top face the
    // player sees at LOD distance.
    //
    // Column: 16^3 grid, y=0..14 STONE, y=15 GRASS cap. Downsample once -> 8^3
    // coarse: each top coarse voxel must be GRASS, so its +Y face is grass-green.
    // =======================================================================
    {
        DenseGrid fine(16);
        fine.fill_type((uint8_t)mat::AIR);
        fine.fill_water(0);
        for (int z = 0; z < 16; ++z)
            for (int x = 0; x < 16; ++x) {
                for (int y = 0; y <= 14; ++y) fine.set_type(x, y, z, (uint8_t)mat::STONE);
                fine.set_type(x, 15, z, (uint8_t)mat::GRASS); // 1-voxel grass cap
            }

        DenseGrid coarse = lod::downsample_half(fine); // -> 8^3
        // Confirm the coarse top layer (y = 7) is grass before meshing.
        CHECK(coarse.side == 8 && coarse.type_at(0,7,0) == mat::GRASS,
              "c5: coarse top layer is GRASS after downsample");

        MeshBuffers m = greedy_mesh(slab_from_grid(coarse));
        const MeshSection& sec = m.section(FaceClass::Opaque);

        const Rgb8 want = shaded_color(mat::GRASS, FACE_POS_Y);

        // Find at least one +Y (normal (0,1,0)) vertex and confirm its color is
        // the grass top-face color. Every +Y vertex on the cap should match.
        bool found_top = false;
        bool all_top_grass = true;
        for (const MeshVertex& v : sec.vertices) {
            if (approx(v.ny, 1.0f) && approx(v.nx, 0.0f) && approx(v.nz, 0.0f)) {
                found_top = true;
                if (v.cr != want.r || v.cg != want.g || v.cb != want.b) {
                    all_top_grass = false;
                }
            }
        }
        CHECK(found_top, "c5: coarse mesh emits a +Y (top) face");
        CHECK(all_top_grass,
              "c5: +Y top-face vertex color == shaded_color(GRASS, FACE_POS_Y) (green reaches the top face)");
    }

    // =======================================================================
    // TEST d — NO HOLES / WATERTIGHT OUTER SHELL after downsample.
    //
    // The coarse solid block must still mesh to exactly its 6 outer faces — no
    // missing faces (holes you'd see through at distance) and no spurious interior
    // faces. We mesh the downsampled 8^3 block (from a solid 16^3) and assert
    // exactly 6 quads / 24 vertices in the Opaque section, and nothing in any other
    // section. We also confirm the 6 quads carry the 6 distinct outward normals,
    // i.e. one face per cube side (a true closed box, no duplicated/dropped side).
    // =======================================================================
    {
        DenseGrid fine(16);
        fine.fill_type((uint8_t)mat::STONE);
        fine.fill_water(0);
        DenseGrid coarse = lod::downsample_half(fine); // solid 8^3

        MeshBuffers m = greedy_mesh(slab_from_grid(coarse));

        CHECK(opaque_quads(m) == 6, "coarse solid block -> exactly 6 outer faces (no holes)");
        CHECK(opaque_verts(m) == 24, "coarse solid block -> 24 verts (6 quads, no interior faces)");
        // Nothing should land in the other sections for a pure-stone block.
        CHECK(m.section(FaceClass::Cutout).quad_count() == 0 &&
              m.section(FaceClass::Water).quad_count()  == 0 &&
              m.section(FaceClass::Flora).quad_count()  == 0,
              "coarse solid block emits only Opaque geometry");

        // Confirm all 6 cube directions are present exactly once. Each quad's 4
        // verts share a normal; classify by which axis component is +/-1.
        const MeshSection& sec = m.section(FaceClass::Opaque);
        int dir_hits[6] = {0,0,0,0,0,0}; // -X,+X,-Y,+Y,-Z,+Z
        for (size_t v = 0; v < sec.vertices.size(); v += 4) {
            const MeshVertex& n = sec.vertices[v];
            if      (approx(n.nx, -1.0f)) dir_hits[0]++;
            else if (approx(n.nx,  1.0f)) dir_hits[1]++;
            else if (approx(n.ny, -1.0f)) dir_hits[2]++;
            else if (approx(n.ny,  1.0f)) dir_hits[3]++;
            else if (approx(n.nz, -1.0f)) dir_hits[4]++;
            else if (approx(n.nz,  1.0f)) dir_hits[5]++;
        }
        bool one_each = true;
        for (int i = 0; i < 6; ++i) if (dir_hits[i] != 1) one_each = false;
        CHECK(one_each, "coarse solid block: each of the 6 cube faces present exactly once (watertight)");
    }

    // =======================================================================
    // TEST e — DEEPER LOD CHAIN keeps world size (downsample_to_lod, 2 halvings).
    //
    // Sanity that the invariant holds beyond a single halving: a solid 16^3 at
    // LOD 2 collapses to 4^3, and 4 coarse voxels * scale 4 == the original 16
    // world voxel units. This mirrors what the UE LOD band selector will do when it
    // jumps two levels for a distant tile.
    // =======================================================================
    {
        const int N = 16;
        DenseGrid fine(N);
        fine.fill_type((uint8_t)mat::STONE);
        fine.fill_water(0);

        DenseGrid coarse = lod::downsample_to_lod(fine, 2); // 16 -> 8 -> 4
        CHECK(coarse.side == 4, "downsample_to_lod(.,2): 16^3 -> 4^3");

        MeshBuffers m = greedy_mesh(slab_from_grid(coarse));
        BBox b{};
        CHECK(opaque_bbox(m, b), "LOD2 coarse block meshed");
        const int LOD2_SCALE = 4; // 2^2
        CHECK(approx(b.maxx * LOD2_SCALE, (float)N) &&
              approx(b.maxy * LOD2_SCALE, (float)N) &&
              approx(b.maxz * LOD2_SCALE, (float)N),
              "LOD2 invariant: coarse box * 4 == original 16 world voxel units");
        CHECK(opaque_quads(m) == 6, "LOD2 coarse solid block still meshes to 6 faces (no holes)");
    }

    // =======================================================================
    // Final verdict (exact format the runner / build.sh parse for PASS/FAIL)
    // =======================================================================
    std::printf("[lodmesh ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
