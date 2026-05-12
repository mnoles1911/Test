#pragma once

// CopperIslesHeightmapGeneratorCpp — C++ port of scripts/CopperIslesHeightmapGenerator.gd.
//
// Mirrors CubicHeightmapGeneratorCpp's tier rules (cliff slope, snow line,
// marble jitter, ore veins, clay/gravel disks, cliff outcrops) plus bedrock
// + CHANNEL_DATA5 water byte emission. The only structural difference vs the
// cubic generator is compute_ground_y: this class samples a Gaea EXR
// heightmap via Image::get_pixel (bilinear or nearest) and maps gray → Y.
//
// TODO(cleanup): factor the shared inner-loop / tier code into a
// HeightmapGeneratorBase class. Duplicating ~500 lines from
// CubicHeightmapGeneratorCpp for now to avoid mid-port refactor risk on
// the cubic generator (which has no live parity harness to gate against).
// Extract the base after this port lands and both generators are stable.
//
// Worker-thread safety:
//   - compute_ground_y reads from a cached godot::Ref<Image>. Godot's
//     resource cache has internal locking, and once _ensure_image returns
//     a non-null Image, subsequent reads are read-only on the buffer.
//   - First-call image scan (compute _max_ground_y_voxels) happens on
//     whichever worker thread hits _ensure_image first. Race-tolerant:
//     two workers stomping the same Image instance produce identical
//     pixel data; benign.
//
// Adapter pattern: this class extends godot::Resource, not VoxelGeneratorScript.
// A thin GDScript adapter (CopperIslesHeightmapGeneratorAdapter.gd, landed
// in CI-3) extends VGS and forwards _generate_block to this Resource.

#include "voxel_gen_math.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <mutex>
#include <vector>

// POD snapshots — same shape as the cubic generator's. Duplicated here
// so the Copper Isles class doesn't depend on the cubic header (the
// future base-class extraction will move these to a shared header).
struct CICopperOrePOD {
    int material_id = 0;
    int replaces_material_id = 0;
    int min_altitude_voxels = 0;
    int max_altitude_voxels = 0;
    double ore_noise_threshold = 0.0;
    double ore_noise_scale = 0.0;
};

struct CICopperDiskPOD {
    int material_id = 0;
    int disk_radius_voxels = 0;
    int disk_half_height_voxels = 0;
    double disk_anchor_density = 0.0;
    int disk_max_distance_to_water_voxels = 0;
};

class CopperIslesHeightmapGeneratorCpp : public godot::Resource {
    GDCLASS(CopperIslesHeightmapGeneratorCpp, godot::Resource)

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

    void set_sea_level_voxels(int p_value);
    int get_sea_level_voxels() const;

    void set_elevation_above_at_white_voxels(int p_value);
    int get_elevation_above_at_white_voxels() const;

    void set_bilinear_sampling(bool p_value);
    bool get_bilinear_sampling() const;

    // --- Band properties ---
    void set_grass_layer_thickness_voxels(int p_value);
    int get_grass_layer_thickness_voxels() const;

    void set_dirt_layer_thickness_voxels(int p_value);
    int get_dirt_layer_thickness_voxels() const;

    void set_beach_y_threshold(int p_value);
    int get_beach_y_threshold() const;

    // --- Tier 3: marble jitter ---
    void set_marble_jitter_block_size(int p_value);
    int get_marble_jitter_block_size() const;

    void set_marble_jitter_seed(int p_value);
    int get_marble_jitter_seed() const;

    void set_marble_rare_threshold(double p_value);
    double get_marble_rare_threshold() const;

    void set_marble_dark_threshold(double p_value);
    double get_marble_dark_threshold() const;

    void set_marble_jitter_max_lod(int p_value);
    int get_marble_jitter_max_lod() const;

    // --- Bedrock + water ---
    void set_bedrock_material_id(int p_value);
    int get_bedrock_material_id() const;

    void set_world_floor_voxel_y(int p_value);
    int get_world_floor_voxel_y() const;

    // --- Tier 2: snow line ---
    void set_snow_material_id(int p_value);
    int get_snow_material_id() const;

    void set_snow_line_voxels(int p_value);
    int get_snow_line_voxels() const;

    void set_snow_line_jitter_voxels(int p_value);
    int get_snow_line_jitter_voxels() const;

    void set_snow_line_jitter_block_size(int p_value);
    int get_snow_line_jitter_block_size() const;

    void set_snow_line_seed(int p_value);
    int get_snow_line_seed() const;

    void set_snow_line_max_lod(int p_value);
    int get_snow_line_max_lod() const;

    // --- Tier 1: cliff slope ---
    void set_cliff_slope_sample_distance_voxels(int p_value);
    int get_cliff_slope_sample_distance_voxels() const;

