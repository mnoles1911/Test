// WaterSurfaceMesher.h — the sloped fluid-surface mesher (header-only Core).
//
// WHAT THIS DOES (plain English):
//   The GreedyMesher draws all the SOLID blocks (stone, dirt, grass...). Water is
//   handled separately, here, because water is special: it is translucent, it does
//   not collide, and — the whole point of this file — its top surface is NOT flat.
//   A pond that is "full" near its source but only a shallow puddle at its edge
//   should look like one continuous SLOPED sheet of water, not a staircase of flat
//   square tiles at different heights. So this mesher reads the WATER channel of
//   the slab and builds sloped tops that JOIN smoothly between neighbouring cells.
//
//   It touches ONLY the `water` channel (the WaterByteCodec bytes). It never looks
//   at the solid/type channel — the GreedyMesher owns that. All geometry it emits
//   goes into out.section(FaceClass::Water).
//
// HOW WATER HEIGHT WORKS:
//   Each water cell carries a LEVEL 1..8 (WaterByteCodec::level_of). A cell's water
//   fills it to the fraction level/8 of its height — a level-8 cell is full (top at
//   y_local + 1.0), a level-2 puddle only reaches y_local + 0.25. We render water in
//   VOXEL UNITS: a cell at chunk-local (x,y,z) spans [x..x+1] x [y..y+1] x [z..z+1].
//
// THE SLOPED TOP (the heart of this — classic Minecraft-style fluid blend):
//   If we just drew each cell's top at its own flat level/8 height, neighbouring
//   cells of different level would step. Instead, each of the 4 TOP CORNERS of a
//   cell takes a height BLENDED from the water columns that meet at that corner.
//   For a given corner we look at the up-to-4 cells in the XZ plane that share it
//   (the cell itself and its diagonal/edge neighbours toward that corner). For each
//   such column that is water we contribute a height:
//       * normally its own level/8, BUT
//       * if the cell directly ABOVE that column is ALSO water, the column keeps
//         going up past this layer, so the surface there is at the TOP of this
//         layer -> contribute the full 1.0 instead.
//   We AVERAGE the contributions of the water columns among the up-to-4 (columns
//   that are not water contribute nothing and are not counted). That average, added
//   to y_local, is the corner's height. A corner that touches air on some sides
//   gets a lower average -> the surface slopes DOWN toward the air. A corner deep
//   inside a body (all 4 columns full, or water above) averages to 1.0 -> flat full
//   surface. This is what fuses adjacent cells into one smooth sheet.
//
// FACE EMISSION RULES:
//   * TOP (+Y): emitted only for a SURFACE cell — one whose +Y neighbour is NOT
//     water. (If water sits directly above, this cell is submerged and its top is
//     interior, so no top quad.) The top uses the 4 blended corner heights, so it
//     is a (possibly sloped) quad.
//   * SIDES (the 4 horizontal neighbours): a side quad is emitted on a boundary
//     only when that horizontal neighbour is NOT water (air, or a non-water cell).
//     Water-vs-water horizontal faces are culled (interior of the body). The side
//     rises from the cell bottom (y_local) up to the TWO corner heights on that
//     edge, so the side meets the sloped top exactly. Its normal points outward
//     toward the neighbour.
//   * NO bottom faces, NO collision (water is non-colliding).
//
// TODOs LEFT (documented, not bugs):
//   * Flow-direction UV scroll: the water byte carries a flow direction
//     (WaterByteCodec::dir_of), but MeshVertex has no flow channel yet, so we
//     cannot encode per-vertex scroll direction. UVs here are a plain per-cell unit
//     tile; wiring flow->UV-scroll waits on a MeshVertex flow field.
//   * Water-vs-solid side culling: right now a water side against SOLID terrain is
//     still emitted (we only cull water-vs-water). The water material is
//     translucent so this is visually acceptable for now; a later pass can read the
//     type channel and cull water faces buried in solid rock to save quads.
//
// COORDINATE NOTES (same convention as GreedyMesher):
//   * Slab indices run [0..33]; the meshed chunk is the inner [0..31] in CHUNK-LOCAL
//     coords, reached by adding +APRON (1) on every slab read. So chunk-local -1 ->
//     slab 0 (neighbour apron) and chunk-local 32 -> slab 33 (neighbour apron).
//   * We only EMIT geometry for inner cells [0..31]; we may READ neighbours at
//     -1..32 for level / above / side checks. Every read stays inside the 34^3 slab.
//   * Vertex positions are CHUNK-LOCAL voxel units (slab index - APRON), matching
//     the GreedyMesher so both meshes share one tile-local origin.
//
// Pure C++17, no engine headers — compiles in the standalone clang harness.

