#include "biome_field.h"

#include "voxel_gen_math.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace voxel_gen {

BiomeFieldCpp::BiomeFieldCpp() {}
BiomeFieldCpp::~BiomeFieldCpp() {}

// ----- Configuration -----------------------------------------------------

void BiomeFieldCpp::set_biome_profiles(const Array &p_list) {
    _profiles.clear();
    _profiles.reserve(p_list.size());
    for (int i = 0; i < p_list.size(); ++i) {
        Variant v = p_list[i];
        if (v.get_type() != Variant::DICTIONARY) {
            // Keep slot alignment: push a default so indices stay stable.
            _profiles.push_back(BiomeProfilePOD());
            continue;
        }
        Dictionary d = v;
        BiomeProfilePOD p;
        p.base_amplitude_m = static_cast<double>(d.get("base_amplitude_m", p.base_amplitude_m));
        p.base_frequency_per_m = static_cast<double>(d.get("base_frequency_per_m", p.base_frequency_per_m));
        p.ridge_mix = static_cast<double>(d.get("ridge_mix", p.ridge_mix));
        p.flatness = static_cast<double>(d.get("flatness", p.flatness));
        p.terrace_band_m = static_cast<double>(d.get("terrace_band_m", p.terrace_band_m));
        p.terrace_sharpness = static_cast<double>(d.get("terrace_sharpness", p.terrace_sharpness));
        p.mid_amplitude_m = static_cast<double>(d.get("mid_amplitude_m", p.mid_amplitude_m));
        p.detail_amplitude_m = static_cast<double>(d.get("detail_amplitude_m", p.detail_amplitude_m));
        p.detail_slope_only = static_cast<bool>(d.get("detail_slope_only", p.detail_slope_only));
        p.top_material_id = static_cast<int>(static_cast<int64_t>(d.get("top_material_id", p.top_material_id)));
        p.slope_material_id = static_cast<int>(static_cast<int64_t>(d.get("slope_material_id", p.slope_material_id)));
        p.slope_threshold = static_cast<double>(d.get("slope_threshold", p.slope_threshold));
        p.patch_material_id = static_cast<int>(static_cast<int64_t>(d.get("patch_material_id", p.patch_material_id)));
        p.patch_frequency_per_m = static_cast<double>(d.get("patch_frequency_per_m", p.patch_frequency_per_m));
        p.patch_threshold = static_cast<double>(d.get("patch_threshold", p.patch_threshold));
        p.micro_relief_chance = static_cast<double>(d.get("micro_relief_chance", p.micro_relief_chance));
        p.grass_density = static_cast<double>(d.get("grass_density", p.grass_density));
        p.flower_density = static_cast<double>(d.get("flower_density", p.flower_density));
        p.tree_density = static_cast<double>(d.get("tree_density", p.tree_density));
        p.tree_height_min_m = static_cast<double>(d.get("tree_height_min_m", p.tree_height_min_m));
        p.tree_height_max_m = static_cast<double>(d.get("tree_height_max_m", p.tree_height_max_m));
        p.tree_trunk_radius_min_vox = static_cast<double>(d.get("tree_trunk_radius_min_vox", p.tree_trunk_radius_min_vox));
        p.tree_trunk_radius_max_vox = static_cast<double>(d.get("tree_trunk_radius_max_vox", p.tree_trunk_radius_max_vox));
        p.tree_canopy_radius_min_vox = static_cast<double>(d.get("tree_canopy_radius_min_vox", p.tree_canopy_radius_min_vox));
        p.tree_canopy_radius_max_vox = static_cast<double>(d.get("tree_canopy_radius_max_vox", p.tree_canopy_radius_max_vox));
        _profiles.push_back(p);
    }
}

int BiomeFieldCpp::get_biome_profile_count() const {
    return static_cast<int>(_profiles.size());
}

