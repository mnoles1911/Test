#pragma once

// CubicHeightmapGeneratorCpp -- C++ port of scripts/CubicHeightmapGenerator.gd.
//
// Phase 2 scope: skeleton + height-noise integration + Tier 0 only.
// "Tier 0" = write stone (material id 1) below ground_y, leave air above.
// No bands (grass/dirt/sand), no bedrock, no tier 1-6 rules. Those land in
// Phase 3+ as the bit-exact parity harness ladders up.
//
// Registered ClassDB name: "CubicHeightmapGeneratorCpp" so it coexists
// with the GDScript class_name "CubicHeightmapGenerator" during the
// porting phases. Phase 6 will rename + retire the GD version.
//
// Lifecycle:
//   1. GDScript CubicHeightmapGeneratorAdapter (extends VoxelGeneratorScript)
//      is what Zylann's VoxelLodTerrain actually invokes.
//   2. Adapter holds an exported reference to a CubicHeightmapGeneratorCpp
//      instance and forwards _generate_block to it.
//   3. This class does the heavy work on Zylann's worker thread.
//   4. Worker-thread safety: this class accesses only its own member
//      data + the FastNoiseLite ref. No SceneTree, no autoloads. Mirror
//      of the GD original's worker-thread contract.

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>

class CubicHeightmapGeneratorCpp : public godot::Resource {
    GDCLASS(CubicHeightmapGeneratorCpp, godot::Resource)

public:
    CubicHeightmapGeneratorCpp();
    ~CubicHeightmapGeneratorCpp();

    // --- Properties (mirror the GDScript @export surface) ---
    // FastNoiseLite resource drives macro + mid + detail noise layers.
    // Same Ref<FastNoiseLite> instance shared across layers; only the
    // sample coordinates differ via the frequency multipliers.
    void set_noise(const godot::Ref<godot::FastNoiseLite> &p_noise);
    godot::Ref<godot::FastNoiseLite> get_noise() const;

    void set_height_range_voxels(double p_value);
    double get_height_range_voxels() const;

    void set_height_offset_voxels(int p_value);
    int get_height_offset_voxels() const;

    void set_quantize_to_meters(bool p_value);
    bool get_quantize_to_meters() const;

    void set_mid_amplitude_voxels(int p_value);
    int get_mid_amplitude_voxels() const;

    void set_mid_frequency_multiplier(double p_value);
    double get_mid_frequency_multiplier() const;

    void set_detail_amplitude_voxels(int p_value);
    int get_detail_amplitude_voxels() const;

    void set_detail_frequency_multiplier(double p_value);
    double get_detail_frequency_multiplier() const;

    // --- Phase 3 properties: bands + marble jitter ---

    // How many top voxels of a column are grass (the green skin).
    // Default 1 — single voxel of green over the dirt.
    void set_grass_layer_thickness_voxels(int p_value);
    int get_grass_layer_thickness_voxels() const;

    // Voxels of dirt directly below grass.
    void set_dirt_layer_thickness_voxels(int p_value);
    int get_dirt_layer_thickness_voxels() const;

    // At or below this voxel-Y, the column's top band is sand instead of grass.
    void set_beach_y_threshold(int p_value);
    int get_beach_y_threshold() const;

    // Marble jitter — Tier 3 stone-band variation.
    // Lower thresholds = more frequent. Default rare=0.92, dark=0.75 →
    // ~8 % marble, ~17 % stone_dark, ~75 % plain stone.
    void set_marble_jitter_block_size(int p_value);
    int get_marble_jitter_block_size() const;

    void set_marble_jitter_seed(int p_value);
    int get_marble_jitter_seed() const;

    void set_marble_rare_threshold(double p_value);
    double get_marble_rare_threshold() const;

    void set_marble_dark_threshold(double p_value);
    double get_marble_dark_threshold() const;

    // LOD gate -- marble runs only when lod <= this. -1 disables.
    void set_marble_jitter_max_lod(int p_value);
    int get_marble_jitter_max_lod() const;

    // --- Phase 4a: bedrock + water byte ---

    // Material id written at exactly world_y == world_floor_voxel_y.
    // 0 disables the bedrock row entirely.
    void set_bedrock_material_id(int p_value);
    int get_bedrock_material_id() const;

    // Y voxel coord of the unbreakable bedrock floor. Below this,
    // the generator writes nothing (air); at exactly this Y it writes
    // bedrock; above this, normal heightmap rules apply.
    void set_world_floor_voxel_y(int p_value);
    int get_world_floor_voxel_y() const;

