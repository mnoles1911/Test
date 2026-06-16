// test_raymarch.cpp — parity/contract harness for Brickmap::raycast_solid, the
// CPU ray-march oracle (M7 far-field horizon groundwork).
//   cd tests/standalone && ./build.sh raymarch
//
// WHY THIS EXISTS: M7 renders the distant world by RAY-MARCHING the voxel
// brickmap on the GPU (HLSL) instead of meshing it. The GPU walk must agree
// with this CPU reference voxel-for-voxel — same first-hit voxel, same face
// normal, same entry distance. This harness PINS the oracle's exact contract so
// the future HLSL port has a spec to verify against (and so a refactor of the
// CPU walk can't silently drift). It asserts:
//   * a straight axis ray hits the first solid voxel at the right distance + face;
//   * the outward face normal is correct for +X/-X/+Y/+Z approaches;
//   * a ray whose ORIGIN is inside solid reports an immediate hit (t=0, no normal);
//   * a ray through a gap between solids passes the first and strikes the second;
//   * empty space (and bricks that don't exist) is skipped, not treated as solid;
//   * a ray that runs past max_dist before reaching solid reports a miss;
//   * a diagonal ray crosses bricks and still lands on the correct first solid;
//   * water-only voxels are NOT solid hits (the oracle keys off the type channel).
//
// Prints "[raymarch] PASS/FAIL"; returns 0 on success, 1 on any failure.

#include <cstdio>
#include <cmath>

#include "Core/Brickmap.h"
#include "Core/MaterialIds.h"
#include "Core/MiraVec.h"
#include "Core/WaterByteCodec.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;

static bool approx(double a, double b, double eps = 1e-6) { return std::fabs(a - b) <= eps; }

