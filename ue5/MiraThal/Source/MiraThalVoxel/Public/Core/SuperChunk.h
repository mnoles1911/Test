// SuperChunk.h — clipmap-style super-chunk LOD math (header-only Core).
//
// WHAT THIS IS (plain English): per-chunk LOD bottoms out at LOD 5, where a whole
// 32^3 chunk becomes ONE 320 cm cube. To see terrain MUCH further (hundreds of
// metres → ~1.5 km) without drowning the GPU in draw calls, we render the FAR band
// as "super-chunks": one coarse mesh that covers an N×N×N block of chunks. A single
// super-chunk replaces up to N^3 per-chunk actors with one draw call.
//
// A super-chunk is just a WIDER downsample. The block spans N*32 fine voxels per
// axis (256 for N=8). We downsample that to a grid no larger than CHUNK (32) so the
// EXISTING 34^3 mesh-slab + greedy-mesher path renders it unchanged. The super-LOD
// index L picks the fine→coarse stride; bigger L = coarser = farther.
//
// Pure C++17, no engine headers — compiles in the standalone clang harness.

#pragma once

#include "Core/MiraVec.h"       // Vec3i
#include "Core/ChunkCoords.h"   // coords::CHUNK

namespace mira {
namespace superchunk {

// Default super-chunk edge in CHUNKS. 8 → a 256-voxel (25.6 m) cube per super-chunk.
constexpr int DEFAULT_N = 8;

// Floor division that rounds toward negative infinity (so super coords are correct
// for negative chunk coords, unlike C++ truncating /). Self-contained on purpose.
inline int sc_floor_div(int a, int b) {
    int q = a / b;
    int r = a % b;
    if (r != 0 && ((r < 0) != (b < 0))) { --q; }
    return q;
}

// The super-chunk a given CHUNK coord belongs to (per axis).
inline Vec3i super_of_chunk(const Vec3i& c, int n) {
    return Vec3i(sc_floor_div(c.x, n), sc_floor_div(c.y, n), sc_floor_div(c.z, n));
}

// The CHUNK coord of a super-chunk's minimum corner.
inline Vec3i super_origin_chunk(const Vec3i& s, int n) {
    return Vec3i(s.x * n, s.y * n, s.z * n);
}

// Fine-voxel span of a super-chunk edge. N=8 → 256.
inline int span_voxels(int n) { return n * coords::CHUNK; }

// Fine→coarse downsample stride for super-LOD L. Chosen so the coarse grid side is
// ≤ CHUNK (32), letting the existing mesher run unchanged. For N=8 (span 256):
// base = log2(256/32) = 3, so stride = 2^(3+L) → 8 / 16 / 32 (coarse side 32 / 16 / 8).
inline int stride_for_lod(int n, int L) {
    const int span = span_voxels(n);
    int base = 0;
    while ((span >> base) > coords::CHUNK) { ++base; }
    if (L < 0) { L = 0; }
    return 1 << (base + L);
}

// Coarse grid side for super-LOD L: span / stride. N=8 → 32 / 16 / 8 for L=0/1/2.
inline int coarse_side(int n, int L) {
    const int s = stride_for_lod(n, L);
    return span_voxels(n) / s;
}

} // namespace superchunk
} // namespace mira
