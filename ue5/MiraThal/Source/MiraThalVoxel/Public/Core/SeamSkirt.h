// SeamSkirt.h — border skirts that hide LOD cracks between chunks.
//
// THE PROBLEM (plain English): two neighbouring chunks can be drawn at different
// levels of detail — a near chunk at full 10cm res, a far one downsampled. Where
// they meet, the coarse chunk's surface steps in bigger blocks, so its edge can
// sit a voxel or two LOWER than the fine chunk's edge. That mismatch leaves a thin
// CRACK you can see the sky (or the void) through.
//
// THE FIX: hang a thin vertical "skirt" of geometry straight down from each
// chunk's border, from the surface down by `depth` voxels. Normally the skirt is
// buried inside the neighbouring terrain and invisible; exactly at a LOD seam it
// fills the gap. This is the standard heightmap/clipmap skirt trick applied to our
// cube borders.
//
// This module builds skirt geometry from a 1-D surface profile along one chunk
// side (the height of the terrain column at each position along the border). The
// UE layer decides WHICH chunks/sides actually need skirts (only those touching a
// coarser neighbour) and supplies the profile; here we just turn a profile into
// quads. Pure C++17, `seams` selector asserts the skirt leaves no gap.

#pragma once

#include <cstdint>
#include <array>
#include "Core/MeshTypes.h"   // MeshBuffers, FaceDir, FACE_NORMAL, face_class_of
#include "Core/ChunkCoords.h" // coords::CHUNK
#include "Core/AtlasUV.h"     // atlas::uv_for

namespace mira {
namespace seam {

// The lowest Y a column's skirt reaches. A neighbour surface anywhere in
// [skirt_bottom, surface_top] is covered — so pick depth >= the worst LOD step.
constexpr int skirt_bottom(int surface_top, int depth) { return surface_top - depth; }

// Does a skirt of `depth` hanging from `surface_top` cover a neighbour whose
// surface sits at `neighbour_top`? (The crack we must hide is the band between the
// two surfaces.) Covered iff the skirt reaches at or below the neighbour.
constexpr bool covers_gap(int surface_top, int neighbour_top, int depth) {
    return skirt_bottom(surface_top, depth) <= neighbour_top;
}

// Append skirt quads for ONE chunk side into `out`.
//   side     : which vertical border — NEG_X / POS_X / NEG_Z / POS_Z. (Top/bottom
//              skirts aren't generated; vertical neighbours share our LOD.)
//   surface  : surface[k] = the Y just ABOVE the top solid voxel of the k-th
//              column along the border (k in [0,CHUNK)). 0 or less => empty column,
//              no skirt there.
//   depth    : how many voxels to drop (>= the largest LOD step you must cover).
//   id       : material id to texture the skirt with (usually the border terrain).
// Adjacent columns of equal height merge into one quad, so a flat border is a
// single skirt rather than 32 slivers.
inline void append_side_skirt(MeshBuffers& out, FaceDir side,
                              const int surface[coords::CHUNK], int depth, uint8_t id) {
    if (depth <= 0) return;

    // Pick the constant plane axis/value and the horizontal axis the border runs
    // along. (1 is always the vertical Y axis.)
    int plane_axis, plane_val, border_axis;
    switch (side) {
        case FACE_NEG_X: plane_axis = 0; plane_val = 0;            border_axis = 2; break; // along Z
        case FACE_POS_X: plane_axis = 0; plane_val = coords::CHUNK; border_axis = 2; break;
        case FACE_NEG_Z: plane_axis = 2; plane_val = 0;            border_axis = 0; break; // along X
        case FACE_POS_Z: plane_axis = 2; plane_val = coords::CHUNK; border_axis = 0; break;
        default: return; // top/bottom: no skirt
    }

    MeshSection& sec = out.section(face_class_of(id));
    const float* nrm = FACE_NORMAL[side];
    const atlas::UVRect uv = atlas::uv_for(id, side);

    // Param order bot0->bot1->top1->top0 is CCW about (border_hat x Y_hat). That
    // cross product equals -X for the X-borders and +Z for the Z-borders, so it
    // already faces outward for NEG_X and POS_Z; the other two need a winding flip.
    const bool flip_wind = (side == FACE_POS_X || side == FACE_NEG_Z);

    auto make_corner = [&](int bcoord, int y) -> std::array<float, 3> {
        std::array<float, 3> p{0, 0, 0};
        p[plane_axis]  = static_cast<float>(plane_val);
        p[border_axis] = static_cast<float>(bcoord);
        p[1]           = static_cast<float>(y);
        return p;
    };
    auto add = [&](const std::array<float, 3>& p, float uu, float vv) -> uint32_t {
        MeshVertex mv;
        mv.px = p[0]; mv.py = p[1]; mv.pz = p[2];
        mv.nx = nrm[0]; mv.ny = nrm[1]; mv.nz = nrm[2];
        mv.u = uu; mv.v = vv;
        mv.ao = 1.0f; // skirts are buried fill; flat-lit is fine.
        const uint32_t idx = static_cast<uint32_t>(sec.vertices.size());
        sec.vertices.push_back(mv);
        return idx;
    };
    auto tri = [&](uint32_t a, uint32_t b, uint32_t c) {
        sec.indices.push_back(a);
        if (!flip_wind) { sec.indices.push_back(b); sec.indices.push_back(c); }
        else            { sec.indices.push_back(c); sec.indices.push_back(b); }
    };

    int k = 0;
    while (k < coords::CHUNK) {
        const int top = surface[k];
        if (top <= 0) { ++k; continue; } // empty column

        int run = 1;
        while (k + run < coords::CHUNK && surface[k + run] == top) ++run;

        const int b0 = k, b1 = k + run;
        const int bot = skirt_bottom(top, depth);

        const uint32_t i_b0 = add(make_corner(b0, bot), uv.u0, uv.v0);
        const uint32_t i_b1 = add(make_corner(b1, bot), uv.u1, uv.v0);
        const uint32_t i_t1 = add(make_corner(b1, top), uv.u1, uv.v1);
        const uint32_t i_t0 = add(make_corner(b0, top), uv.u0, uv.v1);

        tri(i_b0, i_b1, i_t1);
        tri(i_b0, i_t1, i_t0);

        k += run;
    }
}

} // namespace seam
} // namespace mira
