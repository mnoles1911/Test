// test_gen.cpp — standalone parity/determinism harness for the engine-agnostic
// terrain heightmap + biome generator (Core/HeightmapGenerator.{h,cpp}).
//
// This mirrors the Godot `gen` headless selector's role: it is the iterative
// verification loop for the ported generator math, running HERE under clang
// because Unreal can't build in the dev container but the Core is pure C++17.
//
// IMPORTANT (see Core/Noise.h): the Core noise is NOT bit-exact with Godot's
// FastNoiseLite, so we assert STRUCTURAL + DETERMINISM properties, not
// Godot voxel-for-voxel parity:
//   * determinism: same (x, z, seed) → identical ground_y + materials forever
//   * liveness:    ground_y actually varies across x/z (the noise is alive)
//   * banding:     grass on top, dirt below it, stone deep; sand on beaches;
//                  columns below sea level flagged as water
//   * scatter:     flora + ore-style hash3 scatter is deterministic per (x,z,seed)
//   * biome:       biome weights sum to 1, ≤3 contributors, sorted, picks
//                  are deterministic
//
// COMPILE + RUN (from this directory, tests/standalone/), all on one line:
//   clang++ -std=c++17 -Wall -Wextra -I ../../Source/MiraThalVoxel/Public  test_gen.cpp  ../../Source/MiraThalVoxel/Private/Core/HeightmapGenerator.cpp  -o /tmp/test_gen && /tmp/test_gen
//
// Prints "[gen     ] PASS" / "[gen     ] FAIL"; returns 0 on success, 1 on any
// failure (matches tests/standalone/test_main.cpp style).

#include <cstdio>
#include <string>
#include <vector>

#include "Core/HeightmapGenerator.h"

// ---- Minimal assertion plumbing (no gtest — zero setup) --------------------
static int g_checks = 0;
static int g_fails = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!(cond)) {                                                          \
            ++g_fails;                                                          \
            std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);     \
        }                                                                       \
    } while (0)

#define CHECK_EQ(a, b, msg)                                                     \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!((a) == (b))) {                                                    \
            ++g_fails;                                                          \
            std::printf("  FAIL %s  expected=%lld got=%lld  (%s:%d)\n",         \
                        (msg), (long long)(b), (long long)(a), __FILE__,        \
                        __LINE__);                                              \
        }                                                                       \
    } while (0)

using namespace mira;

// Build the five-biome profile set used by the biome-path tests. Indices match
// the bindings we wire below: 0 plains, 1 hills, 2 forest, 3 desert, 4 mountains.
static std::vector<BiomeProfile> make_biomes() {
    std::vector<BiomeProfile> v;

    BiomeProfile plains;
    plains.base_amplitude_m = 4.0;
    plains.base_frequency_per_m = 0.0010;
    plains.flatness = 0.7;
    plains.top_material_id = mat::GRASS;
    plains.slope_material_id = mat::STONE;
    plains.grass_density = 0.4;
    plains.flower_density = 0.03;
    plains.tree_density = 0.0;
    v.push_back(plains);

    BiomeProfile hills;
    hills.base_amplitude_m = 12.0;
    hills.base_frequency_per_m = 0.0015;
    hills.top_material_id = mat::GRASS;
    hills.slope_material_id = mat::STONE;
    hills.grass_density = 0.3;
    hills.tree_density = 0.05;
    v.push_back(hills);

    BiomeProfile forest;
    forest.base_amplitude_m = 10.0;
    forest.base_frequency_per_m = 0.0014;
    forest.top_material_id = mat::GRASS;
    forest.slope_material_id = mat::STONE;
    forest.grass_density = 0.5;
    forest.tree_density = 0.4;
    v.push_back(forest);

    BiomeProfile desert;
    desert.base_amplitude_m = 6.0;
    desert.base_frequency_per_m = 0.0012;
    desert.top_material_id = mat::SAND;     // desert tops are sand, not grass
    desert.slope_material_id = mat::STONE;
    desert.grass_density = 0.0;
    desert.micro_relief_chance = 0.05;
    desert.tree_density = 0.0;
    v.push_back(desert);

    BiomeProfile mountains;
    mountains.base_amplitude_m = 40.0;
    mountains.base_frequency_per_m = 0.0016;
    mountains.ridge_mix = 0.8;
    mountains.top_material_id = mat::STONE; // bare rock peaks
    mountains.slope_material_id = mat::STONE;
    mountains.grass_density = 0.0;
    mountains.tree_density = 0.0;
    v.push_back(mountains);

    return v;
}

