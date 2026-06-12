#pragma once

// HeightmapGeneratorBase — shared abstract base for the two C++ heightmap
// generators (CubicHeightmapGeneratorCpp + CopperIslesHeightmapGeneratorCpp).
//
// The two ports share ~500 lines of identical code:
//   * All Tier 1–6 properties (cliff, snow, marble, bedrock, ore, disk gates)
//   * POD snapshot parsing for ore + disk material lists
//   * column_is_cliff (Tier 1 helper)
//   * disk_at_column   (Tier 5 helper)
//   * generate_block_into_buffer (the chunk inner loop)
// The differences are entirely in compute_ground_y — the cubic generator
// samples three FastNoiseLite layers, the Copper Isles generator samples
// an EXR heightmap. Pulling the shared code into a base class collapses
// each concrete generator's .cpp from ~800 lines to ~150.
//
// Adapter pattern is unchanged: godot-cpp can't subclass Zylann's
// VoxelGeneratorScript, so each concrete generator stays a
// godot::Resource and a thin GDScript adapter forwards
// _generate_block to it. See LESSONS_LEARNED.md 2026-05-11.
//
// Worker-thread safety:
//   * All shared state is value-typed (ints, doubles, std::vector<POD>) and
//     populated from the main thread before terrain streaming begins.
//   * generate_block_into_buffer reads instance config and the POD vectors
//     without locking — the "publish before streaming" convention applies.
//   * compute_ground_y is virtual; concrete implementations must be
//     worker-thread safe themselves (e.g. Copper Isles' _ensure_image
//     mutex on its lazy EXR cache — see LESSONS_LEARNED.md 2026-05-12).

#include "biome_field.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <atomic>
#include <cstdint>
#include <vector>

// POD snapshots — the bootstrap translates Array[VoxelMaterial] into
// Array[Dictionary] on the main thread, the resource parses into these
// structs once, and the worker-thread inner loop iterates the
// resulting std::vector without touching the SceneTree.
struct OreMaterialPOD {
    int material_id = 0;
    int replaces_material_id = 0;
    int min_altitude_voxels = 0;
    int max_altitude_voxels = 0;
    double ore_noise_threshold = 0.0;
    double ore_noise_scale = 0.0;
};

struct DiskMaterialPOD {
    int material_id = 0;
    int disk_radius_voxels = 0;
    int disk_half_height_voxels = 0;
    double disk_anchor_density = 0.0;
    int disk_max_distance_to_water_voxels = 0;
};

class HeightmapGeneratorBase : public godot::Resource {
    GDCLASS(HeightmapGeneratorBase, godot::Resource)

public:
    HeightmapGeneratorBase();
    ~HeightmapGeneratorBase();

    // --- Band properties ---------------------------------------------------
    void set_grass_layer_thickness_voxels(int p_value);
    int get_grass_layer_thickness_voxels() const;

    void set_dirt_layer_thickness_voxels(int p_value);
    int get_dirt_layer_thickness_voxels() const;

    void set_beach_y_threshold(int p_value);
    int get_beach_y_threshold() const;

    // --- Tier 3: marble jitter ---------------------------------------------
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

    // --- Bedrock + water byte ---------------------------------------------
    void set_bedrock_material_id(int p_value);
    int get_bedrock_material_id() const;

    void set_world_floor_voxel_y(int p_value);
    int get_world_floor_voxel_y() const;

    void set_sea_level_voxels(int p_value);
    int get_sea_level_voxels() const;

    // --- Tier 2: snow line ------------------------------------------------
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

    // --- Tier 1: cliff slope ----------------------------------------------
    void set_cliff_slope_sample_distance_voxels(int p_value);
    int get_cliff_slope_sample_distance_voxels() const;

    void set_cliff_slope_threshold_voxels(int p_value);
    int get_cliff_slope_threshold_voxels() const;

    void set_cliff_rule_max_lod(int p_value);
    int get_cliff_rule_max_lod() const;

    // --- POD snapshots (Tier 4 ores, Tier 5 disks) -----------------------
    void set_ore_materials(const godot::Array &p_list);
    int get_ore_material_count() const;

    void set_disk_materials(const godot::Array &p_list);
    int get_disk_material_count() const;

    // --- Tier 4 / 5 / 6 gates ---------------------------------------------
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

