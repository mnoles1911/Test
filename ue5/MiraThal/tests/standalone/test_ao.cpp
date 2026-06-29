// test_ao.cpp — parity harness for Core/VoxelAO.h.
//   cd tests/standalone && ./build.sh ao

#include <cstdio>
#include <cmath>
#include <set>
#include <array>
#include "Core/VoxelAO.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)
static bool approx(float a, float b) { return std::fabs(a - b) < 1e-5f; }

using namespace mira;

int main() {
    // ---- the 0fps corner truth table ----
    CHECK(ao::vertex_ao(false,false,false) == 3, "open corner = full light");
    CHECK(ao::vertex_ao(true, false,false) == 2, "one side occluder");
    CHECK(ao::vertex_ao(false,true, false) == 2, "other side occluder");
    CHECK(ao::vertex_ao(false,false,true)  == 2, "diagonal corner only");
    CHECK(ao::vertex_ao(true, false,true)  == 1, "side + corner");
    CHECK(ao::vertex_ao(true, true, false) == 0, "both sides = sealed crease (0)");
    CHECK(ao::vertex_ao(true, true, true)  == 0, "both sides dominate corner");
    CHECK(ao::vertex_ao(false,true, true)  == 1, "other side + corner");

    // ---- weight mapping ----
    CHECK(approx(ao::ao_weight(3), 1.0f),       "level 3 -> full weight");
    CHECK(approx(ao::ao_weight(0), 0.0f),       "level 0 -> dark");
    CHECK(approx(ao::ao_weight(2), 2.0f/3.0f),  "level 2 -> 0.667");

    // ---- occluder predicate (air gotcha) ----
    CHECK(ao::is_occluder(mat::STONE) == true,  "stone occludes");
    CHECK(ao::is_occluder(mat::AIR)   == false, "AIR never occludes (enum-default trap)");
    CHECK(ao::is_occluder(mat::LEAVES)== false, "leaves don't occlude AO");
    CHECK(ao::is_occluder(16)         == false, "water doesn't occlude AO");
    CHECK(ao::is_occluder(mat::GRASS_BLADE_ID) == false, "flora doesn't occlude AO");

    // ---- compute_face_ao: an isolated face is fully lit ----
    {
        auto empty = [](int,int,int){ return false; };
        ao::CornerAO a = ao::compute_face_ao(empty, 0,0,0, FACE_POS_Y);
        CHECK(a.uniform_full(), "no neighbours -> all corners level 3");
        CHECK(!a.should_flip_diagonal(), "uniform AO -> no diagonal flip");
    }

    // ---- one occluder darkens exactly the two corners that touch it ----
    {
        // +Y face of voxel (0,0,0): axis=Y, ua=Z, va=X, base=(0,1,0).
        // Place a solid at (0,1,-1) = base stepped -1 along Z(ua). That is the
        // "side1" sample for the two corners with su=-1 (param 00 and 01).
        std::set<std::array<int,3>> solids = { {{0,1,-1}} };
        auto occ = [&](int x,int y,int z){ return solids.count({{x,y,z}}) > 0; };
        ao::CornerAO a = ao::compute_face_ao(occ, 0,0,0, FACE_POS_Y);
        CHECK(a.level[0] == 2, "corner 00 darkened by side occluder");
        CHECK(a.level[3] == 2, "corner 01 darkened by side occluder");
        CHECK(a.level[1] == 3, "corner 10 untouched");
        CHECK(a.level[2] == 3, "corner 11 untouched");
        CHECK(!a.should_flip_diagonal(), "symmetric [2,3,3,2] diagonals -> no flip");
    }

    // ---- a sealed inside edge drives a corner to 0 ----
    {
        // +Y face of (0,0,0): both side samples of corner 00 are su=-1(Z) and
        // sv=-1(X). Occlude both (0,1,-1) and (-1,1,0) -> corner 00 = 0.
        std::set<std::array<int,3>> solids = { {{0,1,-1}}, {{-1,1,0}} };
        auto occ = [&](int x,int y,int z){ return solids.count({{x,y,z}}) > 0; };
        ao::CornerAO a = ao::compute_face_ao(occ, 0,0,0, FACE_POS_Y);
        CHECK(a.level[0] == 0, "both sides solid -> corner 00 sealed (0)");
        // [0,3,3,3]: diagonal 00-11 = 3, diagonal 10-01 = 6 -> flip toward the lit pair.
        CHECK(a.should_flip_diagonal(), "one dark corner -> flip diagonal");
    }

    std::printf("[ao      ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