void BiomeFieldCpp::set_biome_field_params(double control_frequency_per_m,
                                           double warp_frequency_per_m,
                                           double warp_strength,
                                           double blend_margin,
                                           double voxels_per_metre,
                                           int plains_index,
                                           int hills_index,
                                           int forest_index,
                                           int desert_index,
                                           int mountains_index) {
    _control_frequency_per_m = control_frequency_per_m;
    _warp_frequency_per_m = warp_frequency_per_m;
    _warp_strength = warp_strength;
    _blend_margin = (blend_margin > 1e-6) ? blend_margin : 1e-6;
    _voxels_per_metre = (voxels_per_metre > 1e-6) ? voxels_per_metre : 1.0;
    _idx_plains = plains_index;
    _idx_hills = hills_index;
    _idx_forest = forest_index;
    _idx_desert = desert_index;
    _idx_mountains = mountains_index;
}

void BiomeFieldCpp::set_control_noise(const Ref<FastNoiseLite> &p_noise) { _control_noise = p_noise; }
Ref<FastNoiseLite> BiomeFieldCpp::get_control_noise() const { return _control_noise; }

// ----- Control-field sampling --------------------------------------------
//
// RELIEF and MOISTURE are two independent low-frequency fields. We get
// independence cheaply by sampling the SAME FastNoiseLite at two far-apart
// coordinate offsets (a classic decorrelation trick). A third sample warps
// the lookup position so biome borders meander instead of following the
// noise's axis-aligned cells. All in metres (frequencies are per-metre);
// the voxel→metre divide makes the field scale-proof.

void BiomeFieldCpp::sample_controls(int world_x, int world_z, double &out_relief,
                                    double &out_moisture) const {
    if (_control_noise.is_null()) {
        out_relief = 0.5;
        out_moisture = 0.5;
        return;
    }
    const double mx = static_cast<double>(world_x) / _voxels_per_metre;
    const double mz = static_cast<double>(world_z) / _voxels_per_metre;

    // Domain warp: sample a low-freq field at an offset, push the lookup.
    const double wf = _warp_frequency_per_m;
    const double wx = static_cast<double>(_control_noise->get_noise_2d(
            (mx + 1000.0) * wf, (mz - 1000.0) * wf));
    const double wz = static_cast<double>(_control_noise->get_noise_2d(
            (mx - 2000.0) * wf, (mz + 2000.0) * wf));
    const double sx = mx + wx * _warp_strength;
    const double sz = mz + wz * _warp_strength;

    const double cf = _control_frequency_per_m;
    // Relief: warped lookup at the base offset. Remap [-1,1] -> [0,1].
    const double r = static_cast<double>(_control_noise->get_noise_2d(sx * cf, sz * cf));
    out_relief = std::clamp(r * 0.5 + 0.5, 0.0, 1.0);
    // Moisture: warped lookup at a large coordinate offset (decorrelated).
    const double m = static_cast<double>(_control_noise->get_noise_2d(
            (sx + 31337.0) * cf, (sz - 24601.0) * cf));
    out_moisture = std::clamp(m * 0.5 + 0.5, 0.0, 1.0);
}

// ----- Whittaker classification ------------------------------------------
//
// Decision cascade (tuned to the control noise's bell distribution — the
// FBM relief/moisture fields cluster around 0.5 with ~[0.11,0.87] tails, so
// the thresholds sit where each kind claims >=5% of the world; verified by
// the gate's histogram):
//   relief   > 0.62              -> mountains
//   moisture < 0.33              -> rocky_desert
//   relief   < 0.30              -> flat_plains
//   moisture > 0.62              -> deciduous_forest
//   else                          -> rolling_hills
// Returns the bound profile slot for the chosen kind, or -1 if that kind
// wasn't loaded (the resolver then drops the weight). These same five
// constants drive the soft-membership boundaries in resolve_biome_weights —
// keep the two in lockstep (and mirrored in BiomeReference.gd).

int BiomeFieldCpp::classify_kind_index(double relief, double moisture) const {
    if (relief > 0.62) return _idx_mountains;
    if (moisture < 0.33) return _idx_desert;
    if (relief < 0.30) return _idx_plains;
    if (moisture > 0.62) return _idx_forest;
    return _idx_hills;
}

