// ChunkCoords.h — the addressing math for the voxel world.
//
// THREE GRID LEVELS (plain English):
//   - VOXEL: one 10cm cube. Global voxel coordinates are int32 per axis — at
//     10 vox/m a 12km world is 120,000 voxels/axis, far inside int32's ~2.1B.
//   - BRICK: an 8x8x8 block of voxels. The brickmap stores the world as a sparse
//     hash of bricks, so an edit touches one brick, not the whole world.
//   - CHUNK: a 32x32x32 block of voxels (= 4x4x4 bricks). This is the MESH unit:
//     we greedy-mesh one chunk at a time. A chunk is a *view* assembled from its
//     bricks plus a 1-voxel apron of its neighbours (so border faces are correct).
//
// All math here is pure integer (floor division that works for negative coords)
// so the same routine is used by the mesher, the brickmap, streaming, and the
// (later) GPU mirror. No engine types — clang-testable in the headless harness.
//
// LARGE WORLDS: float32 world positions lose precision past ~1 km, but our voxel
// INDICES are exact int32. So rendering uses "tile-local" origins: a streaming
// tile picks an origin voxel, chunk meshes are expressed relative to it (small
// floats), and the UE actor transform carries the big double/LWC offset. The
// split helpers live here; the precision-boundary tests grow at milestone M4.

#pragma once

#include <cstdint>
#include "Core/MiraVec.h"

namespace mira {
namespace coords {

// Edge lengths, in voxels.
constexpr int BRICK = 8;   // brick = 8^3 voxels (sparse storage unit)
constexpr int CHUNK = 32;  // chunk = 32^3 voxels (mesh unit) = 4^3 bricks
constexpr int BRICKS_PER_CHUNK_AXIS = CHUNK / BRICK; // 4

// Voxel counts per unit (handy for buffer sizing).
constexpr int VOXELS_PER_BRICK = BRICK * BRICK * BRICK;   // 512
constexpr int VOXELS_PER_CHUNK = CHUNK * CHUNK * CHUNK;   // 32768

// Floor-divide that rounds toward negative infinity (NOT toward zero like C's /).
// We need -1/32 to be -1 (the chunk below the origin), not 0. Used everywhere a
// global voxel maps to its containing chunk/brick.
constexpr int32_t floor_div(int32_t a, int32_t b) {
    const int32_t q = a / b;
    const int32_t r = a % b;
    return (r != 0 && ((r < 0) != (b < 0))) ? q - 1 : q;
}

// Euclidean modulo in [0, b): the local offset of a voxel inside its chunk/brick,
// always non-negative even for negative global coords.
constexpr int32_t floor_mod(int32_t a, int32_t b) {
    const int32_t r = a % b;
    return (r != 0 && ((r < 0) != (b < 0))) ? r + b : r;
}

// --- Chunk addressing ---------------------------------------------------------

// Which chunk does this global voxel belong to?
constexpr Vec3i chunk_of_voxel(const Vec3i& v) {
    return { floor_div(v.x, CHUNK), floor_div(v.y, CHUNK), floor_div(v.z, CHUNK) };
}

// The local [0,CHUNK) offset of a global voxel within its chunk.
constexpr Vec3i local_in_chunk(const Vec3i& v) {
    return { floor_mod(v.x, CHUNK), floor_mod(v.y, CHUNK), floor_mod(v.z, CHUNK) };
}

// The global voxel coordinate of a chunk's (0,0,0) corner.
constexpr Vec3i chunk_origin_voxel(const Vec3i& chunk) {
    return { chunk.x * CHUNK, chunk.y * CHUNK, chunk.z * CHUNK };
}

// --- Brick addressing ---------------------------------------------------------

constexpr Vec3i brick_of_voxel(const Vec3i& v) {
    return { floor_div(v.x, BRICK), floor_div(v.y, BRICK), floor_div(v.z, BRICK) };
}

constexpr Vec3i local_in_brick(const Vec3i& v) {
    return { floor_mod(v.x, BRICK), floor_mod(v.y, BRICK), floor_mod(v.z, BRICK) };
}

constexpr Vec3i brick_origin_voxel(const Vec3i& brick) {
    return { brick.x * BRICK, brick.y * BRICK, brick.z * BRICK };
}

// --- Flatten / unflatten ------------------------------------------------------
// Y-fastest layout (index = x*sy*sz... no — we use X-fastest then Y then Z so a
// row of X is contiguous, which the greedy mesher sweeps). Layout: index =
// x + y*side + z*side*side. `side` is the array edge (CHUNK, BRICK, or an
// apron'd 34 for a mesh slab). One formula, reused everywhere, so storage order
// never disagrees between writer and reader.

// Returns int64: the index can exceed 2^31 for a large `side` (z*side*side overflows int32
// once side > ~1290). CHUNK/BRICK/slab(34) are tiny so this never bit, but the helper is reused
// for arbitrary tile_edge_voxels, so we compute in 64-bit to be overflow-proof. Each term is
// promoted to int64 BEFORE the multiply, so no intermediate int32 product can wrap.
constexpr int64_t flatten(int x, int y, int z, int side) {
    return static_cast<int64_t>(x)
         + static_cast<int64_t>(y) * side
         + static_cast<int64_t>(z) * side * side;
}
constexpr int64_t flatten(const Vec3i& p, int side) { return flatten(p.x, p.y, p.z, side); }

// --- Neighbours ---------------------------------------------------------------
// The 6 face-adjacent unit steps, in the canonical face order used by the mesher
// and the water/flow code: -X, +X, -Y, +Y, -Z, +Z.
constexpr Vec3i FACE_OFFSET[6] = {
    {-1, 0, 0}, {1, 0, 0},
    { 0,-1, 0}, {0, 1, 0},
    { 0, 0,-1}, {0, 0, 1},
};

// --- Large-world (LWC) tile split --------------------------------------------
// Split a global voxel into (tile index, local voxel within the tile) for a
// given tile edge in voxels. Rendering uses the tile's origin as a small-float
// local space; the actor transform carries the tile's double world offset.
// (The double-precision world-position math is exercised by M4's precision tests;
// here we provide the exact integer split the renderer keys off.)
constexpr Vec3i tile_of_voxel(const Vec3i& v, int tile_edge_voxels) {
    return { floor_div(v.x, tile_edge_voxels),
             floor_div(v.y, tile_edge_voxels),
             floor_div(v.z, tile_edge_voxels) };
}
constexpr Vec3i local_in_tile(const Vec3i& v, int tile_edge_voxels) {
    return { floor_mod(v.x, tile_edge_voxels),
             floor_mod(v.y, tile_edge_voxels),
             floor_mod(v.z, tile_edge_voxels) };
}

} // namespace coords
} // namespace mira
