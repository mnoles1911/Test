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
// Water Voxel V2 (Minecraft model, 2026-05-16): water is a normal TYPE
// block (blocky model id 5 = transparent water cube). Below-sea-level
// air cells get this written into CHANNEL_TYPE at ALL LODs, replacing
// the old CHANNEL_DATA5 WATER_SOURCE_BYTE side-channel. The blocky
// mesher draws it (transparent pass) like every other block — no
// separate WaterChunkMesher, no horizon plane.
static constexpr int WATER_MATERIAL_ID = 5;
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

            for (int y = 0; y < size.y; ++y) {
                const int world_y = origin_in_voxels.y + y * stride;
                if (world_y > ground_y) {
                    // Air above terrain. If this air voxel sits at or
                    // below sea level and the column dips below sea
                    // level, it becomes a WATER TYPE block (Minecraft
                    // model). The blocky mesher draws model id 5 (the
                    // transparent water cube) directly — no DATA5, no
                    // separate water mesher.
                    if (emit_water_here && world_y <= sea_level_v) {
                        out_buffer.call("set_voxel", WATER_MATERIAL_ID, x, y, z, CHANNEL_TYPE);
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
