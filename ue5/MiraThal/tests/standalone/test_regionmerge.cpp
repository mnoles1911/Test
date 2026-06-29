// test_regionmerge.cpp — headless harness for Core/RegionMerge.h.
//   cd tests/standalone && ./build.sh regionmerge
//
// Proves merge_region_tiles fuses several baked crust-TILE meshes into ONE region
// mesh that, when placed at the REGION anchor with the shared Stride, lands every
// tile's geometry in EXACTLY the same world spot its own per-tile placement would.
//
// CRITICAL — this is NOT a self-consistency test. We define a GROUND-TRUTH placement
// function world_of() that independently replicates VoxelNaniteCrust::PlaceTile's
// transform (the relative origin Min - APRON*Stride / BaseFineY - bias - APRON*Stride,
// then *Stride). We then assert that for a merged vertex placed at the REGION anchor,
// world_of(merged) == world_of(original) at the TILE anchor — i.e. the merge preserves
// world position. Plus: counts add up, indices stay in range, empty + single-tile.

#include <cstdio>
#include <cmath>

#include "Core/RegionMerge.h"

// APRON: PlaceTile uses mira::APRON; the standalone harness pulls it from VoxelChunk.h
// (same header NaniteBakeTiling.h uses). We only need the integer value.
#include "Core/VoxelChunk.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { \
    ++g_checks; \
    if (!(cond)) { \
        ++g_fails; \
        std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__); \
    } \
} while (0)

using namespace mira;

// ---------------------------------------------------------------------------
// GROUND TRUTH: replicate VoxelNaniteCrust::PlaceTile's voxel-space world transform.
//
// A vertex (px,py,pz) of a mesh anchored at (minVoxelX, minVoxelZ, baseFineY) with the
// given stride lands at world VOXEL coords:
//   wx = (minVoxelX - APRON*stride) + px*stride
//   wy = (baseFineY - VBIAS - APRON*stride) + py*stride
//   wz = (minVoxelZ - APRON*stride) + pz*stride
// We return these as a small struct (we don't apply the UE X/Y/Z swap or *VoxelToUU,
// since those are applied uniformly to the whole region mesh and don't affect whether
// two placements agree). VBIAS (VerticalBias) is shared too, so any constant works; we
// pick a non-zero value to make sure it cancels.
// ---------------------------------------------------------------------------
static const int VBIAS = 3; // VerticalBiasVoxels — shared by every placement, must cancel

struct World { double x, y, z; };

static World world_of(float px, float py, float pz,
                      int minVoxelX, int minVoxelZ, int baseFineY, int stride) {
    const double A  = static_cast<double>(APRON) * stride;
    const double Ox = static_cast<double>(minVoxelX) - A;
    const double Oy = static_cast<double>(baseFineY - VBIAS) - A;
    const double Oz = static_cast<double>(minVoxelZ) - A;
    World w;
    w.x = Ox + static_cast<double>(px) * stride;
    w.y = Oy + static_cast<double>(py) * stride;
    w.z = Oz + static_cast<double>(pz) * stride;
    return w;
}

static bool world_eq(const World& a, const World& b) {
    return std::fabs(a.x - b.x) < 1e-3 &&
           std::fabs(a.y - b.y) < 1e-3 &&
           std::fabs(a.z - b.z) < 1e-3;
}

// Build a small section with `nQuads` distinct quads in class `c`. Vertices get varied
// px/py/pz (and a recognizable normal/color/flow) so we can verify per-field copy and
// catch any axis mix-up. seed offsets the values so different tiles differ.
static MeshSection make_section(FaceClass c, int nQuads, float seed) {
    MeshSection s;
    s.cls = c;
    for (int q = 0; q < nQuads; ++q) {
        const uint32_t base = static_cast<uint32_t>(s.vertices.size());
        for (int i = 0; i < 4; ++i) {
            MeshVertex v;
            v.px = seed + q * 1.0f + i * 0.25f;
            v.py = seed * 0.5f + q * 0.5f + i * 0.1f; // fractional to exercise float py
            v.pz = seed + q * 2.0f + i * 0.5f;
            v.nx = 0; v.ny = 1; v.nz = 0;
            v.u = 0.3f; v.v = 0.7f; v.ao = 0.8f;
            v.cr = 10; v.cg = 20; v.cb = 30;
            v.flow_x = 0.5f; v.flow_z = -0.5f;
            s.vertices.push_back(v);
        }
        s.indices.push_back(base + 0); s.indices.push_back(base + 1); s.indices.push_back(base + 2);
        s.indices.push_back(base + 0); s.indices.push_back(base + 2); s.indices.push_back(base + 3);
    }
    return s;
}

