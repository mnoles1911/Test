// RegionMerge.h — combine several baked "crust TILE" meshes into ONE region mesh.
//
// WHAT THIS IS (plain English):
// The Nanite crust bakes the distant land in square TILES (see NaniteBakeTiling.h),
// one mesh per tile. At runtime each tile is placed by VoxelNaniteCrust::PlaceTile,
// which positions a tile's mesh in the world using the tile's own anchor
// (MinVoxelX, MinVoxelZ, BaseFineY) and a shared Stride. That's a lot of separate
// StaticMeshComponents. Sometimes we instead want to bake/stream a whole REGION (a
// block of tiles) as ONE mesh so the runtime places a single component.
//
// This file is the pure MATH that fuses those tile meshes into one region mesh,
// expressed in the REGION's anchor frame, so that when the runtime places the region
// mesh with the SAME PlaceTile transform (using the region anchor + same Stride),
// every tile's geometry lands in EXACTLY the world spot its own per-tile placement
// would have put it. No engine headers — pure C++17, clang-harness testable.
//
// THE TRANSFORM WE'RE MATCHING (from VoxelNaniteCrust::PlaceTile):
//   A tile's mesh verts are in COARSE-cell units (one cell = Stride fine voxels).
//   The component sits at relative voxel-space origin
//       Ox = MinVoxelX - APRON*Stride
//       Oy = (BaseFineY - VerticalBias) - APRON*Stride
//       Oz = MinVoxelZ - APRON*Stride
//   and is SCALED by Stride. A mesh vert (px,py,pz) [mesh axis order: X=vx, Y=vz,
//   Z=vy] therefore lands at world voxel coords:
//       wx = Ox + px*Stride
//       wy = Oy + py*Stride
//       wz = Oz + pz*Stride
//   (then *VoxelToUU with the UE X=vx, Y=vz, Z=vy swap — irrelevant to the merge,
//    because the swap and scale are applied uniformly to the whole region mesh.)
//
// THE MERGE OFFSET (derived by setting tile-world == region-world for a vert):
//   We want the merged vert v' (in the REGION mesh, placed at the region anchor with
//   the same Stride) to reach the SAME world voxel as the original vert v did under
//   the tile's anchor. The APRON*Stride and VerticalBias terms are IDENTICAL for both
//   placements (same Stride), so they cancel, leaving:
//       v'.px = v.px + dx,  dx = (tileMinVoxelX - regionMinVoxelX) / Stride
//       v'.py = v.py + dy,  dy = (tileBaseFineY  - regionBaseFineY ) / Stride
//       v'.pz = v.pz + dz,  dz = (tileMinVoxelZ - regionMinVoxelZ) / Stride
//   dx,dz are INTEGER multiples of coarse_side (tiles are tile-aligned, and the tile
//   span is a whole number of coarse cells). dy may be FRACTIONAL because each tile's
//   BaseFineY is "lowest ground - skirt" and varies per tile — so we keep it float.
//   Every other vertex field (normal, UV, AO, color, flow) is copied unchanged.
//
// Pure C++17, header-only, NO engine headers — compiles in the standalone harness.

#pragma once

#include <cstdint>
#include <vector>

#include "Core/MeshTypes.h"   // MeshBuffers / MeshSection / MeshVertex / FaceClass

namespace mira {

// One tile to fold into the region: its mesh, plus the tile's placement anchor
// (the SAME values PlaceTile reads from the bake manifest entry). `mesh` may be null
// or empty — such a tile contributes nothing.
struct RegionTileInput {
    const MeshBuffers* mesh = nullptr;
    int minVoxelX = 0;  // tile min-corner world voxel X (Entry.MinVoxelX)
    int minVoxelZ = 0;  // tile min-corner world voxel Z (Entry.MinVoxelZ)
    int baseFineY = 0;  // fine-voxel Y the tile's coarse row 0 sits at (Entry.BaseFineY)
};

// Fuse `tiles` into one region mesh expressed in the region anchor's frame.
//
//   tiles            — the per-tile meshes + their anchors.
//   regionMinVoxelX  — the REGION's min-corner world voxel X (the merged mesh's anchor).
//   regionMinVoxelZ  — the REGION's min-corner world voxel Z.
//   regionBaseFineY  — the REGION's coarse-row-0 fine-voxel Y (the merged mesh's anchor).
//   stride           — fine voxels per coarse cell. ALL tiles in a region share this.
//
// Each tile's verts are offset (see THE MERGE OFFSET above) into the region frame and
// appended into the matching FaceClass section; each tile's indices are appended with a
// running per-section vertex base added so they keep pointing at the right verts.
//
// A non-positive stride or empty tile list yields an empty MeshBuffers.
inline MeshBuffers merge_region_tiles(
    const std::vector<RegionTileInput>& tiles,
    int regionMinVoxelX, int regionMinVoxelZ, int regionBaseFineY,
    int stride)
{
    MeshBuffers out;
    if (stride <= 0) { return out; }

    const float invStride = 1.0f / static_cast<float>(stride);

    for (const RegionTileInput& tile : tiles) {
        if (!tile.mesh) { continue; }

        // Offset, in the MESH's voxel-unit (coarse-cell) frame, that re-anchors this
        // tile's verts to the region anchor. dx/dz are exact integers in practice
        // (tile-aligned), dy may be fractional — keep all three float.
        const float dx = static_cast<float>(tile.minVoxelX - regionMinVoxelX) * invStride;
        const float dy = static_cast<float>(tile.baseFineY  - regionBaseFineY ) * invStride;
        const float dz = static_cast<float>(tile.minVoxelZ - regionMinVoxelZ) * invStride;

        // Fold each FaceClass section into the same section of the region mesh.
        for (int s = 0; s < static_cast<int>(FaceClass::Count); ++s) {
            const MeshSection& src = tile.mesh->sections[s];
            if (src.vertices.empty()) { continue; }

            MeshSection& dst = out.sections[s];

            // The index base is "how many verts this section already holds" — every
            // index from this tile gets shifted by it so triangles still reference
            // this tile's own appended verts.
            const uint32_t base = static_cast<uint32_t>(dst.vertices.size());

            // Copy verts with the position offset applied; everything else verbatim.
            dst.vertices.reserve(dst.vertices.size() + src.vertices.size());
            for (const MeshVertex& v : src.vertices) {
                MeshVertex w = v;       // copy normal/UV/AO/color/flow unchanged
                w.px = v.px + dx;
                w.py = v.py + dy;
                w.pz = v.pz + dz;
                dst.vertices.push_back(w);
            }

            // Append the rebased indices.
            dst.indices.reserve(dst.indices.size() + src.indices.size());
            for (uint32_t idx : src.indices) {
                dst.indices.push_back(idx + base);
            }
        }
    }

    return out;
}

} // namespace mira
