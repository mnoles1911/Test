// test_color.cpp — parity harness for Core/VoxelColor.h.
//   cd tests/standalone && ./build.sh color
//
// Verifies the solid-per-face voxel coloring: exact base_color palette values,
// the unknown-id -> stone fallback, the per-direction face_shade ordering (top
// brightest, bottom darkest, all six distinct), and shaded_color = base × shade
// with rounding + clamping. Also checks the whole water id range maps to one tint.

#include <cstdio>
#include "Core/VoxelColor.h"
#include "Core/MaterialIds.h"
#include "Core/MeshTypes.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;

// Helper so braced Rgb8 comparisons don't trip CHECK's comma counting.
static bool ceq(Rgb8 c, int r, int g, int b) {
    return c.r == r && c.g == g && c.b == b;
}

int main() {
    // ---- base_color: exact palette values transcribed from the Godot color_high ----
    CHECK(ceq(base_color(mat::STONE), 158, 153, 140), "stone base color");
    CHECK(ceq(base_color(mat::GRASS),  97, 140,  56), "grass base color");
    CHECK(ceq(base_color(mat::DIRT),  107,  77,  46), "dirt base color");
    CHECK(ceq(base_color(mat::SAND),  224, 204, 148), "sand base color");
    CHECK(ceq(base_color(mat::LOG),    92,  59,  26), "log base color");
    CHECK(ceq(base_color(mat::LEAVES), 59,  92,  33), "leaves base color");
    CHECK(ceq(base_color(13),         255, 255, 255), "snow base color");
    CHECK(ceq(base_color(mat::GRASS_BLADE_ID), 115, 158, 66), "grass_blade base color");
    CHECK(ceq(base_color(mat::FLOWER_RED_ID),  217,  46, 41), "flower_red base color");
    CHECK(ceq(base_color(mat::TWIG_ID),        102,  74, 46), "twig base color");

    // ---- unknown id falls back to stone (not black / not a crash) ----
    CHECK(ceq(base_color(200),  158, 153, 140), "unknown id -> stone fallback");
    CHECK(ceq(base_color(mat::AIR), 158, 153, 140), "air id -> stone fallback");

    // ---- the whole water id range maps to the single water tint ----
    const Rgb8 water{ 51, 102, 153 };
    CHECK(ceq(base_color(mat::LEGACY_WATER_ID), water.r, water.g, water.b), "legacy water 5 -> water tint");
    for (int id = mat::WATER_FLUID_BASE_ID;
         id < mat::WATER_FLUID_BASE_ID + mat::WATER_LEVEL_COUNT; ++id) {
        CHECK(ceq(base_color(id), water.r, water.g, water.b), "fluid level id -> water tint");
    }

    // ---- face_shade: distinct per direction, top brightest, bottom darkest ----
    const float top = face_shade(FACE_POS_Y);
    const float bot = face_shade(FACE_NEG_Y);
    const float px  = face_shade(FACE_POS_X);
    const float nx  = face_shade(FACE_NEG_X);
    const float pz  = face_shade(FACE_POS_Z);
    const float nz  = face_shade(FACE_NEG_Z);

    CHECK(top == 1.00f, "top shade is 1.00");
    CHECK(bot == 0.50f, "bottom shade is 0.50");
    CHECK(top > px && px > pz && pz > nx && nx > nz && nz > bot,
          "shade ordering top>+X>+Z>-X>-Z>bottom");

    // All six distinct (a single cube shows six different shades).
    const float shades[6] = { top, bot, px, nx, pz, nz };
    bool all_distinct = true;
    for (int i = 0; i < 6; ++i)
        for (int j = i + 1; j < 6; ++j)
            if (shades[i] == shades[j]) all_distinct = false;
    CHECK(all_distinct, "all six face shades distinct");

    // ---- shaded_color = base × shade, rounded + clamped ----
    // Top face: shade 1.0 -> color unchanged.
    CHECK(ceq(shaded_color(mat::GRASS, FACE_POS_Y), 97, 140, 56),
          "grass top = base (shade 1.0)");

    // Stone +X: shade 0.86. 158*0.86=135.88->136, 153*0.86=131.58->132,
    //           140*0.86=120.4->120.
    CHECK(ceq(shaded_color(mat::STONE, FACE_POS_X), 136, 132, 120),
          "stone +X = base*0.86 rounded");

    // Snow bottom (255 × 0.50 = 127.5 -> 128) exercises rounding; nothing clamps
    // here because all channels stay <= 255, so also assert no overflow wrap.
    CHECK(ceq(shaded_color(13, FACE_NEG_Y), 128, 128, 128),
          "snow bottom = 255*0.5 rounded to 128 (no clamp wrap)");

    // Explicit clamp check: the brightest possible channel × the brightest shade
    // (255 × 1.0 = 255) must stay exactly 255, never overflow the uint8.
    CHECK(shaded_color(13, FACE_POS_Y).r == 255, "snow top channel clamps at 255");

    // ---- lod_debug_color: DIAGNOSTIC per-LOD palette (cvar mira.LodDebug) ----
    // Per-chunk ramp: green(L0) -> magenta(L5); supers are a distinct cool ramp.
    CHECK(ceq(lod_debug_color(0, /*super=*/false),   0, 255,   0), "per-chunk L0 = green");
    CHECK(ceq(lod_debug_color(2, false),           255, 255,   0), "per-chunk L2 = yellow");
    CHECK(ceq(lod_debug_color(4, false),           255,   0,   0), "per-chunk L4 = red");
    CHECK(ceq(lod_debug_color(5, false),           255,   0, 255), "per-chunk L5 = magenta");
    CHECK(ceq(lod_debug_color(0, /*super=*/true),    0, 200, 180), "super L0 = teal");
    CHECK(ceq(lod_debug_color(5, true),            160,   0, 255), "super L5 = violet");

    // Clamp out-of-range LODs into [0,5] (never read past the palette).
    CHECK(ceq(lod_debug_color(-3, false), 0, 255, 0),   "LOD < 0 clamps to L0");
    CHECK(ceq(lod_debug_color(99, false), 255, 0, 255), "LOD > 5 clamps to L5 (per-chunk)");
    CHECK(ceq(lod_debug_color(99, true),  160, 0, 255), "LOD > 5 clamps to L5 (super)");

    // Per-chunk and super for the SAME LOD number must be DIFFERENT colors, so the
    // tester can never confuse a super tile with a near chunk at the same LOD.
    for (int L = 0; L <= 5; ++L) {
        const Rgb8 c = lod_debug_color(L, false);
        const Rgb8 s = lod_debug_color(L, true);
        CHECK(!(c.r == s.r && c.g == s.g && c.b == s.b),
              "per-chunk vs super color differs at this LOD");
    }

    std::printf("[color   ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
