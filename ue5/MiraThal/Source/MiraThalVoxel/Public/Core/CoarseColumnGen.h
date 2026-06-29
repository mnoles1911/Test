// CoarseColumnGen.h — engine-agnostic column-fill MATH for "coarse far-generation".
//
// WHAT THIS IS (plain English):
// When the streaming system needs the voxels for one 32-wide chunk-column, it
// used to ALWAYS generate them at full 10 cm resolution — every voxel sampled
// from the noise/EXR + banding + cliff + flora — and then, for far-away chunks,
// THROW MOST OF IT AWAY by downsampling (LodDownsample.h) before meshing. That
// full-res generation is the worker-thread loading bottleneck.
//
// "Coarse far-generation" fixes that: for a DISTANT column that will only ever be
// rendered at LOD L (each rendered cube = a 2^L block of fine voxels), we can
// generate the column DIRECTLY at that coarse resolution — sampling the
// expensive heightmap/biome/cliff/flora logic once per coarse cell instead of
// once per fine voxel — and still land on EXACTLY the same voxels you'd get by
// generating full-res and then downsampling. That ~S^2 fewer expensive samples
// (S = 2^L) is the whole win.
//
// THE CORRECTNESS TARGET is LodDownsample.h's "solid survives" reduction. Coarse-gen
// matches it EXACTLY on the load-bearing channels (silhouette + water), which is what
// prevents cracks/holes/pop at distance:
//   * SOLID SILHOUETTE — EXACT. A 2^L block is solid iff ANY fine voxel in it is
//     solid, so the coarse surface rises to the HIGHEST fine surface in the footprint
//     (max ground), quantized UP to the top fine voxel of that block
//     (quantize_surface_y). The dig floor reaches the DEEPEST fine column's floor
//     (min over the footprint's plus-shaped ±1 probe, matching the fine path). Result:
//     downsample(coarse_fill) and downsample(fine_fill) have IDENTICAL solidity.
//   * WATER — EXACT. Water is filled per fine column from that column's own ground+1
//     to sea level, exactly as the fine path, so the water silhouette matches after
//     downsample (which keeps the max level).
//   * FLORA — none. Passthrough ids 24-28 never survive downsample, so coarse-gen
//     emits no flora when gen_lod > 0 (emitting it would mismatch).
//   * MATERIAL TYPE — approximate, by design. Banding uses ONE representative
//     resolve_column for the whole footprint (the expensive biome/cliff/flora work we
//     collapse by ~S^2), not each fine column's own surface. So a SOLID coarse cell
//     can carry a different terrain id than the fine majority deep underground or
//     across a material-patch boundary. This is invisible at LOD distance (the cell is
//     solid either way) and is the deliberate cost/quality trade of coarse far-gen.
//     The harness locks the EXACT channels (solidity + water) and bounds the material
//     drift (it shrinks to zero as L grows). The feature is flag-gated OFF by default.
//
// This header is PURE C++17, NO engine headers (same rule as LodDownsample.h):
// it is clang-testable in the headless harness. It takes a const reference to a
// mira::HeightmapGenerator (the Core generator) and writes a flat list of voxel
// writes — the Unreal adapter (VoxelWorld.cpp) copies those into its brickmap.
//
// gen_lod == 0 is BIT-IDENTICAL to the legacy fine fill loop (full-res; same
// cliff-aware dig floor, same material_at stack, same water fill, same flora
// emit). With the coarse-gen feature flag off, every call is gen_lod 0, so the
// behaviour is byte-for-byte unchanged.

#pragma once

#include <cstdint>
#include <climits>
#include <vector>

#include "Core/HeightmapGenerator.h"  // HeightmapGenerator, ColumnInfo, mat::AIR
#include "Core/ChunkCoords.h"         // coords::CHUNK, coords::floor_div, chunk_origin_voxel, Vec3i
#include "Core/WaterByteCodec.h"      // WaterByteCodec::SOURCE_BYTE
#include "Core/MaterialIds.h"         // mat::AIR

