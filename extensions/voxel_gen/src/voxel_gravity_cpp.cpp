#include "voxel_gravity_cpp.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

VoxelGravityCpp::VoxelGravityCpp() {}
VoxelGravityCpp::~VoxelGravityCpp() {}

void VoxelGravityCpp::set_fall_behavior_table(const Dictionary &p_table) {
    _fall_table.clear();
    Array keys = p_table.keys();
    for (int i = 0; i < keys.size(); ++i) {
        Variant k = keys[i];
        Variant v = p_table[k];
        if (k.get_type() != Variant::INT || v.get_type() != Variant::INT) {
            continue;
        }
        _fall_table[static_cast<int>(static_cast<int64_t>(k))] =
                static_cast<int>(static_cast<int64_t>(v));
    }
}

void VoxelGravityCpp::set_noeditzone_anchor_mask(const PackedByteArray &p_mask) {
    _noeditzone_mask = p_mask;
}

Dictionary VoxelGravityCpp::analyze_bubble(Variant p_buf,
                                           Vector3i p_bubble_min_v,
                                           int p_side) {
    // PHASE 0: stub. Real buffer iteration + 6-connected anchor flood-fill
    // + fall-behavior partition + cluster-component BFS lands in Phase 2,
    // gated by the headless `gravity` selector against the committed
    // baseline. Returns the full key set with empty streams so call-site
    // plumbing can be wired in Phase 0 without crashing.
    (void)p_buf;
    (void)p_bubble_min_v;
    (void)p_side;

    Dictionary out;
    out["loose"] = PackedInt32Array();
    out["pickup"] = PackedInt32Array();
    out["cluster_counts"] = PackedInt32Array();
    out["cluster_voxels"] = PackedInt32Array();
    out["bubble_solid_count"] = 0;
    out["unanchored_cluster_count"] = 0;
    out["phase"] = "stub";
    return out;
}

void VoxelGravityCpp::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_fall_behavior_table", "table"),
                         &VoxelGravityCpp::set_fall_behavior_table);
    ClassDB::bind_method(D_METHOD("set_noeditzone_anchor_mask", "mask"),
                         &VoxelGravityCpp::set_noeditzone_anchor_mask);
    ClassDB::bind_method(D_METHOD("analyze_bubble", "buf", "bubble_min_v", "side"),
                         &VoxelGravityCpp::analyze_bubble);
}