// ----- Weight resolution -------------------------------------------------
//
// We sample the SAME column plus four tiny probes one blend-margin away in
// control space is overkill; instead we compute a soft membership from the
// SIGNED DISTANCE of (relief, moisture) to each classification boundary.
// For each of the five kinds we form a membership in [0,1] that is 1 deep
// inside the kind and ramps to 0 within `blend_margin` of its boundary,
// then normalize the (≤3 largest) memberships to sum to 1.
//
// This keeps borders smooth (params lerp across the margin) without a
// second noise lookup, and is trivially mirrorable in GD.

static double ramp01(double signed_dist, double margin) {
    // signed_dist > 0 = inside the kind by that much (control units).
    // Smoothstep from 0 at -margin to 1 at +margin.
    double t = (signed_dist + margin) / (2.0 * margin);
    t = std::clamp(t, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);  // smoothstep
}

Dictionary BiomeFieldCpp::resolve_biome_weights(int world_x, int world_z) const {
    Dictionary out;
    PackedInt32Array indices;
    PackedFloat64Array weights;
    if (_profiles.empty()) {
        out["indices"] = indices;
        out["weights"] = weights;
        return out;
    }

    double relief, moisture;
    sample_controls(world_x, world_z, relief, moisture);
    const double m = _blend_margin;

    // Membership of each kind, derived from how deep (relief,moisture) sits
    // inside that kind's region. We express each kind's region as the
    // intersection of the cascade conditions ABOVE it failing and its own
    // condition holding, and take the min-distance to the nearest active
    // boundary (standard soft-classification). Distances are in control
    // units (relief/moisture share the same [0,1] scale).
    struct KindMembership { int idx; double mem; };
    KindMembership ks[5];
    int kn = 0;

    // mountains: relief > 0.62
    if (_idx_mountains >= 0) {
        double d = relief - 0.62;
        ks[kn++] = {_idx_mountains, ramp01(d, m)};
    }
    // desert: relief <= 0.62 AND moisture < 0.33
    if (_idx_desert >= 0) {
        double d_relief = 0.62 - relief;       // inside if relief below 0.62
        double d_moist = 0.33 - moisture;      // inside if moisture below 0.33
        double d = std::min(d_relief, d_moist);
        ks[kn++] = {_idx_desert, ramp01(d, m)};
    }
    // plains: relief <= 0.62 AND moisture >= 0.33 AND relief < 0.30
    if (_idx_plains >= 0) {
        double d_relief_hi = 0.62 - relief;
        double d_moist = moisture - 0.33;
        double d_relief_lo = 0.30 - relief;    // inside if relief below 0.30
        double d = std::min(std::min(d_relief_hi, d_moist), d_relief_lo);
        ks[kn++] = {_idx_plains, ramp01(d, m)};
    }
    // forest: relief in [0.30,0.62] AND moisture > 0.62
    if (_idx_forest >= 0) {
        double d_relief_hi = 0.62 - relief;
        double d_relief_lo = relief - 0.30;
        double d_moist_lo = moisture - 0.62;   // inside if moisture above 0.62
        double d = std::min(std::min(d_relief_hi, d_relief_lo), d_moist_lo);
        ks[kn++] = {_idx_forest, ramp01(d, m)};
    }
    // hills: relief in [0.30,0.62] AND moisture in [0.33,0.62]
    if (_idx_hills >= 0) {
        double d_relief_hi = 0.62 - relief;
        double d_relief_lo = relief - 0.30;
        double d_moist_hi = 0.62 - moisture;
        double d_moist_lo = moisture - 0.33;
        double d = std::min(std::min(d_relief_hi, d_relief_lo),
                            std::min(d_moist_hi, d_moist_lo));
        ks[kn++] = {_idx_hills, ramp01(d, m)};
    }

    // If every membership collapsed to ~0 (a column sitting exactly on a
    // triple boundary), fall back to the hard classifier so the column is
    // never biome-less.
    double total = 0.0;
    for (int i = 0; i < kn; ++i) total += ks[i].mem;
    if (total < 1e-9) {
        int hard = classify_kind_index(relief, moisture);
        if (hard < 0) hard = 0;
        indices.push_back(hard);
        weights.push_back(1.0);
        out["indices"] = indices;
        out["weights"] = weights;
        return out;
    }

    // Keep the ≤3 largest. Sort by descending membership, then ascending
    // index for a stable total order (cross-language determinism).
    std::sort(ks, ks + kn, [](const KindMembership &a, const KindMembership &b) {
        if (a.mem != b.mem) return a.mem > b.mem;
        return a.idx < b.idx;
    });
    int keep = std::min(kn, 3);
    double kept_total = 0.0;
    for (int i = 0; i < keep; ++i) kept_total += ks[i].mem;
    if (kept_total < 1e-12) kept_total = 1.0;
    for (int i = 0; i < keep; ++i) {
        if (ks[i].mem <= 0.0) continue;
        indices.push_back(ks[i].idx);
        weights.push_back(ks[i].mem / kept_total);
    }
    // Renormalize after dropping zero-weight entries.
    double s = 0.0;
    for (int i = 0; i < weights.size(); ++i) s += weights[i];
    if (s > 1e-12) {
        for (int i = 0; i < weights.size(); ++i) weights[i] = weights[i] / s;
    }
    out["indices"] = indices;
    out["weights"] = weights;
    return out;
}

