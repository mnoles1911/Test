#pragma once

// BiomeField — the per-column biome classifier + parameter blender that
// drives the biome-aware heightmap generator.
//
// WHAT THIS IS (plain English): the world is divided into biomes (plains,
// hills, forest, desert, mountains). Instead of stamping hard borders, we
// run two very-low-frequency "control" noises — RELIEF (how mountainous)
// and MOISTURE (how wet) — domain-warped by a third noise so the borders
// wander organically. A Whittaker-style classifier turns (relief, moisture)
// into a biome, and near a border we BLEND the heightfield PARAMETERS of
// the neighbouring biomes (never the finished heights) so terrain morphs
// smoothly from one biome into the next with no seam.
//
// Two consumers:
//   1. The headless `biome` parity gate instantiates BiomeFieldCpp directly
//      (it's a godot::Resource registered in ClassDB) and compares its
//      weights / blended params / ground-Y against the pure-GD
//      BiomeReference.gd, exactly like the gravity/emissive ports.
//   2. HeightmapGeneratorBase owns one BiomeField instance; when biome
//      profiles are loaded, compute_ground_y + the block-fill material/
//      flora selection read from it. With NO profiles set the generator
//      keeps its legacy single-recipe path bit-for-bit (so the `gen`
//      baseline and Copper Isles are untouched).
//
// Worker-thread safety: all state is value-typed (POD vectors + scalars)
// published from the main thread before streaming. resolve_* are pure
// functions of that state + a FastNoiseLite ref (sampled read-only).

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <cstdint>
#include <vector>

namespace voxel_gen {

// Heightfield + surface + vegetation parameters for ONE biome. Mirrors
// scripts/BiomeProfile.gd field-for-field (the GDScript adapter flattens
// a BiomeProfile resource into a plain Dictionary the C++ side parses
// into this POD — same convention as OreMaterialPOD).
//
// Frequencies are PER-METRE (scale-proof). The generator multiplies by
// voxels-per-metre at sample time so the world keeps its metre-shape if
// the voxel grid scale ever changes again.
struct BiomeProfilePOD {
    // --- Heightfield ---
    double base_amplitude_m = 8.0;       // metres of macro relief (half-range)
    double base_frequency_per_m = 0.0012; // macro noise frequency, cycles/metre
    double ridge_mix = 0.0;              // 0 = fBm billow, 1 = ridged |noise| crests
    double flatness = 0.0;               // 0..1 plateau redistribution strength
    double terrace_band_m = 0.0;         // 0 = off; else band height in metres
    double terrace_sharpness = 0.5;      // 0..1 lip rounding
    double mid_amplitude_m = 1.7;        // mid-frequency detail amplitude (m)
    double detail_amplitude_m = 0.3;     // fine detail amplitude (m)
    bool detail_slope_only = false;      // suppress detail on near-flat ground

    // --- Surface ---
    int top_material_id = 3;             // grass
    int slope_material_id = 1;           // stone
    double slope_threshold = 1.2;        // rise/run that reads as "slope"
    int patch_material_id = 0;           // 0 = no scatter patches
    double patch_frequency_per_m = 0.08;
    double patch_threshold = 0.0;        // 0 = patches off
    double micro_relief_chance = 0.0;    // 0..1 pebble-density bias

    // --- Vegetation ---
    double grass_density = 0.35;         // fraction of grass columns with a blade
    double flower_density = 0.02;        // fraction with a flower

    // --- Identity ---
    // biome_name + debug_color stay GDScript-side (not needed in the hot
    // loop); the gate reads them off the .tres directly.
};

class BiomeFieldCpp : public godot::Resource {
    GDCLASS(BiomeFieldCpp, godot::Resource)

public:
    BiomeFieldCpp();
    ~BiomeFieldCpp();

    // --- Configuration (main thread, before streaming) ---

    // Parse Array[Dictionary] (one dict per biome, in a FIXED order that
    // both the GD reference and the classifier agree on) into the POD
    // vector. The classifier maps a biome KIND to an index by name, so
    // the array order itself does not matter for classification — see
    // set_biome_field_params for the kind→profile binding.
    void set_biome_profiles(const godot::Array &p_list);
    int get_biome_profile_count() const;

