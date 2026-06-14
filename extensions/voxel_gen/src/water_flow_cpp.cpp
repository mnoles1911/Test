#include "water_flow_cpp.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cstdint>
#include <vector>

using namespace godot;

namespace {
constexpr int CHANNEL_TYPE = 0;
constexpr int CHANNEL_DATA5 = 5;

// Mirrors scripts/WaterMaterial.gd. Locked contract — gated by the
// headless `wmat` selector.
constexpr int LEGACY_WATER_ID = 5;
constexpr int WATER_FLUID_BASE_ID = 16;
constexpr int WATER_LEVEL_COUNT = 8;

// Mirrors scripts/WaterByteCodec.gd (locked by the `codec` selector).
constexpr int WATER_SOURCE_BIT = 0x10;

inline bool is_water_type(int t) {
    return t == LEGACY_WATER_ID
        || (t >= WATER_FLUID_BASE_ID && t < WATER_FLUID_BASE_ID + WATER_LEVEL_COUNT);
}

// Six face-neighbour offsets — the same order GD's _process_water_settle
// uses (-Y, +X, -X, +Z, -Z, +Y). Iteration order doesn't change which
// cells become hits (it's an OR — any neighbour water triggers a hit
// and we break out) but matches GD for any diagnostics that print
// neighbour ordering.
struct VOff {
    int dx, dy, dz;
};
constexpr VOff NEIGHBOURS[6] = {
    { 0, -1,  0},
    { 1,  0,  0},
    {-1,  0,  0},
    { 0,  0,  1},
    { 0,  0, -1},
    { 0,  1,  0},
};
}  // namespace

WaterFlowCpp::WaterFlowCpp() {}
WaterFlowCpp::~WaterFlowCpp() {}