// ----- Parameter blending ------------------------------------------------

static BiomeProfilePOD blend_pods(const std::vector<BiomeProfilePOD> &profiles,
                                  const PackedInt32Array &indices,
                                  const PackedFloat64Array &weights) {
    BiomeProfilePOD b;
    // Zero everything we accumulate.
    b.base_amplitude_m = 0;
    b.base_frequency_per_m = 0;
    b.ridge_mix = 0;
    b.flatness = 0;
    b.terrace_band_m = 0;
    b.terrace_sharpness = 0;
    b.mid_amplitude_m = 0;
    b.detail_amplitude_m = 0;
    double detail_slope_factor = 0.0;  // bool → 0..1
    for (int i = 0; i < indices.size(); ++i) {
        const BiomeProfilePOD &p = profiles[indices[i]];
        const double w = weights[i];
        b.base_amplitude_m += p.base_amplitude_m * w;
        b.base_frequency_per_m += p.base_frequency_per_m * w;
        b.ridge_mix += p.ridge_mix * w;
        b.flatness += p.flatness * w;
        b.terrace_band_m += p.terrace_band_m * w;
        b.terrace_sharpness += p.terrace_sharpness * w;
        b.mid_amplitude_m += p.mid_amplitude_m * w;
        b.detail_amplitude_m += p.detail_amplitude_m * w;
        detail_slope_factor += (p.detail_slope_only ? 1.0 : 0.0) * w;
    }
    // detail_slope_only blends as a factor; treat >0.5 as "on" for the
    // discrete suppress decision but keep continuity by storing the factor
    // back into detail_amplitude_m later if desired. We keep the bool
    // semantics simple: store the factor in micro_relief_chance? No —
    // height_from_params reads detail_slope_only as bool, so threshold here.
    b.detail_slope_only = detail_slope_factor > 0.5;
    return b;
}

Dictionary BiomeFieldCpp::blended_height_params(int world_x, int world_z) const {
    Dictionary w = resolve_biome_weights(world_x, world_z);
    PackedInt32Array indices = w["indices"];
    PackedFloat64Array weights = w["weights"];
    BiomeProfilePOD b = blend_pods(_profiles, indices, weights);
    Dictionary out;
    out["base_amplitude_m"] = b.base_amplitude_m;
    out["base_frequency_per_m"] = b.base_frequency_per_m;
    out["ridge_mix"] = b.ridge_mix;
    out["flatness"] = b.flatness;
    out["terrace_band_m"] = b.terrace_band_m;
    out["terrace_sharpness"] = b.terrace_sharpness;
    out["mid_amplitude_m"] = b.mid_amplitude_m;
    out["detail_amplitude_m"] = b.detail_amplitude_m;
    out["detail_slope_only"] = b.detail_slope_only;
    return out;
}

