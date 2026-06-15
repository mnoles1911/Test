// test_mining.cpp — standalone parity harness for the ported mining-carve Core:
// MiningCarve.h (preset sizing, depth-biased carve box, physical-volume mining
// time, the D2 deterministic wall-roughen pass, and the destroy preview).
//
// COMPILE + RUN (either works):
//   cd /home/user/Test/ue5/MiraThal/tests/standalone && ./build.sh mining
// or directly:
//   clang++ -std=c++17 -O2 -Wall -Wextra -Wshadow \
//     -I /home/user/Test/ue5/MiraThal/Source/MiraThalVoxel/Public \
//     test_mining.cpp -o test_mining.run && ./test_mining.run
//
// One self-contained program (its own main), mirroring test_main.cpp's print
// style: each selector prints PASS/FAIL and main returns 0 only if every check
// passed. The single selector here is `mining`.

#include <cstdio>
#include <cmath>
#include <string>
#include <vector>
#include <unordered_set>
#include <unordered_map>
#include <functional>

#include "Core/MiraVec.h"
#include "Core/VoxelScale.h"
#include "Core/MaterialIds.h"
#include "Core/MiningCarve.h"

// ---------------------------------------------------------------------------
// Minimal assertion plumbing (matches test_main.cpp's CHECK / CHECK_EQ).
// ---------------------------------------------------------------------------
static int g_checks = 0;
static int g_fails  = 0;
static std::string g_current;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!(cond)) {                                                          \
            ++g_fails;                                                          \
            std::printf("  FAIL [%s] %s  (%s:%d)\n",                            \
                        g_current.c_str(), (msg), __FILE__, __LINE__);          \
        }                                                                       \
    } while (0)

#define CHECK_EQ(a, b, msg)                                                     \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!((a) == (b))) {                                                    \
            ++g_fails;                                                          \
            std::printf("  FAIL [%s] %s  expected=%lld got=%lld  (%s:%d)\n",    \
                        g_current.c_str(), (msg),                               \
                        (long long)(b), (long long)(a), __FILE__, __LINE__);    \
        }                                                                       \
    } while (0)

#define CHECK_NEAR(a, b, eps, msg)                                             \
    do {                                                                        \
        ++g_checks;                                                             \
        if (std::fabs((double)(a) - (double)(b)) > (eps)) {                     \
            ++g_fails;                                                          \
            std::printf("  FAIL [%s] %s  expected=%.6f got=%.6f  (%s:%d)\n",    \
                        g_current.c_str(), (msg),                               \
                        (double)(b), (double)(a), __FILE__, __LINE__);          \
        }                                                                       \
    } while (0)

using mira::Vec3;
using mira::Vec3i;
using mira::VoxelWrite;
namespace mn = mira::mining;
namespace mat = mira::mat;

// A carved-voxel set as an unordered_set for order-independent comparison.
static std::unordered_set<Vec3i> writes_to_set(const std::vector<VoxelWrite>& w) {
    std::unordered_set<Vec3i> s;
    for (const auto& vw : w) s.insert(vw.pos);
    return s;
}