    // --- R4 micro-voxel flora scatter -------------------------------------
    // The three flora CHANNEL_TYPE ids (grass blade + two flowers). All
    // default 0 = "disabled": the generator writes NO flora until the
    // GDScript bootstrap wires the real ids (24/25/26) at startup, exactly
    // like bedrock_material_id / snow_material_id are 0-gated. Mirrors
    // scripts/FloraMaterial.gd: grass=24, flower_red=25, flower_blue=26.
    void set_grass_blade_material_id(int p_value);
    int get_grass_blade_material_id() const;

    void set_flower_red_material_id(int p_value);
    int get_flower_red_material_id() const;

    void set_flower_blue_material_id(int p_value);
    int get_flower_blue_material_id() const;

    void set_flora_seed(int p_value);
    int get_flora_seed() const;

    // --- D1 surface-detail scatter (pebbles + twigs) ----------------------
    // The two surface-detail CHANNEL_TYPE ids. Default 0 = disabled, same
    // 0-gate as flora — the generator writes NO pebbles/twigs until the
    // GDScript bootstrap wires the real ids (27/28) at startup. Mirrors
    // scripts/FloraMaterial.gd: pebble=27, twig=28. Scattered with a
    // DIFFERENT salt than flora so the two patterns don't correlate.
    void set_pebble_material_id(int p_value);
    int get_pebble_material_id() const;

    void set_twig_material_id(int p_value);
    int get_twig_material_id() const;

    void set_surface_detail_seed(int p_value);
    int get_surface_detail_seed() const;

    // --- Biome framework --------------------------------------------------
    // When biome profiles are loaded the generator switches to the
    // biome-aware path: compute_ground_y blends per-biome heightfield
    // params, and the block-fill loop reads per-biome surface materials +
    // flora densities. With NO profiles set the generator keeps its legacy
    // single-recipe behaviour byte-for-byte (so the `gen` parity baseline
    // and the Copper Isles generator are untouched).
    //
    // set_biome_profiles forwards Array[Dictionary] to the owned
    // BiomeFieldCpp. set_biome_field_params forwards the control-noise +
    // classification knobs + the five KIND→slot bindings. The bootstrap
    // calls both on the main thread before streaming.
    void set_biome_profiles(const godot::Array &p_list);
    void set_biome_field_params(double control_frequency_per_m,
                                double warp_frequency_per_m,
                                double warp_strength,
                                double blend_margin,
                                double voxels_per_metre,
                                int plains_index, int hills_index,
                                int forest_index, int desert_index,
                                int mountains_index);
    void set_biome_control_noise(const godot::Ref<godot::FastNoiseLite> &p_noise);
    int get_biome_profile_count() const;

    // The owned field, exposed so the headless gate can pull the SAME
    // configured instance the generator uses (the `biome` selector reads
    // it off the live World3D generator, like `gen`/`distant` do).
    godot::Ref<voxel_gen::BiomeFieldCpp> get_biome_field() const { return _biome_field; }

    // True once profiles are loaded — gates the biome-vs-legacy branch.
    bool biome_active() const {
        return _biome_field.is_valid() && _biome_field->has_profiles();
    }

    // --- Core API ---------------------------------------------------------

    // Concrete generators override this with their ground-Y math.
    // Pure virtual on the C++ side; the abstract-class registration
    // below stops Godot's editor from offering "New Resource" for the
    // base class. ClassDB::bind_method dispatches virtually, so
    // GDScript callers of get_ground_voxel_y_at / compute_ground_y
    // reach the concrete override correctly.
    virtual int compute_ground_y(int world_x, int world_z) const = 0;

    // Public alias used by the bake controller (duck-typed). Same
    // semantics as compute_ground_y; the rename is purely interop.
    int get_ground_voxel_y_at(int world_x, int world_z) const {
        return compute_ground_y(world_x, world_z);
    }

    // True when (world_x, world_z) has a drop >= cliff_slope_threshold_voxels
    // to any of its 4-neighbour columns at ± cliff_slope_sample_distance_voxels
    // away. Pure function of compute_ground_y at the 5 sample points —
    // worker-thread safe as long as the override is.
    bool column_is_cliff(int world_x, int world_z, int this_ground_y) const;

    // Called by the GDScript adapter from _generate_block on Zylann's worker
    // pool. out_buffer is a Zylann VoxelBuffer (no godot-cpp wrapper, so
    // it's passed as Variant and we Variant::call into it).
    void generate_block_into_buffer(godot::Variant out_buffer,
                                    godot::Vector3i origin_in_voxels,
                                    int lod);