    // Control-noise + classification knobs. blend_margin is the distance-
    // to-threshold falloff width (normalized 0..1 control space). The five
    // *_index args bind each Whittaker biome KIND to a profile slot in the
    // array set above (-1 = "this kind not loaded"); this lets the gate /
    // bootstrap load any subset and still classify deterministically.
    void set_biome_field_params(double control_frequency_per_m,
                                double warp_frequency_per_m,
                                double warp_strength,
                                double blend_margin,
                                double voxels_per_metre,
                                int plains_index,
                                int hills_index,
                                int forest_index,
                                int desert_index,
                                int mountains_index);

    void set_control_noise(const godot::Ref<godot::FastNoiseLite> &p_noise);
    godot::Ref<godot::FastNoiseLite> get_control_noise() const;

    // --- Query API (worker-thread safe; pure fn of config + noise) ---

    // Returns { indices: PackedInt32Array, weights: PackedFloat64Array }
    // — up to 3 contributing profile slots, weights summing to 1.0,
    // sorted by descending weight then ascending index (total order so GD
    // + C++ never disagree).
    godot::Dictionary resolve_biome_weights(int world_x, int world_z) const;

    // Blended heightfield params at a column (Σ w_i × profile_i). Returns a
    // Dictionary with every BiomeProfilePOD heightfield scalar (bools as
    // 0..1 factors). Surface/flora are NOT blended — those come from a
    // single weighted-hash-picked biome (see pick_surface_biome).
    godot::Dictionary blended_height_params(int world_x, int world_z) const;

    // Final ground voxel-Y at a column, computed ONCE from the blended
    // params. This is the biome path's compute_ground_y.
    int compute_ground_y(int world_x, int world_z) const;

    // The profile slot whose SURFACE rules drive materials/flora at this
    // column. Deterministic weighted pick over the (≤3) contributors by a
    // per-(x,z,seed) hash so borders dither organically instead of cutting
    // a hard material line. Returns the profile index (or -1 if empty).
    int pick_surface_biome(int world_x, int world_z) const;

    // Dominant (highest-weight) profile slot — used by FarGrassManager-style
    // "is this region grassy?" cheap checks and the debug readout.
    int dominant_biome(int world_x, int world_z) const;

    // Convenience: read a profile POD field for a slot (gate + generator).
    bool has_profiles() const { return !_profiles.empty(); }
    const BiomeProfilePOD &profile_at(int index) const { return _profiles[index]; }
    int profile_count() const { return static_cast<int>(_profiles.size()); }

    double get_voxels_per_metre() const { return _voxels_per_metre; }

protected:
    static void _bind_methods();

    // The Whittaker classifier — maps (relief, moisture) in [0,1] to a
    // biome KIND, returning the bound profile INDEX (or -1). Pulled out so
    // the GD reference can mirror it exactly. Border-blend uses the signed
    // distance of (relief, moisture) to each decision boundary.
    int classify_kind_index(double relief, double moisture) const;

    // Sample the two control fields (domain-warped) at a column. Outputs in
    // [0,1]. FastNoiseLite returns [-1,1]; we remap to [0,1].
    void sample_controls(int world_x, int world_z, double &out_relief,
                         double &out_moisture) const;

    // Per-biome ground height from a fully-resolved BiomeProfilePOD (the
    // blended params). Pure math on the control/detail noises.
    double height_from_params(int world_x, int world_z,
                              const BiomeProfilePOD &p) const;

private:
    std::vector<BiomeProfilePOD> _profiles;
    godot::Ref<godot::FastNoiseLite> _control_noise;

    double _control_frequency_per_m = 0.00167; // ~1/600 m
    double _warp_frequency_per_m = 0.0008;
    double _warp_strength = 140.0;             // metres of domain warp
    double _blend_margin = 0.06;
    double _voxels_per_metre = 10.0;

    // Whittaker KIND → profile slot bindings (-1 = not loaded).
    int _idx_plains = -1;
    int _idx_hills = -1;
    int _idx_forest = -1;
    int _idx_desert = -1;
    int _idx_mountains = -1;
};

}  // namespace voxel_gen
