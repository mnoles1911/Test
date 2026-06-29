// test_columnmerge.cpp — headless harness for Core/ColumnMerge.h.
//   cd tests/standalone && ./build.sh columnmerge
//
// Proves merge_column_buffers concatenates a column's per-chunk-Y mesh rows into a
// single buffer set correctly BEFORE any UE wiring:
//   - vertices of every row land in the matching FaceClass section
//   - each row's vertices are shifted up the world-up axis (py) by
//     (chunk_y - base_chunk_y) * CHUNK / lod_scale buffer units
//   - indices are rebased per section so the combined index list stays valid
//     (every index < that section's vertex count, triangles preserved)
//   - empty rows / empty sections contribute nothing
//   - LOD>0 (lod_scale>1) uses the coarse per-row step

#include <cstdio>

#include "Core/ColumnMerge.h"
#include "Core/ChunkCoords.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { \
    ++g_checks; \
    if (!(cond)) { \
        ++g_fails; \
        std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__); \
    } \
} while (0)

using namespace mira;

// Build a one-quad section in the given class: 4 verts (py = local height `h`), 6 indices.
static MeshSection make_quad(FaceClass c, float h) {
    MeshSection s;
    s.cls = c;
    for (int i = 0; i < 4; ++i) {
        MeshVertex v;
        v.px = static_cast<float>(i); // distinct so we can spot offset on py only
        v.py = h;
        v.pz = 0.0f;
        s.vertices.push_back(v);
    }
    // two triangles 0-1-2, 0-2-3
    s.indices = {0, 1, 2, 0, 2, 3};
    return s;
}

int main() {
    std::printf("test_columnmerge\n");

    // --- Case 1: two rows, one Opaque quad each, LOD0 (scale 1) ---------------
    {
        MeshBuffers row0, row2;
        row0.section(FaceClass::Opaque) = make_quad(FaceClass::Opaque, 0.0f);
        row2.section(FaceClass::Opaque) = make_quad(FaceClass::Opaque, 5.0f);

        std::vector<ColumnMergeRow> rows = {
            { 0, &row0 },
            { 2, &row2 },
        };
        MeshBuffers m = merge_column_buffers(rows, /*base_chunk_y=*/0, /*lod_scale=*/1);

        const MeshSection& op = m.section(FaceClass::Opaque);
        CHECK(op.vertices.size() == 8, "merged opaque has 8 verts (4+4)");
        CHECK(op.indices.size() == 12, "merged opaque has 12 indices (6+6)");

        // row0 verts unchanged (base row, offset 0): py == 0
        CHECK(op.vertices[0].py == 0.0f, "row0 vert py unchanged");
        // row2 sits 2 chunks above base at scale 1 -> +2*32 = +64 on the ORIGINAL local py(5)
        CHECK(op.vertices[4].py == 5.0f + 64.0f, "row2 vert py offset by 2*CHUNK");
        // px untouched (offset is Y only)
        CHECK(op.vertices[4].px == 0.0f && op.vertices[5].px == 1.0f, "row2 px untouched");

        // indices rebased: second quad references verts 4..7, not 0..3
        CHECK(op.indices[6] == 4 && op.indices[7] == 5 && op.indices[8] == 6, "row2 indices rebased +4");
        CHECK(op.indices[9] == 4 && op.indices[10] == 6 && op.indices[11] == 7, "row2 second tri rebased");

        // every index in range
        bool in_range = true;
        for (uint32_t i : op.indices) { if (i >= op.vertices.size()) in_range = false; }
        CHECK(in_range, "all merged indices < vertex count");
    }

    // --- Case 2: different FaceClasses stay in their own sections -------------
    {
        MeshBuffers row0, row1;
        row0.section(FaceClass::Opaque) = make_quad(FaceClass::Opaque, 0.0f);
        row1.section(FaceClass::Flora)  = make_quad(FaceClass::Flora, 1.0f);

        std::vector<ColumnMergeRow> rows = { { 0, &row0 }, { 1, &row1 } };
        MeshBuffers m = merge_column_buffers(rows, 0, 1);

        CHECK(m.section(FaceClass::Opaque).vertices.size() == 4, "opaque only from row0");
        CHECK(m.section(FaceClass::Flora).vertices.size() == 4, "flora only from row1");
        CHECK(m.section(FaceClass::Water).vertices.empty(), "water section empty");
        // flora row1 offset +1*CHUNK on its local py(1)
        CHECK(m.section(FaceClass::Flora).vertices[0].py == 1.0f + 32.0f, "flora row1 offset by CHUNK");
    }

    // --- Case 3: base row in the MIDDLE -> negative offset for rows below ------
    {
        MeshBuffers rNeg, rBase;
        rNeg.section(FaceClass::Opaque)  = make_quad(FaceClass::Opaque, 0.0f);
        rBase.section(FaceClass::Opaque) = make_quad(FaceClass::Opaque, 0.0f);
        std::vector<ColumnMergeRow> rows = { { -1, &rNeg }, { 0, &rBase } };
        MeshBuffers m = merge_column_buffers(rows, /*base_chunk_y=*/0, 1);
        // row -1 sits one chunk BELOW base -> -32
        CHECK(m.section(FaceClass::Opaque).vertices[0].py == -32.0f, "row below base offset -CHUNK");
        CHECK(m.section(FaceClass::Opaque).vertices[4].py == 0.0f, "base row unchanged");
    }

    // --- Case 4: LOD>0 uses the COARSE per-row step (CHUNK/scale) --------------
    {
        MeshBuffers row0, row1;
        row0.section(FaceClass::Opaque) = make_quad(FaceClass::Opaque, 0.0f);
        row1.section(FaceClass::Opaque) = make_quad(FaceClass::Opaque, 0.0f);
        std::vector<ColumnMergeRow> rows = { { 0, &row0 }, { 1, &row1 } };
        MeshBuffers m = merge_column_buffers(rows, 0, /*lod_scale=*/2); // LOD1
        // at scale 2 the per-row step is CHUNK/2 = 16 buffer units (×2 on upload = 32 voxels)
        CHECK(m.section(FaceClass::Opaque).vertices[4].py == 16.0f, "LOD1 per-row step = CHUNK/scale");
    }

    // --- Case 5: null / empty rows contribute nothing ------------------------
    {
        MeshBuffers row0;
        row0.section(FaceClass::Opaque) = make_quad(FaceClass::Opaque, 0.0f);
        MeshBuffers emptyRow; // no sections populated
        std::vector<ColumnMergeRow> rows = { { 0, &row0 }, { 1, nullptr }, { 2, &emptyRow } };
        MeshBuffers m = merge_column_buffers(rows, 0, 1);
        CHECK(m.section(FaceClass::Opaque).vertices.size() == 4, "null + empty rows add nothing");
    }

    if (g_fails == 0) std::printf("  OK (%d checks)\n", g_checks);
    else              std::printf("  %d/%d FAILED\n", g_fails, g_checks);
    return g_fails == 0 ? 0 : 1;
}
