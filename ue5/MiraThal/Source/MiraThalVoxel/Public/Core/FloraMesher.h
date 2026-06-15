// FloraMesher.h — decorative geometry builder for flora and surface-detail voxels.
//
// Called after (or alongside) the greedy mesher for the same chunk slab. Where
// the greedy mesher explicitly SKIPS ids 24..28 (is_passthrough -> FaceClass::Flora,
// no cube faces emitted), THIS mesher fills the Flora section with the correct
// billboard / ground-quad geometry for each decoration voxel.
//
// WHY SEPARATE (plain English): flora geometry is NOT a cube face — a grass blade
// is a pair of thin diagonal quads crossing through the voxel cell, not six axis-
// aligned faces. A pebble is a tiny flat oval near the ground. Forcing the greedy
// mesher to understand this would bloat its already-complex sweep logic. Instead,
// we scan the inner chunk in a dumb linear sweep, emit the small fixed-count
// geometry per id, and the UE upload glue treats it exactly like any other
// MeshSection (just with a flora atlas material + alpha-scissor / no-cull).
//
// DOUBLE-SIDED QUADS (plain English): the flora material uses alpha-scissor (the
// UE material does NOT cull back faces), so geometrically we DO need to emit the
// quad twice — once with each winding — so that BOTH triangle halves pass the
// depth pre-pass from any angle. Convention used here:
//   Each "visual quad" = 4 unique vertices + 6 indices (two CCW-wound triangles
//   when viewed from the front, THEN two more CCW-wound triangles from the back).
//   Total: 4 verts, 6 indices per one-sided quad.
//   Double-sided = 4 verts, 12 indices (same 4 verts, two winding sets).
//   A grass-blade CROSS = 2 quads, each double-sided = 8 verts, 24 indices.
// The MeshSection::quad_count() helper (indices.size()/6) therefore reports
//   cross  ->  4   (24/6)
//   ground quad ->  2   (12/6)   [double-sided ground quad for pebble/twig]
//
// HASH / JITTER (plain English): without any offset, every grass voxel would
// place its cross centred on the exact grid point and they would all look
// identical. We derive a deterministic per-cell hash from (x,y,z) — same inputs
// always produce the same outputs, so the world does not flicker between frames.
// From the hash we extract:
//   dx, dz  — horizontal centre offset, clipped to ±0.25 voxels so the quad
//              never pokes outside the cell's XZ footprint.
//   yaw     — rotation of the cross/quad about the vertical centre axis, in
//              radians, full 2π range, so pairs of quads fan out differently.
//
// PLACEHOLDER UV TILES (plain English): the greedy mesher's atlas (AtlasUV.h)
// owns the 1024px terrain atlas rows 0-15. Flora goes onto a SEPARATE flora
// atlas texture. For now we assign placeholder tile slots inside a notional
// 512px / 16px-tile (32-column) flora atlas — just enough to give each id a
// unique rect so the UE side can verify correct routing. The UE material
// blueprint wires the actual flora atlas PNG; these UV values are correct-for-
// the-atlas, just filled with stand-in column/row numbers. Document them here
// clearly so the UE wiring engineer knows which row to put each sprite on.
//
//  Flora atlas layout (placeholder):
//    column 0, row 0  -> id 24  GRASS_BLADE
//    column 1, row 0  -> id 25  FLOWER_RED
//    column 2, row 0  -> id 26  FLOWER_BLUE
//    column 0, row 1  -> id 27  PEBBLE
//    column 1, row 1  -> id 28  TWIG
//
// Pure C++17, no engine headers. Usable from the clang headless harness.

#pragma once

#include <cstdint>
#include <cmath>

#include "Core/VoxelChunk.h"    // DenseGrid, APRON, make_mesh_slab
#include "Core/MeshTypes.h"     // MeshBuffers, MeshSection, MeshVertex, FaceClass
#include "Core/MaterialIds.h"   // mat::is_passthrough, GRASS_BLADE_ID, etc.
#include "Core/ChunkCoords.h"   // coords::CHUNK