// ----- Height from blended params ----------------------------------------
//
// The biome heightfield. Three octaves built from the SAME control noise
// (sampled at progressively higher per-metre frequencies), shaped by the
// blended biome params:
//   * macro: base_amplitude_m × shaped(base noise)
//       shaped() interpolates fBm-billow ↔ ridged crests by ridge_mix,
//       then applies the flatness plateau S-curve, then optional terraces.
//   * mid + detail: small high-freq layers (detail suppressed on flat
//     ground when detail_slope_only).
// Output is in WORLD METRES of elevation above sea level; the caller adds
// the sea-level offset and converts to voxels.

double BiomeFieldCpp::height_from_params(int world_x, int world_z,
                                         const BiomeProfilePOD &p) const {
    if (_control_noise.is_null()) {
        return 0.0;
    }
    const double mx = static_cast<double>(world_x) / _voxels_per_metre;
    const double mz = static_cast<double>(world_z) / _voxels_per_metre;

    // --- Macro octave ---
    const double bf = p.base_frequency_per_m;
    double n = static_cast<double>(_control_noise->get_noise_2d(mx * bf, mz * bf)); // [-1,1]

    // ridge_mix: 0 = billow/fBm (use n remapped to [0,1] keeps rolling),
    //            1 = ridged (1 - |n|, sharp crests). Lerp the two SHAPES.
    const double billow = n * 0.5 + 0.5;        // [0,1], smooth hills
    const double ridged = 1.0 - std::fabs(n);   // [0,1], sharp peaks at |n|=0
    double h01 = billow + (ridged - billow) * std::clamp(p.ridge_mix, 0.0, 1.0);

    // flatness plateau: push mid-range values toward a plateau via a
    // symmetric S-curve around 0.5. flatness=0 leaves h01 unchanged;
    // flatness=1 hard-flattens everything but the extremes. We blend
    // h01 with smoothstep(h01) by `flatness` (smoothstep compresses the
    // mid-band → plateaus, expands the tails → preserves peaks/valleys).
    const double s = h01 * h01 * (3.0 - 2.0 * h01);  // smoothstep(h01)
    const double fl = std::clamp(p.flatness, 0.0, 1.0);
    h01 = h01 + (s - h01) * fl;

    // Map [0,1] to a signed half-range so sea level sits near the middle.
    double macro_m = (h01 - 0.5) * 2.0 * p.base_amplitude_m;

    // terraces: quantize elevation into bands with rounded lips. band=0
    // disables. Within each band, lerp between the hard step (sharpness=1)
    // and the smooth original (sharpness=0).
    if (p.terrace_band_m > 1e-4) {
        const double band = p.terrace_band_m;
        const double q = std::floor(macro_m / band);  // band index
        const double frac = macro_m / band - q;        // 0..1 within band
        // Rounded lip: smoothstep the fraction so the step has a soft edge.
        const double lip = frac * frac * (3.0 - 2.0 * frac);
        const double stepped = (q + lip) * band;
        const double sh = std::clamp(p.terrace_sharpness, 0.0, 1.0);
        macro_m = macro_m + (stepped - macro_m) * sh;
    }

    double height_m = macro_m;

    // --- Mid + detail octaves ---
    // Frequencies are ratios of the macro frequency, mirroring the cubic
    // generator's mid×3 / detail×12 layering but in per-metre space.
    const double mid_n = static_cast<double>(_control_noise->get_noise_2d(mx * bf * 3.0, mz * bf * 3.0));
    height_m += mid_n * p.mid_amplitude_m;

    // detail_slope_only: suppress the fine layer where the macro field is
    // near-flat (|local gradient| small). Cheap proxy for slope: compare
    // the macro value to a nudged neighbour.
    bool emit_detail = true;
    if (p.detail_slope_only) {
        const double eps = 1.0;  // 1 metre probe
        const double nn = static_cast<double>(_control_noise->get_noise_2d(
                (mx + eps) * bf, mz * bf));
        const double slope = std::fabs((nn - n)) * p.base_amplitude_m;  // ~metres / metre
        emit_detail = slope > 0.15;  // only on visibly sloped ground
    }
    if (emit_detail) {
        const double det_n = static_cast<double>(_control_noise->get_noise_2d(mx * bf * 12.0, mz * bf * 12.0));
        height_m += det_n * p.detail_amplitude_m;
    }
    return height_m;
}

