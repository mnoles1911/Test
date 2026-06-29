// test_atlas.cpp — parity harness for Core/AtlasUV.h + MeshTypes face classes.
//   cd tests/standalone && ./build.sh atlas

#include <cstdio>
#include <cmath>
#include "Core/AtlasUV.h"
#include "Core/MeshTypes.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)
static bool approx(float a, float b) { return std::fabs(a - b) < 1e-5f; }
// Helper so braced Tile literals don't trip the comma-counting in CHECK(...).
static bool teq(mira::atlas::Tile t, int col, int row) { return t.col == col && t.row == row; }

using namespace mira;

int main() {
    // ---- atlas grid constants ----
    CHECK(atlas::COLS == 64 && atlas::ROWS == 64, "64x64 tile grid");

    // ---- per-face tilesets transcribed from the Godot blocky library ----
    CHECK(teq(atlas::tile_for(mat::STONE, FACE_POS_Y), 0,0), "stone top tile (0,0)");
    // grass: green top, grass-side, dirt bottom (the signature 3-texture block)
    CHECK(teq(atlas::tile_for(mat::GRASS, FACE_POS_Y), 2,0), "grass top (2,0)");
    CHECK(teq(atlas::tile_for(mat::GRASS, FACE_NEG_X), 3,0), "grass side (3,0)");
    CHECK(teq(atlas::tile_for(mat::GRASS, FACE_POS_X), 3,0), "grass side both x");
    CHECK(teq(atlas::tile_for(mat::GRASS, FACE_NEG_Z), 3,0), "grass side z");
    CHECK(teq(atlas::tile_for(mat::GRASS, FACE_NEG_Y), 1,0), "grass bottom = dirt (1,0)");
    // log: rings on top/bottom, bark on the sides
    CHECK(teq(atlas::tile_for(mat::LOG, FACE_POS_Y), 0,1), "log top rings (0,1)");
    CHECK(teq(atlas::tile_for(mat::LOG, FACE_POS_X), 1,1), "log bark side (1,1)");
    CHECK(teq(atlas::tile_for(mat::DIRT, FACE_POS_Y), 1,0), "dirt all faces (1,0)");
    CHECK(teq(atlas::tile_for(mat::STONE_DARK, FACE_POS_Y), 9,0), "stone_dark (9,0)");
    // unknown id falls back to stone tile, not a crash
    CHECK(teq(atlas::tile_for(200, FACE_POS_Y), 0,0), "unknown id -> fallback tile");

    // ---- UV rect math: each tile is 1/64 of the atlas ----
    atlas::UVRect r = atlas::uv_rect({0,0});
    CHECK(approx(r.u0,0.0f) && approx(r.v0,0.0f), "tile (0,0) min corner");
    CHECK(approx(r.u1, 1.0f/64.0f) && approx(r.v1, 1.0f/64.0f), "tile (0,0) spans 1/64");
    r = atlas::uv_rect({3,0});
    CHECK(approx(r.u0, 3.0f/64.0f), "tile (3,0) u0 = 3/64");
    CHECK(approx(r.u1, 4.0f/64.0f), "tile (3,0) u1 = 4/64");
    r = atlas::uv_rect({0,1});
    CHECK(approx(r.v0, 1.0f/64.0f), "tile (0,1) v0 = 1/64");
    // uv_for matches uv_rect(tile_for(...))
    atlas::UVRect a = atlas::uv_for(mat::GRASS, FACE_POS_Y);
    atlas::UVRect b = atlas::uv_rect(atlas::tile_for(mat::GRASS, FACE_POS_Y));
    CHECK(approx(a.u0,b.u0) && approx(a.v1,b.v1), "uv_for == uv_rect(tile_for)");

    // ---- face_class_of buckets ids into transparency sections (MeshTypes) ----
    CHECK(face_class_of(mat::STONE) == FaceClass::Opaque,  "stone is opaque");
    CHECK(face_class_of(mat::LOG)   == FaceClass::Opaque,  "log is opaque");
    CHECK(face_class_of(mat::LEAVES)== FaceClass::Cutout,  "leaves are cutout");
    CHECK(face_class_of(16)         == FaceClass::Water,   "fluid id 16 is water");
    CHECK(face_class_of(23)         == FaceClass::Water,   "fluid id 23 is water");
    CHECK(face_class_of(mat::GRASS_BLADE_ID) == FaceClass::Flora, "grass blade is flora");
    CHECK(face_class_of(mat::TWIG_ID)        == FaceClass::Flora, "twig is flora");
    CHECK(face_class_of(mat::AIR)   == FaceClass::Opaque,  "air defaults opaque (never emitted)");

    // ---- face normals match the canonical dir order ----
    CHECK(FACE_NORMAL[FACE_POS_Y][1] == 1.0f, "+Y normal up");
    CHECK(FACE_NORMAL[FACE_NEG_X][0] == -1.0f, "-X normal");

    std::printf("[atlas   ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