namespace mira {
namespace coarsegen {

// One voxel write produced by the fill: a type OR a water byte at (x,y,z).
// (water == false -> set the TYPE channel to `value`; water == true -> set the
// WATER channel to `value`.) Mirrors FColumnGenResult::FWrite field-for-field so
// the Unreal adapter is a trivial copy.
struct ColWrite {
    int     x, y, z;
    uint8_t value;
    bool    water;
};

// ---------------------------------------------------------------------------
// quantize_surface_y — the TOP fine voxel-Y of the 2^L block that contains the
// surface voxel `ground_y`, given block stride S (= 1 << L).
//
//   = floor_div(ground_y, S) * S + (S - 1)
//
// WHY (plain English): downsample treats a coarse cell as solid if ANY of its S
// fine voxels is solid. The fine column is solid from the bottom up THROUGH
// ground_y. So the coarse cell that holds ground_y is solid, and that cell spans
// fine-Y [floor_div(ground_y,S)*S .. +S-1]. To reproduce "solid survives" we
// must fill the fine column solid all the way to the TOP of that block — i.e. to
// this quantized Y — otherwise a coarse-generated column would be one block
// SHORTER than the downsample of a fine-generated one and the two would mismatch.
//
// At S == 1 (gen_lod 0) this is just ground_y (floor_div(g,1)*1 + 0 == g), which
// keeps the full-res path identical.
// ---------------------------------------------------------------------------
inline int quantize_surface_y(int ground_y, int S) {
    if (S <= 1) return ground_y;
    return coords::floor_div(ground_y, S) * S + (S - 1);
}

// ---------------------------------------------------------------------------
// fill_column — generate ONE 32-wide chunk-column's voxels (terrain + water +
// flora) into `out`, recording the vertical voxel span in [y_lo, y_hi].
//
//   ccx, ccz           — the chunk-column's XZ chunk coords.
//   gen_lod            — 0 = full-res (legacy); L>0 = coarse (stride S = 1<<L).
//   gen                — the Core terrain generator (heightmap/biome/cliff/flora).
//   depth_below_chunks — how many chunks of solid rock to fill below the surface
//                        (the dig-able depth); matches FGenParams::ChunkDepthBelow.
//   out                — flat write list (appended to; not cleared).
//   y_lo, y_hi         — OUT: the filled voxel-Y span (pre-floor_div), exactly as
//                        the legacy loop computed (YBottom .. ground_y+1, and up
//                        to sea level when the column is underwater).
//
// gen_lod == 0 reproduces the legacy fine loop voxel-for-voxel. gen_lod > 0
// collapses the per-fine-voxel resolve_column / compute_ground_y sampling to once
// per S x S footprint, landing on the same voxels a downsample of the fine fill
// would produce.
// ---------------------------------------------------------------------------
inline void fill_column(int ccx, int ccz, int gen_lod, const HeightmapGenerator& gen,
                        int depth_below_chunks, std::vector<ColWrite>& out,
                        int& y_lo, int& y_hi) {
    const Vec3i chunk_origin = coords::chunk_origin_voxel(Vec3i(ccx, 0, ccz));
    const int depth_voxels = depth_below_chunks * coords::CHUNK;
    const int sea_level = gen.sea_level_voxels;

    int filled_min_y = INT_MAX;
    int filled_max_y = INT_MIN;

    // -----------------------------------------------------------------------
    // FULL-RES PATH (gen_lod == 0). This is the legacy GenerateColumnWritesPure
    // inner loop, moved here verbatim so sync + async + (flag-off) coarse all
    // share ONE code path. Any change here changes both — keep it identical.
    // -----------------------------------------------------------------------
    if (gen_lod <= 0) {
        for (int lx = 0; lx < coords::CHUNK; ++lx)
        for (int lz = 0; lz < coords::CHUNK; ++lz) {
            const int wx = chunk_origin.x + lx;
            const int wz = chunk_origin.z + lz;
            const ColumnInfo col = gen.resolve_column(wx, wz);

            // Cliff-aware dig floor: drop to depth_voxels below the LOWEST of the
            // 4 side-neighbour surfaces so a cliff column is a continuous solid
            // wall, never a floating shelf.
            int min_nbr_ground = col.ground_y;
            if (gen.compute_ground_y(wx - 1, wz) < min_nbr_ground) min_nbr_ground = gen.compute_ground_y(wx - 1, wz);
            if (gen.compute_ground_y(wx + 1, wz) < min_nbr_ground) min_nbr_ground = gen.compute_ground_y(wx + 1, wz);
            if (gen.compute_ground_y(wx, wz - 1) < min_nbr_ground) min_nbr_ground = gen.compute_ground_y(wx, wz - 1);
            if (gen.compute_ground_y(wx, wz + 1) < min_nbr_ground) min_nbr_ground = gen.compute_ground_y(wx, wz + 1);

            const int y_bottom       = min_nbr_ground - depth_voxels;
            const int y_bottom_apron = y_bottom - coords::CHUNK;
            for (int wy = y_bottom_apron; wy <= col.ground_y; ++wy) {
                const int id = gen.material_at(wx, wy, wz, col);
                if (id != mat::AIR) {
                    out.push_back({ wx, wy, wz, static_cast<uint8_t>(id), false });
                }
            }
            if (y_bottom < filled_min_y) filled_min_y = y_bottom;
            if (col.ground_y + 1 > filled_max_y) filled_max_y = col.ground_y + 1;

            if (col.below_sea) {
                for (int wy = col.ground_y + 1; wy <= sea_level; ++wy) {
                    out.push_back({ wx, wy, wz,
                        static_cast<uint8_t>(WaterByteCodec::SOURCE_BYTE), true });
                }
                if (sea_level > filled_max_y) filled_max_y = sea_level;
            }

            if (col.flora_id != 0) {
                out.push_back({ wx, col.ground_y + 1, wz,
                    static_cast<uint8_t>(col.flora_id), false });
            }
        }

        if (filled_max_y < filled_min_y) { filled_min_y = filled_max_y = 0; }
        y_lo = filled_min_y;
        y_hi = filled_max_y;
        return;
    }

    // -----------------------------------------------------------------------
    // COARSE PATH (gen_lod == L > 0). S = 1<<L fine voxels per coarse cell/axis.
    // S divides 32 for L <= 5, so the 32-wide chunk tiles cleanly into S x S
    // coarse footprints. We sample the expensive generator ONCE per footprint
    // (not S^2 times) and fill the footprint to match what a downsample of the
    // fine fill would yield.
    // -----------------------------------------------------------------------
    const int S = 1 << gen_lod;

    for (int cx = 0; cx < coords::CHUNK; cx += S)
    for (int cz = 0; cz < coords::CHUNK; cz += S) {
        // The coarse cell's fine footprint is [wx0 .. wx0+S) x [wz0 .. wz0+S).
        const int wx0 = chunk_origin.x + cx;
        const int wz0 = chunk_origin.z + cz;
        const int wx1 = wx0 + S - 1;        // far corner (inclusive)
        const int wz1 = wz0 + S - 1;
        const int wxc = wx0 + S / 2;        // representative (cell centre)
        const int wzc = wz0 + S / 2;

        // GROUND = MAX surface over the WHOLE footprint (the highest fine column in
        // the block). "Solid survives" means the highest surface wins, so the coarse
        // column must rise to that max. We sample every fine (x,z) in the footprint —
        // that's S^2 calls to compute_ground_y, which (for an EXR bilinear or a noise
        // lookup) is the CHEAP part; the EXPENSIVE per-column work (resolve_column's
        // biome weights + cliff probe + flora hashing) is what we collapse to ONE call.
        // Sampling every column (not just corners) is what makes the coarse SOLID
        // silhouette match the fine downsample EXACTLY (no holes, no overhang).
        int max_ground = INT_MIN;
        for (int fx = wx0; fx <= wx1; ++fx)
        for (int fz = wz0; fz <= wz1; ++fz) {
            const int g = gen.compute_ground_y(fx, fz);
            if (g > max_ground) max_ground = g;
        }
        const int ground_q = quantize_surface_y(max_ground, S);

        // Cliff dig-floor: the fine path drops each fine column to depth_voxels below
        // the LOWEST of its 4 ±1 neighbours, then "solid survives" downsample makes the
        // coarse cell reach the DEEPEST fine floor in the footprint. To reproduce the
        // fine YLo + bottom solidity EXACTLY we take the min compute_ground_y over the
        // SAME sample set the fine path uses: every footprint column plus its 4 axis
        // neighbours (the PLUS shape — NOT the diagonal corners, which the fine path
        // never probes), minus depth_voxels.
        int min_nbr_ground = INT_MAX;
        for (int fx = wx0; fx <= wx1; ++fx)
        for (int fz = wz0; fz <= wz1; ++fz) {
            const int g  = gen.compute_ground_y(fx, fz);        if (g  < min_nbr_ground) min_nbr_ground = g;
            const int gl = gen.compute_ground_y(fx - 1, fz);    if (gl < min_nbr_ground) min_nbr_ground = gl;
            const int gr = gen.compute_ground_y(fx + 1, fz);    if (gr < min_nbr_ground) min_nbr_ground = gr;
            const int gd = gen.compute_ground_y(fx, fz - 1);    if (gd < min_nbr_ground) min_nbr_ground = gd;
            const int gu = gen.compute_ground_y(fx, fz + 1);    if (gu < min_nbr_ground) min_nbr_ground = gu;
        }
        const int y_bottom       = min_nbr_ground - depth_voxels;
        const int y_bottom_apron = y_bottom - coords::CHUNK;

        // ONE resolve_column for the whole footprint (the representative, at the cell
        // centre) — this is the expensive call we collapse by ~S^2. We override its
        // ground_y to the QUANTIZED surface so material_at bands off the coarse surface
        // (top/dirt/stone measured down from ground_q). NOTE: because banding uses the
        // single representative (not each fine column's own surface/biome/cliff), the
        // coarse MATERIAL is the representative's banding rather than the fine majority;
        // the SOLID SILHOUETTE and water are exact, material-type can differ deep
        // underground (invisible at LOD distance). See the header-top contract note.
        ColumnInfo col_q = gen.resolve_column(wxc, wzc);
        col_q.ground_y = ground_q;

        // Fill the S x S footprint solid from the apron bottom up to ground_q.
        for (int fx = wx0; fx <= wx1; ++fx)
        for (int fz = wz0; fz <= wz1; ++fz) {
            for (int wy = y_bottom_apron; wy <= ground_q; ++wy) {
                const int id = gen.material_at(fx, wy, fz, col_q);
                if (id != mat::AIR) {
                    out.push_back({ fx, wy, fz, static_cast<uint8_t>(id), false });
                }
            }
        }
        if (y_bottom < filled_min_y) filled_min_y = y_bottom;
        if (ground_q + 1 > filled_max_y) filled_max_y = ground_q + 1;

        // Water: fill water PER FINE COLUMN from that column's own ground+1 up to sea
        // level (cheap compute_ground_y), exactly mirroring the fine path's per-column
        // water so the water silhouette matches after downsample (which keeps max level).
        for (int fx = wx0; fx <= wx1; ++fx)
        for (int fz = wz0; fz <= wz1; ++fz) {
            const int fgy = gen.compute_ground_y(fx, fz);
            if (fgy < sea_level) {
                for (int wy = fgy + 1; wy <= sea_level; ++wy) {
                    out.push_back({ fx, wy, fz,
                        static_cast<uint8_t>(WaterByteCodec::SOURCE_BYTE), true });
                }
                if (sea_level > filled_max_y) filled_max_y = sea_level;
            }
        }
        // FLORA: intentionally NONE at gen_lod > 0 (passthrough ids 24-28 collapse
        // to AIR under downsample; emitting them would mismatch the reduction).
    }

    if (filled_max_y < filled_min_y) { filled_min_y = filled_max_y = 0; }
    y_lo = filled_min_y;
    y_hi = filled_max_y;
}

} // namespace coarsegen
} // namespace mira
