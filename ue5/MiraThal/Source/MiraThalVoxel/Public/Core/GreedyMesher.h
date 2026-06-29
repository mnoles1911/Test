// GreedyMesher.h — the cubic greedy mesher for opaque + cutout terrain.
//
// WHAT THIS DOES (plain English):
// A chunk is 32x32x32 little cubes. The dumb way to draw it is six square faces
// per cube — 32^3 * 6 quads, almost all of them hidden inside the rock. The
// greedy mesher does two cheap-but-huge wins instead:
//
//   1. CULLING — a face is only drawn if the neighbouring voxel doesn't hide it.
//      A stone block buried in stone shows zero faces; only the surface skin of
//      the world becomes geometry.
//
//   2. GREEDY MERGING — once we know which faces are visible, neighbouring faces
//      that look identical (same material, same direction) get stitched into one
//      big rectangle instead of many little squares. A flat grass field that
//      would be 1024 separate top-faces collapses to a handful of large quads.
//      A fully solid 32^3 chunk surrounded by air becomes just SIX quads — one
//      32x32 rectangle per side. That is the signature "this mesher works"
//      result.
//
// ALGORITHM PROVENANCE: this is the classic Mikola Lysenko "0fps" greedy mesher
// (sweep each of the 3 axes, build a 2D "mask" of visible faces for each slice,
// then rectangle-merge the mask). We deliberately chose this over the faster
// binary/bitmask variant (cgerikj/binary-greedy-meshing) because the bitmask
// version is tangled with a packed 8-byte-per-quad vertex format and 64-wide
// SIMD-ish bit tricks; getting CORRECTNESS + real greedy merging first matters
// more than the ~100us speed win. Swapping in the binary backend later is an
// isolated, test-guarded change (it would produce the identical quad set).
//
// INPUT: an apron'd DenseGrid slab (side == MESH_SLAB_SIDE == 34). The inner
// cube — local indices [1..32] on each axis — is the chunk we mesh. The outer
// 1-voxel shell (index 0 and 33) is a copy of the neighbouring chunks' voxels,
// so a face sitting on the chunk border can ask "is my neighbour solid?" and get
// the right answer instead of wrongly drawing a wall mid-world.
//
// OUTPUT: a MeshBuffers — positions in VOXEL UNITS, chunk-local (a voxel at slab
// index (sx,sy,sz) lives at chunk-local (sx-1, sy-1, sz-1)). Faces land in the
// section for their own id's FaceClass: solid terrain in Opaque, leaves in
// Cutout. Water and flora/detail are SKIPPED here — they have their own meshers.
//
// Pure C++17, no engine headers — compiles in the standalone clang harness.

#pragma once

#include "Core/VoxelChunk.h" // DenseGrid, MESH_SLAB_SIDE, APRON
#include "Core/MeshTypes.h"  // MeshBuffers, FaceClass, FaceDir, FACE_NORMAL

namespace mira {

// Greedy-mesh one apron'd chunk slab into per-class triangle buffers.
//
// `slab.side` is expected to be MESH_SLAB_SIDE (34): inner [1..32] is the chunk,
// the shell is the neighbour apron used purely for border-face visibility. The
// returned MeshBuffers holds the minimal merged quad set (2 triangles each) with
// outward-facing winding, per-face atlas UVs, and ao == 1 (M0).
MeshBuffers greedy_mesh(const DenseGrid& slab);

} // namespace mira