int main() {
    std::printf("test_regionmerge\n");

    const int stride = 8; // fine voxels per coarse cell; shared across tiles
    const int coarse_side = 16; // tile span / stride; tiles are aligned to this in coarse cells
    const int tileSpanVoxels = coarse_side * stride; // 128 voxels

    // Region anchor (the merged mesh's placement anchor).
    const int regMinX = -tileSpanVoxels; // region starts a tile to the left of origin
    const int regMinZ = -tileSpanVoxels;
    const int regBaseY = 40;

    // -------------------------------------------------------------------------
    // Case 1: GROUND-TRUTH world-position preservation across several tiles/verts.
    //   Three tiles at different aligned XZ offsets and DIFFERENT (fractional-capable)
    //   BaseFineY. Merge, then for every tile + vert assert
    //   world_of(merged @ region anchor) == world_of(original @ tile anchor).
    // -------------------------------------------------------------------------
    {
        // Tile anchors: tile-aligned in XZ (integer multiples of tileSpanVoxels from the
        // region corner), but BaseFineY varies and need NOT be stride-aligned -> the
        // per-tile dy is fractional in coarse units. That's the key thing to preserve.
        MeshBuffers m0, m1, m2;
        m0.section(FaceClass::Opaque) = make_section(FaceClass::Opaque, 2, 0.0f);
        m0.section(FaceClass::Water)  = make_section(FaceClass::Water,  1, 5.0f);
        m1.section(FaceClass::Opaque) = make_section(FaceClass::Opaque, 3, 1.0f);
        m1.section(FaceClass::Cutout) = make_section(FaceClass::Cutout, 1, 2.0f);
        m2.section(FaceClass::Opaque) = make_section(FaceClass::Opaque, 1, 7.0f);
        m2.section(FaceClass::Flora)  = make_section(FaceClass::Flora,  2, 9.0f);

        std::vector<RegionTileInput> tiles = {
            // dx=0,  dz=0,    dy = (37-40)/8 = -0.375  (fractional!)
            { &m0, regMinX,                    regMinZ,                    37 },
            // dx=16, dz=0,    dy = (44-40)/8 =  0.5
            { &m1, regMinX + tileSpanVoxels,   regMinZ,                    44 },
            // dx=16, dz=16,   dy = (41-40)/8 =  0.125
            { &m2, regMinX + tileSpanVoxels,   regMinZ + tileSpanVoxels,   41 },
        };

        MeshBuffers merged = merge_region_tiles(tiles, regMinX, regMinZ, regBaseY, stride);

        // Walk each tile/section/vert and verify the world position is preserved. We
        // track a running per-section cursor into the merged verts (tiles append in
        // order, sections fold independently — exactly how the merge runs).
        int cursor[static_cast<int>(FaceClass::Count)] = {0, 0, 0, 0};
        bool allWorldEq = true;
        for (const RegionTileInput& t : tiles) {
            for (int s = 0; s < static_cast<int>(FaceClass::Count); ++s) {
                const MeshSection& src = t.mesh->sections[s];
                const MeshSection& dst = merged.sections[s];
                for (size_t i = 0; i < src.vertices.size(); ++i) {
                    const MeshVertex& ov = src.vertices[i];
                    const MeshVertex& mv = dst.vertices[cursor[s] + i];

                    World wOrig = world_of(ov.px, ov.py, ov.pz,
                                           t.minVoxelX, t.minVoxelZ, t.baseFineY, stride);
                    World wMerged = world_of(mv.px, mv.py, mv.pz,
                                             regMinX, regMinZ, regBaseY, stride);
                    if (!world_eq(wOrig, wMerged)) { allWorldEq = false; }

                    // Non-position fields must be copied verbatim.
                    if (ov.nx != mv.nx || ov.ny != mv.ny || ov.nz != mv.nz ||
                        ov.u != mv.u || ov.v != mv.v || ov.ao != mv.ao ||
                        ov.cr != mv.cr || ov.cg != mv.cg || ov.cb != mv.cb ||
                        ov.flow_x != mv.flow_x || ov.flow_z != mv.flow_z) {
                        allWorldEq = false;
                    }
                }
                cursor[s] += static_cast<int>(src.vertices.size());
            }
        }
        CHECK(allWorldEq, "every merged vert reaches the same world voxel as its original (+ fields copied)");

        // Vertex + index counts add up per section.
        CHECK(merged.section(FaceClass::Opaque).vertices.size() == (2 + 3 + 1) * 4u, "opaque verts = sum of tiles");
        CHECK(merged.section(FaceClass::Opaque).indices.size()  == (2 + 3 + 1) * 6u, "opaque indices = sum of tiles");
        CHECK(merged.section(FaceClass::Water).vertices.size()  == 1u * 4u, "water verts from m0 only");
        CHECK(merged.section(FaceClass::Cutout).vertices.size() == 1u * 4u, "cutout verts from m1 only");
        CHECK(merged.section(FaceClass::Flora).vertices.size()  == 2u * 4u, "flora verts from m2 only");
        CHECK(merged.total_vertices() == ((2+3+1) + 1 + 1 + 2) * 4, "total verts add up across classes");

        // Indices stay in range AND are correctly rebased (the second tile's first quad
        // must reference verts at base 8, not 0).
        bool inRange = true;
        for (int s = 0; s < static_cast<int>(FaceClass::Count); ++s) {
            const MeshSection& sec = merged.sections[s];
            for (uint32_t idx : sec.indices) {
                if (idx >= sec.vertices.size()) { inRange = false; }
            }
        }
        CHECK(inRange, "all merged indices < their section vertex count");
        // m1 has 3 opaque quads starting at vert base 8 (m0 contributed 2 quads = 8 verts).
        CHECK(merged.section(FaceClass::Opaque).indices[12] == 8u, "second tile's opaque indices rebased by 8");
    }

    // -------------------------------------------------------------------------
    // Case 2: SINGLE tile placed AT the region anchor -> identity (no offset).
    // -------------------------------------------------------------------------
    {
        MeshBuffers m;
        m.section(FaceClass::Opaque) = make_section(FaceClass::Opaque, 2, 3.0f);
        std::vector<RegionTileInput> tiles = { { &m, regMinX, regMinZ, regBaseY } };
        MeshBuffers merged = merge_region_tiles(tiles, regMinX, regMinZ, regBaseY, stride);

        bool identity = true;
        const MeshSection& src = m.section(FaceClass::Opaque);
        const MeshSection& dst = merged.section(FaceClass::Opaque);
        for (size_t i = 0; i < src.vertices.size(); ++i) {
            if (src.vertices[i].px != dst.vertices[i].px ||
                src.vertices[i].py != dst.vertices[i].py ||
                src.vertices[i].pz != dst.vertices[i].pz) { identity = false; }
        }
        CHECK(identity, "single tile at region anchor is identity (zero offset)");
        CHECK(dst.indices == src.indices, "single-tile indices unchanged");
    }

    // -------------------------------------------------------------------------
    // Case 3: empty input -> empty mesh; and null/empty tiles contribute nothing.
    // -------------------------------------------------------------------------
    {
        std::vector<RegionTileInput> none;
        MeshBuffers empty = merge_region_tiles(none, regMinX, regMinZ, regBaseY, stride);
        CHECK(empty.total_vertices() == 0, "empty input -> zero vertices");
        CHECK(empty.total_quads() == 0, "empty input -> zero quads");

        MeshBuffers good;
        good.section(FaceClass::Opaque) = make_section(FaceClass::Opaque, 1, 0.0f);
        MeshBuffers emptyBuf; // no sections populated
        std::vector<RegionTileInput> tiles = {
            { nullptr, regMinX, regMinZ, regBaseY },     // null mesh
            { &emptyBuf, regMinX, regMinZ, regBaseY },   // empty mesh
            { &good, regMinX, regMinZ, regBaseY },       // the only real one
        };
        MeshBuffers merged = merge_region_tiles(tiles, regMinX, regMinZ, regBaseY, stride);
        CHECK(merged.total_vertices() == 4, "null + empty tiles add nothing; one real quad survives");
    }

    // -------------------------------------------------------------------------
    // Case 4: stride <= 0 is rejected (empty mesh, no divide-by-zero).
    // -------------------------------------------------------------------------
    {
        MeshBuffers m;
        m.section(FaceClass::Opaque) = make_section(FaceClass::Opaque, 1, 0.0f);
        std::vector<RegionTileInput> tiles = { { &m, regMinX, regMinZ, regBaseY } };
        MeshBuffers merged = merge_region_tiles(tiles, regMinX, regMinZ, regBaseY, /*stride=*/0);
        CHECK(merged.total_vertices() == 0, "stride<=0 -> empty mesh (guarded)");
    }

    if (g_fails == 0) std::printf("  OK (%d checks)\n", g_checks);
    else              std::printf("  %d/%d FAILED\n", g_fails, g_checks);
    return g_fails == 0 ? 0 : 1;
}
