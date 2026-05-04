@tool
extends VoxelGeneratorScript
# WorldGenerator — procedural terrain generator for the open world of Mira.
#
# This script feeds Zylann's Voxel Tools plugin (godot_voxel). It is attached
# to a `VoxelLodTerrain` node and called automatically whenever the terrain
# needs to fill in a new chunk of the world (i.e. as Roland walks around).
#
# REQUIRES: Zylann's Voxel Tools plugin installed and enabled. Without it,
# `VoxelGeneratorScript` does not exist and this script will not parse.
# Install via Godot's AssetLib (search "Zylann Voxel Tools") then enable
# in Project Settings → Plugins.
#
# The generator's job is simple in shape: for every (x, z) column in a chunk,
# decide a "surface height" — the y value where solid ground stops and air
# begins. Below that y is rock, above it is sky. The rest of the world's
# personality (mountains, valleys, plains, settlement flats) all comes from
# how we compute that one number.
#
# Reference: design/ART_PIPELINE.md → Tool 2
#            design/3D_VOXEL_MIGRATION.md
#            CLAUDE.md → World coordinate reference (settlement coords)
#
# COORDINATE SYSTEM
# - World is 12,000 m east-west (x axis) by 10,000 m north-south (z axis).
# - Origin (0, 0, 0) is the NW corner of the playable map.
# - +x runs east, +z runs south, +y is up (Godot standard).
# - Sea level / valley floor is around y = 30. Spine peaks reach y ~280.


# ─────────────────────────────────────────────────────────────────────────
#  Tunables — exported so a designer can tweak from the inspector
# ─────────────────────────────────────────────────────────────────────────

@export_group("Elevation")

@export var sea_level: int = 30
# The "default" ground height anywhere there's no biome influence pushing
# it up or down. Most of the central lowlands sit a bit above this.

@export var spine_peak_height: int = 280
# Highest point of the Spine of Mira (the eastern mountain range). The
# actual y a peak hits depends on noise — this is the cap.

@export var spine_min_height: int = 90
# Foothill height at the edges of the Spine zone. Below this we're back
# in lowlands.

@export var greatwood_height: int = 45
# Greatwood (northern forest) sits slightly higher than the central plain
# but isn't mountainous. Gentle rolling.

@export var aldwater_floor: int = 22
# Aldwater valley floor — the lowest carved channel running east-west
# through the center of the map. Rivers (added in a later phase) will
# follow this line.

@export var ashfields_height: int = 35
# Ashfields east of the Spine: low, flat, dead. Slightly above sea level
# but very even.


@export_group("Spine Mountains")

@export var spine_x_min: float = 5000.0
@export var spine_x_max: float = 7000.0
# X range of the Spine mountain zone. Outside this band, no mountains.
# Inside it, elevation ramps up with distance from the edges.

@export var spine_falloff: float = 800.0
# How wide the transition is between "lowland" and "mountain". A larger
# value = gentler foothills; smaller = sharper cliffs at the range edge.


@export_group("Greatwood")

@export var greatwood_z_min: float = 0.0
@export var greatwood_z_max: float = 2500.0
# Z range of the Greatwood. Northern band of the map.


@export_group("Aldwater Valley")

@export var aldwater_z_center: float = 4500.0
# Z position of the carved valley channel.

@export var aldwater_width: float = 600.0
# How wide the valley is. Inside this band the ground dips down.


@export_group("Ashfields")

@export var ashfields_x_min: float = 7000.0
# East of the Spine = Ashfields. They run all the way to the east edge.


@export_group("Noise")

@export var base_noise_frequency: float = 0.0008
# Frequency of the large-scale terrain noise. Smaller = bigger features
# (continent-wide rolls). Larger = noisier, hill-by-hill variation.

@export var detail_noise_frequency: float = 0.008
# Frequency of small bumps layered on top of the base shape. Adds the
# "natural unevenness" that keeps slopes from looking like a smooth ramp.

@export var detail_noise_amplitude: float = 4.0
# How tall those small bumps are, in voxels.

@export var noise_seed: int = 1911
# Seed for the noise generators. Same seed = same Mira every time.
# Change this only if you want a totally different world.


@export_group("Settlements")

@export var settlement_flatten_radius: float = 90.0
# Within this many metres of a settlement coordinate, force the ground
# perfectly flat. Buildings need flat ground or they sink/float on slopes.

@export var settlement_blend_radius: float = 140.0
# Between flatten_radius and blend_radius, smoothly tween from the
# flattened settlement height to the surrounding natural terrain.
# Without this we'd get ugly cliffs at the edge of every village.


# ─────────────────────────────────────────────────────────────────────────
#  Internal state
# ─────────────────────────────────────────────────────────────────────────