    // Y voxel coord of the global sea level. Water bytes fill columns
    // whose ground_y < sea_level_voxels up through this Y at LOD=0.
    void set_sea_level_voxels(int p_value);
    int get_sea_level_voxels() const;

    // --- Phase 4b: snow line (Tier 2) ---
    //
    // Non-cliff columns whose ground_y crosses (snow_line_voxels + jitter)
    // get their top voxel replaced with snow. Jitter is a hash3 lookup
    // bucketed at snow_line_jitter_block_size, scaled by
    // snow_line_jitter_voxels. snow_material_id=0 disables the tier
    // (mirrors the GD `snow_id != 0` gate).
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

    // --- Phase 4c: cliff slope rule (Tier 1) ---
    //
    // Sample 4 neighbour columns at ± cliff_slope_sample_distance_voxels;
    // if the largest Y drop is >= cliff_slope_threshold_voxels, the
    // column is a cliff: top + dirt collapse to bare stone. LOD-gated
    // by cliff_rule_max_lod (set to -1 to disable).
    void set_cliff_slope_sample_distance_voxels(int p_value);
    int get_cliff_slope_sample_distance_voxels() const;

    void set_cliff_slope_threshold_voxels(int p_value);
    int get_cliff_slope_threshold_voxels() const;

    void set_cliff_rule_max_lod(int p_value);
    int get_cliff_rule_max_lod() const;

    // --- Core API (used by tests + by the adapter) ---
    // Mirrors the GD generator's _ground_y_at. Returns the voxel-Y at
    // which solid ground ends and air begins for the column (world_x, world_z).
    // Pure function of the configured properties. Worker-thread safe.
    int compute_ground_y(int world_x, int world_z) const;

    // Called by the GDScript adapter from _generate_block on Zylann's worker
    // pool. out_buffer is a Zylann VoxelBuffer (no godot-cpp wrapper, so
    // it's passed as Variant and we Variant::call into it).
    //
    // Tier 0 behavior: for each voxel in the buffer, write material_id 1
    // (stone) if the world-space Y is at or below the column's ground_y;
    // otherwise leave default 0 (air).
    void generate_block_into_buffer(godot::Variant out_buffer,
                                    godot::Vector3i origin_in_voxels,
                                    int lod);

protected:
    static void _bind_methods();

private:
    godot::Ref<godot::FastNoiseLite> _noise;
    double _height_range_voxels = 900.0;
    int _height_offset_voxels = 60;
    bool _quantize_to_meters = false;
    int _mid_amplitude_voxels = 10;
    double _mid_frequency_multiplier = 3.0;
    int _detail_amplitude_voxels = 2;
    double _detail_frequency_multiplier = 12.0;

    // Phase 3 (bands + marble jitter)
    int _grass_layer_thickness_voxels = 1;
    int _dirt_layer_thickness_voxels = 3;
    int _beach_y_threshold = 74;
    int _marble_jitter_block_size = 4;
    int _marble_jitter_seed = 1;
    double _marble_rare_threshold = 0.92;
    double _marble_dark_threshold = 0.75;
    int _marble_jitter_max_lod = 1;

    // Phase 4a (bedrock + water)
    int _bedrock_material_id = 0;       // 0 = bedrock row disabled
    int _world_floor_voxel_y = -300;    // matches GD WORLD_FLOOR_VOXEL_Y
    int _sea_level_voxels = 72;         // matches GD SEA_LEVEL_VOXELS

    // Phase 4b (snow line — Tier 2)
    int _snow_material_id = 0;          // 0 = snow tier disabled
    int _snow_line_voxels = 30000;      // GD default — effectively off until lowered
    int _snow_line_jitter_voxels = 30;
    int _snow_line_jitter_block_size = 8;
    int _snow_line_seed = 2;
    int _snow_line_max_lod = 2;

    // Phase 4c (cliff slope — Tier 1)
    int _cliff_slope_sample_distance_voxels = 6;
    int _cliff_slope_threshold_voxels = 10;
    int _cliff_rule_max_lod = 2;

    // True when the column at (world_x, world_z) has a drop >=
    // cliff_slope_threshold_voxels to any of its 4-neighbour columns
    // at ± cliff_slope_sample_distance_voxels away. Pure function of
    // ground_y at the 5 sample points — worker-thread safe.
    bool column_is_cliff(int world_x, int world_z, int this_ground_y) const;
};
