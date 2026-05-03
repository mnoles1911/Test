@tool
extends VoxelGeneratorScript
class_name CubicHeightmapGenerator

# CubicHeightmapGenerator — writes a noise-driven heightmap into the
# voxel TYPE channel so VoxelMesherCubes can render the world as
# hard-edged blocks (no Transvoxel smoothing).
#
# What this does in plain English:
#
#   For every voxel block the engine asks us to fill, we walk a 2D
#   grid (X, Z) at the block's world position, sample 2D noise to get
#   a ground height, then for every Y in the block:
#       - if Y <= ground_height → write TYPE = 1 (solid block)
#       - if Y >  ground_height → leave TYPE = 0 (air)
#
#   VoxelMesherCubes then renders one cube per solid voxel, all as
#   the same color (palette index 1) until we add a per-material
#   palette later.
#
# Why a custom generator instead of VoxelGeneratorNoise2D?
#
#   Noise2D writes to the SDF (signed-distance) channel that
#   VoxelMesherTransvoxel reads. Cubes reads TYPE only. So we need
#   a generator that writes integer-block-type output.
#
# Coordinates:
#
#   - origin and the inner X/Y/Z indices are in voxel-grid space
#     (1 voxel = 1 grid unit). The VoxelLodTerrain node's transform
#     scale (currently 0.125) maps voxel-grid coords → world-space
#     metres at render time. This script does NOT need to know about
#     world scale.
#   - LOD: at LOD 0 we sample one grid unit per voxel. At higher LODs
#     each voxel covers (1 << lod) grid units, so we step the noise
#     by that stride.

@export var noise: FastNoiseLite
# 2D noise source. Set this in the Inspector. FastNoiseLite with
# fractal_type = RIDGED (2), 5 octaves, frequency ~0.006 gives nice
# valley/ridge terrain. Lower frequency = bigger features.

@export var height_range_voxels: float = 80.0
# Total vertical relief in VOXEL units (not metres). Heightmap output
# is centered around voxel-Y = 0, so half the range goes above sea
# level (Y > 0) and half below (Y < 0). At terrain scale 0.125, 80
# voxels = 10 metres of vertical relief in world space.

@export var sea_level_voxels: int = 0
# Voxel-Y coordinate that should correspond to "ocean surface". Ground
# at or below this Y is submerged when the OceanVolume Area3D sits at
# world Y = 0. Kept as an int so the height comparison is integer-safe.

const SOLID_BLOCK: int = 1
# Voxel TYPE value for solid ground. 0 is reserved for air. We can
# add more types (water=2, stone=3, etc.) later when palettes land.


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# Engine calls this for every chunk the player approaches. We fill
	# `out_buffer` with TYPE values for that chunk.
	#
	# Cheap path: if the block is entirely above the highest possible
	# ground height OR entirely below the lowest, skip the per-voxel
	# loop and just leave it as default (air) or fully solid. Avoids
	# noise sampling for sky/deep-underground chunks.

	var size: Vector3i = out_buffer.get_size()
	var stride: int = 1 << lod  # 1 at LOD0, 2 at LOD1, etc.

	# Cull: every block above max ground is air, every block below
	# min ground is solid. height_range_voxels/2 is the symmetric
	# bound around Y=0.
	var max_ground_y: int = int(height_range_voxels * 0.5) + 1
	var min_ground_y: int = -int(height_range_voxels * 0.5) - 1
	var block_min_y: int = origin_in_voxels.y
	var block_max_y: int = origin_in_voxels.y + (size.y * stride) - 1

	if block_min_y > max_ground_y:
		# Entire block is above terrain — leave as air (default).
		return
	if block_max_y < min_ground_y:
		# Entire block is below terrain — fill solid.
		out_buffer.fill(SOLID_BLOCK, VoxelBuffer.CHANNEL_TYPE)
		return

	if noise == null:
		# No noise resource yet — fall back to flat ground at Y=0.
		_fill_flat(out_buffer, origin_in_voxels, stride)
		return

	# Per-column heightmap pass.
	for x in size.x:
		for z in size.z:
			var world_x: int = origin_in_voxels.x + x * stride
			var world_z: int = origin_in_voxels.z + z * stride
			# Noise output is in [-1, 1]. Scale to half-height range
			# so total relief = height_range_voxels.
			var n: float = noise.get_noise_2d(float(world_x), float(world_z))
			var ground_y: int = int(n * height_range_voxels * 0.5)

			for y in size.y:
				var world_y: int = origin_in_voxels.y + y * stride
				if world_y <= ground_y:
					out_buffer.set_voxel(SOLID_BLOCK, x, y, z, VoxelBuffer.CHANNEL_TYPE)


func _fill_flat(out_buffer: VoxelBuffer, origin: Vector3i, stride: int) -> void:
	# Ground-truth fallback when no noise is configured. Solid up to
	# Y=0, air above. Useful for sanity-checking the mesher channel
	# wiring without noise variability.
	var size: Vector3i = out_buffer.get_size()
	for x in size.x:
		for z in size.z:
			for y in size.y:
				var world_y: int = origin.y + y * stride
				if world_y <= 0:
					out_buffer.set_voxel(SOLID_BLOCK, x, y, z, VoxelBuffer.CHANNEL_TYPE)
