// MeshTypes.h — the contract between the Core meshers and the UE upload glue.
//
// The greedy mesher, water surface mesher, and flora mesher all produce a
// MeshBuffers: positions in VOXEL UNITS (the UE bridge multiplies by VoxelSizeM
// and offsets to the tile-local origin), normals, atlas UVs, an AO weight, and a
// transparency class per section. Keeping this engine-agnostic means the meshers
// stay pure Core (clang-testable) and the UE side just copies into
// RealtimeMeshComponent stream buffers.

#pragma once

#include <cstdint>
#include <vector>
#include "Core/MaterialIds.h"

namespace mira {

// How a face sorts + which material section it lands in. Mirrors the Godot
// transparency indices: 0 opaque solids, 1 leaves (alpha-scissor), 2 water,
// 3 flora/detail. The mesher emits one section per class so the UE material
// slot (and its blend/cull/alpha-scissor settings) is per-section, not per-pixel.
enum class FaceClass : uint8_t {
    Opaque = 0, // stone/dirt/grass/sand/etc. + tree logs
    Cutout = 1, // leaves (alpha-scissor, non-culling)
    Water  = 2, // fluid surfaces (handled by WaterSurfaceMesher)
    Flora  = 3, // grass blades / flowers / pebbles / twigs (walk-through)
    Count  = 4,
};

// Which material section a CHANNEL_TYPE id renders into. Single source of the
// id->class rule, used by the greedy mesher to bucket faces.
constexpr FaceClass face_class_of(int type_id) {
    if (type_id == mat::LEAVES)        return FaceClass::Cutout;
    if (mat::is_water_type(type_id))   return FaceClass::Water;
    if (mat::is_passthrough(type_id))  return FaceClass::Flora; // 24..28
    return FaceClass::Opaque;
}

// The 6 cube faces, in the canonical order coords::FACE_OFFSET uses
// (-X,+X,-Y,+Y,-Z,+Z). The mesher tags each emitted quad with its dir so the
// upload glue / AtlasUV pick the right per-face tile and outward normal.
enum FaceDir : uint8_t {
    FACE_NEG_X = 0, FACE_POS_X = 1,
    FACE_NEG_Y = 2, FACE_POS_Y = 3,
    FACE_NEG_Z = 4, FACE_POS_Z = 5,
};

// Outward unit normal per face dir (float; matches FACE_OFFSET).
constexpr float FACE_NORMAL[6][3] = {
    {-1, 0, 0}, {1, 0, 0},
    { 0,-1, 0}, {0, 1, 0},
    { 0, 0,-1}, {0, 0, 1},
};

// One mesh vertex. Position is in VOXEL UNITS (not metres). AO is a 0..1 weight
// (1 = fully lit; lower = darker corner) — defaulted to 1 until the AO pass (M1).
struct MeshVertex {
    float px = 0, py = 0, pz = 0; // position, voxel units
    float nx = 0, ny = 0, nz = 0; // normal
    float u  = 0, v  = 0;         // atlas UV (tile space)
    float ao = 1.0f;              // ambient-occlusion weight 0..1
    // Baked solid voxel color (base_color × face_shade). Default white so any
    // existing producer that doesn't set it renders untinted. AO stays separate
    // in `ao`; the UE material reads rgb = albedo, alpha = AO.
    uint8_t cr = 255, cg = 255, cb = 255;

    // FLOW VECTOR for water scroll/animation (M-water). This is a 2D direction in
    // the world XZ plane telling the water shader WHICH WAY this surface is moving,
    // so the material can scroll its normal/foam UVs that way (a river drifts
    // downstream, still water doesn't move). It is written ONLY by the water surface
    // mesher; every solid/flora/leaf vertex leaves it at the default (0,0) = "no
    // scroll", which is completely inert until a material actually samples it.
    //   * (0,0)            -> still water (or any non-water vertex): no movement.
    //   * a unit-ish vector-> the flow direction decoded from the water cell's byte.
    // The UE bridge carries this into a SECOND UV channel (UV1) for the water section;
    // a future Single Layer Water material reads UV1 to drive its scroll. Default 0
    // keeps it harmless for every existing vertex producer (additive, opt-in).
    float flow_x = 0.0f; // world +X component of the flow direction
    float flow_z = 0.0f; // world +Z component of the flow direction
};

// One material section: a triangle list (indices into vertices) for one class.
struct MeshSection {
    std::vector<MeshVertex> vertices;
    std::vector<uint32_t>   indices;
    FaceClass cls = FaceClass::Opaque;

    bool empty() const { return indices.empty(); }
    int  quad_count() const { return static_cast<int>(indices.size() / 6); }
};

// The full output for a chunk: one section per transparency class.
struct MeshBuffers {
    MeshSection sections[static_cast<int>(FaceClass::Count)];

    MeshBuffers() {
        for (int i = 0; i < static_cast<int>(FaceClass::Count); ++i)
            sections[i].cls = static_cast<FaceClass>(i);
    }

    MeshSection&       section(FaceClass c)       { return sections[static_cast<int>(c)]; }
    const MeshSection& section(FaceClass c) const { return sections[static_cast<int>(c)]; }

    int total_quads() const {
        int n = 0;
        for (int i = 0; i < static_cast<int>(FaceClass::Count); ++i)
            n += sections[i].quad_count();
        return n;
    }
    int total_vertices() const {
        int n = 0;
        for (int i = 0; i < static_cast<int>(FaceClass::Count); ++i)
            n += static_cast<int>(sections[i].vertices.size());
        return n;
    }
};

} // namespace mira
