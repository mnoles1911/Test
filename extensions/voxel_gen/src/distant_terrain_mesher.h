#pragma once

// DistantTerrainMesher — builds a smooth heightmesh chunk for the
// streaming distant-terrain LOD system (replaces the baked HorizonSkirt).
//
// Given a HeightmapGeneratorBase and a world-space XZ rect, build_chunk
// returns raw mesh arrays (vertices / normals / colours / indices) as a
// Dictionary. Returning raw arrays — not an ArrayMesh — lets the call run
// on a WorkerThreadPool task (ArrayMesh assembly stays on the main
// thread) and lets the headless parity harness diff arrays without a GPU.
//
// The Phase 1 geometry algorithm is a 1:1 C++ port of
// scripts/_dev/SkirtBaker.gd — the 3-layer vertex-colour palette
// (elevation gradient + slope-to-rock shift + 2-octave hash jitter),
// central-difference normals, min-neighbourhood sampling, the Y-offset
// drop, and the spliced vertical cliff walls. Phase 2 adds the perimeter
// skirt apron on top. Bit-exact parity vs SkirtBaker is gated by the
// `distant` headless selector (tools/headless/runner.gd).
//
// Worker-thread safe: build_chunk only calls the generator's worker-safe
// compute_ground_y; it touches no SceneTree / RenderingServer state and
// holds no mutable members.

#include "heightmap_generator_base.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>

class DistantTerrainMesher : public godot::RefCounted {
    GDCLASS(DistantTerrainMesher, godot::RefCounted)

public:
    DistantTerrainMesher();
    ~DistantTerrainMesher();

    // Build one heightmesh chunk covering the world-XZ rect
    // [p_min_xz, p_max_xz] at p_quad_size_m metre spacing.
    // p_voxels_per_metre converts world metres -> generator voxel coords
    // (canonical 6.0). p_lod_ring is the LOD ring index (0 = finest);
    // accepted in Phase 1 but unused — Phase 2 uses it to scale the
    // skirt apron depth. Returns { vertices, normals, colors, indices }
    // (PackedVector3Array / PackedVector3Array / PackedColorArray /
    // PackedInt32Array) or an empty Dictionary on failure.
    godot::Dictionary build_chunk(const godot::Ref<HeightmapGeneratorBase> &p_generator,
                                  godot::Vector2 p_min_xz,
                                  godot::Vector2 p_max_xz,
                                  double p_quad_size_m,
                                  double p_voxels_per_metre,
                                  int p_lod_ring) const;

protected:
    static void _bind_methods();
};
