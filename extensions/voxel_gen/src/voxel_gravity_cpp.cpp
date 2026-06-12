#include "voxel_gravity_cpp.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cstdint>
#include <vector>

using namespace godot;

// Zylann VoxelBuffer.CHANNEL_TYPE = 0. Hardcoded here for the same
// reason heightmap_generator_base.cpp hardcodes it: the only caller
// is the GD VoxelGravityManager autoload, which always reads TYPE.
namespace {
constexpr int CHANNEL_TYPE = 0;

// FallBehavior mirror — see scripts/VoxelMaterial.gd:169 and
// scripts/_dev/GravityReference.gd. The fall_table snapshot stores
// these integers; the reference and the port agree by value.
constexpr int FALL_LOOSE = 2;
constexpr int FALL_PICKUP_DROP = 4;

// R4 flora + D1 surface-detail pass-through range (mirrors
// scripts/FloraMaterial.gd PASSTHROUGH range + GravityReference: 24..28 =
// grass/flowers 24..26 PLUS pebbles/twigs 27..28). All are PASS-THROUGH AIR
// for the gravity analysis — a grass blade, flower, pebble or twig never
// anchors a structure and never rides a falling cluster. The read pass
// skips these ids exactly like the GD reference, so the two stay
// set-for-set identical under the `gravity` selector.
constexpr int PASSTHROUGH_BASE_ID = 24;
constexpr int PASSTHROUGH_COUNT = 5;   // 24..28

inline bool is_flora_type(int packed) {
    // Name kept for back-compat; covers the full pass-through decoration
    // range (flora + surface detail) by value, matching the GD side.
    const int t = packed & 0xFF;
    return t >= PASSTHROUGH_BASE_ID && t < PASSTHROUGH_BASE_ID + PASSTHROUGH_COUNT;
}
}  // namespace

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

