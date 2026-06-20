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

// CONSERVATIVE (always-below) height sampling — fixes the vista poking THROUGH the
// near voxel cubes.
//
// WHY (plain English): the coarse vista mesh only samples the ground at its grid
// vertices (one point every ~3 m on a 5 km map), then draws straight lines between
// them. The near voxels follow the TRUE height at every 10 cm column. At a ridge or
// peak the land bulges up (concave-up) between two grid samples, so the straight
// line drawn between those two samples sits ABOVE the real terrain — and therefore
// above the near cubes — and pokes through. That over-shoot is the clipping.
//
// THE FIX: instead of reading the height at the single grid-vertex point, scan the
// little square of terrain that the vertex "owns" (half a cell out in every
// direction) and take the LOWEST ground there. Because every vertex is now pinned
// to the lowest point in its footprint, the straight line between any two vertices
// can never rise above the true terrain — so the near cubes always cover it and the
// poke-through is gone. The cost is the silhouette sits a touch lower in valleys,
// which is exactly what the existing VerticalBias sink already does on purpose.
//
// `footprint_samples` = how many fine sub-samples per axis to scan across the cell
// (so footprint_samples^2 reads per vertex). 0 or 1 = legacy single-point sampling
// (the old look). 2..N = conservative min over the cell footprint. The scan covers
// [-step/2, +step/2] on each axis so adjacent vertices' footprints meet in the
// middle of every cell, leaving no gap the chord could overshoot through.
//
// NO-OVERSHOOT INVARIANT: for every grid vertex, the stored height is <= height_at
// at that vertex's own world point (min includes the centre), and <= the true
// ground at every fine column inside its footprint. A flat map returns the same
// value everywhere (min of equal values), so flat terrain is unchanged.
inline int conservative_height_min(
    const std::function<int(int, int)>& height_at,
    int wx, int wz, double half_x, double half_z, int footprint_samples)
{
    if (footprint_samples <= 1 || (half_x <= 0.0 && half_z <= 0.0)) {
        return height_at(wx, wz); // legacy single-point sample
    }
    int best = height_at(wx, wz); // always include the centre point
    const int n = footprint_samples;
    // Spread n sub-samples evenly across [-half, +half] on each axis.
    for (int sj = 0; sj < n; ++sj) {
        const double tz = (n > 1) ? (static_cast<double>(sj) / (n - 1)) : 0.5; // 0..1
        const int dz = static_cast<int>(std::llround((tz * 2.0 - 1.0) * half_z));
        for (int si = 0; si < n; ++si) {
            const double tx = (n > 1) ? (static_cast<double>(si) / (n - 1)) : 0.5;
            const int dx = static_cast<int>(std::llround((tx * 2.0 - 1.0) * half_x));
            const int h = height_at(wx + dx, wz + dz);
            if (h < best) best = h;
        }
    }
    return best;
}

// Build a grid_n x grid_n heightfield spanning the heightmap's FULL world extent
// (origin + width*voxels_per_pixel). Heights and colors come from the callbacks.
// Returns an empty (invalid) mesh if grid_n < 2 or the heightmap is invalid.
//
// `footprint_samples` controls conservative min-over-footprint height sampling (see
// conservative_height_min above): <=1 keeps the original single-point behaviour;
// >=2 pins each vertex to the lowest ground in its cell so the mesh never overshoots
// the true terrain (kills the near-voxel poke-through). Defaults to 1 so existing
// callers are unchanged; the far-mesh actor passes a higher value when its
// conservative-height flag is on.
inline FarHeightmesh build_far_heightmesh(
    const ImageHeightmap& hm, int grid_n,
    const std::function<int(int, int)>&  height_at,
    const std::function<Rgb8(int, int)>& color_at,
    int footprint_samples = 1)
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

    // Half a cell on each axis — the footprint each vertex scans for its min height.
    const double half_x = 0.5 * step_x;
    const double half_z = 0.5 * step_z;

    // Pass 1: sample heights into a buffer (needed for smooth normals). When
    // footprint_samples >= 2 this is the conservative MIN over the cell footprint so
    // the coarse surface sits at/below the true terrain everywhere (no poke-through).
    std::vector<int> H(static_cast<size_t>(grid_n) * grid_n);
    for (int j = 0; j < grid_n; ++j)
    for (int i = 0; i < grid_n; ++i) {
        H[static_cast<size_t>(j) * grid_n + i] =
            conservative_height_min(height_at, wx_of(i), wz_of(j),
                                    half_x, half_z, footprint_samples);
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