var _base_noise: FastNoiseLite
# Big rolling shape — used to break up otherwise-flat biome heights.

var _detail_noise: FastNoiseLite
# Small jitter layered on top. Keeps cliffs and ridges from looking
# mathematically perfect.

# Settlement coordinates from CLAUDE.md → World coordinate reference.
# Each entry is (x, z, ground_y) — the third number is the height the
# ground is forced to inside the flatten radius.
const SETTLEMENT_FLATS: Array = [
	# Caer Brannoch — Eldermark seat, valley
	{ "x": 880.0, "z": 2200.0, "y": 38 },
	# Lirien-Thal — Aen-Vael city, slightly raised
	{ "x": 1950.0, "z": 2800.0, "y": 42 },
	# Karaz-Dûn — dwarven hold at base of Spine
	{ "x": 5200.0, "z": 2300.0, "y": 95 },
	# Aldenholt — south-central village
	{ "x": 4400.0, "z": 5800.0, "y": 36 },
	# Brightwatch — Spine foothill watchtower
	{ "x": 5200.0, "z": 4600.0, "y": 110 },
	# Khorumzad — major dwarven city, mid-Spine
	{ "x": 5200.0, "z": 5800.0, "y": 130 },
	# Solgrade — southern town
	{ "x": 4000.0, "z": 7400.0, "y": 38 },
	# Kazaad-Brak — far south dwarven settlement
	{ "x": 5200.0, "z": 9000.0, "y": 90 },
	# Mor-Vethrin — Ashfields outpost (east of Spine)
	{ "x": 6700.0, "z": 2200.0, "y": 40 },
]


# ─────────────────────────────────────────────────────────────────────────
#  Setup
# ─────────────────────────────────────────────────────────────────────────

func _init() -> void:
	# Initialise the two noise generators. We use two so big and small
	# features can be tuned independently without one drowning out the other.
	_base_noise = FastNoiseLite.new()
	_base_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_base_noise.seed = noise_seed
	_base_noise.frequency = base_noise_frequency

	_detail_noise = FastNoiseLite.new()
	_detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail_noise.seed = noise_seed + 1  # different seed = different pattern
	_detail_noise.frequency = detail_noise_frequency


# ─────────────────────────────────────────────────────────────────────────
#  Plugin entry point — called by VoxelLodTerrain
# ─────────────────────────────────────────────────────────────────────────

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# This is the function the voxel plugin calls whenever it needs a chunk.
	# `origin_in_voxels` is the world-space corner of the chunk (in voxels,
	# which at LOD 0 equals metres). `lod` tells us what detail level the
	# plugin wants — for a height-based generator we can ignore it for now.
	var size_x: int = out_buffer.get_size_x()
	var size_y: int = out_buffer.get_size_y()
	var size_z: int = out_buffer.get_size_z()

	# Voxel step in world space. At LOD 0 this is 1 metre. At LOD 1 each
	# voxel covers 2 m, at LOD 2 it covers 4 m, etc. We multiply x/z by
	# this to look up the right point on our height field.
	var step: int = 1 << lod  # 2 ^ lod

	for z_local in range(size_z):
		for x_local in range(size_x):
			var wx: float = float(origin_in_voxels.x + x_local * step)
			var wz: float = float(origin_in_voxels.z + z_local * step)
			var surface_y: int = _get_surface_height(wx, wz)

			for y_local in range(size_y):
				var wy: int = origin_in_voxels.y + y_local * step
				if wy < surface_y:
					# Below surface = solid rock (voxel ID 1).
					out_buffer.set_voxel(1, x_local, y_local, z_local, 0)
				else:
					# Above surface = air (voxel ID 0). The plugin
					# defaults to air, so this line is technically optional,
					# but being explicit is clearer.
					out_buffer.set_voxel(0, x_local, y_local, z_local, 0)


# ─────────────────────────────────────────────────────────────────────────
#  Height field — the heart of the generator
# ─────────────────────────────────────────────────────────────────────────

func _get_surface_height(wx: float, wz: float) -> int:
	# Combine: biome base height + noise variation + settlement flattening.
	# Settlement flattening runs LAST so it can override everything else.

	var biome_height: float = _biome_base_height(wx, wz)
	var noise_offset: float = _noise_height_offset(wx, wz)
	var natural_height: float = biome_height + noise_offset

	# Check settlements last — they win.
	var settlement_height: float = _settlement_override(wx, wz, natural_height)

	return int(round(settlement_height))


