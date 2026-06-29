// VoxelGravity.cpp — implementation of the engine-agnostic gravity flood-fill.
//
// This is a faithful line-by-line port of scripts/_dev/GravityReference.gd
// (the Godot parity source of truth) and its godot-cpp twin
// extensions/voxel_gen/src/voxel_gravity_cpp.cpp. The ONLY differences from the
// Godot reference are the unavoidable language ones, called out inline:
//   * We index a flat std::vector<int32_t> by (x + y*side + z*side2) instead of
//     a Dictionary[Vector3i], the same trick the cpp extension uses to avoid
//     hash-table churn. Iteration order is still (x outer, y mid, z inner) so
//     the partition + cluster order matches the reference for diagnostics.
//   * The flood-fills are EXPLICIT stack loops (push/pop_back) rather than
//     anything recursive — mirrors the GD `Array` used as a stack via pop_back,
//     and avoids blowing the C call stack on a tall tree.
//   * The LOOSE column pass sorts by (y, x, z) lexicographically, the exact
//     total ordering the reference pins down so both languages agree.

#include "Core/VoxelGravity.h"

#include <algorithm>

namespace mira {

// 6-connected neighbour offsets, same set + order as the Godot NEIGHBOURS_6.
// (Order doesn't change the connectivity result, but we keep it identical so a
// step-by-step trace lines up with the reference if anyone ever needs it.)
namespace {
const Vec3i kNeighbours6[6] = {
    { 1, 0, 0}, {-1, 0, 0},
    { 0, 1, 0}, { 0,-1, 0},
    { 0, 0, 1}, { 0, 0,-1},
};
} // namespace

GravityResult analyze_bubble(
    int side,
    const std::function<int32_t(const Vec3i&)>& get_packed,
    const std::function<int(int)>&              fall_of,
    const std::function<bool(const Vec3i&)>&    is_anchor_mask) {

    GravityResult out;
    if (side <= 0) {
        return out;
    }

    const int side2 = side * side;
    const int side3 = side2 * side;
    const bool has_mask = static_cast<bool>(is_anchor_mask);

    // Small index helpers so the flat-array math reads like the GD coord math.
    auto idx_of = [side, side2](int x, int y, int z) {
        return x + y * side + z * side2;
    };

    // --- Read pass: build packed[] indexed flat. Iterate (x, y, z) outer-to-
    // inner exactly like GravityReference so every downstream order matches.
    // Skip air (low byte 0) and flora/decoration (pass-through air for gravity).
    std::vector<int32_t> packed(static_cast<size_t>(side3), 0);
    int bubble_solid_count = 0;
    for (int x = 0; x < side; ++x) {
        for (int y = 0; y < side; ++y) {
            for (int z = 0; z < side; ++z) {
                const int32_t p = get_packed(Vec3i(x, y, z));
                if ((p & 0xFF) == 0) {
                    continue;   // air
                }
                if (IsFloraType(p)) {
                    continue;   // R4 + D1: grass/flowers/pebbles/twigs are
                                // pass-through air — never anchor, never cluster
                }
                packed[static_cast<size_t>(idx_of(x, y, z))] = p;
                ++bubble_solid_count;
            }
        }
    }

    // --- Anchor identification: bottom-face seed + NoEditZone mask.
    // y==0 is the ground floor of the bubble; anything on it is attached. A
    // NoEditZone-flagged cell is also treated as always-attached terrain.
    std::vector<uint8_t> anchored(static_cast<size_t>(side3), 0);
    std::vector<int>     frontier;
    frontier.reserve(static_cast<size_t>(bubble_solid_count));
    for (int x = 0; x < side; ++x) {
        for (int y = 0; y < side; ++y) {
            for (int z = 0; z < side; ++z) {
                const int idx = idx_of(x, y, z);
                if (packed[static_cast<size_t>(idx)] == 0) {
                    continue;
                }
                bool anch = false;
                if (y == 0) {
                    anch = true;
                } else if (has_mask && is_anchor_mask(Vec3i(x, y, z))) {
                    anch = true;
                }
                if (anch) {
                    anchored[static_cast<size_t>(idx)] = 1;
                    frontier.push_back(idx);
                }
            }
        }
    }

    // --- Flood-fill anchors through solids (6-connected). Stack-based
    // (pop the back) to mirror the GD reference's frontier.pop_back().
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
        // Bounds-guard each axis (the flat index can't wrap a cube face).
        if (x + 1 < side) try_anchor(idx + 1);
        if (x - 1 >= 0)   try_anchor(idx - 1);
        if (y + 1 < side) try_anchor(idx + side);
        if (y - 1 >= 0)   try_anchor(idx - side);
        if (z + 1 < side) try_anchor(idx + side2);
        if (z - 1 >= 0)   try_anchor(idx - side2);
    }

