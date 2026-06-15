// test_brickmap.cpp — parity harness for Core/Brickmap.h.
//   cd tests/standalone && ./build.sh brickmap

#include <cstdio>
#include <cmath>
#include "Core/Brickmap.h"
#include "Core/WaterByteCodec.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)
static bool approx(double a, double b) { return std::fabs(a - b) < 1e-4; }

using namespace mira;

int main() {
    // ---- sparse storage: absent bricks read as air, allocate on write ----
    {
        Brickmap bm;
        CHECK(bm.brick_count() == 0, "fresh brickmap has no bricks");
        CHECK(bm.type_at({5, 5, 5}) == mat::AIR, "absent voxel reads as air");
        CHECK(bm.water_at({5, 5, 5}) == 0, "absent voxel has no water");

        bm.set_type({5, 5, 5}, mat::STONE);
        CHECK(bm.type_at({5, 5, 5}) == mat::STONE, "stored type reads back");
        CHECK(bm.brick_count() == 1, "one write -> one brick");

        // A voxel in the same 8^3 brick doesn't allocate a second brick.
        bm.set_type({6, 6, 6}, mat::DIRT);
        CHECK(bm.brick_count() == 1, "same-brick write reuses the brick");
        // Crossing the 8-voxel boundary lands in a new brick.
        bm.set_type({8, 6, 6}, mat::DIRT);
        CHECK(bm.brick_count() == 2, "crossing a brick boundary allocates a new brick");
    }

    // ---- negative coordinates and brick assignment ----
    {
        Brickmap bm;
        bm.set_type({-1, -1, -1}, mat::STONE);
        CHECK(bm.type_at({-1, -1, -1}) == mat::STONE, "negative-coord round trip");
        CHECK(bm.has_brick(coords::brick_of_voxel({-1, -1, -1})), "negative voxel -> brick -1");
        CHECK(bm.type_at({-9, -1, -1}) == mat::AIR, "neighbour brick still air");
    }

    // ---- water channel + sparse garbage-collection ----
    {
        Brickmap bm;
        bm.set_water({3, 3, 3}, static_cast<uint8_t>(WaterByteCodec::SOURCE_BYTE));
        CHECK(WaterByteCodec::is_water(bm.water_at({3, 3, 3})), "water byte stored");
        CHECK(bm.brick_count() == 1, "water write allocated a brick");

        // Clear it back to nothing -> the brick is freed (stays sparse).
        bm.set_water({3, 3, 3}, 0);
        CHECK(bm.brick_count() == 0, "emptying the last cell frees the brick");

        // type + water in one cell: clearing only one keeps the brick alive.
        bm.set_type({3, 3, 3}, mat::STONE);
        bm.set_water({3, 3, 3}, static_cast<uint8_t>(WaterByteCodec::SOURCE_BYTE));
        bm.set_type({3, 3, 3}, mat::AIR); // water remains -> brick stays
        CHECK(bm.brick_count() == 1, "cell still nonzero (water) -> brick kept");
        CHECK(bm.brick_solid_count(coords::brick_of_voxel({3,3,3})) == 0, "solid_count dropped to 0");
        bm.set_water({3, 3, 3}, 0); // now fully empty -> freed
        CHECK(bm.brick_count() == 0, "now fully empty -> brick freed");
    }

    // ---- ray-march: straight +X hit, correct normal and distance ----
    {
        Brickmap bm;
        bm.set_type({10, 0, 0}, mat::STONE); // cube spans [10,11)x[0,1)x[0,1)
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.0f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 100.0);
        CHECK(h.hit, "ray hits the solid voxel");
        CHECK(h.voxel == Vec3i(10, 0, 0), "hit the right voxel");
        CHECK(h.normal == Vec3i(-1, 0, 0), "entry normal points back along -X");
        CHECK(approx(h.t, 10.0), "hit distance == 10");
        CHECK(h.type == mat::STONE, "hit carries the material id");
    }

    // ---- ray pointing away finds nothing ----
    {
        Brickmap bm;
        bm.set_type({10, 0, 0}, mat::STONE);
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.0f, 0.5f, 0.5f}, Vec3{-1, 0, 0}, 100.0);
        CHECK(!h.hit, "ray pointing away hits nothing");
    }

    // ---- traversal through a long stretch of empty bricks (two-level skip range) ----
    {
        Brickmap bm;
        bm.set_type({100, 0, 0}, mat::MARBLE); // far away, many empty bricks between
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.0f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 200.0);
        CHECK(h.hit && h.voxel == Vec3i(100, 0, 0), "ray crosses empty space and hits far voxel");
        CHECK(approx(h.t, 100.0), "far hit distance == 100");
        // But a max_dist short of it must NOT report a hit.
        Brickmap::Hit h2 = bm.raycast_solid(Vec3{0.0f, 0.5f, 0.5f}, Vec3{1, 0, 0}, 50.0);
        CHECK(!h2.hit, "max_dist short of the target -> no hit");
    }

    // ---- a +Y approach gets a -Y entry normal ----
    {
        Brickmap bm;
        bm.set_type({0, 10, 0}, mat::STONE);
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.5f, 0.0f, 0.5f}, Vec3{0, 1, 0}, 100.0);
        CHECK(h.hit && h.voxel == Vec3i(0, 10, 0), "vertical ray hits the voxel above");
        CHECK(h.normal == Vec3i(0, -1, 0), "top approach -> -Y entry normal");
    }

    // ---- a ray that passes over the voxel misses it ----
    {
        Brickmap bm;
        bm.set_type({10, 0, 0}, mat::STONE);
        // Start below and aim up-and-over so the path clears the single cube.
        Brickmap::Hit h = bm.raycast_solid(Vec3{0.0f, 0.5f, 0.5f}, Vec3{1, 1, 0}, 100.0);
        CHECK(!h.hit, "diagonal ray clears the lone voxel (miss)");
    }

    // ---- origin starting inside solid reports an immediate hit ----
    {
        Brickmap bm;
        bm.set_type({4, 4, 4}, mat::STONE);
        Brickmap::Hit h = bm.raycast_solid(Vec3{4.5f, 4.5f, 4.5f}, Vec3{1, 0, 0}, 10.0);
        CHECK(h.hit && approx(h.t, 0.0) && h.voxel == Vec3i(4, 4, 4), "origin inside solid -> t=0 hit");
    }

    std::printf("[brickmap] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
