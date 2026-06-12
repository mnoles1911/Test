#include "heightmap_generator_base.h"

#include "voxel_gen_math.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
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
// Shared band materials are hardcoded; ore/disk/snow are configurable.
static constexpr int STONE_MATERIAL_ID = 1;
static constexpr int DIRT_MATERIAL_ID = 2;
static constexpr int GRASS_MATERIAL_ID = 3;
static constexpr int SAND_MATERIAL_ID = 4;
// Native-fluid pivot (Phase 4, 2026-05-18): generated ocean/lake water
// is the FULL-level Zylann fluid model, not the old transparent cube
// (id 5). Mirrors scripts/WaterMaterial.gd EXACTLY:
//   WATER_FLUID_BASE_ID = 16, WATER_LEVEL_COUNT = 8
//   level L (1..8) -> blocky model id BASE + L - 1
//   full (level 8) -> 16 + 8 - 1 = 23
// Oceans/lakes are Minecraft SOURCE blocks: full to sea level (level
// 8). Partial levels + sloped surfaces are produced by the flow sim at
// dynamic fronts (Phase 3) and by waterfalls (Phase 8) — NOT by static
// generation: a uniform partial top would just sink the whole ocean
// ~1/8 voxel with no slope benefit and worse LOD downsampling. So this
// is a strict id-only swap (5 -> 23); the parity harness asserts
// terrain + water POSITIONS are byte-identical and only the id changed.
// World3DBootstrap injects the 8 VoxelBlockyModelFluid at runtime so
// ids 16..23 exist by the time chunks stream. The blocky mesher
// auto-slopes the fluid surface — no WaterChunkMesher, no horizon plane.
static constexpr int WATER_FLUID_BASE_ID = 16;
static constexpr int WATER_LEVEL_COUNT = 8;
static constexpr int WATER_MATERIAL_ID = WATER_FLUID_BASE_ID + WATER_LEVEL_COUNT - 1; // 23 = full level
static constexpr int MARBLE_MATERIAL_ID = 9;
static constexpr int STONE_DARK_MATERIAL_ID = 14;

HeightmapGeneratorBase::HeightmapGeneratorBase() {}
HeightmapGeneratorBase::~HeightmapGeneratorBase() {}

// ----- Property setters / getters ----------------------------------------

void HeightmapGeneratorBase::set_grass_layer_thickness_voxels(int p_value) { _grass_layer_thickness_voxels = p_value; }
int HeightmapGeneratorBase::get_grass_layer_thickness_voxels() const { return _grass_layer_thickness_voxels; }

void HeightmapGeneratorBase::set_dirt_layer_thickness_voxels(int p_value) { _dirt_layer_thickness_voxels = p_value; }
int HeightmapGeneratorBase::get_dirt_layer_thickness_voxels() const { return _dirt_layer_thickness_voxels; }

void HeightmapGeneratorBase::set_beach_y_threshold(int p_value) { _beach_y_threshold = p_value; }
int HeightmapGeneratorBase::get_beach_y_threshold() const { return _beach_y_threshold; }

void HeightmapGeneratorBase::set_marble_jitter_block_size(int p_value) { _marble_jitter_block_size = p_value; }
int HeightmapGeneratorBase::get_marble_jitter_block_size() const { return _marble_jitter_block_size; }

void HeightmapGeneratorBase::set_marble_jitter_seed(int p_value) { _marble_jitter_seed = p_value; }
int HeightmapGeneratorBase::get_marble_jitter_seed() const { return _marble_jitter_seed; }

void HeightmapGeneratorBase::set_marble_rare_threshold(double p_value) { _marble_rare_threshold = p_value; }
double HeightmapGeneratorBase::get_marble_rare_threshold() const { return _marble_rare_threshold; }

void HeightmapGeneratorBase::set_marble_dark_threshold(double p_value) { _marble_dark_threshold = p_value; }
double HeightmapGeneratorBase::get_marble_dark_threshold() const { return _marble_dark_threshold; }

void HeightmapGeneratorBase::set_marble_jitter_max_lod(int p_value) { _marble_jitter_max_lod = p_value; }
int HeightmapGeneratorBase::get_marble_jitter_max_lod() const { return _marble_jitter_max_lod; }

void HeightmapGeneratorBase::set_bedrock_material_id(int p_value) { _bedrock_material_id = p_value; }
int HeightmapGeneratorBase::get_bedrock_material_id() const { return _bedrock_material_id; }

void HeightmapGeneratorBase::set_world_floor_voxel_y(int p_value) { _world_floor_voxel_y = p_value; }
int HeightmapGeneratorBase::get_world_floor_voxel_y() const { return _world_floor_voxel_y; }

void HeightmapGeneratorBase::set_sea_level_voxels(int p_value) { _sea_level_voxels = p_value; }
int HeightmapGeneratorBase::get_sea_level_voxels() const { return _sea_level_voxels; }

void HeightmapGeneratorBase::set_snow_material_id(int p_value) { _snow_material_id = p_value; }
int HeightmapGeneratorBase::get_snow_material_id() const { return _snow_material_id; }

void HeightmapGeneratorBase::set_snow_line_voxels(int p_value) { _snow_line_voxels = p_value; }
int HeightmapGeneratorBase::get_snow_line_voxels() const { return _snow_line_voxels; }

void HeightmapGeneratorBase::set_snow_line_jitter_voxels(int p_value) { _snow_line_jitter_voxels = p_value; }
int HeightmapGeneratorBase::get_snow_line_jitter_voxels() const { return _snow_line_jitter_voxels; }