    // --- Partition unanchored solids by fall_behavior. Same (x,y,z) order.
    std::vector<int> loose_indices;
    std::vector<int> pickup_indices;
    std::vector<int> cluster_indices;
    for (int x = 0; x < side; ++x) {
        for (int y = 0; y < side; ++y) {
            for (int z = 0; z < side; ++z) {
                const int idx = idx_of(x, y, z);
                if (packed[static_cast<size_t>(idx)] == 0
                        || anchored[static_cast<size_t>(idx)]) {
                    continue;
                }
                const int mat_id = packed[static_cast<size_t>(idx)] & 0xFF;
                const int fall   = fall_of ? fall_of(mat_id) : FALL_NEVER;
                if (fall == FALL_LOOSE) {
                    loose_indices.push_back(idx);
                } else if (fall == FALL_PICKUP_DROP) {
                    pickup_indices.push_back(idx);
                } else {
                    // NEVER + SOLID (and anything else) -> cluster path.
                    cluster_indices.push_back(idx);
                }
            }
        }
    }

    // --- LOOSE column-fall. Sort by (y, x, z) lex so lower cells settle first
    // and the reference + this port process columns in identical order.
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
        // Tracks where already-fallen loose cells came to rest, so a later
        // cell in the same column stacks on top of them rather than passing
        // through.
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
                continue;   // already resting — no move emitted
            }
            const int landing_idx = x + landing_y * side + z * side2;
            LooseMove m;
            m.from   = Vec3i(x, y, z);
            m.to     = Vec3i(x, landing_y, z);
            m.packed = packed[static_cast<size_t>(idx)];
            out.loose.push_back(m);
            loose_landings[static_cast<size_t>(landing_idx)] = 1;
        }
    }

    // --- PICKUP stream (order = partition order = x,y,z lex).
    for (int idx : pickup_indices) {
        const int x = idx % side;
        const int y = (idx / side) % side;
        const int z = idx / side2;
        PickupDrop d;
        d.pos    = Vec3i(x, y, z);
        d.packed = packed[static_cast<size_t>(idx)];
        out.pickup.push_back(d);
    }

    // --- Cluster connected-component BFS. Only walks into cluster-bound cells
    // (NEVER/SOLID); LOOSE + PICKUP were already routed away in the partition,
    // so the neighbour gate re-checks fall_behavior to keep them out. Stack-
    // based (pop_back) to match the reference's queue treatment.
    std::vector<uint8_t> visited(static_cast<size_t>(side3), 0);
    int unanchored_cluster_count = 0;
    for (int seed : cluster_indices) {
        if (visited[static_cast<size_t>(seed)]) {
            continue;
        }
        std::vector<int> stack;
        stack.push_back(seed);
        visited[static_cast<size_t>(seed)] = 1;
        int count = 0;

        auto try_step = [&](int ni) {
            if (visited[static_cast<size_t>(ni)]
                    || packed[static_cast<size_t>(ni)] == 0
                    || anchored[static_cast<size_t>(ni)]) {
                return;
            }
            const int nmid = packed[static_cast<size_t>(ni)] & 0xFF;
            const int nf   = fall_of ? fall_of(nmid) : FALL_NEVER;
            // Cluster path takes NEVER/SOLID only.
            if (nf == FALL_LOOSE || nf == FALL_PICKUP_DROP) {
                return;
            }
            visited[static_cast<size_t>(ni)] = 1;
            stack.push_back(ni);
        };

        while (!stack.empty()) {
            const int cur = stack.back();
            stack.pop_back();
            const int x = cur % side;
            const int y = (cur / side) % side;
            const int z = cur / side2;
            ++count;
            ++unanchored_cluster_count;
            ClusterVoxel cv;
            cv.pos    = Vec3i(x, y, z);
            cv.packed = packed[static_cast<size_t>(cur)];
            out.cluster_voxels.push_back(cv);
            if (x + 1 < side) try_step(cur + 1);
            if (x - 1 >= 0)   try_step(cur - 1);
            if (y + 1 < side) try_step(cur + side);
            if (y - 1 >= 0)   try_step(cur - side);
            if (z + 1 < side) try_step(cur + side2);
            if (z - 1 >= 0)   try_step(cur - side2);
        }
        out.cluster_counts.push_back(count);
    }

    out.bubble_solid_count       = bubble_solid_count;
    out.unanchored_cluster_count = unanchored_cluster_count;
    return out;
}