// ---------------------------------------------------------------------------
// Part 1 — presets carve the right COUNT and side length.
// ---------------------------------------------------------------------------
static void test_presets() {
    // Names match PRESET_NAMES exactly.
    CHECK(std::string(mn::preset_name(mn::CarvePreset::Small))  == "Small",  "Small name");
    CHECK(std::string(mn::preset_name(mn::CarvePreset::Medium)) == "Medium", "Medium name");
    CHECK(std::string(mn::preset_name(mn::CarvePreset::Full))   == "Full",   "Full name");

    // Side lengths: Small=1, Medium=3, Full=N (default 5).
    CHECK_EQ(mn::preset_side(mn::CarvePreset::Small),  1, "Small side = 1");
    CHECK_EQ(mn::preset_side(mn::CarvePreset::Medium), 3, "Medium side = 3");
    CHECK_EQ(mn::preset_side(mn::CarvePreset::Full),   5, "Full side = N (default 5)");
    // Full honours a custom tool max bite, clamped to >= 1.
    CHECK_EQ(mn::preset_side(mn::CarvePreset::Full, 8), 8, "Full honours custom N=8");
    CHECK_EQ(mn::preset_side(mn::CarvePreset::Full, 0), 1, "Full clamps to >= 1");

    // A flat-ground dig (normal points UP, +Y). Centre voxel at origin.
    const Vec3i centre(0, 0, 0);
    const Vec3 up(0.0f, 1.0f, 0.0f);

    // Small -> 1 voxel.
    {
        auto box = mn::compute_carve_box(centre, up, mn::preset_side(mn::CarvePreset::Small));
        CHECK_EQ(box.voxel_count(), 1, "Small box = 1 voxel");
        CHECK_EQ((long long)mn::compute_carve(box).size(), 1ll, "Small carve emits 1 write");
    }
    // Medium -> 27 voxels (3^3).
    {
        auto box = mn::compute_carve_box(centre, up, mn::preset_side(mn::CarvePreset::Medium));
        CHECK_EQ(box.voxel_count(), 27, "Medium box = 27 voxels");
        CHECK_EQ((long long)mn::compute_carve(box).size(), 27ll, "Medium carve emits 27 writes");
    }
    // Full -> 125 voxels (5^3).
    {
        auto box = mn::compute_carve_box(centre, up, mn::preset_side(mn::CarvePreset::Full));
        CHECK_EQ(box.voxel_count(), 125, "Full box = 125 voxels (5^3)");
        CHECK_EQ((long long)mn::compute_carve(box).size(), 125ll, "Full carve emits 125 writes");
    }

    // Every carve write is AIR (value 0).
    {
        auto w = mn::compute_carve(centre, up, mn::CarvePreset::Medium);
        bool all_air = true;
        for (const auto& vw : w) if (vw.value != mn::AIR_VOXEL) all_air = false;
        CHECK(all_air, "every carve write is air (0)");
    }
}

// ---------------------------------------------------------------------------
// Part 2 — depth-biased anchoring: the box carves INTO the surface.
// ---------------------------------------------------------------------------
static void test_depth_bias() {
    const Vec3i centre(0, 0, 0);
    const int n = 3;  // Medium — half_lo=1, half_hi=1

    // (a) Digging DOWNWARD: aim at the ground, normal points UP (+Y). The carve
    //     must remove voxels BELOW the hit — the aimed voxel sits at the box's
    //     TOP and the box extends down into the dirt.
    {
        const Vec3 up(0.0f, 1.0f, 0.0f);
        auto box = mn::compute_carve_box(centre, up, n);
        // Unbiased 3^3 would be y in [-1, +1]. Depth bias shifts -half_hi*sign(+1)
        // = -1 on Y, giving y in [-2, 0]: the aimed voxel (y=0) is the TOP slab,
        // everything else is below it.
        CHECK_EQ(box.vmin.y, -2, "down dig: box bottom 2 below hit");
        CHECK_EQ(box.vmax.y,  0, "down dig: aimed voxel is the box top");
        CHECK(box.vmax.y <= centre.y, "down dig: no voxel ABOVE the hit");
        // X/Z stay symmetric around the aim (no bias off the dominant axis).
        CHECK_EQ(box.vmin.x, -1, "down dig: X symmetric lo");
        CHECK_EQ(box.vmax.x,  1, "down dig: X symmetric hi");
    }

    // (b) Side dig into a +X-facing wall: normal points +X toward the player.
    //     The carve must remove voxels BEHIND the face (lower X), so the aimed
    //     surface voxel is the box's max-X (player-facing) slab.
    {
        const Vec3 px(1.0f, 0.0f, 0.0f);
        auto box = mn::compute_carve_box(centre, px, n);
        // Bias = -half_hi*sign(+1) = -1 on X -> x in [-2, 0].
        CHECK_EQ(box.vmax.x, 0, "side dig: aimed voxel is the player-facing slab");
        CHECK_EQ(box.vmin.x, -2, "side dig: box extends 2 voxels behind the face");
        CHECK(box.vmax.x <= centre.x, "side dig: no voxel IN FRONT of the face");
    }

    // (c) Side dig into a -Z-facing wall: normal points -Z. Bias = -(-1) = +1 on
    //     Z -> the box extends to HIGHER Z (into the wall behind a -Z face).
    {
        const Vec3 nz(0.0f, 0.0f, -1.0f);
        auto box = mn::compute_carve_box(centre, nz, n);
        CHECK_EQ(box.vmin.z, 0,  "neg-Z dig: aimed voxel is the player-facing slab");
        CHECK_EQ(box.vmax.z, 2,  "neg-Z dig: box extends 2 voxels into the wall");
    }

    // (d) CENTERED anchor leaves the box symmetric — no bias at all.
    {
        const Vec3 up(0.0f, 1.0f, 0.0f);
        auto box = mn::compute_carve_box(centre, up, n, mn::MiningAnchor::Centered);
        CHECK_EQ(box.vmin.y, -1, "centered: symmetric lo");
        CHECK_EQ(box.vmax.y,  1, "centered: symmetric hi");
    }

    // (e) Even-N (N=2): aimed voxel stays the MIN corner, never extends behind
    //     the aim. Unbiased: half_lo=0, half_hi=1 -> [c, c+1]. Down normal (+Y):
    //     bias -1 on Y -> y in [-1, 0]; aimed voxel (0) is still the top.
    {
        const Vec3 up(0.0f, 1.0f, 0.0f);
        auto box = mn::compute_carve_box(centre, up, 2);
        CHECK_EQ(box.voxel_count(), 8, "even N=2 -> 8 voxels (2^3)");
        CHECK_EQ(box.vmax.y, 0, "even N: aimed voxel is the top of a down dig");
        CHECK_EQ(box.vmin.y, -1, "even N: one voxel below the hit");
    }
}

