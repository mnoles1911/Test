// BrickmapMeshing.h — the bridge from the sparse Brickmap to the greedy mesher.
//
// THE PROBLEM, IN PLAIN ENGLISH:
//   - The Brickmap is the authoritative store: a sparse hash of 8^3 bricks,
//     mostly air, edited one voxel at a time. Great for storage, NOT a shape the
//     greedy mesher wants to sweep.
//   - The greedy mesher wants a small DENSE block it can scan linearly: a 34^3
//     "mesh slab" (a 32^3 chunk plus a 1-voxel apron shell copied from the
//     neighbours, so faces on the chunk border know if their neighbour is solid).
//
// This header is the glue between the two. It does three small jobs:
//
//   1. extract_mesh_slab() — read a chunk (plus its 1-voxel apron) OUT of the
//      brickmap into a fresh DenseGrid the mesher can chew.
//   2. apply_writes()      — push a batch of voxel writes (a mining carve, a
//      fill) back INTO the brickmap.
//   3. chunks_touched_by_voxel() / affected_chunks() — answer "which chunk MESHES
//      do I have to rebuild after these edits?". A voxel on a chunk border lives
//      in its own chunk AND shows up in the apron of the neighbour(s) across that
//      border, so editing it dirties up to 8 chunks (face / edge / corner).
//
// Pure C++17, namespace `mira`, NO engine headers — clang-testable in the
// headless harness (tests/standalone/test_brickmesh.cpp).

#pragma once

#include <cstdint>
#include <vector>
#include <unordered_set>

#include "Core/MiraVec.h"
#include "Core/ChunkCoords.h"
#include "Core/VoxelChunk.h"
#include "Core/Brickmap.h"
#include "Core/MiningCarve.h"   // struct VoxelWrite { Vec3i pos; int value; }

