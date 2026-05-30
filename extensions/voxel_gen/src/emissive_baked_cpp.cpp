#include "emissive_baked_cpp.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cstdint>
#include <deque>
#include <vector>

using namespace godot;

namespace {

constexpr int CHANNEL_TYPE = 0;

// 6-connected neighbour offsets — same order as the GD reference's
// NEIGHBOURS_6 const so first-visit-during-BFS is identical across
// implementations (parity-critical when two equal-length BFS paths
// reach the same cell with different colours).
struct CellOffset {
    int dx, dy, dz;
};
constexpr CellOffset NEIGHBOURS_6[6] = {
    { 1,  0,  0}, {-1,  0,  0},
    { 0,  1,  0}, { 0, -1,  0},
    { 0,  0,  1}, { 0,  0, -1},
};

inline int floor_div(int a, int b) {
    int q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) {
        --q;
    }
    return q;
}

inline void max_blend(uint8_t *out, int cell_idx, int r, int g, int b) {
    const int base = cell_idx * 4;
    if (out[base + 0] < r) out[base + 0] = static_cast<uint8_t>(r);
    if (out[base + 1] < g) out[base + 1] = static_cast<uint8_t>(g);
    if (out[base + 2] < b) out[base + 2] = static_cast<uint8_t>(b);
    const int max_chan = std::max(r, std::max(g, b));
    if (out[base + 3] < max_chan) out[base + 3] = static_cast<uint8_t>(max_chan);
}

struct BfsEntry {
    int cx, cy, cz;
    int r, g, b;
    int step;
};

}  // namespace

EmissiveBakedCpp::EmissiveBakedCpp() {}
EmissiveBakedCpp::~EmissiveBakedCpp() {}

