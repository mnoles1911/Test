// test_netvoxel.cpp — parity harness for Core/NetVoxelCodec.h.
//   cd tests/standalone && ./build.sh netvoxel
//
// This tests the MULTIPLAYER wire codec: the byte layouts for EditCommand
// batches and BrickDelta packets. Every test covers one of: correct
// round-trip, size efficiency, edge case (empty/negative coords), or
// failure-safe rejection (CRC, truncation, out-of-range fields).

#include <cstdio>
#include <cstring>
#include <vector>
#include "Core/NetVoxelCodec.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;
using namespace mira::net;

int main() {

    // ================================================================
    //  EDIT COMMANDS
    // ================================================================

    // ---- round-trip: varied ops, negative coords, type + water ----
    // Encodes a batch with all three op types and a mix of positive and
    // negative voxel coordinates, then decodes and checks every field.
    {
        std::vector<EditCommand> cmds;

        // Place: positive coords
        cmds.push_back({ Vec3i{10,  20,  30},  EditOp::Place,    7,  0 });
        // Remove: negative coords (important: zig-zag varint must handle these)
        cmds.push_back({ Vec3i{-5, -100, -1},  EditOp::Remove,   0,  0 });
        // SetWater: mixed sign, non-zero water byte
        cmds.push_back({ Vec3i{0,    1,  -1},  EditOp::SetWater, 0, 42 });
        // Place with a large negative coord to exercise multi-byte varint
        cmds.push_back({ Vec3i{-5000, 1234, 0}, EditOp::Place,  13,  0 });

        auto buf = encode_edits(cmds);

        std::vector<EditCommand> out;
        CHECK(decode_edits(buf, out), "round-trip batch: decode returns true");
        CHECK(out.size() == 4, "round-trip batch: 4 commands decoded");

        if (out.size() == 4) {
            // cmd 0: Place
            // Wrap Vec3i{...} in extra parens so the commas inside braces
            // don't confuse the two-argument CHECK macro.
            CHECK((out[0].voxel == Vec3i{10, 20, 30}),   "cmd0 voxel");
            CHECK(out[0].op    == EditOp::Place,          "cmd0 op=Place");
            CHECK(out[0].type  == 7,                      "cmd0 type=7");
            CHECK(out[0].water == 0,                      "cmd0 water=0");

            // cmd 1: Remove with negative coords
            CHECK((out[1].voxel == Vec3i{-5, -100, -1}), "cmd1 voxel negative");
            CHECK(out[1].op    == EditOp::Remove,         "cmd1 op=Remove");
            CHECK(out[1].type  == 0,                      "cmd1 type=0");
            CHECK(out[1].water == 0,                      "cmd1 water=0");

            // cmd 2: SetWater
            CHECK((out[2].voxel == Vec3i{0, 1, -1}),     "cmd2 voxel");
            CHECK(out[2].op    == EditOp::SetWater,       "cmd2 op=SetWater");
            CHECK(out[2].water == 42,                     "cmd2 water=42");

            // cmd 3: large negative coord
            CHECK((out[3].voxel == Vec3i{-5000, 1234, 0}), "cmd3 voxel large neg");
            CHECK(out[3].op    == EditOp::Place,            "cmd3 op=Place");
            CHECK(out[3].type  == 13,                       "cmd3 type=13");
        }
    }

    // ---- compact size: a single small edit should be very small ----
    // Version(1) + varuint_count(1) + varint_x(1) + varint_y(1) + varint_z(1)
    // + u8_op(1) + u8_type(1) + u8_water(1) + CRC(4) = 12 bytes maximum for
    // a voxel near the origin (all coords < 64 => single varint byte each).
    // This asserts varints are actually being used and not fixed-width ints.
    {
        std::vector<EditCommand> cmds;
        cmds.push_back({ Vec3i{1, 2, 3}, EditOp::Place, 5, 0 });
        auto buf = encode_edits(cmds);

        // 12 bytes = minimal possible with version + CRC overhead.
        // Give a small headroom (say <=15) to avoid being brittle about
        // future minor format tweaks while still proving varints help.
        CHECK(buf.size() <= 15, "single small edit is compact (<=15 bytes)");
        // Also prove it's more than just the CRC footer (not degenerate).
        CHECK(buf.size() >= 10, "single small edit has expected minimum size");
    }

    // ---- empty command list round-trips ----
    {
        std::vector<EditCommand> empty_cmds;
        auto buf = encode_edits(empty_cmds);

        // Should encode fine: version(1) + varuint(0)(1) + CRC(4) = 6 bytes.
        CHECK(buf.size() == 6, "empty command list encodes to 6 bytes");

        std::vector<EditCommand> out;
        CHECK(decode_edits(buf, out),       "empty list decodes ok");
        CHECK(out.empty(),                  "empty list decodes to 0 commands");
    }

    // ---- CRC catches corruption: flip a byte -> decode returns false ----
    {
        std::vector<EditCommand> cmds;
        cmds.push_back({ Vec3i{5, 5, 5}, EditOp::Place, 3, 0 });
        auto buf = encode_edits(cmds);

        // Flip the first payload byte (after the version byte).
        auto corrupt = buf;
        corrupt[1] ^= 0xFF;

        std::vector<EditCommand> out;
        CHECK(!decode_edits(corrupt, out), "flipped payload byte -> CRC fails, decode=false");
    }

    // ---- CRC catches corruption: flip a byte in the middle ----
    {
        std::vector<EditCommand> cmds;
        cmds.push_back({ Vec3i{100, 200, 300}, EditOp::SetWater, 0, 7 });
        auto buf = encode_edits(cmds);

        auto corrupt = buf;
        corrupt[buf.size() / 2] ^= 0x01; // flip one bit somewhere in the middle

        std::vector<EditCommand> out;
        CHECK(!decode_edits(corrupt, out), "mid-buffer bit flip -> decode=false");
    }

    // ---- truncation: a buffer cut short -> decode returns false, no crash ----
    {
        std::vector<EditCommand> cmds;
        cmds.push_back({ Vec3i{1, 1, 1}, EditOp::Remove, 0, 0 });
        auto buf = encode_edits(cmds);

        // Try several truncation lengths, including 0 and 1 byte.
        for (size_t cut = 0; cut < buf.size(); ++cut) {
            std::vector<uint8_t> trunc(buf.begin(), buf.begin() + static_cast<long>(cut));
            std::vector<EditCommand> out;
            bool ok = decode_edits(trunc, out);
            // Every truncated buffer must fail (return false) and not crash.
            // We can't CHECK each one individually without flooding output,
            // so accumulate into a single boolean.
            if (ok) {
                ++g_fails;
                std::printf("  FAIL truncation at %zu bytes returned true  (%s:%d)\n",
                            cut, __FILE__, __LINE__);
            }
            ++g_checks;
        }
        // Verify the full buffer still works (sanity check after the truncation loop).
        std::vector<EditCommand> out;
        CHECK(decode_edits(buf, out), "full buffer still decodes after truncation tests");
    }

    // ---- out-of-range op byte -> decode returns false ----
    // Hand-craft a buffer with op byte = 99 (> EDIT_OP_MAX = 2).
    {
        // Build a valid buffer first, then patch the op byte.
        std::vector<EditCommand> cmds;
        cmds.push_back({ Vec3i{0, 0, 0}, EditOp::Place, 1, 0 });
        auto buf = encode_edits(cmds);

        // The op byte is at offset: version(1) + varuint_count(1) +
        // varint_x(1) + varint_y(1) + varint_z(1) = byte [5].
        // (All coords are 0, which encodes as single zero byte via zig-zag.)
        auto patched = buf;
        patched[5] = 99; // invalid op
        // The CRC was computed before the patch, so it will fail first.
        // Recompute the CRC over the patched body to isolate the op-range check.
        {
            const size_t body_len = patched.size() - 4;
            const uint32_t new_crc = bytes::crc32(patched.data(), body_len);
            patched[body_len + 0] = static_cast<uint8_t>(new_crc);
            patched[body_len + 1] = static_cast<uint8_t>(new_crc >> 8);
            patched[body_len + 2] = static_cast<uint8_t>(new_crc >> 16);
            patched[body_len + 3] = static_cast<uint8_t>(new_crc >> 24);
        }

        std::vector<EditCommand> out;
        CHECK(!decode_edits(patched, out), "op byte 99 -> decode=false (out-of-range op)");
    }


    // ================================================================
    //  BRICK DELTA
    // ================================================================

    // ---- BrickDelta round-trip: negative brick coords, several changes ----
    // Covers local_index 0 (first cell) and 511 (last cell) as edge cases.
    {
        BrickDelta d;
        d.brick = Vec3i{-3, 7, -100}; // negative brick coords

        d.changes.push_back({ 0,   5,  0 }); // first cell, solid material
        d.changes.push_back({ 255, 0, 42 }); // mid-range, water only
        d.changes.push_back({ 511, 3,  7 }); // last valid cell

        auto buf = encode_brick_delta(d);

        BrickDelta out;
        CHECK(decode_brick_delta(buf, out), "BrickDelta round-trip: decode=true");
        CHECK((out.brick == Vec3i{-3, 7, -100}), "BrickDelta brick coord");
        CHECK(out.changes.size() == 3,           "BrickDelta change count");

        if (out.changes.size() == 3) {
            CHECK(out.changes[0].local_index == 0,   "change0 local_index=0");
            CHECK(out.changes[0].type        == 5,   "change0 type=5");
            CHECK(out.changes[0].water       == 0,   "change0 water=0");

            CHECK(out.changes[1].local_index == 255, "change1 local_index=255");
            CHECK(out.changes[1].type        == 0,   "change1 type=0");
            CHECK(out.changes[1].water       == 42,  "change1 water=42");

            CHECK(out.changes[2].local_index == 511, "change2 local_index=511 (last valid)");
            CHECK(out.changes[2].type        == 3,   "change2 type=3");
            CHECK(out.changes[2].water       == 7,   "change2 water=7");
        }
    }

    // ---- BrickDelta: local_index 512 in a hand-crafted buffer -> rejected ----
    // We manually encode a delta where one change has local_index = 512.
    // The decoder must reject this as corruption (>= VOXELS_PER_BRICK).
    {
        // Build a valid-looking buffer with local_index = 512 (= 0x200).
        bytes::ByteWriter w;
        w.u8(BRICK_DELTA_VERSION);
        w.varint(0); // brick x
        w.varint(0); // brick y
        w.varint(0); // brick z
        w.varuint(1); // one change
        w.varuint(512); // local_index = 512 — out of range!
        w.u8(1); // type
        w.u8(0); // water
        w.append_crc32();

        BrickDelta out;
        CHECK(!decode_brick_delta(w.buf, out), "local_index 512 -> decode=false (out of range)");
    }

    // ---- BrickDelta: CRC catches corruption ----
    {
        BrickDelta d;
        d.brick = Vec3i{1, 2, 3};
        d.changes.push_back({ 10, 5, 0 });
        auto buf = encode_brick_delta(d);

        auto corrupt = buf;
        corrupt[0] ^= 0x01; // flip version byte (or re-CRC to target payload)
        // This also breaks the CRC footer, so decode must return false.

        BrickDelta out;
        CHECK(!decode_brick_delta(corrupt, out), "BrickDelta corrupted buffer -> decode=false");
    }

    // ---- BrickDelta: truncation -> decode returns false, no crash ----
    {
        BrickDelta d;
        d.brick = Vec3i{5, 5, 5};
        d.changes.push_back({ 100, 3, 1 });
        auto buf = encode_brick_delta(d);

        for (size_t cut = 0; cut < buf.size(); ++cut) {
            std::vector<uint8_t> trunc(buf.begin(), buf.begin() + static_cast<long>(cut));
            BrickDelta out;
            bool ok = decode_brick_delta(trunc, out);
            if (ok) {
                ++g_fails;
                std::printf("  FAIL BrickDelta truncation at %zu bytes returned true  (%s:%d)\n",
                            cut, __FILE__, __LINE__);
            }
            ++g_checks;
        }
        // Full buffer still works.
        BrickDelta out;
        CHECK(decode_brick_delta(buf, out), "full BrickDelta still decodes after truncation tests");
    }

    // ---- BrickDelta: empty changes list round-trips ----
    {
        BrickDelta d;
        d.brick = Vec3i{0, 0, 0};
        // no changes pushed

        auto buf = encode_brick_delta(d);

        BrickDelta out;
        CHECK(decode_brick_delta(buf, out),   "empty BrickDelta decodes ok");
        CHECK(out.changes.empty(),             "empty BrickDelta has 0 changes");
        CHECK((out.brick == Vec3i{0, 0, 0}),   "empty BrickDelta brick coord preserved");
    }

    // ---- Version byte mismatch -> decode=false ----
    // Flip the first byte to a wrong version number after computing a valid CRC.
    {
        std::vector<EditCommand> cmds;
        cmds.push_back({ Vec3i{1, 1, 1}, EditOp::Place, 1, 0 });
        auto buf = encode_edits(cmds);

        auto bad_ver = buf;
        bad_ver[0] = 99; // wrong version
        // Recompute CRC so the CRC check passes and the version check is isolated.
        {
            const size_t body_len = bad_ver.size() - 4;
            const uint32_t new_crc = bytes::crc32(bad_ver.data(), body_len);
            bad_ver[body_len + 0] = static_cast<uint8_t>(new_crc);
            bad_ver[body_len + 1] = static_cast<uint8_t>(new_crc >> 8);
            bad_ver[body_len + 2] = static_cast<uint8_t>(new_crc >> 16);
            bad_ver[body_len + 3] = static_cast<uint8_t>(new_crc >> 24);
        }
        std::vector<EditCommand> out;
        CHECK(!decode_edits(bad_ver, out), "wrong version byte -> decode_edits=false");
    }
    {
        BrickDelta d;
        d.brick = Vec3i{0, 0, 0};
        auto buf = encode_brick_delta(d);

        auto bad_ver = buf;
        bad_ver[0] = 99;
        {
            const size_t body_len = bad_ver.size() - 4;
            const uint32_t new_crc = bytes::crc32(bad_ver.data(), body_len);
            bad_ver[body_len + 0] = static_cast<uint8_t>(new_crc);
            bad_ver[body_len + 1] = static_cast<uint8_t>(new_crc >> 8);
            bad_ver[body_len + 2] = static_cast<uint8_t>(new_crc >> 16);
            bad_ver[body_len + 3] = static_cast<uint8_t>(new_crc >> 24);
        }
        BrickDelta out;
        CHECK(!decode_brick_delta(bad_ver, out), "wrong version byte -> decode_brick_delta=false");
    }

    // ================================================================
    //  Summary
    // ================================================================
    std::printf("[netvoxel] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