// ---------------------------------------------------------------------------
// Part 3 — physical-volume mining-time anchor.
// ---------------------------------------------------------------------------
static void test_mining_time() {
    // BASELINE_VOLUME_M3 = 8/216 m^3.
    CHECK_NEAR(mn::BASELINE_VOLUME_M3, 8.0 / 216.0, 1e-12, "BASELINE_VOLUME_M3 = 8/216");
    CHECK_NEAR(mn::BASELINE_VOLUME_M3, 0.037037037, 1e-6, "BASELINE_VOLUME_M3 ~ 0.037 m^3");

    // baseline_voxels at 10 vox/m = (8/216) * 1000 ~ 37.037.
    CHECK_NEAR(mn::baseline_voxels(), 1000.0 * 8.0 / 216.0, 1e-9, "baseline_voxels ~ 37 at 10vox/m");
    CHECK_NEAR(mn::baseline_voxels(), 37.037037, 1e-4, "baseline_voxels ~ 37.04");

    // volume_multiplier per preset (values from MINING_TIME_SCALING.md table).
    CHECK_NEAR(mn::volume_multiplier(1),   1.0 / 37.037037,   1e-4, "Small mult ~ 0.027x");
    CHECK_NEAR(mn::volume_multiplier(27),  27.0 / 37.037037,  1e-4, "Medium mult ~ 0.73x");
    CHECK_NEAR(mn::volume_multiplier(125), 125.0 / 37.037037, 1e-4, "Full mult ~ 3.375x");

    // The Full 5^3 multiplier is DELIBERATELY 3.375 — identical to the old 3^3
    // at 6 vox/m (27/8). This is the load-bearing scale-flip invariant.
    CHECK_NEAR(mn::volume_multiplier(125), 3.375, 1e-3, "Full multiplier == old 3^3 feel (3.375)");

    // Final swing time = per_voxel * multiplier. Stone is 0.8 s/voxel.
    // Full stone swing = 0.8 * 3.375 = 2.70 s (matches the doc table exactly).
    CHECK_NEAR(mn::mining_time_secs(0.8, 125), 2.70, 1e-2, "Full stone swing = 2.70 s");
    // Medium dirt (0.3 s/voxel) = 0.3 * 0.729 ~ 0.219 s.
    CHECK_NEAR(mn::mining_time_secs(0.3, 27),  0.219, 1e-3, "Medium dirt swing ~ 0.219 s");
    // Small sand (0.2 s/voxel) = 0.2 * 0.027 ~ 0.0054 s.
    CHECK_NEAR(mn::mining_time_secs(0.2, 1),   0.0054, 1e-3, "Small sand swing ~ 0.005 s");

    // Wrong-tool penalty constant.
    CHECK_NEAR(mn::WRONG_TOOL_SPEED_MULTIPLIER, 3.0, 1e-12, "wrong-tool penalty = 3.0x");
    // Shovel on stone: per-voxel 0.8 * 3 = 2.4; Full swing = 2.4 * 3.375 = 8.1 s.
    CHECK_NEAR(mn::mining_time_secs(0.8 * mn::WRONG_TOOL_SPEED_MULTIPLIER, 125), 8.1, 1e-2,
               "Full shovel-on-stone swing = 8.1 s");
}

