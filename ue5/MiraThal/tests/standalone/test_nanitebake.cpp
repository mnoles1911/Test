// test_nanitebake.cpp — headless harness for Core/NaniteBakeTiling.h (M6 cold-bake math).
//   cd tests/standalone && ./build.sh nanitebake
//
// Locks the pure MATH the Nanite crust baker + runtime ring rely on, so it's verified
// without ever opening the editor:
//   - tiling is a correct PARTITION: every world voxel maps to exactly one tile, and
//     adjacent tile origins are contiguous (no gap, no overlap) incl. negative coords;
//   - sample_crust_slab on a FLAT map = a flat solid shell exactly skirtDepth thick;
//   - on a SLOPE = the shell follows per-column ground height;
//   - which_tiles_in_band membership matches the [inner..outer] chunk thresholds;
//   - determinism (same inputs -> identical output).

#include <cstdio>
#include <set>
#include <vector>

#include "Core/NaniteBakeTiling.h"
#include "Core/MiraVec.h"
#include "Core/ChunkCoords.h"
#include "Core/VoxelChunk.h"
#include "Core/VoxelColor.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { \
    ++g_checks; \
    if (!(cond)) { ++g_fails; std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__); } \
} while (0)

using namespace mira;
using namespace mira::nanitebake;

// Count solid cells (inner cube only) in a crust slab.
static int count_solid_inner(const CrustSlab& cr) {
    int n = 0;
    const int cs = cr.coarse_side;
    for (int cz = 0; cz < cs; ++cz)
    for (int cy = 0; cy < cs; ++cy)
    for (int cx = 0; cx < cs; ++cx) {
        if (cr.slab.type_at(cx + APRON, cy + APRON, cz + APRON) != 0) { ++n; }
    }
    return n;
}

// Solid-cell count in ONE coarse column (cx,cz) of the inner cube.
static int column_solid_height(const CrustSlab& cr, int cx, int cz) {
    int n = 0;
    const int cs = cr.coarse_side;
    for (int cy = 0; cy < cs; ++cy) {
        if (cr.slab.type_at(cx + APRON, cy + APRON, cz + APRON) != 0) { ++n; }
    }
    return n;
}

