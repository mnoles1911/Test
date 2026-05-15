#include "water_chunk_mesher.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <array>
#include <unordered_map>
#include <vector>

using namespace godot;

// Match VoxelEditManager / WaterFlowManager constants. Hard-coded here
// to avoid a Variant round-trip per call into GD globals.
static constexpr int CHUNK_SIZE_VOXELS = 16;
static constexpr int CELLS_PER_CHUNK = CHUNK_SIZE_VOXELS
        * CHUNK_SIZE_VOXELS * CHUNK_SIZE_VOXELS;
static constexpr double VOXELS_PER_METER = 6.0;

// Zylann VoxelBuffer channel index. DATA5 carries the packed water
// byte (level | source_bit | tick) — see scripts/WaterByteCodec.gd.
static constexpr int CHANNEL_DATA5 = 5;

// ArrayMesh subdivision per quad — matches the GD implementation's
// SUBDIV=4 so the wave shader has interior verts to displace. A 2-tri
// quad would only displace at corners and look flat.
static constexpr int SUBDIV = 4;
static constexpr int VERTS_PER_QUAD = (SUBDIV + 1) * (SUBDIV + 1);
static constexpr int INDICES_PER_QUAD = SUBDIV * SUBDIV * 6;

// Greedy-merge rectangle in chunk-local voxel coordinates. min/max are
// inclusive on min, exclusive on max — i.e. width = max_x - min_x in
// voxels. y_voxels_local is the top face Y (0..CHUNK_SIZE_VOXELS).
struct Quad {
    int min_x;
    int max_x;
    int min_z;
    int max_z;
    int top_y_voxels_local;  // top face Y in voxels (= cell Y + 1)
};

WaterChunkMesherCpp::WaterChunkMesherCpp() {}
WaterChunkMesherCpp::~WaterChunkMesherCpp() {}

// Greedy 2D run-merge over a 16×16 bitmap. Mirrors the GD
// _greedy_merge_into_quads function. Emits one Quad per merged
// rectangle, all sharing the same top_y_voxels_local.
static void greedy_merge(const std::array<uint8_t, CHUNK_SIZE_VOXELS * CHUNK_SIZE_VOXELS> &p_bitmap,
                         int p_top_y_voxels_local,
                         std::vector<Quad> &r_out) {
    std::array<uint8_t, CHUNK_SIZE_VOXELS * CHUNK_SIZE_VOXELS> work = p_bitmap;
    for (int z = 0; z < CHUNK_SIZE_VOXELS; ++z) {
        for (int x = 0; x < CHUNK_SIZE_VOXELS; ++x) {
            if (work[x * CHUNK_SIZE_VOXELS + z] == 0) {
                continue;
            }
            // Extend right along this Z-row.
            int end_x = x;
            while (end_x + 1 < CHUNK_SIZE_VOXELS
                   && work[(end_x + 1) * CHUNK_SIZE_VOXELS + z] == 1) {
                ++end_x;
            }
            // Extend down — every cell in [x..end_x] must be set on
            // row z+1, z+2, …
            int end_z = z;
            while (end_z + 1 < CHUNK_SIZE_VOXELS) {
                bool row_ok = true;
                for (int xi = x; xi <= end_x; ++xi) {
                    if (work[xi * CHUNK_SIZE_VOXELS + (end_z + 1)] == 0) {
                        row_ok = false;
                        break;
                    }
                }
                if (!row_ok) {
                    break;
                }
                ++end_z;
            }
            // Mark consumed.
            for (int xi = x; xi <= end_x; ++xi) {
                for (int zi = z; zi <= end_z; ++zi) {
                    work[xi * CHUNK_SIZE_VOXELS + zi] = 0;
                }
            }
            Quad q;
            q.min_x = x;
            q.max_x = end_x + 1;
            q.min_z = z;
            q.max_z = end_z + 1;
            q.top_y_voxels_local = p_top_y_voxels_local;
            r_out.push_back(q);
        }
    }
}

// Build the verts/normals/uvs/indices arrays for one quad and append
// to the running arrays. Each quad becomes a (SUBDIV+1)² vertex grid
// and SUBDIV²×2 triangles. Local-space verts (chunk-relative); the
// MeshInstance3D global_position lives at chunk world origin.
static void emit_quad_arrays(const Quad &q,
                             PackedVector3Array &verts,
                             PackedVector3Array &normals,
                             PackedVector2Array &uvs,
                             PackedInt32Array &indices) {
    const double inv = 1.0 / VOXELS_PER_METER;
    const double min_x_m = double(q.min_x) * inv;
    const double max_x_m = double(q.max_x) * inv;
    const double min_z_m = double(q.min_z) * inv;
    const double max_z_m = double(q.max_z) * inv;
    const double y_m = double(q.top_y_voxels_local) * inv;
    const int v_start = verts.size();
    const Vector3 up_normal = Vector3(0.0f, 1.0f, 0.0f);

    for (int j = 0; j <= SUBDIV; ++j) {
        const double tz = double(j) / double(SUBDIV);
        const double z = min_z_m + (max_z_m - min_z_m) * tz;
        for (int i = 0; i <= SUBDIV; ++i) {
            const double tx = double(i) / double(SUBDIV);
            const double x = min_x_m + (max_x_m - min_x_m) * tx;
            verts.push_back(Vector3(float(x), float(y_m), float(z)));
            normals.push_back(up_normal);
            uvs.push_back(Vector2(float(tx), float(tz)));
        }
    }
    // Two triangles per cell. CCW from above so +Y faces win cull_back.
    for (int j = 0; j < SUBDIV; ++j) {
        for (int i = 0; i < SUBDIV; ++i) {
            const int top_left = v_start + j * (SUBDIV + 1) + i;
            const int top_right = top_left + 1;
            const int bot_left = top_left + (SUBDIV + 1);
            const int bot_right = bot_left + 1;
            indices.push_back(top_left);
            indices.push_back(bot_left);
            indices.push_back(top_right);
            indices.push_back(top_right);
            indices.push_back(bot_left);
            indices.push_back(bot_right);
        }
    }
}

