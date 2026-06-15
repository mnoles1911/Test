// test_chunkcoords.cpp — parity harness for Core/ChunkCoords.h.
//   cd tests/standalone && ./build.sh chunkcoords

#include <cstdio>
#include "Core/ChunkCoords.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;
using namespace mira::coords;

static bool veq(const Vec3i& a, int x, int y, int z) {
    return a.x == x && a.y == y && a.z == z;
}

int main() {
    // ---- floor_div / floor_mod handle negatives the way voxel math needs ----
    CHECK(floor_div(0, 32) == 0,   "floor_div 0");
    CHECK(floor_div(31, 32) == 0,  "floor_div 31 -> 0");
    CHECK(floor_div(32, 32) == 1,  "floor_div 32 -> 1");
    CHECK(floor_div(-1, 32) == -1, "floor_div -1 -> -1 (toward -inf, not 0)");
    CHECK(floor_div(-32, 32) == -1,"floor_div -32 -> -1");
    CHECK(floor_div(-33, 32) == -2,"floor_div -33 -> -2");
    CHECK(floor_mod(-1, 32) == 31, "floor_mod -1 -> 31");
    CHECK(floor_mod(0, 32) == 0,   "floor_mod 0");
    CHECK(floor_mod(33, 32) == 1,  "floor_mod 33 -> 1");

    // ---- chunk addressing round-trips ----
    CHECK(veq(chunk_of_voxel({0,0,0}), 0,0,0),       "voxel 0 -> chunk 0");
    CHECK(veq(chunk_of_voxel({31,31,31}), 0,0,0),    "voxel 31 -> chunk 0");
    CHECK(veq(chunk_of_voxel({32,0,0}), 1,0,0),      "voxel 32 -> chunk 1");
    CHECK(veq(chunk_of_voxel({-1,-1,-1}), -1,-1,-1), "voxel -1 -> chunk -1");
    CHECK(veq(local_in_chunk({-1,0,0}), 31,0,0),     "local of -1 -> 31");
    CHECK(veq(chunk_origin_voxel({1,2,3}), 32,64,96),"chunk 1,2,3 origin");

    // reconstruct: origin + local == original voxel, for a few points
    for (int v : {-65, -1, 0, 5, 32, 99}) {
        Vec3i p{v, v, v};
        Vec3i c = chunk_of_voxel(p);
        Vec3i l = local_in_chunk(p);
        Vec3i o = chunk_origin_voxel(c);
        CHECK(veq({o.x + l.x, o.y + l.y, o.z + l.z}, v, v, v), "chunk origin+local == voxel");
        CHECK(l.x >= 0 && l.x < CHUNK, "local in [0,CHUNK)");
    }

    // ---- brick addressing ----
    CHECK(veq(brick_of_voxel({8,0,0}), 1,0,0),  "voxel 8 -> brick 1");
    CHECK(veq(brick_of_voxel({-1,0,0}), -1,0,0),"voxel -1 -> brick -1");
    CHECK(veq(local_in_brick({-1,0,0}), 7,0,0), "brick local of -1 -> 7");
    CHECK(BRICKS_PER_CHUNK_AXIS == 4, "4 bricks per chunk axis");
    CHECK(VOXELS_PER_BRICK == 512, "512 voxels per brick");
    CHECK(VOXELS_PER_CHUNK == 32768, "32768 voxels per chunk");

    // ---- flatten is a bijection over a small grid ----
    {
        const int side = 4;
        bool seen[64] = {false};
        bool ok = true;
        for (int z = 0; z < side; ++z)
        for (int y = 0; y < side; ++y)
        for (int x = 0; x < side; ++x) {
            int i = flatten(x, y, z, side);
            if (i < 0 || i >= 64 || seen[i]) ok = false;
            seen[i] = true;
        }
        CHECK(ok, "flatten is a bijection over 4^3");
        CHECK(flatten(1,0,0,side) == 1, "X is fastest-varying");
        CHECK(flatten(0,1,0,side) == side, "Y strides by side");
        CHECK(flatten(0,0,1,side) == side*side, "Z strides by side^2");
    }

    // ---- face offsets are the 6 unit cardinals in canonical order ----
    CHECK(veq(FACE_OFFSET[0], -1,0,0) && veq(FACE_OFFSET[1], 1,0,0), "X faces");
    CHECK(veq(FACE_OFFSET[2], 0,-1,0) && veq(FACE_OFFSET[3], 0,1,0), "Y faces");
    CHECK(veq(FACE_OFFSET[4], 0,0,-1) && veq(FACE_OFFSET[5], 0,0,1), "Z faces");

    // ---- LWC tile split reconstructs ----
    {
        const int tile = 4096; // voxels per tile edge
        Vec3i p{ -5, 100000, 4096 };
        Vec3i t = tile_of_voxel(p, tile);
        Vec3i l = local_in_tile(p, tile);
        CHECK(t.x == -1 && l.x == 4091, "tile split negative axis");
        CHECK(t.z == 1 && l.z == 0,     "tile split on boundary");
        CHECK(t.x * tile + l.x == p.x,  "tile origin+local == voxel (x)");
        CHECK(t.y * tile + l.y == p.y,  "tile origin+local == voxel (y)");
    }

    std::printf("[chunkcoords] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
