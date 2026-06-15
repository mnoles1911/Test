// test_materials.cpp — parity harness for Core/MaterialIds.h.
//
// Verifies the consolidated water/flora/surface-detail id authority against the
// exact ranges from the Godot WaterMaterial.gd + FloraMaterial.gd. This is the
// shared id contract every other Core system (gravity, water, generator) range-
// checks against, so it gets its own selector.
//
// Compile/run (or just: cd tests/standalone && ./build.sh materials):
//   clang++ -std=c++17 -Wall -Wextra -I ../../Source/MiraThalVoxel/Public \
//       test_materials.cpp -o /tmp/test_materials && /tmp/test_materials

#include <cstdio>
#include "Core/MaterialIds.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

int main() {
    using namespace mira::mat;

    // --- water id range (WaterMaterial.is_water_type) ---
    CHECK(is_water_type(5),  "legacy cube id 5 is water");
    CHECK(is_water_type(16), "fluid base 16 is water");
    CHECK(is_water_type(23), "full fluid 23 is water");
    CHECK(!is_water_type(15), "15 (below fluid base) is not water");
    CHECK(!is_water_type(24), "24 (flora) is not water");
    CHECK(!is_water_type(0),  "air is not water");
    CHECK(!is_water_type(3),  "grass is not water");
    CHECK(FULL_FLUID_ID == 23, "full fluid id is 23");

    // --- level -> render id projection ---
    CHECK(render_id_for_level(0, 0) == 0,  "level 0 -> air");
    CHECK(render_id_for_level(1, 0) == 16, "level 1 -> 16");
    CHECK(render_id_for_level(8, 0) == 23, "level 8 -> 23");
    CHECK(render_id_for_level(99, 0) == 23, "level clamps to 8 -> 23");
    CHECK(map_legacy_id(5) == 23, "legacy 5 migrates to 23");
    CHECK(map_legacy_id(2) == 2,  "non-water id unchanged by migration");

    // --- flora vegetation (24..26) ---
    CHECK(is_flora(24), "grass_blade is flora");
    CHECK(is_flora(25), "flower_red is flora");
    CHECK(is_flora(26), "flower_blue is flora");
    CHECK(!is_flora(27), "pebble is NOT flora");
    CHECK(!is_flora(23), "water is not flora");

    // --- surface detail (27..28) ---
    CHECK(is_surface_detail(27), "pebble is surface detail");
    CHECK(is_surface_detail(28), "twig is surface detail");
    CHECK(!is_surface_detail(26), "flower is not surface detail");
    CHECK(!is_surface_detail(29), "29 is not surface detail");

    // --- pass-through (24..28) = the physics exclusion range ---
    for (int id = 24; id <= 28; ++id) CHECK(is_passthrough(id), "24..28 passthrough");
    CHECK(!is_passthrough(23), "water is solid to physics (not passthrough)");
    CHECK(!is_passthrough(29), "29 is solid (not passthrough)");
    CHECK(!is_passthrough(0),  "air id is not 'passthrough decoration'");
    CHECK(PASSTHROUGH_COUNT == 5, "passthrough block is 5 wide (24..28)");

    // water and pass-through id spaces never overlap
    for (int id = 16; id <= 23; ++id) CHECK(!is_passthrough(id), "fluid never passthrough");
    for (int id = 24; id <= 28; ++id) CHECK(!is_water_type(id),  "decoration never water");

    std::printf("[materials] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