// analyze_bubble — pure data partition + flood-fill + cluster BFS.
//
// Bit-for-set-exact mirror of scripts/_dev/GravityReference.gd
// analyze_bubble (which is itself a 1:1 port of VoxelGravityManager's
// _process_bubble inner loop, stripped of SceneTree access). The
// `gravity` headless selector diffs the two semantically — same
// loose / pickup / cluster sets, same bubble_solid_count.
//
// All scratch lives in std::vector<> sized by side^3 so the hot loop
// has no allocations after the read pass. The std::unordered_map
// fall_table lookup is the only hash-table touch per voxel.
Dictionary VoxelGravityCpp::analyze_bubble(Variant p_buf,
                                           Vector3i p_bubble_min_v,
                                           int p_side) {
    (void)p_bubble_min_v;  // unused by analysis; kept for signature symmetry

    Dictionary out;
    PackedInt32Array loose_stream;
    PackedInt32Array pickup_stream;
    PackedInt32Array cluster_counts;
    PackedInt32Array cluster_voxels;

    if (p_side <= 0 || p_buf.get_type() != Variant::OBJECT) {
        out["loose"] = loose_stream;
        out["pickup"] = pickup_stream;
        out["cluster_counts"] = cluster_counts;
        out["cluster_voxels"] = cluster_voxels;
        out["bubble_solid_count"] = 0;
        out["unanchored_cluster_count"] = 0;
        return out;
    }

    const int side = p_side;
    const int side2 = side * side;
    const int side3 = side2 * side;

    // --- Read pass: build packed[] indexed by (x + y*side + z*side*side).
    // Iteration order (x outer, y middle, z inner) matches the reference
    // so the cluster_indices order below also matches — keeps cluster_*
    // streams in the same per-position order for diagnostics, even though
    // the harness compares semantically.
    std::vector<int32_t> packed(static_cast<size_t>(side3), 0);
    int bubble_solid_count = 0;
    for (int x = 0; x < side; ++x) {
        for (int y = 0; y < side; ++y) {
            for (int z = 0; z < side; ++z) {
                Variant v = p_buf.call("get_voxel", x, y, z, CHANNEL_TYPE);
                if (v.get_type() != Variant::INT) {
                    continue;
                }
                const int32_t p = static_cast<int32_t>(static_cast<int64_t>(v));
                if ((p & 0xFF) == 0) {
                    continue;
                }
                if (is_flora_type(p)) {
                    continue;   // R4+D1: flora/pebbles/twigs are pass-through air for gravity
                }
                packed[static_cast<size_t>(x + y * side + z * side2)] = p;
                ++bubble_solid_count;
            }
        }
    }

    // --- Anchor identification: bottom-face seed + NoEditZone mask.
    std::vector<uint8_t> anchored(static_cast<size_t>(side3), 0);
    std::vector<int> frontier;
    frontier.reserve(static_cast<size_t>(bubble_solid_count));
    const bool has_mask = _noeditzone_mask.size() == side3;
    for (int x = 0; x < side; ++x) {
        for (int y = 0; y < side; ++y) {
            for (int z = 0; z < side; ++z) {
                const int idx = x + y * side + z * side2;
                if (packed[static_cast<size_t>(idx)] == 0) {
                    continue;
                }
                bool anch = false;
                if (y == 0) {
                    anch = true;
                } else if (has_mask && _noeditzone_mask[idx] != 0) {
                    anch = true;
                }
                if (anch) {
                    anchored[static_cast<size_t>(idx)] = 1;
                    frontier.push_back(idx);
                }
            }
        }
    }

    // --- Flood-fill anchors through solids (6-connected).
    // Stack-based (pop_back) to mirror the GD reference's queue treatment.
    while (!frontier.empty()) {
        const int idx = frontier.back();
        frontier.pop_back();
        const int x = idx % side;
        const int y = (idx / side) % side;
        const int z = idx / side2;
        auto try_anchor = [&](int ni) {
            if (packed[static_cast<size_t>(ni)] == 0
                    || anchored[static_cast<size_t>(ni)]) {
                return;
            }
            anchored[static_cast<size_t>(ni)] = 1;
            frontier.push_back(ni);
        };
        if (x + 1 < side) try_anchor(idx + 1);
        if (x - 1 >= 0)   try_anchor(idx - 1);
        if (y + 1 < side) try_anchor(idx + side);
        if (y - 1 >= 0)   try_anchor(idx - side);
        if (z + 1 < side) try_anchor(idx + side2);
        if (z - 1 >= 0)   try_anchor(idx - side2);
    }

    // --- Partition unanchored by fall_behavior. Iteration order matches
    // the reference (x, y, z).
    std::vector<int> loose_indices;
    std::vector<int> pickup_indices;
    std::vector<int> cluster_indices;
    for (int x = 0; x < side; ++x) {
        for (int y = 0; y < side; ++y) {
            for (int z = 0; z < side; ++z) {
                const int idx = x + y * side + z * side2;
                if (packed[static_cast<size_t>(idx)] == 0
                        || anchored[static_cast<size_t>(idx)]) {
                    continue;
                }
                const int mat_id = packed[static_cast<size_t>(idx)] & 0xFF;
                const auto it = _fall_table.find(mat_id);
                const int fall = (it == _fall_table.end()) ? 0 : it->second;
                if (fall == FALL_LOOSE) {
                    loose_indices.push_back(idx);
                } else if (fall == FALL_PICKUP_DROP) {
                    pickup_indices.push_back(idx);
                } else {
                    // NEVER + SOLID (and any other) -> cluster path.
                    cluster_indices.push_back(idx);
                }
            }
        }
    }

    // --- LOOSE column-fall. Sort by (y, x, z) lex to match the reference.
    if (!loose_indices.empty()) {
        std::sort(loose_indices.begin(), loose_indices.end(),
                [side, side2](int a, int b) {
                    const int ay = (a / side) % side;
                    const int by = (b / side) % side;
                    if (ay != by) return ay < by;
                    const int ax = a % side;
                    const int bx = b % side;
                    if (ax != bx) return ax < bx;
                    return (a / side2) < (b / side2);
                });
        std::vector<uint8_t> loose_landings(static_cast<size_t>(side3), 0);
        for (int idx : loose_indices) {
            const int x = idx % side;
            const int y = (idx / side) % side;
            const int z = idx / side2;
            int landing_y = y;
            while (landing_y > 0) {
                const int below = x + (landing_y - 1) * side + z * side2;
                if (anchored[static_cast<size_t>(below)]
                        || loose_landings[static_cast<size_t>(below)]) {
                    break;
                }
                --landing_y;
            }
            if (landing_y == y) {
                continue;
            }
            const int landing_idx = x + landing_y * side + z * side2;
            loose_stream.append(x);
            loose_stream.append(y);
            loose_stream.append(z);
            loose_stream.append(x);
            loose_stream.append(landing_y);
            loose_stream.append(z);
            loose_stream.append(packed[static_cast<size_t>(idx)]);
            loose_landings[static_cast<size_t>(landing_idx)] = 1;
        }
    }

    // --- PICKUP stream.
    for (int idx : pickup_indices) {
        const int x = idx % side;
        const int y = (idx / side) % side;
        const int z = idx / side2;
        pickup_stream.append(x);
        pickup_stream.append(y);
        pickup_stream.append(z);
        pickup_stream.append(packed[static_cast<size_t>(idx)]);
    }

    // --- Cluster connected-component BFS. Only walks into cluster-bound
    // cells (NEVER/SOLID), matching the reference's
    // unanchored_cluster-only neighbour gate.
    std::vector<uint8_t> visited(static_cast<size_t>(side3), 0);
    int unanchored_cluster_count = 0;
    for (int seed : cluster_indices) {
        if (visited[static_cast<size_t>(seed)]) {
            continue;
        }
        std::vector<int> queue;
        queue.push_back(seed);
        visited[static_cast<size_t>(seed)] = 1;
        int count = 0;

        auto try_step = [&](int ni) {
            if (visited[static_cast<size_t>(ni)]
                    || packed[static_cast<size_t>(ni)] == 0
                    || anchored[static_cast<size_t>(ni)]) {
                return;
            }
            const int nmid = packed[static_cast<size_t>(ni)] & 0xFF;
            const auto it = _fall_table.find(nmid);
            const int nf = (it == _fall_table.end()) ? 0 : it->second;
            // Cluster path takes NEVER/SOLID only; LOOSE + PICKUP_DROP
            // were already routed away in the partition.
            if (nf == FALL_LOOSE || nf == FALL_PICKUP_DROP) {
                return;
            }
            visited[static_cast<size_t>(ni)] = 1;
            queue.push_back(ni);
        };

        while (!queue.empty()) {
            const int cur = queue.back();
            queue.pop_back();
            const int x = cur % side;
            const int y = (cur / side) % side;
            const int z = cur / side2;
            ++count;
            ++unanchored_cluster_count;
            cluster_voxels.append(x);
            cluster_voxels.append(y);
            cluster_voxels.append(z);
            cluster_voxels.append(packed[static_cast<size_t>(cur)]);
            if (x + 1 < side) try_step(cur + 1);
            if (x - 1 >= 0)   try_step(cur - 1);
            if (y + 1 < side) try_step(cur + side);
            if (y - 1 >= 0)   try_step(cur - side);
            if (z + 1 < side) try_step(cur + side2);
            if (z - 1 >= 0)   try_step(cur - side2);
        }
        cluster_counts.append(count);
    }

    out["loose"] = loose_stream;
    out["pickup"] = pickup_stream;
    out["cluster_counts"] = cluster_counts;
    out["cluster_voxels"] = cluster_voxels;
    out["bubble_solid_count"] = bubble_solid_count;
    out["unanchored_cluster_count"] = unanchored_cluster_count;
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
