@tool
extends VoxelGeneratorScript
class_name CubicHeightmapGenerator

# CubicHeightmapGenerator — fills the COLOR channel so VoxelMesherCubes
# can render the world as hard-edged colored cubes.
#
# What this does in plain English:
#
#   For every voxel block the engine asks us to fill, we walk a 2D
#   grid (X, Z) at the block's world position, sample 2D noise to get
#   a ground height, then for every Y in the block:
#       - if Y <= ground_height → write a packed RGBA color into
#         CHANNEL_COLOR (visible solid cube)
#       - if Y >  ground_height → leave default 0 (air, transparent,
#         no cube emitted)
#
#   Color shifts subtly with altitude — peaks paler than valleys —
#   so the cubic terrain reads as terrain rather than a uniform
#   slab of one color.
#
# Why CHANNEL_COLOR and not CHANNEL_TYPE?
#
#   VoxelMesherCubes determines "is this voxel solid?" by reading the
#   COLOR channel: alpha=0 means air, alpha>0 means a solid cube of
#   that RGBA. Writing TYPE doesn't help Cubes — that channel is for
#   VoxelMesherBlocky (which uses a per-type model library).
#
#   Earlier versions of this script wrote TYPE and threw thousands
#   of "Central buffer must be valid" errors at world load because
#   the COLOR channel was never populated. The fix is to write COLOR.
#
# Coordinates:
#
#   - origin_in_voxels and the inner X/Y/Z indices are in voxel-grid
#     space (1 voxel = 1 grid unit). The VoxelLodTerrain node's
#     transform scale (locked at 0.166667 = 1/6) maps voxel-grid coords →
#     world-space metres at render time. This script does NOT need
#     to know about world scale.
#   - LOD: at LOD 0 we sample one grid unit per voxel. At higher
#     LODs each voxel covers (1 << lod) grid units, so we step the
#     noise by that stride.

# =============================================================
# PRESETS — quick-apply tuning bundles for live iteration
# =============================================================
#
# Iteration loop with the designer:
#   1. Run World3D.tscn (F5)
#   2. In the running scene tree, find VoxelLodTerrain → generator
#   3. Pick a preset from the dropdown to A/B between bundled looks,
#      OR drag the @export_range sliders below to fine-tune one
#      parameter at a time
#   4. Walk around → terrain chunks not yet streamed will use new
#      params; force a refresh by walking far enough to unload then
#      back in
#   5. When a setting feels right, tell Claude the values and we'll
#      bake them into a named preset
#
# Add new presets to the PRESETS dict; the enum + dropdown updates
# automatically.

enum Preset {
	CUSTOM,
	MOUNTAIN_VALLEY,
	LAY_OF_THE_LAND,
	MINECRAFT_BLOCKY,
	SMOOTH_GRADIENT,
}

# All voxel-amplitude values are in the project's locked 6 vox/m grid.
# Physical metre conversion: voxels / 6 = metres.
const PRESETS: Dictionary = {
	Preset.MOUNTAIN_VALLEY: {
		"height_range_voxels": 900.0,           # 150 m peak-to-trough — real mountains
		"height_offset_voxels": 60,             # +10 m bias above sea level
		"mid_amplitude_voxels": 10,             # ±1.7 m gentle undulation (was 24, too rocky)
		"mid_frequency_multiplier": 3.0,        # wider mid features for smoother slopes
		"detail_amplitude_voxels": 2,           # ±0.33 m surface grain (was 6, too noisy)
		"detail_frequency_multiplier": 12.0,    # smoother detail
		"color_jitter": 0.10,                   # cleaner colour, less per-cube noise
		"quantize_to_meters": false,
	},
	Preset.LAY_OF_THE_LAND: {
		"color_jitter": 0.25,
		"mid_amplitude_voxels": 12,             # ±2 m
		"mid_frequency_multiplier": 8.0,
		"detail_amplitude_voxels": 3,           # ±0.5 m
		"detail_frequency_multiplier": 30.0,
		"quantize_to_meters": false,
	},
	Preset.MINECRAFT_BLOCKY: {
		"color_jitter": 0.05,
		"mid_amplitude_voxels": 0,
		"detail_amplitude_voxels": 0,
		"quantize_to_meters": true,
	},
	Preset.SMOOTH_GRADIENT: {
		"color_jitter": 0.05,
		"mid_amplitude_voxels": 3,              # ±0.5 m
		"mid_frequency_multiplier": 6.0,
		"detail_amplitude_voxels": 0,
		"quantize_to_meters": false,
	},
}

