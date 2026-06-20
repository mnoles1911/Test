// test_p2persist.cpp — the P2 "edit-journal persistence" round-trip, end-to-end.
//   cd tests/standalone && ./build.sh p2persist
//
// WHAT THIS PROVES (plain English):
// The game never saves the whole world to disk. It saves only "what the player
// changed" — a journal of voxel edits — and rebuilds everything else from the
// terrain generator on load. This test runs that ENTIRE loop the way the game
// runs it, and proves the world you see after a save+reload is byte-for-byte the
// world you had before, while NOT cheating by keeping the old data around:
//
//   1. GENERATE base terrain into a brickmap from the real HeightmapGenerator
//      (this is "the world the generator gives you for free", same code the game
//      streams a chunk-column from).
//   2. The player makes edits: carve some voxels to AIR (digging a tunnel),
//      place a few solid materials (building), and leave a settled pool of water
//      (a water byte built with the real WaterByteCodec). Each edit is recorded
//      into a WorldEditStore — the authoritative journal.
//   3. Apply those edits on top of the generated terrain → this is the
//      "post-edit world" the player actually sees. We remember it as the truth.
//   4. SAVE: for each touched region, serialize its deltas to a byte buffer via
//      RegionFormat::encode_delta_log — the exact bytes MiraWorldPersist writes
//      to a region file on disk.
//   5. RELOAD (simulated): decode those bytes back with decode_delta_log into a
//      COMPLETELY FRESH WorldEditStore. The original store is then dropped — so
//      from here on the only memory of the player's work is what survived disk.
//   6. REGENERATE the base terrain into a brand-new brickmap (the generator is
//      deterministic, so it reproduces the same terrain), then REPLAY the loaded
//      edits on top (the ApplyEditsToColumn equivalent the game runs per chunk).
//   7. ASSERT: every voxel — edited AND untouched — matches the post-edit truth
//      from step 3 exactly, in BOTH channels (material id and water byte).
//
// Plus two safety cases:
//   * EMPTY region: a region with no edits still round-trips cleanly (the save
//     system must tolerate "nothing changed here").
//   * FORMAT INTEGRITY: a one-byte corruption of the saved bytes is caught by
//     RegionFormat's CRC32 footer (a bad save file must fail loudly, not load
//     a silently-wrong world).
//
// NOTE on scope: test_worldedit.cpp already covers the store's bucketing,
// latest-wins, dirty tracking, and a small single-region round-trip. This
// harness deliberately does NOT re-test those; it exercises the full
// generator → edit → save → reload → regenerate → replay loop across MULTIPLE
// region tiles with a real generated base and exact whole-world verification.
//
// Prints "[p2persist] PASS/FAIL"; returns 0 on success, 1 on any failure — the
// same convention build.sh keys off for the green gate.

#include <cstdio>
#include <vector>
#include <unordered_set>

#include "Core/WorldEditStore.h"   // the player-edit journal (record/load/apply)
#include "Core/RegionFormat.h"     // encode_delta_log / decode_delta_log (disk bytes)
#include "Core/Brickmap.h"         // the authoritative voxel store (replay target)
#include "Core/ChunkCoords.h"      // floor_div / region math
#include "Core/MaterialIds.h"      // mat::AIR, STONE, DIRT, ...
#include "Core/WaterByteCodec.h"   // build a real settled-water byte
#include "Core/HeightmapGenerator.h" // the real base-terrain generator

// ---- Test harness: same CHECK macro + counters as the other Core tests -------
static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;

