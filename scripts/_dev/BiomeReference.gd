@tool
extends Object
class_name _BiomeReferenceDoNotUse

# BiomeReference — pure GD reference for the C++ BiomeFieldCpp math. Used by
# the headless `biome` selector to validate resolve_biome_weights /
# blended_height_params / compute_ground_y / pick_surface_biome against the
# C++ port, exactly like GravityReference validates VoxelGravityCpp.
#
# EVERY function here mirrors biome_field.cpp line-for-line — the control
# sampling, the smoothstep ramp, the Whittaker cascade, the weight resolver,
# the param blend, and the height function. If you change one side you MUST
# change the other and re-run the `biome` gate (it is bit-eps-exact).
#
# All state is passed in by value (a FastNoiseLite ref + a profiles Array +
# field params) — no SceneTree, no autoload. class_name is a tagged
# do-not-use placeholder so the editor doesn't offer the type; the call site
# preloads by path.
#
# A "profile" here is the same plain Dictionary BiomeProfile.to_pod_dict()
# produces (and that the bootstrap forwards to C++). Field params are passed
# as a Dictionary with the same names as BiomeFieldCpp::set_biome_field_params.

const _HASH := preload("res://scripts/VoxelGenerationMath.gd")


# ===== Control-field sampling (mirror sample_controls) =====
static func sample_controls(noise: FastNoiseLite, world_x: int, world_z: int,
		fp: Dictionary) -> Array:
	# Returns [relief, moisture], both in [0,1].
	if noise == null:
		return [0.5, 0.5]
	var vpm: float = fp["voxels_per_metre"]
	var mx: float = float(world_x) / vpm
	var mz: float = float(world_z) / vpm
	var wf: float = fp["warp_frequency_per_m"]
	var wx: float = float(noise.get_noise_2d((mx + 1000.0) * wf, (mz - 1000.0) * wf))
	var wz: float = float(noise.get_noise_2d((mx - 2000.0) * wf, (mz + 2000.0) * wf))
	var ws: float = fp["warp_strength"]
	var sx: float = mx + wx * ws
	var sz: float = mz + wz * ws
	var cf: float = fp["control_frequency_per_m"]
	var r: float = float(noise.get_noise_2d(sx * cf, sz * cf))
	var relief: float = clampf(r * 0.5 + 0.5, 0.0, 1.0)
	var m: float = float(noise.get_noise_2d((sx + 31337.0) * cf, (sz - 24601.0) * cf))
	var moisture: float = clampf(m * 0.5 + 0.5, 0.0, 1.0)
	return [relief, moisture]


# ===== Whittaker classifier (mirror classify_kind_index) =====
static func classify_kind_index(relief: float, moisture: float, fp: Dictionary) -> int:
	if relief > 0.62:
		return int(fp["mountains_index"])
	if moisture < 0.33:
		return int(fp["desert_index"])
	if relief < 0.30:
		return int(fp["plains_index"])
	if moisture > 0.62:
		return int(fp["forest_index"])
	return int(fp["hills_index"])


# smoothstep ramp (mirror ramp01)
static func _ramp01(signed_dist: float, margin: float) -> float:
	var t: float = (signed_dist + margin) / (2.0 * margin)
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ===== Weight resolution (mirror resolve_biome_weights) =====
# Returns { "indices": Array[int], "weights": Array[float] }.
static func resolve_biome_weights(noise: FastNoiseLite, world_x: int, world_z: int,
		profiles: Array, fp: Dictionary) -> Dictionary:
	var indices: Array = []
	var weights: Array = []
	if profiles.is_empty():
		return {"indices": indices, "weights": weights}
	var rm: Array = sample_controls(noise, world_x, world_z, fp)
	var relief: float = rm[0]
	var moisture: float = rm[1]
	var m: float = maxf(float(fp["blend_margin"]), 1e-6)

	var idx_plains: int = int(fp["plains_index"])
	var idx_hills: int = int(fp["hills_index"])
	var idx_forest: int = int(fp["forest_index"])
	var idx_desert: int = int(fp["desert_index"])
	var idx_mountains: int = int(fp["mountains_index"])

	# [idx, membership] pairs, in the SAME order C++ pushes them.
	var ks: Array = []
	if idx_mountains >= 0:
		ks.append([idx_mountains, _ramp01(relief - 0.62, m)])
	if idx_desert >= 0:
		var d: float = minf(0.62 - relief, 0.33 - moisture)
		ks.append([idx_desert, _ramp01(d, m)])
	if idx_plains >= 0:
		var d2: float = minf(minf(0.62 - relief, moisture - 0.33), 0.30 - relief)
		ks.append([idx_plains, _ramp01(d2, m)])
	if idx_forest >= 0:
		var d3: float = minf(minf(0.62 - relief, relief - 0.30), moisture - 0.62)
		ks.append([idx_forest, _ramp01(d3, m)])
	if idx_hills >= 0:
		var d4: float = minf(minf(0.62 - relief, relief - 0.30), minf(0.62 - moisture, moisture - 0.33))
		ks.append([idx_hills, _ramp01(d4, m)])

	var total: float = 0.0
	for k in ks:
		total += k[1]
	if total < 1e-9:
		var hard: int = classify_kind_index(relief, moisture, fp)
		if hard < 0:
			hard = 0
		return {"indices": [hard], "weights": [1.0]}

	# Sort by descending membership then ascending index (total order).
	ks.sort_custom(func(a, b):
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[0] < b[0]
	)
	var keep: int = mini(ks.size(), 3)
	var kept_total: float = 0.0
	for i in range(keep):
		kept_total += ks[i][1]
	if kept_total < 1e-12:
		kept_total = 1.0
	for i in range(keep):
		if ks[i][1] <= 0.0:
			continue
		indices.append(ks[i][0])
		weights.append(ks[i][1] / kept_total)
	# Renormalize after dropping zero-weight entries.
	var s: float = 0.0
	for w in weights:
		s += w
	if s > 1e-12:
		for i in range(weights.size()):
			weights[i] = weights[i] / s
	return {"indices": indices, "weights": weights}