# Re-entrancy guard so applying a preset's params doesn't recursively
# trigger the preset setter while it's writing them. Without it,
# selecting a preset would fight itself as each `set(key, ...)` call
# re-invoked the preset setter.
var _applying_preset: bool = false

## Quick-apply tuning bundle for the rest of the parameters below.
## Selecting any value other than CUSTOM batch-writes that bundle's
## values into the other sliders, then snaps back to CUSTOM so the
## dropdown signals "you're now in custom-tuned territory."
@export var preset: Preset = Preset.CUSTOM:
	set(value):
		preset = value
		if _applying_preset:
			return
		if value != Preset.CUSTOM and PRESETS.has(value):
			_applying_preset = true
			for key in PRESETS[value]:
				set(key, PRESETS[value][key])
			# Reset to CUSTOM after applying so the dropdown shows
			# "you're now in custom-tuned mode" rather than implying
			# the params still match the preset (which they may not
			# after subsequent manual tweaks).
			preset = Preset.CUSTOM
			_applying_preset = false


# =============================================================
# CORE PARAMETERS — tunable in the Inspector while the scene runs
# =============================================================

## FastNoiseLite resource that drives all three height layers (macro,
## mid, detail) at different frequency multiples. Tweak this resource's
## own properties (Type, Octaves, Frequency, Lacunarity) to change the
## underlying terrain character — ridged vs simplex, fewer/more octaves,
## etc. Lower frequency = bigger horizontal features.
@export var noise: FastNoiseLite

## Total vertical relief from the macro noise layer, in VOXELS
## (6 voxels = 1 m). Bigger = taller mountains. Default 900 = ±75 m
## macro relief = 150 m peak-to-trough. With wide noise frequency
## (set on the FastNoiseLite resource), the slope between peak and
## valley spans hundreds of metres horizontally — slow, gradual
## elevation changes rather than sharp climbs.
@export_range(0.0, 2000.0, 1.0) var height_range_voxels: float = 900.0

## Vertical shift applied to every column AFTER the noise. Positive
## pushes terrain UP (above sea level); negative pushes DOWN. Default
## +60 voxels (+10 m) keeps the average ground above the ocean
## (surface_y=8 m) while letting low ground dip below for valley
## lakes and rivers.
@export_range(-300, 400, 1) var height_offset_voxels: int = 60

## When ON, terrain heights snap to integer-metre (6-voxel) steps —
## Minecraft-style terraces with hard 1 m cliffs. When OFF (default),
## noise stays continuous and slopes are stair-stepped voxel-by-voxel.
@export var quantize_to_meters: bool = false

## Mid-scale layer amplitude in voxels (6 vox = 1 m). Default 10
## = ±1.7 m gentle undulation on the macro silhouette. Push higher
## (24+) for a rockier, broken-rock-face surface; lower (3-4) for
## clean grass/snow slopes. Set 0 for pure macro slopes.
@export_range(0, 96, 1) var mid_amplitude_voxels: int = 10

## How tight the mid-scale features are, as a multiple of macro
## noise frequency. Higher = tighter wavy ground (lots of small humps);
## lower = wider rolling features. Default 3.0 = wide rolling humps
## that don't fight the slow macro slopes.
@export_range(1.0, 20.0, 0.5) var mid_frequency_multiplier: float = 3.0

