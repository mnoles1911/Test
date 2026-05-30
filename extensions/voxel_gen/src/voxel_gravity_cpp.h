#pragma once

// VoxelGravityCpp — C++ implementation of the VoxelGravityManager
// pure-data hot path: the 110k-cell buffer iteration, 6-connected
// anchor flood-fill, fall-behavior partition, and cluster-component
// BFS that together account for the 130 ms blast spikes in the
// 2026-05-26 capture.
//
// Boundary (see memory + branch plan):
//   * GD VoxelGravityManager autoload still owns ALL SceneTree work:
//     terrain lookup, VoxelTool.copy, NoEditZone registry queries,
//     queue_set_voxels_bulk write submission, VoxelDrop/FallingVoxelCluster
//     spawn. C++ does pure analysis only.
//   * Returns are PackedInt32Array streams (not nested Dictionaries) so
//     a 4096-voxel cluster doesn't pay the per-Variant marshalling tax.
//     GD unpacks once at the call site.
//
// Phase 0: header + stub. Real flood-fill + partition lands in Phase 2.
//
// godot-cpp can't subclass Zylann's VoxelBuffer — it's passed in as
// godot::Variant and accessed via Variant::call("get_voxel", ...), the
// same pattern HeightmapGeneratorBase::generate_block_into_buffer uses.

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <unordered_map>

class VoxelGravityCpp : public godot::Resource {
    GDCLASS(VoxelGravityCpp, godot::Resource)

public:
    VoxelGravityCpp();
    ~VoxelGravityCpp();

    // --- Snapshot setters (main thread, called per scan; cheap) -----------
    //
    // Fall-behavior table: material_id (int) -> VoxelMaterial.FallBehavior
    //   NEVER = 0, LOOSE = 1, PICKUP_DROP = 2, SOLID = 3
    // The C++ inner loop reads this with std::unordered_map lookup; no
    // VoxelMaterialRegistry crossings inside the hot loop.
    void set_fall_behavior_table(const godot::Dictionary &p_table);

    // NoEditZone anchor mask: side^3 bytes (1 = NoEditZone-anchored, 0 =
    // not). The GD autoload pre-resolves this on the main thread (the
    // registry has SceneTree-touching Area3D queries that can't run from
    // a worker). Empty PackedByteArray = "no zones in this bubble" — the
    // C++ skips the per-voxel check entirely (mirrors the existing
    // bubble_has_zones pre-flight).
    void set_noeditzone_anchor_mask(const godot::PackedByteArray &p_mask);

    // --- Main analysis call (pure; no SceneTree access) -------------------
    //
    // Inputs:
    //   p_buf          — Zylann VoxelBuffer holding the bubble (CHANNEL_TYPE
    //                    only). Passed as Variant; accessed via Variant::call.
    //   p_bubble_min_v — world-voxel coord of the bubble's minimum corner.
    //                    Currently unused by analysis (kept for symmetry
    //                    with the GD signature + future loose-landing
    //                    world-coord math); the caller still owns the
    //                    bubble-local -> world-voxel translation.
    //   p_side         — bubble side length in voxels (cube).
    //
    // Returns a Dictionary with:
    //   "loose":           PackedInt32Array, 7 ints per loose voxel:
    //                      [from_x, from_y, from_z, to_x, to_y, to_z, packed]
    //                      (bubble-local coords on both ends)
    //   "pickup":          PackedInt32Array, 4 ints per pickup voxel:
    //                      [x, y, z, packed] (bubble-local)
    //   "cluster_counts":  PackedInt32Array, voxel count per cluster
    //   "cluster_voxels":  PackedInt32Array, 4 ints per cluster voxel:
    //                      [x, y, z, packed]; segmented by cluster_counts
    //                      (cluster 0 takes the first counts[0]*4 entries,
    //                      cluster 1 the next counts[1]*4, etc.)
    //   "bubble_solid_count":      int (total solid cells found)
    //   "unanchored_cluster_count": int (sum of cluster_counts)
    godot::Dictionary analyze_bubble(godot::Variant p_buf,
                                     godot::Vector3i p_bubble_min_v,
                                     int p_side);

protected:
    static void _bind_methods();

private:
    std::unordered_map<int, int> _fall_table;
    godot::PackedByteArray _noeditzone_mask;
};
