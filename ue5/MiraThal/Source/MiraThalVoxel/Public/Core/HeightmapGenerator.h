// HeightmapGenerator.h — engine-agnostic terrain heightmap + biome generator.
//
// WHAT THIS IS (plain English):
// This is the Core-layer port of the Godot voxel terrain generator. In the
// Godot build the logic lives across three godot-cpp files:
//   * cubic_heightmap_generator.cpp  — the three-layer macro/mid/detail noise
//                                       heightfield + 8m-quantize toggle
//   * heightmap_generator_base.cpp   — the material banding rules (grass/dirt/
//                                       stone), bedrock + sea level, and the
//                                       hash3-based flora / surface-detail /
//                                       ore scatter
//   * biome_field.cpp                — the Whittaker relief/moisture biome
//                                       classifier + per-biome parameter blend
// All three used Godot's FastNoiseLite, Variant, and PackedArrays. This Core
// version is PURE C++17: it samples mira::noise (Core/Noise.h) instead of
// FastNoiseLite and works in plain ints/doubles. It must compile both inside
// the Unreal module and standalone under clang (no engine headers).
//
// FAITHFUL-STRUCTURE, NOT BIT-EXACT (see Core/Noise.h for the full note):
// The noise field differs from Godot's FastNoiseLite, so absolute ground
// heights won't match the Godot baseline voxel-for-voxel. What IS preserved
// 1:1: the layer stack, the quantize flag, the sea-level offset, the biome
// relief blend, the banding rules, the material id ranges, and the integer
// hash3 used for flora/ore scatter (carried over with the SAME primes so the
// scatter pattern keeps its gameplay character). Tests assert determinism and
// structural correctness rather than Godot parity.
//
// MATERIAL ID RANGES (verified against the Godot sources; do not change):
//   terrain band : stone=1, dirt=2, grass=3, sand=4, marble=9, stone_dark=14
//   trees        : log=10, leaves=11
//   water source : fluid ids 16..23 (full level = 23); DATA5 source byte 0x18
//   flora        : grass blade=24, flower_red=25, flower_blue=26
//   surface det. : pebble=27, twig=28
//
// SEA LEVEL + FLOOR CONSTANTS (carried over from the 10 vox/m sources):
//   sea_level_voxels   = 120  (= 12 m at 10 vox/m)
//   world_floor_voxel_y= -500 (= -50 m)
//   beach_y_threshold  = 74
//   height_offset_voxels = 100 (legacy no-biome path)

#pragma once

#include <cstdint>
#include <vector>

#include "Core/Noise.h"
#include "Core/MaterialIds.h" // single authority for the mira::mat ids (incl. the
                              // TREE_LOG / FLORA_GRASS_BLADE / ... aliases below)

namespace mira {

// =============================================================================
// hash3 — the gameplay scatter hash, ported 1:1 from VoxelGenerationMath.gd /
// voxel_gen_math.cpp. This is NOT the noise-field hash; it is the integer hash
// the generator uses for ore veins, marble jitter, disk anchors, flora and
// surface-detail scatter, and the biome surface pick. Carried over verbatim
// (same four primes, same 24-bit truncate, same double divide) so the scatter
// PATTERN keeps its character. Returns a deterministic value in [0, 1].
// =============================================================================
inline double hash3(int64_t x, int64_t y, int64_t z, int64_t seed = 0) {
    int64_t h = ((x * 73856093LL) ^ (y * 19349663LL) ^ (z * 83492791LL)
                 ^ (seed * 39916801LL)) & 0xFFFFFFLL;
    return static_cast<double>(h) / static_cast<double>(0xFFFFFFLL);
}

// Material id constants now live in Core/MaterialIds.h (the single authority),
// included above. It defines mira::mat with the canonical ids PLUS the alias
// names this generator uses (TREE_LOG, FLORA_GRASS_BLADE, WATER_FULL, ...).

// =============================================================================
// BiomeProfile — one biome's heightfield + surface + vegetation recipe.
// Mirrors BiomeProfilePOD in biome_field.h field-for-field (only the fields
// the Core path actually reads are carried; tree species ranges included so
// the scatter stays complete).
// =============================================================================
struct BiomeProfile {
    // --- Heightfield ---
    double base_amplitude_m      = 8.0;
    double base_frequency_per_m  = 0.0012;
    double ridge_mix             = 0.0;
    double flatness              = 0.0;
    double terrace_band_m        = 0.0;
    double terrace_sharpness     = 0.5;
    double mid_amplitude_m       = 1.7;
    double detail_amplitude_m    = 0.3;
    bool   detail_slope_only     = false;

