#include "copper_isles_heightmap_generator.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

// Zylann VoxelBuffer channel indices. Same constants as the cubic generator;
// duplicated rather than shared until the base-class extraction.
static constexpr int CHANNEL_TYPE = 0;
static constexpr int CHANNEL_DATA5 = 5;

// Canonical water source byte — matches WaterByteCodec.SOURCE_BYTE
// (MAX_LEVEL=8 | SOURCE_BIT=0x10).
static constexpr int WATER_SOURCE_BYTE = 0x18;

// Hardcoded band material IDs. Kept in sync with the cubic generator;
// future base-class extraction lifts these to a shared location.
static constexpr int STONE_MATERIAL_ID = 1;
static constexpr int DIRT_MATERIAL_ID = 2;
static constexpr int GRASS_MATERIAL_ID = 3;
static constexpr int SAND_MATERIAL_ID = 4;
static constexpr int MARBLE_MATERIAL_ID = 9;
static constexpr int STONE_DARK_MATERIAL_ID = 14;

CopperIslesHeightmapGeneratorCpp::CopperIslesHeightmapGeneratorCpp() {}
CopperIslesHeightmapGeneratorCpp::~CopperIslesHeightmapGeneratorCpp() {}

// ----- Heightmap cache --------------------------------------------------
//
// _ensure_image loads the EXR on first call, scans for max gray, caches
// the Image. Worker-thread safe in the "two-stomp-is-benign" sense:
// concurrent first calls produce identical Image objects with identical
// pixel data, and one stomp on the cache is harmless.

Ref<Image> CopperIslesHeightmapGeneratorCpp::_ensure_image() {
    if (_heightmap_load_attempted) {
        return _heightmap_image;
    }
    _heightmap_load_attempted = true;
    if (_heightmap_path.is_empty()) {
        UtilityFunctions::push_error("[CopperIslesCpp] heightmap_path is empty.");
        return Ref<Image>();
    }
    Ref<Image> img;
    img.instantiate();
    const Error err = img->load(_heightmap_path);
    if (err != OK) {
        UtilityFunctions::push_error(
                String("[CopperIslesCpp] Failed to load heightmap '") + _heightmap_path
                + String("' (err=") + String::num_int64(err) + String(").")
        );
        return Ref<Image>();
    }
    _heightmap_image = img;
    _heightmap_w = img->get_width();
    _heightmap_h = img->get_height();
    UtilityFunctions::print(String("[CopperIslesCpp] Loaded heightmap ")
            + String::num_int64(_heightmap_w) + String("x") + String::num_int64(_heightmap_h)
            + String(" from ") + _heightmap_path);
    return _heightmap_image;
}

Ref<Image> CopperIslesHeightmapGeneratorCpp::ensure_image_const() const {
    // Mutable cache state populated under const semantics — matches the
    // "lazy load" pattern in the GDScript generator. The actual mutating
    // happens via the mutable members declared in the header.
    return const_cast<CopperIslesHeightmapGeneratorCpp *>(this)->_ensure_image();
}

// ----- Sampling ---------------------------------------------------------

double CopperIslesHeightmapGeneratorCpp::sample_gray(int world_x, int world_z) const {
    Ref<Image> img = ensure_image_const();
    if (!img.is_valid() || _heightmap_w == 0 || _heightmap_h == 0) {
        return 0.5;  // flat-sea-level fallback (matches GD)
    }
    const double u = static_cast<double>(world_x - _origin_x_voxels) / static_cast<double>(_extent_x_voxels);
    const double v = static_cast<double>(world_z - _origin_z_voxels) / static_cast<double>(_extent_z_voxels);
    if (u < 0.0 || u >= 1.0 || v < 0.0 || v >= 1.0) {
        return 0.0;  // deep ocean outside the heightmap rectangle
    }
    if (!_bilinear_sampling) {
        int px = static_cast<int>(u * static_cast<double>(_heightmap_w));
        int pz = static_cast<int>(v * static_cast<double>(_heightmap_h));
        if (px < 0) px = 0;
        if (px > _heightmap_w - 1) px = _heightmap_w - 1;
        if (pz < 0) pz = 0;
        if (pz > _heightmap_h - 1) pz = _heightmap_h - 1;
        return static_cast<double>(img->get_pixel(px, pz).r);
    }
    // Bilinear: GD uses floori (toward -inf) for the integer floor of the
    // fractional coords; (int)std::floor matches on negatives + positives.
    const double fx = u * static_cast<double>(_heightmap_w) - 0.5;
    const double fz = v * static_cast<double>(_heightmap_h) - 0.5;
    int x0 = static_cast<int>(std::floor(fx));
    int z0 = static_cast<int>(std::floor(fz));
    if (x0 < 0) x0 = 0;
    if (x0 > _heightmap_w - 1) x0 = _heightmap_w - 1;
    if (z0 < 0) z0 = 0;
    if (z0 > _heightmap_h - 1) z0 = _heightmap_h - 1;
    int x1 = x0 + 1;
    int z1 = z0 + 1;
    if (x1 > _heightmap_w - 1) x1 = _heightmap_w - 1;
    if (z1 > _heightmap_h - 1) z1 = _heightmap_h - 1;
    double tx = fx - std::floor(fx);
    double tz = fz - std::floor(fz);
    if (tx < 0.0) tx = 0.0; else if (tx > 1.0) tx = 1.0;
    if (tz < 0.0) tz = 0.0; else if (tz > 1.0) tz = 1.0;
    // Sample as float (Color.r is float32 in Godot), promote to double for
    // the lerp accumulation. Mirrors the GD generator's lerp() which works
    // in double-precision since GDScript float == double.
    const double g00 = static_cast<double>(img->get_pixel(x0, z0).r);
    const double g10 = static_cast<double>(img->get_pixel(x1, z0).r);
    const double g01 = static_cast<double>(img->get_pixel(x0, z1).r);
    const double g11 = static_cast<double>(img->get_pixel(x1, z1).r);
    const double g0 = g00 + (g10 - g00) * tx;
    const double g1 = g01 + (g11 - g01) * tx;
    return g0 + (g1 - g0) * tz;
}

