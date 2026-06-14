// test_main.cpp — standalone headless parity harness for the engine-agnostic
// Core, mirroring the Godot tools/headless/ runner selectors.
//
// WHY THIS EXISTS:
// Unreal cannot build or run in the dev container (no engine, no .NET, paltry
// disk/RAM, Epic download blocked). But the Core layer is pure C++17 with no
// Unreal headers, so it compiles and runs HERE under clang. This harness IS the
// iterative verification loop for the port's load-bearing math: each ported
// system lands with its selector green before it's "done", exactly like the
// 25-selector headless gate guarding the Godot build.
//
// Usage:
//   ./run_tests              # run every selector
//   ./run_tests scale codec  # run only the named selectors
// Exit 0 = all selected selectors passed; non-zero = a failure (with detail).
//
// Build with tests/standalone/build.sh (clang++ -std=c++17).

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <functional>

#include "Core/VoxelScale.h"
#include "Core/WaterByteCodec.h"

// ----------------------------------------------------------------------------
// Minimal assertion plumbing (no gtest dependency — keep the loop zero-setup).
// ----------------------------------------------------------------------------
static int  g_checks = 0;
static int  g_fails  = 0;
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

// ----------------------------------------------------------------------------
// Selector: scale  (ports the Godot `scale` gate)
// ----------------------------------------------------------------------------
static void sel_scale() {
    using namespace mira::scale;
    CHECK_EQ((long long)(VoxelsPerMeter), 10ll, "10 voxels per metre");
    CHECK(VoxelSizeM > 0.0999 && VoxelSizeM < 0.1001, "voxel size is 0.1 m");
    // round-to-nearest, not floor: 0.9 m -> 9 voxels
    CHECK_EQ(MetersToVoxels(0.9), 9, "0.9m -> 9 voxels (round nearest)");
    CHECK_EQ(MetersToVoxels(1.0), 10, "1.0m -> 10 voxels");
    CHECK_EQ(MetersToVoxels(2.55), 26, "2.55m -> 26 voxels (rounds up at .5)");
    CHECK(VoxelsToMeters(10) > 0.999 && VoxelsToMeters(10) < 1.001, "10 voxels -> 1 m");
    CHECK(VoxelsToMeters(5) > 0.499 && VoxelsToMeters(5) < 0.501, "5 voxels -> 0.5 m");
}

// ----------------------------------------------------------------------------
// Selector: codec  (ports the Godot `codec` gate — water byte layout)
// ----------------------------------------------------------------------------
static void sel_codec() {
    using C = mira::WaterByteCodec;

    // Pre-baked constants
    CHECK_EQ(C::AIR_BYTE, 0, "air byte is 0");
    CHECK_EQ(C::SOURCE_BYTE, 0x18, "source byte = level 8 | source bit = 0x18");

    // pack / unpack round-trips across the whole field space
    for (int level = 0; level <= C::MAX_LEVEL; ++level) {
        for (int src = 0; src <= 1; ++src) {
            for (int dir = 0; dir <= 7; ++dir) {
                const int b = C::pack(level, src != 0, dir);
                CHECK_EQ(C::level_of(b), level, "level round-trip");
                CHECK_EQ((int)C::is_source(b), src, "source round-trip");
                // dir 7 (RSVD) packs as 7 but spatially decodes to STILL offset
                CHECK_EQ(C::dir_of(b), dir, "dir round-trip");
                // fields must not bleed into each other
                CHECK_EQ(b & ~(C::LEVEL_MASK | C::SOURCE_BIT | C::DIR_MASK), 0,
                         "no stray bits outside the 3 fields");
            }
        }
    }

    // clamping: out-of-range level/dir cannot smuggle bits
    CHECK_EQ(C::level_of(C::pack(99, false, 0)), C::MAX_LEVEL, "level clamps to MAX");
    CHECK_EQ(C::dir_of(C::pack(0, false, 99)), 7, "dir clamps to 7");

    // is_water
    CHECK(!C::is_water(C::AIR_BYTE), "air is not water");
    CHECK(C::is_water(C::pack(1, false, 0)), "level 1 is water");
    CHECK(C::is_water(C::SOURCE_BYTE), "source is water");

    // mutators preserve other fields
    int b = C::pack(3, true, C::DIR_POS_X);
    int b2 = C::set_level(b, 7);
    CHECK_EQ(C::level_of(b2), 7, "set_level changes level");
    CHECK_EQ((int)C::is_source(b2), 1, "set_level preserves source");
    CHECK_EQ(C::dir_of(b2), C::DIR_POS_X, "set_level preserves dir");
    int b3 = C::set_dir(b, C::DIR_DOWN);
    CHECK_EQ(C::dir_of(b3), C::DIR_DOWN, "set_dir changes dir");
    CHECK_EQ(C::level_of(b3), 3, "set_dir preserves level");
    int b4 = C::set_source(b, false);
    CHECK_EQ((int)C::is_source(b4), 0, "set_source clears source");
    CHECK_EQ(C::level_of(b4), 3, "set_source preserves level");

    // height-aware column test
    int half = C::pack(4, false, 0); // 4/8 = fills bottom half
    CHECK(C::is_inside_water_column(half, 0.25f), "0.25 inside a level-4 cell");
    CHECK(!C::is_inside_water_column(half, 0.75f), "0.75 above a level-4 cell");
    CHECK(C::is_inside_water_column(C::SOURCE_BYTE, 1.0f), "source fills whole voxel");

    // direction <-> offset is a clean bijection over the 6 cardinals
    const int dirs[6] = {C::DIR_POS_X, C::DIR_NEG_X, C::DIR_POS_Z,
                         C::DIR_NEG_Z, C::DIR_DOWN, C::DIR_UP};
    for (int d : dirs) {
        mira::Vec3i off = C::dir_to_offset(d);
        CHECK_EQ(C::offset_to_dir(off), d, "dir->offset->dir round-trip");
    }
    CHECK(C::dir_to_offset(C::DIR_STILL) == mira::Vec3i(0, 0, 0), "STILL has zero offset");
    CHECK_EQ(C::offset_to_dir(mira::Vec3i(0, 0, 0)), C::DIR_STILL, "zero offset is STILL");
}

// ----------------------------------------------------------------------------
// Selector registry + dispatch
// ----------------------------------------------------------------------------
struct Selector {
    const char* name;
    std::function<void()> fn;
};

int main(int argc, char** argv) {
    const std::vector<Selector> all = {
        {"scale", sel_scale},
        {"codec", sel_codec},
        // Heavier selectors (finite/gravity/gen) are appended as those Core
        // systems land — each subagent's port registers its selector here.
    };

    std::vector<std::string> requested;
    for (int i = 1; i < argc; ++i) requested.emplace_back(argv[i]);

    int ran = 0;
    for (const auto& s : all) {
        bool run = requested.empty();
        for (const auto& r : requested) if (r == s.name) run = true;
        if (!run) continue;
        g_current = s.name;
        const int before = g_fails;
        s.fn();
        std::printf("[%-8s] %s\n", s.name, (g_fails == before) ? "PASS" : "FAIL");
        ++ran;
    }

    std::printf("----\n%d selector(s), %d checks, %d failure(s)\n",
                ran, g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
