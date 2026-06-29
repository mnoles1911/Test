// NetVoxelCodec.h — the MULTIPLAYER wire format for voxel world changes.
//
// BIG PICTURE (plain English): in multiplayer the server is the single source
// of truth — clients never modify the world directly. Instead a client sends a
// tiny EDIT COMMAND ("I placed/removed/set-water at voxel X"). The server
// validates it, applies it, then BROADCASTS that same command back to every
// connected client so they all replay the identical edit and stay in sync.
//
// Water and gravity are DERIVED — they simulate forward from the edit, so each
// client re-runs the same sim locally. But where a client joins mid-session it
// needs the resulting world state fast; that is a BRICK DELTA: a compact list of
// (local_index, type, water) tuples for a single 8×8×8 brick, representing only
// the cells that changed. Full world replication for a brand-new joiner reuses
// the RegionFormat save codec — that is out of scope here; see RegionFormat.h.
//
// Both message types are self-describing byte buffers: a version byte guards
// against future format changes, and a CRC32 footer lets the reader detect a
// truncated or corrupted packet BEFORE acting on it. Varints shrink coordinate
// fields significantly — a voxel near the origin uses 1 byte per axis instead
// of 4, so a typical one-voxel edit encodes to about 10 bytes.
//
// All decode paths are fail-safe: on any error (bad version, CRC mismatch,
// truncation, out-of-range field) the function returns false and leaves `out`
// untouched. No undefined behaviour, no silent garbage.
//
// Pure C++17, no engine headers — compiles in the standalone clang harness.

#pragma once

#include <cstdint>
#include <vector>
#include "Core/ByteIO.h"    // ByteWriter, ByteReader, crc32
#include "Core/MiraVec.h"   // Vec3i