namespace mira {

// ---------------------------------------------------------------------------
// 1. extract_mesh_slab — sparse Brickmap -> dense 34^3 mesh slab.
// ---------------------------------------------------------------------------
// Build the apron'd DenseGrid the greedy mesher meshes for `chunk_coord`.
//
// THE SLAB CONVENTION (matches VoxelChunk.h / VoxelChunkActor.cpp): the slab is
// MESH_SLAB_SIDE (34) per side. Slab cell (lx,ly,lz), for each of lx/ly/lz in
// [0,34), maps to the world voxel:
//
//     world = chunk_origin_voxel(chunk_coord) + (lx - APRON, ly - APRON, lz - APRON)
//
// So the inner cube [APRON .. APRON+CHUNK) == [1..33) holds the chunk's own 32^3
// voxels, and the outer 1-voxel shell is the apron — read straight from whatever
// neighbour brick owns those voxels (absent bricks read as air, which is exactly
// what we want for an open border).
inline DenseGrid extract_mesh_slab(const Brickmap& bm, const Vec3i& chunk_coord) {
    DenseGrid slab = make_mesh_slab();
    const Vec3i origin = coords::chunk_origin_voxel(chunk_coord);

    for (int lz = 0; lz < MESH_SLAB_SIDE; ++lz) {
        for (int ly = 0; ly < MESH_SLAB_SIDE; ++ly) {
            for (int lx = 0; lx < MESH_SLAB_SIDE; ++lx) {
                // Slab cell -> world voxel (shift by -APRON so the shell reads
                // the neighbour voxel just outside the chunk).
                const Vec3i world{
                    origin.x + (lx - APRON),
                    origin.y + (ly - APRON),
                    origin.z + (lz - APRON),
                };
                slab.set_type (lx, ly, lz, bm.type_at(world));
                slab.set_water(lx, ly, lz, bm.water_at(world));
            }
        }
    }
    return slab;
}

// ---------------------------------------------------------------------------
// 2. apply_writes — push a batch of voxel writes back into the Brickmap.
// ---------------------------------------------------------------------------
// Each VoxelWrite is "set the voxel at `pos` to `value`". A mining carve emits
// AIR (0) writes (which clear solid voxels); a future "fill" verb emits non-air
// values. Either way it's one set_type per write — the brickmap handles brick
// allocation / garbage-collection internally.
//
// (Only the TYPE channel is written: VoxelWrite carries a single `value`, which
// is a material id. Water edits go through a separate path.)
inline void apply_writes(Brickmap& bm, const std::vector<VoxelWrite>& writes) {
    for (const VoxelWrite& w : writes) {
        bm.set_type(w.pos, static_cast<uint8_t>(w.value));
    }
}

// ---------------------------------------------------------------------------
// 3a. chunks_touched_by_voxel — which chunk MESHES depend on this voxel?
// ---------------------------------------------------------------------------
// Appends, to `out`, every chunk whose 34^3 mesh slab reads this voxel: the
// chunk that CONTAINS it, plus any neighbour chunk that holds it in its 1-voxel
// apron shell.
//
// Per axis the rule is: the containing chunk is always touched (offset 0). If the
// voxel sits on the chunk's LOW face for that axis (local coord == 0) it is also
// the apron of the chunk one step DOWN (offset -1). If it sits on the HIGH face
// (local coord == CHUNK-1) it is the apron of the chunk one step UP (offset +1).
// We take the Cartesian product of the per-axis offset sets, so a voxel deep
// inside is 1 chunk, on a face 2, on an edge 4, on a corner 8 — and every entry
// of one product is distinct (no dup within a single call).
inline void chunks_touched_by_voxel(const Vec3i& voxel,
                                    std::vector<Vec3i>& out) {
    using coords::CHUNK;
    using coords::floor_div;
    using coords::floor_mod;

    // The base chunk this voxel lives in.
    const Vec3i base{
        floor_div(voxel.x, CHUNK),
        floor_div(voxel.y, CHUNK),
        floor_div(voxel.z, CHUNK),
    };

    // Per-axis neighbour offsets: always {0}, plus -1 on the low face / +1 on the
    // high face. (At most {-1,0} or {0,+1}; never both, since CHUNK > 1.)
    auto axis_offsets = [](int32_t v, int (&buf)[2]) -> int {
        const int32_t m = floor_mod(v, CHUNK);
        buf[0] = 0;
        int n = 1;
        if (m == 0)          buf[n++] = -1; // on the low border -> neighbour below
        else if (m == CHUNK - 1) buf[n++] = 1;  // on the high border -> neighbour above
        return n;
    };

    int ox[2], oy[2], oz[2];
    const int nx = axis_offsets(voxel.x, ox);
    const int ny = axis_offsets(voxel.y, oy);
    const int nz = axis_offsets(voxel.z, oz);

    // Cartesian product over the three axes (1..8 chunks).
    for (int i = 0; i < nx; ++i) {
        for (int j = 0; j < ny; ++j) {
            for (int k = 0; k < nz; ++k) {
                out.push_back(Vec3i{
                    base.x + ox[i],
                    base.y + oy[j],
                    base.z + oz[k],
                });
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 3b. affected_chunks — the DEDUPED set of chunks a batch of writes dirties.
// ---------------------------------------------------------------------------
// Union chunks_touched_by_voxel over every write, de-duplicated (two writes in
// the same chunk, or sharing a border neighbour, must rebuild that chunk once).
// Returned as a vector; order is unspecified (it's a set).
inline std::vector<Vec3i> affected_chunks(const std::vector<VoxelWrite>& writes) {
    std::unordered_set<Vec3i> seen;
    std::vector<Vec3i> touched; // scratch, reused per write

    for (const VoxelWrite& w : writes) {
        touched.clear();
        chunks_touched_by_voxel(w.pos, touched);
        for (const Vec3i& c : touched) seen.insert(c);
    }

    return std::vector<Vec3i>(seen.begin(), seen.end());
}

} // namespace mira
