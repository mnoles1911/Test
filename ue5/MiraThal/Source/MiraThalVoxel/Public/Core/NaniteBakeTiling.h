// NaniteBakeTiling.h — the MATH for the M6 "Nanite cold-bake" of distant terrain.
//
// WHAT THIS IS (plain English):
// When the player stands on a hilltop they can see the whole 5 km map. The near few
// hundred metres are real 10 cm voxel cubes; the band BEYOND that we want to draw as
// a permanent, baked Nanite static mesh — a "crust" of the land's surface that costs
// almost nothing to draw because Nanite culls it down to ~1 triangle per pixel.
//
// The crust is cut into square TILES (default 512 voxels = 51.2 m on a side). Each
// tile becomes one baked .uasset. This file is the pure, engine-free MATH the baker
// and the runtime ring both rely on:
//
//   1. tile_of_world / tile_origin_voxel / tile_bounds — the addressing: which tile
//      does a world voxel fall in, and where does a tile sit in the world. (floor-div,
//      so it's correct for negative coordinates — exactly like ChunkCoords.)
//
//   2. sample_crust_slab — fill ONE tile's coarse, apron'd voxel slab as a SURFACE
//      SHELL: solids only, in a thin band [ground - skirtDepth .. ground]. We don't
//      bake the whole solid column (that's millions of buried cubes nobody sees); we
//      bake just the visible skin plus a few voxels of skirt so cliff edges and the
//      seam against the near voxels aren't see-through. This GENERALISES the proven
//      MeshSuperPure sampling loop, but is decoupled from the generator via CALLBACKS
//      (height_at / color_at) so the headless clang harness can drive it with lambdas,
//      exactly like Core/FarHeightmesh.h does for the vista mesh.
//
//   3. which_tiles_in_band — the runtime ensure/release RING: given the tile the
//      player is in, which tiles fall in the crust band [innerChunks .. outerChunks]?
//      Pure and testable so the streaming component's "load these, drop those" logic
//      is locked by the harness, not guessed at against a live editor.
//
// COORDINATE NOTE: like every other Core mesher, positions come out in VOXEL space
// (x, height=y, z). The UE upload layer maps them with the SAME MiraVoxelMesh::
// PositionToUE swap+scale as the live voxels, so the crust lines up seamlessly.
//
// Pure C++17, header-only, NO engine headers — compiles in the standalone harness.

#pragma once

#include <cstdint>
#include <vector>
#include <functional>

#include "Core/MiraVec.h"       // Vec2i, Vec3i
#include "Core/ChunkCoords.h"   // coords::floor_div / floor_mod / CHUNK
#include "Core/VoxelChunk.h"    // DenseGrid, APRON, make_mesh_slab
#include "Core/VoxelColor.h"    // Rgb8

