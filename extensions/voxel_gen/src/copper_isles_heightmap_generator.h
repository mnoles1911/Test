#pragma once

// CopperIslesHeightmapGeneratorCpp — EXR-heightmap-based generator for
// the Copper Isles demo. All tier rules + chunk loop live in
// HeightmapGeneratorBase; this class adds only:
//   * The EXR cache (mutex-guarded Ref<Image> + width/height) and the
//     extent / origin / elevation / bilinear params that drive sampling
//   * sample_gray / gray_to_ground_y helpers
//   * The compute_ground_y override that composes them
//
// Worker-thread safety:
//   * _ensure_image() is mutex-protected because Zylann calls
//     generate_block from many worker threads concurrently. Without the
//     lock, two threads can both pass the load-attempted check and one
//     reads partially-populated state — the "floating cubes" artifact
//     fixed on 2026-05-12. See LESSONS_LEARNED.md for the trace.
//   * Reads after _heightmap_load_attempted = true are pure
//     Image::get_pixel calls and are safe without further locking.
//
// Adapter pattern: thin GDScript adapter at
// `scripts/_dev/CopperIslesHeightmapGeneratorAdapter.gd` extends
// VoxelGeneratorScript and forwards _generate_block here.

#include "heightmap_generator_base.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref.hpp>

#include <mutex>

class CopperIslesHeightmapGeneratorCpp : public HeightmapGeneratorBase {
    GDCLASS(CopperIslesHeightmapGeneratorCpp, HeightmapGeneratorBase)

public:
    CopperIslesHeightmapGeneratorCpp();
    ~CopperIslesHeightmapGeneratorCpp();

    // --- Heightmap properties (mirror the GDScript @export surface) ---
    void set_heightmap_path(const godot::String &p_value);
    godot::String get_heightmap_path() const;

    void set_extent_x_voxels(int p_value);
    int get_extent_x_voxels() const;

    void set_extent_z_voxels(int p_value);
    int get_extent_z_voxels() const;

    void set_origin_x_voxels(int p_value);
    int get_origin_x_voxels() const;

    void set_origin_z_voxels(int p_value);
    int get_origin_z_voxels() const;

    void set_elevation_above_at_white_voxels(int p_value);
    int get_elevation_above_at_white_voxels() const;

    void set_bilinear_sampling(bool p_value);
    bool get_bilinear_sampling() const;

    // Bilinear (or nearest) sample of the heightmap at world voxel coords.
    // Returns clamped gray in [0, 1]; out-of-bounds returns 0 (deep ocean).
    // Worker-thread safe — pure Image::get_pixel reads after cache load.
    double sample_gray(int world_x, int world_z) const;

    // Map gray ∈ [0, 1] to ground voxel-Y. Linear: gray=0 → Y=0,
    // gray=1 → Y=elevation_above_at_white_voxels. Sea level is an
    // INDEPENDENT visual concept (does not enter this formula).
    int gray_to_ground_y(double gray) const;

    // Override of HeightmapGeneratorBase::compute_ground_y. Composes
    // sample_gray + gray_to_ground_y.
    int compute_ground_y(int world_x, int world_z) const override;

protected:
    static void _bind_methods();

private:
    // Lazy heightmap cache. _ensure_image loads the EXR on first
    // worker-thread access. Mutex-protected because Zylann calls
    // generate_block from many worker threads concurrently; without the
    // lock, a race in the load-flag check + assignment can leave one
    // thread reading from a half-initialized Image (zeros) or a stale
    // pointer, producing wrong gray values and therefore wrong
    // ground_y. This was masked in the GDScript original because the
    // slower interpreter rarely hit the race; the C++ port hits it
    // reliably and manifests as bad terrain in the LOD pyramid.
    godot::Ref<godot::Image> _ensure_image();
    mutable godot::Ref<godot::Image> _heightmap_image;
    mutable bool _heightmap_load_attempted = false;
    mutable int _heightmap_w = 0;
    mutable int _heightmap_h = 0;
    mutable std::mutex _heightmap_mutex;

    // Const helper for read paths that need to invoke _ensure_image.
    // The cache state is mutable, hence the const-cast in the impl.
    godot::Ref<godot::Image> ensure_image_const() const;

    // --- Heightmap config ---
    godot::String _heightmap_path = "res://assets/heightmaps/copper_isles_heightmap.exr";
    // Voxel-unit extents rescaled x5/3 at the 10 vox/m pivot
    // (2026-06-12) so the island keeps the same WORLD-metre footprint
    // (5 km x 5 km; was 30000/-15000/15000 at 6 vox/m). Per the
    // change-all-together-or-none table in COPPER_ISLES_BAKE_NOTES.md.
    int _extent_x_voxels = 50000;
    int _extent_z_voxels = 50000;
    int _origin_x_voxels = -25000;
    int _origin_z_voxels = -25000;
    int _elevation_above_at_white_voxels = 25000;
    bool _bilinear_sampling = true;
};