int main() {
    // =====================================================================
    // 1) TILE ADDRESSING — partition correctness.
    // =====================================================================
    const int SPAN = 512;

    // tile_of_world: floor-div, correct for negatives.
    CHECK(tile_of_world(0, 0, SPAN)        == Vec2i(0, 0),   "tile_of_world(0,0)=0");
    CHECK(tile_of_world(511, 511, SPAN)    == Vec2i(0, 0),   "tile_of_world(511,511)=0");
    CHECK(tile_of_world(512, 0, SPAN)      == Vec2i(1, 0),   "tile_of_world(512,0)=(1,0)");
    CHECK(tile_of_world(-1, -1, SPAN)      == Vec2i(-1, -1), "tile_of_world(-1,-1)=(-1,-1)");
    CHECK(tile_of_world(-512, 0, SPAN)     == Vec2i(-1, 0),  "tile_of_world(-512,0)=(-1,0)");
    CHECK(tile_of_world(-513, 0, SPAN)     == Vec2i(-2, 0),  "tile_of_world(-513,0)=(-2,0)");

    // tile_origin_voxel + tile_bounds: contiguous, inclusive, no overlap.
    {
        const Vec2i o0 = tile_origin_voxel(Vec2i(0, 0), SPAN);
        CHECK(o0 == Vec2i(0, 0), "origin(0,0)=0");
        const TileBounds b0 = tile_bounds(Vec2i(0, 0), SPAN);
        CHECK(b0.minX == 0 && b0.maxX == 511, "tile0 X bounds [0,511]");
        const TileBounds b1 = tile_bounds(Vec2i(1, 0), SPAN);
        CHECK(b1.minX == 512, "tile1 minX = 512 (contiguous with tile0 max+1)");
        CHECK(b0.maxX + 1 == b1.minX, "tiles contiguous (no gap, no overlap)");
        const TileBounds bn = tile_bounds(Vec2i(-1, 0), SPAN);
        CHECK(bn.minX == -512 && bn.maxX == -1, "tile -1 X bounds [-512,-1]");
        CHECK(bn.maxX + 1 == b0.minX, "negative tile contiguous with tile0");
    }

    // PARTITION sweep: every voxel in a range maps to exactly one tile, and that tile's
    // bounds contain it. Cover a span crossing the origin (negatives included).
    {
        bool ok = true;
        for (int wx = -1100; wx <= 1100 && ok; wx += 7) {
            const Vec2i t = tile_of_world(wx, 0, SPAN);
            const TileBounds b = tile_bounds(t, SPAN);
            if (!(wx >= b.minX && wx <= b.maxX)) { ok = false; }
        }
        CHECK(ok, "every voxel falls inside exactly its own tile's bounds");
    }

    // =====================================================================
    // 2) sample_crust_slab — FLAT map -> flat solid shell skirtDepth thick.
    // =====================================================================
    // Pick stride so coarse_side = SPAN/stride <= CHUNK(32). 512/16 = 32.
    const int STRIDE = 16;
    const int SKIRT  = 8 * STRIDE; // skirt in fine voxels (so it spans skirt/stride coarse rows)
    {
        const int FLAT_GROUND = 1000;
        auto heightFlat = [&](int, int) { return FLAT_GROUND; };
        auto idFlat     = [&](int, int) -> uint8_t { return 3; }; // some solid surface id

        CrustSlab cr = sample_crust_slab(Vec2i(2, 3), SPAN, STRIDE, SKIRT,
                                         heightFlat, idFlat);
        CHECK(cr.coarse_side == 32, "flat: coarse_side = 32 (512/16)");
        CHECK(cr.has_solid, "flat: shell has solids");

        // Each coarse column should have the SAME solid height (flat terrain).
        const int h00 = column_solid_height(cr, 0, 0);
        bool uniform = true;
        for (int cz = 0; cz < cr.coarse_side && uniform; ++cz)
        for (int cx = 0; cx < cr.coarse_side && uniform; ++cx) {
            if (column_solid_height(cr, cx, cz) != h00) { uniform = false; }
        }
        CHECK(uniform, "flat: every column has identical shell height");

        // The shell band is [ground-skirt .. ground]; with row0 at min_ground-skirt and
        // stride per row, the solid rows span exactly skirt/stride + 1 (inclusive band).
        const int expectRows = SKIRT / STRIDE + 1;
        CHECK(h00 == expectRows, "flat: shell thickness = skirt/stride + 1 rows");

        // Origin bookkeeping: tile (2,3) at span 512 -> world (1024, 1536).
        CHECK(cr.origin_voxel_x == 1024 && cr.origin_voxel_z == 1536,
              "flat: origin voxel = (1024,1536)");
        CHECK(cr.base_fine_y == FLAT_GROUND - SKIRT, "flat: base_fine_y = ground-skirt");
    }

    // =====================================================================
    // 3) sample_crust_slab — SLOPE -> shell follows per-column ground.
    // =====================================================================
    {
        // Ground rises 1 voxel per voxel of world X (a 45-degree ramp). Columns at
        // larger X sit higher -> their solid cells start at a higher fine-Y, but each
        // column's shell thickness (rows) stays ~constant (skirt is per-column).
        auto heightSlope = [&](int wx, int) { return wx; };
        auto idSlope     = [&](int, int) -> uint8_t { return 7; };

        CrustSlab cr = sample_crust_slab(Vec2i(0, 0), SPAN, STRIDE, SKIRT,
                                         heightSlope, idSlope);
        CHECK(cr.has_solid, "slope: shell has solids");

        // The TOP solid coarse-row index must INCREASE with cx (higher ground at higher X).
        auto top_row = [&](int cx, int cz) -> int {
            int top = -1;
            for (int cy = 0; cy < cr.coarse_side; ++cy) {
                if (cr.slab.type_at(cx + APRON, cy + APRON, cz + APRON) != 0) { top = cy; }
            }
            return top;
        };
        const int tLeft  = top_row(0, 0);
        const int tRight = top_row(cr.coarse_side - 1, 0);
        CHECK(tRight > tLeft, "slope: shell top rises with X (follows ground)");

        // Determinism: re-sampling gives byte-identical type bytes.
        CrustSlab cr2 = sample_crust_slab(Vec2i(0, 0), SPAN, STRIDE, SKIRT,
                                          heightSlope, idSlope);
        CHECK(cr.slab.type == cr2.slab.type, "slope: sampling is deterministic");
        CHECK(count_solid_inner(cr) == count_solid_inner(cr2), "slope: solid count stable");
    }

    // All-air tile (ground far below the slab? No — ground always reachable; instead test
    // a tile where the shell is well-formed and non-empty as a sanity floor).
    {
        auto h = [&](int, int) { return 500; };
        auto id = [&](int, int) -> uint8_t { return 2; };
        CrustSlab cr = sample_crust_slab(Vec2i(-3, -3), SPAN, STRIDE, SKIRT, h, id);
        CHECK(cr.has_solid && count_solid_inner(cr) > 0, "negative tile still bakes a shell");
    }

    // =====================================================================
    // 4) which_tiles_in_band — ring membership matches thresholds.
    // =====================================================================
    {
        // Focus at chunk (0,0). Inner = 4 chunks (the near voxels), outer = 30 chunks.
        // Tile span 512 voxels = 16 chunks. So the band [4..30] chunks should include
        // tiles touching that annulus and EXCLUDE the focus tile's near chunks only if
        // the whole tile is inside the inner radius (it isn't, since a tile is 16 chunks
        // wide and inner is 4 -> the focus tile straddles the band).
        const Vec2i focusChunk(0, 0);
        const int inner = 4, outer = 30;
        std::vector<Vec2i> tiles = which_tiles_in_band(focusChunk, SPAN, inner, outer);
        CHECK(!tiles.empty(), "band: returns a non-empty tile set");

        // Every returned tile must actually be in [inner..outer] chunk distance.
        bool allInBand = true;
        for (const Vec2i& t : tiles) {
            const int d = tile_chunk_distance(focusChunk, t, SPAN);
            if (d < inner || d > outer) { allInBand = false; }
        }
        CHECK(allInBand, "band: every returned tile is within [inner..outer]");

        // A far tile WELL beyond outer must NOT be present.
        {
            const Vec2i farTile(10, 0); // 10 tiles = 160 chunks away -> outside outer=30
            bool present = false;
            for (const Vec2i& t : tiles) { if (t == farTile) { present = true; } }
            CHECK(!present, "band: tile far beyond outer is excluded");
        }

        // No duplicate tiles.
        {
            std::set<std::pair<int,int>> uniq;
            bool dup = false;
            for (const Vec2i& t : tiles) {
                if (!uniq.insert({t.x, t.y}).second) { dup = true; }
            }
            CHECK(!dup, "band: no duplicate tiles");
        }

        // Determinism: same query -> same set (order included).
        std::vector<Vec2i> tiles2 = which_tiles_in_band(focusChunk, SPAN, inner, outer);
        bool same = (tiles.size() == tiles2.size());
        for (size_t i = 0; same && i < tiles.size(); ++i) {
            if (tiles[i] != tiles2[i]) { same = false; }
        }
        CHECK(same, "band: membership is deterministic");
    }

    // tile_chunk_distance sanity: a tile containing the focus chunk is distance 0.
    {
        const Vec2i focusChunk(1, 1); // chunk (1,1) -> voxel (32,32) -> tile (0,0) at span 512
        const int d = tile_chunk_distance(focusChunk, Vec2i(0, 0), SPAN);
        CHECK(d == 0, "tile containing focus chunk has distance 0");
    }

    // =====================================================================
    // 5) tile_chunk_bounds — the chunk rectangle a tile covers (runtime HANDOFF query).
    //    The crust asks AVoxelWorld whether THESE columns are meshed before releasing a tile.
    // =====================================================================
    {
        // Tile (0,0) @ span 512 covers voxels [0..511] -> chunks [0..15] (CHUNK = 32).
        const TileChunkBounds c0 = tile_chunk_bounds(Vec2i(0, 0), SPAN);
        CHECK(c0.minCx == 0 && c0.maxCx == 15, "tile(0,0) covers chunks X [0..15]");
        CHECK(c0.minCz == 0 && c0.maxCz == 15, "tile(0,0) covers chunks Z [0..15]");
        // Tile (1,0) -> voxels [512..1023] -> chunks [16..31].
        const TileChunkBounds c1 = tile_chunk_bounds(Vec2i(1, 0), SPAN);
        CHECK(c1.minCx == 16 && c1.maxCx == 31, "tile(1,0) covers chunks X [16..31]");
        // Negative tile (-1,0) -> voxels [-512..-1] -> chunks [-16..-1].
        const TileChunkBounds cn = tile_chunk_bounds(Vec2i(-1, 0), SPAN);
        CHECK(cn.minCx == -16 && cn.maxCx == -1, "tile(-1,0) covers chunks X [-16..-1]");
        CHECK(cn.maxCx + 1 == c0.minCx, "tile chunk-bounds contiguous (no gap/overlap)");
    }

    // =====================================================================
    // 6) MAX_COARSE_SIDE guard — an over-fine tile is refused (no OOM), a tile at the
    //    ceiling still bakes. This is what keeps a "cubic" re-bake from blowing memory.
    // =====================================================================
    {
        auto h  = [&](int, int) { return 100; };
        auto id = [&](int, int) -> uint8_t { return 3; };
        // span 512 @ stride 1 -> coarse_side 512 > MAX_COARSE_SIDE -> refused (empty, cs=0).
        CrustSlab huge = sample_crust_slab(Vec2i(0, 0), SPAN, 1, 8, h, id);
        CHECK(!huge.has_solid && huge.coarse_side == 0, "over-fine tile refused: empty, cs=0");
        CHECK(count_solid_inner(huge) == 0, "over-fine tile refused: no solids");
        // A tile right at the ceiling still bakes: span 96 @ stride 1 -> cs 96 == MAX.
        CrustSlab okTile = sample_crust_slab(Vec2i(0, 0), MAX_COARSE_SIDE, 1, 8, h, id);
        CHECK(okTile.coarse_side == MAX_COARSE_SIDE && okTile.has_solid,
              "cs == MAX_COARSE_SIDE still bakes a shell");
    }

    std::printf("[nanitebake] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
