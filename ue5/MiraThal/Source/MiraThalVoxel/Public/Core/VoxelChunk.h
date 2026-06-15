// VoxelChunk.h — dense voxel grids used as meshing input.
//
// The brickmap (M2) is the sparse authoritative store; but the greedy mesher
// wants a small DENSE grid it can sweep linearly. `DenseGrid` is that grid: a
// side^3 block holding the two channels (type + water). The mesher is handed an
// APRON'D slab — side = CHUNK+2 (34) — where the inner [1..32] cube is the chunk
// being meshed and the outer shell is a 1-voxel copy of the neighbouring voxels,
// so a face on the chunk border knows whether its neighbour is solid.
//
// `VoxelChunk` is the plain 32^3 case (a chunk with no apron), handy for tests
// and for the brickmap->chunk assembly step. Pure C++; X-fastest layout via
// coords::flatten so every reader/writer agrees on storage order.

#pragma once

#include <cstdint>
#include <vector>
#include <algorithm>
#include "Core/ChunkCoords.h"

namespace mira {

// A dense side^3 voxel grid with two 8-bit channels.
struct DenseGrid {
    int side = 0;
    std::vector<uint8_t> type;  // CHANNEL_TYPE: material id (0 = air)
    std::vector<uint8_t> water; // water byte (WaterByteCodec); 0 when no water

    DenseGrid() = default;
    explicit DenseGrid(int s)
        : side(s),
          type(static_cast<size_t>(s) * s * s, 0),
          water(static_cast<size_t>(s) * s * s, 0) {}

    int index(int x, int y, int z) const { return coords::flatten(x, y, z, side); }

    uint8_t type_at(int x, int y, int z) const { return type[index(x, y, z)]; }
    uint8_t water_at(int x, int y, int z) const { return water[index(x, y, z)]; }

    void set_type(int x, int y, int z, uint8_t v)  { type[index(x, y, z)] = v; }
    void set_water(int x, int y, int z, uint8_t v) { water[index(x, y, z)] = v; }

    void fill_type(uint8_t v)  { std::fill(type.begin(),  type.end(),  v); }
    void fill_water(uint8_t v) { std::fill(water.begin(), water.end(), v); }

    // Bounds check (used by mesher apron reads to stay safe at slab edges).
    bool in_bounds(int x, int y, int z) const {
        return x >= 0 && y >= 0 && z >= 0 && x < side && y < side && z < side;
    }
};

// The apron edge: a mesh slab is CHUNK + 2*APRON per side.
constexpr int APRON = 1;
constexpr int MESH_SLAB_SIDE = coords::CHUNK + 2 * APRON; // 34

// Construct an empty apron'd slab ready to be filled (inner = chunk, shell = apron).
inline DenseGrid make_mesh_slab() { return DenseGrid(MESH_SLAB_SIDE); }

// A plain chunk (no apron). Inner data only; the assembly step copies a chunk +
// its neighbour shell into a MESH_SLAB for the mesher.
using VoxelChunk = DenseGrid;
inline DenseGrid make_chunk() { return DenseGrid(coords::CHUNK); }

} // namespace mira