// ---------------------------------------------------------------------------
// Part 4 — D2 roughen pass: deterministic, soft-only, ~22% of the shell.
// ---------------------------------------------------------------------------
static void test_roughen() {
    // Salt + chance constants.
    CHECK_EQ((long long)mn::CARVE_ROUGHEN_SALT, (long long)0x6B0BB1E, "roughen salt = 0x6B0BB1E");
    CHECK_NEAR(mn::CARVE_ROUGHEN_CHANCE, 0.22, 1e-6, "roughen chance = 0.22");

    // The hash is a pure [0,1) function of coords — same coord, same value.
    for (int i = 0; i < 50; ++i) {
        Vec3i v(i * 7 - 13, i - 20, i * 3 + 1);
        float a = mn::roughen_hash(v);
        float b = mn::roughen_hash(v);
        CHECK(a == b, "roughen_hash is pure (same coord -> same value)");
        CHECK(a >= 0.0f && a < 1.0f, "roughen_hash in [0,1)");
    }

    // Build a world where the whole shell around a Medium carve is DIRT (soft).
    // Carve box at origin, Medium (3^3), flat-ground dig (normal +Y).
    const Vec3i centre(0, 0, 0);
    const Vec3 up(0.0f, 1.0f, 0.0f);
    auto box = mn::compute_carve_box(centre, up, mn::preset_side(mn::CarvePreset::Medium));

    // get_type_at returning DIRT everywhere (the shell is all soft earth).
    auto all_dirt = [](const Vec3i&) -> int { return mat::DIRT; };

    auto r1 = mn::compute_roughen_set(box, all_dirt);
    auto r2 = mn::compute_roughen_set(box, all_dirt);

    // DETERMINISM: two runs identical (same set AND same order).
    CHECK_EQ((long long)r1.size(), (long long)r2.size(), "roughen deterministic size");
    bool identical = (r1.size() == r2.size());
    for (size_t i = 0; identical && i < r1.size(); ++i) {
        if (!(r1[i].pos == r2[i].pos) || r1[i].value != r2[i].value) identical = false;
    }
    CHECK(identical, "roughen two runs byte-identical");

    // Every roughen write is air, and lands OUTSIDE the carve box (the shell).
    auto in_box = [&](const Vec3i& p) {
        return p.x >= box.vmin.x && p.x <= box.vmax.x
            && p.y >= box.vmin.y && p.y <= box.vmax.y
            && p.z >= box.vmin.z && p.z <= box.vmax.z;
    };
    bool all_outside_air = true;
    for (const auto& w : r1) {
        if (w.value != mn::AIR_VOXEL) all_outside_air = false;
        if (in_box(w.pos)) all_outside_air = false;  // must be shell, not interior
    }
    CHECK(all_outside_air, "roughen writes are air voxels in the shell only");

    // FRACTION: the de-duplicated shell of a 3^3 box is the 6 faces of a 5^3
    // outer cube minus the 3^3 interior... actually the shell is exactly the
    // one-voxel layer outside the 6 faces: count it directly and confirm we
    // removed ~22% of it.
    std::unordered_set<Vec3i> shell;
    for (int y = box.vmin.y; y <= box.vmax.y; ++y)
        for (int z = box.vmin.z; z <= box.vmax.z; ++z) {
            shell.insert(Vec3i(box.vmin.x - 1, y, z));
            shell.insert(Vec3i(box.vmax.x + 1, y, z));
        }
    for (int x = box.vmin.x; x <= box.vmax.x; ++x)
        for (int z = box.vmin.z; z <= box.vmax.z; ++z) {
            shell.insert(Vec3i(x, box.vmin.y - 1, z));
            shell.insert(Vec3i(x, box.vmax.y + 1, z));
        }
    for (int x = box.vmin.x; x <= box.vmax.x; ++x)
        for (int y = box.vmin.y; y <= box.vmax.y; ++y) {
            shell.insert(Vec3i(x, y, box.vmin.z - 1));
            shell.insert(Vec3i(x, y, box.vmax.z + 1));
        }
    const double frac = (double)r1.size() / (double)shell.size();
    // 6 faces of 3x3 = 54 unique shell voxels; ~22% ~ 12. Allow a generous band
    // (the hash is one fixed draw, not a statistical average over many seeds).
    CHECK(shell.size() == 54, "Medium shell = 54 unique voxels");
    CHECK(frac > 0.10 && frac < 0.35, "roughen removes ~22% of the shell");

    // SOFT-ONLY: if the shell is STONE, nothing is roughened (precision mining
    // stays precise). Same for water and pass-through flora/detail.
    auto all_stone = [](const Vec3i&) -> int { return mat::STONE; };
    CHECK_EQ((long long)mn::compute_roughen_set(box, all_stone).size(), 0ll,
             "stone shell is never roughened");
    auto all_water = [](const Vec3i&) -> int { return mat::WATER_FLUID_BASE_ID; };
    CHECK_EQ((long long)mn::compute_roughen_set(box, all_water).size(), 0ll,
             "water shell is never roughened");
    auto all_flora = [](const Vec3i&) -> int { return mat::GRASS_BLADE_ID; };
    CHECK_EQ((long long)mn::compute_roughen_set(box, all_flora).size(), 0ll,
             "flora/detail shell is never roughened");
    auto all_air = [](const Vec3i&) -> int { return mn::AIR_VOXEL; };
    CHECK_EQ((long long)mn::compute_roughen_set(box, all_air).size(), 0ll,
             "air shell has nothing to chew");

    // is_soft_diggable predicate spot-checks.
    CHECK(mn::is_soft_diggable(mat::DIRT),  "dirt is soft");
    CHECK(mn::is_soft_diggable(mat::GRASS), "grass is soft");
    CHECK(mn::is_soft_diggable(mat::SAND),  "sand is soft");
    CHECK(!mn::is_soft_diggable(mat::STONE), "stone is not soft");
    CHECK(!mn::is_soft_diggable(mat::MARBLE), "marble is not soft");
}