namespace mira {
namespace nanitebake {

// Default tile edge in VOXELS. 512 voxels = 51.2 m. Big enough that a 5 km map is a
// few thousand tiles (sane asset count), small enough that each baked mesh is bounded
// and the runtime can stream tiles in/out cheaply. Designer-tunable on the baker.
constexpr int DEFAULT_TILE_SPAN_VOXELS = 512;

// Default skirt depth in VOXELS: how many voxels BELOW the surface the crust shell is
// solid. The crust is a skin, not a filled column — skirtDepth gives cliff faces and
// the near-band seam enough thickness to never be see-through. 8 voxels = 0.8 m.
constexpr int DEFAULT_SKIRT_DEPTH_VOXELS = 8;

// Hard ceiling on a tile's coarse-grid side (cells per axis). sample_crust_slab allocates a
// (coarse_side + 2*APRON)^3 DenseGrid per tile, so an over-fine tile (small stride + big
// tileSpan) would blow memory — e.g. tileSpan 512 @ stride 1 = a 514^3 grid (~270 MB). Tiles
// whose coarse_side exceeds this are REFUSED (empty slab) so the caller skips them instead of
// OOMing the bake; to bake finer, shrink tileSpan so tileSpan/stride stays <= this.
constexpr int MAX_COARSE_SIDE = 96;

// ---------------------------------------------------------------------------
// 1) TILE ADDRESSING — which tile a world voxel belongs to, and where tiles sit.
//    All floor-division so negative world coordinates map correctly (the tile
//    just left/below the origin is tile -1, not tile 0). Mirrors ChunkCoords.
// ---------------------------------------------------------------------------

// The (X,Z) tile a world voxel column falls in. tileSpanVoxels is the tile edge.
inline Vec2i tile_of_world(int wx, int wz, int tileSpanVoxels) {
    return Vec2i(coords::floor_div(wx, tileSpanVoxels),
                 coords::floor_div(wz, tileSpanVoxels));
}

// The world-voxel coordinate of a tile's minimum (X,Z) corner.
inline Vec2i tile_origin_voxel(const Vec2i& tile, int tileSpanVoxels) {
    return Vec2i(tile.x * tileSpanVoxels, tile.y * tileSpanVoxels);
}

// The world-voxel [min, max] inclusive XZ bounds a tile covers. maxX/maxZ are the
// LAST voxel inside the tile (origin + span - 1), so adjacent tiles are contiguous
// with no gap and no overlap.
struct TileBounds {
    int minX, minZ; // inclusive min corner (world voxels)
    int maxX, maxZ; // inclusive max corner (world voxels)
};
inline TileBounds tile_bounds(const Vec2i& tile, int tileSpanVoxels) {
    const Vec2i o = tile_origin_voxel(tile, tileSpanVoxels);
    TileBounds b;
    b.minX = o.x;
    b.minZ = o.y;
    b.maxX = o.x + tileSpanVoxels - 1;
    b.maxZ = o.y + tileSpanVoxels - 1;
    return b;
}

// The inclusive CHUNK rectangle a tile covers (the chunk columns its voxel footprint touches).
// Used by the runtime HANDOFF: before releasing a tile the crust asks the live world whether
// THESE columns are meshed yet (AVoxelWorld::AreCoveredColumnsReady), so the near voxels are
// proven present before the crust lets go — no transition hole. floor-div for negatives.
struct TileChunkBounds { int minCx, maxCx, minCz, maxCz; };
inline TileChunkBounds tile_chunk_bounds(const Vec2i& tile, int tileSpanVoxels) {
    const TileBounds b = tile_bounds(tile, tileSpanVoxels);
    TileChunkBounds c;
    c.minCx = coords::floor_div(b.minX, coords::CHUNK);
    c.maxCx = coords::floor_div(b.maxX, coords::CHUNK);
    c.minCz = coords::floor_div(b.minZ, coords::CHUNK);
    c.maxCz = coords::floor_div(b.maxZ, coords::CHUNK);
    return c;
}

// ---------------------------------------------------------------------------
// 2) SAMPLE A TILE'S CRUST SLAB — fill one apron'd coarse DenseGrid as a surface
//    shell (solids only). GENERALISES MeshSuperPure: sample the surface at each
//    coarse column, then mark cells solid only inside the thin band
//    [ground - skirtDepth .. ground]. Decoupled from the generator via callbacks.
// ---------------------------------------------------------------------------

// The result of sampling one tile: the coarse slab to mesh, plus the coarse-cell Y
// origin we placed the shell at (the UE layer needs it to position the actor, the
// same way SuperChunkActorLocation cancels the APRON*stride shift).
struct CrustSlab {
    DenseGrid slab;          // apron'd coarse grid (side = coarse_side + 2*APRON)
    int coarse_side = 0;     // inner cube edge in COARSE cells (tileSpan / stride)
    int stride = 1;          // fine voxels per coarse cell
    int origin_voxel_x = 0;  // tile min-corner world voxel X
    int origin_voxel_z = 0;  // tile min-corner world voxel Z
    int base_fine_y = 0;     // fine-voxel Y the slab's coarse row 0 sits at (min ground - skirt)
    bool has_solid = false;  // false -> all air (e.g. tile entirely above terrain)
};

// Fill one tile's crust slab.
//
//   tile          — which tile to sample (X,Z).
//   tileSpanVoxels— tile edge in voxels (e.g. 512).
//   stride        — fine voxels per coarse cell (the downsample). coarse_side =
//                   tileSpanVoxels / stride. THIS IS THE SMOOTH-vs-CUBIC KNOB: a big stride
//                   (e.g. 16 -> 1.6 m cubes) is what makes the far crust read as a SMOOTH
//                   silhouette; a small stride bakes visibly CUBIC far terrain. Nanite renders
//                   dense cubic geometry cheaply, so cubic-everywhere is a bake-parameter choice,
//                   not a perf one. CONSTRAINT: the sampler allocates a (coarse_side + 2*APRON)^3
//                   DenseGrid PER TILE, so coarse_side must stay modest (<= ~64). To get cubic you
//                   therefore SHRINK THE TILE with the stride together — e.g. tileSpan 128 @ stride
//                   4 (40 cm cubes, coarse_side 32) or tileSpan 64 @ stride 2 (20 cm cubes). Full
//                   10 cm (stride 1) over a 5 km map is millions of tiles/assets — not viable as
//                   one-.uasset-per-tile; 20-40 cm cubes are the practical "cubic far" sweet spot.
//   skirtDepth    — how many fine voxels below the surface stay solid (the skirt).
//   height_at     — ground voxel Y at (wx,wz). Usually Gen.compute_ground_y so the
//                   crust lines up with the near voxels. In the harness: a lambda.
//   top_id_at     — surface MATERIAL ID at (wx,wz). Usually resolve_column(wx,wz).top_id.
//                   We store this id in the slab's type byte so the SAME greedy mesher
//                   the live path uses derives the SAME palette colour (base_color/
//                   shaded_color) — identical to MeshSuperPure. Must be a SOLID id
//                   (non-air, non-water) so the cell renders.
//
// The slab is apron'd (make_mesh_slab on the coarse side): the inner
// [APRON .. APRON+coarse_side) cube holds the cells; the 1-cell apron shell stays air
// (the crust band has no neighbour data to stitch against, and a coarse tile seam is
// below the noise floor at this range — same reasoning as MeshSuperPure).
//
// HEIGHT PLACEMENT (the part that makes the shell THIN): a full column would mark every
// cell from the slab bottom up to the surface solid — millions of buried cubes. Instead
// we (a) find the LOWEST ground over the tile, (b) place coarse row 0 at
// base_fine_y = min_ground - skirtDepth, and (c) per coarse column mark a cell solid only
// while its fine-Y lies in [ground - skirtDepth .. ground]. The result is a skin that
// follows the terrain, skirtDepth thick, with no interior fill.
inline CrustSlab sample_crust_slab(
    const Vec2i& tile, int tileSpanVoxels, int stride, int skirtDepth,
    const std::function<int(int, int)>&     height_at,
    const std::function<uint8_t(int, int)>& top_id_at)
{
    CrustSlab out;
    if (tileSpanVoxels <= 0 || stride <= 0) { return out; }
    const int cs = tileSpanVoxels / stride; // coarse grid side
    out.coarse_side = cs;
    out.stride = stride;
    const Vec2i o = tile_origin_voxel(tile, tileSpanVoxels);
    out.origin_voxel_x = o.x;
    out.origin_voxel_z = o.y;
    if (cs <= 0) { return out; }
    // Memory safety: refuse an over-fine tile (would allocate a huge DenseGrid). Zero coarse_side
    // so nothing iterates the unsized slab; has_solid stays false -> the caller treats it as an
    // all-air tile and skips it.
    if (cs > MAX_COARSE_SIDE) { out.coarse_side = 0; return out; }

    // The coarse slab side must hold cs cells + a 1-cell apron each side. We reuse the
    // 34^3 mesh slab when cs == CHUNK (32); for smaller cs a tighter slab still works
    // with the same APRON convention, so size it exactly cs + 2*APRON.
    const int slabSide = cs + 2 * APRON;
    out.slab = DenseGrid(slabSide);

    // --- Pass A: sample the surface height (and remember the lowest) at each coarse
    //     column's footprint centre, so we know where to anchor the shell. ---
    std::vector<int> groundY(static_cast<size_t>(cs) * cs, 0);
    int minGround = 0;
    bool any = false;
    for (int cz = 0; cz < cs; ++cz)
    for (int cx = 0; cx < cs; ++cx) {
        const int worldX = o.x + cx * stride + stride / 2;
        const int worldZ = o.y + cz * stride + stride / 2;
        const int g = height_at(worldX, worldZ);
        groundY[static_cast<size_t>(cz) * cs + cx] = g;
        if (!any || g < minGround) { minGround = g; any = true; }
    }

    // Anchor coarse row 0 a skirt below the lowest ground so every column's skirt fits.
    const int baseFineY = minGround - skirtDepth;
    out.base_fine_y = baseFineY;

    // --- Pass B: mark the thin shell solid with the SURFACE material id, so the greedy
    //     mesher derives the same palette colour the live near voxels use. ---
    for (int cz = 0; cz < cs; ++cz)
    for (int cx = 0; cx < cs; ++cx) {
        const int g = groundY[static_cast<size_t>(cz) * cs + cx];
        const int worldX = o.x + cx * stride + stride / 2;
        const int worldZ = o.y + cz * stride + stride / 2;
        const uint8_t topId = top_id_at(worldX, worldZ); // e.g. resolve_column().top_id

        for (int cy = 0; cy < cs; ++cy) {
            // The fine-Y of this coarse cell's BOTTOM (row 0 sits at baseFineY).
            const int cellBottomFineY = baseFineY + cy * stride;
            // Solid only inside the surface band [ground - skirtDepth .. ground].
            // (cellBottomFineY <= g keeps the cell at/under the surface; the
            //  >= g - skirtDepth keeps it within skirtDepth of the surface — a skin.)
            if (cellBottomFineY <= g && cellBottomFineY >= g - skirtDepth) {
                // Store the real surface material id (like MeshSuperPure stores top_id)
                // so BuildMeshBuffers colours this cell with the same base_color/shade as
                // the near voxels. topId is assumed solid (resolve_column.top_id is a
                // grass/dirt/stone id at the surface). Guard against an accidental air id.
                const uint8_t id = (topId != 0) ? topId : static_cast<uint8_t>(1);
                out.slab.set_type(cx + APRON, cy + APRON, cz + APRON, id);
                out.has_solid = true;
            }
        }
    }

    return out;
}

// ---------------------------------------------------------------------------
// 3) RUNTIME RING MEMBERSHIP — which tiles are in the crust band right now.
//    The crust covers the band [innerChunks .. outerChunks] CHUNKS from the focus.
//    We express the band in CHUNKS (to match StreamRadiusChunks / NaniteOuterChunks)
//    and convert to tiles. A tile is "in the band" if ANY part of it falls in the
//    annulus (its nearest covered chunk distance is within [inner, outer]).
//
//    Pure + deterministic so the streaming component's ensure/release set is locked
//    by the harness. focusTile is the tile the player's chunk sits in.
// ---------------------------------------------------------------------------

// Chebyshev (square-ring) distance, in CHUNKS, from a focus chunk to the NEAREST chunk
// covered by `tile`. 0 if the focus is inside the tile's footprint.
inline int tile_chunk_distance(const Vec2i& focusChunkXZ, const Vec2i& tile,
                               int tileSpanVoxels) {
    const TileBounds b = tile_bounds(tile, tileSpanVoxels);
    // Convert the tile's voxel bounds to chunk bounds (the chunks it touches).
    const int cMinX = coords::floor_div(b.minX, coords::CHUNK);
    const int cMaxX = coords::floor_div(b.maxX, coords::CHUNK);
    const int cMinZ = coords::floor_div(b.minZ, coords::CHUNK);
    const int cMaxZ = coords::floor_div(b.maxZ, coords::CHUNK);
    auto axisDist = [](int focus, int lo, int hi) -> int {
        if (focus < lo) { return lo - focus; }
        if (focus > hi) { return focus - hi; }
        return 0;
    };
    const int dx = axisDist(focusChunkXZ.x, cMinX, cMaxX);
    const int dz = axisDist(focusChunkXZ.y, cMinZ, cMaxZ);
    return (dx > dz) ? dx : dz;
}

// All tiles whose nearest covered chunk lies in [innerChunks .. outerChunks] from the
// focus chunk. innerChunks is usually the near voxel StreamRadius (the crust starts
// where the live voxels end); outerChunks is how far the crust reaches.
//
// We sweep the square of tiles that could possibly intersect the outer ring and keep
// the ones in the band. Returns tile (X,Z) keys; the caller maps each to its .uasset.
inline std::vector<Vec2i> which_tiles_in_band(
    const Vec2i& focusChunkXZ, int tileSpanVoxels,
    int innerChunks, int outerChunks)
{
    std::vector<Vec2i> out;
    if (tileSpanVoxels <= 0 || outerChunks < 0) { return out; }
    if (innerChunks < 0) { innerChunks = 0; }

    // How many TILES wide the outer ring is (round up): a tile is at most
    // ceil(outerChunks*CHUNK / tileSpan) tiles away from the focus tile in each axis.
    const int outerVoxels = outerChunks * coords::CHUNK;
    const int tileReach = (outerVoxels + tileSpanVoxels - 1) / tileSpanVoxels + 1;

    // The tile the focus chunk sits in (convert focus chunk -> focus voxel -> tile).
    const int focusVoxelX = focusChunkXZ.x * coords::CHUNK;
    const int focusVoxelZ = focusChunkXZ.y * coords::CHUNK;
    const Vec2i focusTile = tile_of_world(focusVoxelX, focusVoxelZ, tileSpanVoxels);

    for (int tz = -tileReach; tz <= tileReach; ++tz)
    for (int tx = -tileReach; tx <= tileReach; ++tx) {
        const Vec2i tile(focusTile.x + tx, focusTile.y + tz);
        const int d = tile_chunk_distance(focusChunkXZ, tile, tileSpanVoxels);
        if (d >= innerChunks && d <= outerChunks) {
            out.push_back(tile);
        }
    }
    return out;
}

} // namespace nanitebake
} // namespace mira
