// test_region.cpp — parity harness for Core/RegionFormat.h.
//   cd tests/standalone && ./build.sh region
//
// Covers:
//   - all-air brick round-trip (RLE should be tiny)
//   - all-solid brick round-trip (solid_count==512, nonzero_count==512)
//   - mixed brick (type + water at known indices, count recomputed correctly)
//   - CRC corruption detection for brick codec
//   - truncated buffer for brick codec
//   - delta log round-trip (including negative coords and varied type/water)
//   - empty delta log round-trip
//   - corrupted delta log detection
//   - truncated delta log detection

#include <cstdio>
#include <cstring>
#include "Core/RegionFormat.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { \
    ++g_checks; \
    if (!(cond)) { \
        ++g_fails; \
        std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__); \
    } \
} while (0)

using namespace mira;
using namespace mira::region;

// ---- Helpers -----------------------------------------------------------------

// Build a Brick with a handful of specific type/water assignments.
// Returns the expected solid_count and nonzero_count for verification.
static Brick make_mixed_brick(int& expected_solid, int& expected_nonzero) {
    Brick b;
    // All arrays start zeroed (air + no water).
    expected_solid   = 0;
    expected_nonzero = 0;

    // Write a few solid type cells.
    auto set_type = [&](int i, uint8_t t) {
        b.type[i] = t;
        if (t != mat::AIR) ++expected_solid;
    };
    auto set_water = [&](int i, uint8_t w) {
        b.water[i] = w;
    };

    // Place stone at indices 0, 10, 100, 300, 511.
    set_type(0,   mat::STONE);
    set_type(10,  mat::STONE);
    set_type(100, mat::STONE);
    set_type(300, mat::STONE);
    set_type(511, mat::STONE);

    // Water only (no type) at indices 50 and 200.
    set_water(50,  0x42);
    set_water(200, 0x08);

    // Both type AND water at index 5.
    set_type(5, mat::DIRT);
    set_water(5, 0x01);

    // Recompute expected nonzero_count ourselves.
    for (int i = 0; i < coords::VOXELS_PER_BRICK; ++i) {
        if (b.type[i] != 0 || b.water[i] != 0) ++expected_nonzero;
    }

    return b;
}

// ---- Tests -------------------------------------------------------------------

static void test_all_air_brick() {
    // An all-air brick should encode as: version(1) + run(varuint 512, 2 bytes)
    // + value(u8 1) + run(varuint 512, 2 bytes) + value(u8 1) + CRC(4) = ~11 bytes.
    // That is FAR smaller than 1024 raw bytes — the whole point of RLE.

    Brick air_brick; // default-constructed: all type=0, all water=0, counts=0

    auto encoded = encode_brick(air_brick);

    // Sanity: must be well under 32 bytes.
    CHECK(encoded.size() < 32, "all-air brick encodes to < 32 bytes (RLE wins)");

    // Round-trip: decode and verify.
    Brick decoded;
    bool ok = decode_brick(encoded, decoded);
    CHECK(ok, "all-air brick decodes successfully");

    // All type cells must be 0.
    bool types_ok = true;
    for (int i = 0; i < coords::VOXELS_PER_BRICK; ++i) {
        if (decoded.type[i] != 0) { types_ok = false; break; }
    }
    CHECK(types_ok, "all-air: decoded type array is all-zero");

    // All water cells must be 0.
    bool water_ok = true;
    for (int i = 0; i < coords::VOXELS_PER_BRICK; ++i) {
        if (decoded.water[i] != 0) { water_ok = false; break; }
    }
    CHECK(water_ok, "all-air: decoded water array is all-zero");

    // Counters must be 0.
    CHECK(decoded.solid_count   == 0, "all-air: solid_count == 0");
    CHECK(decoded.nonzero_count == 0, "all-air: nonzero_count == 0");
}

