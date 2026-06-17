// WorldEditStore.h — the authoritative "what the player changed" journal.
//
// THE BIG IDEA (plain English): the unedited world is free — the EXR + generator
// recreate any chunk on demand. The ONLY thing we must remember is what the player
// changed: dug a tunnel, placed a block, left a pool. This store is that memory.
// It is the single authoritative thing the save system persists; everything else
// is rebuilt. (See design/UE5_WORLD_STREAMING_PLAN.md §1/§7.)
//
// HOW IT'S ORGANISED:
//   * Edits are bucketed into REGION TILES (REGION_SIZE voxels per side in X/Z) so
//     each region saves to its own small file — only regions the player touched
//     ever get one. The disk byte format is RegionFormat's delta log (varint +
//     CRC); this store just owns the in-memory buckets and the apply/replay logic.
//   * Within a region, edits are keyed by voxel coordinate with LATEST-WINS
//     semantics: editing the same voxel twice keeps only the final value, so the
//     journal stays compact (one entry per changed voxel, not per change event)
//     and replay order doesn't matter (each voxel is set once to its final state).
//
// USAGE (in AVoxelWorld):
//   * on carve/place:      store.record(voxel, type, water)
//   * after generating a chunk-column from the EXR: store.apply_region(region, bm)
//     replays that region's edits on top, so the dig you made is back.
//   * on save:             for each dirty region, encode region_edit_list() and
//                          write it; mark_clean().
//   * on load:             decode a region file and load_region() it.
//
// Pure C++17, no engine headers — harness-testable.

#pragma once

#include <cstdint>
#include <vector>
#include <unordered_map>

#include "Core/MiraVec.h"        // Vec3i
#include "Core/ChunkCoords.h"    // coords::floor_div
#include "Core/RegionFormat.h"   // region::VoxelEdit
#include "Core/Brickmap.h"       // Brickmap (replay target)

namespace mira {

class WorldEditStore {
public:
    // Voxels per region tile side (X and Z). 512 vox = 51.2 m. A region holds ALL
    // Y for its X/Z footprint (edits are sparse, so tall mines are still cheap).
    static constexpr int REGION_SIZE = 512;

    // The region tile a voxel belongs to. Y is always 0 (XZ tiling); the region's
    // file covers the whole vertical column of that footprint.
    static Vec3i region_of(const Vec3i& v) {
        return Vec3i(coords::floor_div(v.x, REGION_SIZE), 0,
                     coords::floor_div(v.z, REGION_SIZE));
    }

    // ---- Recording edits ----
    void record(const Vec3i& voxel, uint8_t type, uint8_t water) {
        const Vec3i rc = region_of(voxel);
        Region& r = regions_[rc];
        r.edits[voxel] = region::VoxelEdit{voxel, type, water};
        r.dirty = true;
    }
    void record(const region::VoxelEdit& e) { record(e.voxel, e.type, e.water); }

    // ---- Queries ----
    bool   has_region(const Vec3i& rc) const { return regions_.count(rc) > 0; }
    size_t region_count() const { return regions_.size(); }
    size_t total_edits() const {
        size_t n = 0;
        for (const auto& kv : regions_) n += kv.second.edits.size();
        return n;
    }
    // The number of distinct edited voxels in a region (0 if absent).
    size_t region_edit_count(const Vec3i& rc) const {
        auto it = regions_.find(rc);
        return it == regions_.end() ? 0 : it->second.edits.size();
    }

    // All region coords currently held (for iterating saves).
    std::vector<Vec3i> region_coords() const {
        std::vector<Vec3i> out;
        out.reserve(regions_.size());
        for (const auto& kv : regions_) out.push_back(kv.first);
        return out;
    }

    // Region coords whose edits changed since the last mark_clean (for saving).
    std::vector<Vec3i> dirty_regions() const {
        std::vector<Vec3i> out;
        for (const auto& kv : regions_) if (kv.second.dirty) out.push_back(kv.first);
        return out;
    }
    void mark_clean(const Vec3i& rc) {
        auto it = regions_.find(rc);
        if (it != regions_.end()) it->second.dirty = false;
    }

    // ---- Serialization bridge ----
    // The region's edits as a flat list (for region::encode_delta_log). Order is
    // unspecified but irrelevant (latest-wins already collapsed duplicates).
    std::vector<region::VoxelEdit> region_edit_list(const Vec3i& rc) const {
        std::vector<region::VoxelEdit> out;
        auto it = regions_.find(rc);
        if (it == regions_.end()) return out;
        out.reserve(it->second.edits.size());
        for (const auto& kv : it->second.edits) out.push_back(kv.second);
        return out;
    }

    // Load a region's edits (e.g. just decoded from disk) into the store. Merges
    // with latest-wins, so loading then editing keeps the new value. Loaded data
    // is NOT marked dirty (it already matches disk).
    void load_region(const Vec3i& rc, const std::vector<region::VoxelEdit>& edits) {
        Region& r = regions_[rc];
        for (const region::VoxelEdit& e : edits) r.edits[e.voxel] = e;
        // (don't clear dirty if it was already set by prior records)
    }

    // ---- Replay ----
    // Apply one region's edits onto a brickmap (after generating it from the EXR).
    void apply_region(const Vec3i& rc, Brickmap& bm) const {
        auto it = regions_.find(rc);
        if (it == regions_.end()) return;
        for (const auto& kv : it->second.edits) {
            const region::VoxelEdit& e = kv.second;
            bm.set_type(e.voxel, e.type);
            bm.set_water(e.voxel, e.water);
        }
    }
    // Apply only the edits whose X/Z fall in [x0,x1) x [z0,z1) (any Y). This is
    // what a chunk-column replays AFTER it generates from the EXR, so generation
    // can't overwrite the player's edits and neighbouring columns aren't touched.
    // Only the overlapping region buckets are scanned, so it stays cheap.
    void apply_xz_box(int x0, int x1, int z0, int z1, Brickmap& bm) const {
        if (x1 <= x0 || z1 <= z0) return;
        const int rx0 = coords::floor_div(x0,     REGION_SIZE);
        const int rx1 = coords::floor_div(x1 - 1, REGION_SIZE);
        const int rz0 = coords::floor_div(z0,     REGION_SIZE);
        const int rz1 = coords::floor_div(z1 - 1, REGION_SIZE);
        for (int rx = rx0; rx <= rx1; ++rx)
        for (int rz = rz0; rz <= rz1; ++rz) {
            auto it = regions_.find(Vec3i(rx, 0, rz));
            if (it == regions_.end()) continue;
            for (const auto& kv : it->second.edits) {
                const region::VoxelEdit& e = kv.second;
                if (e.voxel.x >= x0 && e.voxel.x < x1 &&
                    e.voxel.z >= z0 && e.voxel.z < z1) {
                    bm.set_type(e.voxel, e.type);
                    bm.set_water(e.voxel, e.water);
                }
            }
        }
    }

    // Apply every region (used for small worlds / tests).
    void apply_all(Brickmap& bm) const {
        for (const auto& kv : regions_) apply_region(kv.first, bm);
    }

    // Drop everything (new world / clear).
    void clear() { regions_.clear(); }

private:
    struct Region {
        std::unordered_map<Vec3i, region::VoxelEdit> edits; // voxel -> final state
        bool dirty = false;                                 // changed since last save
    };
    std::unordered_map<Vec3i, Region> regions_;
};

} // namespace mira