    // --- Cache-miss telemetry ---------------------------------------------
    // generate_block_into_buffer atomically increments this counter on
    // every call. Each call corresponds to a Zylann CACHE MISS — Zylann
    // only runs the generator for blocks that aren't in the VoxelStream
    // (no SQLite row + save_generator_output didn't fire yet). Subtract
    // consecutive readings to get the cache-miss rate per second; if
    // most chunks in an area are coming from the SQLite cache, this
    // counter should stay near-flat as the player walks through them.
    // Worker-thread safe (atomic counter, no locks).
    int get_generated_block_count() const {
        return int(_generated_block_count.load(std::memory_order_relaxed));
    }
    void reset_generated_block_count() {
        _generated_block_count.store(0, std::memory_order_relaxed);
    }

protected:
    static void _bind_methods();

    // Tier 5 helper. Mirrors GD _disk_at_column. Returns pointer to a
    // disk POD if (world_x, world_z) sits inside a disk anchor footprint
    // at this elevation, or nullptr otherwise. The pointer is valid for
    // the lifetime of _disk_materials, which is stable during streaming.
    const DiskMaterialPOD *disk_at_column(int world_x, int world_z, int ground_y) const;

    // --- Band properties --------------------------------------------------
    int _grass_layer_thickness_voxels = 1;
    int _dirt_layer_thickness_voxels = 3;
    int _beach_y_threshold = 74;

    // --- Tier 3: marble jitter --------------------------------------------
    int _marble_jitter_block_size = 4;
    int _marble_jitter_seed = 1;
    double _marble_rare_threshold = 0.92;
    double _marble_dark_threshold = 0.75;
    int _marble_jitter_max_lod = 1;

    // --- Bedrock / world floor / sea ---------------------------------------
    // Voxel-unit values rescaled 2026-06-12 for the 10 vox/m pivot so
    // the WORLD-metre meaning is preserved: floor -300vox(-50m at 6/m)
    // -> -500vox(-50m at 10/m); sea 72vox(12m) -> 120vox(12m).
    int _bedrock_material_id = 0;     // 0 disables the bedrock row
    int _world_floor_voxel_y = -500;
    int _sea_level_voxels = 120;

    // --- Tier 2: snow line -------------------------------------------------
    int _snow_material_id = 0;        // 0 disables the snow tier
    int _snow_line_voxels = 30000;
    int _snow_line_jitter_voxels = 30;
    int _snow_line_jitter_block_size = 8;
    int _snow_line_seed = 2;
    int _snow_line_max_lod = 2;

    // --- Tier 1: cliff slope ----------------------------------------------
    // Also voxel units meaning metres: sample 6vox(1m at 6/m) ->
    // 10vox(1m at 10/m); threshold 10vox(1.67m) -> 17vox(1.7m).
    int _cliff_slope_sample_distance_voxels = 10;
    int _cliff_slope_threshold_voxels = 17;
    int _cliff_rule_max_lod = 2;

    // --- POD snapshots (set on main thread; read on worker threads) -------
    std::vector<OreMaterialPOD> _ore_materials;
    std::vector<DiskMaterialPOD> _disk_materials;

    // --- Tier 4 / 5 / 6 gates ---------------------------------------------
    int _ore_vein_max_lod = 1;
    int _disk_rule_max_lod = 1;
    int _disk_anchor_grid_voxels = 24;
    double _cliff_ore_outcrop_chance = 0.03;
    int _cliff_ore_seed = 5;

    // --- R4 flora scatter (0 = disabled until the bootstrap wires ids) ----
    int _grass_blade_material_id = 0;
    int _flower_red_material_id = 0;
    int _flower_blue_material_id = 0;
    int _flora_seed = 1337;

    // --- D1 surface-detail scatter (0 = disabled until bootstrap wires) ---
    int _pebble_material_id = 0;
    int _twig_material_id = 0;
    // Different salt from _flora_seed so pebble/twig placement is
    // statistically independent of where grass/flowers landed.
    int _surface_detail_seed = 7919;

    // --- Biome framework --------------------------------------------------
    // Lazily created when set_biome_profiles / set_biome_field_params /
    // set_biome_control_noise first run (the bootstrap wires all three).
    // Null until then → biome_active() false → legacy path.
    godot::Ref<voxel_gen::BiomeFieldCpp> _biome_field;
    // Map the biome top/slope material id to the band layout. The biome
    // block-loop reuses the generator's grass/dirt/stone band thicknesses
    // but swaps the TOP + SLOPE ids per the picked biome's surface params.
    void _ensure_biome_field();

private:
    mutable std::atomic<int> _generated_block_count{0};
};