#pragma once

#include <cstdint>
#include "Core/VoxelChunk.h"      // DenseGrid, APRON
#include "Core/ChunkCoords.h"     // coords::CHUNK
#include "Core/MeshTypes.h"       // MeshBuffers, MeshVertex, FaceClass, FaceDir, FACE_NORMAL
#include "Core/WaterByteCodec.h"  // WaterByteCodec::is_water / level_of / MAX_LEVEL
#include "Core/VoxelColor.h"      // base_color, Rgb8

namespace mira {

namespace water_mesh_detail {

// The inner chunk edge we emit for (32). Reads may stray to -1..N via the apron.
constexpr int N = coords::CHUNK;

// Read the WATER byte at a CHUNK-LOCAL coord; the +APRON shift reaches the shell.
// Callers only pass coords in [-1..N], all of which land inside the 34^3 slab.
inline uint8_t water_local(const DenseGrid& slab, int lx, int ly, int lz) {
    return slab.water_at(lx + APRON, ly + APRON, lz + APRON);
}

inline bool is_water_local(const DenseGrid& slab, int lx, int ly, int lz) {
    return WaterByteCodec::is_water(water_local(slab, lx, ly, lz));
}

// The surface height CONTRIBUTION of one water column at chunk-local (x,y,z),
// expressed as a fraction of cell height in [0..1] (NOT yet offset by y).
//   * full 1.0 if the cell directly above is also water (column continues up,
//     so the surface here is at the top of THIS layer), else
//   * level/8 from this cell's own fill level.
// Caller guarantees (x,y,z) is itself a water cell before asking.
inline float column_height_frac(const DenseGrid& slab, int x, int y, int z) {
    if (is_water_local(slab, x, y + 1, z)) {
        return 1.0f; // water above -> this layer is brim-full at its top
    }
    const int lvl = WaterByteCodec::level_of(water_local(slab, x, y, z));
    return static_cast<float>(lvl) / static_cast<float>(WaterByteCodec::MAX_LEVEL);
}

// Blended height (in voxel units, already offset by y) of ONE top corner of the
// cell at (x,y,z). `sx`,`sz` are each -1 or +1 and pick which of the 4 corners:
//   (sx=-1,sz=-1) -> the (x,z) min corner ; (sx=+1,sz=+1) -> the (x+1,z+1) max corner.
// We gather the up-to-4 XZ columns meeting at that corner — (x,z), (x+sx,z),
// (x,z+sz), (x+sx,z+sz) — and average the height fractions of those that are
// water. Non-water columns contribute nothing and are not counted. If somehow no
// column is water (shouldn't happen, the centre cell always is) we fall back to
// the centre cell so we never divide by zero.
inline float corner_height(const DenseGrid& slab, int x, int y, int z, int sx, int sz) {
    const int xs[4] = { x,      x + sx, x,      x + sx };
    const int zs[4] = { z,      z,      z + sz, z + sz };

    float sum = 0.0f;
    int   count = 0;
    for (int i = 0; i < 4; ++i) {
        if (is_water_local(slab, xs[i], y, zs[i])) {
            sum += column_height_frac(slab, xs[i], y, zs[i]);
            ++count;
        }
    }
    if (count == 0) {
        // Defensive fallback: blend off the centre cell alone (it is water by
        // contract). Keeps the mesher total even if a caller ever slips.
        sum = column_height_frac(slab, x, y, z);
        count = 1;
    }
    return static_cast<float>(y) + sum / static_cast<float>(count);
}

// Push one water quad. Four corners are given DIRECTLY in chunk-local voxel units
// in parameter order 00,10,11,01 (the same order GreedyMesher uses). We tag each
// vertex with the face normal, a plain per-cell unit UV (00->(0,0), 11->(1,1)), and
// ao = 1.0. Winding: 00->10->11 / 00->11->01. The caller orders the corners so this
// is CCW from outside for the face it is emitting (see the call sites).
inline void emit_water_quad(MeshBuffers& out, const float* nrm,
                            const float p00[3], const float p10[3],
                            const float p11[3], const float p01[3]) {
    MeshSection& sec = out.section(FaceClass::Water);

    // One flat tint for the whole water surface — water has its own material, so
    // a sensible per-vertex albedo is the base water color (WATER_FULL). The water
    // shader can ignore or tint by this; it gives a sane fallback under the default
    // vertex-color material. No directional face_shade (water reads as one sheet).
    const Rgb8 wcol = base_color(mat::WATER_FULL);

    auto add = [&](const float p[3], float uu, float vv) -> uint32_t {
        MeshVertex mv;
        mv.px = p[0]; mv.py = p[1]; mv.pz = p[2];
        mv.nx = nrm[0]; mv.ny = nrm[1]; mv.nz = nrm[2];
        mv.u = uu; mv.v = vv;
        mv.ao = 1.0f; // water has no baked AO (translucent, lit by the water shader)
        mv.cr = wcol.r; mv.cg = wcol.g; mv.cb = wcol.b;
        const uint32_t idx = static_cast<uint32_t>(sec.vertices.size());
        sec.vertices.push_back(mv);
        return idx;
    };

    const uint32_t i00 = add(p00, 0.0f, 0.0f);
    const uint32_t i10 = add(p10, 1.0f, 0.0f);
    const uint32_t i11 = add(p11, 1.0f, 1.0f);
    const uint32_t i01 = add(p01, 0.0f, 1.0f);

    // Two triangles, CCW in parameter space (00->10->11, 00->11->01).
    sec.indices.push_back(i00); sec.indices.push_back(i10); sec.indices.push_back(i11);
    sec.indices.push_back(i00); sec.indices.push_back(i11); sec.indices.push_back(i01);
}

} // namespace water_mesh_detail

// ---------------------------------------------------------------------------
// THE ENTRY POINT. Read the slab's WATER channel; append sloped fluid surfaces
// (tops + exposed sides) to out.section(FaceClass::Water). Solids untouched.
// ---------------------------------------------------------------------------
inline void append_water_surface(const DenseGrid& slab, MeshBuffers& out) {
    using namespace water_mesh_detail;

    // Only emit for the INNER chunk cells [0..N). Neighbour reads may reach -1..N.
    for (int z = 0; z < N; ++z) {
        for (int y = 0; y < N; ++y) {
            for (int x = 0; x < N; ++x) {
                if (!is_water_local(slab, x, y, z)) continue;

                // The four blended TOP corner heights for this cell. Naming:
                //   h<minX/maxX><minZ/maxZ>. sx=-1 is the -X side, +1 the +X side.
                const float h00 = corner_height(slab, x, y, z, -1, -1); // (x,   z)
                const float h10 = corner_height(slab, x, y, z, +1, -1); // (x+1, z)
                const float h11 = corner_height(slab, x, y, z, +1, +1); // (x+1, z+1)
                const float h01 = corner_height(slab, x, y, z, -1, +1); // (x,   z+1)

                const float x0 = static_cast<float>(x), x1 = x0 + 1.0f;
                const float z0 = static_cast<float>(z), z1 = z0 + 1.0f;
                const float yb = static_cast<float>(y); // cell bottom (water units)

                // ---- TOP (+Y): only for a SURFACE cell (no water directly above) ----
                if (!is_water_local(slab, x, y + 1, z)) {
                    const float* n = FACE_NORMAL[FACE_POS_Y]; // (0,1,0)
                    // Corner order 00,10,11,01 over (x,z): looking DOWN the +Y normal
                    // from above, going (x0,z0)->(x1,z0)->(x1,z1)->(x0,z1) winds CCW.
                    const float p00[3] = { x0, h00, z0 };
                    const float p10[3] = { x1, h10, z0 };
                    const float p11[3] = { x1, h11, z1 };
                    const float p01[3] = { x0, h01, z1 };
                    emit_water_quad(out, n, p00, p10, p11, p01);
                }

                // ---- SIDES: one per horizontal neighbour that is NOT water ----
                // Each side rises from the cell bottom (yb) to the two top corner
                // heights on that edge, so it meets the sloped top exactly. Corners
                // are ordered 00,10,11,01 to wind CCW seen from OUTSIDE (from the
                // neighbour, looking back along the outward normal).

                // +X face (boundary at x1). Outward normal +X. Looking from +X back
                // toward -X, +Z is to the LEFT, so going bottom +Z -> bottom -Z ->
                // top -Z -> top +Z is CCW.
                if (!is_water_local(slab, x + 1, y, z)) {
                    const float* n = FACE_NORMAL[FACE_POS_X];
                    const float p00[3] = { x1, yb,  z1 };
                    const float p10[3] = { x1, yb,  z0 };
                    const float p11[3] = { x1, h10, z0 }; // top at (x1,z0) corner
                    const float p01[3] = { x1, h11, z1 }; // top at (x1,z1) corner
                    emit_water_quad(out, n, p00, p10, p11, p01);
                }

                // -X face (boundary at x0). Outward normal -X. Looking from -X back
                // toward +X, +Z is to the RIGHT, so bottom -Z -> bottom +Z -> top +Z
                // -> top -Z is CCW.
                if (!is_water_local(slab, x - 1, y, z)) {
                    const float* n = FACE_NORMAL[FACE_NEG_X];
                    const float p00[3] = { x0, yb,  z0 };
                    const float p10[3] = { x0, yb,  z1 };
                    const float p11[3] = { x0, h01, z1 }; // top at (x0,z1) corner
                    const float p01[3] = { x0, h00, z0 }; // top at (x0,z0) corner
                    emit_water_quad(out, n, p00, p10, p11, p01);
                }

                // +Z face (boundary at z1). Outward normal +Z. Looking from +Z back
                // toward -Z, +X is to the RIGHT, so bottom -X -> bottom +X -> top +X
                // -> top -X is CCW.
                if (!is_water_local(slab, x, y, z + 1)) {
                    const float* n = FACE_NORMAL[FACE_POS_Z];
                    const float p00[3] = { x0, yb,  z1 };
                    const float p10[3] = { x1, yb,  z1 };
                    const float p11[3] = { x1, h11, z1 }; // top at (x1,z1) corner
                    const float p01[3] = { x0, h01, z1 }; // top at (x0,z1) corner
                    emit_water_quad(out, n, p00, p10, p11, p01);
                }

                // -Z face (boundary at z0). Outward normal -Z. Looking from -Z back
                // toward +Z, +X is to the LEFT, so bottom +X -> bottom -X -> top -X
                // -> top +X is CCW.
                if (!is_water_local(slab, x, y, z - 1)) {
                    const float* n = FACE_NORMAL[FACE_NEG_Z];
                    const float p00[3] = { x1, yb,  z0 };
                    const float p10[3] = { x0, yb,  z0 };
                    const float p11[3] = { x0, h00, z0 }; // top at (x0,z0) corner
                    const float p01[3] = { x1, h10, z0 }; // top at (x1,z0) corner
                    emit_water_quad(out, n, p00, p10, p11, p01);
                }
            }
        }
    }
}

} // namespace mira