int main() {
    // ---------------------------------------------------------------------
    // 1. Straight +X ray hits the first solid voxel; entry distance + face.
    //    Solid at x=10. Origin at (0.5, 0.5, 0.5), dir +X. The ray enters the
    //    voxel x=10 at its low-X face (x=10.0), so t = 10.0 - 0.5 = 9.5, and the
    //    outward normal of the struck face points back at the ray: -X = (-1,0,0).
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        bm.set_type({10, 0, 0}, mat::STONE);
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 100.0);
        CHECK(h.hit, "+X ray hits the solid voxel");
        CHECK(h.voxel.x == 10 && h.voxel.y == 0 && h.voxel.z == 0, "+X hit is voxel (10,0,0)");
        CHECK(approx(h.t, 9.5), "+X entry distance = 9.5");
        CHECK(h.normal.x == -1 && h.normal.y == 0 && h.normal.z == 0, "+X struck face normal = -X");
        CHECK(h.type == mat::STONE, "+X hit reports the material id");
    }

    // ---------------------------------------------------------------------
    // 2. Face normals for the other approach directions.
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        bm.set_type({0, 0, 0}, mat::DIRT);
        // -X approach: start at high X moving toward -X. Enters voxel 0 at its
        // high-X face (x=1), outward normal +X.
        Brickmap::Hit hx = bm.raycast_solid(Vec3{5.5f, 0.5f, 0.5f}, Vec3{-1, 0, 0}, 100.0);
        CHECK(hx.hit && hx.normal.x == 1, "-X approach: struck face normal = +X");
        // +Y approach toward a solid above.
        Brickmap bm2; bm2.set_type({0, 8, 0}, mat::DIRT);
        Brickmap::Hit hy = bm2.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{0, 1, 0}, 100.0);
        CHECK(hy.hit && hy.normal.y == -1, "+Y approach: struck face normal = -Y");
        // +Z approach.
        Brickmap bm3; bm3.set_type({0, 0, 6}, mat::DIRT);
        Brickmap::Hit hz = bm3.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{0, 0, 1}, 100.0);
        CHECK(hz.hit && hz.normal.z == -1, "+Z approach: struck face normal = -Z");
    }

    // ---------------------------------------------------------------------
    // 3. Origin already inside solid -> immediate hit at t=0, zero normal.
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        bm.set_type({3, 3, 3}, mat::STONE);
        Brickmap::Hit h = bm.raycast_solid(Vec3{3.5f, 3.5f, 3.5f}, Vec3{1, 0, 0}, 100.0);
        CHECK(h.hit, "origin-inside-solid hits");
        CHECK(approx(h.t, 0.0), "origin-inside hit reports t=0");
        CHECK(h.voxel.x == 3 && h.voxel.y == 3 && h.voxel.z == 3, "origin-inside hit is the containing voxel");
        CHECK(h.normal.x == 0 && h.normal.y == 0 && h.normal.z == 0, "origin-inside hit has zero normal");
    }

    // ---------------------------------------------------------------------
    // 4. Gap test: two solids with a hole between them — the ray ignores the
    //    first if it doesn't cross it and lands on the one it does cross.
    //    Solids at x=5 and x=20 along z=0; a ray at z=0 hits x=5 first.
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        bm.set_type({5, 0, 0}, mat::STONE);
        bm.set_type({20, 0, 0}, mat::STONE);
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 100.0);
        CHECK(h.hit && h.voxel.x == 5, "first solid along the ray is the hit (x=5, not x=20)");

        // Carve the first solid away -> the same ray now reaches the second.
        bm.set_type({5, 0, 0}, mat::AIR);
        Brickmap::Hit h2 = bm.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 100.0);
        CHECK(h2.hit && h2.voxel.x == 20, "with the first removed, the ray reaches x=20");
    }

    // ---------------------------------------------------------------------
    // 5. Empty world / nonexistent bricks -> miss (not a false solid).
    // ---------------------------------------------------------------------
    {
        Brickmap bm; // nothing set
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 100.0);
        CHECK(!h.hit, "empty world: ray misses (empty bricks are skipped)");
    }

    // ---------------------------------------------------------------------
    // 6. max_dist: a solid beyond the ray's reach is a miss; extending the
    //    reach turns it into a hit (the GPU uses max_dist to bound the march).
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        bm.set_type({50, 0, 0}, mat::STONE);
        Brickmap::Hit miss = bm.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 10.0);
        CHECK(!miss.hit, "solid past max_dist is a miss");
        Brickmap::Hit hit = bm.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 100.0);
        CHECK(hit.hit && hit.voxel.x == 50, "same solid within a longer max_dist is a hit");
    }

    // ---------------------------------------------------------------------
    // 7. Diagonal ray across brick boundaries lands on the correct first solid.
    //    A solid wall plane at x=12 (several voxels in y); a 45° ray in the XY
    //    plane from the origin should strike the wall voxel at (12, 12, 0).
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        for (int y = 0; y < 24; ++y) bm.set_type({12, y, 0}, mat::STONE);
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{1, 1, 0}, 100.0);
        CHECK(h.hit, "diagonal ray hits the wall");
        CHECK(h.voxel.x == 12, "diagonal hit lands on the wall plane x=12");
        // Crossing bricks (brick size 8): x=12 is in brick 1, proving multi-brick
        // traversal works rather than only within the origin brick.
        CHECK(h.voxel.x / coords::BRICK == 1, "diagonal hit crossed into a second brick");
    }

    // ---------------------------------------------------------------------
    // 8. Water-only voxels are NOT solid hits — the oracle keys off the TYPE
    //    channel (air type + water byte => transparent to the solid ray-march).
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        bm.set_water({6, 0, 0}, static_cast<uint8_t>(WaterByteCodec::SOURCE_BYTE));
        bm.set_type({15, 0, 0}, mat::STONE);
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.5f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 100.0);
        CHECK(h.hit && h.voxel.x == 15, "water voxel is passed through; first SOLID (x=15) is the hit");
    }

    std::printf("[raymarch] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
