// test_worldedit.cpp — parity harness for Core/WorldEditStore.h (P2 persistence).
//   cd tests/standalone && ./build.sh worldedit
//
// Asserts the contract of the player-edit journal:
//   * region bucketing: voxels group into REGION_SIZE tiles; region_of uses
//     floor-div so negative coords land in the right tile;
//   * latest-wins: editing a voxel twice keeps only the final value (compact);
//   * apply_region replays edits onto a brickmap (carve to air, place a block);
//   * dirty tracking: records dirty a region, mark_clean clears it, loads don't
//     dirty;
//   * disk round-trip: region_edit_list -> encode_delta_log -> decode_delta_log
//     -> load_region into a fresh store reproduces the same applied world.
//
// Prints "[worldedit] PASS/FAIL"; returns 0 on success, 1 on any failure.

#include <cstdio>
#include <algorithm>
#include <vector>

#include "Core/WorldEditStore.h"
#include "Core/RegionFormat.h"
#include "Core/Brickmap.h"
#include "Core/MaterialIds.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;

static bool has_region_coord(const std::vector<Vec3i>& v, const Vec3i& c) {
    return std::find(v.begin(), v.end(), c) != v.end();
}

int main() {
    const int R = WorldEditStore::REGION_SIZE; // 512

    // ---------------------------------------------------------------------
    // 1. Region bucketing + floor-div on negatives.
    // ---------------------------------------------------------------------
    {
        CHECK(WorldEditStore::region_of(Vec3i(0,0,0))    == Vec3i(0,0,0), "origin -> region (0,0,0)");
        CHECK(WorldEditStore::region_of(Vec3i(R-1,99,R-1))== Vec3i(0,0,0), "just inside tile 0 -> (0,0,0)");
        CHECK(WorldEditStore::region_of(Vec3i(R,0,0))    == Vec3i(1,0,0), "x=R -> region (1,0,0)");
        CHECK(WorldEditStore::region_of(Vec3i(-1,0,-1))  == Vec3i(-1,0,-1), "x=-1 -> region (-1,0,-1) (floor-div)");
        CHECK(WorldEditStore::region_of(Vec3i(5,9999,7)) == Vec3i(0,0,0), "Y is ignored in the XZ tiling");
    }

    // ---------------------------------------------------------------------
    // 2. record + latest-wins + counts.
    // ---------------------------------------------------------------------
    {
        WorldEditStore s;
        s.record(Vec3i(10,10,10), mat::STONE, 0);
        s.record(Vec3i(10,10,10), mat::AIR, 0);   // dig the SAME voxel -> overwrites
        s.record(Vec3i(11,10,10), mat::DIRT, 0);
        s.record(Vec3i(R+4, 0, 4), mat::GRASS, 0); // different region tile

        CHECK(s.total_edits() == 3, "latest-wins: 4 records over 3 distinct voxels = 3 edits");
        CHECK(s.region_count() == 2, "edits span 2 region tiles");
        CHECK(s.region_edit_count(Vec3i(0,0,0)) == 2, "tile 0 holds 2 voxels");
        CHECK(s.region_edit_count(Vec3i(1,0,0)) == 1, "tile 1 holds 1 voxel");

        // The final value of the twice-edited voxel is the LAST one (air).
        std::vector<region::VoxelEdit> list = s.region_edit_list(Vec3i(0,0,0));
        bool found_air = false;
        for (const auto& e : list) if (e.voxel == Vec3i(10,10,10)) found_air = (e.type == mat::AIR);
        CHECK(found_air, "twice-edited voxel keeps the final value (air)");
    }

    // ---------------------------------------------------------------------
    // 3. apply_region replays onto a brickmap (over generated terrain).
    // ---------------------------------------------------------------------
    {
        Brickmap bm;
        // Pretend the generator filled solid stone here.
        bm.set_type(Vec3i(10,10,10), mat::STONE);
        bm.set_type(Vec3i(12,10,10), mat::STONE);

        WorldEditStore s;
        s.record(Vec3i(10,10,10), mat::AIR, 0);    // player dug this one out
        s.record(Vec3i(20,20,20), mat::DIRT, 0);   // player placed a block in air

        s.apply_region(Vec3i(0,0,0), bm);

        CHECK(bm.type_at(Vec3i(10,10,10)) == mat::AIR,  "replay carved the dug voxel to air");
        CHECK(bm.type_at(Vec3i(12,10,10)) == mat::STONE,"untouched generated voxel unchanged");
        CHECK(bm.type_at(Vec3i(20,20,20)) == mat::DIRT, "replay placed the new block");
    }

    // ---------------------------------------------------------------------
    // 4. Dirty tracking.
    // ---------------------------------------------------------------------
    {
        WorldEditStore s;
        s.record(Vec3i(1,1,1), mat::STONE, 0);
        std::vector<Vec3i> d = s.dirty_regions();
        CHECK(d.size() == 1 && has_region_coord(d, Vec3i(0,0,0)), "a record dirties its region");
        s.mark_clean(Vec3i(0,0,0));
        CHECK(s.dirty_regions().empty(), "mark_clean clears the dirty flag");
        s.record(Vec3i(2,2,2), mat::DIRT, 0);
        CHECK(s.dirty_regions().size() == 1, "a later record re-dirties the region");
    }

    // ---------------------------------------------------------------------
    // 5. Disk round-trip: store -> delta-log bytes -> store -> same world.
    // ---------------------------------------------------------------------
    {
        WorldEditStore src;
        src.record(Vec3i(10,10,10), mat::AIR, 0);
        src.record(Vec3i(20,20,20), mat::DIRT, 0);
        src.record(Vec3i(30,5,30),  mat::GRASS, 7); // also carries a water byte

        const Vec3i rc(0,0,0);
        std::vector<region::VoxelEdit> list = src.region_edit_list(rc);
        std::vector<uint8_t> bytes = region::encode_delta_log(list);

        std::vector<region::VoxelEdit> decoded;
        const bool ok = region::decode_delta_log(bytes, decoded);
        CHECK(ok, "delta log decodes");
        CHECK(decoded.size() == 3, "all 3 edits survive the round-trip");

        // Load into a fresh store + apply; compare to applying the source directly.
        WorldEditStore dst;
        dst.load_region(rc, decoded);
        CHECK(dst.total_edits() == 3, "loaded store has 3 edits");
        CHECK(dst.dirty_regions().empty(), "a loaded region is NOT dirty (matches disk)");

        Brickmap a, b;
        src.apply_region(rc, a);
        dst.apply_region(rc, b);
        CHECK(a.type_at(Vec3i(30,5,30)) == b.type_at(Vec3i(30,5,30)), "round-tripped type matches");
        CHECK(a.water_at(Vec3i(30,5,30)) == b.water_at(Vec3i(30,5,30)), "round-tripped water matches");
        CHECK(b.type_at(Vec3i(20,20,20)) == mat::DIRT, "round-tripped placed block present");
    }

    std::printf("[worldedit] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
