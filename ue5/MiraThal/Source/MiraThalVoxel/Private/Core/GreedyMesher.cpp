// GreedyMesher.cpp — implementation of the cubic greedy mesher.
//
// See GreedyMesher.h for the why. This file is the how: a classic Lysenko-style
// sweep. The world is axis-aligned cubes, so each of the 6 face directions is a
// stack of 2D slices perpendicular to one axis. For each slice we paint a "mask"
// of which faces are visible (and what material they carry), then greedily merge
// adjacent equal cells of that mask into the biggest rectangles we can, emitting
// one quad per rectangle.
//
// COORDINATE NOTES:
//   - Slab indices run [0..33]; the meshed chunk is the inner [1..32]. A voxel at
//     slab (sx,sy,sz) is chunk-local (sx-1, sy-1, sz-1) in VOXEL UNITS, which is
//     what we write into vertex positions.
//   - We iterate the inner chunk in CHUNK-LOCAL coords [0..31] and add +APRON (1)
//     whenever we read the slab, so the neighbour shell is reachable at local
//     index -1 -> slab 0 and local index 32 -> slab 33.

#include "Core/GreedyMesher.h"
#include "Core/ChunkCoords.h" // coords::CHUNK, FACE_OFFSET, flatten
#include "Core/AtlasUV.h"     // atlas::uv_for
#include "Core/VoxelColor.h"  // shaded_color, Rgb8
#include "Core/MaterialIds.h" // mat:: predicates
#include "Core/VoxelAO.h"     // ao::compute_face_ao, ao::CornerAO, ao::ao_weight

#include <vector>
#include <cstdint>