## Cube-by-cube surface grain amplitude in voxels. Default 2 = ±0.33 m
## subtle wobble. Adds just enough texture so flat tops aren't dead-flat.
## Set to 0 for fully clean slopes; push higher (5-8) for visible grit.
@export_range(0, 24, 1) var detail_amplitude_voxels: int = 2

## How fast the cube-by-cube grain varies, as a multiple of macro
## noise frequency. Higher = each adjacent cube very different from
## its neighbour (gritty); lower = grain blends smoothly across cubes.
## Default 12× = grain visible but smooth across multiple cubes.
@export_range(1.0, 80.0, 0.5) var detail_frequency_multiplier: float = 12.0

## Per-voxel brightness variation as ± fraction of base colour. 0.10
## = ±10 % brightness — clean look that lets the macro silhouette
## breathe. Push to 0.20+ for stronger Lay-of-the-Land contrast; drop
## to 0.05 for uniform colour per height.
@export_range(0.0, 0.5, 0.01) var color_jitter: float = 0.10

## Reference voxel-Y for "ocean surface". Currently informational only
## — actual water elevation lives on `OceanVolume.surface_y` in
## `World3D.tscn` (default Y=8). Kept here for future generator-side
## logic (e.g. forced sand colour at coastline).
@export var sea_level_voxels: int = 0

## Colour of the LOWEST ground voxels (deep valleys, beach floor).
## LEGACY — used only as a fallback when the VoxelMaterialRegistry
## autoload isn't available (e.g. running this script in isolation
## for a unit test). In normal play, per-material colours come from
## the .tres files in `assets/voxels/materials/`.
@export var color_low: Color = Color(0.30, 0.42, 0.18)

## Colour of the HIGHEST ground voxels (ridge peaks). LEGACY — see
## `color_low` above. The active per-material colour pipeline lives
## in the .tres files; designers tune those, not these sliders.
@export var color_high: Color = Color(0.62, 0.55, 0.42)


# =============================================================
# MATERIAL BANDS — which material lives at which depth
# =============================================================
#
# The world is split into vertical bands measured DOWN from each
# column's ground_y. The top voxel is grass (or sand at coastlines),
# the next few voxels are dirt, and everything below is stone.
# Designers can re-tune these without touching code.

## Number of voxels at the very top of each ground column that are
## grass (the green skin). Default 1 — a single voxel of green over
## the dirt. Set to 0 to remove grass entirely (e.g. a desert preset).
@export_range(0, 5, 1) var grass_layer_thickness_voxels: int = 1

## Voxels of dirt directly below the grass layer. Default 3
## (~50 cm of soil before stone). The chunkier the world, the
## thicker this layer should feel relative to the player.
@export_range(0, 12, 1) var dirt_layer_thickness_voxels: int = 3

## At or below this voxel-Y, the top layer of the column is sand
## instead of grass. Roughly the OceanVolume.surface_y plus a
## small margin to give beaches their characteristic strip above
## the waterline. Default 7 ≈ 1 voxel above the test ocean's
## surface_y of 8 (-1 below it for the tide line).
@export var beach_y_threshold: int = 7


# =============================================================
# RUNTIME CACHE — material references, looked up once
# =============================================================
#
# `_generate_block` runs on Zylann's worker threads, so we don't
# want to do a registry lookup per voxel (or even per chunk). We
# fetch the four pilot materials lazily on first call and cache
# the references. Writes to these member vars are idempotent
# (same VoxelMaterial reference every time) so race conditions
# between worker threads doing the same lookup are harmless.

var _cached_stone: VoxelMaterial = null
var _cached_dirt: VoxelMaterial = null
var _cached_grass: VoxelMaterial = null
var _cached_sand: VoxelMaterial = null
var _materials_lookup_attempted: bool = false


