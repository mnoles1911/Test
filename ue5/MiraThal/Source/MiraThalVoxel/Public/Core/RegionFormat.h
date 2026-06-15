// RegionFormat.h — on-disk byte format for world saves.
//
// THE BIG IDEA (plain English): we save the world as "what the seed generator
// would produce, PLUS a log of every voxel the player ever changed." Untouched
// terrain is never written to disk — the generator recreates it for free. This
// file handles the BYTE LAYOUT for two things:
//
//   1. BRICK RLE — encoding one 8x8x8 brick (512 type bytes + 512 water bytes)
//      in run-length form.  A brick of solid stone is 512 identical bytes; RLE
//      collapses that to two numbers (run=512, value=1). The wins are huge —
//      most bricks are large homogeneous runs, so the encoded size is typically
//      a tiny fraction of the raw 1024 bytes.
//
//   2. DELTA LOG — a compact list of individual voxel edits (coord + new type +
//      new water).  Each edit uses varint coords (zig-zag keeps negatives small)
//      so the common case of small absolute coordinates costs very few bytes.
//
// Both formats use a version byte at the front (future-proofing) and a CRC32
// footer (corruption detection). The reader fails safe: if anything doesn't add
// up — wrong version, bad CRC, truncated data, RLE that doesn't sum to exactly
// 512 — the decode function returns false and leaves the output untouched.
//
// File I/O (opening/closing files, mapping to disk paths, region file naming)
// lives in the higher-level glue layer. This header is PURE byte packing and
// unpacking: give it a vector, get a vector back, no file handles anywhere.
//
// Pure C++17, no engine headers — compiles identically in the standalone clang
// test harness and inside the Unreal module.

#pragma once

#include <cstdint>
#include <vector>
#include "Core/ByteIO.h"
#include "Core/Brickmap.h"
#include "Core/MaterialIds.h"