namespace mira {

namespace {

constexpr int N = coords::CHUNK; // 32 — the inner chunk edge we mesh

// Does material id `n` HIDE the face of its neighbour? Only fully-opaque SOLIDS
// occlude. Leaves (Cutout) are deliberately non-culling — a stone face next to
// leaves still draws, and leaf-vs-leaf faces both draw — so the canopy reads as
// a dense mass of leaf cards rather than a sealed shell. Water and flora never
// occlude either (they have their own meshers).
//
// IMPORTANT air gotcha: face_class_of(AIR) returns FaceClass::Opaque (air has no
// real class; the enum default is 0 == Opaque). So we must explicitly exclude air
// here — otherwise every face would think its empty-air neighbour is a solid wall
// and the whole chunk would cull to nothing.
inline bool occludes(int n) {
    return n != mat::AIR && face_class_of(n) == FaceClass::Opaque;
}

// Should voxel id `id` emit faces AT ALL from this mesher? Only opaque solids and
// cutout leaves. Air emits nothing; water + flora/detail belong to other meshers.
inline bool meshes_here(int id) {
    if (id == mat::AIR) return false;
    const FaceClass c = face_class_of(id);
    return c == FaceClass::Opaque || c == FaceClass::Cutout;
}

// Read the slab at a CHUNK-LOCAL coordinate (the +APRON shift reaches the shell).
inline uint8_t at_local(const DenseGrid& slab, int lx, int ly, int lz) {
    return slab.type_at(lx + APRON, ly + APRON, lz + APRON);
}

// One painted mask cell: which material to draw here (0 == no visible face) plus
// the 4 baked corner AO levels of that face. Two cells merge iff BOTH match — so
// an AO gradient (a darker crease running across a flat wall) correctly breaks a
// would-be giant quad into pieces instead of smearing the shading. dir is fixed
// per sweep, so it isn't stored.
struct MaskCell {
    uint8_t id = 0; // 0 == empty (no visible face here)
    ao::CornerAO ao;
    bool operator==(const MaskCell& o) const { return id == o.id && ao == o.ao; }
    bool operator!=(const MaskCell& o) const { return !(*this == o); }
    explicit operator bool() const { return id != 0; }
};

// Push one merged quad (w x h cells, all the same id) into the right section.
//
// The quad lives on the plane of constant `slice` along axis `dir`, spanning a
// `w` x `h` rectangle in the two in-plane axes. `origin[3]` is the min corner of
// the rectangle in chunk-local VOXEL UNITS (already apron-corrected); `du[3]` and
// `dv[3]` are the in-plane unit step vectors scaled into the world axes, so the
// four corners are origin, origin+du*w, origin+du*w+dv*h, origin+dv*h.
//
// Winding: we order the four corners so the two emitted triangles wind
// counter-clockwise as seen from OUTSIDE (looking back along the normal). Each
// vertex normal is FACE_NORMAL[dir]. UVs stretch the tile rect across the merged
// quad (M0 simplification — see header), so the 4 corners get the 4 tile corners.
void emit_quad(MeshBuffers& out, FaceDir dir, uint8_t id,
               const float origin[3], const float du[3], const float dv[3],
               int w, int h, const ao::CornerAO& cao) {
    const FaceClass cls = face_class_of(id);
    MeshSection& sec = out.section(cls);

    // The four corners (voxel units), in (u,v) parameter order 00,10,11,01.
    const float p00[3] = { origin[0],                  origin[1],                  origin[2] };
    const float p10[3] = { origin[0] + du[0] * w,      origin[1] + du[1] * w,      origin[2] + du[2] * w };
    const float p11[3] = { origin[0] + du[0] * w + dv[0] * h,
                           origin[1] + du[1] * w + dv[1] * h,
                           origin[2] + du[2] * w + dv[2] * h };
    const float p01[3] = { origin[0] + dv[0] * h,      origin[1] + dv[1] * h,      origin[2] + dv[2] * h };

    const float* nrm = FACE_NORMAL[dir];

    // Atlas tile rect for this id+face; stretched across the whole merged quad.
    const atlas::UVRect uv = atlas::uv_for(id, static_cast<FaceDir>(dir));

    // Solid baked color for this id+face. One value for the whole quad (color is
    // per material+direction, never per voxel), so greedy merging is preserved.
    const Rgb8 col = shaded_color(id, static_cast<FaceDir>(dir));

    // Tie each corner's UV to its (u,v) parameter so the tile maps corner-to-corner,
    // and bake the corner's AO level into the vertex weight.
    auto add = [&](const float p[3], float uu, float vv, uint8_t ao_level) -> uint32_t {
        MeshVertex mv;
        mv.px = p[0]; mv.py = p[1]; mv.pz = p[2];
        mv.nx = nrm[0]; mv.ny = nrm[1]; mv.nz = nrm[2];
        mv.u = uu; mv.v = vv;
        mv.ao = ao::ao_weight(ao_level);
        mv.cr = col.r; mv.cg = col.g; mv.cb = col.b;
        const uint32_t idx = static_cast<uint32_t>(sec.vertices.size());
        sec.vertices.push_back(mv);
        return idx;
    };

    const uint32_t i00 = add(p00, uv.u0, uv.v0, cao.level[0]);
    const uint32_t i10 = add(p10, uv.u1, uv.v0, cao.level[1]);
    const uint32_t i11 = add(p11, uv.u1, uv.v1, cao.level[2]);
    const uint32_t i01 = add(p01, uv.u0, uv.v1, cao.level[3]);

    // The parameter winding 00->10->11->01 is CCW in the (du,dv) plane. Whether
    // that looks CCW from OUTSIDE depends on whether (du x dv) points along +normal
    // or -normal. We pick du/dv per direction (below) so (du x dv) == +normal for
    // the POSITIVE faces and == -normal for the NEGATIVE faces, then reverse the
    // winding for negative faces. Result: every quad faces outward.
    const bool flip_wind = (dir == FACE_NEG_X || dir == FACE_NEG_Y || dir == FACE_NEG_Z);
    auto tri = [&](uint32_t a, uint32_t b, uint32_t c) {
        sec.indices.push_back(a);
        if (!flip_wind) { sec.indices.push_back(b); sec.indices.push_back(c); }
        else            { sec.indices.push_back(c); sec.indices.push_back(b); }
    };

    // Pick the triangulation diagonal. Splitting along 00-11 is the default; when
    // the AO of the 00/11 pair is darker than the 10/01 pair, split along 10-01 so
    // the shading gradient interpolates smoothly across the quad instead of
    // creasing along the wrong diagonal (the classic AO anisotropy fix).
    if (!cao.should_flip_diagonal()) {
        tri(i00, i10, i11); // 00->10->11
        tri(i00, i11, i01); // 00->11->01
    } else {
        tri(i10, i11, i01); // 10->11->01
        tri(i10, i01, i00); // 10->01->00
    }
}

// Sweep ONE face direction and emit its merged quads.
//
// `dir` is the outward face direction. `axis` is the axis the slices stack along
// (the axis the normal points along): 0=X, 1=Y, 2=Z. `ua`/`va` are the two
// in-plane axes (the rectangle spans these). For each slice along `axis`, we
// paint a w x h mask: cell (i,j) holds the id of the voxel at that in-plane
// position IF that voxel meshes here AND its neighbour in `dir` does not occlude
// it; else 0. Then we rectangle-merge the mask.
void sweep_dir(const DenseGrid& slab, MeshBuffers& out, FaceDir dir, int axis) {
    const int ua = (axis + 1) % 3; // first in-plane axis
    const int va = (axis + 2) % 3; // second in-plane axis

    const Vec3i off = coords::FACE_OFFSET[dir]; // neighbour step for this face
    // +1 for positive faces (quad sits at the +side of the cell), 0 for negative.
    const bool positive = (dir == FACE_POS_X || dir == FACE_POS_Y || dir == FACE_POS_Z);

    std::vector<MaskCell> mask(static_cast<size_t>(N) * N);

    // Walk every slice (constant value along `axis`).
    for (int s = 0; s < N; ++s) {
        // ---- paint the mask for this slice ----
        for (int j = 0; j < N; ++j) {       // along va
            for (int i = 0; i < N; ++i) {   // along ua
                int c[3];
                c[axis] = s; c[ua] = i; c[va] = j;
                const int id = at_local(slab, c[0], c[1], c[2]);

                MaskCell cell;
                if (meshes_here(id)) {
                    const int nb = at_local(slab, c[0] + off.x, c[1] + off.y, c[2] + off.z);
                    if (!occludes(nb)) {
                        cell.id = static_cast<uint8_t>(id);
                        // Bake this face's 4 corner AO levels. The occupancy probe
                        // reads the slab (incl. apron) through the AO occluder rule.
                        auto occ = [&](int ox, int oy, int oz) {
                            return ao::is_occluder(at_local(slab, ox, oy, oz));
                        };
                        cell.ao = ao::compute_face_ao(occ, c[0], c[1], c[2], dir);
                    }
                }
                mask[static_cast<size_t>(j) * N + i] = cell;
            }
        }

        // ---- greedily merge the mask into rectangles ----
        for (int j = 0; j < N; ++j) {
            for (int i = 0; i < N;) {
                const MaskCell start = mask[static_cast<size_t>(j) * N + i];
                if (!start) { ++i; continue; }

                // Grow width along ua while cells match.
                int w = 1;
                while (i + w < N && mask[static_cast<size_t>(j) * N + (i + w)] == start) ++w;

                // Grow height along va while the entire next row [i..i+w) matches.
                int h = 1;
                bool grow = true;
                while (j + h < N && grow) {
                    for (int k = 0; k < w; ++k) {
                        if (mask[static_cast<size_t>(j + h) * N + (i + k)] != start) { grow = false; break; }
                    }
                    if (grow) ++h;
                }

                // Build the quad geometry in voxel units.
                // Base corner of the cell rectangle (min corner along ua/va, and
                // along `axis` the slice plane). For a positive face the plane is
                // at s+1 (the +side of the cube); for a negative face it's at s.
                float origin[3] = {0, 0, 0};
                origin[ua]   = static_cast<float>(i);
                origin[va]   = static_cast<float>(j);
                origin[axis] = static_cast<float>(positive ? s + 1 : s);

                // In-plane step vectors (one voxel unit each) along ua then va.
                float du[3] = {0, 0, 0};
                float dv[3] = {0, 0, 0};
                du[ua] = 1.0f;
                dv[va] = 1.0f;

                emit_quad(out, dir, start.id, origin, du, dv, w, h, start.ao);

                // Clear the consumed rectangle so we don't re-emit it.
                for (int hh = 0; hh < h; ++hh)
                    for (int ww = 0; ww < w; ++ww)
                        mask[static_cast<size_t>(j + hh) * N + (i + ww)] = MaskCell{};

                i += w;
            }
        }
    }
}

} // namespace

MeshBuffers greedy_mesh(const DenseGrid& slab) {
    MeshBuffers out;

    // Six face directions, each stacking slices along the axis its normal follows.
    sweep_dir(slab, out, FACE_NEG_X, 0);
    sweep_dir(slab, out, FACE_POS_X, 0);
    sweep_dir(slab, out, FACE_NEG_Y, 1);
    sweep_dir(slab, out, FACE_POS_Y, 1);
    sweep_dir(slab, out, FACE_NEG_Z, 2);
    sweep_dir(slab, out, FACE_POS_Z, 2);

    return out;
}

} // namespace mira
