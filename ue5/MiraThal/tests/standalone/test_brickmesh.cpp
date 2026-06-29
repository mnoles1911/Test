// test_brickmesh.cpp — parity harness for Core/BrickmapMeshing.h.
//   cd tests/standalone && ./build.sh brickmesh
//
// Asserts the CONTRACT of the Brickmap <-> mesher bridge (not pixels):
//   * extract_mesh_slab reads voxels out of the sparse store into the right slab
//     cells, including a neighbour voxel that lands in THIS chunk's apron shell.
//   * chunks_touched_by_voxel returns 1 / 2 / 4 / 8 chunks for an interior /
//     face / edge / corner voxel.
//   * apply_writes carving AIR over solid voxels clears them.
//   * affected_chunks de-duplicates the union across a border-spanning batch.
//
// Prints "[brickmesh] PASS" / "[brickmesh] FAIL"; returns 0 on success, 1 on any
// failure (matches the other tests/standalone harnesses).

#include <cstdio>
#include <algorithm>
#include <vector>

#include "Core/BrickmapMeshing.h"
#include "Core/Brickmap.h"
#include "Core/VoxelChunk.h"
#include "Core/ChunkCoords.h"
#include "Core/MaterialIds.h"
#include "Core/MiningCarve.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;

// Does `out` contain chunk coord c?
static bool contains(const std::vector<Vec3i>& v, const Vec3i& c) {
    return std::find(v.begin(), v.end(), c) != v.end();
}