// =============================================================================
// generate_base_terrain — fill a brickmap with the generator's output over a
// rectangular world footprint, the same way a streamed chunk-column gets its
// base voxels before edits are replayed on top.
//
// We walk every (x, z) column in the footprint, ask the generator where the
// ground is and what material each voxel is, and write the solid cells. Air
// above the ground is left as air (absent bricks read as air — that's the
// sparse store doing its job). The Y window is chosen to comfortably bracket
// the generated ground so the surface always lands inside it.
// =============================================================================
static void generate_base_terrain(const HeightmapGenerator& gen, Brickmap& bm,
                                  int x0, int x1, int z0, int z1,
                                  int y_lo, int y_hi) {
    for (int z = z0; z < z1; ++z) {
        for (int x = x0; x < x1; ++x) {
            // Resolve this column once (ground height, banding, water flag, ...).
            const ColumnInfo col = gen.resolve_column(x, z);
            for (int y = y_lo; y < y_hi; ++y) {
                // material_at returns AIR for cells above ground; only write the
                // solid ones so the sparse brickmap stays sparse (air = absent).
                const int id = gen.material_at(x, y, z, col);
                if (id != mat::AIR) {
                    bm.set_type(Vec3i(x, y, z), static_cast<uint8_t>(id));
                }
            }
        }
    }
}

// A single player edit we will record, apply, save, and later verify. Mirrors
// region::VoxelEdit but kept local so the "expected truth" list is independent
// of the store's internals.
struct PlayerEdit {
    Vec3i   voxel;
    uint8_t type;
    uint8_t water;
};