namespace mira {
namespace region {

// ---- Version sentinels -------------------------------------------------------
// Bump BRICK_VERSION or DELTA_VERSION (not both, independently) whenever the
// byte layout changes in a breaking way.  The decoder rejects a mismatch
// immediately so an old binary never silently misreads a newer file.

static constexpr uint8_t BRICK_VERSION = 0x01;
static constexpr uint8_t DELTA_VERSION = 0x01;

// ---- Brick RLE codec ---------------------------------------------------------
//
// FORMAT (bytes, in order):
//   [0]          BRICK_VERSION  (u8 — must match on decode)
//   [1..]        RLE of 512 TYPE  bytes: pairs of (varuint run_length, u8 value)
//   [..]         RLE of 512 WATER bytes: same scheme
//   [last 4]     CRC32 of everything above (little-endian u32, IEEE poly)
//
// The RLE scheme: walk the 512-cell array. Each run is (length, value) where
// length >= 1. Runs do NOT cross channel boundaries — we encode type completely,
// then start fresh for water.

// encode_brick — turn a Brick into a CRC-protected RLE byte vector.
//
// Returns a vector that is MUCH smaller than 1024 bytes for typical bricks
// (all-air or all-solid), and at most a modest overhead for pathological
// checkerboard input.
inline std::vector<uint8_t> encode_brick(const Brick& b) {
    bytes::ByteWriter w;

    // Format version byte so the decoder can reject mismatches.
    w.u8(BRICK_VERSION);

    // ---- Encode the TYPE channel via RLE ----
    // Walk all 512 slots. Accumulate the current run (value + length).
    // Whenever the value changes (or we reach the end), flush the run.
    {
        uint8_t cur_val = b.type[0];
        uint64_t run = 1;
        for (int i = 1; i < coords::VOXELS_PER_BRICK; ++i) {
            if (b.type[i] == cur_val) {
                ++run;
            } else {
                w.varuint(run);  // run length first (small numbers = few bytes)
                w.u8(cur_val);   // then the material id
                cur_val = b.type[i];
                run = 1;
            }
        }
        // Flush the final run.
        w.varuint(run);
        w.u8(cur_val);
    }

    // ---- Encode the WATER channel via RLE (same scheme, fresh run state) ----
    {
        uint8_t cur_val = b.water[0];
        uint64_t run = 1;
        for (int i = 1; i < coords::VOXELS_PER_BRICK; ++i) {
            if (b.water[i] == cur_val) {
                ++run;
            } else {
                w.varuint(run);
                w.u8(cur_val);
                cur_val = b.water[i];
                run = 1;
            }
        }
        w.varuint(run);
        w.u8(cur_val);
    }

    // CRC32 footer — covers everything written above.
    w.append_crc32();

    return w.buf;
}

// decode_brick — verify and unpack a byte vector produced by encode_brick.
//
// Returns true and fills `out` on success.  Returns false (out is unspecified)
// on: wrong version, CRC mismatch, truncated input, or RLE that doesn't sum to
// exactly 512 cells per channel.
//
// After a successful decode, solid_count and nonzero_count are RECOMPUTED from
// scratch — not read from the file — so they can never be accidentally corrupted
// by a stale cached value.
inline bool decode_brick(const std::vector<uint8_t>& data, Brick& out) {
    // We need at least version byte + 4-byte CRC footer to do anything.
    if (data.size() < 5) return false;

    bytes::ByteReader r(data);

    // Check the version before reading anything else.
    const uint8_t ver = r.u8();
    if (ver != BRICK_VERSION) return false;

    // We read into a local brick so `out` stays clean if decoding fails midway.
    Brick tmp;

    // ---- Decode the TYPE channel ----
    {
        int filled = 0; // how many of the 512 slots we've written so far
        while (filled < coords::VOXELS_PER_BRICK) {
            // We need at least a run-length byte and a value byte remaining
            // (plus the 4-byte CRC footer at the very end of the buffer).
            // ByteReader's ok_ flag will trip false on overread — we check below.
            const uint64_t run = r.varuint();
            const uint8_t  val = r.u8();
            if (!r.ok()) return false;

            // Guard against a malicious/corrupt run that would overflow the array.
            if (run == 0 || run > static_cast<uint64_t>(coords::VOXELS_PER_BRICK - filled)) {
                return false;
            }
            for (uint64_t j = 0; j < run; ++j) {
                tmp.type[filled++] = val;
            }
        }
        // The RLE must have consumed EXACTLY 512 cells — no more, no less.
        if (filled != coords::VOXELS_PER_BRICK) return false;
    }

    // ---- Decode the WATER channel ----
    {
        int filled = 0;
        while (filled < coords::VOXELS_PER_BRICK) {
            const uint64_t run = r.varuint();
            const uint8_t  val = r.u8();
            if (!r.ok()) return false;

            if (run == 0 || run > static_cast<uint64_t>(coords::VOXELS_PER_BRICK - filled)) {
                return false;
            }
            for (uint64_t j = 0; j < run; ++j) {
                tmp.water[filled++] = val;
            }
        }
        if (filled != coords::VOXELS_PER_BRICK) return false;
    }

    // ---- CRC footer — must be exactly here (nothing trailing after it) ----
    // check_crc32() reads the 4-byte footer from the current position, verifies
    // it against everything that came before, then advances past it.
    if (!r.check_crc32()) return false;

    // The reader must now be fully consumed. If bytes remain, the format is wrong.
    if (r.remaining() != 0) return false;

    // ---- Recompute the occupancy counters from scratch ----
    // We deliberately DO NOT store solid_count / nonzero_count in the file.
    // Recomputing them here means they are always correct and can never get out
    // of sync with the actual data (a stale counter would cause meshing or GC
    // bugs that are very hard to track down).
    tmp.solid_count   = 0;
    tmp.nonzero_count = 0;
    for (int i = 0; i < coords::VOXELS_PER_BRICK; ++i) {
        // solid_count: voxels whose type is anything other than air.
        if (tmp.type[i] != static_cast<uint8_t>(mat::AIR)) {
            ++tmp.solid_count;
        }
        // nonzero_count: voxels where EITHER type OR water is non-zero.
        // Drives the sparse GC: if this reaches 0 the brick is dropped.
        if (tmp.type[i] != 0 || tmp.water[i] != 0) {
            ++tmp.nonzero_count;
        }
    }

    out = tmp;
    return true;
}

// ---- Delta log codec ---------------------------------------------------------
//
// A delta log is a compact ordered list of individual voxel edits.  The game
// records every player-made change here; at load time the generator recreates
// the base terrain and we replay these edits on top to restore the world.
//
// FORMAT (bytes, in order):
//   [0]          DELTA_VERSION  (u8)
//   [1..]        count          (varuint — total number of edits)
//   [..]         per edit, repeated `count` times:
//                    x (varint zig-zag — handles negative coords cheaply)
//                    y (varint zig-zag)
//                    z (varint zig-zag)
//                    type  (u8 — material id)
//                    water (u8 — WaterByteCodec byte, 0 = no water)
//   [last 4]     CRC32 footer

// One recorded player edit: the global voxel coordinate + both data channels.
struct VoxelEdit {
    Vec3i   voxel;  // global voxel coordinate (can be large negative or positive)
    uint8_t type;   // material id to write (0 = carve to air)
    uint8_t water;  // water byte to write  (0 = remove water)
};

// encode_delta_log — pack a list of edits into a CRC-protected byte vector.
// An empty list is legal and produces a tiny ~6-byte result.
inline std::vector<uint8_t> encode_delta_log(const std::vector<VoxelEdit>& edits) {
    bytes::ByteWriter w;

    w.u8(DELTA_VERSION);

    // Total edit count lets the decoder pre-validate and pre-allocate.
    w.varuint(static_cast<uint64_t>(edits.size()));

    for (const VoxelEdit& e : edits) {
        // Zig-zag varint: small-magnitude negative values (think coords near the
        // origin like -3, 10, -200) encode in fewer bytes than a flat int32.
        w.varint(static_cast<int64_t>(e.voxel.x));
        w.varint(static_cast<int64_t>(e.voxel.y));
        w.varint(static_cast<int64_t>(e.voxel.z));
        w.u8(e.type);
        w.u8(e.water);
    }

    w.append_crc32();

    return w.buf;
}

// decode_delta_log — verify and unpack a byte vector from encode_delta_log.
//
// Returns true and fills `out` on success.  Returns false on: wrong version,
// CRC mismatch, truncated input.  `out` is cleared on entry so a partial
// result is never left behind on failure.
inline bool decode_delta_log(const std::vector<uint8_t>& data, std::vector<VoxelEdit>& out) {
    out.clear();

    // Minimum viable buffer: version(1) + count(1 for empty) + CRC(4) = 6 bytes.
    if (data.size() < 6) return false;

    bytes::ByteReader r(data);

    const uint8_t ver = r.u8();
    if (ver != DELTA_VERSION) return false;

    const uint64_t count = r.varuint();
    if (!r.ok()) return false;

    // Sanity cap: guard against a corrupt count that would balloon memory.
    // 64 million edits is already absurdly large for a single save file.
    constexpr uint64_t MAX_EDITS = 64u * 1024u * 1024u;
    if (count > MAX_EDITS) return false;

    out.reserve(static_cast<size_t>(count));

    for (uint64_t i = 0; i < count; ++i) {
        VoxelEdit e;
        e.voxel.x = static_cast<int32_t>(r.varint());
        e.voxel.y = static_cast<int32_t>(r.varint());
        e.voxel.z = static_cast<int32_t>(r.varint());
        e.type    = r.u8();
        e.water   = r.u8();

        // Check ok_ after each edit — stops early on truncation without
        // leaving partially-initialized edits in the output.
        if (!r.ok()) {
            out.clear();
            return false;
        }

        out.push_back(e);
    }

    // CRC footer — verify integrity of everything we just read.
    if (!r.check_crc32()) {
        out.clear();
        return false;
    }

    // Buffer must be fully consumed.
    if (r.remaining() != 0) {
        out.clear();
        return false;
    }

    return true;
}

} // namespace region
} // namespace mira
