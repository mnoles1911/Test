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
#     transform scale (currently 0.125) maps voxel-grid coords →
#     world-space metres at render time. This script does NOT need
#     to know about world scale.
#   - LOD: at LOD 0 we sample one grid unit per voxel. At higher
#     LODs each voxel covers (1 << lod) grid units, so we step the
#     noise by that stride.

@export var noise: FastNoiseLite
# 2D noise source. FastNoiseLite with fractal_type=RIDGED (2),
# 5 octaves, frequency ~0.002 gives wide, landscape-scale ridges
# and valleys. Lower frequency = bigger features.

@export var height_range_voxels: float = 240.0
# Total vertical relief in VOXEL units (not metres). At terrain scale
# 0.125, 240 voxels = 30 metres of relief in world space — meaningful
# hills relative to a 1.7 m player but not crushing walls. Pair with
# FastNoiseLite frequency ~0.002 on the noise resource for wide,
# landscape-scale ridges instead of tight bumps.

@export var height_offset_voxels: int = 80
# Vertical bias applied to every column AFTER the noise → height map.
# Without this, ground_y is centered on Y = 0, which means half the
# world spawns BELOW sea level (under water) and the player at Y=10
# stares at a flat ocean with terrain walls poking up around them.
# Default +80 voxels = +10 m biases terrain mostly above sea level:
# average ground sits around Y=10 m, valleys dip to Y=-5 m (flooded
# coastline), peaks rise to Y=+25 m (hills the player must climb).

@export var quantize_to_meters: bool = false
# When true, the macro noise is snapped to integer-metre (8-voxel)
# steps. Produces hard 1 m cliffs at the half-metre noise crossings.
# Off by default: with quantize on we got jumpable-but-choppy
# terraces with no smooth grading between them — opposite of the
# intended "cubic-but-smooth" look. With this off the noise stays
# continuous and adjacent voxel columns differ by 0-2 voxels, which
# reads as a natural sub-voxel staircase smoothing each slope.

@export var mid_amplitude_voxels: int = 16
# Mid-scale noise amplitude. ±16 voxels = ±2 m. Drives the "rolling
# hills" / "1-2 m undulation" layer that Lay-of-the-Land terrain
# uses to keep every metre of ground visually interesting (paths
# winding over small humps, dips between trees, etc) on top of the
# wide macro silhouette.

@export var mid_frequency_multiplier: float = 8.0
# Mid noise is sampled at 8× the macro noise frequency. With macro
# at ~0.002, mid sits around ~0.016 — features ~8 m wide, the
# right scale for "every few metres elevation changes."

@export var detail_amplitude_voxels: int = 4
# High-frequency detail amplitude. ±4 voxels = ±50 cm of surface
# grain layered on top of macro+mid. Breaks up perfectly flat
# stretches into textured surface.

@export var detail_frequency_multiplier: float = 30.0
# Detail noise is sampled at 30× macro frequency — features ~1-2 m
# wide. Pushed up from 4.5× so detail varies cube-by-cube rather
# than smooth-blending across the metre with mid noise.

@export var color_jitter: float = 0.25
# Per-voxel deterministic colour jitter applied as ± this fraction
# of brightness. Without strong jitter, voxels at the same height
# share a colour and the sub-voxel grid disappears into a smooth
# slab. 0.25 = ±25 % brightness — matches the contrasty per-cube
# look of reference cubic-voxel games like Lay of the Land. Set
# to 0 to disable; drop toward 0.10 for a softer, more uniform look.

@export var sea_level_voxels: int = 0
# Voxel-Y coordinate that should correspond to "ocean surface".
# Ground at or below this Y is submerged when the OceanVolume Area3D
# sits at world Y = 0.

@export var color_low: Color = Color(0.30, 0.42, 0.18)
# Color of the lowest ground voxels (deep valleys, beach floor).
# Mossy green-brown by default.

@export var color_high: Color = Color(0.62, 0.55, 0.42)
# Color of the highest ground voxels (ridge peaks). Pale stone-brown
# by default. The generator lerps between low and high based on
# voxel-Y / height_range so terrain reads as varied without needing
# multiple block types.


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
	if block_max_y < min_ground_y:
		# Entire block is below terrain — fill solid with the
		# valley-floor color. This shows the cube faces of any pit
		# the player digs deep enough to expose underlying voxels.
		var deep_color: int = color_low.to_rgba32()
		out_buffer.fill(deep_color, VoxelBuffer.CHANNEL_COLOR)
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

				# Base colour from the height lerp. world_y (not
				# ground_y) so a tall cliff face fades smoothly rather
				# than painting every cube on the ledge the same shade.
				var t: float = clamp((float(world_y) + half_range - float(height_offset_voxels)) / height_range_voxels, 0.0, 1.0)
				var c: Color = color_low.lerp(color_high, t)

				# --- Per-voxel deterministic colour jitter ---
				# Triple-prime hash mixes the three coords into one
				# pseudo-random byte. Adding a small ± offset to RGB
				# breaks up the otherwise-uniform colour of any flat
				# top, so the eye picks up individual cubes and the
				# 12.5 cm sub-voxel grid becomes visible against the
				# 1 m macro terraces.
				if color_jitter > 0.0:
					var hash_val: int = ((world_x * 73856093) ^ (world_y * 19349663) ^ (world_z * 83492791)) & 0xFF
					var j: float = (float(hash_val) / 255.0 - 0.5) * color_jitter
					c.r = clampf(c.r + j, 0.0, 1.0)
					c.g = clampf(c.g + j, 0.0, 1.0)
					c.b = clampf(c.b + j, 0.0, 1.0)

				out_buffer.set_voxel(c.to_rgba32(), x, y, z, VoxelBuffer.CHANNEL_COLOR)


func _fill_flat(out_buffer: VoxelBuffer, origin: Vector3i, stride: int) -> void:
	# Ground-truth fallback when no noise resource is configured.
	# Solid up to Y=0, air above.
	var size: Vector3i = out_buffer.get_size()
	var c: int = color_low.to_rgba32()
	for x in size.x:
		for z in size.z:
			for y in size.y:
				var world_y: int = origin.y + y * stride
				if world_y <= 0:
					out_buffer.set_voxel(c, x, y, z, VoxelBuffer.CHANNEL_COLOR)