// ---------------------------------------------------------------------------
// sever_follow_bfs — port of SeverFollowLib.continue_bfs.
// ---------------------------------------------------------------------------
SeverFollowResult sever_follow_bfs(
    const Vec3i&                                box_size,
    const std::vector<Vec3i>&                   seeds,
    const std::function<bool(const Vec3i&)>&    is_solid_at,
    const std::function<int32_t(const Vec3i&)>& get_packed,
    int                                         max_voxels) {

    SeverFollowResult out;

    auto in_box = [&](const Vec3i& p) {
        return p.x >= 0 && p.y >= 0 && p.z >= 0
            && p.x < box_size.x && p.y < box_size.y && p.z < box_size.z;
    };

    // visited set keyed by box-local coord (the std::hash<Vec3i> from MiraVec.h).
    std::unordered_map<Vec3i, bool> visited;
    std::vector<Vec3i> stack;

    // Seed pass. Seeds arrive in box-local coords already (the GD version takes
    // absolute coords + ext_min and subtracts; the Core pushes that translation
    // out to the caller so this function stays coordinate-system agnostic).
    for (const Vec3i& s : seeds) {
        if (!in_box(s) || visited.count(s)) {
            continue;
        }
        visited[s] = true;
        stack.push_back(s);
    }

    while (!stack.empty()) {
        const Vec3i loc = stack.back();
        stack.pop_back();

        if (!is_solid_at(loc)) {
            continue;   // air / water / flora — nothing to carry, mirrors the
                        // GD branches that skip type 0, water, and passthrough
        }

        // Edge checks BEFORE accepting — an edge hit poisons the whole
        // extension (conservative abort). Flag it and stop.
        if (loc.x == 0 || loc.x == box_size.x - 1
                || loc.z == 0 || loc.z == box_size.z - 1) {
            out.touched_side = true;
            break;
        }
        if (loc.y == box_size.y - 1) {
            out.touched_top = true;
            break;
        }

        ClusterVoxel cv;
        cv.pos    = loc;
        cv.packed = get_packed(loc);
        out.voxels.push_back(cv);
        if (static_cast<int>(out.voxels.size()) > max_voxels) {
            // Over budget — caller aborts either way; report via touched_top
            // (same channel the GD version uses for the budget bail).
            out.touched_top = true;
            break;
        }

        for (const Vec3i& d : kNeighbours6) {
            const Vec3i nb = loc + d;
            if (nb.y < 0) {
                continue;   // never grow back DOWN past the bubble roof
            }
            if (!in_box(nb) || visited.count(nb)) {
                continue;
            }
            visited[nb] = true;
            stack.push_back(nb);
        }
    }

    return out;
}

} // namespace mira