func _get_used_channels_mask() -> int:
	# CRITICAL — without this override, Zylann assumes the generator
	# writes only the default (SDF) channel and never allocates
	# CHANNEL_COLOR in the chunk buffer. The mesher then tries to
	# read an unallocated channel and throws "Central buffer must be
	# valid" — thousands of times, once per streamed chunk.
	#
	# Returning a bitmask of channels we write tells the engine which
	# channels to set up before calling _generate_block.
	return 1 << VoxelBuffer.CHANNEL_COLOR


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# Engine calls this for every chunk the player approaches. We
	# fill out_buffer with COLOR values for that chunk.
	#
	# Channel depth is set up by the engine based on
	# _get_used_channels_mask above — we don't need to call
	# set_channel_depth here. (Calling it from inside _generate_block
	# can race with the engine's internal allocation pipeline.)

	var size: Vector3i = out_buffer.get_size()
	var stride: int = 1 << lod  # 1 at LOD0, 2 at LOD1, etc.

	# Bound the heightmap range so we can skip blocks fully above or
	# fully below terrain without per-voxel work. Includes the bias
	# offset, the mid layer amplitude, and the detail amplitude so
	# the early-out test stays correct after all three layers stack.
	var extra_amplitude: int = mid_amplitude_voxels + detail_amplitude_voxels
	var max_ground_y: int = int(height_range_voxels * 0.5) + height_offset_voxels + extra_amplitude + 1
	var min_ground_y: int = -int(height_range_voxels * 0.5) + height_offset_voxels - extra_amplitude - 1
	var block_min_y: int = origin_in_voxels.y
	var block_max_y: int = origin_in_voxels.y + (size.y * stride) - 1

	if block_min_y > max_ground_y:
		# Entire block is above terrain — leave as air (default 0).
		return

	# Materials registered? (Lazy lookup; safe across worker threads
	# because writes are idempotent — every thread fetches the same
	# VoxelMaterial references.)
	_ensure_materials_cached()

	if block_max_y < min_ground_y:
		# Entire block is buried deep below terrain — fill solid with
		# stone. Player only sees these voxels if they dig deep enough
		# to expose them.
		var stone_packed: int = _pack_for_material(_cached_stone, _cached_stone.color_low if _cached_stone != null else color_low)
		out_buffer.fill(stone_packed, VoxelBuffer.CHANNEL_COLOR)
		return

	if noise == null:
		# Fall back to flat ground at Y=0 with a default color. Useful
		# for sanity-checking the channel wiring without noise.
		_fill_flat(out_buffer, origin_in_voxels, stride)
		return

	# Per-column heightmap pass.
	var half_range: float = height_range_voxels * 0.5
	for x in size.x:
		for z in size.z:
			var world_x: int = origin_in_voxels.x + x * stride
			var world_z: int = origin_in_voxels.z + z * stride

			# --- Macro height: wide-feature noise, optionally quantized
			#     to integer-metre (8-voxel) steps for terraced look. ---
			var n_macro: float = noise.get_noise_2d(float(world_x), float(world_z))
			var macro_y: int
			if quantize_to_meters:
				# roundi → terraces centred on integer metres rather
				# than always rounded down. Cliff transitions happen
				# at the half-metre crossings of the macro noise.
				var macro_meters: int = roundi(n_macro * half_range / 8.0)
				macro_y = macro_meters * 8
			else:
				macro_y = int(n_macro * half_range)

			# --- Mid height: 8-m-scale rolling hills layered on the
			#     macro silhouette. This is the layer that makes every
			#     metre of terrain visually interesting (paths winding
			#     over small humps, dips between trees) instead of
			#     long uniform slopes. ±2 m amplitude. ---
			var n_mid: float = noise.get_noise_2d(
				float(world_x) * mid_frequency_multiplier,
				float(world_z) * mid_frequency_multiplier,
			)
			var mid_y: int = int(n_mid * float(mid_amplitude_voxels))

			# --- Detail height: cube-by-cube high-frequency wobble.
			#     ±50 cm at ~1-2 m feature scale. Reuses the same
			#     noise resource sampled at higher frequency — the
			#     multiplier produces a different visit pattern over
			#     the noise field, so it de-correlates from macro/mid
			#     enough to look like independent variation. ---
			var n_detail: float = noise.get_noise_2d(
				float(world_x) * detail_frequency_multiplier,
				float(world_z) * detail_frequency_multiplier,
			)
			var detail_y: int = int(n_detail * float(detail_amplitude_voxels))

			var ground_y: int = macro_y + mid_y + detail_y + height_offset_voxels

			for y in size.y:
				var world_y: int = origin_in_voxels.y + y * stride
				if world_y > ground_y:
					continue

				# --- Decide which material this voxel is ---
				# Top layer = grass (or sand at coastlines), next few
				# voxels = dirt, everything below = stone. The bands
				# are measured down from this column's ground_y.
				var depth: int = ground_y - world_y  # 0 = top voxel
				var material: VoxelMaterial = _select_material_for_depth(depth, ground_y)

				# --- Compute colour from the chosen material ---
				# Each material has its own color_low → color_high
				# palette and per-voxel jitter. We lerp using the
				# voxel's height within the macro range (so cliff faces
				# of the same material still fade smoothly across
				# vertical extent rather than painting flat).
				var c: Color = _compute_voxel_color(material, world_x, world_y, world_z, half_range)

				# --- Pack and write ---
				# RGB from `c`, alpha byte = material_id. The mesher
				# only checks alpha != 0 for solid-vs-air, so the
				# alpha byte is free to encode our material lookup key.
				var packed: int = _pack_for_material(material, c)
				out_buffer.set_voxel(packed, x, y, z, VoxelBuffer.CHANNEL_COLOR)


