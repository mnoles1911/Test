#include "distant_terrain_mesher.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <set>
#include <utility>
#include <vector>

using namespace godot;

namespace {

// --- Constants — 1:1 with scripts/_dev/SkirtBaker.gd ------------------
// QUAD_SIZE_M is a build_chunk parameter (p_quad_size_m), not a constant
// here, because the streaming system meshes each LOD ring at a different
// spacing. The parity harness passes 12.0 to match SkirtBaker.QUAD_SIZE_M.
const double Y_OFFSET_DOWN_M = 1.5;
const double SLOPE_TO_ROCK_THRESHOLD = 0.35;
const double SLOPE_TO_ROCK_BLEND_RANGE = 0.30;
const double SNOW_LINE_LATITUDE_OFFSET_M = 200.0;
const double CLIFF_THRESHOLD_M = 20.0;

// clampf — double clamp, mirrors GDScript clampf (float == double in GD).
inline double clamp_d(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// Mirrors SkirtBaker._compute_slope_at — the max absolute neighbour
// height difference (in voxels) across the 4 cardinal ±1-voxel samples.
double compute_slope_at(const HeightmapGeneratorBase *gen, int voxel_x, int voxel_z) {
    const int h = gen->compute_ground_y(voxel_x, voxel_z);
    const int hx_p = gen->compute_ground_y(voxel_x + 1, voxel_z);
    const int hx_m = gen->compute_ground_y(voxel_x - 1, voxel_z);
    const int hz_p = gen->compute_ground_y(voxel_x, voxel_z + 1);
    const int hz_m = gen->compute_ground_y(voxel_x, voxel_z - 1);
    int max_diff = 0;
    const int diffs[4] = {
        std::abs(hx_p - h), std::abs(hx_m - h),
        std::abs(hz_p - h), std::abs(hz_m - h)
    };
    for (int d : diffs) {
        if (d > max_diff) {
            max_diff = d;
        }
    }
    return static_cast<double>(max_diff);
}

}  // namespace

DistantTerrainMesher::DistantTerrainMesher() {}
DistantTerrainMesher::~DistantTerrainMesher() {}

Dictionary DistantTerrainMesher::build_chunk(
        const Ref<HeightmapGeneratorBase> &p_generator,
        Vector2 p_min_xz,
        Vector2 p_max_xz,
        double p_quad_size_m,
        double p_voxels_per_metre,
        double p_apron_depth) const {
    Dictionary out;
    const HeightmapGeneratorBase *gen = p_generator.ptr();
    if (gen == nullptr) {
        return out;
    }
    const double quad = p_quad_size_m;
    const double vpm = p_voxels_per_metre;
    if (quad <= 0.0 || vpm <= 0.0) {
        return out;
    }

    // Grid dimensions — mirrors SkirtBaker.bake_mesh.
    const double width = static_cast<double>(p_max_xz.x) - static_cast<double>(p_min_xz.x);
    const double depth = static_cast<double>(p_max_xz.y) - static_cast<double>(p_min_xz.y);
    const int quads_x = static_cast<int>(std::ceil(width / quad));
    const int quads_z = static_cast<int>(std::ceil(depth / quad));
    if (quads_x <= 0 || quads_z <= 0) {
        return out;
    }
    const int verts_x = quads_x + 1;
    const int verts_z = quads_z + 1;
    const int grid_count = verts_x * verts_z;

    const int sea_level_voxels = gen->get_sea_level_voxels();
    const int beach_y = gen->get_beach_y_threshold();
    // Min-neighbourhood sample stride — SkirtBaker: int(QUAD_SIZE_M * vpm).
    const int step = static_cast<int>(quad * vpm);

    // --- Pass 1: pre-sample the height grid + per-vertex colour --------
    std::vector<float> heights(static_cast<size_t>(grid_count), 0.0f);
    std::vector<Color> colors(static_cast<size_t>(grid_count));

    for (int zi = 0; zi < verts_z; ++zi) {
        for (int xi = 0; xi < verts_x; ++xi) {
            const int i = xi + zi * verts_x;
            const double world_x = static_cast<double>(p_min_xz.x) + static_cast<double>(xi) * quad;
            const double world_z = static_cast<double>(p_min_xz.y) + static_cast<double>(zi) * quad;
            const int voxel_x = static_cast<int>(world_x * vpm);
            const int voxel_z = static_cast<int>(world_z * vpm);

            // SKIRT_SAMPLE_MIN_NEIGHBOURHOOD — min of centre + 4 cardinals
            // so the flat skirt triangle sits at/below every voxel top.
            int ground_voxels = gen->compute_ground_y(voxel_x, voxel_z);
            const int n0 = gen->compute_ground_y(voxel_x + step, voxel_z);
            const int n1 = gen->compute_ground_y(voxel_x - step, voxel_z);
            const int n2 = gen->compute_ground_y(voxel_x, voxel_z + step);
            const int n3 = gen->compute_ground_y(voxel_x, voxel_z - step);
            ground_voxels = std::min(ground_voxels,
                std::min(std::min(n0, n1), std::min(n2, n3)));

            const double ground_world_y = static_cast<double>(ground_voxels) / vpm;
            heights[static_cast<size_t>(i)] =
                static_cast<float>(ground_world_y - Y_OFFSET_DOWN_M);

            // Vertex colour — 3 layered effects (elevation / slope / jitter).
            // 64-bit hash math: Godot ints are 64-bit, so the multiplies
            // must wrap at 64 bits, not 32 — use int64_t throughout.
            const int64_t hash_lo = (((static_cast<int64_t>(voxel_x) * INT64_C(374761393))
                ^ (static_cast<int64_t>(voxel_z) * INT64_C(668265263)))) & INT64_C(0xFFFF);
            const int64_t hash_hi = (((static_cast<int64_t>(voxel_x) * INT64_C(73856093))
                ^ (static_cast<int64_t>(voxel_z) * INT64_C(83492791)))) & INT64_C(0xFFFF);
            const double jitter_coarse = (static_cast<double>(hash_lo) / 65535.0 - 0.5) * 0.10;
            const double jitter_fine = (static_cast<double>(hash_hi) / 65535.0 - 0.5) * 0.06;
            const double jitter = jitter_coarse + jitter_fine;

            Color c_elev(0.0f, 0.0f, 0.0f, 1.0f);
            if (ground_voxels <= sea_level_voxels) {
                c_elev = Color(0.14f, 0.18f, 0.22f, 1.0f);
            } else if (ground_voxels <= beach_y) {
                c_elev = Color(0.78f, 0.72f, 0.58f, 1.0f);
            } else {
                const int elev_above_beach = ground_voxels - beach_y;
                const double latitude_factor = clamp_d(world_z / 2500.0, -1.0, 1.0);
                const int snow_line_offset_voxels = static_cast<int>(std::lround(
                    -latitude_factor * SNOW_LINE_LATITUDE_OFFSET_M * vpm));
                const double t1 = clamp_d(
                    static_cast<double>(elev_above_beach + snow_line_offset_voxels) / 4500.0,
                    0.0, 1.0);
                const Color c_lo(0.26f, 0.36f, 0.20f, 1.0f);
                const Color c_mid(0.62f, 0.60f, 0.56f, 1.0f);
                const Color c_hi(0.93f, 0.94f, 0.95f, 1.0f);
                if (t1 < 0.5) {
                    c_elev = c_lo.lerp(c_mid, static_cast<float>(t1 * 2.0));
                } else {
                    c_elev = c_mid.lerp(c_hi, static_cast<float>((t1 - 0.5) * 2.0));
                }
            }

            const double slope = compute_slope_at(gen, voxel_x, voxel_z);
            const Color rock_color(0.60f, 0.58f, 0.54f, 1.0f);
            const double slope_t = clamp_d(
                (slope - SLOPE_TO_ROCK_THRESHOLD) / SLOPE_TO_ROCK_BLEND_RANGE,
                0.0, 1.0);
            Color c = c_elev.lerp(rock_color, static_cast<float>(slope_t));
            c.r = static_cast<float>(clamp_d(static_cast<double>(c.r) + jitter, 0.0, 1.0));
            c.g = static_cast<float>(clamp_d(static_cast<double>(c.g) + jitter, 0.0, 1.0));
            c.b = static_cast<float>(clamp_d(static_cast<double>(c.b) + jitter, 0.0, 1.0));
            c.a = 1.0f;
            colors[static_cast<size_t>(i)] = c;
        }
    }

    // --- Pass 2: grid vertex positions + quad indices -----------------
    std::vector<Vector3> verts_v(static_cast<size_t>(grid_count));
    std::vector<int> idx_v;
    idx_v.reserve(static_cast<size_t>(quads_x) * quads_z * 6);
    for (int zi = 0; zi < verts_z; ++zi) {
        for (int xi = 0; xi < verts_x; ++xi) {
            const int i = xi + zi * verts_x;
            verts_v[static_cast<size_t>(i)] = Vector3(
                static_cast<float>(static_cast<double>(p_min_xz.x) + static_cast<double>(xi) * quad),
                heights[static_cast<size_t>(i)],
                static_cast<float>(static_cast<double>(p_min_xz.y) + static_cast<double>(zi) * quad));
        }
    }
    for (int zi = 0; zi < quads_z; ++zi) {
        for (int xi = 0; xi < quads_x; ++xi) {
            const int i00 = xi + zi * verts_x;
            const int i10 = (xi + 1) + zi * verts_x;
            const int i01 = xi + (zi + 1) * verts_x;
            const int i11 = (xi + 1) + (zi + 1) * verts_x;
            idx_v.push_back(i00);
            idx_v.push_back(i10);
            idx_v.push_back(i01);
            idx_v.push_back(i10);
            idx_v.push_back(i11);
            idx_v.push_back(i01);
        }
    }

    // --- Pass 3: per-vertex normals (height-field central differences) -
    std::vector<Vector3> norms_v(static_cast<size_t>(grid_count));
    for (int zi = 0; zi < verts_z; ++zi) {
        for (int xi = 0; xi < verts_x; ++xi) {
            const int i = xi + zi * verts_x;
            const float hx0 = heights[static_cast<size_t>(std::max(xi - 1, 0) + zi * verts_x)];
            const float hx1 = heights[static_cast<size_t>(std::min(xi + 1, verts_x - 1) + zi * verts_x)];
            const float hz0 = heights[static_cast<size_t>(xi + std::max(zi - 1, 0) * verts_x)];
            const float hz1 = heights[static_cast<size_t>(xi + std::min(zi + 1, verts_z - 1) * verts_x)];
            const double dx = (static_cast<double>(hx1) - static_cast<double>(hx0)) / (2.0 * quad);
            const double dz = (static_cast<double>(hz1) - static_cast<double>(hz0)) / (2.0 * quad);
            const Vector3 n(static_cast<float>(-dx), 1.0f, static_cast<float>(-dz));
            norms_v[static_cast<size_t>(i)] = n.normalized();
        }
    }

    // --- Pass 4: cliff-face geometry ----------------------------------
    // Where two adjacent grid vertices differ in height by more than
    // CLIFF_THRESHOLD_M, splice a vertical wall into the gap so the
    // silhouette reads as a sheer drop. Each interior edge is shared by
    // two quads, so dedupe via a sorted-index set — iteration order is
    // identical to SkirtBaker so the appended geometry matches.
    std::set<std::pair<int, int>> visited_edges;
    std::vector<Vector3> cliff_verts;
    std::vector<Vector3> cliff_normals;
    std::vector<Color> cliff_colors;
    std::vector<int> cliff_indices;
    const Color cliff_color(0.55f, 0.52f, 0.48f, 1.0f);

    auto maybe_add_cliff = [&](int i_a, int i_b) {
        const std::pair<int, int> key(std::min(i_a, i_b), std::max(i_a, i_b));
        if (visited_edges.count(key) != 0) {
            return;
        }
        visited_edges.insert(key);
        const float h_a = heights[static_cast<size_t>(i_a)];
        const float h_b = heights[static_cast<size_t>(i_b)];
        if (std::abs(static_cast<double>(h_a) - static_cast<double>(h_b)) < CLIFF_THRESHOLD_M) {
            return;
        }
        const Vector3 pos_a = verts_v[static_cast<size_t>(i_a)];
        const Vector3 pos_b = verts_v[static_cast<size_t>(i_b)];
        const double y_high = std::max(static_cast<double>(h_a), static_cast<double>(h_b));
        const double y_low = std::min(static_cast<double>(h_a), static_cast<double>(h_b));
        Vector2 edge_xz(
            static_cast<float>(static_cast<double>(pos_b.x) - static_cast<double>(pos_a.x)),
            static_cast<float>(static_cast<double>(pos_b.z) - static_cast<double>(pos_a.z)));
        if (edge_xz.length_squared() < 0.0001f) {
            return;
        }
        edge_xz = edge_xz.normalized();
        const Vector3 wall_normal(edge_xz.y, 0.0f, -edge_xz.x);
        const Vector3 v0(pos_a.x, static_cast<float>(y_high), pos_a.z);
        const Vector3 v1(pos_b.x, static_cast<float>(y_high), pos_b.z);
        const Vector3 v2(pos_a.x, static_cast<float>(y_low), pos_a.z);
        const Vector3 v3(pos_b.x, static_cast<float>(y_low), pos_b.z);
        const int base = static_cast<int>(cliff_verts.size());
        cliff_verts.push_back(v0);
        cliff_verts.push_back(v1);
        cliff_verts.push_back(v2);
        cliff_verts.push_back(v3);
        for (int k = 0; k < 4; ++k) {
            cliff_normals.push_back(wall_normal);
            cliff_colors.push_back(cliff_color);
        }
        cliff_indices.push_back(base + 0);
        cliff_indices.push_back(base + 1);
        cliff_indices.push_back(base + 2);
        cliff_indices.push_back(base + 1);
        cliff_indices.push_back(base + 3);
        cliff_indices.push_back(base + 2);
    };

    for (int zi = 0; zi < quads_z; ++zi) {
        for (int xi = 0; xi < quads_x; ++xi) {
            const int i00 = xi + zi * verts_x;
            const int i10 = (xi + 1) + zi * verts_x;
            const int i01 = xi + (zi + 1) * verts_x;
            const int i11 = (xi + 1) + (zi + 1) * verts_x;
            // Edge order: south, east, north, west — matches SkirtBaker.
            maybe_add_cliff(i00, i10);
            maybe_add_cliff(i10, i11);
            maybe_add_cliff(i11, i01);
            maybe_add_cliff(i01, i00);
        }
    }

    // --- Splice cliff geometry onto the grid arrays -------------------
    const int cliff_base = static_cast<int>(verts_v.size());
    verts_v.insert(verts_v.end(), cliff_verts.begin(), cliff_verts.end());
    norms_v.insert(norms_v.end(), cliff_normals.begin(), cliff_normals.end());
    colors.insert(colors.end(), cliff_colors.begin(), cliff_colors.end());
    for (int ci : cliff_indices) {
        idx_v.push_back(ci + cliff_base);
    }

    // --- Pass 5: perimeter skirt apron --------------------------------
    // A vertical curtain dropping p_apron_depth metres from every
    // chunk-border edge. Plugs the T-junction crack where this chunk
    // meets a neighbour at a different LOD — no neighbour-LOD knowledge
    // needed. The apron hangs below the surface; only its top edge is
    // ever near the visible terrain, and it carries the edge vertex
    // colour so any peek blends. p_apron_depth <= 0 disables it (used
    // for the apron-off parity check and for the innermost ring).
    // Purely additive — appended after the grid + cliff geometry so the
    // grid prefix stays byte-identical.
    if (p_apron_depth > 0.0) {
        const float depth = static_cast<float>(p_apron_depth);
        auto add_apron_edge = [&](int i_a, int i_b, const Vector3 &outward) {
            const Vector3 top_a = verts_v[static_cast<size_t>(i_a)];
            const Vector3 top_b = verts_v[static_cast<size_t>(i_b)];
            const Vector3 bot_a(top_a.x, top_a.y - depth, top_a.z);
            const Vector3 bot_b(top_b.x, top_b.y - depth, top_b.z);
            const Color col_a = colors[static_cast<size_t>(i_a)];
            const Color col_b = colors[static_cast<size_t>(i_b)];
            const int base = static_cast<int>(verts_v.size());
            verts_v.push_back(top_a);
            verts_v.push_back(top_b);
            verts_v.push_back(bot_a);
            verts_v.push_back(bot_b);
            for (int k = 0; k < 4; ++k) {
                norms_v.push_back(outward);
            }
            colors.push_back(col_a);
            colors.push_back(col_b);
            colors.push_back(col_a);
            colors.push_back(col_b);
            // Two triangles: (top_a, top_b, bot_a) + (top_b, bot_b, bot_a).
            idx_v.push_back(base + 0);
            idx_v.push_back(base + 1);
            idx_v.push_back(base + 2);
            idx_v.push_back(base + 1);
            idx_v.push_back(base + 3);
            idx_v.push_back(base + 2);
        };
        // South border (zi = 0) — outward -Z.
        for (int xi = 0; xi < quads_x; ++xi) {
            add_apron_edge(xi + 0 * verts_x, (xi + 1) + 0 * verts_x,
                Vector3(0.0f, 0.0f, -1.0f));
        }
        // North border (zi = verts_z - 1) — outward +Z.
        for (int xi = 0; xi < quads_x; ++xi) {
            add_apron_edge(xi + (verts_z - 1) * verts_x,
                (xi + 1) + (verts_z - 1) * verts_x,
                Vector3(0.0f, 0.0f, 1.0f));
        }
        // West border (xi = 0) — outward -X.
        for (int zi = 0; zi < quads_z; ++zi) {
            add_apron_edge(0 + zi * verts_x, 0 + (zi + 1) * verts_x,
                Vector3(-1.0f, 0.0f, 0.0f));
        }
        // East border (xi = verts_x - 1) — outward +X.
        for (int zi = 0; zi < quads_z; ++zi) {
            add_apron_edge((verts_x - 1) + zi * verts_x,
                (verts_x - 1) + (zi + 1) * verts_x,
                Vector3(1.0f, 0.0f, 0.0f));
        }
    }

    // --- Marshal std::vectors into Packed arrays ----------------------
    const int total_verts = static_cast<int>(verts_v.size());
    PackedVector3Array vertices;
    PackedVector3Array normals;
    PackedColorArray vert_colors;
    PackedInt32Array indices;
    vertices.resize(total_verts);
    normals.resize(total_verts);
    vert_colors.resize(total_verts);
    indices.resize(static_cast<int>(idx_v.size()));
    for (int i = 0; i < total_verts; ++i) {
        vertices.set(i, verts_v[static_cast<size_t>(i)]);
        normals.set(i, norms_v[static_cast<size_t>(i)]);
        vert_colors.set(i, colors[static_cast<size_t>(i)]);
    }
    for (int i = 0; i < static_cast<int>(idx_v.size()); ++i) {
        indices.set(i, idx_v[static_cast<size_t>(i)]);
    }

    out["vertices"] = vertices;
    out["normals"] = normals;
    out["colors"] = vert_colors;
    out["indices"] = indices;
    return out;
}

void DistantTerrainMesher::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD("build_chunk", "generator", "min_xz", "max_xz",
                 "quad_size_m", "voxels_per_metre", "apron_depth"),
        &DistantTerrainMesher::build_chunk);
}