    // --- Surface ---
    int    top_material_id       = mat::GRASS;
    int    slope_material_id     = mat::STONE;
    double slope_threshold       = 1.2;
    int    patch_material_id     = 0;
    double patch_frequency_per_m = 0.08;
    double patch_threshold       = 0.0;
    double micro_relief_chance   = 0.0;

    // --- Vegetation ---
    double grass_density         = 0.35;
    double flower_density        = 0.02;

    // --- Trees ---
    double tree_density          = 0.0;
};

// =============================================================================
// A single resolved voxel-column "stack": what the generator decided sits
// above/at/below the ground for this (x, z). The test harness inspects this
// to verify the banding + water rules without needing a Zylann VoxelBuffer.
// =============================================================================
struct ColumnInfo {
    int  ground_y     = 0;     // surface voxel-Y (top solid voxel)
    int  top_id       = mat::GRASS;  // material of the topmost solid voxel
    int  dirt_band_end = 0;    // depth at which dirt gives way to stone
    bool is_cliff     = false;
    bool below_sea    = false; // ground dips below sea level → water column
    int  flora_id     = 0;     // flora/detail voxel above the surface (0 = none)
    int  biome_index  = -1;    // surface biome slot picked (or -1 on legacy path)
};

// =============================================================================
// HeightmapGenerator — the ported generator.
//
// Two height paths, exactly like the Godot source:
//   * LEGACY (no biome profiles loaded): the three-layer cubic noise
//     heightfield + height_offset_voxels. This is the path the Godot `gen`
//     parity baseline was captured on.
//   * BIOME (profiles loaded via set_biome_profiles): per-column Whittaker
//     classification + soft-weight parameter blend + biome heightfield,
//     offset by sea_level_voxels.
//
// All knobs default to the 10 vox/m source values.
// =============================================================================
class HeightmapGenerator {
public:
    HeightmapGenerator() = default;

    // ---- Noise seed (replaces the FastNoiseLite resource) ----
    void set_seed(int64_t s) { seed_ = s; }
    int64_t seed() const { return seed_; }

    // ---- Legacy three-layer cubic params (cubic_heightmap_generator.h) ----
    double height_range_voxels       = 1500.0;
    int    height_offset_voxels      = 100;
    bool   quantize_to_meters        = false;
    int    mid_amplitude_voxels      = 17;
    double mid_frequency_multiplier  = 3.0;
    int    detail_amplitude_voxels   = 3;
    double detail_frequency_multiplier = 12.0;
    // The macro layer's base frequency (FastNoiseLite defaulted to ~0.01/unit;
    // the legacy path multiplied x/z directly so we pick a small base here so
    // macro relief is large-scale, not per-voxel speckle).
    double macro_frequency           = 0.0008;

    // ---- Band layout (heightmap_generator_base.h) ----
    int    grass_layer_thickness_voxels = 1;
    int    dirt_layer_thickness_voxels  = 3;
    int    beach_y_threshold            = 74;

    // ---- Bedrock / world floor / sea (10 vox/m constants) ----
    int    bedrock_material_id = 0;     // 0 disables the bedrock row
    int    world_floor_voxel_y = -500;  // -50 m
    int    sea_level_voxels    = 120;   // 12 m

    // ---- Tier 1 cliff slope ----
    int    cliff_slope_sample_distance_voxels = 10;
    int    cliff_slope_threshold_voxels       = 17;