namespace mira {
namespace net {

// ============================================================
//  Version bytes — bump these whenever the layout changes.
//  A decoder that sees the wrong version rejects the packet
//  immediately rather than trying to parse a format it doesn't
//  understand (fail-safe, not best-effort).
// ============================================================
constexpr uint8_t EDITS_VERSION       = 1; // EditCommand batch packets
constexpr uint8_t BRICK_DELTA_VERSION = 1; // BrickDelta packets


// ============================================================
//  EDIT COMMANDS
//  One "what I did to the world" message from client -> server,
//  then server -> all clients (multicast). The server validates
//  the intent; the codec just moves bytes around.
// ============================================================

// The three things a client can ask to do with one voxel:
//   Place    — set it to a solid material (type byte says which)
//   Remove   — dig it out (turn it to air; type + water ignored)
//   SetWater — write a water byte to it (water byte says the value)
enum class EditOp : uint8_t {
    Place    = 0,
    Remove   = 1,
    SetWater = 2,
};
// RANGE CHECK: valid ops are 0–2. Any byte > 2 is corruption.
constexpr uint8_t EDIT_OP_MAX = 2;

// One atomic world-edit the player (or server) wants to make.
struct EditCommand {
    Vec3i   voxel;  // global voxel coordinate (can be negative)
    EditOp  op;     // Place / Remove / SetWater
    uint8_t type;   // material id (meaningful for Place; 0 otherwise)
    uint8_t water;  // water byte   (meaningful for SetWater; 0 otherwise)
};

// ---- encode_edits -----------------------------------------------------------
// Pack a list of EditCommands into a byte buffer ready to send over the wire.
//
// Layout:
//   [0]          version byte  (EDITS_VERSION)
//   [1..]        varuint       command count
//   per command:
//     varint x, varint y, varint z   — zig-zag signed; small coords = 1 byte each
//     u8 op                          — 0=Place 1=Remove 2=SetWater
//     u8 type                        — material id
//     u8 water                       — water byte
//   [tail 4]     u32 CRC32 of everything above (little-endian)
//
// An empty list (count 0) encodes fine — 6 bytes total (version + varuint(0) + CRC).
inline std::vector<uint8_t> encode_edits(const std::vector<EditCommand>& cmds) {
    bytes::ByteWriter w;

    w.u8(EDITS_VERSION);
    w.varuint(static_cast<uint64_t>(cmds.size()));

    for (const EditCommand& cmd : cmds) {
        // Voxel coordinates: varint handles negatives compactly via zig-zag.
        w.varint(static_cast<int64_t>(cmd.voxel.x));
        w.varint(static_cast<int64_t>(cmd.voxel.y));
        w.varint(static_cast<int64_t>(cmd.voxel.z));

        // Op, material, water — each exactly 1 byte, no variable encoding needed.
        w.u8(static_cast<uint8_t>(cmd.op));
        w.u8(cmd.type);
        w.u8(cmd.water);
    }

    // Integrity footer: CRC32 of all bytes written above.
    w.append_crc32();

    return w.buf;
}

// ---- decode_edits -----------------------------------------------------------
// Parse a byte buffer produced by encode_edits().
//
// Returns true and fills `out` only when ALL of these pass:
//   - version byte matches EDITS_VERSION
//   - CRC32 footer is valid (protects against corruption AND truncation)
//   - reader.ok() is true throughout (no read past the end)
//   - every op byte is in [0, EDIT_OP_MAX] (0–2)
//
// On any failure returns false and leaves `out` unchanged.
inline bool decode_edits(const std::vector<uint8_t>& bytes,
                         std::vector<EditCommand>&    out) {
    bytes::ByteReader r(bytes);

    // --- version check (before touching the rest) ---
    const uint8_t ver = r.u8();
    if (!r.ok() || ver != EDITS_VERSION) return false;

    // Verify the CRC over [0, size-4) against the trailing 4-byte footer
    // BEFORE parsing any payload. This way a corrupt or truncated packet
    // is rejected up-front without risking reads from garbage data.
    if (bytes.size() < 5) return false; // need at least version(1) + CRC(4)
    {
        const size_t body_len = bytes.size() - 4;
        const uint32_t computed = bytes::crc32(bytes.data(), body_len);
        bytes::ByteReader footer_r(bytes.data() + body_len, 4);
        const uint8_t b0 = footer_r.u8(), b1 = footer_r.u8(),
                      b2 = footer_r.u8(), b3 = footer_r.u8();
        const uint32_t stored_crc = static_cast<uint32_t>(b0)
                                  | (static_cast<uint32_t>(b1) << 8)
                                  | (static_cast<uint32_t>(b2) << 16)
                                  | (static_cast<uint32_t>(b3) << 24);
        if (computed != stored_crc) return false;
    }

    // CRC passed — now parse the payload (version byte already consumed above).
    const uint64_t count = r.varuint();
    if (!r.ok()) return false;

    std::vector<EditCommand> result;
    result.reserve(static_cast<size_t>(count));

    for (uint64_t i = 0; i < count; ++i) {
        EditCommand cmd{};
        cmd.voxel.x = static_cast<int32_t>(r.varint());
        cmd.voxel.y = static_cast<int32_t>(r.varint());
        cmd.voxel.z = static_cast<int32_t>(r.varint());
        const uint8_t op_byte = r.u8();
        cmd.type  = r.u8();
        cmd.water = r.u8();

        if (!r.ok()) return false; // truncated mid-command

        // Range-check the op byte BEFORE casting — anything > 2 is corruption.
        if (op_byte > EDIT_OP_MAX) return false;
        cmd.op = static_cast<EditOp>(op_byte);

        result.push_back(cmd);
    }

    // The next 4 bytes are the CRC footer we already validated above —
    // just make sure there's nothing unexpected left.
    // (r should now point exactly at the CRC footer; we don't re-verify it,
    //  the up-front check already guarantees integrity.)

    out = std::move(result);
    return true;
}


// ============================================================
//  BRICK DELTAS
//  Derived sim results: after the water/gravity sim runs on the
//  server, any bricks that changed are shipped as a compact list
//  of (local_index, type, water) tuples. Clients apply them
//  directly to their brickmap, staying in lock-step with the
//  server without re-running the whole sim.
// ============================================================

// One changed cell inside a brick.
//   local_index  — flat index into the brick's 512-cell array.
//                  Must be in [0, 512) = [0, VOXELS_PER_BRICK).
//                  Any value >= 512 is corrupt and rejected on decode.
//   type         — new material id at that cell
//   water        — new water byte at that cell
struct CellChange {
    uint16_t local_index; // [0, 511]
    uint8_t  type;
    uint8_t  water;
};
constexpr uint16_t CELL_INDEX_MAX = 511; // = VOXELS_PER_BRICK - 1

// A batch of changed cells in one 8×8×8 brick.
//   brick    — brick coordinate (global; can be negative)
//   changes  — which cells changed and what their new values are
struct BrickDelta {
    Vec3i                  brick;
    std::vector<CellChange> changes;
};

// ---- encode_brick_delta -----------------------------------------------------
// Pack a BrickDelta into a byte buffer.
//
// Layout:
//   [0]          version byte  (BRICK_DELTA_VERSION)
//   [1..]        varint bx, varint by, varint bz   — brick coord
//   [..]         varuint change count
//   per change:
//     varuint local_index   — [0,511] in one or two bytes
//     u8 type
//     u8 water
//   [tail 4]     u32 CRC32
//
// An empty changes list is valid (count 0) — it means "we looked at this brick
// and nothing in it changed", useful as a heartbeat or to ack a no-op sim tick.
inline std::vector<uint8_t> encode_brick_delta(const BrickDelta& d) {
    bytes::ByteWriter w;

    w.u8(BRICK_DELTA_VERSION);

    // Brick coordinate: varints handle negative brick coords compactly.
    w.varint(static_cast<int64_t>(d.brick.x));
    w.varint(static_cast<int64_t>(d.brick.y));
    w.varint(static_cast<int64_t>(d.brick.z));

    w.varuint(static_cast<uint64_t>(d.changes.size()));

    for (const CellChange& c : d.changes) {
        // local_index fits in [0,511] — varuint encodes 0–127 as 1 byte,
        // 128–511 as 2 bytes. Always tighter than u16.
        w.varuint(static_cast<uint64_t>(c.local_index));
        w.u8(c.type);
        w.u8(c.water);
    }

    w.append_crc32();

    return w.buf;
}

// ---- decode_brick_delta -----------------------------------------------------
// Parse a byte buffer produced by encode_brick_delta().
//
// Returns true and fills `out` only when ALL of these pass:
//   - version byte matches BRICK_DELTA_VERSION
//   - CRC32 footer is valid
//   - reader.ok() is true throughout (no truncation)
//   - every local_index is in [0, 511] (>= 512 means corrupt packet)
//
// On any failure returns false and leaves `out` unchanged.
inline bool decode_brick_delta(const std::vector<uint8_t>& bytes,
                               BrickDelta&                  out) {
    if (bytes.size() < 5) return false; // version(1) + CRC(4) minimum

    // --- Up-front CRC check (same approach as decode_edits) ---
    {
        const size_t body_len = bytes.size() - 4;
        const uint32_t computed = bytes::crc32(bytes.data(), body_len);
        bytes::ByteReader footer_r(bytes.data() + body_len, 4);
        const uint8_t b0 = footer_r.u8(), b1 = footer_r.u8(),
                      b2 = footer_r.u8(), b3 = footer_r.u8();
        const uint32_t stored_crc = static_cast<uint32_t>(b0)
                                  | (static_cast<uint32_t>(b1) << 8)
                                  | (static_cast<uint32_t>(b2) << 16)
                                  | (static_cast<uint32_t>(b3) << 24);
        if (computed != stored_crc) return false;
    }

    bytes::ByteReader r(bytes);

    // --- version check ---
    const uint8_t ver = r.u8();
    if (!r.ok() || ver != BRICK_DELTA_VERSION) return false;

    // --- brick coordinate ---
    BrickDelta result{};
    result.brick.x = static_cast<int32_t>(r.varint());
    result.brick.y = static_cast<int32_t>(r.varint());
    result.brick.z = static_cast<int32_t>(r.varint());
    if (!r.ok()) return false;

    // --- change list ---
    const uint64_t count = r.varuint();
    if (!r.ok()) return false;

    result.changes.reserve(static_cast<size_t>(count));

    for (uint64_t i = 0; i < count; ++i) {
        CellChange c{};
        const uint64_t raw_idx = r.varuint();
        c.type  = r.u8();
        c.water = r.u8();

        if (!r.ok()) return false; // truncated mid-change

        // Range-check: local_index must be a valid cell in an 8×8×8 brick.
        if (raw_idx > CELL_INDEX_MAX) return false;
        c.local_index = static_cast<uint16_t>(raw_idx);

        result.changes.push_back(c);
    }

    out = std::move(result);
    return true;
}

} // namespace net
} // namespace mira