void HeightmapGeneratorBase::set_snow_line_jitter_block_size(int p_value) { _snow_line_jitter_block_size = p_value; }
int HeightmapGeneratorBase::get_snow_line_jitter_block_size() const { return _snow_line_jitter_block_size; }

void HeightmapGeneratorBase::set_snow_line_seed(int p_value) { _snow_line_seed = p_value; }
int HeightmapGeneratorBase::get_snow_line_seed() const { return _snow_line_seed; }

void HeightmapGeneratorBase::set_snow_line_max_lod(int p_value) { _snow_line_max_lod = p_value; }
int HeightmapGeneratorBase::get_snow_line_max_lod() const { return _snow_line_max_lod; }

void HeightmapGeneratorBase::set_cliff_slope_sample_distance_voxels(int p_value) { _cliff_slope_sample_distance_voxels = p_value; }
int HeightmapGeneratorBase::get_cliff_slope_sample_distance_voxels() const { return _cliff_slope_sample_distance_voxels; }

void HeightmapGeneratorBase::set_cliff_slope_threshold_voxels(int p_value) { _cliff_slope_threshold_voxels = p_value; }
int HeightmapGeneratorBase::get_cliff_slope_threshold_voxels() const { return _cliff_slope_threshold_voxels; }

void HeightmapGeneratorBase::set_cliff_rule_max_lod(int p_value) { _cliff_rule_max_lod = p_value; }
int HeightmapGeneratorBase::get_cliff_rule_max_lod() const { return _cliff_rule_max_lod; }

void HeightmapGeneratorBase::set_ore_vein_max_lod(int p_value) { _ore_vein_max_lod = p_value; }
int HeightmapGeneratorBase::get_ore_vein_max_lod() const { return _ore_vein_max_lod; }

void HeightmapGeneratorBase::set_disk_rule_max_lod(int p_value) { _disk_rule_max_lod = p_value; }
int HeightmapGeneratorBase::get_disk_rule_max_lod() const { return _disk_rule_max_lod; }

void HeightmapGeneratorBase::set_disk_anchor_grid_voxels(int p_value) { _disk_anchor_grid_voxels = p_value; }
int HeightmapGeneratorBase::get_disk_anchor_grid_voxels() const { return _disk_anchor_grid_voxels; }

void HeightmapGeneratorBase::set_cliff_ore_outcrop_chance(double p_value) { _cliff_ore_outcrop_chance = p_value; }
double HeightmapGeneratorBase::get_cliff_ore_outcrop_chance() const { return _cliff_ore_outcrop_chance; }

void HeightmapGeneratorBase::set_cliff_ore_seed(int p_value) { _cliff_ore_seed = p_value; }
int HeightmapGeneratorBase::get_cliff_ore_seed() const { return _cliff_ore_seed; }

// R4 flora scatter ids + seed.
void HeightmapGeneratorBase::set_grass_blade_material_id(int p_value) { _grass_blade_material_id = p_value; }
int HeightmapGeneratorBase::get_grass_blade_material_id() const { return _grass_blade_material_id; }

void HeightmapGeneratorBase::set_flower_red_material_id(int p_value) { _flower_red_material_id = p_value; }
int HeightmapGeneratorBase::get_flower_red_material_id() const { return _flower_red_material_id; }

void HeightmapGeneratorBase::set_flower_blue_material_id(int p_value) { _flower_blue_material_id = p_value; }
int HeightmapGeneratorBase::get_flower_blue_material_id() const { return _flower_blue_material_id; }

void HeightmapGeneratorBase::set_flora_seed(int p_value) { _flora_seed = p_value; }
int HeightmapGeneratorBase::get_flora_seed() const { return _flora_seed; }

// D1 surface-detail scatter ids + seed.
void HeightmapGeneratorBase::set_pebble_material_id(int p_value) { _pebble_material_id = p_value; }
int HeightmapGeneratorBase::get_pebble_material_id() const { return _pebble_material_id; }

void HeightmapGeneratorBase::set_twig_material_id(int p_value) { _twig_material_id = p_value; }
int HeightmapGeneratorBase::get_twig_material_id() const { return _twig_material_id; }

void HeightmapGeneratorBase::set_surface_detail_seed(int p_value) { _surface_detail_seed = p_value; }
int HeightmapGeneratorBase::get_surface_detail_seed() const { return _surface_detail_seed; }

// ----- POD snapshot setters ---------------------------------------------
//
// The GDScript adapter translates Array[VoxelMaterial] into Array[Dict]
// (main thread, before terrain streaming begins). The dicts shape:
//   ores  -> {material_id, replaces_material_id, min_altitude_voxels,
//             max_altitude_voxels, ore_noise_threshold, ore_noise_scale}
//   disks -> {material_id, disk_radius_voxels, disk_half_height_voxels,
//             disk_anchor_density, disk_max_distance_to_water_voxels}
// Missing or wrong-typed keys fall through to POD defaults (no crash,
// no warning — the bootstrap is expected to pass clean data).