int CopperIslesHeightmapGeneratorCpp::gray_to_ground_y(double gray) const {
    // GD: int(round(g * float(elevation_above_at_white_voxels)))
    // C++: std::lround matches roundi() (half-away-from-zero on positives).
    double g = gray;
    if (g < 0.0) g = 0.0;
    if (g > 1.0) g = 1.0;
    return static_cast<int>(std::lround(g * static_cast<double>(_elevation_above_at_white_voxels)));
}

int CopperIslesHeightmapGeneratorCpp::compute_ground_y(int world_x, int world_z) const {
    return gray_to_ground_y(sample_gray(world_x, world_z));
}

// ----- Cliff helper -----------------------------------------------------

bool CopperIslesHeightmapGeneratorCpp::column_is_cliff(int world_x, int world_z, int this_ground_y) const {
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

// ----- Disk helper (Tier 5) ---------------------------------------------

const CICopperDiskPOD *CopperIslesHeightmapGeneratorCpp::disk_at_column(int world_x, int world_z, int ground_y) const {
    if (_disk_materials.empty()) {
        return nullptr;
    }
    int max_reach = 0;
    for (const auto &d : _disk_materials) {
        if (d.disk_max_distance_to_water_voxels > max_reach) {
            max_reach = d.disk_max_distance_to_water_voxels;
        }
    }
    const int dy_to_sea = std::abs(ground_y - _sea_level_voxels);
    if (dy_to_sea > max_reach) {
        return nullptr;
    }
    const int grid = _disk_anchor_grid_voxels < 1 ? 1 : _disk_anchor_grid_voxels;
    for (const auto &disk : _disk_materials) {
        if (dy_to_sea > disk.disk_max_distance_to_water_voxels) {
            continue;
        }
        const int r = disk.disk_radius_voxels;
        if (r <= 0) {
            continue;
        }
        const int ax_min = static_cast<int>(std::floor(static_cast<double>(world_x - r) / static_cast<double>(grid)));
        const int ax_max = static_cast<int>(std::floor(static_cast<double>(world_x + r) / static_cast<double>(grid)));
        const int az_min = static_cast<int>(std::floor(static_cast<double>(world_z - r) / static_cast<double>(grid)));
        const int az_max = static_cast<int>(std::floor(static_cast<double>(world_z + r) / static_cast<double>(grid)));
        const int64_t density_seed = static_cast<int64_t>(disk.material_id) * 7919;
        const int64_t jitter_seed = disk.material_id;
        for (int ax = ax_min; ax <= ax_max; ++ax) {
            for (int az = az_min; az <= az_max; ++az) {
                const double density_hash = voxel_gen::math::hash3(ax, 0, az, density_seed);
                if (density_hash > disk.disk_anchor_density) {
                    continue;
                }
                const double jx = voxel_gen::math::hash3(ax, 1, az, jitter_seed) - 0.5;
                const double jz = voxel_gen::math::hash3(ax, 2, az, jitter_seed) - 0.5;
                const int anchor_x = ax * grid + static_cast<int>(jx * static_cast<double>(grid));
                const int anchor_z = az * grid + static_cast<int>(jz * static_cast<double>(grid));
                const int dx = world_x - anchor_x;
                const int dz = world_z - anchor_z;
                if (dx * dx + dz * dz <= r * r) {
                    return &disk;
                }
            }
        }
    }
    return nullptr;
}

// ----- POD setters ------------------------------------------------------

void CopperIslesHeightmapGeneratorCpp::set_ore_materials(const Array &p_list) {
    _ore_materials.clear();
    _ore_materials.reserve(p_list.size());
    for (int i = 0; i < p_list.size(); ++i) {
        Variant v = p_list[i];
        if (v.get_type() != Variant::DICTIONARY) {
            continue;
        }
        Dictionary d = v;
        CICopperOrePOD pod;
        pod.material_id = static_cast<int>(static_cast<int64_t>(d.get("material_id", 0)));
        pod.replaces_material_id = static_cast<int>(static_cast<int64_t>(d.get("replaces_material_id", 0)));
        pod.min_altitude_voxels = static_cast<int>(static_cast<int64_t>(d.get("min_altitude_voxels", 0)));
        pod.max_altitude_voxels = static_cast<int>(static_cast<int64_t>(d.get("max_altitude_voxels", 0)));
        pod.ore_noise_threshold = static_cast<double>(d.get("ore_noise_threshold", 0.0));
        pod.ore_noise_scale = static_cast<double>(d.get("ore_noise_scale", 0.0));
        _ore_materials.push_back(pod);
    }
}

int CopperIslesHeightmapGeneratorCpp::get_ore_material_count() const {
    return static_cast<int>(_ore_materials.size());
}

void CopperIslesHeightmapGeneratorCpp::set_disk_materials(const Array &p_list) {
    _disk_materials.clear();
    _disk_materials.reserve(p_list.size());
    for (int i = 0; i < p_list.size(); ++i) {
        Variant v = p_list[i];
        if (v.get_type() != Variant::DICTIONARY) {
            continue;
        }
        Dictionary d = v;
        CICopperDiskPOD pod;
        pod.material_id = static_cast<int>(static_cast<int64_t>(d.get("material_id", 0)));
        pod.disk_radius_voxels = static_cast<int>(static_cast<int64_t>(d.get("disk_radius_voxels", 0)));
        pod.disk_half_height_voxels = static_cast<int>(static_cast<int64_t>(d.get("disk_half_height_voxels", 0)));
        pod.disk_anchor_density = static_cast<double>(d.get("disk_anchor_density", 0.0));
        pod.disk_max_distance_to_water_voxels = static_cast<int>(static_cast<int64_t>(d.get("disk_max_distance_to_water_voxels", 0)));
        _disk_materials.push_back(pod);
    }
}

int CopperIslesHeightmapGeneratorCpp::get_disk_material_count() const {
    return static_cast<int>(_disk_materials.size());
}

// ----- Property setters/getters -----------------------------------------

void CopperIslesHeightmapGeneratorCpp::set_heightmap_path(const String &p_value) {
    _heightmap_path = p_value;
    // Drop cache so the new path is loaded on next access.
    _heightmap_load_attempted = false;
    _heightmap_image = Ref<Image>();
    _heightmap_w = 0;
    _heightmap_h = 0;
}
String CopperIslesHeightmapGeneratorCpp::get_heightmap_path() const { return _heightmap_path; }

void CopperIslesHeightmapGeneratorCpp::set_extent_x_voxels(int p_value) { _extent_x_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_extent_x_voxels() const { return _extent_x_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_extent_z_voxels(int p_value) { _extent_z_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_extent_z_voxels() const { return _extent_z_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_origin_x_voxels(int p_value) { _origin_x_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_origin_x_voxels() const { return _origin_x_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_origin_z_voxels(int p_value) { _origin_z_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_origin_z_voxels() const { return _origin_z_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_sea_level_voxels(int p_value) { _sea_level_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_sea_level_voxels() const { return _sea_level_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_elevation_above_at_white_voxels(int p_value) { _elevation_above_at_white_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_elevation_above_at_white_voxels() const { return _elevation_above_at_white_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_bilinear_sampling(bool p_value) { _bilinear_sampling = p_value; }
bool CopperIslesHeightmapGeneratorCpp::get_bilinear_sampling() const { return _bilinear_sampling; }

void CopperIslesHeightmapGeneratorCpp::set_grass_layer_thickness_voxels(int p_value) { _grass_layer_thickness_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_grass_layer_thickness_voxels() const { return _grass_layer_thickness_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_dirt_layer_thickness_voxels(int p_value) { _dirt_layer_thickness_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_dirt_layer_thickness_voxels() const { return _dirt_layer_thickness_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_beach_y_threshold(int p_value) { _beach_y_threshold = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_beach_y_threshold() const { return _beach_y_threshold; }

void CopperIslesHeightmapGeneratorCpp::set_marble_jitter_block_size(int p_value) { _marble_jitter_block_size = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_marble_jitter_block_size() const { return _marble_jitter_block_size; }

void CopperIslesHeightmapGeneratorCpp::set_marble_jitter_seed(int p_value) { _marble_jitter_seed = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_marble_jitter_seed() const { return _marble_jitter_seed; }

void CopperIslesHeightmapGeneratorCpp::set_marble_rare_threshold(double p_value) { _marble_rare_threshold = p_value; }
double CopperIslesHeightmapGeneratorCpp::get_marble_rare_threshold() const { return _marble_rare_threshold; }

void CopperIslesHeightmapGeneratorCpp::set_marble_dark_threshold(double p_value) { _marble_dark_threshold = p_value; }
double CopperIslesHeightmapGeneratorCpp::get_marble_dark_threshold() const { return _marble_dark_threshold; }

void CopperIslesHeightmapGeneratorCpp::set_marble_jitter_max_lod(int p_value) { _marble_jitter_max_lod = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_marble_jitter_max_lod() const { return _marble_jitter_max_lod; }

void CopperIslesHeightmapGeneratorCpp::set_bedrock_material_id(int p_value) { _bedrock_material_id = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_bedrock_material_id() const { return _bedrock_material_id; }

void CopperIslesHeightmapGeneratorCpp::set_world_floor_voxel_y(int p_value) { _world_floor_voxel_y = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_world_floor_voxel_y() const { return _world_floor_voxel_y; }

void CopperIslesHeightmapGeneratorCpp::set_snow_material_id(int p_value) { _snow_material_id = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_snow_material_id() const { return _snow_material_id; }

void CopperIslesHeightmapGeneratorCpp::set_snow_line_voxels(int p_value) { _snow_line_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_snow_line_voxels() const { return _snow_line_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_snow_line_jitter_voxels(int p_value) { _snow_line_jitter_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_snow_line_jitter_voxels() const { return _snow_line_jitter_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_snow_line_jitter_block_size(int p_value) { _snow_line_jitter_block_size = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_snow_line_jitter_block_size() const { return _snow_line_jitter_block_size; }

void CopperIslesHeightmapGeneratorCpp::set_snow_line_seed(int p_value) { _snow_line_seed = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_snow_line_seed() const { return _snow_line_seed; }

void CopperIslesHeightmapGeneratorCpp::set_snow_line_max_lod(int p_value) { _snow_line_max_lod = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_snow_line_max_lod() const { return _snow_line_max_lod; }

void CopperIslesHeightmapGeneratorCpp::set_cliff_slope_sample_distance_voxels(int p_value) { _cliff_slope_sample_distance_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_cliff_slope_sample_distance_voxels() const { return _cliff_slope_sample_distance_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_cliff_slope_threshold_voxels(int p_value) { _cliff_slope_threshold_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_cliff_slope_threshold_voxels() const { return _cliff_slope_threshold_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_cliff_rule_max_lod(int p_value) { _cliff_rule_max_lod = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_cliff_rule_max_lod() const { return _cliff_rule_max_lod; }

void CopperIslesHeightmapGeneratorCpp::set_ore_vein_max_lod(int p_value) { _ore_vein_max_lod = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_ore_vein_max_lod() const { return _ore_vein_max_lod; }

void CopperIslesHeightmapGeneratorCpp::set_disk_rule_max_lod(int p_value) { _disk_rule_max_lod = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_disk_rule_max_lod() const { return _disk_rule_max_lod; }

void CopperIslesHeightmapGeneratorCpp::set_disk_anchor_grid_voxels(int p_value) { _disk_anchor_grid_voxels = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_disk_anchor_grid_voxels() const { return _disk_anchor_grid_voxels; }

void CopperIslesHeightmapGeneratorCpp::set_cliff_ore_outcrop_chance(double p_value) { _cliff_ore_outcrop_chance = p_value; }
double CopperIslesHeightmapGeneratorCpp::get_cliff_ore_outcrop_chance() const { return _cliff_ore_outcrop_chance; }

void CopperIslesHeightmapGeneratorCpp::set_cliff_ore_seed(int p_value) { _cliff_ore_seed = p_value; }
int CopperIslesHeightmapGeneratorCpp::get_cliff_ore_seed() const { return _cliff_ore_seed; }

// ----- Block fill -------------------------------------------------------
//
// Mirrors the cubic generator's inner loop verbatim — the only difference
// is compute_ground_y. Pull the loop into a shared base after the port
// stabilises.

void CopperIslesHeightmapGeneratorCpp::generate_block_into_buffer(Variant out_buffer,
                                                                  Vector3i origin_in_voxels,
                                                                  int lod) {
    Variant size_v = out_buffer.call("get_size");
    if (size_v.get_type() != Variant::VECTOR3I) {
        UtilityFunctions::printerr(
                "CopperIslesHeightmapGeneratorCpp: out_buffer.get_size() did not return Vector3i");
        return;
    }
    Vector3i size = size_v;
    const int stride = 1 << lod;

    const int grass_thick = _grass_layer_thickness_voxels;
    const int dirt_band_end = grass_thick + _dirt_layer_thickness_voxels;
    const int beach_y = _beach_y_threshold;

    // Tier 3 marble cache.
    const int jitter_block = _marble_jitter_block_size < 1 ? 1 : _marble_jitter_block_size;
    const int64_t jitter_seed = _marble_jitter_seed;
    const double jitter_marble = _marble_rare_threshold;
    const double jitter_dark = _marble_dark_threshold;
    const bool run_marble_jitter = _marble_jitter_max_lod >= 0 && lod <= _marble_jitter_max_lod;

    // Bedrock + water.
    const int world_floor_y = _world_floor_voxel_y;
    const int bedrock_id = _bedrock_material_id;
    const int sea_level_v = _sea_level_voxels;
    const bool write_water = (lod == 0);

    // Tier 2 snow line.
    const int snow_id = _snow_material_id;
    const int snow_alt_voxels = _snow_line_voxels;
    const int snow_block = _snow_line_jitter_block_size < 1 ? 1 : _snow_line_jitter_block_size;
    const double snow_jitter_amp = static_cast<double>(_snow_line_jitter_voxels);
    const int64_t snow_seed = _snow_line_seed;
    const bool run_snow_line = snow_id != 0
            && _snow_line_max_lod >= 0
            && lod <= _snow_line_max_lod;

    // Tier 1 cliff.
    const bool run_cliff_rule = _cliff_rule_max_lod >= 0 && lod <= _cliff_rule_max_lod;

    // Tier 4 / 6.
    const bool has_ores = !_ore_materials.empty();
    const bool run_ore_veins = has_ores
            && _ore_vein_max_lod >= 0
            && lod <= _ore_vein_max_lod;
    const double cliff_ore_chance = _cliff_ore_outcrop_chance;
    const int64_t cliff_ore_seed = _cliff_ore_seed;

    // Tier 5.
    const bool run_disk_rule = _disk_rule_max_lod >= 0
            && lod <= _disk_rule_max_lod
            && !_disk_materials.empty();

    for (int z = 0; z < size.z; ++z) {
        for (int x = 0; x < size.x; ++x) {
            const int world_x = origin_in_voxels.x + x * stride;
            const int world_z = origin_in_voxels.z + z * stride;
            const int ground_y = compute_ground_y(world_x, world_z);

            int top_id = GRASS_MATERIAL_ID;
            if (ground_y <= beach_y) {
                top_id = SAND_MATERIAL_ID;
            }

            int col_dirt_band_end = dirt_band_end;
            const bool col_is_cliff = run_cliff_rule
                    && column_is_cliff(world_x, world_z, ground_y);
            if (col_is_cliff) {
                top_id = STONE_MATERIAL_ID;
                col_dirt_band_end = grass_thick;
                if (has_ores) {
                    const double dice = voxel_gen::math::hash3(
                            world_x, ground_y, world_z, cliff_ore_seed);
                    if (dice < cliff_ore_chance) {
                        const double pick = voxel_gen::math::hash3(
                                world_x, ground_y, world_z, cliff_ore_seed + 1);
                        int ore_idx = static_cast<int>(pick * static_cast<double>(_ore_materials.size()));
                        if (ore_idx < 0) ore_idx = 0;
                        if (ore_idx > static_cast<int>(_ore_materials.size()) - 1)
                            ore_idx = static_cast<int>(_ore_materials.size()) - 1;
                        const CICopperOrePOD &ore_pick = _ore_materials[ore_idx];
                        if (ground_y >= ore_pick.min_altitude_voxels
                                && ground_y <= ore_pick.max_altitude_voxels) {
                            top_id = ore_pick.material_id;
                        }
                    }
                }
            }

            if (run_snow_line && !col_is_cliff && ground_y >= snow_alt_voxels) {
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

            const CICopperDiskPOD *disk_match = nullptr;
            int disk_thickness = 0;
            if (run_disk_rule && !col_is_cliff) {
                disk_match = disk_at_column(world_x, world_z, ground_y);
                if (disk_match != nullptr) {
                    disk_thickness = 1 + disk_match->disk_half_height_voxels * 2;
                }
            }

            const bool emit_water_here = write_water && ground_y < sea_level_v;

            for (int y = 0; y < size.y; ++y) {
                const int world_y = origin_in_voxels.y + y * stride;
                if (world_y > ground_y) {
                    if (emit_water_here && world_y <= sea_level_v) {
                        out_buffer.call("set_voxel", WATER_SOURCE_BYTE, x, y, z, CHANNEL_DATA5);
                    }
                    continue;
                }
                if (world_y < world_floor_y) {
                    continue;
                }
                if (world_y == world_floor_y && bedrock_id != 0) {
                    out_buffer.call("set_voxel", bedrock_id, x, y, z, CHANNEL_TYPE);
                    continue;
                }
                const int depth = ground_y - world_y;

                int mat_id;
                if (depth < grass_thick) {
                    mat_id = top_id;
                } else if (depth < col_dirt_band_end) {
                    mat_id = DIRT_MATERIAL_ID;
                } else {
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
                    if (run_ore_veins) {
                        for (const auto &ore : _ore_materials) {
                            if (mat_id != ore.replaces_material_id) {
                                continue;
                            }
                            if (world_y < ore.min_altitude_voxels
                                    || world_y > ore.max_altitude_voxels) {
                                continue;
                            }
                            const double s = ore.ore_noise_scale;
                            const double on = voxel_gen::math::hash3(
                                    static_cast<int64_t>(static_cast<double>(world_x) * s),
                                    static_cast<int64_t>(static_cast<double>(world_y) * s),
                                    static_cast<int64_t>(static_cast<double>(world_z) * s),
                                    static_cast<int64_t>(ore.material_id) * 1009);
                            if (on > ore.ore_noise_threshold) {
                                mat_id = ore.material_id;
                                break;
                            }
                        }
                    }
                }

                if (disk_match != nullptr && depth < disk_thickness) {
                    mat_id = disk_match->material_id;
                }
                out_buffer.call("set_voxel", mat_id, x, y, z, CHANNEL_TYPE);
            }
        }
    }
}

// ----- ClassDB bindings -------------------------------------------------

void CopperIslesHeightmapGeneratorCpp::_bind_methods() {
    // Heightmap config
    ClassDB::bind_method(D_METHOD("set_heightmap_path", "path"), &CopperIslesHeightmapGeneratorCpp::set_heightmap_path);
    ClassDB::bind_method(D_METHOD("get_heightmap_path"), &CopperIslesHeightmapGeneratorCpp::get_heightmap_path);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "heightmap_path"), "set_heightmap_path", "get_heightmap_path");

    ClassDB::bind_method(D_METHOD("set_extent_x_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_extent_x_voxels);
    ClassDB::bind_method(D_METHOD("get_extent_x_voxels"), &CopperIslesHeightmapGeneratorCpp::get_extent_x_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "extent_x_voxels"), "set_extent_x_voxels", "get_extent_x_voxels");

    ClassDB::bind_method(D_METHOD("set_extent_z_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_extent_z_voxels);
    ClassDB::bind_method(D_METHOD("get_extent_z_voxels"), &CopperIslesHeightmapGeneratorCpp::get_extent_z_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "extent_z_voxels"), "set_extent_z_voxels", "get_extent_z_voxels");

    ClassDB::bind_method(D_METHOD("set_origin_x_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_origin_x_voxels);
    ClassDB::bind_method(D_METHOD("get_origin_x_voxels"), &CopperIslesHeightmapGeneratorCpp::get_origin_x_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "origin_x_voxels"), "set_origin_x_voxels", "get_origin_x_voxels");

    ClassDB::bind_method(D_METHOD("set_origin_z_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_origin_z_voxels);
    ClassDB::bind_method(D_METHOD("get_origin_z_voxels"), &CopperIslesHeightmapGeneratorCpp::get_origin_z_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "origin_z_voxels"), "set_origin_z_voxels", "get_origin_z_voxels");

    ClassDB::bind_method(D_METHOD("set_sea_level_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_sea_level_voxels);
    ClassDB::bind_method(D_METHOD("get_sea_level_voxels"), &CopperIslesHeightmapGeneratorCpp::get_sea_level_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "sea_level_voxels"), "set_sea_level_voxels", "get_sea_level_voxels");

    ClassDB::bind_method(D_METHOD("set_elevation_above_at_white_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_elevation_above_at_white_voxels);
    ClassDB::bind_method(D_METHOD("get_elevation_above_at_white_voxels"), &CopperIslesHeightmapGeneratorCpp::get_elevation_above_at_white_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "elevation_above_at_white_voxels"), "set_elevation_above_at_white_voxels", "get_elevation_above_at_white_voxels");

    ClassDB::bind_method(D_METHOD("set_bilinear_sampling", "v"), &CopperIslesHeightmapGeneratorCpp::set_bilinear_sampling);
    ClassDB::bind_method(D_METHOD("get_bilinear_sampling"), &CopperIslesHeightmapGeneratorCpp::get_bilinear_sampling);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "bilinear_sampling"), "set_bilinear_sampling", "get_bilinear_sampling");

    // Band properties
    ClassDB::bind_method(D_METHOD("set_grass_layer_thickness_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_grass_layer_thickness_voxels);
    ClassDB::bind_method(D_METHOD("get_grass_layer_thickness_voxels"), &CopperIslesHeightmapGeneratorCpp::get_grass_layer_thickness_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "grass_layer_thickness_voxels"), "set_grass_layer_thickness_voxels", "get_grass_layer_thickness_voxels");

    ClassDB::bind_method(D_METHOD("set_dirt_layer_thickness_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_dirt_layer_thickness_voxels);
    ClassDB::bind_method(D_METHOD("get_dirt_layer_thickness_voxels"), &CopperIslesHeightmapGeneratorCpp::get_dirt_layer_thickness_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "dirt_layer_thickness_voxels"), "set_dirt_layer_thickness_voxels", "get_dirt_layer_thickness_voxels");

    ClassDB::bind_method(D_METHOD("set_beach_y_threshold", "v"), &CopperIslesHeightmapGeneratorCpp::set_beach_y_threshold);
    ClassDB::bind_method(D_METHOD("get_beach_y_threshold"), &CopperIslesHeightmapGeneratorCpp::get_beach_y_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "beach_y_threshold"), "set_beach_y_threshold", "get_beach_y_threshold");

    // Tier 3 marble
    ClassDB::bind_method(D_METHOD("set_marble_jitter_block_size", "v"), &CopperIslesHeightmapGeneratorCpp::set_marble_jitter_block_size);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_block_size"), &CopperIslesHeightmapGeneratorCpp::get_marble_jitter_block_size);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_block_size"), "set_marble_jitter_block_size", "get_marble_jitter_block_size");

    ClassDB::bind_method(D_METHOD("set_marble_jitter_seed", "v"), &CopperIslesHeightmapGeneratorCpp::set_marble_jitter_seed);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_seed"), &CopperIslesHeightmapGeneratorCpp::get_marble_jitter_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_seed"), "set_marble_jitter_seed", "get_marble_jitter_seed");

    ClassDB::bind_method(D_METHOD("set_marble_rare_threshold", "v"), &CopperIslesHeightmapGeneratorCpp::set_marble_rare_threshold);
    ClassDB::bind_method(D_METHOD("get_marble_rare_threshold"), &CopperIslesHeightmapGeneratorCpp::get_marble_rare_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "marble_rare_threshold"), "set_marble_rare_threshold", "get_marble_rare_threshold");

    ClassDB::bind_method(D_METHOD("set_marble_dark_threshold", "v"), &CopperIslesHeightmapGeneratorCpp::set_marble_dark_threshold);
    ClassDB::bind_method(D_METHOD("get_marble_dark_threshold"), &CopperIslesHeightmapGeneratorCpp::get_marble_dark_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "marble_dark_threshold"), "set_marble_dark_threshold", "get_marble_dark_threshold");

    ClassDB::bind_method(D_METHOD("set_marble_jitter_max_lod", "v"), &CopperIslesHeightmapGeneratorCpp::set_marble_jitter_max_lod);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_max_lod"), &CopperIslesHeightmapGeneratorCpp::get_marble_jitter_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_max_lod"), "set_marble_jitter_max_lod", "get_marble_jitter_max_lod");

    // Bedrock / world floor
    ClassDB::bind_method(D_METHOD("set_bedrock_material_id", "v"), &CopperIslesHeightmapGeneratorCpp::set_bedrock_material_id);
    ClassDB::bind_method(D_METHOD("get_bedrock_material_id"), &CopperIslesHeightmapGeneratorCpp::get_bedrock_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "bedrock_material_id"), "set_bedrock_material_id", "get_bedrock_material_id");

    ClassDB::bind_method(D_METHOD("set_world_floor_voxel_y", "v"), &CopperIslesHeightmapGeneratorCpp::set_world_floor_voxel_y);
    ClassDB::bind_method(D_METHOD("get_world_floor_voxel_y"), &CopperIslesHeightmapGeneratorCpp::get_world_floor_voxel_y);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "world_floor_voxel_y"), "set_world_floor_voxel_y", "get_world_floor_voxel_y");

    // Tier 2 snow
    ClassDB::bind_method(D_METHOD("set_snow_material_id", "v"), &CopperIslesHeightmapGeneratorCpp::set_snow_material_id);
    ClassDB::bind_method(D_METHOD("get_snow_material_id"), &CopperIslesHeightmapGeneratorCpp::get_snow_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_material_id"), "set_snow_material_id", "get_snow_material_id");

    ClassDB::bind_method(D_METHOD("set_snow_line_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_snow_line_voxels);
    ClassDB::bind_method(D_METHOD("get_snow_line_voxels"), &CopperIslesHeightmapGeneratorCpp::get_snow_line_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_voxels"), "set_snow_line_voxels", "get_snow_line_voxels");

    ClassDB::bind_method(D_METHOD("set_snow_line_jitter_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_snow_line_jitter_voxels);
    ClassDB::bind_method(D_METHOD("get_snow_line_jitter_voxels"), &CopperIslesHeightmapGeneratorCpp::get_snow_line_jitter_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_jitter_voxels"), "set_snow_line_jitter_voxels", "get_snow_line_jitter_voxels");

    ClassDB::bind_method(D_METHOD("set_snow_line_jitter_block_size", "v"), &CopperIslesHeightmapGeneratorCpp::set_snow_line_jitter_block_size);
    ClassDB::bind_method(D_METHOD("get_snow_line_jitter_block_size"), &CopperIslesHeightmapGeneratorCpp::get_snow_line_jitter_block_size);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_jitter_block_size"), "set_snow_line_jitter_block_size", "get_snow_line_jitter_block_size");

    ClassDB::bind_method(D_METHOD("set_snow_line_seed", "v"), &CopperIslesHeightmapGeneratorCpp::set_snow_line_seed);
    ClassDB::bind_method(D_METHOD("get_snow_line_seed"), &CopperIslesHeightmapGeneratorCpp::get_snow_line_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_seed"), "set_snow_line_seed", "get_snow_line_seed");

    ClassDB::bind_method(D_METHOD("set_snow_line_max_lod", "v"), &CopperIslesHeightmapGeneratorCpp::set_snow_line_max_lod);
    ClassDB::bind_method(D_METHOD("get_snow_line_max_lod"), &CopperIslesHeightmapGeneratorCpp::get_snow_line_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_max_lod"), "set_snow_line_max_lod", "get_snow_line_max_lod");

    // Tier 1 cliff
    ClassDB::bind_method(D_METHOD("set_cliff_slope_sample_distance_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_cliff_slope_sample_distance_voxels);
    ClassDB::bind_method(D_METHOD("get_cliff_slope_sample_distance_voxels"), &CopperIslesHeightmapGeneratorCpp::get_cliff_slope_sample_distance_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_slope_sample_distance_voxels"), "set_cliff_slope_sample_distance_voxels", "get_cliff_slope_sample_distance_voxels");

    ClassDB::bind_method(D_METHOD("set_cliff_slope_threshold_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_cliff_slope_threshold_voxels);
    ClassDB::bind_method(D_METHOD("get_cliff_slope_threshold_voxels"), &CopperIslesHeightmapGeneratorCpp::get_cliff_slope_threshold_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_slope_threshold_voxels"), "set_cliff_slope_threshold_voxels", "get_cliff_slope_threshold_voxels");

    ClassDB::bind_method(D_METHOD("set_cliff_rule_max_lod", "v"), &CopperIslesHeightmapGeneratorCpp::set_cliff_rule_max_lod);
    ClassDB::bind_method(D_METHOD("get_cliff_rule_max_lod"), &CopperIslesHeightmapGeneratorCpp::get_cliff_rule_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_rule_max_lod"), "set_cliff_rule_max_lod", "get_cliff_rule_max_lod");

    // Tier 4 / 5 / 6 gates
    ClassDB::bind_method(D_METHOD("set_ore_vein_max_lod", "v"), &CopperIslesHeightmapGeneratorCpp::set_ore_vein_max_lod);
    ClassDB::bind_method(D_METHOD("get_ore_vein_max_lod"), &CopperIslesHeightmapGeneratorCpp::get_ore_vein_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "ore_vein_max_lod"), "set_ore_vein_max_lod", "get_ore_vein_max_lod");

    ClassDB::bind_method(D_METHOD("set_disk_rule_max_lod", "v"), &CopperIslesHeightmapGeneratorCpp::set_disk_rule_max_lod);
    ClassDB::bind_method(D_METHOD("get_disk_rule_max_lod"), &CopperIslesHeightmapGeneratorCpp::get_disk_rule_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "disk_rule_max_lod"), "set_disk_rule_max_lod", "get_disk_rule_max_lod");

    ClassDB::bind_method(D_METHOD("set_disk_anchor_grid_voxels", "v"), &CopperIslesHeightmapGeneratorCpp::set_disk_anchor_grid_voxels);
    ClassDB::bind_method(D_METHOD("get_disk_anchor_grid_voxels"), &CopperIslesHeightmapGeneratorCpp::get_disk_anchor_grid_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "disk_anchor_grid_voxels"), "set_disk_anchor_grid_voxels", "get_disk_anchor_grid_voxels");

    ClassDB::bind_method(D_METHOD("set_cliff_ore_outcrop_chance", "v"), &CopperIslesHeightmapGeneratorCpp::set_cliff_ore_outcrop_chance);
    ClassDB::bind_method(D_METHOD("get_cliff_ore_outcrop_chance"), &CopperIslesHeightmapGeneratorCpp::get_cliff_ore_outcrop_chance);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cliff_ore_outcrop_chance"), "set_cliff_ore_outcrop_chance", "get_cliff_ore_outcrop_chance");

    ClassDB::bind_method(D_METHOD("set_cliff_ore_seed", "v"), &CopperIslesHeightmapGeneratorCpp::set_cliff_ore_seed);
    ClassDB::bind_method(D_METHOD("get_cliff_ore_seed"), &CopperIslesHeightmapGeneratorCpp::get_cliff_ore_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_ore_seed"), "set_cliff_ore_seed", "get_cliff_ore_seed");

    // POD snapshot setters
    ClassDB::bind_method(D_METHOD("set_ore_materials", "list"), &CopperIslesHeightmapGeneratorCpp::set_ore_materials);
    ClassDB::bind_method(D_METHOD("get_ore_material_count"), &CopperIslesHeightmapGeneratorCpp::get_ore_material_count);
    ClassDB::bind_method(D_METHOD("set_disk_materials", "list"), &CopperIslesHeightmapGeneratorCpp::set_disk_materials);
    ClassDB::bind_method(D_METHOD("get_disk_material_count"), &CopperIslesHeightmapGeneratorCpp::get_disk_material_count);

    // Core API
    ClassDB::bind_method(D_METHOD("sample_gray", "world_x", "world_z"), &CopperIslesHeightmapGeneratorCpp::sample_gray);
    ClassDB::bind_method(D_METHOD("gray_to_ground_y", "gray"), &CopperIslesHeightmapGeneratorCpp::gray_to_ground_y);
    ClassDB::bind_method(D_METHOD("compute_ground_y", "world_x", "world_z"), &CopperIslesHeightmapGeneratorCpp::compute_ground_y);
    ClassDB::bind_method(D_METHOD("get_ground_voxel_y_at", "world_x", "world_z"), &CopperIslesHeightmapGeneratorCpp::get_ground_voxel_y_at);
    ClassDB::bind_method(D_METHOD("column_is_cliff", "world_x", "world_z", "this_ground_y"), &CopperIslesHeightmapGeneratorCpp::column_is_cliff);
    ClassDB::bind_method(
            D_METHOD("generate_block_into_buffer", "out_buffer", "origin_in_voxels", "lod"),
            &CopperIslesHeightmapGeneratorCpp::generate_block_into_buffer);
}
