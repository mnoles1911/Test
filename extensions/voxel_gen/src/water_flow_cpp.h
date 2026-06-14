#pragma once

// WaterFlowCpp — C++ port of WaterFlowManager._process_water_settle's
// inner per-cell loop (the "find AIR cells inside the settle region that
// still touch water" scan).
//
// Why this loop:
//   The v2 connectivity fill drains its frontier at 12 cells/tick. The
//   settle sweep runs AFTER the frontier idles and scans up to
//   SETTLE_SCAN_PER_TICK=1024 cells per tick to catch holes the
//   bottom-up fill left behind. Each cell does up to seven
//   `tool.get_voxel` calls (centre + 6 neighbours), so a fully-active
//   settle sweep is ~7000 Variant crossings per tick (~28k/s at 4 Hz).
//   That's the heaviest water hot path right now.
//
// Boundary:
//   GD WaterFlowManager autoload still owns `tool.copy()` (one bulk
//   call into Zylann's voxel storage), the _bucket_push() queue, the
//   settle bookkeeping (settle_y cursor, settle_dirty flag, the
//   region AABB), and all calls into VoxelEditManager. C++ scans the
//   bulk-read channel bytes natively and returns the hit list.
//
// Pending + retry awareness:
//   The GD version skips cells that are in _pending_water OR at
//   FILL_MAX_RETRY. We pass those in as Dictionary[Vector3i, *] so the
//   port matches behaviour exactly — at the typical sizes (dozens of
//   entries each) the Variant Dict.has() call is cheap vs. building a
//   bitmap.
//
// Water identity (mirrors scripts/WaterMaterial.gd):
//   LEGACY_WATER_ID = 5
//   WATER_FLUID_BASE_ID = 16, WATER_LEVEL_COUNT = 8
//   so 5 OR (16..23) is water.
// Hardcoded here as constants so the inner loop branches without
// touching GD; the WaterMaterial.gd contract is locked and gated by
// the headless `wmat` selector.

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

class WaterFlowCpp : public godot::Resource {
    GDCLASS(WaterFlowCpp, godot::Resource)

public:
    WaterFlowCpp();
    ~WaterFlowCpp();

    // --- Settle-region scan (pure data; no SceneTree access) ----------
    //
    // Inputs:
    //   p_buf            — VoxelBuffer covering the settle region's bounding
    //                      box, CHANNEL_TYPE populated. Caller's
    //                      tool.copy(region_min, buf, type_mask) sizes it.
    //   p_region_min/max — inclusive voxel-coord bounds of the settle AABB.
    //   p_y_start        — current _settle_y cursor (>= region_min.y).
    //   p_y_end_max      — top of the sweep this tick: mini(region_max.y, sea_y).
    //   p_scan_cap       — SETTLE_SCAN_PER_TICK (1024 in production).
    //   p_player_pos     — world-space player position (metres).
    //   p_active_radius_m— ACTIVE_RADIUS_M + CHUNK_SIZE_M (caller adds the
    //                      one-chunk skirt the GD original uses).
    //   p_voxels_per_metre— 10.0 (the canonical scale).
    //   p_pending        — Dictionary[Vector3i, *] of cells already queued
    //                      for fill (key-existence test only).
    //   p_retry          — Dictionary[Vector3i, int] of retry counts;
    //                      cells with value >= p_fill_max_retry are skipped.
    //   p_fill_max_retry — FILL_MAX_RETRY (40 in production).
    //
    // Returns Dictionary:
    //   "hits":    PackedInt32Array stream [x, y, z, ...] — voxel coords
    //              the caller should _bucket_push(p, true).
    //   "next_y":  int — the y value the caller stores into _settle_y.
    //              (= the last y attempted, exclusive; matches the GD loop
    //              semantics "advance y after sweeping its XZ row".)
    //   "scanned": int — total cells scanned this call.
    godot::Dictionary scan_settle_region(
        godot::Variant p_buf,
        godot::Vector3i p_region_min,
        godot::Vector3i p_region_max,
        int p_y_start,
        int p_y_end_max,
        int p_scan_cap,
        godot::Vector3 p_player_pos,
        double p_active_radius_m,
        double p_voxels_per_metre,
        godot::Dictionary p_pending,
        godot::Dictionary p_retry,
        int p_fill_max_retry);

protected:
    static void _bind_methods();
};
