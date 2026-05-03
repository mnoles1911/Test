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
# 5 octaves, frequency ~0.006 gives ridge/valley terrain. Lower
# frequency = bigger features.

@export var height_range_voxels: float = 80.0
# Total vertical relief in VOXEL units (not metres). Heightmap output
# is centered around voxel-Y = 0, so half goes above sea level
# (Y > 0) and half below (Y < 0). At terrain scale 0.125, 80 voxels
# = 10 metres of vertical relief in world space.

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


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# Engine calls this for every chunk the player approaches. We
	# fill out_buffer with COLOR values for that chunk.

	# Make sure COLOR has enough bit depth to hold packed RGBA8888.
	# Default channel depth is too narrow for full color.
	out_buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)

	var size: Vector3i = out_buffer.get_size()
	var stride: int = 1 << lod  # 1 at LOD0, 2 at LOD1, etc.

	# Bound the heightmap range so we can skip blocks fully above or
	# fully below terrain without per-voxel work.
	var max_ground_y: int = int(height_range_voxels * 0.5) + 1
	var min_ground_y: int = -int(height_range_voxels * 0.5) - 1
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
			# Noise output is in [-1, 1]. Scale to half-range so total
			# relief == height_range_voxels.
			var n: float = noise.get_noise_2d(float(world_x), float(world_z))
			var ground_y: int = int(n * half_range)

			for y in size.y:
				var world_y: int = origin_in_voxels.y + y * stride
				if world_y > ground_y:
					continue
				# Lerp color based on this voxel's height within the
				# overall range. Using world_y (not ground_y) so the
				# vertical face of a cliff fades smoothly rather than
				# painting all ledge tops the same shade.
				var t: float = clamp((float(world_y) + half_range) / height_range_voxels, 0.0, 1.0)
				var c: Color = color_low.lerp(color_high, t)
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
