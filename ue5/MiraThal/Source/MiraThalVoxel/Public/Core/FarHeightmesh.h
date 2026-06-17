// FarHeightmesh.h — the whole-map "vista" mesh (T3 of the streaming plan).
//
// WHAT THIS IS (plain English):
// The near world is real 10 cm voxel cubes, but you can only afford those for a
// few hundred metres around the player. To see the WHOLE 5 km map from a hilltop,
// we draw one cheap, smooth, low-resolution mesh of the entire heightmap — a
// "tablecloth" draped over the terrain shape, coloured like the voxels. It has no
// caves or overhangs and isn't editable; it's just the silhouette of the land out
// to the horizon. The near voxels render on top of it; beyond them, it IS the view.
//
// This Core builder turns an `ImageHeightmap` (the imported EXR) into a grid of
// vertices + triangles. It is deliberately decoupled from how heights/colours are
// produced: the caller passes two callbacks —
//   * height_at(wx,wz) -> ground voxel Y   (usually the generator's compute_ground_y
//                                            so the vista lines up with the voxels)
//   * color_at(wx,wz)  -> surface Rgb8      (usually base_color(resolve_column.top_id)
//                                            so the far hue matches the near cubes)
// so the same builder serves the UE actor (generator-backed callbacks) and the
// clang harness (simple lambdas). Positions come out in VOXEL space (x, height=y,
// z) so the UE layer maps them with the SAME PositionToUE as the voxels — the
// vista and the cubes share one coordinate system and line up seamlessly.
//
// Pure C++17, header-only, no engine headers.

#pragma once

#include <cstdint>
#include <vector>
#include <functional>
#include <cmath>

#include "Core/ImageHeightmap.h"
#include "Core/VoxelColor.h"  // Rgb8

namespace mira {

// One vertex of the far heightmesh: position (voxel space), smooth normal, color.
struct FarMeshVertex {
    float px, py, pz;     // position in VOXEL units (y = height)
    float nx, ny, nz;     // smooth surface normal (unit), y-up
    uint8_t r, g, b;      // sRGB palette color (same palette as the voxels)
};

struct FarHeightmesh {
    std::vector<FarMeshVertex> vertices; // grid_n * grid_n
    std::vector<uint32_t>      indices;  // (grid_n-1)^2 * 6
    int grid_n = 0;

    bool valid() const { return grid_n >= 2 && !vertices.empty() && !indices.empty(); }
    int  vertex_count() const   { return static_cast<int>(vertices.size()); }
    int  triangle_count() const { return static_cast<int>(indices.size() / 3); }
};

// Build a grid_n x grid_n heightfield spanning the heightmap's FULL world extent
// (origin + width*voxels_per_pixel). Heights and colors come from the callbacks.
// Returns an empty (invalid) mesh if grid_n < 2 or the heightmap is invalid.
inline FarHeightmesh build_far_heightmesh(
    const ImageHeightmap& hm, int grid_n,
    const std::function<int(int, int)>&  height_at,
    const std::function<Rgb8(int, int)>& color_at)
{
    FarHeightmesh out;
    if (grid_n < 2 || !hm.valid()) {
        return out; // grid_n stays 0 -> invalid
    }
    out.grid_n = grid_n;

    // World-voxel extent the EXR covers, and the step between grid vertices.
    const double span_x = static_cast<double>(hm.width)  * hm.voxels_per_pixel;
    const double span_z = static_cast<double>(hm.height) * hm.voxels_per_pixel;
    const double ox = hm.origin_voxel_x;
    const double oz = hm.origin_voxel_z;
    const double step_x = span_x / static_cast<double>(grid_n - 1);
    const double step_z = span_z / static_cast<double>(grid_n - 1);

    auto wx_of = [&](int i) { return static_cast<int>(std::llround(ox + i * step_x)); };
    auto wz_of = [&](int j) { return static_cast<int>(std::llround(oz + j * step_z)); };

    // Pass 1: sample heights into a buffer (needed for smooth normals).
    std::vector<int> H(static_cast<size_t>(grid_n) * grid_n);
    for (int j = 0; j < grid_n; ++j)
    for (int i = 0; i < grid_n; ++i) {
        H[static_cast<size_t>(j) * grid_n + i] = height_at(wx_of(i), wz_of(j));
    }

    // Pass 2: build vertices (position + central-difference normal + color).
    out.vertices.resize(static_cast<size_t>(grid_n) * grid_n);
    for (int j = 0; j < grid_n; ++j)
    for (int i = 0; i < grid_n; ++i) {
        const size_t idx = static_cast<size_t>(j) * grid_n + i;
        const int wx = wx_of(i), wz = wz_of(j);
        const int h  = H[idx];

        // Slopes from neighbours (forward/backward at edges). Heights are in
        // voxels, steps in voxels, so the slope is dimensionless.
        const int im = (i > 0) ? i - 1 : i, ip = (i < grid_n - 1) ? i + 1 : i;
        const int jm = (j > 0) ? j - 1 : j, jp = (j < grid_n - 1) ? j + 1 : j;
        const double dx = static_cast<double>(ip - im) * step_x;
        const double dz = static_cast<double>(jp - jm) * step_z;
        const double dhx = (dx != 0.0) ? (H[static_cast<size_t>(j) * grid_n + ip]
                                          - H[static_cast<size_t>(j) * grid_n + im]) / dx : 0.0;
        const double dhz = (dz != 0.0) ? (H[static_cast<size_t>(jp) * grid_n + i]
                                          - H[static_cast<size_t>(jm) * grid_n + i]) / dz : 0.0;
        double nx = -dhx, ny = 1.0, nz = -dhz;
        double len = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (len < 1e-9) len = 1.0;

        FarMeshVertex v;
        v.px = static_cast<float>(wx);
        v.py = static_cast<float>(h);
        v.pz = static_cast<float>(wz);
        v.nx = static_cast<float>(nx / len);
        v.ny = static_cast<float>(ny / len);
        v.nz = static_cast<float>(nz / len);
        const Rgb8 c = color_at(wx, wz);
        v.r = c.r; v.g = c.g; v.b = c.b;
        out.vertices[idx] = v;
    }

    // Pass 3: triangulate the grid (two tris per quad). Winding chosen so the
    // surface faces +Y (up) in voxel space; the UE layer flips if its mapping needs it.
    out.indices.reserve(static_cast<size_t>(grid_n - 1) * (grid_n - 1) * 6);
    for (int j = 0; j < grid_n - 1; ++j)
    for (int i = 0; i < grid_n - 1; ++i) {
        const uint32_t a = static_cast<uint32_t>(j) * grid_n + i;
        const uint32_t b = a + 1;
        const uint32_t c = a + grid_n;
        const uint32_t d = c + 1;
        out.indices.push_back(a); out.indices.push_back(c); out.indices.push_back(b);
        out.indices.push_back(b); out.indices.push_back(c); out.indices.push_back(d);
    }
    return out;
}

} // namespace mira