// ---------------------------------------------------------------------------
// Selector: gen
// ---------------------------------------------------------------------------
static void sel_gen() {
    // ---- 1. Material id ranges + sea/floor constants (carried over) --------
    CHECK_EQ(mat::STONE, 1, "stone id = 1");
    CHECK_EQ(mat::DIRT, 2, "dirt id = 2");
    CHECK_EQ(mat::GRASS, 3, "grass id = 3");
    CHECK_EQ(mat::SAND, 4, "sand id = 4");
    CHECK_EQ(mat::TREE_LOG, 10, "tree log id = 10");
    CHECK_EQ(mat::TREE_LEAVES, 11, "tree leaves id = 11");
    CHECK_EQ(mat::WATER_FLUID_BASE, 16, "water fluid base id = 16");
    CHECK_EQ(mat::WATER_FULL, 23, "water full level id = 23");
    CHECK_EQ(mat::WATER_SOURCE_BYTE, 0x18, "water source byte = 0x18");
    CHECK_EQ(mat::FLORA_GRASS_BLADE, 24, "flora grass blade id = 24");
    CHECK_EQ(mat::FLORA_FLOWER_RED, 25, "flower red id = 25");
    CHECK_EQ(mat::FLORA_FLOWER_BLUE, 26, "flower blue id = 26");
    CHECK_EQ(mat::DETAIL_PEBBLE, 27, "pebble id = 27");
    CHECK_EQ(mat::DETAIL_TWIG, 28, "twig id = 28");

    {
        HeightmapGenerator g;
        CHECK_EQ(g.sea_level_voxels, 120, "sea level = 120 voxels (12 m)");
        CHECK_EQ(g.world_floor_voxel_y, -500, "world floor = -500 voxels (-50 m)");
        CHECK_EQ(g.beach_y_threshold, 74, "beach y threshold = 74");
        CHECK_EQ(g.height_offset_voxels, 100, "legacy height offset = 100");
    }

    // ---- 2. DETERMINISM: same (x,z,seed) → identical results forever -------
    {
        HeightmapGenerator g;
        g.set_seed(12345);
        for (int i = 0; i < 200; ++i) {
            const int x = (i * 137) - 5000;
            const int z = (i * -91) + 3000;
            const int a = g.compute_ground_y(x, z);
            const int b = g.compute_ground_y(x, z);
            CHECK_EQ(a, b, "ground_y stable across repeated calls");

            ColumnInfo c1 = g.resolve_column(x, z);
            ColumnInfo c2 = g.resolve_column(x, z);
            CHECK_EQ(c1.ground_y, c2.ground_y, "column ground_y stable");
            CHECK_EQ(c1.top_id, c2.top_id, "column top_id stable");
            CHECK_EQ(c1.flora_id, c2.flora_id, "column flora_id stable");

            // Material stack stable at several depths.
            for (int d = -2; d < 8; ++d) {
                const int wy = c1.ground_y - d;
                const int m1 = g.material_at(x, wy, z, c1);
                const int m2 = g.material_at(x, wy, z, c2);
                CHECK_EQ(m1, m2, "material_at stable across calls");
            }
        }
    }

    // Different seed → field actually changes (the seed is live).
    {
        HeightmapGenerator g1; g1.set_seed(1);
        HeightmapGenerator g2; g2.set_seed(2);
        int diffs = 0;
        for (int i = 0; i < 300; ++i) {
            const int x = i * 53;
            const int z = i * -29;
            if (g1.compute_ground_y(x, z) != g2.compute_ground_y(x, z)) ++diffs;
        }
        CHECK(diffs > 50, "different seeds give different terrain");
    }

    // ---- 3. LIVENESS: ground_y varies across x/z (noise is alive) ---------
    {
        HeightmapGenerator g;
        g.set_seed(777);
        int min_y = 1 << 30, max_y = -(1 << 30);
        for (int x = -2000; x <= 2000; x += 23) {
            for (int z = -2000; z <= 2000; z += 29) {
                const int y = g.compute_ground_y(x, z);
                if (y < min_y) min_y = y;
                if (y > max_y) max_y = y;
            }
        }
        CHECK(max_y > min_y, "ground_y varies across the sampled field");
        CHECK((max_y - min_y) > 5, "ground_y has meaningful relief, not flat");
    }

    // ---- 4. BANDING: grass top, dirt, stone deep; sand beaches; water -----
    {
        HeightmapGenerator g;
        g.set_seed(2024);
        // Pin the surface high above the beach + sea line so this column is a
        // normal grass column (force a flat, non-cliff surface by zeroing the
        // noise amplitudes — pure banding test).
        g.height_range_voxels = 0.0;
        g.mid_amplitude_voxels = 0;
        g.detail_amplitude_voxels = 0;
        g.height_offset_voxels = 300; // well above sea(120) and beach(74)

        ColumnInfo col = g.resolve_column(100, 100);
        CHECK_EQ(col.ground_y, 300, "flat column sits at the offset");
        CHECK(!col.is_cliff, "flat column is not a cliff");
        CHECK(!col.below_sea, "column above sea level is not water");
        CHECK_EQ(col.top_id, mat::GRASS, "high flat column is grass-topped");

        // Top voxel = grass, the next few = dirt, deeper = stone.
        const int top = g.material_at(100, col.ground_y, 100, col);
        CHECK_EQ(top, mat::GRASS, "depth 0 is grass");
        const int just_below = g.material_at(100, col.ground_y - 1, 100, col);
        CHECK_EQ(just_below, mat::DIRT, "depth 1 is dirt");
        const int deeper = g.material_at(100, col.ground_y - 2, 100, col);
        CHECK_EQ(deeper, mat::DIRT, "depth 2 is dirt (within dirt band)");
        // dirt band ends at grass(1)+dirt(3)=4; depth 4 is stone-family.
        const int deep = g.material_at(100, col.ground_y - 6, 100, col);
        CHECK(deep == mat::STONE || deep == mat::MARBLE || deep == mat::STONE_DARK,
              "deep voxel is stone family");

        // Air above the surface.
        const int above = g.material_at(100, col.ground_y + 1, 100, col);
        CHECK_EQ(above, mat::AIR, "above surface is air");

        // World-floor enforcement: below floor = air; exactly at floor with a
        // bedrock id set = bedrock.
        const int below_floor = g.material_at(100, g.world_floor_voxel_y - 1, 100, col);
        CHECK_EQ(below_floor, mat::AIR, "below world floor is air");
        g.bedrock_material_id = mat::STONE_DARK;
        const int at_floor = g.material_at(100, g.world_floor_voxel_y, 100, col);
        CHECK_EQ(at_floor, mat::STONE_DARK, "world floor row is bedrock when enabled");
    }

    // Beach: a column at/below beach_y is sand-topped.
    {
        HeightmapGenerator g;
        g.set_seed(2024);
        g.height_range_voxels = 0.0;
        g.mid_amplitude_voxels = 0;
        g.detail_amplitude_voxels = 0;
        g.height_offset_voxels = 70; // below beach(74) but above-ish
        ColumnInfo col = g.resolve_column(50, 50);
        CHECK_EQ(col.top_id, mat::SAND, "below beach line is sand-topped");
    }

    // Below sea level: column flagged as water, ground below sea.
    {
        HeightmapGenerator g;
        g.set_seed(2024);
        g.height_range_voxels = 0.0;
        g.mid_amplitude_voxels = 0;
        g.detail_amplitude_voxels = 0;
        g.height_offset_voxels = 40; // below sea(120) and beach(74)
        ColumnInfo col = g.resolve_column(50, 50);
        CHECK(col.below_sea, "ground below sea level is flagged water");
        CHECK(col.ground_y < g.sea_level_voxels, "below-sea ground is under sea level");
        CHECK_EQ(col.top_id, mat::SAND, "underwater/beach floor is sand");
        // No flora underwater.
        CHECK_EQ(col.flora_id, 0, "no flora below sea level");
    }

    // ---- 5. SCATTER determinism: flora + hash3 per (x,z,seed) -------------
    {
        // hash3 itself: deterministic, in [0,1], seed-sensitive.
        for (int i = 0; i < 100; ++i) {
            const double a = hash3(i, 3, i * 7, 1234);
            const double b = hash3(i, 3, i * 7, 1234);
            CHECK(a == b, "hash3 deterministic");
            CHECK(a >= 0.0 && a <= 1.0, "hash3 in [0,1]");
        }
        CHECK(hash3(10, 0, 10, 1) != hash3(10, 0, 10, 2),
              "hash3 is seed-sensitive");

        // Flora scatter: deterministic per column, and SOME columns sprout
        // flora (the roll is live), all ids inside the flora/detail range.
        HeightmapGenerator g;
        g.set_seed(99);
        g.height_range_voxels = 0.0;
        g.mid_amplitude_voxels = 0;
        g.detail_amplitude_voxels = 0;
        g.height_offset_voxels = 300; // grass plateau above sea/beach
        int flora_cols = 0;
        for (int x = 0; x < 400; ++x) {
            ColumnInfo c1 = g.resolve_column(x, 17);
            ColumnInfo c2 = g.resolve_column(x, 17);
            CHECK_EQ(c1.flora_id, c2.flora_id, "flora scatter deterministic");
            if (c1.flora_id != 0) {
                ++flora_cols;
                CHECK(c1.flora_id >= mat::FLORA_GRASS_BLADE
                          && c1.flora_id <= mat::DETAIL_TWIG,
                      "flora id in 24..28 range");
            }
        }
        CHECK(flora_cols > 0, "some grass columns sprout flora");
    }

    // ---- 6. BIOME path: weights sum to 1, ≤3 sorted contributors ----------
    {
        HeightmapGenerator g;
        g.set_seed(55555);
        g.set_biome_profiles(make_biomes());
        g.idx_plains = 0;
        g.idx_hills = 1;
        g.idx_forest = 2;
        g.idx_desert = 3;
        g.idx_mountains = 4;
        CHECK(g.biome_active(), "biome path active once profiles loaded");

        for (int i = 0; i < 500; ++i) {
            const int x = (i * 211) - 30000;
            const int z = (i * -307) + 40000;
            int indices[3];
            double weights[3];
            int count = 0;
            g.resolve_biome_weights(x, z, indices, weights, count);
            CHECK(count >= 1 && count <= 3, "1..3 biome contributors");
            double sum = 0.0;
            for (int k = 0; k < count; ++k) {
                CHECK(weights[k] >= 0.0 && weights[k] <= 1.0001, "weight in [0,1]");
                CHECK(indices[k] >= 0 && indices[k] < g.profile_count(),
                      "biome index in range");
                sum += weights[k];
            }
            CHECK(sum > 0.999 && sum < 1.001, "biome weights sum to 1");
            // Sorted: descending weight (ties broken by ascending index).
            for (int k = 1; k < count; ++k) {
                CHECK(weights[k - 1] >= weights[k] - 1e-12,
                      "weights sorted descending");
            }

            // Determinism on the biome path.
            const int y1 = g.compute_ground_y(x, z);
            const int y2 = g.compute_ground_y(x, z);
            CHECK_EQ(y1, y2, "biome ground_y deterministic");
            const int p1 = g.pick_surface_biome(x, z);
            const int p2 = g.pick_surface_biome(x, z);
            CHECK_EQ(p1, p2, "surface biome pick deterministic");
            CHECK(p1 >= 0 && p1 < g.profile_count(), "picked biome in range");
        }

        // Biome ground sits in a sane band around sea level (sea-relative
        // height + sea offset). With amplitudes up to 40 m = 400 vox the
        // ground should stay within a few hundred voxels of sea level.
        int min_y = 1 << 30, max_y = -(1 << 30);
        for (int x = -5000; x <= 5000; x += 97) {
            const int y = g.compute_ground_y(x, 1234);
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }
        CHECK(max_y > min_y, "biome terrain varies across x");
        CHECK(min_y > g.sea_level_voxels - 600 && max_y < g.sea_level_voxels + 600,
              "biome ground stays in a sane band around sea level");

        // Dominant biome == highest-weight contributor (index 0 of the sorted
        // resolve), and is deterministic.
        for (int i = 0; i < 50; ++i) {
            const int x = i * 613;
            const int z = i * -419;
            int indices[3];
            double weights[3];
            int count = 0;
            g.resolve_biome_weights(x, z, indices, weights, count);
            CHECK_EQ(g.dominant_biome(x, z), indices[0],
                     "dominant biome is the top-weight contributor");
        }
    }
}

int main(int argc, char** argv) {
    bool run = (argc <= 1);
    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "gen") run = true;
    }
    if (!run) {
        std::printf("[gen     ] SKIP (not selected)\n");
        return 0;
    }

    sel_gen();

    std::printf("[gen     ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("----\n%d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
