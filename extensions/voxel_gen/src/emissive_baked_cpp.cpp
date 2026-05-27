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
// implementations (a parity-critical detail when two equal-length BFS
// paths reach the same cell with different colours).
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

// BFS queue entry — kept tight so the std::deque doesn't dominate the cost.
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
// Performance notes:
//   * The hot path is the per-cell visit + 6-neighbour try inside BFS.
//   * Scratch vectors live for the whole call to avoid per-emitter alloc.
//     visited[] is reused across emitters by re-initialising in O(N^3); a
//     "visit generation counter" pattern would skip the re-init, but the
//     1MB pass is cache-friendly and trivial vs the BFS itself.
//   * std::deque chosen over a hand-rolled ring buffer — Godot's CI
//     toolchain handles it; visit cost dominates queue ops here.
PackedByteArray EmissiveBakedCpp::bake_light_volume(
        Variant p_buf,
        Vector3i p_volume_origin_v,
        int p_cell_size_voxels,
        int p_cells_per_axis,
        PackedInt32Array p_emitters,
        int p_max_steps,
        int p_falloff_q12) {
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
    // Zero the output buffer (PackedByteArray::resize doesn't guarantee
    // zero-init on grow-from-empty in all godot-cpp versions; explicit).
    uint8_t *out_ptr = out.ptrw();
    std::fill(out_ptr, out_ptr + n3 * 4, uint8_t(0));

    // --- Pre-compute open[]: cell-centre voxel must be air. ----------
    //
    // Single bulk Variant call to Zylann's get_channel_as_byte_array
    // pulls the whole CHANNEL_TYPE as a contiguous PackedByteArray.
    // Eliminates the per-voxel Variant cost that surfaced as the ELM
    // regression (47.6 ms peak vs 18 ms GD-native pre-port). For a
    // 256^3 production volume that is one call returning 16 MB of
    // bytes vs. 64^3 = 262144 individual calls.
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
    // Layout: Y-FASTEST (Zylann convention — confirmed by the
    // 2026-05-27 probe). Linear byte index =
    //   (y + x*sy + z*sx*sy) * bytes_per_voxel
    // Material id is the LOW byte at that offset (mat_ids are < 256
    // so this works for both 8-bit production CHANNEL_TYPE and 16-bit
    // Zylann-default channels used in tests).
    const int bpv = (voxel_count > 0) ? (ch_bytes.size() / voxel_count) : 1;
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

    // --- Per-emitter BFS. ---
    std::vector<uint8_t> visited(static_cast<size_t>(n3), 0);
    const int emitter_count = p_emitters.size() / 7;
    for (int i = 0; i < emitter_count; ++i) {
        const int base = i * 7;
        const int gx = p_emitters[base + 0];
        const int gy = p_emitters[base + 1];
        const int gz = p_emitters[base + 2];
        const int er = p_emitters[base + 3];
        const int eg = p_emitters[base + 4];
        const int eb = p_emitters[base + 5];
        const int energy = p_emitters[base + 6];

        const int dx = gx - p_volume_origin_v.x;
        const int dy = gy - p_volume_origin_v.y;
        const int dz = gz - p_volume_origin_v.z;
        const int cx0 = floor_div(dx, k);
        const int cy0 = floor_div(dy, k);
        const int cz0 = floor_div(dz, k);
        if (cx0 < 0 || cy0 < 0 || cz0 < 0 || cx0 >= n || cy0 >= n || cz0 >= n) {
            continue;
        }

        const int sr = std::clamp((er * energy) / 255, 0, 255);
        const int sg = std::clamp((eg * energy) / 255, 0, 255);
        const int sb = std::clamp((eb * energy) / 255, 0, 255);
        if (sr == 0 && sg == 0 && sb == 0) {
            continue;
        }

        const int seed_idx = cx0 + cy0 * n + cz0 * n2;
        max_blend(out_ptr, seed_idx, sr, sg, sb);

        // Re-init visited[] for this emitter (cheap memset over 1MB max).
        std::fill(visited.begin(), visited.end(), uint8_t(0));
        visited[static_cast<size_t>(seed_idx)] = 1;

        std::deque<BfsEntry> queue;
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

    return out;
}

void EmissiveBakedCpp::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD("bake_light_volume",
                 "buf", "volume_origin_v",
                 "cell_size_voxels", "cells_per_axis",
                 "emitters", "max_steps", "falloff_q12"),
        &EmissiveBakedCpp::bake_light_volume);
}