    void set_cliff_slope_threshold_voxels(int p_value);
    int get_cliff_slope_threshold_voxels() const;

    void set_cliff_rule_max_lod(int p_value);
    int get_cliff_rule_max_lod() const;

    // --- POD snapshots (Tier 4 ores, Tier 5 disks) ---
    void set_ore_materials(const godot::Array &p_list);
    int get_ore_material_count() const;

    void set_disk_materials(const godot::Array &p_list);
    int get_disk_material_count() const;

    // --- Tier 4 / 5 / 6 gates ---
    void set_ore_vein_max_lod(int p_value);
    int get_ore_vein_max_lod() const;

    void set_disk_rule_max_lod(int p_value);
    int get_disk_rule_max_lod() const;

    void set_disk_anchor_grid_voxels(int p_value);
    int get_disk_anchor_grid_voxels() const;

    void set_cliff_ore_outcrop_chance(double p_value);
    double get_cliff_ore_outcrop_chance() const;

    void set_cliff_ore_seed(int p_value);
    int get_cliff_ore_seed() const;

    // --- Core API ---
    // Bilinear (or nearest) sample of the heightmap at world voxel coords.
    // Returns clamped gray in [0, 1]; out-of-bounds returns 0 (deep ocean).
    // Worker-thread safe — pure Image::get_pixel reads after cache load.
    double sample_gray(int world_x, int world_z) const;

    // Map gray ∈ [0, 1] to ground voxel-Y. Linear: gray=0 → Y=0,
    // gray=1 → Y=elevation_above_at_white_voxels. Sea level is an
    // INDEPENDENT visual concept (does not enter this formula).
    int gray_to_ground_y(double gray) const;

    // Compose: sample heightmap + map to ground Y. Public alias
    // get_ground_voxel_y_at matches CopperIslesHeightmapGenerator.gd's
    // bake-controller-facing name.
    int compute_ground_y(int world_x, int world_z) const;
    int get_ground_voxel_y_at(int world_x, int world_z) const { return compute_ground_y(world_x, world_z); }

    // True when (world_x, world_z) has a >= cliff_slope_threshold_voxels
    // drop to any 4-neighbour at ± cliff_slope_sample_distance_voxels away.
    bool column_is_cliff(int world_x, int world_z, int this_ground_y) const;

    // Called by the GDScript adapter from _generate_block on Zylann's
    // worker pool. out_buffer is a Zylann VoxelBuffer (no godot-cpp
    // wrapper, passed as Variant + Variant::call into it).
    void generate_block_into_buffer(godot::Variant out_buffer,
                                    godot::Vector3i origin_in_voxels,
                                    int lod);

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
    int _extent_x_voxels = 30000;
    int _extent_z_voxels = 30000;
    int _origin_x_voxels = -15000;
    int _origin_z_voxels = -15000;
    int _sea_level_voxels = 0;
    int _elevation_above_at_white_voxels = 15000;
    bool _bilinear_sampling = true;

    // --- Band properties ---
    int _grass_layer_thickness_voxels = 1;
    int _dirt_layer_thickness_voxels = 3;
    int _beach_y_threshold = 12;

    // --- Tier 3: marble jitter ---
    int _marble_jitter_block_size = 4;
    int _marble_jitter_seed = 1;
    double _marble_rare_threshold = 0.92;
    double _marble_dark_threshold = 0.75;
    int _marble_jitter_max_lod = 1;

    // --- Bedrock / world floor ---
    int _bedrock_material_id = 0;     // 0 = bedrock row disabled
    int _world_floor_voxel_y = -300;

    // --- Tier 2: snow line ---
    int _snow_material_id = 0;        // 0 = snow tier disabled
    int _snow_line_voxels = 12000;
    int _snow_line_jitter_voxels = 30;
    int _snow_line_jitter_block_size = 8;
    int _snow_line_seed = 2;
    int _snow_line_max_lod = 2;

    // --- Tier 1: cliff slope ---
    int _cliff_slope_sample_distance_voxels = 6;
    int _cliff_slope_threshold_voxels = 10;
    int _cliff_rule_max_lod = 2;

    // --- POD snapshots ---
    std::vector<CICopperOrePOD> _ore_materials;
    std::vector<CICopperDiskPOD> _disk_materials;

    // --- Tier gates ---
    int _ore_vein_max_lod = 1;
    int _disk_rule_max_lod = 1;
    int _disk_anchor_grid_voxels = 24;
    double _cliff_ore_outcrop_chance = 0.03;
    int _cliff_ore_seed = 5;

    // Disk lookup helper (Tier 5).
    const CICopperDiskPOD *disk_at_column(int world_x, int world_z, int ground_y) const;
};