# ===== Param blend (mirror blend_pods) =====
# Returns a Dictionary of the blended heightfield scalars (+ detail_slope_only
# as a bool thresholded at >0.5).
static func blend_height_params(profiles: Array, indices: Array, weights: Array) -> Dictionary:
	var keys := ["base_amplitude_m", "base_frequency_per_m", "ridge_mix", "flatness",
		"terrace_band_m", "terrace_sharpness", "mid_amplitude_m", "detail_amplitude_m"]
	var b: Dictionary = {}
	for k in keys:
		b[k] = 0.0
	var slope_factor: float = 0.0
	for i in range(indices.size()):
		var p: Dictionary = profiles[indices[i]]
		var w: float = weights[i]
		for k in keys:
			b[k] += float(p[k]) * w
		slope_factor += (1.0 if bool(p["detail_slope_only"]) else 0.0) * w
	b["detail_slope_only"] = slope_factor > 0.5
	return b


# ===== Height from blended params (mirror height_from_params) =====
static func height_from_params(noise: FastNoiseLite, world_x: int, world_z: int,
		b: Dictionary, fp: Dictionary) -> float:
	if noise == null:
		return 0.0
	var vpm: float = fp["voxels_per_metre"]
	var mx: float = float(world_x) / vpm
	var mz: float = float(world_z) / vpm
	var bf: float = b["base_frequency_per_m"]
	var n: float = float(noise.get_noise_2d(mx * bf, mz * bf))

	var billow: float = n * 0.5 + 0.5
	var ridged: float = 1.0 - absf(n)
	var h01: float = billow + (ridged - billow) * clampf(b["ridge_mix"], 0.0, 1.0)

	var sm: float = h01 * h01 * (3.0 - 2.0 * h01)
	var fl: float = clampf(b["flatness"], 0.0, 1.0)
	h01 = h01 + (sm - h01) * fl

	var amp: float = b["base_amplitude_m"]
	var macro_m: float = (h01 - 0.5) * 2.0 * amp

	var band: float = b["terrace_band_m"]
	if band > 1e-4:
		var q: float = floor(macro_m / band)
		var frac: float = macro_m / band - q
		var lip: float = frac * frac * (3.0 - 2.0 * frac)
		var stepped: float = (q + lip) * band
		var sh: float = clampf(b["terrace_sharpness"], 0.0, 1.0)
		macro_m = macro_m + (stepped - macro_m) * sh

	var height_m: float = macro_m
	var mid_n: float = float(noise.get_noise_2d(mx * bf * 3.0, mz * bf * 3.0))
	height_m += mid_n * b["mid_amplitude_m"]

	var emit_detail: bool = true
	if bool(b["detail_slope_only"]):
		var eps: float = 1.0
		var nn: float = float(noise.get_noise_2d((mx + eps) * bf, mz * bf))
		var slope: float = absf(nn - n) * amp
		emit_detail = slope > 0.15
	if emit_detail:
		var det_n: float = float(noise.get_noise_2d(mx * bf * 12.0, mz * bf * 12.0))
		height_m += det_n * b["detail_amplitude_m"]
	return height_m


# ===== compute_ground_y (mirror compute_ground_y; sea-level offset is the
# generator's job, so the reference returns the RELATIVE voxel-Y like C++). =====
static func compute_ground_y_rel(noise: FastNoiseLite, world_x: int, world_z: int,
		profiles: Array, fp: Dictionary) -> int:
	var w: Dictionary = resolve_biome_weights(noise, world_x, world_z, profiles, fp)
	var indices: Array = w["indices"]
	var weights: Array = w["weights"]
	if indices.is_empty():
		return 0
	var b: Dictionary = blend_height_params(profiles, indices, weights)
	var height_m: float = height_from_params(noise, world_x, world_z, b, fp)
	return int(floor(height_m * float(fp["voxels_per_metre"])))


# ===== Surface pick (mirror pick_surface_biome) =====
static func pick_surface_biome(noise: FastNoiseLite, world_x: int, world_z: int,
		profiles: Array, fp: Dictionary) -> int:
	var w: Dictionary = resolve_biome_weights(noise, world_x, world_z, profiles, fp)
	var indices: Array = w["indices"]
	var weights: Array = w["weights"]
	if indices.is_empty():
		return -1
	if indices.size() == 1:
		return indices[0]
	var roll: float = _HASH.hash3(world_x, 7, world_z, 0xB10E)
	var acc: float = 0.0
	for i in range(indices.size()):
		acc += weights[i]
		if roll < acc:
			return indices[i]
	return indices[indices.size() - 1]