// bake_light_volume — bit-exact mirror of EmissiveBakedReference.bake_light_volume.
//
// C++ owns both emitter discovery (scanning the bulk channel bytes for
// non-air voxels whose material is flagged emissive in the color table)
// AND the BFS propagation. The air-neighbour filter eliminates buried
// emissive voxels from seeding light — the fix for the "amber bleeds
// through ~5-15 voxels of rock to the surface" cosmetic bug the
// designer flagged 2026-05-27 when v1 of this autoload shipped.
//
// Boundary:
//   GD-side autoload owns the 3D texture upload, the shader globals,
//   the per-tick bake trigger, and the one-time color-table build from
//   VoxelMaterialRegistry. C++ does the per-voxel hot loop only.
PackedByteArray EmissiveBakedCpp::bake_light_volume(
        Variant p_buf,
        Vector3i p_volume_origin_v,
        int p_cell_size_voxels,
        int p_cells_per_axis,
        PackedByteArray p_mat_color_table,
        bool p_air_neighbor_filter,
        int p_max_steps,
        int p_falloff_q12) {
    (void)p_volume_origin_v;  // unused — buffer-local indexing maps directly to cell coords

    PackedByteArray out;
    const int n = std::clamp(p_cells_per_axis, 1, 256);
    const int k = std::max(p_cell_size_voxels, 1);
    const int steps_cap = std::clamp(p_max_steps, 1, n);
    const int falloff = std::clamp(p_falloff_q12, 1, 4096);
    const int n2 = n * n;
    const int n3 = n2 * n;
    out.resize(n3 * 4);

    if (p_buf.get_type() != Variant::OBJECT) {
        return out;
    }
    if (p_mat_color_table.size() < 256 * 4) {
        return out;
    }
    const uint8_t *table = p_mat_color_table.ptr();

    uint8_t *out_ptr = out.ptrw();
    std::fill(out_ptr, out_ptr + n3 * 4, uint8_t(0));

    // --- Pre-compute open[]: cell-centre voxel must be air. -------------
    Variant size_v = p_buf.call("get_size");
    if (size_v.get_type() != Variant::VECTOR3I) {
        return out;
    }
    const Vector3i buf_size = size_v;
    Variant ch_v = p_buf.call("get_channel_as_byte_array", CHANNEL_TYPE);
    if (ch_v.get_type() != Variant::PACKED_BYTE_ARRAY) {
        return out;
    }
    PackedByteArray ch_bytes = ch_v;
    const uint8_t *ch_ptr = ch_bytes.ptr();
    const int sx = buf_size.x;
    const int sy = buf_size.y;
    const int sz = buf_size.z;
    const int voxel_count = sx * sy * sz;
    if (voxel_count <= 0) {
        return out;
    }
    // Y-fastest layout: byte_index = (y + x*sy + z*sx*sy) * bpv. Low
    // byte = mat_id (mat_ids < 256). Same for 8-bit production
    // CHANNEL_TYPE (bpv=1) and 16-bit Zylann-default (bpv=2).
    const int bpv = ch_bytes.size() / voxel_count;
    if (bpv <= 0) {
        return out;
    }

    std::vector<uint8_t> open(static_cast<size_t>(n3), 0);
    const int half_k = k / 2;
    for (int cz = 0; cz < n; ++cz) {
        const int bz = cz * k + half_k;
        const bool z_in = (bz >= 0 && bz < sz);
        for (int cy = 0; cy < n; ++cy) {
            const int by = cy * k + half_k;
            const bool y_in = (by >= 0 && by < sy);
            for (int cx = 0; cx < n; ++cx) {
                const int bx = cx * k + half_k;
                const int idx = cx + cy * n + cz * n2;
                if (!y_in || !z_in || bx < 0 || bx >= sx) {
                    open[static_cast<size_t>(idx)] = 0;
                    continue;
                }
                const int byte_idx = (by + bx * sy + bz * sx * sy) * bpv;
                open[static_cast<size_t>(idx)] = (ch_ptr[byte_idx] == 0) ? 1 : 0;
            }
        }
    }

    // --- Discover emitters + BFS. ---------------------------------------
    //
    // One pass over the bulk channel bytes. For each non-air voxel:
    //   1. Look up entry in the 256-entry color table; skip if energy==0.
    //   2. If air-neighbour filter on: skip unless at least one 6-face
    //      neighbour is air (this is the "exposed only" gate that
    //      stops buried emissives from seeding light).
    //   3. Seed the containing cell with (channel * energy / 255).
    //   4. BFS from that cell through open[] cells, attenuating per step.
    //
    // Cross-emitter max-blend keeps the brightest contributor per cell.
    std::vector<uint8_t> visited(static_cast<size_t>(n3), 0);
    std::deque<BfsEntry> queue;

    auto buf_at = [&](int bx, int by, int bz) -> int {
        if (bx < 0 || by < 0 || bz < 0 || bx >= sx || by >= sy || bz >= sz) {
            return -1;
        }
        const int idx = (by + bx * sy + bz * sx * sy) * bpv;
        return ch_ptr[idx] & 0xFF;
    };

    for (int z = 0; z < sz; ++z) {
        for (int x = 0; x < sx; ++x) {
            const int row_base = (x * sy + z * sx * sy) * bpv;
            for (int y = 0; y < sy; ++y) {
                const int b = ch_ptr[row_base + y * bpv] & 0xFF;
                if (b == 0) {
                    continue;
                }
                const uint8_t *entry = &table[b * 4];
                const int energy = entry[3];
                if (energy == 0) {
                    continue;  // material not emissive
                }
                if (p_air_neighbor_filter) {
                    bool exposed = false;
                    if (buf_at(x + 1, y, z) == 0) exposed = true;
                    else if (buf_at(x - 1, y, z) == 0) exposed = true;
                    else if (buf_at(x, y + 1, z) == 0) exposed = true;
                    else if (buf_at(x, y - 1, z) == 0) exposed = true;
                    else if (buf_at(x, y, z + 1) == 0) exposed = true;
                    else if (buf_at(x, y, z - 1) == 0) exposed = true;
                    if (!exposed) {
                        continue;  // buried emissive — don't seed
                    }
                }
                const int cx0 = floor_div(x, k);
                const int cy0 = floor_div(y, k);
                const int cz0 = floor_div(z, k);
                if (cx0 < 0 || cy0 < 0 || cz0 < 0
                        || cx0 >= n || cy0 >= n || cz0 >= n) {
                    continue;
                }

                const int sr = std::clamp((entry[0] * energy) / 255, 0, 255);
                const int sg = std::clamp((entry[1] * energy) / 255, 0, 255);
                const int sb = std::clamp((entry[2] * energy) / 255, 0, 255);
                if (sr == 0 && sg == 0 && sb == 0) {
                    continue;
                }

                const int seed_idx = cx0 + cy0 * n + cz0 * n2;
                max_blend(out_ptr, seed_idx, sr, sg, sb);

                // Per-emitter visited[] reset (one-pass BFS).
                std::fill(visited.begin(), visited.end(), uint8_t(0));
                visited[static_cast<size_t>(seed_idx)] = 1;
                queue.clear();
                queue.push_back({cx0, cy0, cz0, sr, sg, sb, 0});
                while (!queue.empty()) {
                    const BfsEntry e = queue.front();
                    queue.pop_front();
                    if (e.step >= steps_cap) {
                        continue;
                    }
                    const int nr = (e.r * falloff) >> 12;
                    const int ng = (e.g * falloff) >> 12;
                    const int nb = (e.b * falloff) >> 12;
                    if (nr < 1 && ng < 1 && nb < 1) {
                        continue;
                    }
                    for (int o = 0; o < 6; ++o) {
                        const int ncx = e.cx + NEIGHBOURS_6[o].dx;
                        const int ncy = e.cy + NEIGHBOURS_6[o].dy;
                        const int ncz = e.cz + NEIGHBOURS_6[o].dz;
                        if (ncx < 0 || ncy < 0 || ncz < 0
                                || ncx >= n || ncy >= n || ncz >= n) {
                            continue;
                        }
                        const int nidx = ncx + ncy * n + ncz * n2;
                        if (visited[static_cast<size_t>(nidx)] != 0) {
                            continue;
                        }
                        if (open[static_cast<size_t>(nidx)] == 0) {
                            continue;
                        }
                        visited[static_cast<size_t>(nidx)] = 1;
                        max_blend(out_ptr, nidx, nr, ng, nb);
                        queue.push_back({ncx, ncy, ncz, nr, ng, nb, e.step + 1});
                    }
                }
            }
        }
    }

    return out;
}

void EmissiveBakedCpp::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD("bake_light_volume",
                 "buf", "volume_origin_v",
                 "cell_size_voxels", "cells_per_axis",
                 "mat_color_table", "air_neighbor_filter",
                 "max_steps", "falloff_q12"),
        &EmissiveBakedCpp::bake_light_volume);
}