Ref<ArrayMesh> WaterChunkMesherCpp::build_chunk_mesh(Variant p_buffer,
                                                     Vector3i p_chunk) {
    (void)p_chunk;  // reserved for future diagnostics
    Ref<ArrayMesh> empty;
    if (p_buffer.get_type() != Variant::OBJECT) {
        return empty;
    }

    // ---- Uniform fast path -------------------------------------------------
    // is_uniform is an O(1) plugin call on Zylann's VoxelBuffer. Most
    // sea-level-row chunks are either uniform 0 (above-water terrain —
    // no water voxels) or uniform SOURCE_BYTE (open ocean — every voxel
    // is full source). The first case skips meshing entirely; the
    // second emits one full-chunk top quad without per-voxel scanning.
    const bool is_uniform_data5 = bool(p_buffer.call("is_uniform", CHANNEL_DATA5));
    std::vector<Quad> quads;
    if (is_uniform_data5) {
        const int uniform_byte = int(p_buffer.call(
                "get_voxel", 0, 0, 0, CHANNEL_DATA5));
        if (uniform_byte == 0) {
            return empty;  // uniform air — dry chunk
        }
        Quad q;
        q.min_x = 0;
        q.max_x = CHUNK_SIZE_VOXELS;
        q.min_z = 0;
        q.max_z = CHUNK_SIZE_VOXELS;
        q.top_y_voxels_local = CHUNK_SIZE_VOXELS;  // top face of top cell
        quads.push_back(q);
    } else {
        // ---- Per-column topmost-water search --------------------------------
        // For each (x, z), walk Y top-to-bottom; first nonzero DATA5
        // byte wins. Worst case (sea-level chunk with no water) is
        // 4096 reads; ocean chunks usually hit at y=15 immediately
        // (256 reads).
        std::array<int8_t, CHUNK_SIZE_VOXELS * CHUNK_SIZE_VOXELS> column_top;
        column_top.fill(-1);
        bool any_water = false;
        for (int x = 0; x < CHUNK_SIZE_VOXELS; ++x) {
            for (int z = 0; z < CHUNK_SIZE_VOXELS; ++z) {
                int8_t top = -1;
                for (int y = CHUNK_SIZE_VOXELS - 1; y >= 0; --y) {
                    const int byte = int(p_buffer.call(
                            "get_voxel", x, y, z, CHANNEL_DATA5));
                    if (byte > 0) {
                        top = int8_t(y);
                        any_water = true;
                        break;
                    }
                }
                column_top[x * CHUNK_SIZE_VOXELS + z] = top;
            }
        }
        if (!any_water) {
            return empty;
        }

        // ---- Group columns by top_y, then greedy-merge per group ------------
        // Distinct top_y_local values are typically 1–4 per chunk
        // (heightmap-aligned ocean surface is mostly one value;
        // partial-fill cells from flow sim add a few more). Small map
        // ok.
        std::unordered_map<int, std::array<uint8_t, CHUNK_SIZE_VOXELS * CHUNK_SIZE_VOXELS>> groups;
        for (int x = 0; x < CHUNK_SIZE_VOXELS; ++x) {
            for (int z = 0; z < CHUNK_SIZE_VOXELS; ++z) {
                const int8_t top = column_top[x * CHUNK_SIZE_VOXELS + z];
                if (top < 0) {
                    continue;
                }
                auto it = groups.find(int(top));
                if (it == groups.end()) {
                    std::array<uint8_t, CHUNK_SIZE_VOXELS * CHUNK_SIZE_VOXELS> bmp{};
                    bmp[x * CHUNK_SIZE_VOXELS + z] = 1;
                    groups.emplace(int(top), bmp);
                } else {
                    it->second[x * CHUNK_SIZE_VOXELS + z] = 1;
                }
            }
        }
        for (const auto &kv : groups) {
            const int top_y_voxels_local = kv.first + 1;  // top face Y
            greedy_merge(kv.second, top_y_voxels_local, quads);
        }
    }

    if (quads.empty()) {
        return empty;
    }

    // ---- Build the surface arrays ------------------------------------------
    PackedVector3Array verts;
    PackedVector3Array normals;
    PackedVector2Array uvs;
    PackedInt32Array indices;
    const int reserve_verts = int(quads.size()) * VERTS_PER_QUAD;
    const int reserve_indices = int(quads.size()) * INDICES_PER_QUAD;
    verts.resize(0);  // PackedArrays start empty; no reserve API. Push grows.
    (void)reserve_verts;
    (void)reserve_indices;
    for (const Quad &q : quads) {
        emit_quad_arrays(q, verts, normals, uvs, indices);
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_NORMAL] = normals;
    arrays[Mesh::ARRAY_TEX_UV] = uvs;
    arrays[Mesh::ARRAY_INDEX] = indices;

    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    if (!verts.is_empty()) {
        mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    }
    return mesh;
}

void WaterChunkMesherCpp::_bind_methods() {
    ClassDB::bind_method(
            D_METHOD("build_chunk_mesh", "buffer", "chunk"),
            &WaterChunkMesherCpp::build_chunk_mesh);
}