void HeightmapGeneratorBase::set_ore_materials(const Array &p_list) {
    _ore_materials.clear();
    _ore_materials.reserve(p_list.size());
    for (int i = 0; i < p_list.size(); ++i) {
        Variant v = p_list[i];
        if (v.get_type() != Variant::DICTIONARY) {
            continue;
        }
        Dictionary d = v;
        OreMaterialPOD pod;
        pod.material_id = static_cast<int>(static_cast<int64_t>(d.get("material_id", 0)));
        pod.replaces_material_id = static_cast<int>(static_cast<int64_t>(d.get("replaces_material_id", 0)));
        pod.min_altitude_voxels = static_cast<int>(static_cast<int64_t>(d.get("min_altitude_voxels", 0)));
        pod.max_altitude_voxels = static_cast<int>(static_cast<int64_t>(d.get("max_altitude_voxels", 0)));
        pod.ore_noise_threshold = static_cast<double>(d.get("ore_noise_threshold", 0.0));
        pod.ore_noise_scale = static_cast<double>(d.get("ore_noise_scale", 0.0));
        _ore_materials.push_back(pod);
    }
}

int HeightmapGeneratorBase::get_ore_material_count() const {
    return static_cast<int>(_ore_materials.size());
}

void HeightmapGeneratorBase::set_disk_materials(const Array &p_list) {
    _disk_materials.clear();
    _disk_materials.reserve(p_list.size());
    for (int i = 0; i < p_list.size(); ++i) {
        Variant v = p_list[i];
        if (v.get_type() != Variant::DICTIONARY) {
            continue;
        }
        Dictionary d = v;
        DiskMaterialPOD pod;
        pod.material_id = static_cast<int>(static_cast<int64_t>(d.get("material_id", 0)));
        pod.disk_radius_voxels = static_cast<int>(static_cast<int64_t>(d.get("disk_radius_voxels", 0)));
        pod.disk_half_height_voxels = static_cast<int>(static_cast<int64_t>(d.get("disk_half_height_voxels", 0)));
        pod.disk_anchor_density = static_cast<double>(d.get("disk_anchor_density", 0.0));
        pod.disk_max_distance_to_water_voxels = static_cast<int>(static_cast<int64_t>(d.get("disk_max_distance_to_water_voxels", 0)));
        _disk_materials.push_back(pod);
    }
}

int HeightmapGeneratorBase::get_disk_material_count() const {
    return static_cast<int>(_disk_materials.size());
}

// ----- Tier 1 cliff helper ----------------------------------------------
//
// Mirrors scripts/CubicHeightmapGenerator.gd:599 _column_is_cliff.
// Worker-thread safe as long as the concrete compute_ground_y is.

