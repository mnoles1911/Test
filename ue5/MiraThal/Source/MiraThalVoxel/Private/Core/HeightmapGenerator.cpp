// HeightmapGenerator.cpp — implementation of the engine-agnostic terrain +
// biome generator declared in Core/HeightmapGenerator.h.
//
// This is the ported LOGIC of three Godot godot-cpp files folded into one
// pure-C++17 unit:
//   * cubic_heightmap_generator.cpp  → legacy_ground_y (three-layer noise)
//   * heightmap_generator_base.cpp   → column_is_cliff / resolve_column /
//                                       material_at (banding + flora + water)
//   * biome_field.cpp                → sample_controls / classify / blend /
//                                       height_from_params / weight resolution
//
// The only thing swapped is the continuous noise primitive: every
// `noise->get_noise_2d(a, b)` from the Godot source becomes
// `mira::noise::noise2d(a, b, seed)`. The integer hash3 scatter, the banding
// rules, the sea-level offset, the biome relief blend and every material id
// are carried over faithfully. See Core/Noise.h for the divergence note.

#include "Core/HeightmapGenerator.h"

#include <algorithm>
#include <cmath>

namespace mira {

// ============================================================================
// Legacy three-layer cubic heightfield.
//
// Mirror of CubicHeightmapGeneratorCpp::compute_ground_y. The Godot version
// sampled FastNoiseLite three times (macro / mid / detail), truncated each
// layer to an int, and summed with the height offset. We sample mira::noise
// instead. The truncation + quantize semantics are preserved exactly:
//   * static_cast<int>(double) truncates toward zero (matches GDScript int()).
//   * std::lround rounds half-away-from-zero (matches GDScript roundi()).
// ============================================================================
int HeightmapGenerator::legacy_ground_y(int world_x, int world_z) const {
    const double half_range = height_range_voxels * 0.5;

    // MACRO layer. The Godot path fed raw world coords into FastNoiseLite
    // (which applied its own low base frequency). Here we pre-scale by
    // macro_frequency so the macro relief is large-scale, then use fBm for a
    // richer hill profile than a single octave gives.
    const double n_macro = noise::fbm2d(static_cast<double>(world_x) * macro_frequency,
                                        static_cast<double>(world_z) * macro_frequency,
                                        seed_, 4);
    int macro_y;
    if (quantize_to_meters) {
        const long macro_meters = std::lround(n_macro * half_range / 8.0);
        macro_y = static_cast<int>(macro_meters * 8L);
    } else {
        macro_y = static_cast<int>(n_macro * half_range);
    }

    // MID layer — frequency is a ratio of the macro frequency, mirroring the
    // source's mid_frequency_multiplier applied on top of the base.
    const double n_mid = noise::noise2d(
            static_cast<double>(world_x) * macro_frequency * mid_frequency_multiplier,
            static_cast<double>(world_z) * macro_frequency * mid_frequency_multiplier,
            seed_ + 101);
    const int mid_y = static_cast<int>(n_mid * static_cast<double>(mid_amplitude_voxels));

    // DETAIL layer.
    const double n_detail = noise::noise2d(
            static_cast<double>(world_x) * macro_frequency * detail_frequency_multiplier,
            static_cast<double>(world_z) * macro_frequency * detail_frequency_multiplier,
            seed_ + 202);
    const int detail_y = static_cast<int>(n_detail * static_cast<double>(detail_amplitude_voxels));

    return macro_y + mid_y + detail_y + height_offset_voxels;
}

// ============================================================================
// Biome control-field sampling. Mirror of BiomeFieldCpp::sample_controls.
//
// RELIEF and MOISTURE are two low-frequency fields decorrelated by sampling
// the SAME noise at far-apart coordinate offsets, with a domain warp so biome
// borders meander. All in metres (per-metre frequencies); the voxel→metre
// divide keeps the field scale-proof. FastNoiseLite returns [-1,1]; we remap
// relief/moisture to [0,1] exactly as the source does.
// ============================================================================
void HeightmapGenerator::sample_controls(int world_x, int world_z,
                                         double& out_relief, double& out_moisture) const {
    const double mx = static_cast<double>(world_x) / voxels_per_metre;
    const double mz = static_cast<double>(world_z) / voxels_per_metre;

    // Domain warp: sample a low-freq field at an offset, push the lookup.
    const double wf = warp_frequency_per_m;
    const double wx = noise::noise2d((mx + 1000.0) * wf, (mz - 1000.0) * wf, seed_ + 11);
    const double wz = noise::noise2d((mx - 2000.0) * wf, (mz + 2000.0) * wf, seed_ + 22);
    const double sx = mx + wx * warp_strength;
    const double sz = mz + wz * warp_strength;

    const double cf = control_frequency_per_m;
    // Relief: warped lookup at the base offset. Remap [-1,1] → [0,1].
    const double r = noise::noise2d(sx * cf, sz * cf, seed_ + 33);
    out_relief = std::clamp(r * 0.5 + 0.5, 0.0, 1.0);
    // Moisture: warped lookup at a large coordinate offset (decorrelated).
    const double m = noise::noise2d((sx + 31337.0) * cf, (sz - 24601.0) * cf, seed_ + 44);
    out_moisture = std::clamp(m * 0.5 + 0.5, 0.0, 1.0);
}

// ============================================================================
// Whittaker classifier. Mirror of BiomeFieldCpp::classify_kind_index.
// Same five thresholds; returns the bound profile slot for the chosen kind,
// or -1 if that kind was not loaded.
// ============================================================================
int HeightmapGenerator::classify_kind_index(double relief, double moisture) const {
    if (relief > 0.62) return idx_mountains;
    if (moisture < 0.33) return idx_desert;
    if (relief < 0.30) return idx_plains;
    if (moisture > 0.62) return idx_forest;
    return idx_hills;
}

// Smoothstep ramp in [0,1]: 0 at -margin, 1 at +margin. Mirror of the file-
// static ramp01 in biome_field.cpp.
static double ramp01(double signed_dist, double margin) {
    double t = (signed_dist + margin) / (2.0 * margin);
    t = std::clamp(t, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// ============================================================================
// Soft-membership weight resolution. Mirror of
// BiomeFieldCpp::resolve_biome_weights — same boundary-distance memberships,
// same ≤3-largest keep, same descending-weight/ascending-index total order.
// Writes up to 3 (index, weight) pairs; weights sum to 1.0.
// ============================================================================
void HeightmapGenerator::resolve_biome_weights(int world_x, int world_z,
                                               int out_indices[3], double out_weights[3],
                                               int& out_count) const {
    out_count = 0;
    if (profiles_.empty()) {
        return;
    }

    double relief, moisture;
    sample_controls(world_x, world_z, relief, moisture);
    const double m = (blend_margin > 1e-6) ? blend_margin : 1e-6;

    struct KindMembership { int idx; double mem; };
    KindMembership ks[5];
    int kn = 0;

    // mountains: relief > 0.62
    if (idx_mountains >= 0) {
        const double d = relief - 0.62;
        ks[kn++] = {idx_mountains, ramp01(d, m)};
    }
    // desert: relief <= 0.62 AND moisture < 0.33
    if (idx_desert >= 0) {
        const double d_relief = 0.62 - relief;
        const double d_moist = 0.33 - moisture;
        const double d = std::min(d_relief, d_moist);
        ks[kn++] = {idx_desert, ramp01(d, m)};
    }
    // plains: relief <= 0.62 AND moisture >= 0.33 AND relief < 0.30
    if (idx_plains >= 0) {
        const double d_relief_hi = 0.62 - relief;
        const double d_moist = moisture - 0.33;
        const double d_relief_lo = 0.30 - relief;
        const double d = std::min(std::min(d_relief_hi, d_moist), d_relief_lo);
        ks[kn++] = {idx_plains, ramp01(d, m)};
    }
    // forest: relief in [0.30,0.62] AND moisture > 0.62
    if (idx_forest >= 0) {
        const double d_relief_hi = 0.62 - relief;
        const double d_relief_lo = relief - 0.30;
        const double d_moist_lo = moisture - 0.62;
        const double d = std::min(std::min(d_relief_hi, d_relief_lo), d_moist_lo);
        ks[kn++] = {idx_forest, ramp01(d, m)};
    }
    // hills: relief in [0.30,0.62] AND moisture in [0.33,0.62]
    if (idx_hills >= 0) {
        const double d_relief_hi = 0.62 - relief;
        const double d_relief_lo = relief - 0.30;
        const double d_moist_hi = 0.62 - moisture;
        const double d_moist_lo = moisture - 0.33;
        const double d = std::min(std::min(d_relief_hi, d_relief_lo),
                                  std::min(d_moist_hi, d_moist_lo));
        ks[kn++] = {idx_hills, ramp01(d, m)};
    }

    // Triple-boundary fallback: if every membership collapsed to ~0, use the
    // hard classifier so the column is never biome-less.
    double total = 0.0;
    for (int i = 0; i < kn; ++i) total += ks[i].mem;
    if (total < 1e-9) {
        int hard = classify_kind_index(relief, moisture);
        if (hard < 0) hard = 0;
        out_indices[0] = hard;
        out_weights[0] = 1.0;
        out_count = 1;
        return;
    }

    // Keep the ≤3 largest. Sort descending membership, then ascending index
    // for a stable cross-language total order.
    std::sort(ks, ks + kn, [](const KindMembership& a, const KindMembership& b) {
        if (a.mem != b.mem) return a.mem > b.mem;
        return a.idx < b.idx;
    });
    int keep = std::min(kn, 3);
    double kept_total = 0.0;
    for (int i = 0; i < keep; ++i) kept_total += ks[i].mem;
    if (kept_total < 1e-12) kept_total = 1.0;

    int cnt = 0;
    for (int i = 0; i < keep; ++i) {
        if (ks[i].mem <= 0.0) continue;
        out_indices[cnt] = ks[i].idx;
        out_weights[cnt] = ks[i].mem / kept_total;
        ++cnt;
    }
    // Renormalize after dropping zero-weight entries.
    double s = 0.0;
    for (int i = 0; i < cnt; ++i) s += out_weights[i];
    if (s > 1e-12) {
        for (int i = 0; i < cnt; ++i) out_weights[i] /= s;
    }
    out_count = cnt;
}

// ============================================================================
// Parameter blending. Mirror of biome_field.cpp blend_pods — only the
// heightfield scalars are accumulated by weight (surface/flora/trees come
// from a single weighted-hash-picked biome, not a blend).
// ============================================================================
BiomeProfile HeightmapGenerator::blend_profiles(const int indices[3],
                                                const double weights[3],
                                                int count) const {
    BiomeProfile b;
    b.base_amplitude_m = 0;
    b.base_frequency_per_m = 0;
    b.ridge_mix = 0;
    b.flatness = 0;
    b.terrace_band_m = 0;
    b.terrace_sharpness = 0;
    b.mid_amplitude_m = 0;
    b.detail_amplitude_m = 0;
    double detail_slope_factor = 0.0;
    for (int i = 0; i < count; ++i) {
        const BiomeProfile& p = profiles_[indices[i]];
        const double w = weights[i];
        b.base_amplitude_m     += p.base_amplitude_m * w;
        b.base_frequency_per_m += p.base_frequency_per_m * w;
        b.ridge_mix            += p.ridge_mix * w;
        b.flatness             += p.flatness * w;
        b.terrace_band_m       += p.terrace_band_m * w;
        b.terrace_sharpness    += p.terrace_sharpness * w;
        b.mid_amplitude_m      += p.mid_amplitude_m * w;
        b.detail_amplitude_m   += p.detail_amplitude_m * w;
        detail_slope_factor    += (p.detail_slope_only ? 1.0 : 0.0) * w;
    }
    b.detail_slope_only = detail_slope_factor > 0.5;
    return b;
}

// ============================================================================
// Height from blended params. Mirror of BiomeFieldCpp::height_from_params.
// Three octaves of the SAME noise field shaped by ridge_mix / flatness /
// terraces, plus mid + (slope-gated) detail. Output is WORLD METRES of
// elevation above sea level; the caller converts to voxels + adds sea level.
// ============================================================================
double HeightmapGenerator::height_from_params(int world_x, int world_z,
                                              const BiomeProfile& p) const {
    const double mx = static_cast<double>(world_x) / voxels_per_metre;
    const double mz = static_cast<double>(world_z) / voxels_per_metre;

    // --- Macro octave ---
    const double bf = p.base_frequency_per_m;
    const double n = noise::noise2d(mx * bf, mz * bf, seed_ + 33); // [-1,1]

    // ridge_mix: lerp between billow (smooth hills) and ridged (sharp crests).
    const double billow = n * 0.5 + 0.5;       // [0,1]
    const double ridged = 1.0 - std::fabs(n);  // [0,1]
    double h01 = billow + (ridged - billow) * std::clamp(p.ridge_mix, 0.0, 1.0);

    // flatness plateau: blend h01 toward its smoothstep (compresses mid-band
    // into plateaus, preserves the tails).
    const double sc = h01 * h01 * (3.0 - 2.0 * h01);
    const double fl = std::clamp(p.flatness, 0.0, 1.0);
    h01 = h01 + (sc - h01) * fl;

    // Map [0,1] to a signed half-range so sea level sits near the middle.
    double macro_m = (h01 - 0.5) * 2.0 * p.base_amplitude_m;

    // terraces: quantize into bands with rounded lips (band=0 disables).
    if (p.terrace_band_m > 1e-4) {
        const double band = p.terrace_band_m;
        const double q = std::floor(macro_m / band);
        const double frac = macro_m / band - q;
        const double lip = frac * frac * (3.0 - 2.0 * frac);
        const double stepped = (q + lip) * band;
        const double sh = std::clamp(p.terrace_sharpness, 0.0, 1.0);
        macro_m = macro_m + (stepped - macro_m) * sh;
    }

    double height_m = macro_m;

    // --- Mid + detail octaves (ratios of the macro frequency) ---
    const double mid_n = noise::noise2d(mx * bf * 3.0, mz * bf * 3.0, seed_ + 55);
    height_m += mid_n * p.mid_amplitude_m;

    bool emit_detail = true;
    if (p.detail_slope_only) {
        const double eps = 1.0; // 1 metre probe
        const double nn = noise::noise2d((mx + eps) * bf, mz * bf, seed_ + 33);
        const double slope = std::fabs(nn - n) * p.base_amplitude_m;
        emit_detail = slope > 0.15;
    }
    if (emit_detail) {
        const double det_n = noise::noise2d(mx * bf * 12.0, mz * bf * 12.0, seed_ + 66);
        height_m += det_n * p.detail_amplitude_m;
    }
    return height_m;
}

// ============================================================================
// Biome ground-Y. Mirror of BiomeFieldCpp::compute_ground_y: resolve weights,
// blend params, evaluate the heightfield in metres, floor to voxels RELATIVE
// to sea level (the caller adds the sea-level offset).
// ============================================================================
int HeightmapGenerator::biome_ground_y(int world_x, int world_z) const {
    int indices[3];
    double weights[3];
    int count = 0;
    resolve_biome_weights(world_x, world_z, indices, weights, count);
    if (count == 0) {
        return 0;
    }
    const BiomeProfile b = blend_profiles(indices, weights, count);
    const double height_m = height_from_params(world_x, world_z, b);
    return static_cast<int>(std::floor(height_m * voxels_per_metre));
}

// ============================================================================
// Surface biome pick (weighted hash). Mirror of
// BiomeFieldCpp::pick_surface_biome: deterministic per-(x,z) roll walks the
// cumulative weights so borders dither instead of cutting a hard line.
// ============================================================================
int HeightmapGenerator::pick_surface_biome(int world_x, int world_z) const {
    int indices[3];
    double weights[3];
    int count = 0;
    resolve_biome_weights(world_x, world_z, indices, weights, count);
    if (count == 0) return -1;
    if (count == 1) return indices[0];
    const double roll = hash3(world_x, 7, world_z, 0xB10E); // salt "BIOE"
    double acc = 0.0;
    for (int i = 0; i < count; ++i) {
        acc += weights[i];
        if (roll < acc) return indices[i];
    }
    return indices[count - 1];
}

int HeightmapGenerator::dominant_biome(int world_x, int world_z) const {
    int indices[3];
    double weights[3];
    int count = 0;
    resolve_biome_weights(world_x, world_z, indices, weights, count);
    if (count == 0) return -1;
    return indices[0]; // resolver sorts by descending weight
}

// ============================================================================
// compute_ground_y — top-level surface-Y. Mirror of
// CubicHeightmapGeneratorCpp::compute_ground_y dispatch: biome path adds the
// sea-level voxel offset to the biome's sea-relative height; legacy path runs
// the three-layer cubic noise.
// ============================================================================
int HeightmapGenerator::compute_ground_y(int world_x, int world_z) const {
    if (biome_active()) {
        return biome_ground_y(world_x, world_z) + sea_level_voxels;
    }
    return legacy_ground_y(world_x, world_z);
}

// ============================================================================
// Tier 1 cliff test. Mirror of HeightmapGeneratorBase::column_is_cliff:
// the column is a cliff if it drops >= threshold to any 4-neighbour sampled
// ±sample_distance away.
// ============================================================================
bool HeightmapGenerator::column_is_cliff(int world_x, int world_z, int this_ground_y) const {
    const int step = cliff_slope_sample_distance_voxels;
    if (step <= 0 || cliff_slope_threshold_voxels <= 0) {
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
    return max_drop >= cliff_slope_threshold_voxels;
}

// ============================================================================
// resolve_column — fold the per-column decisions out of the Godot block loop
// (heightmap_generator_base.cpp generate_block_into_buffer) into a single
// struct. Covers: biome surface pick, top-band selection (grass/sand/cliff),
// cliff collapse, water-below-sea flag, and the LOD0 flora/surface-detail
// scatter roll. Ore/disk/snow tiers are not modelled here (they need the POD
// lists wired by the bootstrap); the banding + flora + water rules that define
// "a sane stack" ARE.
// ============================================================================
ColumnInfo HeightmapGenerator::resolve_column(int world_x, int world_z) const {
    ColumnInfo col;
    const int ground_y = compute_ground_y(world_x, world_z);
    col.ground_y = ground_y;

    const int grass_thick = grass_layer_thickness_voxels;
    const int dirt_band_end = grass_thick + dirt_layer_thickness_voxels;
    col.dirt_band_end = dirt_band_end;

    // --- Biome surface resolution (once per column) ---
    int biome_top_id = mat::GRASS;
    int biome_cliff_id = mat::STONE;
    int biome_patch_id = 0;
    double biome_patch_freq = 0.0;
    double biome_patch_thresh = 0.0;
    double biome_grass_density = 0.35;
    double biome_flower_density = 0.02;
    bool col_biome = false;
    if (biome_active()) {
        const int surf = pick_surface_biome(world_x, world_z);
        if (surf >= 0 && surf < profile_count()) {
            const BiomeProfile& bp = profiles_[surf];
            biome_top_id = bp.top_material_id;
            biome_cliff_id = bp.slope_material_id;
            biome_patch_id = bp.patch_material_id;
            biome_patch_freq = bp.patch_frequency_per_m;
            biome_patch_thresh = bp.patch_threshold;
            biome_grass_density = bp.grass_density;
            biome_flower_density = bp.flower_density;
            col_biome = true;
            col.biome_index = surf;
        }
    }

    // Top-band selection: grass by default, sand below the beach line.
    int top_id = col_biome ? biome_top_id : mat::GRASS;
    if (ground_y <= beach_y_threshold) {
        top_id = mat::SAND;
    }

    // Biome patch scatter (gravel/litter) overrides the top material.
    if (col_biome && biome_patch_id != 0 && biome_patch_thresh > 0.0
            && ground_y > beach_y_threshold) {
        const double vpm = voxels_per_metre;
        const double pf = biome_patch_freq;
        const int64_t qx = static_cast<int64_t>(std::floor(
                (static_cast<double>(world_x) / vpm) * pf));
        const int64_t qz = static_cast<int64_t>(std::floor(
                (static_cast<double>(world_z) / vpm) * pf));
        const double ph = hash3(qx, 5, qz, 0x9A7C);
        if (ph < biome_patch_thresh) {
            top_id = biome_patch_id;
        }
    }

    // Tier 1 cliff slope: collapse top + dirt to bare stone (or biome slope).
    int col_dirt_band_end = dirt_band_end;
    const bool col_is_cliff = column_is_cliff(world_x, world_z, ground_y);
    if (col_is_cliff) {
        top_id = col_biome ? biome_cliff_id : mat::STONE;
        col_dirt_band_end = grass_thick;
    }
    col.is_cliff = col_is_cliff;
    col.dirt_band_end = col_dirt_band_end;
    col.top_id = top_id;

    // Water flag: this column's ground dips below sea level.
    col.below_sea = (ground_y < sea_level_voxels);

    // R4 flora + D1 surface-detail scatter (LOD0 semantics; one air cell at
    // ground_y+1). Mirrors the block-loop logic: grassland-only, above sea
    // level, deterministic per-(x,z,seed) hash. Records the chosen id in
    // col.flora_id (0 = nothing).
    int flora_id = 0;
    const bool col_is_grassland = (top_id == mat::GRASS);
    const double flower_cut = col_biome ? biome_flower_density : 0.02;
    const double grass_density = col_biome ? biome_grass_density : 0.35;
    // Sparse-clump grass: a coarse 16-voxel lattice cell hosts a clump ~18% of
    // the time (dense inside, rare strays outside). >> 4 = floor-div 16.
    const bool grass_clump = hash3(world_x >> 4, 5, world_z >> 4,
                                   flora_seed + 7) < 0.18;
    const double grass_cut = flower_cut + (grass_clump
            ? std::min(1.0, grass_density * 1.3)
            : grass_density * 0.043);

    if (grass_blade_material_id != 0
            && col_is_grassland
            && (ground_y + 1) > sea_level_voxels) {
        const double roll = hash3(world_x, 0, world_z, flora_seed);
        if (roll < flower_cut) {
            const double which = hash3(world_x, 1, world_z, flora_seed + 1);
            if (which < 0.5 && flower_red_material_id != 0) {
                flora_id = flower_red_material_id;
            } else if (flower_blue_material_id != 0) {
                flora_id = flower_blue_material_id;
            } else if (flower_red_material_id != 0) {
                flora_id = flower_red_material_id;
            } else {
                flora_id = grass_blade_material_id;
            }
        } else if (roll < grass_cut) {
            flora_id = grass_blade_material_id;
        }
    }

    // D1 surface detail fills the cell only when no flora rolled (flora wins),
    // with a DIFFERENT salt so the patterns don't correlate.
    if (flora_id == 0
            && (pebble_material_id != 0 || twig_material_id != 0)
            && (ground_y + 1) > sea_level_voxels) {
        const bool ground_is_soft = (top_id == mat::DIRT || top_id == mat::GRASS);
        const bool ground_takes_pebble =
                (top_id == mat::STONE || top_id == mat::SAND || ground_is_soft);
        const double pebble_cut = 0.015;
        const double twig_cut = pebble_cut + 0.010;
        const double droll = hash3(world_x, 0, world_z, surface_detail_seed);
        if (droll < pebble_cut && ground_takes_pebble && pebble_material_id != 0) {
            flora_id = pebble_material_id;
        } else if (droll < twig_cut && ground_is_soft && twig_material_id != 0) {
            flora_id = twig_material_id;
        }
    }
    col.flora_id = flora_id;

    return col;
}

// ============================================================================
// material_at — the per-voxel band selection for a resolved column. Mirror of
// the inner y-loop in generate_block_into_buffer (the LOD0, no-ore/disk path):
//   world_y >  ground_y                 → AIR (caller layers water/flora)
//   world_y <  world_floor_voxel_y      → AIR (below the world floor)
//   world_y == world_floor_voxel_y      → bedrock row (if enabled)
//   depth <  grass_thick                → top_id
//   depth <  dirt_band_end              → dirt
//   else                                → stone (with marble jitter)
// depth is measured DOWN from ground_y (depth 0 = top voxel).
// ============================================================================
int HeightmapGenerator::material_at(int world_x, int world_y, int world_z,
                                    const ColumnInfo& col) const {
    if (world_y > col.ground_y) {
        return mat::AIR; // caller decides water/flora above the surface
    }
    if (world_y < world_floor_voxel_y) {
        return mat::AIR;
    }
    if (world_y == world_floor_voxel_y && bedrock_material_id != 0) {
        return bedrock_material_id;
    }

    const int depth = col.ground_y - world_y;
    if (depth < grass_layer_thickness_voxels) {
        return col.top_id;
    }
    if (depth < col.dirt_band_end) {
        return mat::DIRT;
    }

    // Stone band with Tier 3 marble jitter (hash3 on block-quantized coords).
    int mat_id = mat::STONE;
    const int jitter_block = marble_jitter_block_size < 1 ? 1 : marble_jitter_block_size;
    const double nrm = hash3(static_cast<int64_t>(world_x) / jitter_block,
                             static_cast<int64_t>(world_y) / jitter_block,
                             static_cast<int64_t>(world_z) / jitter_block,
                             marble_jitter_seed);
    if (nrm > marble_rare_threshold) {
        mat_id = mat::MARBLE;
    } else if (nrm > marble_dark_threshold) {
        mat_id = mat::STONE_DARK;
    }
    return mat_id;
}

} // namespace mira