int BiomeFieldCpp::compute_ground_y(int world_x, int world_z) const {
    Dictionary w = resolve_biome_weights(world_x, world_z);
    PackedInt32Array indices = w["indices"];
    PackedFloat64Array weights = w["weights"];
    if (indices.size() == 0) {
        return 0;
    }
    BiomeProfilePOD b = blend_pods(_profiles, indices, weights);
    const double height_m = height_from_params(world_x, world_z, b);
    // metres of elevation → voxels. The generator adds sea-level offset;
    // here we return voxel-Y RELATIVE to sea level (the caller offsets).
    return static_cast<int>(std::floor(height_m * _voxels_per_metre));
}

// ----- Surface biome pick (weighted hash) --------------------------------

int BiomeFieldCpp::pick_surface_biome(int world_x, int world_z) const {
    Dictionary w = resolve_biome_weights(world_x, world_z);
    PackedInt32Array indices = w["indices"];
    PackedFloat64Array weights = w["weights"];
    if (indices.size() == 0) return -1;
    if (indices.size() == 1) return indices[0];
    // Deterministic per-(x,z) roll in [0,1); walk the cumulative weights.
    const double roll = math::hash3(world_x, 7, world_z, 0xB10E);  // salt "BIOE"
    double acc = 0.0;
    for (int i = 0; i < indices.size(); ++i) {
        acc += weights[i];
        if (roll < acc) return indices[i];
    }
    return indices[indices.size() - 1];
}

int BiomeFieldCpp::dominant_biome(int world_x, int world_z) const {
    Dictionary w = resolve_biome_weights(world_x, world_z);
    PackedInt32Array indices = w["indices"];
    if (indices.size() == 0) return -1;
    return indices[0];  // resolver sorts by descending weight
}

// ----- ClassDB -----------------------------------------------------------

void BiomeFieldCpp::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_biome_profiles", "list"), &BiomeFieldCpp::set_biome_profiles);
    ClassDB::bind_method(D_METHOD("get_biome_profile_count"), &BiomeFieldCpp::get_biome_profile_count);
    ClassDB::bind_method(D_METHOD("set_biome_field_params",
                                  "control_frequency_per_m", "warp_frequency_per_m",
                                  "warp_strength", "blend_margin", "voxels_per_metre",
                                  "plains_index", "hills_index", "forest_index",
                                  "desert_index", "mountains_index"),
                         &BiomeFieldCpp::set_biome_field_params);
    ClassDB::bind_method(D_METHOD("set_control_noise", "noise"), &BiomeFieldCpp::set_control_noise);
    ClassDB::bind_method(D_METHOD("get_control_noise"), &BiomeFieldCpp::get_control_noise);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "control_noise", PROPERTY_HINT_RESOURCE_TYPE, "FastNoiseLite"),
                 "set_control_noise", "get_control_noise");

    ClassDB::bind_method(D_METHOD("resolve_biome_weights", "world_x", "world_z"),
                         &BiomeFieldCpp::resolve_biome_weights);
    ClassDB::bind_method(D_METHOD("blended_height_params", "world_x", "world_z"),
                         &BiomeFieldCpp::blended_height_params);
    ClassDB::bind_method(D_METHOD("compute_ground_y", "world_x", "world_z"),
                         &BiomeFieldCpp::compute_ground_y);
    ClassDB::bind_method(D_METHOD("pick_surface_biome", "world_x", "world_z"),
                         &BiomeFieldCpp::pick_surface_biome);
    ClassDB::bind_method(D_METHOD("dominant_biome", "world_x", "world_z"),
                         &BiomeFieldCpp::dominant_biome);
}

}  // namespace voxel_gen