func _biome_base_height(wx: float, wz: float) -> float:
	# Decide the base height for this column based on which biome it falls
	# in. Biomes blend at their edges so we never get sudden walls.

	# Start with the central lowland default.
	var height: float = float(sea_level)

	# Aldwater valley — carved channel through the center, so subtract first.
	# (We do this before adding mountains so the valley still appears even
	# when it cuts under the Spine's western foothills.)
	var dist_from_valley: float = abs(wz - aldwater_z_center)
	if dist_from_valley < aldwater_width:
		# Inside the valley: blend toward the valley floor.
		# weight = 1 at center, 0 at the edge.
		var weight: float = 1.0 - (dist_from_valley / aldwater_width)
		height = lerp(height, float(aldwater_floor), weight)

	# Greatwood — gentle rise in the north band.
	if wz >= greatwood_z_min and wz <= greatwood_z_max:
		# Soft blend toward greatwood_height across the band.
		var dz: float = (wz - greatwood_z_min) / (greatwood_z_max - greatwood_z_min)
		# Smoothstep so the boundary at z=2500 isn't sharp.
		var weight: float = _smoothstep(0.0, 1.0, 1.0 - dz)
		height = lerp(height, float(greatwood_height), weight * 0.6)

	# Spine of Mira — eastern mountain range. This is the dominant feature.
	var spine_weight: float = _spine_weight(wx)
	if spine_weight > 0.0:
		# Mountains are taller toward the center of the range.
		# We use a separate noise value here as a "ridge map" so the
		# Spine isn't a uniform wall — it has peaks and saddles.
		var ridge: float = _base_noise.get_noise_2d(wx * 0.6, wz * 0.6)
		# ridge is roughly -1..+1; remap to 0..1.
		ridge = (ridge + 1.0) * 0.5
		var mountain_target: float = lerp(
			float(spine_min_height),
			float(spine_peak_height),
			ridge
		)
		height = lerp(height, mountain_target, spine_weight)

	# Ashfields — flat dead plain east of the Spine.
	if wx >= ashfields_x_min:
		# How far east of the Spine ridge are we? Blend in over ~500m
		# so the transition off the eastern foothills isn't a step.
		var ash_blend: float = clamp((wx - ashfields_x_min) / 500.0, 0.0, 1.0)
		height = lerp(height, float(ashfields_height), ash_blend)

	return height


func _spine_weight(wx: float) -> float:
	# Return 0..1 indicating how "in the Spine" this column is.
	# 0 = lowlands, 1 = full mountain. Smooth ramp at edges.

	if wx < spine_x_min - spine_falloff:
		return 0.0
	if wx > spine_x_max + spine_falloff:
		return 0.0

	# West edge ramp.
	if wx < spine_x_min:
		return _smoothstep(spine_x_min - spine_falloff, spine_x_min, wx)
	# East edge ramp.
	if wx > spine_x_max:
		return 1.0 - _smoothstep(spine_x_max, spine_x_max + spine_falloff, wx)
	# Inside the range = full weight.
	return 1.0


func _noise_height_offset(wx: float, wz: float) -> float:
	# Layered noise giving organic unevenness. Two octaves: the base
	# noise gives broad rolls (10s of metres of sway) and the detail
	# noise adds metre-scale jitter so slopes don't look like ramps.
	var base_n: float = _base_noise.get_noise_2d(wx, wz)
	var detail_n: float = _detail_noise.get_noise_2d(wx, wz)
	# Both noise values come back in the range -1..+1.
	# Base: ±20m of broad variation. Detail: ±detail_noise_amplitude.
	return (base_n * 20.0) + (detail_n * detail_noise_amplitude)


func _settlement_override(wx: float, wz: float, natural_height: float) -> float:
	# Walk the settlement list. If we're inside the flatten radius of any
	# settlement, force the height. If we're between flatten and blend,
	# tween smoothly to natural terrain.
	for entry in SETTLEMENT_FLATS:
		var sx: float = entry["x"]
		var sz: float = entry["z"]
		var sy: float = float(entry["y"])
		var dist: float = sqrt((wx - sx) * (wx - sx) + (wz - sz) * (wz - sz))

		if dist <= settlement_flatten_radius:
			# Fully inside the settlement footprint — forced flat.
			return sy
		elif dist <= settlement_blend_radius:
			# In the blend ring — interpolate from settlement height
			# back to natural terrain. weight = 1 at outer edge, 0 at inner.
			var t: float = (dist - settlement_flatten_radius) \
				/ (settlement_blend_radius - settlement_flatten_radius)
			return lerp(sy, natural_height, t)

	# Not near any settlement — return the natural shape unchanged.
	return natural_height


# ─────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	# Standard smoothstep curve. Returns 0..1 with smooth tangents at
	# both ends — a much nicer ramp than a linear lerp for terrain edges.
	var t: float = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
