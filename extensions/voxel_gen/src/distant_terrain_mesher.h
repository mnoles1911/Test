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
// The grid geometry is a 1:1 C++ port of scripts/_dev/SkirtBaker.gd —
// the 3-layer vertex-colour palette (elevation gradient + slope-to-rock
// shift + 2-octave hash jitter), central-difference normals,
// min-neighbourhood sampling, the Y-offset drop, and the spliced
// vertical cliff walls. On top of that it splices a vertical perimeter
// skirt apron (Phase 2) that plugs the T-junction cracks where this
// chunk meets a neighbour at a different LOD. Bit-exact parity of the
// apron-off grid vs SkirtBaker is gated by the `distant` headless
// selector (tools/headless/runner.gd).
//
// Worker-thread safe: build_chunk only calls the generator's worker-safe
// compute_ground_y; it touches no SceneTree / RenderingServer state and
// holds no mutable members.

#include "heightmap_generator_base.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
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
    // (canonical 10.0). p_apron_depth is the depth in metres of the
    // vertical perimeter skirt apron (the manager derives it from the LOD
    // ring); <= 0 disables the apron. Returns
    // { vertices, normals, colors, indices } (PackedVector3Array /
    // PackedVector3Array / PackedColorArray / PackedInt32Array) or an
    // empty Dictionary on failure.
    godot::Dictionary build_chunk(const godot::Ref<HeightmapGeneratorBase> &p_generator,
                                  godot::Vector2 p_min_xz,
                                  godot::Vector2 p_max_xz,
                                  double p_quad_size_m,
                                  double p_voxels_per_metre,
                                  double p_apron_depth) const;

    // --- Vertex-colour palette --------------------------------------------
    // The elevation/slope palette used by build_chunk. Defaults below are
    // the historical hand-guessed values (so the mesher still produces a
    // sane image if nobody configures it), but the World3D bootstrap
    // OVERRIDES every entry at boot with the REAL mean colour of the
    // matching blocky-terrain atlas tile (grass-top, stone, sand, snow) so
    // the smooth skirt and the blocky near-band share one source of truth.
    // See DistantTerrainManager.configure_palette + World3DBootstrap.
    void set_lowland_color(godot::Color p_c);   // c_lo  — grass-top tile mean
    godot::Color get_lowland_color() const;
    void set_mid_color(godot::Color p_c);       // c_mid — mid-elevation blend
    godot::Color get_mid_color() const;
    void set_high_color(godot::Color p_c);      // c_hi  — snow tile mean
    godot::Color get_high_color() const;
    void set_rock_color(godot::Color p_c);      // slope-driven rock — stone mean
    godot::Color get_rock_color() const;
    void set_beach_color(godot::Color p_c);     // beach/sand tile mean
    godot::Color get_beach_color() const;
    void set_below_sea_color(godot::Color p_c); // deep-water dark blue-grey
    godot::Color get_below_sea_color() const;

protected:
    static void _bind_methods();

private:
    // Historical hand-guessed defaults — overridden at boot by the atlas
    // sampler. Kept only as a no-config fallback.
    godot::Color _lowland_color = godot::Color(0.26f, 0.36f, 0.20f, 1.0f);
    godot::Color _mid_color = godot::Color(0.62f, 0.60f, 0.56f, 1.0f);
    godot::Color _high_color = godot::Color(0.93f, 0.94f, 0.95f, 1.0f);
    godot::Color _rock_color = godot::Color(0.60f, 0.58f, 0.54f, 1.0f);
    godot::Color _beach_color = godot::Color(0.78f, 0.72f, 0.58f, 1.0f);
    godot::Color _below_sea_color = godot::Color(0.14f, 0.18f, 0.22f, 1.0f);
};