bool HeightmapGeneratorBase::column_is_cliff(int world_x, int world_z, int this_ground_y) const {
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

// ----- Tier 5 disk helper -----------------------------------------------
//
// Mirrors scripts/CubicHeightmapGenerator.gd:405 _disk_at_column.
//
// GD `floori(x)` rounds toward -inf; `(int)std::floor(x)` matches.
// GD `int(x)` truncates toward zero; `static_cast<int>(x)` matches.

const DiskMaterialPOD *HeightmapGeneratorBase::disk_at_column(int world_x, int world_z, int ground_y) const {
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

// ----- Block fill: shared inner loop ------------------------------------
//
// The chunk hot loop. compute_ground_y is virtual; the cubic generator
// dispatches to FastNoiseLite sampling, the Copper Isles generator
// dispatches to EXR bilinear sampling. Everything else is identical.
// LOD-stride sampling + Tier 1–6 rules + bedrock + water byte emission
// match the GDScript original byte-for-byte (verified by per-port parity
// harnesses before retirement).

void HeightmapGeneratorBase::generate_block_into_buffer(Variant out_buffer,
                                                        Vector3i origin_in_voxels,
                                                        int lod) {
    // Cache-miss telemetry: Zylann only calls into _generate_block when
    // a chunk isn't already in the VoxelStream (SQLite). One call =
    // one cache miss. Worker-thread safe via atomic.
    _generated_block_count.fetch_add(1, std::memory_order_relaxed);

    Variant size_v = out_buffer.call("get_size");
    if (size_v.get_type() != Variant::VECTOR3I) {
        UtilityFunctions::printerr(
                "HeightmapGeneratorBase: out_buffer.get_size() did not return Vector3i");
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

    // Bedrock + water emission. Water Voxel V2: water is a TYPE block
    // emitted at ALL LODs (was LOD0-only DATA5) so distant ocean meshes
    // with terrain via the blocky mesher — no horizon plane needed.
    // NoEditZone-water suppression from the old GD generator is
    // deliberately omitted — that feature is no longer used.
    const int world_floor_y = _world_floor_voxel_y;
    const int bedrock_id = _bedrock_material_id;
    const int sea_level_v = _sea_level_voxels;
    const bool write_water = true;

    // Tier 2 snow line. Gated by snow_material_id != 0 (mirrors the GD
    // `snow_id != 0` check) and snow_line_max_lod.
    const int snow_id = _snow_material_id;
    const int snow_alt_voxels = _snow_line_voxels;
    const int snow_block = _snow_line_jitter_block_size < 1 ? 1 : _snow_line_jitter_block_size;
    const double snow_jitter_amp = static_cast<double>(_snow_line_jitter_voxels);
    const int64_t snow_seed = _snow_line_seed;
    const bool run_snow_line = snow_id != 0
            && _snow_line_max_lod >= 0
            && lod <= _snow_line_max_lod;

    // Tier 1 cliff. LOD-gated to skip the 4× per-column ground_y resamples
    // at distant LODs.
    const bool run_cliff_rule = _cliff_rule_max_lod >= 0 && lod <= _cliff_rule_max_lod;

    // Tier 4 ore veins + Tier 6 cliff outcrops. has_ores feeds Tier 6 too;
    // run_ore_veins additionally requires ore_vein_max_lod (Tier 4 only).
    const bool has_ores = !_ore_materials.empty();
    const bool run_ore_veins = has_ores
            && _ore_vein_max_lod >= 0
            && lod <= _ore_vein_max_lod;
    const double cliff_ore_chance = _cliff_ore_outcrop_chance;
    const int64_t cliff_ore_seed = _cliff_ore_seed;

    // Tier 5 disks. LOD-gated AND requires a non-empty list.
    const bool run_disk_rule = _disk_rule_max_lod >= 0
            && lod <= _disk_rule_max_lod
            && !_disk_materials.empty();

    for (int z = 0; z < size.z; ++z) {
        for (int x = 0; x < size.x; ++x) {
            const int world_x = origin_in_voxels.x + x * stride;
            const int world_z = origin_in_voxels.z + z * stride;
            const int ground_y = compute_ground_y(world_x, world_z);

            // Top-band selection: grass by default, sand if column dips
            // at or below the beach line.
            int top_id = GRASS_MATERIAL_ID;
            if (ground_y <= beach_y) {
                top_id = SAND_MATERIAL_ID;
            }

            // Tier 1 cliff slope. When a column has a steep drop to any
            // 4-neighbour, collapse top + dirt to bare stone.
            int col_dirt_band_end = dirt_band_end;
            const bool col_is_cliff = run_cliff_rule
                    && column_is_cliff(world_x, world_z, ground_y);
            if (col_is_cliff) {
                top_id = STONE_MATERIAL_ID;
                col_dirt_band_end = grass_thick;
                // Tier 6 cliff ore outcrops. Dice + uniform pick from the
                // ore list, gated by the picked ore's altitude band.
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
                        const OreMaterialPOD &ore_pick = _ore_materials[ore_idx];
                        if (ground_y >= ore_pick.min_altitude_voxels
                                && ground_y <= ore_pick.max_altitude_voxels) {
                            top_id = ore_pick.material_id;
                        }
                    }
                }
            }

            // Tier 2 snow line. Non-cliff columns above (snow_alt + jitter)
            // get their top voxel turned to snow. Cliff faces poke through
            // snowcaps because col_is_cliff blocks the override.
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

            // Tier 5 per-column disk lookup. Non-cliff columns only.
            const DiskMaterialPOD *disk_match = nullptr;
            int disk_thickness = 0;
            if (run_disk_rule && !col_is_cliff) {
                disk_match = disk_at_column(world_x, world_z, ground_y);
                if (disk_match != nullptr) {
                    disk_thickness = 1 + disk_match->disk_half_height_voxels * 2;
                }
            }

            // Per-column water-emission gate: this column's ground dips
            // below sea level (write_water is now always true — water is
            // a TYPE block emitted at every LOD).
            const bool emit_water_here = write_water && ground_y < sea_level_v;

            // R4 micro-voxel flora scatter. Decide ONCE per column which
            // flora voxel (if any) sits in the air cell one voxel above the
            // surface (world_y == ground_y + 1):
            //   * LOD0 only — coarser LODs must NEVER mesh flora (a single
            //     10cm blade has no business surviving at a 2m+ voxel; it
            //     would also break LOD cross-fade against the flora-less
            //     coarse rings). This is the same lod==0 gate the design
            //     calls for, mirrored on the is_top_voxel coarse-LOD logic.
            //   * grassland only — the surface top material must be plain
            //     grass (so beaches/sand, snowcaps, cliffs, and near-water
            //     disks stay bare). top_id already folded in all those
            //     overrides above, so a single top_id==GRASS test is enough.
            //   * the surface must be ABOVE sea level — no underwater grass
            //     (ground_y + 1 would be a water cell otherwise).
            //   * deterministic: a per-(world_x, world_z, seed) hash decides
            //     grass vs flower vs nothing, so the same column always
            //     grows the same thing across regen / save / reload. Pure
            //     integer/double math — worker-thread safe, no RNG state.
            // flora_id 0 means "nothing here this column".
            int flora_id = 0;
            const bool flora_enabled = (lod == 0) && (_grass_blade_material_id != 0);
            if (flora_enabled
                    && top_id == GRASS_MATERIAL_ID
                    && disk_match == nullptr      // not on a clay/gravel disk surface
                    && (ground_y + 1) > sea_level_v) {
                // One hash roll in [0,1) picks the outcome. Layout:
                //   [0.00 .. 0.02)  -> a flower (red/blue split by a 2nd roll)
                //   [0.02 .. 0.37)  -> a grass blade   (~35% of grassland)
                //   [0.37 .. 1.00)  -> bare ground
                // ~2% flowers, ~35% grass — the design's locked densities.
                const double roll = voxel_gen::math::hash3(
                        world_x, 0, world_z, static_cast<int64_t>(_flora_seed));
                if (roll < 0.02) {
                    // Split flowers ~50/50 red/blue via an independent roll.
                    const double which = voxel_gen::math::hash3(
                            world_x, 1, world_z, static_cast<int64_t>(_flora_seed) + 1);
                    if (which < 0.5 && _flower_red_material_id != 0) {
                        flora_id = _flower_red_material_id;
                    } else if (_flower_blue_material_id != 0) {
                        flora_id = _flower_blue_material_id;
                    } else if (_flower_red_material_id != 0) {
                        flora_id = _flower_red_material_id;
                    } else {
                        flora_id = _grass_blade_material_id;  // no flower ids wired — fall back to grass
                    }
                } else if (roll < 0.37) {
                    flora_id = _grass_blade_material_id;
                }
            }

            // D1 micro-detail surface scatter: pebbles + twigs. Same air
            // cell as flora (world_y == ground_y + 1), LOD0-only, above sea
            // level, deterministic per-(world_x, world_z) hash but a
            // DIFFERENT salt (_surface_detail_seed) so the pattern is
            // statistically independent of where grass/flowers landed.
            // Surface detail only fills the cell when NO flora rolled there
            // (flora wins the cell) so the two never collide. Pebbles sit on
            // stone/dirt/sand/grass; twigs only on dirt/grass (a stick on a
            // beach or bare rock reads wrong). top_id already folded in
            // sand/stone/snow/ore overrides, so a top_id test is enough.
            const bool detail_enabled = (lod == 0) && (_pebble_material_id != 0 || _twig_material_id != 0);
            if (flora_id == 0
                    && detail_enabled
                    && disk_match == nullptr
                    && (ground_y + 1) > sea_level_v) {
                const bool ground_is_soft =
                        (top_id == DIRT_MATERIAL_ID || top_id == GRASS_MATERIAL_ID);
                const bool ground_takes_pebble =
                        (top_id == STONE_MATERIAL_ID || top_id == SAND_MATERIAL_ID || ground_is_soft);
                // One hash roll in [0,1). Layout (independent of flora's):
                //   [0.000 .. 0.015)  -> pebble (~1.5% on pebble-eligible)
                //   [0.015 .. 0.025)  -> twig   (~1.0% on dirt/grass only)
                //   [0.025 .. 1.000)  -> bare
                const double droll = voxel_gen::math::hash3(
                        world_x, 0, world_z, static_cast<int64_t>(_surface_detail_seed));
                if (droll < 0.015 && ground_takes_pebble && _pebble_material_id != 0) {
                    flora_id = _pebble_material_id;
                } else if (droll < 0.025 && ground_is_soft && _twig_material_id != 0) {
                    flora_id = _twig_material_id;
                }
            }

            for (int y = 0; y < size.y; ++y) {
                const int world_y = origin_in_voxels.y + y * stride;
                if (world_y > ground_y) {
                    // R4 flora: the single air cell ONE voxel above the
                    // surface becomes a grass blade / flower TYPE voxel
                    // when this column rolled flora above. Written into
                    // CHANNEL_TYPE just like terrain — the blocky mesher
                    // draws our injected cross-quad model for ids 24..26.
                    // No DATA5 byte (that's water-only). Placed BEFORE the
                    // water branch but they can't overlap: flora only rolls
                    // when ground_y+1 > sea_level (above water), water only
                    // fills cells <= sea_level. flora_id stays 0 at lod>0.
                    if (flora_id != 0 && world_y == ground_y + 1) {
                        out_buffer.call("set_voxel", flora_id, x, y, z, CHANNEL_TYPE);
                        continue;
                    }
                    // Air above terrain. If this air voxel sits at or
                    // below sea level and the column dips below sea
                    // level, it becomes a native fluid TYPE block
                    // (WATER_MATERIAL_ID = full level 23). The Zylann
                    // blocky mesher draws/auto-slopes it directly — no
                    // separate water mesher, no horizon plane.
                    if (emit_water_here && world_y <= sea_level_v) {
                        out_buffer.call("set_voxel", WATER_MATERIAL_ID, x, y, z, CHANNEL_TYPE);
                        // #14 SOURCE RULES (Phase 8a): generated ocean/
                        // lake cells are INFINITE SOURCES. Pin the
                        // WaterByteCodec source byte (MAX_LEVEL 8 |
                        // SOURCE_BIT 0x10 = 0x18 = 24) into CHANNEL_DATA5
                        // so WaterFlowManager.is_source() keeps them at
                        // level 8 and NEVER drains them — an ocean-fed
                        // channel doesn't deplete the sea. Player-dug
                        // pools are written NON-source by the sim
                        // (WaterByteCodec.pack(level,false,dir)) so they
                        // drain. This is the field the codec reserved
                        // but the generator never wrote until now.
                        out_buffer.call("set_voxel", WATER_SOURCE_BYTE, x, y, z, CHANNEL_DATA5);
                    }
                    continue;
                }
                // World floor enforcement:
                //   world_y <  world_floor_y → air (no voxel written)
                //   world_y == world_floor_y → bedrock row (unmineable)
                //   world_y >  world_floor_y → normal band selection
                if (world_y < world_floor_y) {
                    continue;
                }
                if (world_y == world_floor_y && bedrock_id != 0) {
                    out_buffer.call("set_voxel", bedrock_id, x, y, z, CHANNEL_TYPE);
                    continue;
                }
                // Depth measured DOWN from ground_y. depth=0 is top voxel.
                const int depth = ground_y - world_y;

                // Topmost solid voxel of the column. At coarse LODs each
                // voxel spans `stride` (= 2^lod) fine units, so the top
                // voxel's depth (measured from the fine-grained ground_y)
                // is usually 1..stride-1 and would fall PAST the thin
                // grass band into the dirt band — making coarse LODs
                // render DIRT-topped and flicker against the grass fine
                // LOD during LOD cross-fades (designer bug 2026-05-20).
                // Force the topmost voxel to the surface material (top_id)
                // at lod>0. lod==0 is left byte-identical: stride is 1 so
                // depth==0 there, already inside the grass band — LOD0
                // parity holds; only coarse-LOD baselines change.
                const bool is_top_voxel = (lod > 0) && (depth < stride);

                int mat_id;
                if (depth < grass_thick || is_top_voxel) {
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
                    // instead of per-voxel speckle.
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

                    // Tier 4 ore veins. Each ore replaces only its declared
                    // parent material (e.g. plain stone), so marble/stone_dark
                    // variants don't get overrun.
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

                // Tier 5 disk override on the top voxels of any column
                // inside a near-water disk anchor.
                if (disk_match != nullptr && depth < disk_thickness) {
                    mat_id = disk_match->material_id;
                }
                out_buffer.call("set_voxel", mat_id, x, y, z, CHANNEL_TYPE);
            }
        }
    }
}

// ----- ClassDB bindings --------------------------------------------------

void HeightmapGeneratorBase::_bind_methods() {
    // Band properties
    ClassDB::bind_method(D_METHOD("set_grass_layer_thickness_voxels", "value"),
                         &HeightmapGeneratorBase::set_grass_layer_thickness_voxels);
    ClassDB::bind_method(D_METHOD("get_grass_layer_thickness_voxels"),
                         &HeightmapGeneratorBase::get_grass_layer_thickness_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "grass_layer_thickness_voxels"),
                 "set_grass_layer_thickness_voxels", "get_grass_layer_thickness_voxels");

    ClassDB::bind_method(D_METHOD("set_dirt_layer_thickness_voxels", "value"),
                         &HeightmapGeneratorBase::set_dirt_layer_thickness_voxels);
    ClassDB::bind_method(D_METHOD("get_dirt_layer_thickness_voxels"),
                         &HeightmapGeneratorBase::get_dirt_layer_thickness_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "dirt_layer_thickness_voxels"),
                 "set_dirt_layer_thickness_voxels", "get_dirt_layer_thickness_voxels");

    ClassDB::bind_method(D_METHOD("set_beach_y_threshold", "value"),
                         &HeightmapGeneratorBase::set_beach_y_threshold);
    ClassDB::bind_method(D_METHOD("get_beach_y_threshold"),
                         &HeightmapGeneratorBase::get_beach_y_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "beach_y_threshold"),
                 "set_beach_y_threshold", "get_beach_y_threshold");

    // Tier 3 marble
    ClassDB::bind_method(D_METHOD("set_marble_jitter_block_size", "value"),
                         &HeightmapGeneratorBase::set_marble_jitter_block_size);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_block_size"),
                         &HeightmapGeneratorBase::get_marble_jitter_block_size);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_block_size"),
                 "set_marble_jitter_block_size", "get_marble_jitter_block_size");

    ClassDB::bind_method(D_METHOD("set_marble_jitter_seed", "value"),
                         &HeightmapGeneratorBase::set_marble_jitter_seed);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_seed"),
                         &HeightmapGeneratorBase::get_marble_jitter_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_seed"),
                 "set_marble_jitter_seed", "get_marble_jitter_seed");

    ClassDB::bind_method(D_METHOD("set_marble_rare_threshold", "value"),
                         &HeightmapGeneratorBase::set_marble_rare_threshold);
    ClassDB::bind_method(D_METHOD("get_marble_rare_threshold"),
                         &HeightmapGeneratorBase::get_marble_rare_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "marble_rare_threshold"),
                 "set_marble_rare_threshold", "get_marble_rare_threshold");

    ClassDB::bind_method(D_METHOD("set_marble_dark_threshold", "value"),
                         &HeightmapGeneratorBase::set_marble_dark_threshold);
    ClassDB::bind_method(D_METHOD("get_marble_dark_threshold"),
                         &HeightmapGeneratorBase::get_marble_dark_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "marble_dark_threshold"),
                 "set_marble_dark_threshold", "get_marble_dark_threshold");

    ClassDB::bind_method(D_METHOD("set_marble_jitter_max_lod", "value"),
                         &HeightmapGeneratorBase::set_marble_jitter_max_lod);
    ClassDB::bind_method(D_METHOD("get_marble_jitter_max_lod"),
                         &HeightmapGeneratorBase::get_marble_jitter_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "marble_jitter_max_lod"),
                 "set_marble_jitter_max_lod", "get_marble_jitter_max_lod");

    // Bedrock + world floor + sea
    ClassDB::bind_method(D_METHOD("set_bedrock_material_id", "value"),
                         &HeightmapGeneratorBase::set_bedrock_material_id);
    ClassDB::bind_method(D_METHOD("get_bedrock_material_id"),
                         &HeightmapGeneratorBase::get_bedrock_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "bedrock_material_id"),
                 "set_bedrock_material_id", "get_bedrock_material_id");

    ClassDB::bind_method(D_METHOD("set_world_floor_voxel_y", "value"),
                         &HeightmapGeneratorBase::set_world_floor_voxel_y);
    ClassDB::bind_method(D_METHOD("get_world_floor_voxel_y"),
                         &HeightmapGeneratorBase::get_world_floor_voxel_y);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "world_floor_voxel_y"),
                 "set_world_floor_voxel_y", "get_world_floor_voxel_y");

    ClassDB::bind_method(D_METHOD("set_sea_level_voxels", "value"),
                         &HeightmapGeneratorBase::set_sea_level_voxels);
    ClassDB::bind_method(D_METHOD("get_sea_level_voxels"),
                         &HeightmapGeneratorBase::get_sea_level_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "sea_level_voxels"),
                 "set_sea_level_voxels", "get_sea_level_voxels");

    // Tier 2 snow line
    ClassDB::bind_method(D_METHOD("set_snow_material_id", "value"),
                         &HeightmapGeneratorBase::set_snow_material_id);
    ClassDB::bind_method(D_METHOD("get_snow_material_id"),
                         &HeightmapGeneratorBase::get_snow_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_material_id"),
                 "set_snow_material_id", "get_snow_material_id");

    ClassDB::bind_method(D_METHOD("set_snow_line_voxels", "value"),
                         &HeightmapGeneratorBase::set_snow_line_voxels);
    ClassDB::bind_method(D_METHOD("get_snow_line_voxels"),
                         &HeightmapGeneratorBase::get_snow_line_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_voxels"),
                 "set_snow_line_voxels", "get_snow_line_voxels");

    ClassDB::bind_method(D_METHOD("set_snow_line_jitter_voxels", "value"),
                         &HeightmapGeneratorBase::set_snow_line_jitter_voxels);
    ClassDB::bind_method(D_METHOD("get_snow_line_jitter_voxels"),
                         &HeightmapGeneratorBase::get_snow_line_jitter_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_jitter_voxels"),
                 "set_snow_line_jitter_voxels", "get_snow_line_jitter_voxels");

    ClassDB::bind_method(D_METHOD("set_snow_line_jitter_block_size", "value"),
                         &HeightmapGeneratorBase::set_snow_line_jitter_block_size);
    ClassDB::bind_method(D_METHOD("get_snow_line_jitter_block_size"),
                         &HeightmapGeneratorBase::get_snow_line_jitter_block_size);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_jitter_block_size"),
                 "set_snow_line_jitter_block_size", "get_snow_line_jitter_block_size");

    ClassDB::bind_method(D_METHOD("set_snow_line_seed", "value"),
                         &HeightmapGeneratorBase::set_snow_line_seed);
    ClassDB::bind_method(D_METHOD("get_snow_line_seed"),
                         &HeightmapGeneratorBase::get_snow_line_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_seed"),
                 "set_snow_line_seed", "get_snow_line_seed");

    ClassDB::bind_method(D_METHOD("set_snow_line_max_lod", "value"),
                         &HeightmapGeneratorBase::set_snow_line_max_lod);
    ClassDB::bind_method(D_METHOD("get_snow_line_max_lod"),
                         &HeightmapGeneratorBase::get_snow_line_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "snow_line_max_lod"),
                 "set_snow_line_max_lod", "get_snow_line_max_lod");

    // Tier 1 cliff
    ClassDB::bind_method(D_METHOD("set_cliff_slope_sample_distance_voxels", "value"),
                         &HeightmapGeneratorBase::set_cliff_slope_sample_distance_voxels);
    ClassDB::bind_method(D_METHOD("get_cliff_slope_sample_distance_voxels"),
                         &HeightmapGeneratorBase::get_cliff_slope_sample_distance_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_slope_sample_distance_voxels"),
                 "set_cliff_slope_sample_distance_voxels", "get_cliff_slope_sample_distance_voxels");

    ClassDB::bind_method(D_METHOD("set_cliff_slope_threshold_voxels", "value"),
                         &HeightmapGeneratorBase::set_cliff_slope_threshold_voxels);
    ClassDB::bind_method(D_METHOD("get_cliff_slope_threshold_voxels"),
                         &HeightmapGeneratorBase::get_cliff_slope_threshold_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_slope_threshold_voxels"),
                 "set_cliff_slope_threshold_voxels", "get_cliff_slope_threshold_voxels");

    ClassDB::bind_method(D_METHOD("set_cliff_rule_max_lod", "value"),
                         &HeightmapGeneratorBase::set_cliff_rule_max_lod);
    ClassDB::bind_method(D_METHOD("get_cliff_rule_max_lod"),
                         &HeightmapGeneratorBase::get_cliff_rule_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_rule_max_lod"),
                 "set_cliff_rule_max_lod", "get_cliff_rule_max_lod");

    ClassDB::bind_method(D_METHOD("column_is_cliff", "world_x", "world_z", "this_ground_y"),
                         &HeightmapGeneratorBase::column_is_cliff);

    // POD snapshot setters (no ADD_PROPERTY — bootstrap-only).
    ClassDB::bind_method(D_METHOD("set_ore_materials", "list"),
                         &HeightmapGeneratorBase::set_ore_materials);
    ClassDB::bind_method(D_METHOD("get_ore_material_count"),
                         &HeightmapGeneratorBase::get_ore_material_count);
    ClassDB::bind_method(D_METHOD("set_disk_materials", "list"),
                         &HeightmapGeneratorBase::set_disk_materials);
    ClassDB::bind_method(D_METHOD("get_disk_material_count"),
                         &HeightmapGeneratorBase::get_disk_material_count);

    // Tier 4 / 5 / 6 gates
    ClassDB::bind_method(D_METHOD("set_ore_vein_max_lod", "value"),
                         &HeightmapGeneratorBase::set_ore_vein_max_lod);
    ClassDB::bind_method(D_METHOD("get_ore_vein_max_lod"),
                         &HeightmapGeneratorBase::get_ore_vein_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "ore_vein_max_lod"),
                 "set_ore_vein_max_lod", "get_ore_vein_max_lod");

    ClassDB::bind_method(D_METHOD("set_disk_rule_max_lod", "value"),
                         &HeightmapGeneratorBase::set_disk_rule_max_lod);
    ClassDB::bind_method(D_METHOD("get_disk_rule_max_lod"),
                         &HeightmapGeneratorBase::get_disk_rule_max_lod);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "disk_rule_max_lod"),
                 "set_disk_rule_max_lod", "get_disk_rule_max_lod");

    ClassDB::bind_method(D_METHOD("set_disk_anchor_grid_voxels", "value"),
                         &HeightmapGeneratorBase::set_disk_anchor_grid_voxels);
    ClassDB::bind_method(D_METHOD("get_disk_anchor_grid_voxels"),
                         &HeightmapGeneratorBase::get_disk_anchor_grid_voxels);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "disk_anchor_grid_voxels"),
                 "set_disk_anchor_grid_voxels", "get_disk_anchor_grid_voxels");

    ClassDB::bind_method(D_METHOD("set_cliff_ore_outcrop_chance", "value"),
                         &HeightmapGeneratorBase::set_cliff_ore_outcrop_chance);
    ClassDB::bind_method(D_METHOD("get_cliff_ore_outcrop_chance"),
                         &HeightmapGeneratorBase::get_cliff_ore_outcrop_chance);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cliff_ore_outcrop_chance"),
                 "set_cliff_ore_outcrop_chance", "get_cliff_ore_outcrop_chance");

    ClassDB::bind_method(D_METHOD("set_cliff_ore_seed", "value"),
                         &HeightmapGeneratorBase::set_cliff_ore_seed);
    ClassDB::bind_method(D_METHOD("get_cliff_ore_seed"),
                         &HeightmapGeneratorBase::get_cliff_ore_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cliff_ore_seed"),
                 "set_cliff_ore_seed", "get_cliff_ore_seed");

    // R4 flora scatter ids + seed (default 0 = disabled).
    ClassDB::bind_method(D_METHOD("set_grass_blade_material_id", "value"),
                         &HeightmapGeneratorBase::set_grass_blade_material_id);
    ClassDB::bind_method(D_METHOD("get_grass_blade_material_id"),
                         &HeightmapGeneratorBase::get_grass_blade_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "grass_blade_material_id"),
                 "set_grass_blade_material_id", "get_grass_blade_material_id");

    ClassDB::bind_method(D_METHOD("set_flower_red_material_id", "value"),
                         &HeightmapGeneratorBase::set_flower_red_material_id);
    ClassDB::bind_method(D_METHOD("get_flower_red_material_id"),
                         &HeightmapGeneratorBase::get_flower_red_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "flower_red_material_id"),
                 "set_flower_red_material_id", "get_flower_red_material_id");

    ClassDB::bind_method(D_METHOD("set_flower_blue_material_id", "value"),
                         &HeightmapGeneratorBase::set_flower_blue_material_id);
    ClassDB::bind_method(D_METHOD("get_flower_blue_material_id"),
                         &HeightmapGeneratorBase::get_flower_blue_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "flower_blue_material_id"),
                 "set_flower_blue_material_id", "get_flower_blue_material_id");

    ClassDB::bind_method(D_METHOD("set_flora_seed", "value"),
                         &HeightmapGeneratorBase::set_flora_seed);
    ClassDB::bind_method(D_METHOD("get_flora_seed"),
                         &HeightmapGeneratorBase::get_flora_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "flora_seed"),
                 "set_flora_seed", "get_flora_seed");

    // D1 surface-detail scatter ids + seed (default 0 = disabled).
    ClassDB::bind_method(D_METHOD("set_pebble_material_id", "value"),
                         &HeightmapGeneratorBase::set_pebble_material_id);
    ClassDB::bind_method(D_METHOD("get_pebble_material_id"),
                         &HeightmapGeneratorBase::get_pebble_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "pebble_material_id"),
                 "set_pebble_material_id", "get_pebble_material_id");

    ClassDB::bind_method(D_METHOD("set_twig_material_id", "value"),
                         &HeightmapGeneratorBase::set_twig_material_id);
    ClassDB::bind_method(D_METHOD("get_twig_material_id"),
                         &HeightmapGeneratorBase::get_twig_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "twig_material_id"),
                 "set_twig_material_id", "get_twig_material_id");

    ClassDB::bind_method(D_METHOD("set_surface_detail_seed", "value"),
                         &HeightmapGeneratorBase::set_surface_detail_seed);
    ClassDB::bind_method(D_METHOD("get_surface_detail_seed"),
                         &HeightmapGeneratorBase::get_surface_detail_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "surface_detail_seed"),
                 "set_surface_detail_seed", "get_surface_detail_seed");

    // Core API — compute_ground_y is virtual; ClassDB dispatches to the
    // concrete child override at runtime. get_ground_voxel_y_at is the
    // bake-controller-facing alias.
    ClassDB::bind_method(D_METHOD("compute_ground_y", "world_x", "world_z"),
                         &HeightmapGeneratorBase::compute_ground_y);
    ClassDB::bind_method(D_METHOD("get_ground_voxel_y_at", "world_x", "world_z"),
                         &HeightmapGeneratorBase::get_ground_voxel_y_at);
    ClassDB::bind_method(
            D_METHOD("generate_block_into_buffer", "out_buffer", "origin_in_voxels", "lod"),
            &HeightmapGeneratorBase::generate_block_into_buffer);

    // Cache-miss telemetry — see heightmap_generator_base.h.
    ClassDB::bind_method(D_METHOD("get_generated_block_count"),
                         &HeightmapGeneratorBase::get_generated_block_count);
    ClassDB::bind_method(D_METHOD("reset_generated_block_count"),
                         &HeightmapGeneratorBase::reset_generated_block_count);
}