    // ---- Tier 3 marble jitter ----
    int    marble_jitter_block_size = 4;
    int64_t marble_jitter_seed      = 1;
    double marble_rare_threshold    = 0.92;
    double marble_dark_threshold    = 0.75;

    // ---- R4 flora scatter (Core defaults wire the real ids) ----
    int    grass_blade_material_id = mat::FLORA_GRASS_BLADE;
    int    flower_red_material_id  = mat::FLORA_FLOWER_RED;
    int    flower_blue_material_id = mat::FLORA_FLOWER_BLUE;
    int64_t flora_seed             = 1337;

    // ---- D1 surface-detail scatter ----
    int    pebble_material_id      = mat::DETAIL_PEBBLE;
    int    twig_material_id        = mat::DETAIL_TWIG;
    int64_t surface_detail_seed    = 7919;

    // ---- Biome field params (biome_field.h) ----
    double control_frequency_per_m = 0.00167; // ~1/600 m
    double warp_frequency_per_m    = 0.0008;
    double warp_strength           = 140.0;
    double blend_margin            = 0.06;
    double voxels_per_metre        = 10.0;

    // Whittaker KIND → profile slot bindings (-1 = not loaded).
    int idx_plains    = -1;
    int idx_hills     = -1;
    int idx_forest    = -1;
    int idx_desert    = -1;
    int idx_mountains = -1;

    // ---- Biome profile loading ----
    void set_biome_profiles(const std::vector<BiomeProfile>& profiles) {
        profiles_ = profiles;
    }
    bool biome_active() const { return !profiles_.empty(); }
    int  profile_count() const { return static_cast<int>(profiles_.size()); }

    // =========================================================================
    // CORE API
    // =========================================================================

    // The surface voxel-Y for a world column. Routes to the biome path when
    // profiles are loaded (biome ground-Y + sea-level offset), else the legacy
    // three-layer cubic noise. Mirror of compute_ground_y.
    int compute_ground_y(int world_x, int world_z) const;

    // Tier 1: steep drop to any 4-neighbour at ±sample_distance. Mirror of
    // column_is_cliff.
    bool column_is_cliff(int world_x, int world_z, int this_ground_y) const;

    // Resolve the full column decision (top material, banding, water flag,
    // flora) for one (x, z). This folds the per-column logic out of the Zylann
    // block loop so the Core + tests can reason about a column without a
    // VoxelBuffer.
    ColumnInfo resolve_column(int world_x, int world_z) const;

    // The material id at an absolute (world_x, world_y, world_z) given a
    // resolved column. Implements the band selection + bedrock + marble jitter.
    // Returns mat::AIR for cells above ground (caller layers water/flora on
    // top). This is the per-voxel inner-loop body.
    int material_at(int world_x, int world_y, int world_z, const ColumnInfo& col) const;

    // ---- Biome query helpers (mirror BiomeFieldCpp) ----
    // Up to 3 contributing profile slots + their weights (summing to 1.0),
    // sorted descending weight then ascending index.
    void resolve_biome_weights(int world_x, int world_z,
                               int out_indices[3], double out_weights[3],
                               int& out_count) const;
    int pick_surface_biome(int world_x, int world_z) const;
    int dominant_biome(int world_x, int world_z) const;

private:
    int64_t seed_ = 0;
    std::vector<BiomeProfile> profiles_;

    // Legacy three-layer noise heightfield.
    int legacy_ground_y(int world_x, int world_z) const;

    // Biome path internals (mirror biome_field.cpp).
    void   sample_controls(int world_x, int world_z,
                           double& out_relief, double& out_moisture) const;
    int    classify_kind_index(double relief, double moisture) const;
    BiomeProfile blend_profiles(const int indices[3], const double weights[3],
                                int count) const;
    double height_from_params(int world_x, int world_z, const BiomeProfile& p) const;
    int    biome_ground_y(int world_x, int world_z) const;
};

} // namespace mira