static void test_all_solid_brick() {
    // Fill every voxel with stone (id 1).
    Brick solid;
    for (int i = 0; i < coords::VOXELS_PER_BRICK; ++i) {
        solid.type[i] = static_cast<uint8_t>(mat::STONE);
    }
    // water stays all-zero

    auto encoded = encode_brick(solid);

    // Should also encode small: one big type run + one big water run.
    CHECK(encoded.size() < 32, "all-solid brick encodes to < 32 bytes (RLE wins)");

    Brick decoded;
    bool ok = decode_brick(encoded, decoded);
    CHECK(ok, "all-solid brick decodes successfully");

    // Verify all type cells == STONE.
    bool types_ok = true;
    for (int i = 0; i < coords::VOXELS_PER_BRICK; ++i) {
        if (decoded.type[i] != static_cast<uint8_t>(mat::STONE)) { types_ok = false; break; }
    }
    CHECK(types_ok, "all-solid: decoded type array is all-stone");

    // Verify counters recomputed correctly.
    CHECK(decoded.solid_count   == 512, "all-solid: solid_count == 512");
    CHECK(decoded.nonzero_count == 512, "all-solid: nonzero_count == 512");
}

static void test_mixed_brick() {
    int expected_solid = 0, expected_nonzero = 0;
    Brick original = make_mixed_brick(expected_solid, expected_nonzero);

    auto encoded = encode_brick(original);

    Brick decoded;
    bool ok = decode_brick(encoded, decoded);
    CHECK(ok, "mixed brick decodes successfully");

    // Compare the full 512-cell type array.
    bool types_match = (decoded.type == original.type);
    CHECK(types_match, "mixed brick: decoded type array matches original");

    // Compare the full 512-cell water array.
    bool water_match = (decoded.water == original.water);
    CHECK(water_match, "mixed brick: decoded water array matches original");

    // Counters must match what we computed above.
    CHECK(decoded.solid_count   == expected_solid,
          "mixed brick: solid_count recomputed correctly");
    CHECK(decoded.nonzero_count == expected_nonzero,
          "mixed brick: nonzero_count recomputed correctly");
}

static void test_brick_crc_corruption() {
    // Encode an all-air brick (or any brick), then flip one byte in the middle.
    // decode_brick must return false.

    Brick b; // all-air
    auto encoded = encode_brick(b);

    // Flip the very first payload byte (index 1, after the version byte).
    // This is squarely in the RLE data, not the CRC footer, so the CRC mismatch
    // proves the footer caught the corruption rather than us just reading the wrong version.
    std::vector<uint8_t> corrupt = encoded;
    corrupt[1] ^= 0xFF;

    Brick out;
    bool ok = decode_brick(corrupt, out);
    CHECK(!ok, "CRC corruption in brick data is detected (decode returns false)");
}

static void test_brick_truncation() {
    // A too-short buffer must not crash and must return false.
    // Try several lengths from 0 up to a few bytes.

    Brick b;
    auto encoded = encode_brick(b);

    // Buffer of length 0.
    {
        std::vector<uint8_t> empty;
        Brick out;
        bool ok = decode_brick(empty, out);
        CHECK(!ok, "zero-byte buffer -> decode_brick returns false");
    }

    // Buffer of length 4 (too short even for version + CRC).
    {
        std::vector<uint8_t> tiny(encoded.begin(), encoded.begin() + 4);
        Brick out;
        bool ok = decode_brick(tiny, out);
        CHECK(!ok, "4-byte truncated buffer -> decode_brick returns false");
    }

    // Buffer truncated halfway through the data.
    if (encoded.size() > 8) {
        std::vector<uint8_t> half(encoded.begin(), encoded.begin() + encoded.size() / 2);
        Brick out;
        bool ok = decode_brick(half, out);
        CHECK(!ok, "half-truncated brick buffer -> decode_brick returns false");
    }
}