// ---------------------------------------------------------------------------
// Part 5 — destroy preview = the SOLID voxels the carve would remove.
// ---------------------------------------------------------------------------
static void test_destroy_preview() {
    const Vec3i centre(0, 0, 0);
    const Vec3 up(0.0f, 1.0f, 0.0f);
    auto box = mn::compute_carve_box(centre, up, mn::preset_side(mn::CarvePreset::Medium));

    // (a) Solid terrain everywhere: preview == the full carve box (27 voxels).
    {
        auto solid = [](const Vec3i&) -> int { return mat::STONE; };
        auto preview = mn::compute_destroy_preview(box, solid);
        CHECK_EQ((long long)preview.size(), 27ll, "all-solid preview = 27 voxels");

        // And the preview set must equal the carve write set (minus the value).
        auto carve_set = writes_to_set(mn::compute_carve(box));
        std::unordered_set<Vec3i> preview_set(preview.begin(), preview.end());
        CHECK(carve_set == preview_set, "preview matches what the carve removes");
    }

    // (b) A RIDGE: only voxels with y <= -1 are solid (the lower half of the
    //     down-biased box y in [-2,0]). Preview should light up exactly those.
    {
        auto ridge = [](const Vec3i& p) -> int {
            return p.y <= -1 ? mat::DIRT : mn::AIR_VOXEL;
        };
        auto preview = mn::compute_destroy_preview(box, ridge);
        // box y in [-2, 0]; solid rows y=-2 and y=-1 -> 2 of 3 Y-layers, each
        // 3x3 = 9 -> 18 solid voxels.
        CHECK_EQ((long long)preview.size(), 18ll, "ridge preview = only the solid 18");
        bool all_solid = true;
        for (const auto& p : preview) if (p.y > -1) all_solid = false;
        CHECK(all_solid, "ridge preview contains no air voxels");
    }

    // (c) WATER is excluded (tools don't mine water) even though it's non-air.
    {
        auto water = [](const Vec3i&) -> int { return mat::WATER_FLUID_BASE_ID; };
        CHECK_EQ((long long)mn::compute_destroy_preview(box, water).size(), 0ll,
                 "water preview is empty (not mineable)");
        auto legacy = [](const Vec3i&) -> int { return mat::LEGACY_WATER_ID; };
        CHECK_EQ((long long)mn::compute_destroy_preview(box, legacy).size(), 0ll,
                 "legacy-water preview is empty");
    }

    // (d) All air: nothing glows.
    {
        auto air = [](const Vec3i&) -> int { return mn::AIR_VOXEL; };
        CHECK_EQ((long long)mn::compute_destroy_preview(box, air).size(), 0ll,
                 "all-air preview is empty");
    }
}

// ---------------------------------------------------------------------------
// Selector dispatch (single `mining` selector, matching the harness style).
// ---------------------------------------------------------------------------
static void sel_mining() {
    test_presets();
    test_depth_bias();
    test_mining_time();
    test_roughen();
    test_destroy_preview();
}

int main() {
    g_current = "mining";
    const int before = g_fails;
    sel_mining();
    std::printf("[%-8s] %s\n", "mining", (g_fails == before) ? "PASS" : "FAIL");
    std::printf("----\n1 selector(s), %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
