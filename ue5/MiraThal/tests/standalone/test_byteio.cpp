// test_byteio.cpp — parity harness for Core/ByteIO.h.
//   cd tests/standalone && ./build.sh byteio

#include <cstdio>
#include <cstring>
#include "Core/ByteIO.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira::bytes;

int main() {
    // ---- CRC32 standard check value ----
    {
        const char* s = "123456789";
        const uint32_t c = crc32(reinterpret_cast<const uint8_t*>(s), 9);
        CHECK(c == 0xCBF43926u, "crc32(\"123456789\") == 0xCBF43926");
        CHECK(crc32(nullptr, 0) == 0u, "crc32 of empty is 0");
    }

    // ---- fixed-width round trips (little-endian) ----
    {
        ByteWriter w;
        w.u8(0xAB);
        w.u16(0x1234);
        w.u32(0xDEADBEEF);
        CHECK(w.buf[0] == 0xAB, "u8 stored");
        CHECK(w.buf[1] == 0x34 && w.buf[2] == 0x12, "u16 little-endian");
        CHECK(w.buf[3] == 0xEF && w.buf[6] == 0xDE, "u32 little-endian");

        ByteReader r(w.buf);
        CHECK(r.u8() == 0xAB, "u8 read back");
        CHECK(r.u16() == 0x1234, "u16 read back");
        CHECK(r.u32() == 0xDEADBEEFu, "u32 read back");
        CHECK(r.ok() && r.remaining() == 0, "reader consumed all, still ok");
    }

    // ---- varuint: small values are 1 byte; large round-trip ----
    {
        ByteWriter w;
        w.varuint(0);
        w.varuint(127);
        w.varuint(128);
        w.varuint(300);
        w.varuint(0xFFFFFFFFull);
        CHECK(w.buf[0] == 0 && w.buf[1] == 127, "varuint < 128 is a single byte");

        ByteReader r(w.buf);
        CHECK(r.varuint() == 0, "varuint 0");
        CHECK(r.varuint() == 127, "varuint 127");
        CHECK(r.varuint() == 128, "varuint 128");
        CHECK(r.varuint() == 300, "varuint 300");
        CHECK(r.varuint() == 0xFFFFFFFFull, "varuint 4G-1");
        CHECK(r.ok(), "reader ok after varuints");
    }

    // ---- varint: zig-zag keeps small negatives small ----
    {
        ByteWriter w;
        w.varint(0);
        w.varint(-1);
        w.varint(1);
        w.varint(-1000000);
        w.varint(1000000);
        CHECK(w.buf[0] == 0 && w.buf[1] == 1, "zig-zag: 0->0, -1->1 (one byte each)");

        ByteReader r(w.buf);
        CHECK(r.varint() == 0, "varint 0");
        CHECK(r.varint() == -1, "varint -1");
        CHECK(r.varint() == 1, "varint 1");
        CHECK(r.varint() == -1000000, "varint -1e6");
        CHECK(r.varint() == 1000000, "varint 1e6");
        CHECK(r.ok(), "reader ok after varints");
    }

    // ---- truncation fails safe ----
    {
        ByteWriter w; w.u32(42);
        ByteReader r(w.buf.data(), 2); // only 2 of the 4 bytes available
        r.u32();
        CHECK(!r.ok(), "reading past the end trips ok=false");
    }

    // ---- overlong varint is rejected ----
    {
        std::vector<uint8_t> bad(12, 0x80); // all continuation bits, never terminates
        ByteReader r(bad);
        r.varuint();
        CHECK(!r.ok(), "overlong varint trips ok=false");
    }

    // ---- CRC footer round trip + corruption detection ----
    {
        ByteWriter w;
        w.varuint(12345);
        w.u8(7);
        w.append_crc32();
        ByteReader r(w.buf);
        CHECK(r.varuint() == 12345, "payload read before footer");
        CHECK(r.u8() == 7, "payload byte");
        CHECK(r.check_crc32(), "intact CRC footer verifies");

        // Flip a payload byte -> CRC must fail.
        std::vector<uint8_t> corrupt = w.buf;
        corrupt[0] ^= 0xFF;
        ByteReader r2(corrupt);
        r2.varuint(); r2.u8();
        CHECK(!r2.check_crc32(), "corrupted payload fails CRC");
    }

    std::printf("[byteio  ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