func _fill_flat(out_buffer: VoxelBuffer, origin: Vector3i, stride: int) -> void:
	# Ground-truth fallback when no noise resource is configured.
	# Solid up to Y=0, air above. Used only for sanity-checking the
	# channel wiring without noise; not reached during normal play.
	_ensure_materials_cached()
	var size: Vector3i = out_buffer.get_size()
	var packed: int = _pack_for_material(_cached_dirt, _cached_dirt.color_low if _cached_dirt != null else color_low)
	for x in size.x:
		for z in size.z:
			for y in size.y:
				var world_y: int = origin.y + y * stride
				if world_y <= 0:
					out_buffer.set_voxel(packed, x, y, z, VoxelBuffer.CHANNEL_COLOR)


# =============================================================
# MATERIAL HELPERS — band selection, colour, and packing
# =============================================================

func _ensure_materials_cached() -> void:
	# Lazy first-call lookup of the four pilot materials by id_string.
	# Resources don't get _ready, so we can't wire this up at script
	# load time. Instead the first call to _generate_block triggers
	# the lookup; subsequent calls hit the cached references.
	#
	# Thread-safety: Zylann calls _generate_block from worker threads.
	# Multiple threads racing to populate the cache all write the same
	# values (same VoxelMaterial Resource references), so the race is
	# benign. GDScript property writes are individually atomic.
	if _materials_lookup_attempted:
		return
	# Autoload accessor — Godot synthesises a global from the autoload
	# name. Available from Resource scripts at runtime; in @tool /
	# editor context the autoload may not be present, in which case the
	# cache stays null and the legacy color_low/high path runs.
	var registry: Node = null
	if Engine.has_singleton("VoxelMaterialRegistry"):
		registry = Engine.get_singleton("VoxelMaterialRegistry")
	if registry == null:
		# Try the autoload accessor via the tree (works at runtime).
		var ml: SceneTree = Engine.get_main_loop() as SceneTree
		if ml != null and ml.root != null:
			registry = ml.root.get_node_or_null("VoxelMaterialRegistry")
	_materials_lookup_attempted = true
	if registry == null:
		# Editor / @tool context with no autoload available. Leave the
		# cache empty; the colour pipeline will fall back to the legacy
		# color_low/color_high sliders.
		return
	_cached_stone = registry.get_by_string("stone")
	_cached_dirt = registry.get_by_string("dirt")
	_cached_grass = registry.get_by_string("grass")
	_cached_sand = registry.get_by_string("sand")


