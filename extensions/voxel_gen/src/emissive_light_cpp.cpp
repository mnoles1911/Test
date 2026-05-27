#include "emissive_light_cpp.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <unordered_set>
#include <vector>

using namespace godot;

namespace {
constexpr int CHANNEL_TYPE = 0;

// Negatives-safe floor division — matches GD floori(a / b) when b > 0.
// Std C++ integer division truncates toward zero; for negative dividend
// we need to step one more toward -inf.
inline int floor_div(int a, int b) {
    int q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) {
        --q;
    }
    return q;
}

// 64-bit pack of a (cell_x, cell_y, cell_z) triple for std::unordered_set
// dedup. 21 bits per axis is enough for ±1M cells (~±5M voxels at cell=5)
// — far past any cell coord the EmissiveLightManager will ever see.
inline uint64_t pack_cell(int cx, int cy, int cz) {
    auto mask = [](int v) -> uint64_t {
        return static_cast<uint64_t>(static_cast<uint32_t>(v)) & 0x1FFFFFu;
    };
    return mask(cx) | (mask(cy) << 21) | (mask(cz) << 42);
}
inline int unpack21(uint64_t v) {
    // Sign-extend 21-bit field stored in low bits.
    const uint32_t raw = static_cast<uint32_t>(v & 0x1FFFFFu);
    if (raw & 0x100000u) {
        return static_cast<int>(raw | 0xFFE00000u);
    }
    return static_cast<int>(raw);
}
}  // namespace

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

// scan_region — bit-for-set-exact mirror of EmissiveReference.scan_region
// (itself a 1:1 port of EmissiveLightManager._scan_region's per-voxel
// classification + _has_air_neighbor gate). Returns:
//   "now_lit":         PackedInt32Array [g_x, g_y, g_z, mat_id, ...]
//   "affected_cells":  PackedInt32Array [c_x, c_y, c_z, ...] deduped
//
// GD-side responsibilities preserved (not ported):
//   * diff against _emissive_voxels for removals / mat_id changes
//   * compute coarse cells for removals (added to affected_cells in GD)
//   * _rebuild_cell + OmniLight3D streaming
Dictionary EmissiveLightCpp::scan_region(Variant p_buf,
                                          Vector3i p_min_v,
                                          Vector3i p_side) {
    Dictionary out;
    PackedInt32Array now_lit;
    PackedInt32Array affected_cells;

    if (p_buf.get_type() != Variant::OBJECT
            || p_side.x <= 0 || p_side.y <= 0 || p_side.z <= 0) {
        out["now_lit"] = now_lit;
        out["affected_cells"] = affected_cells;
        return out;
    }

    const int sx = p_side.x;
    const int sy = p_side.y;
    const int sz = p_side.z;
    const int sxsy = sx * sy;
    const int total = sx * sy * sz;

    // Read CHANNEL_TYPE for the whole region into a flat int array — the
    // air-neighbour check needs random access. One read per voxel, then
    // 6 in-memory lookups.
    std::vector<int32_t> mids(static_cast<size_t>(total), 0);
    for (int x = 0; x < sx; ++x) {
        for (int y = 0; y < sy; ++y) {
            for (int z = 0; z < sz; ++z) {
                Variant v = p_buf.call("get_voxel", x, y, z, CHANNEL_TYPE);
                if (v.get_type() != Variant::INT) {
                    continue;
                }
                const int32_t p = static_cast<int32_t>(static_cast<int64_t>(v));
                mids[static_cast<size_t>(x + y * sx + z * sxsy)] = p & 0xFF;
            }
        }
    }

    const int cell = _cell_size_voxels < 1 ? 1 : _cell_size_voxels;
    std::unordered_set<uint64_t> affected_set;

    for (int x = 0; x < sx; ++x) {
        for (int y = 0; y < sy; ++y) {
            for (int z = 0; z < sz; ++z) {
                const int idx = x + y * sx + z * sxsy;
                const int mid = mids[static_cast<size_t>(idx)];
                if (mid == 0) {
                    continue;
                }
                if (_emissive_ids.count(mid) == 0) {
                    continue;
                }
                bool has_air = false;
                if (x + 1 < sx && mids[static_cast<size_t>(idx + 1)] == 0) {
                    has_air = true;
                } else if (x - 1 >= 0 && mids[static_cast<size_t>(idx - 1)] == 0) {
                    has_air = true;
                } else if (y + 1 < sy && mids[static_cast<size_t>(idx + sx)] == 0) {
                    has_air = true;
                } else if (y - 1 >= 0 && mids[static_cast<size_t>(idx - sx)] == 0) {
                    has_air = true;
                } else if (z + 1 < sz && mids[static_cast<size_t>(idx + sxsy)] == 0) {
                    has_air = true;
                } else if (z - 1 >= 0 && mids[static_cast<size_t>(idx - sxsy)] == 0) {
                    has_air = true;
                }
                if (!has_air) {
                    continue;
                }
                const int gx = p_min_v.x + x;
                const int gy = p_min_v.y + y;
                const int gz = p_min_v.z + z;
                now_lit.append(gx);
                now_lit.append(gy);
                now_lit.append(gz);
                now_lit.append(mid);
                affected_set.insert(pack_cell(
                        floor_div(gx, cell),
                        floor_div(gy, cell),
                        floor_div(gz, cell)));
            }
        }
    }

    affected_cells.resize(static_cast<int>(affected_set.size()) * 3);
    int w = 0;
    for (uint64_t p : affected_set) {
        affected_cells.set(w++, unpack21(p));
        affected_cells.set(w++, unpack21(p >> 21));
        affected_cells.set(w++, unpack21(p >> 42));
    }

    out["now_lit"] = now_lit;
    out["affected_cells"] = affected_cells;
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
