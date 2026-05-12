#include "cubic_heightmap_generator.h"

#include "voxel_gen_math.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

// Zylann VoxelBuffer channel indices.
// CHANNEL_TYPE = 0 (material id), CHANNEL_DATA5 = 5 (first user channel,
// used here for the Minecraft-style water byte).
static constexpr int CHANNEL_TYPE = 0;
static constexpr int CHANNEL_DATA5 = 5;

// Canonical water source byte. Mirrors WaterByteCodec.SOURCE_BYTE
// (MAX_LEVEL=8 | SOURCE_BIT=0x10 = 0x18 = 24). Worker-thread-safe to
// hardcode because the codec layout is locked.
static constexpr int WATER_SOURCE_BYTE = 0x18;

// Material IDs match the .tres files under assets/voxels/materials/.
// Hardcoded for Phase 2-3; Phase 4 will refactor to read from
// VoxelMaterialSnapshot POD structs pushed from the bootstrap.
static constexpr int STONE_MATERIAL_ID = 1;
static constexpr int DIRT_MATERIAL_ID = 2;
static constexpr int GRASS_MATERIAL_ID = 3;
static constexpr int SAND_MATERIAL_ID = 4;
static constexpr int MARBLE_MATERIAL_ID = 9;
static constexpr int STONE_DARK_MATERIAL_ID = 14;

CubicHeightmapGeneratorCpp::CubicHeightmapGeneratorCpp() {}
CubicHeightmapGeneratorCpp::~CubicHeightmapGeneratorCpp() {}

// ----- Property setters / getters ----------------------------------------

void CubicHeightmapGeneratorCpp::set_noise(const Ref<FastNoiseLite> &p_noise) { _noise = p_noise; }
Ref<FastNoiseLite> CubicHeightmapGeneratorCpp::get_noise() const { return _noise; }

void CubicHeightmapGeneratorCpp::set_height_range_voxels(double p_value) { _height_range_voxels = p_value; }
double CubicHeightmapGeneratorCpp::get_height_range_voxels() const { return _height_range_voxels; }