func _select_material_for_depth(depth: int, ground_y: int) -> VoxelMaterial:
	# `depth` is "voxels below the ground_y of this column" — 0 = the
	# topmost voxel of the column, 1 = one below, etc.
	#
	# Bands (measured from the top down):
	#   0 to grass_layer_thickness_voxels-1 → top layer (grass or sand)
	#   next dirt_layer_thickness_voxels    → dirt
	#   below that                           → stone
	#
	# At low altitudes (ground_y at or below beach_y_threshold), the
	# top layer is sand instead of grass, producing beaches.
	#
	# If a material isn't loaded (registry missing or .tres file
	# absent), we fall through to the next-best option so the
	# generator still produces SOMETHING rather than air. The
	# fallback chain: top layer → grass/sand → dirt → stone.

	# Top layer.
	if depth < grass_layer_thickness_voxels:
		if ground_y <= beach_y_threshold:
			if _cached_sand != null:
				return _cached_sand
		else:
			if _cached_grass != null:
				return _cached_grass
		# Fall through if the top-layer material isn't loaded.

	# Dirt layer (also catches the fall-through from the top layer).
	if depth < grass_layer_thickness_voxels + dirt_layer_thickness_voxels:
		if _cached_dirt != null:
			return _cached_dirt

	# Everything else is stone.
	return _cached_stone


func _compute_voxel_color(
	material: VoxelMaterial,
	world_x: int,
	world_y: int,
	world_z: int,
	half_range: float,
) -> Color:
	# Lerp the material's colour palette by altitude, then apply
	# per-voxel jitter. Identical to the old per-voxel colour code,
	# but the palette comes from the material's .tres rather than
	# the global color_low/color_high sliders.
	var lo: Color = color_low
	var hi: Color = color_high
	var jitter_amount: float = color_jitter
	if material != null:
		lo = material.color_low
		hi = material.color_high
		jitter_amount = material.color_jitter

	var t: float = clamp(
		(float(world_y) + half_range - float(height_offset_voxels)) / height_range_voxels,
		0.0,
		1.0,
	)
	var c: Color = lo.lerp(hi, t)

	# Per-voxel deterministic colour jitter — same triple-prime hash
	# the original generator used. Breaks up uniform colour on flat
	# tops so individual cubes are visible.
	if jitter_amount > 0.0:
		var hash_val: int = ((world_x * 73856093) ^ (world_y * 19349663) ^ (world_z * 83492791)) & 0xFF
		var j: float = (float(hash_val) / 255.0 - 0.5) * jitter_amount
		c.r = clampf(c.r + j, 0.0, 1.0)
		c.g = clampf(c.g + j, 0.0, 1.0)
		c.b = clampf(c.b + j, 0.0, 1.0)
	return c


func _pack_for_material(material: VoxelMaterial, color: Color) -> int:
	# Build the packed RGBA32 voxel value with the material id in the
	# alpha byte. If material is null (registry not loaded), fall
	# through to a plain to_rgba32 — the voxel will be alpha=255
	# (legacy behaviour) and won't have a queryable material, but at
	# least it'll render. This is the editor-only / @tool fallback.
	if material == null:
		return color.to_rgba32()
	# Use the registry helper directly so the alpha-byte-as-id encoding
	# stays in one place.
	var registry: Node = null
	if Engine.has_singleton("VoxelMaterialRegistry"):
		registry = Engine.get_singleton("VoxelMaterialRegistry")
	if registry == null:
		var ml: SceneTree = Engine.get_main_loop() as SceneTree
		if ml != null and ml.root != null:
			registry = ml.root.get_node_or_null("VoxelMaterialRegistry")
	if registry == null:
		# Inline pack as fallback — same math as registry.pack_voxel.
		var packed: int = color.to_rgba32()
		return (packed & 0xFFFFFF00) | (material.material_id & 0xFF)
	return registry.pack_voxel(material.material_id, color)