Dictionary WaterFlowCpp::scan_settle_region(
        Variant p_buf,
        Vector3i p_region_min,
        Vector3i p_region_max,
        int p_y_start,
        int p_y_end_max,
        int p_scan_cap,
        Vector3 p_player_pos,
        double p_active_radius_m,
        double p_voxels_per_metre,
        Dictionary p_pending,
        Dictionary p_retry,
        int p_fill_max_retry) {
    Dictionary out;
    PackedInt32Array hits;
    int scanned = 0;
    int next_y = p_y_start;

    if (p_buf.get_type() != Variant::OBJECT) {
        out["hits"] = hits;
        out["next_y"] = next_y;
        out["scanned"] = 0;
        return out;
    }

    Variant size_v = p_buf.call("get_size");
    if (size_v.get_type() != Variant::VECTOR3I) {
        out["hits"] = hits;
        out["next_y"] = next_y;
        out["scanned"] = 0;
        return out;
    }
    const Vector3i buf_size = size_v;
    Variant ch_v = p_buf.call("get_channel_as_byte_array", CHANNEL_TYPE);
    if (ch_v.get_type() != Variant::PACKED_BYTE_ARRAY) {
        out["hits"] = hits;
        out["next_y"] = next_y;
        out["scanned"] = 0;
        return out;
    }
    PackedByteArray ch_bytes = ch_v;
    const uint8_t *ch_ptr = ch_bytes.ptr();
    const int sx = buf_size.x;
    const int sy = buf_size.y;
    const int sz = buf_size.z;
    const int voxel_count = sx * sy * sz;
    if (voxel_count <= 0) {
        out["hits"] = hits;
        out["next_y"] = next_y;
        out["scanned"] = 0;
        return out;
    }
    // Y-fastest layout (probed 2026-05-27): byte_index =
    //   (y + x*sy + z*sx*sy) * bytes_per_voxel
    // Material id is the low byte (mat_ids < 256).
    const int bpv = ch_bytes.size() / voxel_count;
    if (bpv <= 0) {
        out["hits"] = hits;
        out["next_y"] = next_y;
        out["scanned"] = 0;
        return out;
    }

    // W2 (finite-water track): the settle scan is part of the OCEAN
    // subsystem, so a hit requires the touching water to be INFINITE
    // (DATA5 source bit set). DATA5 == 0 on a water TYPE is legacy
    // water and conservatively counts as source. The caller's copy()
    // must include CHANNEL_DATA5 in its mask; if the channel is absent
    // (empty array) every water neighbour decodes as legacy-source,
    // which reproduces the pre-W2 behaviour.
    Variant d5_v = p_buf.call("get_channel_as_byte_array", CHANNEL_DATA5);
    PackedByteArray d5_bytes;
    if (d5_v.get_type() == Variant::PACKED_BYTE_ARRAY) {
        d5_bytes = d5_v;
    }
    const uint8_t *d5_ptr = d5_bytes.is_empty() ? nullptr : d5_bytes.ptr();
    const int bpv5 = d5_bytes.is_empty() ? 0 : (d5_bytes.size() / voxel_count);

    // Convert region coords -> buffer-local coords. Buffer minimum
    // corner sits at region_min; out-of-buffer cells are treated as
    // "solid" (the GD original's behaviour through tool.get_voxel
    // outside the loaded area is "non-water solid" by default — block).
    auto buf_get = [&](int rx, int ry, int rz) -> int {
        const int bx = rx - p_region_min.x;
        const int by = ry - p_region_min.y;
        const int bz = rz - p_region_min.z;
        if (bx < 0 || by < 0 || bz < 0 || bx >= sx || by >= sy || bz >= sz) {
            return -1;  // sentinel: out of buffer => treat as solid
        }
        const int idx = (by + bx * sy + bz * sx * sy) * bpv;
        return ch_ptr[idx] & 0xFF;
    };
    auto d5_get = [&](int rx, int ry, int rz) -> int {
        if (d5_ptr == nullptr || bpv5 <= 0) {
            return 0;  // channel not copied => everything reads legacy (source)
        }
        const int bx = rx - p_region_min.x;
        const int by = ry - p_region_min.y;
        const int bz = rz - p_region_min.z;
        if (bx < 0 || by < 0 || bz < 0 || bx >= sx || by >= sy || bz >= sz) {
            return 0;
        }
        const int idx = (by + bx * sy + bz * sx * sy) * bpv5;
        return d5_ptr[idx] & 0xFF;
    };

    // Pre-square the radius — distance compare in metres^2 vs the
    // squared distance (voxels * VOXEL_SIZE_M). Avoids per-cell sqrt
    // and matches the GD original's effective threshold:
    //   _voxel_center_world(p).distance_to(_player_pos) > active_radius_m
    // is equivalent to dist_sq > active_radius_m^2.
    const double radius_sq = p_active_radius_m * p_active_radius_m;
    const double voxel_size_m = (p_voxels_per_metre > 0.0) ? (1.0 / p_voxels_per_metre) : (1.0 / 10.0);

    int y = p_y_start;
    while (y <= p_y_end_max && scanned < p_scan_cap) {
        for (int x = p_region_min.x; x <= p_region_max.x; ++x) {
            for (int z = p_region_min.z; z <= p_region_max.z; ++z) {
                ++scanned;
                // World-space distance check (cell-centre).
                const double wx = (static_cast<double>(x) + 0.5) * voxel_size_m;
                const double wy = (static_cast<double>(y) + 0.5) * voxel_size_m;
                const double wz = (static_cast<double>(z) + 0.5) * voxel_size_m;
                const double dx = wx - static_cast<double>(p_player_pos.x);
                const double dy = wy - static_cast<double>(p_player_pos.y);
                const double dz = wz - static_cast<double>(p_player_pos.z);
                if (dx * dx + dy * dy + dz * dz > radius_sq) {
                    continue;
                }
                const Vector3i p(x, y, z);
                if (p_pending.has(p)) {
                    continue;
                }
                // retry cap: skip if retry[p] >= fill_max_retry
                if (p_retry.has(p)) {
                    Variant rv = p_retry[p];
                    if (rv.get_type() == Variant::INT
                            && static_cast<int>(static_cast<int64_t>(rv)) >= p_fill_max_retry) {
                        continue;
                    }
                }
                // Centre voxel: must be AIR (mat_id 0). Solid or water
                // both disqualify (water is fine; we only re-fill air).
                const int t = buf_get(x, y, z);
                if (t != 0) {
                    continue;
                }
                // Any face-neighbour SOURCE water -> hit. Finite water
                // (DATA5 level set, source bit clear) must not feed the
                // ocean re-fill — see design/WATER_FINITE_SIM_PLAN.md.
                bool touches = false;
                for (int o = 0; o < 6; ++o) {
                    const int nx = x + NEIGHBOURS[o].dx;
                    const int ny = y + NEIGHBOURS[o].dy;
                    const int nz = z + NEIGHBOURS[o].dz;
                    const int nt = buf_get(nx, ny, nz);
                    if (nt < 0) {
                        continue;  // out of buffer -> treat as non-water
                    }
                    if (!is_water_type(nt)) {
                        continue;
                    }
                    const int nd5 = d5_get(nx, ny, nz);
                    if (nd5 == 0 || (nd5 & WATER_SOURCE_BIT) != 0) {
                        touches = true;
                        break;
                    }
                }
                if (touches) {
                    hits.append(x);
                    hits.append(y);
                    hits.append(z);
                }
            }
        }
        ++y;
        next_y = y;
        if (scanned >= p_scan_cap) {
            break;
        }
    }

    out["hits"] = hits;
    out["next_y"] = next_y;
    out["scanned"] = scanned;
    return out;
}

void WaterFlowCpp::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD("scan_settle_region",
                 "buf", "region_min", "region_max",
                 "y_start", "y_end_max", "scan_cap",
                 "player_pos", "active_radius_m", "voxels_per_metre",
                 "pending", "retry", "fill_max_retry"),
        &WaterFlowCpp::scan_settle_region);
}
