// ByteIO.h — the shared byte-packing toolkit for saves and network packets.
//
// WHY THIS EXISTS (plain English): two different systems need to turn voxel data
// into a compact stream of bytes and back — the SAVE system (RegionFormat) and the
// MULTIPLAYER system (NetVoxelCodec). Rather than each reinventing "how do I write
// a number into bytes" (and risking two subtly different, incompatible formats),
// they both build on this one little toolkit:
//
//   ByteWriter — append numbers to a growing byte buffer. Includes VARINTS, which
//     store small numbers in fewer bytes (a value under 128 takes 1 byte, not 4) —
//     huge for edit logs full of small coordinates and ids.
//   ByteReader — read those numbers back, with an `ok` flag that trips false the
//     moment a read runs off the end (so a truncated/corrupt packet fails safe
//     instead of reading garbage).
//   crc32 — a checksum so a loader can tell "did this data arrive intact?" before
//     trusting it.
//
// Little-endian, standard IEEE CRC32 (0xEDB88320), LEB128 varints with zig-zag for
// signed values. Pure C++17, no engine types — `byteio` selector pins the format.

#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>

namespace mira {
namespace bytes {

// ---- CRC32 (IEEE, reflected, init/xorout 0xFFFFFFFF) ------------------------
// Computed on the fly (no static table) so the header stays self-contained and
// thread-safe. crc32("123456789") == 0xCBF43926 (the standard check value).
inline uint32_t crc32(const uint8_t* data, size_t len, uint32_t seed = 0) {
    uint32_t crc = ~seed;
    for (size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (int b = 0; b < 8; ++b)
            crc = (crc >> 1) ^ (0xEDB88320u & (~(crc & 1u) + 1u));
    }
    return ~crc;
}
inline uint32_t crc32(const std::vector<uint8_t>& v, uint32_t seed = 0) {
    return crc32(v.data(), v.size(), seed);
}

// ---- Writer -----------------------------------------------------------------
struct ByteWriter {
    std::vector<uint8_t> buf;

    void u8(uint8_t v) { buf.push_back(v); }
    void u16(uint16_t v) { u8(static_cast<uint8_t>(v)); u8(static_cast<uint8_t>(v >> 8)); }
    void u32(uint32_t v) { u16(static_cast<uint16_t>(v)); u16(static_cast<uint16_t>(v >> 16)); }

    // LEB128 unsigned varint: 7 bits per byte, high bit = "more follows".
    void varuint(uint64_t v) {
        while (v >= 0x80) { u8(static_cast<uint8_t>(v) | 0x80); v >>= 7; }
        u8(static_cast<uint8_t>(v));
    }
    // Zig-zag signed varint: maps small-magnitude negatives to small bytes too.
    void varint(int64_t v) {
        varuint((static_cast<uint64_t>(v) << 1) ^ static_cast<uint64_t>(v >> 63));
    }
    void raw(const uint8_t* p, size_t n) { buf.insert(buf.end(), p, p + n); }

    size_t size() const { return buf.size(); }

    // Append a CRC32 of everything written so far (footer-style integrity check).
    void append_crc32() { u32(crc32(buf)); }
};

// ---- Reader -----------------------------------------------------------------
// Every getter checks bounds; once `ok` goes false it stays false and getters
// return 0, so callers can do all reads then check ok() ONCE at the end.
struct ByteReader {
    const uint8_t* p = nullptr;
    size_t n = 0;
    size_t pos = 0;
    bool   ok_ = true;

    ByteReader() = default;
    ByteReader(const uint8_t* data, size_t len) : p(data), n(len) {}
    explicit ByteReader(const std::vector<uint8_t>& v) : p(v.data()), n(v.size()) {}

    bool   ok() const { return ok_; }
    size_t remaining() const { return pos <= n ? n - pos : 0; }

    uint8_t u8() {
        if (pos >= n) { ok_ = false; return 0; }
        return p[pos++];
    }
    uint16_t u16() { uint16_t a = u8(); uint16_t b = u8(); return static_cast<uint16_t>(a | (b << 8)); }
    uint32_t u32() { uint32_t a = u16(); uint32_t b = u16(); return a | (b << 16); }

    uint64_t varuint() {
        uint64_t r = 0;
        int shift = 0;
        for (;;) {
            if (pos >= n) { ok_ = false; return 0; }
            const uint8_t b = p[pos++];
            r |= static_cast<uint64_t>(b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
            shift += 7;
            if (shift > 63) { ok_ = false; return 0; } // malformed (overlong) varint
        }
        return r;
    }
    int64_t varint() {
        const uint64_t z = varuint();
        return static_cast<int64_t>(z >> 1) ^ -static_cast<int64_t>(z & 1);
    }

    // Verify a trailing CRC32 footer written by ByteWriter::append_crc32(). Call
    // when positioned at the footer (i.e. 4 bytes from the end). Consumes it.
    bool check_crc32() {
        if (remaining() < 4) { ok_ = false; return false; }
        const uint32_t body = crc32(p, pos); // CRC of everything before the footer
        const uint32_t want = u32();
        const bool good = ok_ && (body == want);
        if (!good) ok_ = false;
        return good;
    }
};

} // namespace bytes
} // namespace mira