void CubicHeightmapGeneratorCpp::set_height_offset_voxels(int p_value) { _height_offset_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_height_offset_voxels() const { return _height_offset_voxels; }

void CubicHeightmapGeneratorCpp::set_quantize_to_meters(bool p_value) { _quantize_to_meters = p_value; }
bool CubicHeightmapGeneratorCpp::get_quantize_to_meters() const { return _quantize_to_meters; }

void CubicHeightmapGeneratorCpp::set_mid_amplitude_voxels(int p_value) { _mid_amplitude_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_mid_amplitude_voxels() const { return _mid_amplitude_voxels; }

void CubicHeightmapGeneratorCpp::set_mid_frequency_multiplier(double p_value) { _mid_frequency_multiplier = p_value; }
double CubicHeightmapGeneratorCpp::get_mid_frequency_multiplier() const { return _mid_frequency_multiplier; }

void CubicHeightmapGeneratorCpp::set_detail_amplitude_voxels(int p_value) { _detail_amplitude_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_detail_amplitude_voxels() const { return _detail_amplitude_voxels; }

void CubicHeightmapGeneratorCpp::set_detail_frequency_multiplier(double p_value) { _detail_frequency_multiplier = p_value; }
double CubicHeightmapGeneratorCpp::get_detail_frequency_multiplier() const { return _detail_frequency_multiplier; }

// Phase 3 setters/getters
void CubicHeightmapGeneratorCpp::set_grass_layer_thickness_voxels(int p_value) { _grass_layer_thickness_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_grass_layer_thickness_voxels() const { return _grass_layer_thickness_voxels; }

void CubicHeightmapGeneratorCpp::set_dirt_layer_thickness_voxels(int p_value) { _dirt_layer_thickness_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_dirt_layer_thickness_voxels() const { return _dirt_layer_thickness_voxels; }

void CubicHeightmapGeneratorCpp::set_beach_y_threshold(int p_value) { _beach_y_threshold = p_value; }
int CubicHeightmapGeneratorCpp::get_beach_y_threshold() const { return _beach_y_threshold; }

void CubicHeightmapGeneratorCpp::set_marble_jitter_block_size(int p_value) { _marble_jitter_block_size = p_value; }
int CubicHeightmapGeneratorCpp::get_marble_jitter_block_size() const { return _marble_jitter_block_size; }

void CubicHeightmapGeneratorCpp::set_marble_jitter_seed(int p_value) { _marble_jitter_seed = p_value; }
int CubicHeightmapGeneratorCpp::get_marble_jitter_seed() const { return _marble_jitter_seed; }

void CubicHeightmapGeneratorCpp::set_marble_rare_threshold(double p_value) { _marble_rare_threshold = p_value; }
double CubicHeightmapGeneratorCpp::get_marble_rare_threshold() const { return _marble_rare_threshold; }

void CubicHeightmapGeneratorCpp::set_marble_dark_threshold(double p_value) { _marble_dark_threshold = p_value; }
double CubicHeightmapGeneratorCpp::get_marble_dark_threshold() const { return _marble_dark_threshold; }

void CubicHeightmapGeneratorCpp::set_marble_jitter_max_lod(int p_value) { _marble_jitter_max_lod = p_value; }
int CubicHeightmapGeneratorCpp::get_marble_jitter_max_lod() const { return _marble_jitter_max_lod; }

// Phase 4a setters/getters
void CubicHeightmapGeneratorCpp::set_bedrock_material_id(int p_value) { _bedrock_material_id = p_value; }
int CubicHeightmapGeneratorCpp::get_bedrock_material_id() const { return _bedrock_material_id; }

void CubicHeightmapGeneratorCpp::set_world_floor_voxel_y(int p_value) { _world_floor_voxel_y = p_value; }
int CubicHeightmapGeneratorCpp::get_world_floor_voxel_y() const { return _world_floor_voxel_y; }

void CubicHeightmapGeneratorCpp::set_sea_level_voxels(int p_value) { _sea_level_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_sea_level_voxels() const { return _sea_level_voxels; }

// Phase 4b setters/getters
void CubicHeightmapGeneratorCpp::set_snow_material_id(int p_value) { _snow_material_id = p_value; }
int CubicHeightmapGeneratorCpp::get_snow_material_id() const { return _snow_material_id; }

void CubicHeightmapGeneratorCpp::set_snow_line_voxels(int p_value) { _snow_line_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_snow_line_voxels() const { return _snow_line_voxels; }

void CubicHeightmapGeneratorCpp::set_snow_line_jitter_voxels(int p_value) { _snow_line_jitter_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_snow_line_jitter_voxels() const { return _snow_line_jitter_voxels; }

void CubicHeightmapGeneratorCpp::set_snow_line_jitter_block_size(int p_value) { _snow_line_jitter_block_size = p_value; }
int CubicHeightmapGeneratorCpp::get_snow_line_jitter_block_size() const { return _snow_line_jitter_block_size; }

void CubicHeightmapGeneratorCpp::set_snow_line_seed(int p_value) { _snow_line_seed = p_value; }
int CubicHeightmapGeneratorCpp::get_snow_line_seed() const { return _snow_line_seed; }

void CubicHeightmapGeneratorCpp::set_snow_line_max_lod(int p_value) { _snow_line_max_lod = p_value; }
int CubicHeightmapGeneratorCpp::get_snow_line_max_lod() const { return _snow_line_max_lod; }

// Phase 4c setters/getters
void CubicHeightmapGeneratorCpp::set_cliff_slope_sample_distance_voxels(int p_value) { _cliff_slope_sample_distance_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_cliff_slope_sample_distance_voxels() const { return _cliff_slope_sample_distance_voxels; }

void CubicHeightmapGeneratorCpp::set_cliff_slope_threshold_voxels(int p_value) { _cliff_slope_threshold_voxels = p_value; }
int CubicHeightmapGeneratorCpp::get_cliff_slope_threshold_voxels() const { return _cliff_slope_threshold_voxels; }

void CubicHeightmapGeneratorCpp::set_cliff_rule_max_lod(int p_value) { _cliff_rule_max_lod = p_value; }
int CubicHeightmapGeneratorCpp::get_cliff_rule_max_lod() const { return _cliff_rule_max_lod; }

// Tier 1 helper. Mirrors scripts/CubicHeightmapGenerator.gd:599 _column_is_cliff.
// Worker-thread safe — only reads instance config + calls compute_ground_y
// (which is itself pure).
bool CubicHeightmapGeneratorCpp::column_is_cliff(int world_x, int world_z, int this_ground_y) const {
    const int step = _cliff_slope_sample_distance_voxels;
    if (step <= 0 || _cliff_slope_threshold_voxels <= 0) {
        return false;
    }
    int max_drop = 0;
    const int dn = this_ground_y - compute_ground_y(world_x - step, world_z);
    if (dn > max_drop) max_drop = dn;
    const int dp = this_ground_y - compute_ground_y(world_x + step, world_z);
    if (dp > max_drop) max_drop = dp;
    const int dzn = this_ground_y - compute_ground_y(world_x, world_z - step);
    if (dzn > max_drop) max_drop = dzn;
    const int dzp = this_ground_y - compute_ground_y(world_x, world_z + step);
    if (dzp > max_drop) max_drop = dzp;
    return max_drop >= _cliff_slope_threshold_voxels;
}

// ----- Core: ground_y at a world (x, z) column ---------------------------
//
// Mirror of scripts/CubicHeightmapGenerator.gd _ground_y_at (line 572).
//
// Source GDScript (preserved here verbatim for cross-reference):
//
//   if noise == null:
//       return height_offset_voxels
//   var half_range: float = height_range_voxels * 0.5
//   var n_macro = noise.get_noise_2d(float(world_x), float(world_z))
//   var macro_y: int
//   if quantize_to_meters:
//       var macro_meters = roundi(n_macro * half_range / 8.0)
//       macro_y = macro_meters * 8
//   else:
//       macro_y = int(n_macro * half_range)
//   var n_mid = noise.get_noise_2d(world_x * mid_freq, world_z * mid_freq)
//   var mid_y = int(n_mid * mid_amplitude_voxels)
//   var n_detail = noise.get_noise_2d(world_x * detail_freq, world_z * detail_freq)
//   var detail_y = int(n_detail * detail_amplitude_voxels)
//   return macro_y + mid_y + detail_y + height_offset_voxels
//
// Parity gotchas:
//   * int(float) in GDScript truncates toward zero. static_cast<int>(double)
//     in C++ also truncates toward zero (C++ standard).
//   * roundi(float) in GDScript rounds half-away-from-zero. std::lround
//     (C++) matches.
//   * Single-precision vs double-precision matters: FastNoiseLite::get_noise_2d
//     returns float (single precision). We do all subsequent math in double
//     because GDScript float is double; if we used float here, late
//     accumulation could differ. Match GD exactly: store noise result in
//     double immediately after sampling.
int CubicHeightmapGeneratorCpp::compute_ground_y(int world_x, int world_z) const {
    if (_noise.is_null()) {
        return _height_offset_voxels;
    }

    const double half_range = _height_range_voxels * 0.5;

    const double n_macro = static_cast<double>(_noise->get_noise_2d(static_cast<double>(world_x),
                                                                   static_cast<double>(world_z)));
    int macro_y;
    if (_quantize_to_meters) {
        const long macro_meters = std::lround(n_macro * half_range / 8.0);
        macro_y = static_cast<int>(macro_meters * 8L);
    } else {
        macro_y = static_cast<int>(n_macro * half_range);
    }

    const double n_mid = static_cast<double>(_noise->get_noise_2d(
            static_cast<double>(world_x) * _mid_frequency_multiplier,
            static_cast<double>(world_z) * _mid_frequency_multiplier));
    const int mid_y = static_cast<int>(n_mid * static_cast<double>(_mid_amplitude_voxels));

    const double n_detail = static_cast<double>(_noise->get_noise_2d(
            static_cast<double>(world_x) * _detail_frequency_multiplier,
            static_cast<double>(world_z) * _detail_frequency_multiplier));
    const int detail_y = static_cast<int>(n_detail * static_cast<double>(_detail_amplitude_voxels));

    return macro_y + mid_y + detail_y + _height_offset_voxels;
}

// ----- Block fill: Tier 0 only -------------------------------------------

void CubicHeightmapGeneratorCpp::generate_block_into_buffer(Variant out_buffer,
                                                            Vector3i origin_in_voxels,
                                                            int lod) {
    // Discover buffer dimensions via Zylann's VoxelBuffer.get_size().
    Variant size_v = out_buffer.call("get_size");
    if (size_v.get_type() != Variant::VECTOR3I) {
        UtilityFunctions::printerr(
                "CubicHeightmapGeneratorCpp: out_buffer.get_size() did not return Vector3i");
        return;
    }
    Vector3i size = size_v;

    // LOD stride: at LOD 0 each voxel covers 1 world unit; at LOD n it covers
    // 2^n. The GD original applies the same stride for noise sampling.
    const int stride = 1 << lod;

    // Pre-compute per-block constants for the inner loop. Mirrors the
    // GD generator's hot-loop optimization: read properties once, then
    // the y-loop reads only local variables.
    const int grass_thick = _grass_layer_thickness_voxels;
    const int dirt_band_end = grass_thick + _dirt_layer_thickness_voxels;
    const int beach_y = _beach_y_threshold;

    // Tier 3 marble cache. block_size clamped to >=1 to avoid div-by-zero.
    const int jitter_block = _marble_jitter_block_size < 1 ? 1 : _marble_jitter_block_size;
    const int64_t jitter_seed = _marble_jitter_seed;
    const double jitter_marble = _marble_rare_threshold;
    const double jitter_dark = _marble_dark_threshold;
    const bool run_marble_jitter = _marble_jitter_max_lod >= 0 && lod <= _marble_jitter_max_lod;

    // Phase 4a caches — bedrock + water emission.
    // Water emission is LOD0-only (matches GD `write_water = (lod == 0)`).
    // NoEditZone-water-AABB suppression from the GD generator is
    // deliberately omitted here — that feature is no longer used in the
    // project and dropping it keeps the C++ port simple and fast.
    const int world_floor_y = _world_floor_voxel_y;
    const int bedrock_id = _bedrock_material_id;
    const int sea_level_v = _sea_level_voxels;
    const bool write_water = (lod == 0);

    // Phase 4b caches — snow line (Tier 2). Gated by snow_material_id != 0
    // (mirrors the GD `snow_id != 0` check that triggers when the
    // snow.tres resource was loaded) and snow_line_max_lod.
    const int snow_id = _snow_material_id;
    const int snow_alt_voxels = _snow_line_voxels;
    const int snow_block = _snow_line_jitter_block_size < 1 ? 1 : _snow_line_jitter_block_size;
    const double snow_jitter_amp = static_cast<double>(_snow_line_jitter_voxels);
    const int64_t snow_seed = _snow_line_seed;
    const bool run_snow_line = snow_id != 0
            && _snow_line_max_lod >= 0
            && lod <= _snow_line_max_lod;

    // Phase 4c — cliff slope (Tier 1). LOD-gated to skip the 4× per-column
    // ground_y resamples at distant LODs.
    const bool run_cliff_rule = _cliff_rule_max_lod >= 0 && lod <= _cliff_rule_max_lod;

    // Walk every (x, z) column. For each, compute ground_y once; pick the
    // top-band material (grass or sand); then walk Y selecting band by
    // depth from ground_y. Phase 3 implements GD's plan-Tier 1 (bands) +
    // plan-Tier 3 (marble). Bedrock (plan-Tier 2), cliff slope (proj-Tier 1),
    // snow line (proj-Tier 2), ores (proj-Tier 4), disks (proj-Tier 5),
    // cliff outcrops (proj-Tier 6), and water emission all stay off.
    for (int z = 0; z < size.z; ++z) {
        for (int x = 0; x < size.x; ++x) {
            const int world_x = origin_in_voxels.x + x * stride;
            const int world_z = origin_in_voxels.z + z * stride;
            const int ground_y = compute_ground_y(world_x, world_z);

            // Top-band selection: grass by default, sand if column dips
            // at or below the beach line. Done once per column.
            int top_id = GRASS_MATERIAL_ID;
            if (ground_y <= beach_y) {
                top_id = SAND_MATERIAL_ID;
            }

            // Phase 4c — Tier 1 cliff slope. When a column has a steep
            // drop to any 4-neighbour, collapse top + dirt to bare stone.
            // The col_dirt_band_end local mirrors GD's per-column override:
            // dirt_band_end normally, grass_thick on cliffs (so depth >= 1
            // lands straight in the stone band — no dirt sandwich on
            // exposed rock faces).
            int col_dirt_band_end = dirt_band_end;
            const bool col_is_cliff = run_cliff_rule
                    && column_is_cliff(world_x, world_z, ground_y);
            if (col_is_cliff) {
                top_id = STONE_MATERIAL_ID;
                col_dirt_band_end = grass_thick;
                // Tier 6 (rare ore outcrops) lands in 4g; nothing here yet.
            }

            // Phase 4b — Tier 2 snow line. Mirrors the GD inner-loop
            // override: non-cliff columns above (snow_alt + jitter) get
            // their top voxel turned to snow. Cliff faces poke through
            // snowcaps because col_is_cliff blocks the override.
            if (run_snow_line && !col_is_cliff && ground_y >= snow_alt_voxels) {
                // GD uses integer-division: world_{x,z} / snow_block.
                // GDScript / on ints truncates toward zero; C++ / on
                // signed ints also truncates toward zero in C++11+.
                // Match by using the same operator.
                const double sj = (voxel_gen::math::hash3(
                                           static_cast<int64_t>(world_x) / snow_block,
                                           0,
                                           static_cast<int64_t>(world_z) / snow_block,
                                           snow_seed)
                                   - 0.5)
                        * 2.0 * snow_jitter_amp;
                if (static_cast<double>(ground_y) >= static_cast<double>(snow_alt_voxels) + sj) {
                    top_id = snow_id;
                }
            }

            // Phase 4a: per-column water-emission gate. Three conditions
            // must hold: LOD=0 (water is LOD0-only), this column's
            // ground dips below sea level (above-water columns stay dry).
            const bool emit_water_here = write_water && ground_y < sea_level_v;

            for (int y = 0; y < size.y; ++y) {
                const int world_y = origin_in_voxels.y + y * stride;
                if (world_y > ground_y) {
                    // Air above terrain. If this air voxel sits at or
                    // below sea level and the column emits water, write
                    // a water source byte into CHANNEL_DATA5. The cube
                    // mesher ignores DATA5, so this voxel still renders
                    // as air — WaterChunkMesher emits the transparent
                    // surface from this byte.
                    if (emit_water_here && world_y <= sea_level_v) {
                        out_buffer.call("set_voxel", WATER_SOURCE_BYTE, x, y, z, CHANNEL_DATA5);
                    }
                    continue;
                }
                // World floor enforcement (Phase 4a):
                //   world_y <  world_floor_y → air (no voxel written)
                //   world_y == world_floor_y → bedrock row (unmineable)
                //   world_y >  world_floor_y → normal band selection below
                if (world_y < world_floor_y) {
                    continue;
                }
                if (world_y == world_floor_y && bedrock_id != 0) {
                    out_buffer.call("set_voxel", bedrock_id, x, y, z, CHANNEL_TYPE);
                    continue;
                }
                // Depth measured DOWN from ground_y. depth=0 is top voxel.
                const int depth = ground_y - world_y;

                int mat_id;
                if (depth < grass_thick) {
                    mat_id = top_id;
                } else if (depth < col_dirt_band_end) {
                    // col_dirt_band_end collapses to grass_thick on cliff
                    // columns (Tier 1), so depth>=1 there falls straight
                    // through to the stone branch below.
                    mat_id = DIRT_MATERIAL_ID;
                } else {
                    // Stone band. Apply marble jitter (Tier 3) if enabled
                    // for this LOD. hash3 inputs use integer division by
                    // jitter_block to read as ~block_size-voxel patches
                    // instead of per-voxel speckle. Mirror GD's
                    // @warning_ignore("integer_division") site exactly.
                    mat_id = STONE_MATERIAL_ID;
                    if (run_marble_jitter) {
                        const double n = voxel_gen::math::hash3(
                                static_cast<int64_t>(world_x) / jitter_block,
                                static_cast<int64_t>(world_y) / jitter_block,
                                static_cast<int64_t>(world_z) / jitter_block,
                                jitter_seed);
                        if (n > jitter_marble) {
                            mat_id = MARBLE_MATERIAL_ID;
                        } else if (n > jitter_dark) {
                            mat_id = STONE_DARK_MATERIAL_ID;
                        }
                    }
                }
                out_buffer.call("set_voxel", mat_id, x, y, z, CHANNEL_TYPE);
            }
        }
    }
}

// ----- ClassDB bindings --------------------------------------------------

void CubicHeightmapGeneratorCpp::_bind_methods() {
    // noise
    ClassDB::bind_method(D_METHOD("set_noise", "noise"), &CubicHeightmapGeneratorCpp::set_noise);
    ClassDB::bind_method(D_METHOD("get_noise"), &CubicHeightmapGeneratorCpp::get_noise);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "noise", PROPERTY_HINT_RESOURCE_TYPE, "FastNoiseLite"),
                 "set_noise", "get_noise");

    // height_range_voxels
    ClassDB::bind_method(D_METHOD("set_height_range_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_height_range_voxels);
    ClassDB::bind_method(D_METHOD("get_height_range_voxels"),
                         &CubicHeightmapGeneratorCpp::get_height_range_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "height_range_voxels"),
                 "set_height_range_voxels", "get_height_range_voxels");

    // height_offset_voxels
    ClassDB::bind_method(D_METHOD("set_height_offset_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_height_offset_voxels);
    ClassDB::bind_method(D_METHOD("get_height_offset_voxels"),
                         &CubicHeightmapGeneratorCpp::get_height_offset_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "height_offset_voxels"),
                 "set_height_offset_voxels", "get_height_offset_voxels");

    // quantize_to_meters
    ClassDB::bind_method(D_METHOD("set_quantize_to_meters", "value"),
                         &CubicHeightmapGeneratorCpp::set_quantize_to_meters);
    ClassDB::bind_method(D_METHOD("get_quantize_to_meters"),
                         &CubicHeightmapGeneratorCpp::get_quantize_to_meters);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "quantize_to_meters"),
                 "set_quantize_to_meters", "get_quantize_to_meters");

    // mid_amplitude_voxels
    ClassDB::bind_method(D_METHOD("set_mid_amplitude_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_mid_amplitude_voxels);
    ClassDB::bind_method(D_METHOD("get_mid_amplitude_voxels"),
                         &CubicHeightmapGeneratorCpp::get_mid_amplitude_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "mid_amplitude_voxels"),
                 "set_mid_amplitude_voxels", "get_mid_amplitude_voxels");

    // mid_frequency_multiplier
    ClassDB::bind_method(D_METHOD("set_mid_frequency_multiplier", "value"),
                         &CubicHeightmapGeneratorCpp::set_mid_frequency_multiplier);
    ClassDB::bind_method(D_METHOD("get_mid_frequency_multiplier"),
                         &CubicHeightmapGeneratorCpp::get_mid_frequency_multiplier);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mid_frequency_multiplier"),
                 "set_mid_frequency_multiplier", "get_mid_frequency_multiplier");

    // detail_amplitude_voxels
    ClassDB::bind_method(D_METHOD("set_detail_amplitude_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_detail_amplitude_voxels);
    ClassDB::bind_method(D_METHOD("get_detail_amplitude_voxels"),
                         &CubicHeightmapGeneratorCpp::get_detail_amplitude_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "detail_amplitude_voxels"),
                 "set_detail_amplitude_voxels", "get_detail_amplitude_voxels");

    // detail_frequency_multiplier
    ClassDB::bind_method(D_METHOD("set_detail_frequency_multiplier", "value"),
                         &CubicHeightmapGeneratorCpp::set_detail_frequency_multiplier);
    ClassDB::bind_method(D_METHOD("get_detail_frequency_multiplier"),
                         &CubicHeightmapGeneratorCpp::get_detail_frequency_multiplier);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "detail_frequency_multiplier"),
                 "set_detail_frequency_multiplier", "get_detail_frequency_multiplier");

    // Phase 3 bindings
    ClassDB::bind_method(D_METHOD("set_grass_layer_thickness_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_grass_layer_thickness_voxels);
    ClassDB::bind_method(D_METHOD("get_grass_layer_thickness_voxels"),
                         &CubicHeightmapGeneratorCpp::get_grass_layer_thickness_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "grass_layer_thickness_voxels"),
                 "set_grass_layer_thickness_voxels", "get_grass_layer_thickness_voxels");

    ClassDB::bind_method(D_METHOD("set_dirt_layer_thickness_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_dirt_layer_thickness_voxels);
    ClassDB::bind_method(D_METHOD("get_dirt_layer_thickness_voxels"),
                         &CubicHeightmapGeneratorCpp::get_dirt_layer_thickness_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "dirt_layer_thickness_voxels"),
                 "set_dirt_layer_thickness_voxels", "get_dirt_layer_thickness_voxels");

    ClassDB::bind_method(D_METHOD("set_beach_y_threshold", "value"),
                         &CubicHeightmapGeneratorCpp::set_beach_y_threshold);
    ClassDB::bind_method(D_METHOD("get_beach_y_threshold"),
                         &CubicHeightmapGeneratorCpp::get_beach_y_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "beach_y_threshold"),
                 "set_beach_y_threshold", "get_beach_y_threshold");

    ClassDB::bind_method(D_METHOD("set_marble_jitter_block_size", "value"),
                         &CubicHeightmapGeneratorCpp::set_marble_jitter_block_size);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_block_size"),
                         &CubicHeightmapGeneratorCpp::get_marble_jitter_block_size);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_block_size"),
                 "set_marble_jitter_block_size", "get_marble_jitter_block_size");

    ClassDB::bind_method(D_METHOD("set_marble_jitter_seed", "value"),
                         &CubicHeightmapGeneratorCpp::set_marble_jitter_seed);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_seed"),
                         &CubicHeightmapGeneratorCpp::get_marble_jitter_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_seed"),
                 "set_marble_jitter_seed", "get_marble_jitter_seed");

    ClassDB::bind_method(D_METHOD("set_marble_rare_threshold", "value"),
                         &CubicHeightmapGeneratorCpp::set_marble_rare_threshold);
    ClassDB::bind_method(D_METHOD("get_marble_rare_threshold"),
                         &CubicHeightmapGeneratorCpp::get_marble_rare_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "marble_rare_threshold"),
                 "set_marble_rare_threshold", "get_marble_rare_threshold");

    ClassDB::bind_method(D_METHOD("set_marble_dark_threshold", "value"),
                         &CubicHeightmapGeneratorCpp::set_marble_dark_threshold);
    ClassDB::bind_method(D_METHOD("get_marble_dark_threshold"),
                         &CubicHeightmapGeneratorCpp::get_marble_dark_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "marble_dark_threshold"),
                 "set_marble_dark_threshold", "get_marble_dark_threshold");

    ClassDB::bind_method(D_METHOD("set_marble_jitter_max_lod", "value"),
                         &CubicHeightmapGeneratorCpp::set_marble_jitter_max_lod);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_max_lod"),
                         &CubicHeightmapGeneratorCpp::get_marble_jitter_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_max_lod"),
                 "set_marble_jitter_max_lod", "get_marble_jitter_max_lod");

    // Phase 4a bindings
    ClassDB::bind_method(D_METHOD("set_bedrock_material_id", "value"),
                         &CubicHeightmapGeneratorCpp::set_bedrock_material_id);
    ClassDB::bind_method(D_METHOD("get_bedrock_material_id"),
                         &CubicHeightmapGeneratorCpp::get_bedrock_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "bedrock_material_id"),
                 "set_bedrock_material_id", "get_bedrock_material_id");

    ClassDB::bind_method(D_METHOD("set_world_floor_voxel_y", "value"),
                         &CubicHeightmapGeneratorCpp::set_world_floor_voxel_y);
    ClassDB::bind_method(D_METHOD("get_world_floor_voxel_y"),
                         &CubicHeightmapGeneratorCpp::get_world_floor_voxel_y);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "world_floor_voxel_y"),
                 "set_world_floor_voxel_y", "get_world_floor_voxel_y");

    ClassDB::bind_method(D_METHOD("set_sea_level_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_sea_level_voxels);
    ClassDB::bind_method(D_METHOD("get_sea_level_voxels"),
                         &CubicHeightmapGeneratorCpp::get_sea_level_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "sea_level_voxels"),
                 "set_sea_level_voxels", "get_sea_level_voxels");

    // Phase 4b bindings — snow line
    ClassDB::bind_method(D_METHOD("set_snow_material_id", "value"),
                         &CubicHeightmapGeneratorCpp::set_snow_material_id);
    ClassDB::bind_method(D_METHOD("get_snow_material_id"),
                         &CubicHeightmapGeneratorCpp::get_snow_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_material_id"),
                 "set_snow_material_id", "get_snow_material_id");

    ClassDB::bind_method(D_METHOD("set_snow_line_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_snow_line_voxels);
    ClassDB::bind_method(D_METHOD("get_snow_line_voxels"),
                         &CubicHeightmapGeneratorCpp::get_snow_line_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_voxels"),
                 "set_snow_line_voxels", "get_snow_line_voxels");

    ClassDB::bind_method(D_METHOD("set_snow_line_jitter_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_snow_line_jitter_voxels);
    ClassDB::bind_method(D_METHOD("get_snow_line_jitter_voxels"),
                         &CubicHeightmapGeneratorCpp::get_snow_line_jitter_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_jitter_voxels"),
                 "set_snow_line_jitter_voxels", "get_snow_line_jitter_voxels");

    ClassDB::bind_method(D_METHOD("set_snow_line_jitter_block_size", "value"),
                         &CubicHeightmapGeneratorCpp::set_snow_line_jitter_block_size);
    ClassDB::bind_method(D_METHOD("get_snow_line_jitter_block_size"),
                         &CubicHeightmapGeneratorCpp::get_snow_line_jitter_block_size);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_jitter_block_size"),
                 "set_snow_line_jitter_block_size", "get_snow_line_jitter_block_size");

    ClassDB::bind_method(D_METHOD("set_snow_line_seed", "value"),
                         &CubicHeightmapGeneratorCpp::set_snow_line_seed);
    ClassDB::bind_method(D_METHOD("get_snow_line_seed"),
                         &CubicHeightmapGeneratorCpp::get_snow_line_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_seed"),
                 "set_snow_line_seed", "get_snow_line_seed");

    ClassDB::bind_method(D_METHOD("set_snow_line_max_lod", "value"),
                         &CubicHeightmapGeneratorCpp::set_snow_line_max_lod);
    ClassDB::bind_method(D_METHOD("get_snow_line_max_lod"),
                         &CubicHeightmapGeneratorCpp::get_snow_line_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_max_lod"),
                 "set_snow_line_max_lod", "get_snow_line_max_lod");

    // Phase 4c bindings — cliff slope
    ClassDB::bind_method(D_METHOD("set_cliff_slope_sample_distance_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_cliff_slope_sample_distance_voxels);
    ClassDB::bind_method(D_METHOD("get_cliff_slope_sample_distance_voxels"),
                         &CubicHeightmapGeneratorCpp::get_cliff_slope_sample_distance_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_slope_sample_distance_voxels"),
                 "set_cliff_slope_sample_distance_voxels", "get_cliff_slope_sample_distance_voxels");

    ClassDB::bind_method(D_METHOD("set_cliff_slope_threshold_voxels", "value"),
                         &CubicHeightmapGeneratorCpp::set_cliff_slope_threshold_voxels);
    ClassDB::bind_method(D_METHOD("get_cliff_slope_threshold_voxels"),
                         &CubicHeightmapGeneratorCpp::get_cliff_slope_threshold_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_slope_threshold_voxels"),
                 "set_cliff_slope_threshold_voxels", "get_cliff_slope_threshold_voxels");

    ClassDB::bind_method(D_METHOD("set_cliff_rule_max_lod", "value"),
                         &CubicHeightmapGeneratorCpp::set_cliff_rule_max_lod);
    ClassDB::bind_method(D_METHOD("get_cliff_rule_max_lod"),
                         &CubicHeightmapGeneratorCpp::get_cliff_rule_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_rule_max_lod"),
                 "set_cliff_rule_max_lod", "get_cliff_rule_max_lod");

    ClassDB::bind_method(D_METHOD("column_is_cliff", "world_x", "world_z", "this_ground_y"),
                         &CubicHeightmapGeneratorCpp::column_is_cliff);

    // Core API
    ClassDB::bind_method(D_METHOD("compute_ground_y", "world_x", "world_z"),
                         &CubicHeightmapGeneratorCpp::compute_ground_y);
    ClassDB::bind_method(
            D_METHOD("generate_block_into_buffer", "out_buffer", "origin_in_voxels", "lod"),
            &CubicHeightmapGeneratorCpp::generate_block_into_buffer);
}
