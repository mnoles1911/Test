#include "emissive_light_cpp.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

EmissiveLightCpp::EmissiveLightCpp() {}
EmissiveLightCpp::~EmissiveLightCpp() {}

void EmissiveLightCpp::set_emissive_material_ids(const PackedInt32Array &p_ids) {
    _emissive_ids.clear();
    for (int i = 0; i < p_ids.size(); ++i) {
        _emissive_ids.insert(p_ids[i]);
    }
}

void EmissiveLightCpp::set_cell_size_voxels(int p_value) {
    _cell_size_voxels = p_value < 1 ? 1 : p_value;
}

Dictionary EmissiveLightCpp::scan_region(Variant p_buf,
                                          Vector3i p_min_v,
                                          Vector3i p_side) {
    // PHASE 0: stub. Real per-voxel classification + _has_air_neighbor
    // gate + coarse-cell dedupe lands in Phase 4, gated by the headless
    // `emissive` selector against the committed baseline. Returns the
    // full key set with empty streams so the GD call site can be plumbed
    // in Phase 0 without crashing.
    (void)p_buf;
    (void)p_min_v;
    (void)p_side;

    Dictionary out;
    out["now_lit"] = PackedInt32Array();
    out["affected_cells"] = PackedInt32Array();
    out["phase"] = "stub";
    return out;
}

void EmissiveLightCpp::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_emissive_material_ids", "ids"),
                         &EmissiveLightCpp::set_emissive_material_ids);
    ClassDB::bind_method(D_METHOD("set_cell_size_voxels", "value"),
                         &EmissiveLightCpp::set_cell_size_voxels);
    ClassDB::bind_method(D_METHOD("scan_region", "buf", "min_v", "side"),
                         &EmissiveLightCpp::scan_region);
}