namespace mira {

// ---------------------------------------------------------------------------
// Flora atlas UV helpers (local to this file, no AtlasUV.h involvement).
// ---------------------------------------------------------------------------
namespace flora_atlas {

// The flora atlas is a separate texture from the terrain atlas. Placeholder
// layout: 32 columns × 32 rows of 16×16px sprites in a 512×512px sheet.
// These tile addresses are stand-ins — the real sprite sheet is authored on the
// UE side; the UV MATH here is correct for a 32-column atlas.
constexpr int FLORA_ATLAS_COLS = 32;

struct FloraUVRect { float u0, v0, u1, v1; };

// Convert a (col, row) tile address to a normalised UV rect.
constexpr FloraUVRect tile_uv(int col, int row) {
    const float s = 1.0f / static_cast<float>(FLORA_ATLAS_COLS);
    return { col * s, row * s, (col + 1) * s, (row + 1) * s };
}

// Per-id placeholder tile assignments. Keep in sync with the table in the file
// header comment so the UE wiring engineer knows where to put each sprite.
constexpr FloraUVRect uv_for_id(int type_id) {
    switch (type_id) {
        case mat::GRASS_BLADE_ID: return tile_uv(0, 0); // column 0, row 0
        case mat::FLOWER_RED_ID:  return tile_uv(1, 0); // column 1, row 0
        case mat::FLOWER_BLUE_ID: return tile_uv(2, 0); // column 2, row 0
        case mat::PEBBLE_ID:      return tile_uv(0, 1); // column 0, row 1
        case mat::TWIG_ID:        return tile_uv(1, 1); // column 1, row 1
        default:                  return tile_uv(0, 0); // fallback (shouldn't hit)
    }
}

} // namespace flora_atlas

// ---------------------------------------------------------------------------
// Deterministic per-cell hash (plain English)
//
// We want a function that mixes three integer inputs into one integer output
// such that:
//   1. Same inputs -> same output (deterministic, no random state).
//   2. Different inputs -> generally different outputs (no accidental clustering).
//   3. No external dependencies (pure arithmetic, no std::random, no UE RNG).
//
// We use the well-known "integer hash" idiom: multiply each coordinate by a
// different large prime, XOR them together, then apply two rounds of bit mixing
// (multiply by a near-golden-ratio constant, XOR with a right-shifted version
// of itself). This scrambles the bits thoroughly across the full 32-bit range
// so there is no visible pattern at distances of 1, 2, or even 8 voxels.
//
// IMPORTANT: the hash is computed from CHUNK-LOCAL coords [0..31].  Two voxels
// at different world positions but with the same local coords (different chunks)
// will get the same jitter — that is fine because the chunk-local offset is what
// we care about. If per-world uniqueness were needed we would pass the chunk
// origin too, but that adds complexity with no visual benefit at single-chunk
// scale.
// ---------------------------------------------------------------------------
inline uint32_t hash3(int x, int y, int z) {
    // Step 1: pack into one 32-bit value via prime multiples + XOR.
    //   Primes chosen to spread bits across the low, mid, and high halves.
    uint32_t h = static_cast<uint32_t>(x) * 2654435761u   // Knuth multiplicative hash prime
               ^ static_cast<uint32_t>(y) * 2246822519u   // second prime
               ^ static_cast<uint32_t>(z) * 3266489917u;  // third prime

    // Step 2: two rounds of finalisation mixing (finaliser from MurmurHash3).
    //   Each round: multiply by a near-golden constant, XOR with high bits shifted down.
    h ^= h >> 16;
    h *= 0x85ebca6bu;
    h ^= h >> 13;
    h *= 0xc2b2ae35u;
    h ^= h >> 16;

    return h;
}

// ---------------------------------------------------------------------------
// Geometry helpers — emit quads into the Flora MeshSection.
// ---------------------------------------------------------------------------
namespace flora_detail {

// Push one mesh vertex into the Flora section's vertex buffer and return its index.
inline uint32_t push_vert(MeshSection& sec,
                          float px, float py, float pz,
                          float nx, float ny, float nz,
                          float u,  float v)
{
    MeshVertex vtx;
    vtx.px = px; vtx.py = py; vtx.pz = pz;
    vtx.nx = nx; vtx.ny = ny; vtx.nz = nz;
    vtx.u  = u;  vtx.v  = v;
    vtx.ao = 1.0f; // flora is unoccluded (blades poke above terrain surface)
    const auto idx = static_cast<uint32_t>(sec.vertices.size());
    sec.vertices.push_back(vtx);
    return idx;
}

// Append a DOUBLE-SIDED quad to the Flora section.
//
// A "quad" here means a flat rectangle defined by four corners in winding order:
//   v0 = bottom-left, v1 = bottom-right, v2 = top-right, v3 = top-left
// (where "bottom/top/left/right" are relative to the quad's local plane).
//
// ONE-SIDED winding (CCW from the front = outward normal side):
//   tri A: v0, v1, v2
//   tri B: v0, v2, v3
//
// DOUBLE-SIDED: we add both windings so BOTH faces pass the depth / alpha test
// regardless of which side the camera is on. We reuse the SAME 4 vertices and
// just append the reverse-winding triangles as additional indices:
//   tri C (reverse): v2, v1, v0
//   tri D (reverse): v3, v2, v0
//
// Result: 4 vertices, 12 indices per double-sided quad.
// MeshSection::quad_count() = indices.size()/6, so this counts as 2 "quads".
//
// Normal stored in the vertex is the OUTWARD normal of the front face. Because
// the flora material uses a neutral outward shading, both sides get the same
// lighting approximation (alpha-scissor grass doesn't need per-side normals).
inline void emit_double_sided_quad(MeshSection& sec,
    float x0, float y0, float z0,   // corner 0 (bottom-left)
    float x1, float y1, float z1,   // corner 1 (bottom-right)
    float x2, float y2, float z2,   // corner 2 (top-right)
    float x3, float y3, float z3,   // corner 3 (top-left)
    float nx, float ny, float nz,   // outward normal (front face)
    const flora_atlas::FloraUVRect& uv)
{
    // Four unique vertices with UV corners mapped to the tile rect.
    const uint32_t i0 = push_vert(sec, x0, y0, z0, nx, ny, nz, uv.u0, uv.v1); // BL
    const uint32_t i1 = push_vert(sec, x1, y1, z1, nx, ny, nz, uv.u1, uv.v1); // BR
    const uint32_t i2 = push_vert(sec, x2, y2, z2, nx, ny, nz, uv.u1, uv.v0); // TR
    const uint32_t i3 = push_vert(sec, x3, y3, z3, nx, ny, nz, uv.u0, uv.v0); // TL

    // Front winding (CCW from front = toward the outward normal).
    sec.indices.push_back(i0); sec.indices.push_back(i1); sec.indices.push_back(i2);
    sec.indices.push_back(i0); sec.indices.push_back(i2); sec.indices.push_back(i3);

    // Back winding (CW from front = CCW from behind).
    sec.indices.push_back(i2); sec.indices.push_back(i1); sec.indices.push_back(i0);
    sec.indices.push_back(i3); sec.indices.push_back(i2); sec.indices.push_back(i0);
}

// Emit a BILLBOARD CROSS: two axis-aligned vertical quads crossing through the
// cell's vertical centre, rotated by `yaw` radians about the cell's Y axis.
//
// The cell occupies [cx, cx+1] x [cy, cy+1] x [cz, cz+1] in VOXEL UNITS.
// The cross centre (with jitter) is at (cx + 0.5 + dx, *, cz + 0.5 + dz).
// Each of the two quads spans the full voxel height (y .. y+1) and has a
// half-width of 0.5 voxel units, giving a total quad width of 1 voxel unit —
// exactly filling the cell.
//
// After yaw rotation, quad 0 spans the X direction and quad 1 spans the Z
// direction. The yaw mixes the two directions.
//
// Double-sided quads: 4 verts + 12 indices each. Total for a cross: 8 verts,
// 24 indices -> MeshSection::quad_count() = 24/6 = 4.
inline void emit_cross(MeshSection& sec,
    int cx, int cy, int cz,   // chunk-local cell origin (integer voxel coords)
    float dx, float dz,       // jitter: horizontal offset applied to the centre
    float yaw,                // rotation about the cell's Y axis (radians)
    const flora_atlas::FloraUVRect& uv)
{
    // Centre position with jitter applied. Y is the full voxel extent (cy..cy+1).
    const float cx_f   = static_cast<float>(cx);
    const float cy_bot = static_cast<float>(cy);
    const float cy_top = static_cast<float>(cy) + 1.0f;
    const float cz_f   = static_cast<float>(cz);

    // Jittered centre in XZ.
    const float mx = cx_f + 0.5f + dx;
    const float mz = cz_f + 0.5f + dz;

    // Half-extent of each quad in the quad's local plane direction.
    // 0.4 gives a cross that is 0.8 cells wide. Together with jitter of at most
    // ±0.1, the furthest corner sits exactly 0.5 from the cell's integer edge —
    // always inside [x, x+1] / [z, z+1] for every hash value.
    constexpr float HALF = 0.4f;

    const float cos_y = std::cos(yaw);
    const float sin_y = std::sin(yaw);

    // --- Quad 0: aligned with the (cos_y, 0, -sin_y) axis BEFORE rotation. ---
    // The unit tangent along quad 0 in local space is (1, 0, 0); after yaw rotation:
    //   local X -> (cos_y,  0, sin_y)
    //   local Z -> (-sin_y, 0, cos_y)
    // Quad 0 uses the X tangent (runs along what was the X axis).
    {
        const float tx = cos_y * HALF;
        const float tz = sin_y * HALF;
        // Normal is perpendicular to the quad in XZ: tangent cross +Y = (tz, 0, -tx)...
        // actually for a vertical quad the outward normal lies in XZ, 90° from the tangent.
        // Normal = (-sin_y, 0, cos_y) (the Z-direction tangent of the rotation).
        const float nx = -sin_y;
        const float nz =  cos_y;
        emit_double_sided_quad(sec,
            mx - tx, cy_bot, mz - tz,  // BL
            mx + tx, cy_bot, mz + tz,  // BR
            mx + tx, cy_top, mz + tz,  // TR
            mx - tx, cy_top, mz - tz,  // TL
            nx, 0.0f, nz,
            uv);
    }

    // --- Quad 1: perpendicular to quad 0 (the Z-axis quad after rotation). ---
    // Tangent in local space (0, 0, 1) -> after yaw rotation: (-sin_y, 0, cos_y).
    {
        const float tx = -sin_y * HALF;
        const float tz =  cos_y * HALF;
        // Normal: perpendicular to this tangent in XZ = (cos_y, 0, sin_y).
        const float nx = cos_y;
        const float nz = sin_y;
        emit_double_sided_quad(sec,
            mx - tx, cy_bot, mz - tz,  // BL
            mx + tx, cy_bot, mz + tz,  // BR
            mx + tx, cy_top, mz + tz,  // TR
            mx - tx, cy_top, mz - tz,  // TL
            nx, 0.0f, nz,
            uv);
    }
}

// Emit a GROUND QUAD for a pebble or twig: a small flat rectangle lying just
// above the cell floor, normal +Y.
//
// Pebble: roughly square, 0.6 × 0.6 voxels.
// Twig:   elongated, 0.8 × 0.3 voxels (longer in X before yaw rotation, so
//         the yaw spreads twigs in different directions visually).
//
// The quad is also double-sided (12 indices) so it shows from below-ground
// angles (e.g., camera in a cave looking up). quad_count() contribution = 2.
inline void emit_ground_quad(MeshSection& sec,
    int cx, int cy, int cz,
    float dx, float dz,
    float yaw,
    int type_id,
    const flora_atlas::FloraUVRect& uv)
{
    // Ground level: just barely above the cell floor so Z-fighting is avoided.
    const float ground_y = static_cast<float>(cy) + 0.02f;

    // Centre with jitter.
    const float mx = static_cast<float>(cx) + 0.5f + dx;
    const float mz = static_cast<float>(cz) + 0.5f + dz;

    // Half-extents in the quad's two local axes (before yaw).
    // Pebble: square-ish 0.6×0.6.  Twig: elongated 0.8×0.3.
    float half_a, half_b;
    if (type_id == mat::TWIG_ID) {
        half_a = 0.40f; // half of 0.8 — the long axis (local X before yaw)
        half_b = 0.15f; // half of 0.3 — the short axis (local Z before yaw)
    } else {
        // PEBBLE
        half_a = 0.30f; // half of 0.6
        half_b = 0.30f;
    }

    const float cos_y = std::cos(yaw);
    const float sin_y = std::sin(yaw);

    // Two orthogonal directions in the XZ plane after yaw rotation.
    // Local X-axis after yaw: (cos_y, 0, sin_y)
    // Local Z-axis after yaw: (-sin_y, 0, cos_y)
    const float ax = cos_y  * half_a;
    const float az = sin_y  * half_a;
    const float bx = -sin_y * half_b;
    const float bz =  cos_y * half_b;

    // Four corners of the flat quad:
    //   (-a - b), (-a + b), (+a + b), (+a - b)
    const float x0 = mx - ax - bx, z0 = mz - az - bz;
    const float x1 = mx + ax - bx, z1 = mz + az - bz;
    const float x2 = mx + ax + bx, z2 = mz + az + bz;
    const float x3 = mx - ax + bx, z3 = mz - az + bz;

    emit_double_sided_quad(sec,
        x0, ground_y, z0,
        x1, ground_y, z1,
        x2, ground_y, z2,
        x3, ground_y, z3,
        0.0f, 1.0f, 0.0f,   // normal +Y (flat on the ground)
        uv);
}

} // namespace flora_detail

// ---------------------------------------------------------------------------
// append_flora — the public entry point.
//
// Scans the inner chunk [0..31] of the apron'd slab (inner voxel at slab coords
// [APRON..APRON+31]) for any voxel whose type id is passthrough (24..28). For
// each such voxel, emits decorative geometry into out.section(FaceClass::Flora).
//
// The greedy mesher must have already been told NOT to emit cube faces for these
// ids (which it already does: is_passthrough -> FaceClass::Flora -> skipped by
// greedy cube-face logic). Call order relative to greedy_mesh() does not matter
// since they write to different sections and read the same slab.
//
// Jitter derivation (plain English):
//   We call hash3(x, y, z) with the chunk-local coordinates. We then pick bits
//   from the 32-bit result:
//     bits [0..9]  -> dx: mapped to [-0.1, +0.1] so the geometry stays inside
//                     the cell's XZ footprint.
//     bits [10..19]-> dz: same range.
//     bits [20..31]-> yaw: mapped to [0, 2π] for full rotation.
//
//   WHY ±0.1 (not ±0.25): The cross quads have half-extent 0.4 (width = 0.8
//   cells). The furthest corner of a rotated 0.4-half-extent quad sits at 0.4
//   from the jittered centre in the worst case. Centre jitter of ±0.1 means
//   the corner can reach 0.5 from the cell's integer edge — exactly on the
//   boundary, always inside [x, x+1] and [z, z+1].
//
//   Mapping 10 bits (range 0..1023) to [-0.1, +0.1]:
//     offset = (bits / 1023.0f - 0.5f) * 0.2f
//   Mapping 12 bits (range 0..4095) to [0, 2π]:
//     yaw = (bits / 4095.0f) * 2π
// ---------------------------------------------------------------------------
inline void append_flora(const DenseGrid& slab, MeshBuffers& out) {

    MeshSection& sec = out.section(FaceClass::Flora);
    constexpr float TWO_PI = 6.28318530718f;

    // Sweep only the inner chunk, not the apron shell. Chunk-local coords [0..31]
    // correspond to slab coords [APRON..APRON+31].
    for (int z = 0; z < coords::CHUNK; ++z) {
        for (int y = 0; y < coords::CHUNK; ++y) {
            for (int x = 0; x < coords::CHUNK; ++x) {

                const int sx = x + APRON;
                const int sy = y + APRON;
                const int sz = z + APRON;

                const int type_id = static_cast<int>(slab.type_at(sx, sy, sz));

                // Skip anything that is not a flora or surface-detail voxel.
                if (!mat::is_passthrough(type_id)) continue;

                // Compute the per-cell deterministic hash.
                const uint32_t h = hash3(x, y, z);

                // Extract jitter components from non-overlapping bit ranges.
                const uint32_t bits_dx  = (h >>  0) & 0x3FFu; // 10 bits -> 0..1023
                const uint32_t bits_dz  = (h >> 10) & 0x3FFu; // 10 bits -> 0..1023
                const uint32_t bits_yaw = (h >> 20) & 0xFFFu; // 12 bits -> 0..4095

                // Map bits_dx / bits_dz to [-0.1, +0.1] voxels.
                // Combined with the quad half-extent of 0.4, the outermost corner
                // reaches at most 0.4 + 0.1 = 0.5 from the cell's integer edge,
                // so geometry is always inside [x, x+1] and [z, z+1].
                const float dx = (static_cast<float>(bits_dx) / 1023.0f - 0.5f) * 0.2f;
                const float dz = (static_cast<float>(bits_dz) / 1023.0f - 0.5f) * 0.2f;

                // Map bits_yaw to [0, 2π].
                const float yaw = (static_cast<float>(bits_yaw) / 4095.0f) * TWO_PI;

                // Look up the flora-atlas UV tile for this id.
                const flora_atlas::FloraUVRect uv = flora_atlas::uv_for_id(type_id);

                if (mat::is_flora(type_id)) {
                    // Grass blades (24) and flowers (25, 26): billboard cross.
                    flora_detail::emit_cross(sec, x, y, z, dx, dz, yaw, uv);
                } else {
                    // Pebbles (27) and twigs (28): flat ground quad.
                    flora_detail::emit_ground_quad(sec, x, y, z, dx, dz, yaw, type_id, uv);
                }
            }
        }
    }
}

} // namespace mira