int main() {
    // ---------------------------------------------------------------------
    // 1. extract_mesh_slab: voxels read back at the right slab cells, and a
    //    neighbour voxel appears in THIS chunk's apron.
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        const Vec3i chunk{0, 0, 0};
        const Vec3i origin = coords::chunk_origin_voxel(chunk); // (0,0,0)

        // (a) An interior voxel of chunk (0,0,0): world (5,6,7) -> slab cell
        //     (5+APRON, 6+APRON, 7+APRON).
        bm.set_type({origin.x + 5, origin.y + 6, origin.z + 7}, mat::STONE);

        // (b) A voxel at the chunk's high-X face: world (31,0,0).
        bm.set_type({origin.x + 31, origin.y + 0, origin.z + 0}, mat::DIRT);

        // (c) A neighbour voxel one step in -X beyond the chunk: world (-1,0,0).
        //     It belongs to chunk (-1,0,0) but lands in chunk(0,0,0)'s apron at
        //     slab cell (APRON-1, APRON, APRON) = (0,1,1).
        bm.set_type({origin.x - 1, origin.y + 0, origin.z + 0}, mat::GRASS);

        DenseGrid slab = extract_mesh_slab(bm, chunk);

        CHECK(slab.side == MESH_SLAB_SIDE, "slab is 34^3");
        CHECK(slab.type_at(5 + APRON, 6 + APRON, 7 + APRON) == mat::STONE,
              "interior voxel read at (lx,ly,lz)=(local+APRON)");
        CHECK(slab.type_at(31 + APRON, 0 + APRON, 0 + APRON) == mat::DIRT,
              "high-face voxel read at local+APRON");
        CHECK(slab.type_at(APRON - 1, APRON, APRON) == mat::GRASS,
              "neighbour voxel at world(-1,0,0) shows up in this chunk's -X apron");

        // An untouched slab cell is air.
        CHECK(slab.type_at(20, 20, 20) == mat::AIR, "untouched slab cell reads air");

        // Water channel travels too.
        bm.set_water({origin.x + 2, origin.y + 2, origin.z + 2}, 99);
        DenseGrid slab2 = extract_mesh_slab(bm, chunk);
        CHECK(slab2.water_at(2 + APRON, 2 + APRON, 2 + APRON) == 99,
              "water channel extracted into the slab");
    }

    // ---------------------------------------------------------------------
    // 1b. extract_mesh_slab for a NON-origin chunk uses the right world origin.
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        const Vec3i chunk{1, -2, 3};
        const Vec3i origin = coords::chunk_origin_voxel(chunk); // (32,-64,96)
        bm.set_type({origin.x + 10, origin.y + 11, origin.z + 12}, mat::STONE);

        DenseGrid slab = extract_mesh_slab(bm, chunk);
        CHECK(slab.type_at(10 + APRON, 11 + APRON, 12 + APRON) == mat::STONE,
              "non-origin chunk: voxel read at the right slab cell");
    }

    // ---------------------------------------------------------------------
    // 2. chunks_touched_by_voxel: interior=1, face=2, edge=4, corner=8.
    // ---------------------------------------------------------------------
    {
        // Interior voxel of chunk (0,0,0): local (16,16,16) -> 1 chunk.
        std::vector<Vec3i> out;
        chunks_touched_by_voxel({16, 16, 16}, out);
        CHECK(out.size() == 1, "deep-interior voxel touches exactly 1 chunk");
        CHECK(contains(out, Vec3i{0, 0, 0}), "...the containing chunk");
    }
    {
        // Face voxel: one local coord == CHUNK-1 (high X), others interior.
        // world (31,16,16) -> chunk(0,0,0) + its +X neighbour chunk(1,0,0).
        std::vector<Vec3i> out;
        chunks_touched_by_voxel({31, 16, 16}, out);
        CHECK(out.size() == 2, "high-X face voxel touches 2 chunks");
        CHECK(contains(out, Vec3i{0, 0, 0}), "face: containing chunk");
        CHECK(contains(out, Vec3i{1, 0, 0}), "face: +X neighbour chunk");
    }
    {
        // Face voxel on the LOW border: local 0 -> the -axis neighbour.
        // world (0,16,16) -> chunk(0,0,0) + chunk(-1,0,0).
        std::vector<Vec3i> out;
        chunks_touched_by_voxel({0, 16, 16}, out);
        CHECK(out.size() == 2, "low-X face voxel touches 2 chunks");
        CHECK(contains(out, Vec3i{-1, 0, 0}), "low face: -X neighbour chunk");
    }
    {
        // Edge voxel: two local coords at a border. world (31,31,16) ->
        // chunks (0,0,0),(1,0,0),(0,1,0),(1,1,0) = 4.
        std::vector<Vec3i> out;
        chunks_touched_by_voxel({31, 31, 16}, out);
        CHECK(out.size() == 4, "edge voxel (two borders) touches 4 chunks");
        CHECK(contains(out, Vec3i{1, 1, 0}), "edge: the +X+Y diagonal chunk");
    }
    {
        // Corner voxel: all three at a border. world (31,31,31) -> the 8 chunks
        // of the 2x2x2 block (0..1, 0..1, 0..1).
        std::vector<Vec3i> out;
        chunks_touched_by_voxel({31, 31, 31}, out);
        CHECK(out.size() == 8, "corner voxel (three borders) touches 8 chunks");
        CHECK(contains(out, Vec3i{1, 1, 1}), "corner: the far diagonal chunk");
        CHECK(contains(out, Vec3i{0, 0, 0}), "corner: the containing chunk");
    }

    // ---------------------------------------------------------------------
    // 3. apply_writes: carving AIR over solid voxels clears them.
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        bm.set_type({10, 10, 10}, mat::STONE);
        bm.set_type({11, 10, 10}, mat::STONE);
        bm.set_type({12, 10, 10}, mat::STONE);
        CHECK(bm.type_at({10, 10, 10}) == mat::STONE, "precondition: voxel is solid");

        std::vector<VoxelWrite> writes = {
            VoxelWrite{{10, 10, 10}, 0},
            VoxelWrite{{11, 10, 10}, 0},
            VoxelWrite{{12, 10, 10}, 0},
        };
        apply_writes(bm, writes);

        CHECK(bm.type_at({10, 10, 10}) == mat::AIR, "carve cleared voxel 10");
        CHECK(bm.type_at({11, 10, 10}) == mat::AIR, "carve cleared voxel 11");
        CHECK(bm.type_at({12, 10, 10}) == mat::AIR, "carve cleared voxel 12");

        // And a non-air write fills (supports the future "fill" verb).
        apply_writes(bm, {VoxelWrite{{10, 10, 10}, mat::DIRT}});
        CHECK(bm.type_at({10, 10, 10}) == mat::DIRT, "non-air write fills the voxel");
    }

    // ---------------------------------------------------------------------
    // 4. affected_chunks dedups a batch spanning a chunk boundary.
    // ---------------------------------------------------------------------
    {
        // Two interior writes in the SAME chunk -> one chunk only.
        std::vector<VoxelWrite> same = {
            VoxelWrite{{4, 4, 4}, 0},
            VoxelWrite{{20, 20, 20}, 0},
        };
        std::vector<Vec3i> a = affected_chunks(same);
        CHECK(a.size() == 1, "two writes in one chunk -> 1 affected chunk");
        CHECK(contains(a, Vec3i{0, 0, 0}), "...chunk (0,0,0)");

        // A batch straddling the X border at x=31/x=32: voxel (31,16,16) dirties
        // chunks {0,0,0},{1,0,0}; voxel (32,16,16) is interior to chunk {1,0,0}.
        // The union, deduped, is exactly {(0,0,0),(1,0,0)} -> 2.
        std::vector<VoxelWrite> span = {
            VoxelWrite{{31, 16, 16}, 0},
            VoxelWrite{{32, 16, 16}, 0},
        };
        std::vector<Vec3i> b = affected_chunks(span);
        CHECK(b.size() == 2, "border-straddling batch dedups to 2 chunks");
        CHECK(contains(b, Vec3i{0, 0, 0}), "span: chunk (0,0,0)");
        CHECK(contains(b, Vec3i{1, 0, 0}), "span: chunk (1,0,0)");

        // Empty batch -> no chunks.
        std::vector<Vec3i> none = affected_chunks({});
        CHECK(none.empty(), "empty write batch -> 0 affected chunks");
    }

    std::printf("[brickmesh] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
