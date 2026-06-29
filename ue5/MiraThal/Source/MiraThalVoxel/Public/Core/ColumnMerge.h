// ColumnMerge.h — merge a column's per-chunk-Y mesh rows into ONE buffer set.
//
// WHY (plain English): today every 32-voxel-tall chunk row in a column becomes its
// own render actor. A column ~3 rows tall = ~3 actors = ~3 draw calls, and with
// thousands of near columns that's the thing pinning the frame rate (draw-call bound,
// not streaming bound — see the perf CSV). This helper concatenates the rows of ONE
// column into a single MeshBuffers so the UE side can upload ONE actor for the whole
// column. Same triangles, same look — just far fewer actors/draw calls.
//
// PURE CORE (no engine headers) so the clang harness can prove the geometry is
// byte-correct before any UE wiring. The merge is a straight concatenation with a
// per-row vertical (world-up = core Y = py) offset; indices are rebased per section.
//
// INVARIANT the caller guarantees: every row in `rows` shares the SAME LOD (a column
// is meshed at a single LOD), so they share one PositionScale and the merged buffer
// uploads with that same scale. The per-row Y offset is therefore expressed in the
// SAME (possibly coarse) buffer units the rows already use: a row sitting `dRows`
// chunks above the base row is shifted up by dRows * (CHUNK / lod_scale) buffer units,
// which becomes exactly dRows * CHUNK voxels of world height after the shared scale.

#pragma once

#include <vector>
#include "Core/MeshTypes.h"
#include "Core/ChunkCoords.h" // coords::CHUNK

namespace mira {

// One row to merge: its chunk-Y index and the buffers the mesher produced for it.
struct ColumnMergeRow {
    int                chunk_y = 0;
    const MeshBuffers* buffers = nullptr;
};

// Merge `rows` into a single MeshBuffers, stacking each row above `base_chunk_y`.
//   base_chunk_y : the chunk-Y the merged actor will be PLACED at (its world origin).
//                  Rows below it get a negative offset, above it positive.
//   lod_scale    : 2^lod for this column (1 at LOD0). Must match the PositionScale the
//                  UE side will upload the merged buffer with. >= 1.
// Sections are concatenated per FaceClass; indices are rebased by each section's
// running vertex count so the combined index list stays valid.
inline MeshBuffers merge_column_buffers(const std::vector<ColumnMergeRow>& rows,
                                        int base_chunk_y, int lod_scale)
{
    MeshBuffers out;
    const int scale = (lod_scale < 1) ? 1 : lod_scale;
    // Per-row vertical step in BUFFER units (coarse-cell units at LOD>0).
    const float y_step = static_cast<float>(coords::CHUNK) / static_cast<float>(scale);

    for (const ColumnMergeRow& row : rows) {
        if (row.buffers == nullptr) { continue; }
        const float y_off = static_cast<float>(row.chunk_y - base_chunk_y) * y_step;

        for (int c = 0; c < static_cast<int>(FaceClass::Count); ++c) {
            const MeshSection& src = row.buffers->sections[c];
            if (src.indices.empty()) { continue; }
            MeshSection& dst = out.sections[c];

            // Rebase this row's indices by however many vertices the destination
            // section already holds, then copy the vertices with the Y offset applied.
            const uint32_t base_index = static_cast<uint32_t>(dst.vertices.size());
            dst.vertices.reserve(dst.vertices.size() + src.vertices.size());
            for (MeshVertex v : src.vertices) {
                v.py += y_off;            // stack the row up the world-up axis
                dst.vertices.push_back(v);
            }
            dst.indices.reserve(dst.indices.size() + src.indices.size());
            for (uint32_t idx : src.indices) {
                dst.indices.push_back(base_index + idx);
            }
        }
    }
    return out;
}

} // namespace mira
