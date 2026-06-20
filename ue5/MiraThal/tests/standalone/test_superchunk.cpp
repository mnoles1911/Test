// test_superchunk.cpp — headless harness for Core/SuperChunk.h (super-chunk LOD math).
//   cd tests/standalone && ./build.sh superchunk
//
// Locks the coordinate + stride/side math the clipmap super-chunk renderer relies on:
//   - floor-division (correct for negative coords),
//   - chunk -> super-chunk mapping,
//   - the fine->coarse stride / coarse-side per super-LOD (so the coarse grid stays
//     <= CHUNK and the existing 34^3 mesh path renders it unchanged).

#include <cstdio>

#include "Core/SuperChunk.h"
#include "Core/MiraVec.h"
#include "Core/ChunkCoords.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { \
    ++g_checks; \
    if (!(cond)) { ++g_fails; std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__); } \
} while (0)

int main() {
    using namespace mira;
    using namespace mira::superchunk;

    // --- floor division (rounds toward -inf) ---
    CHECK(sc_floor_div(0, 8) == 0,   "floordiv 0/8 = 0");
    CHECK(sc_floor_div(7, 8) == 0,   "floordiv 7/8 = 0");
    CHECK(sc_floor_div(8, 8) == 1,   "floordiv 8/8 = 1");
    CHECK(sc_floor_div(15, 8) == 1,  "floordiv 15/8 = 1");
    CHECK(sc_floor_div(-1, 8) == -1, "floordiv -1/8 = -1");
    CHECK(sc_floor_div(-8, 8) == -1, "floordiv -8/8 = -1");
    CHECK(sc_floor_div(-9, 8) == -2, "floordiv -9/8 = -2");

    // --- chunk -> super-chunk (N=8) ---
    {
        const Vec3i a = super_of_chunk(Vec3i(0, 0, 0), 8);
        CHECK(a.x == 0 && a.y == 0 && a.z == 0, "super_of_chunk(0) = 0");
        const Vec3i b = super_of_chunk(Vec3i(7, 3, 7), 8);
        CHECK(b.x == 0 && b.y == 0 && b.z == 0, "super_of_chunk(7,3,7) = 0");
        const Vec3i c = super_of_chunk(Vec3i(8, 8, 16), 8);
        CHECK(c.x == 1 && c.y == 1 && c.z == 2, "super_of_chunk(8,8,16) = (1,1,2)");
        const Vec3i d = super_of_chunk(Vec3i(-1, 0, 0), 8);
        CHECK(d.x == -1, "super_of_chunk(-1) = -1 (floored)");
        const Vec3i o = super_origin_chunk(Vec3i(1, 0, 2), 8);
        CHECK(o.x == 8 && o.z == 16, "super_origin_chunk(1,_,2) = (8,_,16)");
    }

    // --- span / stride / coarse side (N=8: span 256, base=log2(256/32)=3) ---
    CHECK(span_voxels(8) == 256, "span_voxels(8) = 256");
    CHECK(stride_for_lod(8, 0) == 8,  "stride L0 = 8");
    CHECK(stride_for_lod(8, 1) == 16, "stride L1 = 16");
    CHECK(stride_for_lod(8, 2) == 32, "stride L2 = 32");
    CHECK(coarse_side(8, 0) == 32, "coarse side L0 = 32 (== CHUNK)");
    CHECK(coarse_side(8, 1) == 16, "coarse side L1 = 16");
    CHECK(coarse_side(8, 2) == 8,  "coarse side L2 = 8");

    // --- FAR super-LOD bands L3/L4/L5 (the "as far as the eye can see" extension). ---
    // These are coarser still: stride 64/128/256, coarse side 4/2/1. They were already
    // mathematically supported by stride_for_lod/coarse_side (no clamp caps L at 2); these
    // checks LOCK them so a future change can't silently break the far-horizon bands.
    // side==1 (L5) is the extreme: a WHOLE 256-voxel (25.6 m) super-chunk becomes ONE
    // big cube — that single solid cell still meshes through the 34^3 apron'd slab path.
    CHECK(stride_for_lod(8, 3) == 64,  "stride L3 = 64");
    CHECK(stride_for_lod(8, 4) == 128, "stride L4 = 128");
    CHECK(stride_for_lod(8, 5) == 256, "stride L5 = 256");
    CHECK(coarse_side(8, 3) == 4, "coarse side L3 = 4");
    CHECK(coarse_side(8, 4) == 2, "coarse side L4 = 2");
    CHECK(coarse_side(8, 5) == 1, "coarse side L5 = 1 (whole super-chunk = 1 cube)");
    // every super-LOD L0..L5 must keep the coarse grid within CHUNK so the existing 34^3
    // mesh path is reused, and tile the span exactly (side * stride == span, no remainder).
    for (int L = 0; L <= 5; ++L) {
        CHECK(coarse_side(8, L) <= coords::CHUNK, "coarse side stays <= CHUNK");
        CHECK(coarse_side(8, L) >= 1,             "coarse side stays >= 1 (mesh path valid)");
        CHECK(coarse_side(8, L) * stride_for_lod(8, L) == 256, "side * stride == span (no remainder)");
    }

    // --- N=4 (span 128, base=2) ---
    CHECK(span_voxels(4) == 128, "span_voxels(4) = 128");
    CHECK(stride_for_lod(4, 0) == 4,  "N4 stride L0 = 4");
    CHECK(coarse_side(4, 0) == 32, "N4 coarse side L0 = 32");

    // --- N=16 (span 512, base=log2(512/32)=4) -------------------------------
    // The "far-scene actor count ~4x cut" knob: a 16-wide super covers 16x16
    // chunks instead of 8x8, so the far ring holds ~1/4 as many super actors.
    // N=16 is mathematically supported (the Core funcs take N), but it is NOT a
    // shipped default — this block LOCKS the math so a future change can't break
    // it and so the designer can safely set SuperChunkSizeChunks=16.
    //
    // span = 16 * 32 = 512. base loops while (512>>base) > 32 -> base = 4, so
    // stride = 2^(4+L) = 16/32/64/128/256/512 for L0..L5, and coarse side =
    // span/stride = 32/16/8/4/2/1. Every side stays <= CHUNK (32) and >= 1, so
    // each super-LOD still meshes through the existing apron'd 34^3 slab path
    // (the slab's inner cube holds 32 cells; coarse_side 32 fits exactly).
    CHECK(span_voxels(16) == 512, "span_voxels(16) = 512");
    CHECK(stride_for_lod(16, 0) == 16,  "N16 stride L0 = 16");
    CHECK(stride_for_lod(16, 1) == 32,  "N16 stride L1 = 32");
    CHECK(stride_for_lod(16, 2) == 64,  "N16 stride L2 = 64");
    CHECK(stride_for_lod(16, 3) == 128, "N16 stride L3 = 128");
    CHECK(stride_for_lod(16, 4) == 256, "N16 stride L4 = 256");
    CHECK(stride_for_lod(16, 5) == 512, "N16 stride L5 = 512");
    CHECK(coarse_side(16, 0) == 32, "N16 coarse side L0 = 32 (== CHUNK)");
    CHECK(coarse_side(16, 1) == 16, "N16 coarse side L1 = 16");
    CHECK(coarse_side(16, 2) == 8,  "N16 coarse side L2 = 8");
    CHECK(coarse_side(16, 3) == 4,  "N16 coarse side L3 = 4");
    CHECK(coarse_side(16, 4) == 2,  "N16 coarse side L4 = 2");
    CHECK(coarse_side(16, 5) == 1,  "N16 coarse side L5 = 1 (whole 512-vox super = 1 cube)");
    // Same invariants the N=8 band asserts: side*stride tiles the span exactly,
    // side stays within the mesh path, and side >= 1 (valid mesh).
    for (int L = 0; L <= 5; ++L) {
        CHECK(coarse_side(16, L) <= coords::CHUNK, "N16 coarse side stays <= CHUNK");
        CHECK(coarse_side(16, L) >= 1,             "N16 coarse side stays >= 1 (mesh path valid)");
        CHECK(coarse_side(16, L) * stride_for_lod(16, L) == 512, "N16 side * stride == span (no remainder)");
    }
    // chunk <-> super mapping at N=16 (floor-div over a 16-chunk block).
    {
        const Vec3i a = super_of_chunk(Vec3i(16, 5, 16), 16);
        CHECK(a.x == 1 && a.z == 1, "N16 super_of_chunk(16,_,16) = (1,_,1)");
        const Vec3i b = super_of_chunk(Vec3i(15, 0, 31), 16);
        CHECK(b.x == 0 && b.z == 1, "N16 super_of_chunk(15,_,31) = (0,_,1)");
        const Vec3i c = super_of_chunk(Vec3i(-1, 0, 0), 16);
        CHECK(c.x == -1, "N16 super_of_chunk(-1) = -1 (floored)");
        const Vec3i o = super_origin_chunk(Vec3i(1, 0, 1), 16);
        CHECK(o.x == 16 && o.z == 16, "N16 super_origin_chunk(1,_,1) = (16,_,16)");
    }

    std::printf("[superchunk] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
