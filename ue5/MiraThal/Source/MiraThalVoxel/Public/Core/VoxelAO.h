// VoxelAO.h — baked per-vertex ambient occlusion for cube faces.
//
// WHAT (plain English): the corners where blocks meet should look slightly
// darker, the way real light fails to reach an inside crease. We don't run a
// lighting pass for this — we BAKE a tiny darkness weight into each face-corner
// vertex at mesh time, by counting how many solid blocks sit around that corner.
// This is the classic "0fps" / Minecraft-style smooth-lighting trick, and it's
// what makes blocky terrain read as solid instead of flat.
//
// THE RULE: a face has 4 corners. Each corner is surrounded by 3 neighbouring
// blocks on the OUTSIDE of the face — two "side" blocks (sharing an edge) and one
// "corner" block (diagonal). The corner's AO level (0 darkest .. 3 full light) is:
//     if both sides are solid            -> 0   (the crease is sealed)
//     else                               -> 3 - (side1 + side2 + corner)
//
// The mesher calls compute_face_ao() per visible face, then (a) only merges
// neighbouring faces whose 4 corner levels match, so AO gradients aren't smeared
// across a giant quad, and (b) writes ao_weight() into each vertex.
//
// Pure C++17, no engine types — `ao` selector pins the truth table + corner math.

#pragma once

#include <cstdint>
#include "Core/MeshTypes.h"   // FaceDir, FaceClass, face_class_of
#include "Core/ChunkCoords.h" // coords::FACE_OFFSET, Vec3i
#include "Core/MaterialIds.h" // mat::AIR

namespace mira {
namespace ao {

// Is material id `id` an AO occluder? Same spirit as face-cull occlusion: only a
// fully-opaque SOLID darkens a crease. Leaves/water/flora don't (light filters
// through). NOTE the air gotcha: face_class_of(AIR) is Opaque (enum 0 default),
// so air must be excluded explicitly or every corner would read as occluded.
constexpr bool is_occluder(int id) {
    return id != mat::AIR && face_class_of(id) == FaceClass::Opaque;
}

// The 0fps corner rule. side1/side2 = the two edge-sharing neighbours, corner =
// the diagonal one. Returns 0..3 (0 = darkest sealed crease, 3 = fully lit).
constexpr uint8_t vertex_ao(bool side1, bool side2, bool corner) {
    if (side1 && side2) return 0;
    return static_cast<uint8_t>(3 - (int(side1) + int(side2) + int(corner)));
}

// Map an AO level 0..3 to a 0..1 vertex lighting weight (1 = full light). Linear
// for now; the designer can raise the floor (e.g. 0.4 + 0.6*level/3) for a gentler
// look without touching the bake — it's one curve, one place.
constexpr float ao_weight(uint8_t level) {
    return static_cast<float>(level) / 3.0f;
}

// The 4 corner AO levels of one face, in the mesher's quad-corner order
// (00, 10, 11, 01) over the in-plane (u,v) axes. Equality is what gates greedy
// merging — two faces merge only if id AND all four corner levels match.
struct CornerAO {
    uint8_t level[4] = {3, 3, 3, 3};

    bool operator==(const CornerAO& o) const {
        return level[0] == o.level[0] && level[1] == o.level[1]
            && level[2] == o.level[2] && level[3] == o.level[3];
    }
    bool operator!=(const CornerAO& o) const { return !(*this == o); }
    bool uniform_full() const {
        return level[0] == 3 && level[1] == 3 && level[2] == 3 && level[3] == 3;
    }
    // The "anisotropy flip" test: when the two diagonals disagree, the quad should
    // be triangulated along the other diagonal so the gradient interpolates
    // smoothly instead of creasing. True => emit_quad should flip its diagonal.
    bool should_flip_diagonal() const {
        return level[0] + level[2] < level[1] + level[3];
    }
};

// Compute the 4 corner AO levels for voxel (x,y,z)'s face `dir`. `occ(x,y,z)`
// answers "is the voxel at these coords an AO occluder?" — the caller wires it to
// the voxel store (incl. the 1-voxel apron, which is all the reach AO needs: the
// face-normal axis only steps ±1, the in-plane axes only step ±1).
template <class OccFn>
CornerAO compute_face_ao(OccFn&& occ, int x, int y, int z, FaceDir dir) {
    const int axis = dir >> 1;          // 0/1/2 for X/Y/Z (NEG,POS pairs share an axis)
    const int ua   = (axis + 1) % 3;    // first in-plane axis  (matches the mesher)
    const int va   = (axis + 2) % 3;    // second in-plane axis
    const Vec3i n  = coords::FACE_OFFSET[dir];

    const int base[3] = { x + n.x, y + n.y, z + n.z }; // the outside cell at this face

    // Sample the outside plane at in-plane offset (du along ua, dv along va).
    auto sample = [&](int du, int dv) -> bool {
        int p[3] = { base[0], base[1], base[2] };
        p[ua] += du;
        p[va] += dv;
        return occ(p[0], p[1], p[2]);
    };

    // Corner param order 00,10,11,01 -> in-plane sign of each corner.
    static const int su[4] = {-1, +1, +1, -1};
    static const int sv[4] = {-1, -1, +1, +1};

    CornerAO r;
    for (int c = 0; c < 4; ++c) {
        const bool side1  = sample(su[c], 0);
        const bool side2  = sample(0,     sv[c]);
        const bool corner = sample(su[c], sv[c]);
        r.level[c] = vertex_ao(side1, side2, corner);
    }
    return r;
}

} // namespace ao
} // namespace mira