int main() {
    // -------------------------------------------------------------------------
    // Set up the deterministic generator. A fixed seed means "regenerate" in
    // step 6 reproduces exactly the same terrain as step 1 — which is the whole
    // premise of edit-journal persistence (untouched terrain is free + repeatable).
    // -------------------------------------------------------------------------
    HeightmapGenerator gen;
    gen.set_seed(20260617);

    const int R = WorldEditStore::REGION_SIZE; // 512 voxels per region tile side

    // -------------------------------------------------------------------------
    // Choose a small world footprint that STRADDLES a region-tile boundary, so
    // the save/load loop must handle more than one region file. The boundary at
    // x = R (512) splits region (0,0,0) from (1,0,0); we put columns on both sides.
    // The footprint is intentionally tiny (a few columns) so the test is fast.
    // -------------------------------------------------------------------------
    const int X0 = R - 4,  X1 = R + 4;   // 8 columns spanning the x=512 boundary
    const int Z0 = 6,      Z1 = 14;      // 8 columns deep

    // The Y window must BRACKET the generator's actual ground (which is data-
    // driven, not a fixed height). Scan every column's ground_y over the
    // footprint, then pad generously below (to include the dirt/stone band) and
    // above (to leave air room for placed blocks). This keeps the test correct
    // no matter where this seed's terrain happens to sit.
    int g_min = 1 << 30, g_max = -(1 << 30);
    for (int z = Z0; z < Z1; ++z)
        for (int x = X0; x < X1; ++x) {
            const int g = gen.resolve_column(x, z).ground_y;
            if (g < g_min) g_min = g;
            if (g > g_max) g_max = g;
        }
    const int Y_LO = g_min - 16;   // a few voxels of solid band below the lowest ground
    const int Y_HI = g_max + 8;    // a few voxels of air above the highest ground

    // Build the original base terrain once (this is "the generated world").
    Brickmap base;
    generate_base_terrain(gen, base, X0, X1, Z0, Z1, Y_LO, Y_HI);
    CHECK(base.brick_count() > 0, "generator produced some solid terrain to edit");

    // -------------------------------------------------------------------------
    // STEP 2 — record the player's edits into the authoritative journal.
    //
    // We pick concrete voxels we KNOW sit on solid ground (so carving them to
    // air is a real change), plus a couple of placements into air, plus a
    // settled water byte. We base the edit Y on each column's resolved ground so
    // the edits are meaningful regardless of the generator's absolute heights.
    // -------------------------------------------------------------------------
    // A real "settled pool" water byte: full level, not a source, still (settled).
    const uint8_t SETTLED_WATER =
        static_cast<uint8_t>(WaterByteCodec::pack(WaterByteCodec::MAX_LEVEL,
                                                  /*source=*/false,
                                                  WaterByteCodec::DIR_STILL));
    CHECK(WaterByteCodec::is_water(SETTLED_WATER), "settled water byte reads as water");
    CHECK(WaterByteCodec::dir_of(SETTLED_WATER) == WaterByteCodec::DIR_STILL,
          "settled water byte is STILL (not flowing)");

    WorldEditStore store;
    std::vector<PlayerEdit> expected_edits; // the edits we will verify survived

    auto record = [&](const Vec3i& v, uint8_t type, uint8_t water) {
        store.record(v, type, water);
        expected_edits.push_back({v, type, water});
    };

    // Walk a few columns on BOTH sides of the region boundary and edit each.
    int columns_edited = 0;
    for (int x = X0; x < X1; x += 3) {       // x = R-4, R-1, R+2 (both regions)
        for (int z = Z0; z < Z1; z += 4) {   // z = 6, 10
            const ColumnInfo col = gen.resolve_column(x, z);
            const int g = col.ground_y;      // top solid voxel of this column

            // (a) CARVE: dig the surface voxel down to air (a tunnel mouth).
            record(Vec3i(x, g, z), static_cast<uint8_t>(mat::AIR), 0);
            // and one voxel below it too, to make a 2-deep hole.
            record(Vec3i(x, g - 1, z), static_cast<uint8_t>(mat::AIR), 0);

            // (b) PLACE: stack a couple of placed blocks into the air above.
            record(Vec3i(x, g + 2, z), static_cast<uint8_t>(mat::MARBLE), 0);
            record(Vec3i(x, g + 3, z), static_cast<uint8_t>(mat::LOG), 0);

            // (c) WATER: leave a settled pool in the carved hole (type air +
            //     a non-zero water byte — exactly how a finite-water cell is
            //     stored: the TYPE channel is air, the WATER channel carries it).
            record(Vec3i(x, g, z), static_cast<uint8_t>(mat::AIR), SETTLED_WATER);
            // NOTE: this voxel was carved to (air, 0) above, then re-recorded as
            //       (air, water). Latest-wins in the store collapses these to the
            //       FINAL state (air + water) — exactly what the game keeps.

            ++columns_edited;
        }
    }
    CHECK(columns_edited >= 3, "edited columns span both region tiles");
    // The carve+water voxel is recorded twice; latest-wins means it is ONE entry.
    // So distinct edited voxels = columns * 4 (carve-top, carve-below, marble, log)
    // because the 5th record re-keys the carve-top voxel.
    CHECK(store.total_edits() == static_cast<size_t>(columns_edited) * 4,
          "latest-wins collapsed the re-edited water voxel (4 distinct per column)");

    // The store must hold edits in BOTH region tiles (proves multi-region save).
    CHECK(store.has_region(Vec3i(0,0,0)), "edits recorded in region (0,0,0)");
    CHECK(store.has_region(Vec3i(1,0,0)), "edits recorded in region (1,0,0)");
    CHECK(store.region_count() == 2, "exactly two regions were touched");

    // -------------------------------------------------------------------------
    // STEP 3 — build the POST-EDIT TRUTH: generated terrain + edits applied.
    // This is the world the player sees on screen right now, before any save.
    // We keep it as the reference everything is compared against later.
    // -------------------------------------------------------------------------
    Brickmap truth;
    generate_base_terrain(gen, truth, X0, X1, Z0, Z1, Y_LO, Y_HI);
    store.apply_all(truth); // replay every region's edits onto the fresh base

    // Quick sanity that the edits actually CHANGED the world (else the test would
    // pass trivially even if persistence were broken).
    {
        const Vec3i probe(X0, gen.resolve_column(X0, Z0).ground_y, Z0);
        CHECK(base.type_at(probe) != mat::AIR, "base terrain was solid at a carve site");
        CHECK(truth.type_at(probe) == mat::AIR, "carve made the truth-world air there");
        CHECK(truth.water_at(probe) == SETTLED_WATER, "settled water present in truth-world");
    }

    // -------------------------------------------------------------------------
    // STEP 4 — SAVE: serialize each touched region's deltas to disk bytes.
    // This is byte-for-byte what MiraWorldPersist writes to a region file. We
    // capture one byte buffer PER region (regions save to their own small files).
    // -------------------------------------------------------------------------
    std::vector<Vec3i> saved_regions = store.region_coords();
    std::vector<std::vector<uint8_t>> region_bytes; // one blob per region (the "files")
    region_bytes.reserve(saved_regions.size());
    for (const Vec3i& rc : saved_regions) {
        std::vector<region::VoxelEdit> list = store.region_edit_list(rc);
        region_bytes.push_back(region::encode_delta_log(list));
    }
    CHECK(region_bytes.size() == 2, "two region delta-logs were serialized");
    for (const auto& blob : region_bytes) {
        CHECK(blob.size() >= 6, "each serialized region is at least the 6-byte minimum");
    }

    // -------------------------------------------------------------------------
    // STEP 5 — RELOAD: decode the saved bytes into a FRESH store. Then drop the
    // original store entirely — the only surviving record of the player's work
    // is now whatever round-tripped through these byte buffers.
    // -------------------------------------------------------------------------
    WorldEditStore reloaded;
    for (size_t i = 0; i < saved_regions.size(); ++i) {
        std::vector<region::VoxelEdit> decoded;
        const bool ok = region::decode_delta_log(region_bytes[i], decoded);
        CHECK(ok, "saved region delta-log decodes cleanly on reload");
        reloaded.load_region(saved_regions[i], decoded);
    }
    // A freshly loaded store matches disk, so it must NOT be marked dirty (the
    // game uses this to avoid re-saving unchanged regions immediately on load).
    CHECK(reloaded.dirty_regions().empty(), "a just-loaded store is not dirty");
    CHECK(reloaded.total_edits() == store.total_edits(),
          "reloaded store has the same number of edits as before saving");

    // Drop the original store so nothing downstream can accidentally read it.
    store.clear();
    CHECK(store.total_edits() == 0, "original store cleared (no cheating below)");

    // -------------------------------------------------------------------------
    // STEP 6 — REGENERATE + REPLAY: rebuild base terrain from scratch, then
    // replay the RELOADED edits on top. This is exactly the per-chunk game path:
    // generate from the generator, then ApplyEditsToColumn from the journal.
    // -------------------------------------------------------------------------
    Brickmap restored;
    generate_base_terrain(gen, restored, X0, X1, Z0, Z1, Y_LO, Y_HI);
    reloaded.apply_all(restored);

    // -------------------------------------------------------------------------
    // STEP 7 — VERIFY: the restored world equals the post-edit truth EVERYWHERE.
    //
    // (a) Every recorded edit's voxel matches its intended final state in BOTH
    //     channels. We compare against the truth-world (which already has the
    //     final, latest-wins state baked in by apply_all).
    // -------------------------------------------------------------------------
    {
        bool all_edits_ok = true;
        for (const PlayerEdit& e : expected_edits) {
            if (restored.type_at(e.voxel)  != truth.type_at(e.voxel) ||
                restored.water_at(e.voxel) != truth.water_at(e.voxel)) {
                all_edits_ok = false;
                break;
            }
        }
        CHECK(all_edits_ok, "every edited voxel matches the post-edit truth (type AND water)");
    }

    // Spot-check the specific game-meaningful outcomes by hand (not just the
    // bulk loop), so a regression names exactly what broke.
    {
        const int gx = X0, gz = Z0;
        const int g = gen.resolve_column(gx, gz).ground_y;
        CHECK(restored.type_at(Vec3i(gx, g, gz))  == mat::AIR,    "restored: carved surface is air");
        CHECK(restored.water_at(Vec3i(gx, g, gz)) == SETTLED_WATER,"restored: settled water survived the round-trip");
        CHECK(restored.type_at(Vec3i(gx, g - 1, gz)) == mat::AIR, "restored: 2-deep carve is air");
        CHECK(restored.type_at(Vec3i(gx, g + 2, gz)) == mat::MARBLE, "restored: placed marble block present");
        CHECK(restored.type_at(Vec3i(gx, g + 3, gz)) == mat::LOG,    "restored: placed log block present");
    }

    // -------------------------------------------------------------------------
    // (b) UN-EDITED voxels are untouched. We sweep the WHOLE footprint+Y window
    //     and compare restored vs truth at every cell. Any voxel the player did
    //     NOT edit must read identically to the freshly generated terrain, and
    //     any voxel they DID edit must read its edited state — both are already
    //     captured in `truth`, so a full equality sweep proves both at once.
    //     This is the strongest possible statement: the reloaded world is the
    //     SAME world, voxel-for-voxel, in both channels.
    // -------------------------------------------------------------------------
    {
        // Build a fast lookup of edited voxels so we can also explicitly assert
        // that at least some swept cells were UN-edited and still matched (i.e.
        // we are genuinely testing untouched terrain, not only edit sites).
        std::unordered_set<Vec3i> edited_set;
        for (const PlayerEdit& e : expected_edits) edited_set.insert(e.voxel);

        long long mismatches      = 0;
        long long unedited_checked = 0;
        for (int z = Z0; z < Z1; ++z) {
            for (int x = X0; x < X1; ++x) {
                for (int y = Y_LO; y < Y_HI; ++y) {
                    const Vec3i v(x, y, z);
                    const uint8_t rt = restored.type_at(v),  tt = truth.type_at(v);
                    const uint8_t rw = restored.water_at(v), tw = truth.water_at(v);
                    if (rt != tt || rw != tw) ++mismatches;
                    if (edited_set.find(v) == edited_set.end() &&
                        tt != mat::AIR) {
                        ++unedited_checked; // an untouched SOLID voxel we verified
                    }
                }
            }
        }
        CHECK(mismatches == 0,
              "whole-footprint sweep: restored world equals truth at every voxel (type + water)");
        CHECK(unedited_checked > 0,
              "the sweep actually verified untouched solid terrain (not just edit sites)");
    }

    // -------------------------------------------------------------------------
    // (c) EMPTY-REGION case: a region with no edits round-trips cleanly. The
    //     save system must tolerate "nothing changed here" — encode an empty
    //     delta-log, decode it, load it, and confirm it adds nothing and stays
    //     non-dirty (a valid, if empty, save).
    // -------------------------------------------------------------------------
    {
        std::vector<region::VoxelEdit> none;            // no edits
        std::vector<uint8_t> empty_blob = region::encode_delta_log(none);
        CHECK(empty_blob.size() <= 8, "empty region serializes to a tiny blob");

        std::vector<region::VoxelEdit> decoded;
        const bool ok = region::decode_delta_log(empty_blob, decoded);
        CHECK(ok, "empty region delta-log decodes successfully");
        CHECK(decoded.empty(), "empty region decodes to zero edits");

        WorldEditStore empty_store;
        const Vec3i far_region(9, 0, 9);                // a region nobody touched
        empty_store.load_region(far_region, decoded);
        CHECK(empty_store.total_edits() == 0, "loading an empty region adds no edits");
        CHECK(empty_store.dirty_regions().empty(), "an empty loaded region is not dirty");

        // Replaying it onto a brickmap is a clean no-op (no crash, no change).
        Brickmap fresh;
        generate_base_terrain(gen, fresh, X0, X0 + 2, Z0, Z0 + 2, Y_LO, Y_HI);
        const size_t bricks_before = fresh.brick_count();
        empty_store.apply_all(fresh);
        CHECK(fresh.brick_count() == bricks_before, "empty replay changes nothing");
    }

    // -------------------------------------------------------------------------
    // (d) FORMAT INTEGRITY: corrupt one byte of a real saved region and confirm
    //     RegionFormat's CRC32 footer rejects it. A damaged save file must fail
    //     to load (decode returns false), NOT silently produce a wrong world.
    // -------------------------------------------------------------------------
    {
        // Use the first real region blob (it has actual edits in it).
        std::vector<uint8_t> corrupt = region_bytes[0];
        CHECK(corrupt.size() > 2, "have a non-trivial region blob to corrupt");
        // Flip a byte in the payload (skip the version byte at [0]); the CRC
        // footer covers it, so the decode must detect the mismatch.
        corrupt[corrupt.size() / 2] ^= 0x5A;

        std::vector<region::VoxelEdit> out;
        const bool ok = region::decode_delta_log(corrupt, out);
        CHECK(!ok, "CRC32 integrity check rejects a corrupted region save");
        CHECK(out.empty(), "rejected save leaves no partial edits behind");
    }

    // ---- Verdict (same line format + return convention as the other harnesses)
    std::printf("[p2persist] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