static void test_delta_log_round_trip() {
    // Build a list with negative coords, big coords, varied type/water.
    std::vector<VoxelEdit> edits;

    edits.push_back({ Vec3i{   0,    0,    0}, mat::STONE, 0     });
    edits.push_back({ Vec3i{  -1,   -1,   -1}, mat::DIRT,  0     });
    edits.push_back({ Vec3i{-100, -200, -300}, mat::AIR,   0     });
    edits.push_back({ Vec3i{ 512,  256,  128}, mat::SAND,  0x42  });
    edits.push_back({ Vec3i{  10,   20,   30}, mat::AIR,   0x08  }); // water-only change
    edits.push_back({ Vec3i{-9999, 0, 9999},   mat::STONE, 0xFF  });

    auto encoded = encode_delta_log(edits);

    std::vector<VoxelEdit> decoded;
    bool ok = decode_delta_log(encoded, decoded);
    CHECK(ok, "delta log decodes successfully");
    CHECK(decoded.size() == edits.size(), "delta log: edit count matches");

    bool all_match = true;
    if (decoded.size() == edits.size()) {
        for (size_t i = 0; i < edits.size(); ++i) {
            const VoxelEdit& a = edits[i];
            const VoxelEdit& b = decoded[i];
            if (a.voxel != b.voxel || a.type != b.type || a.water != b.water) {
                all_match = false;
                break;
            }
        }
    }
    CHECK(all_match, "delta log: all edits round-trip with correct coords + type + water");
}

static void test_delta_log_empty() {
    // An empty list must round-trip cleanly.
    std::vector<VoxelEdit> empty_in;
    auto encoded = encode_delta_log(empty_in);

    // Result should be small: version(1) + count_varuint(1) + CRC(4) = 6 bytes.
    CHECK(encoded.size() <= 8, "empty delta log encodes to <= 8 bytes");

    std::vector<VoxelEdit> empty_out;
    bool ok = decode_delta_log(encoded, empty_out);
    CHECK(ok,                    "empty delta log decodes successfully");
    CHECK(empty_out.empty(),     "empty delta log: decoded list is empty");
}

static void test_delta_log_corruption() {
    // Build a non-empty log then corrupt one byte — CRC should catch it.
    std::vector<VoxelEdit> edits;
    edits.push_back({ Vec3i{1, 2, 3}, mat::STONE, 0 });
    edits.push_back({ Vec3i{-5, 10, -15}, mat::DIRT, 0x04 });

    auto encoded = encode_delta_log(edits);

    // Flip a byte in the middle of the payload (skip version at [0]).
    std::vector<uint8_t> corrupt = encoded;
    corrupt[encoded.size() / 2] ^= 0xAA;

    std::vector<VoxelEdit> out;
    bool ok = decode_delta_log(corrupt, out);
    CHECK(!ok, "corrupted delta log -> decode returns false");
    CHECK(out.empty(), "corrupted delta log -> output is cleared (no partial result)");
}

static void test_delta_log_truncation() {
    // Truncate a delta log mid-stream — must fail safe.
    std::vector<VoxelEdit> edits;
    edits.push_back({ Vec3i{0, 0, 0}, mat::STONE, 0 });
    edits.push_back({ Vec3i{1, 2, 3}, mat::DIRT,  0 });

    auto encoded = encode_delta_log(edits);

    // Too short to even hold version + count.
    {
        std::vector<uint8_t> tiny(1, encoded[0]); // only the version byte
        std::vector<VoxelEdit> out;
        bool ok = decode_delta_log(tiny, out);
        CHECK(!ok, "1-byte truncated delta log -> decode returns false");
    }

    // Cut off midway through the edit list.
    if (encoded.size() > 6) {
        std::vector<uint8_t> half(encoded.begin(), encoded.begin() + encoded.size() / 2);
        std::vector<VoxelEdit> out;
        bool ok = decode_delta_log(half, out);
        CHECK(!ok, "half-truncated delta log -> decode returns false");
    }
}

// ---- Entry point -------------------------------------------------------------

int main() {
    test_all_air_brick();
    test_all_solid_brick();
    test_mixed_brick();
    test_brick_crc_corruption();
    test_brick_truncation();
    test_delta_log_round_trip();
    test_delta_log_empty();
    test_delta_log_corruption();
    test_delta_log_truncation();

    std::printf("[region  ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
