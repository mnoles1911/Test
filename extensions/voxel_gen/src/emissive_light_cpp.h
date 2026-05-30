#pragma once

// EmissiveLightCpp — C++ implementation of the EmissiveLightManager
// per-region scan: identify emissive voxels with at least one air
// face-neighbour (the _has_air_neighbor gate) and report them plus the
// coarse cluster cells they touch.
//
// Boundary:
//   * GD EmissiveLightManager autoload still owns ALL SceneTree work:
//     terrain lookup, VoxelTool.copy, OmniLight3D node creation/free,
//     light streaming around the player, camera lookup,
//     _resolve_terrain. C++ does pure pixel-classification only.
//   * Returns are PackedInt32Array streams (not nested Dicts).
//
// Phase 0: header + stub. Real classification + cell-of math lands in
// Phase 4 (gated by the headless `emissive` selector).
//
// VoxelBuffer is passed as godot::Variant and accessed via
// Variant::call("get_voxel", ...) — same pattern as
// HeightmapGeneratorBase::generate_block_into_buffer.

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <unordered_set>

class EmissiveLightCpp : public godot::Resource {
    GDCLASS(EmissiveLightCpp, godot::Resource)

public:
    EmissiveLightCpp();
    ~EmissiveLightCpp();

    // --- Snapshot setters (main thread, infrequent) -----------------------
    //
    // The set of material ids the registry has flagged emission_enabled.
    // The GD autoload calls this once at _ready, then any time the
    // registry changes. C++ holds it in an unordered_set so per-voxel
    // lookup inside the scan loop is O(1).
    void set_emissive_material_ids(const godot::PackedInt32Array &p_ids);

    // Coarse-grid cell size in voxels — mirrors
    // EmissiveLightManager.cell_size_voxels (default 5). Used to compute
    // the "affected_cells" output (negatives-safe floor-divide of the
    // voxel-grid coord). Setting <1 clamps to 1.
    void set_cell_size_voxels(int p_value);

    // --- Main scan call (pure; no SceneTree access) -----------------------
    //
    // Inputs:
    //   p_buf  — Zylann VoxelBuffer for the region (CHANNEL_TYPE only).
    //   p_min_v — world voxel-grid coord of the buffer's minimum corner.
    //   p_side — buffer dimensions in voxels (x/y/z).
    //
    // Returns a Dictionary with:
    //   "now_lit":         PackedInt32Array, 4 ints per emissive cell:
    //                      [g_x, g_y, g_z, mat_id]
    //                      (g_* are world voxel-grid coords; mat_id is the
    //                      material id; only voxels with at least one air
    //                      face-neighbour in-buffer are emitted)
    //   "affected_cells":  PackedInt32Array, 3 ints per affected cell:
    //                      [c_x, c_y, c_z] (coarse-grid cell coord)
    //                      Deduplicated — caller can rebuild each cell once.
    godot::Dictionary scan_region(godot::Variant p_buf,
                                  godot::Vector3i p_min_v,
                                  godot::Vector3i p_side);

protected:
    static void _bind_methods();

private:
    std::unordered_set<int> _emissive_ids;
    int _cell_size_voxels = 5;
};
