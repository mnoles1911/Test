@tool
extends EditorScript
class_name CopperIslesGeneratorParityHarness

# CopperIslesGeneratorParityHarness — Phase CI-2 verification gate for the
# CopperIslesHeightmapGenerator.gd → CopperIslesHeightmapGeneratorCpp port.
#
# Runs deterministic test fixtures through both the GDScript generator
# and the C++ implementation, comparing:
#   1. hash3 — sanity that ParityProbe still binds and the math layer is
#      bit-exact (10 000 tuples, same as the cubic-era harness).
#   2. sample_gray — bilinear (and nearest) reads from the heightmap EXR
#      across a grid of (x, z) world voxel coords. The C++ Image::get_pixel
#      reads should match GD's Image.get_pixel bit-for-bit.
#   3. gray_to_ground_y — clamp + round trip.
#   4. compute_ground_y — composes (2) + (3); same parity contract as the
#      cubic generator's _ground_y_at.
#   5. column_is_cliff — neighbour-sample slope test.
#   6. Chunk byte tests at LOD0 + LOD1, covering CHANNEL_TYPE and
#      CHANNEL_DATA5 with every tier active (bands, cliff, snow, marble,
#      ores, disks, outcrops, bedrock, water).
#
# How to run: Editor → File → Run on this script. Output panel shows
# `[Parity-CI]` lines.

const HASH3_TUPLE_COUNT: int = 10000
const HASH3_RNG_SEED: int = 0xDEADBEEF
const VERBOSE_MISMATCH_CAP: int = 5

# ground_y grid extent — 5 km Copper Isles map at 6 vox/m is ±15 000 vox.
# Use a 50×50 grid for ~2500 samples.
const GROUND_Y_HALF_EXTENT: int = 14000
const GROUND_Y_STEP: int = 560

const BEDROCK_MATERIAL_ID: int = 6
const SNOW_MATERIAL_ID: int = 13


func _run() -> void:
	print("[Parity-CI] ===== CopperIslesGeneratorParityHarness start =====")

	var probe := ParityProbe.new()
	var hash3_mismatches: int = _test_hash3(probe)
	var sample_gray_mismatches: int = _test_sample_gray()
	var ground_y_mismatches: int = _test_ground_y()
	var cliff_mismatches: int = _test_column_is_cliff()
	var chunk_lod1_mismatches: int = _test_chunk_bytes_lod1()
	var chunk_lod0_mismatches: int = _test_chunk_bytes_lod0()
	var chunk_ores_mismatches: int = _test_chunk_bytes_ores()
	var chunk_disks_mismatches: int = _test_chunk_bytes_disks()
	var chunk_outcrops_mismatches: int = _test_chunk_bytes_outcrops()
	var total: int = hash3_mismatches + sample_gray_mismatches + ground_y_mismatches \
			+ cliff_mismatches + chunk_lod1_mismatches + chunk_lod0_mismatches \
			+ chunk_ores_mismatches + chunk_disks_mismatches + chunk_outcrops_mismatches

	print("[Parity-CI] =====")
	if total == 0:
		print("[Parity-CI] PASS — all checks bit-exact across every tier.")
	else:
		printerr("[Parity-CI] FAIL — %d total mismatches (hash3=%d, sample_gray=%d, ground_y=%d, cliff=%d, lod1=%d, lod0=%d, ores=%d, disks=%d, outcrops=%d)." % [
			total, hash3_mismatches, sample_gray_mismatches, ground_y_mismatches,
			cliff_mismatches, chunk_lod1_mismatches, chunk_lod0_mismatches,
			chunk_ores_mismatches, chunk_disks_mismatches, chunk_outcrops_mismatches,
		])


func _test_hash3(probe: ParityProbe) -> int:
	# Sanity check that the C++ math layer is still bit-exact — required
	# before trusting the tier hashes downstream.
	var rng := RandomNumberGenerator.new()
	rng.seed = HASH3_RNG_SEED
	var mismatches: int = 0
	for i in HASH3_TUPLE_COUNT:
		var x: int = rng.randi_range(-100_000, 100_000)
		var y: int = rng.randi_range(-1_000, 30_000)
		var z: int = rng.randi_range(-100_000, 100_000)
		var seed_v: int = rng.randi_range(0, 1000)
		var gd_v: float = VoxelGenerationMath.hash3(x, y, z, seed_v)
		var cpp_v: float = probe.hash3(x, y, z, seed_v)
		if gd_v != cpp_v:
			mismatches += 1
	if mismatches == 0:
		print("[Parity-CI] hash3: %d / %d bit-for-bit." % [HASH3_TUPLE_COUNT, HASH3_TUPLE_COUNT])
	else:
		printerr("[Parity-CI] hash3: %d / %d MISMATCH." % [mismatches, HASH3_TUPLE_COUNT])
	return mismatches


# Build a configured pair (GD + C++) sharing identical heightmap config.
# The EXR path is the canonical Copper Isles heightmap — the harness fails
# loud if it's not on disk.
func _make_pair() -> Array:
	# Returns [gd_gen, cpp_gen] with identical heightmap config.
	var gd_gen := CopperIslesHeightmapGenerator.new()
	# Defaults from the .gd file already point at the canonical EXR; keep
	# them. Disable all tiers initially; per-test functions enable what
	# they exercise.
	gd_gen.cliff_rule_max_lod = -1
	gd_gen.snow_line_max_lod = -1
	gd_gen.ore_vein_max_lod = -1
	gd_gen.disk_rule_max_lod = -1

	var cpp_gen := CopperIslesHeightmapGeneratorCpp.new()
	cpp_gen.heightmap_path = gd_gen.heightmap_path
	cpp_gen.extent_x_voxels = gd_gen.extent_x_voxels
	cpp_gen.extent_z_voxels = gd_gen.extent_z_voxels
	cpp_gen.origin_x_voxels = gd_gen.origin_x_voxels
	cpp_gen.origin_z_voxels = gd_gen.origin_z_voxels
	cpp_gen.sea_level_voxels = gd_gen.sea_level_voxels
	cpp_gen.elevation_above_at_white_voxels = gd_gen.elevation_above_at_white_voxels
	cpp_gen.bilinear_sampling = gd_gen.bilinear_sampling
	cpp_gen.grass_layer_thickness_voxels = gd_gen.grass_layer_thickness_voxels
	cpp_gen.dirt_layer_thickness_voxels = gd_gen.dirt_layer_thickness_voxels
	cpp_gen.beach_y_threshold = gd_gen.beach_y_threshold
	cpp_gen.marble_jitter_block_size = gd_gen.marble_jitter_block_size
	cpp_gen.marble_jitter_seed = gd_gen.marble_jitter_seed
	cpp_gen.marble_rare_threshold = gd_gen.marble_rare_threshold
	cpp_gen.marble_dark_threshold = gd_gen.marble_dark_threshold
	cpp_gen.marble_jitter_max_lod = gd_gen.marble_jitter_max_lod
	cpp_gen.snow_line_voxels = gd_gen.snow_line_voxels
	cpp_gen.snow_line_jitter_voxels = gd_gen.snow_line_jitter_voxels
	cpp_gen.snow_line_jitter_block_size = gd_gen.snow_line_jitter_block_size
	cpp_gen.snow_line_seed = gd_gen.snow_line_seed
	cpp_gen.snow_line_max_lod = gd_gen.snow_line_max_lod
	cpp_gen.cliff_slope_sample_distance_voxels = gd_gen.cliff_slope_sample_distance_voxels
	cpp_gen.cliff_slope_threshold_voxels = gd_gen.cliff_slope_threshold_voxels
	cpp_gen.cliff_rule_max_lod = gd_gen.cliff_rule_max_lod
	cpp_gen.ore_vein_max_lod = gd_gen.ore_vein_max_lod
	cpp_gen.disk_rule_max_lod = gd_gen.disk_rule_max_lod
	cpp_gen.disk_anchor_grid_voxels = gd_gen.disk_anchor_grid_voxels
	cpp_gen.cliff_ore_outcrop_chance = gd_gen.cliff_ore_outcrop_chance
	cpp_gen.cliff_ore_seed = gd_gen.cliff_ore_seed
	cpp_gen.bedrock_material_id = BEDROCK_MATERIAL_ID
	cpp_gen.snow_material_id = SNOW_MATERIAL_ID
	cpp_gen.world_floor_voxel_y = -300
	return [gd_gen, cpp_gen]


func _test_sample_gray() -> int:
	# Walk a sparse grid of world coords and compare sample_gray() outputs.
	# Bilinear math is the riskiest piece — half-pixel offset + double
	# promotion of float pixel reads + clamping at edges.
	var pair: Array = _make_pair()
	var gd_gen: CopperIslesHeightmapGenerator = pair[0]
	var cpp_gen: CopperIslesHeightmapGeneratorCpp = pair[1]

	var mismatches: int = 0
	var checked: int = 0
	var dumped: int = 0
	var x: int = -GROUND_Y_HALF_EXTENT
	while x <= GROUND_Y_HALF_EXTENT:
		var z: int = -GROUND_Y_HALF_EXTENT
		while z <= GROUND_Y_HALF_EXTENT:
			var gd_v: float = gd_gen._sample_gray(x, z)
			var cpp_v: float = cpp_gen.sample_gray(x, z)
			checked += 1
			if not is_equal_approx(gd_v, cpp_v):
				mismatches += 1
				if dumped < VERBOSE_MISMATCH_CAP:
					printerr("[Parity-CI] sample_gray mismatch at (x=%d, z=%d): gd=%.10f cpp=%.10f delta=%.10g" % [
						x, z, gd_v, cpp_v, gd_v - cpp_v
					])
					dumped += 1
			z += GROUND_Y_STEP
		x += GROUND_Y_STEP
	if mismatches == 0:
		print("[Parity-CI] sample_gray: %d / %d samples match (approx-equal)." % [checked, checked])
	else:
		printerr("[Parity-CI] sample_gray: %d / %d mismatches." % [mismatches, checked])
	return mismatches


func _test_ground_y() -> int:
	# Composes sample_gray + gray_to_ground_y. Compares the int output.
	var pair: Array = _make_pair()
	var gd_gen: CopperIslesHeightmapGenerator = pair[0]
	var cpp_gen: CopperIslesHeightmapGeneratorCpp = pair[1]

	var mismatches: int = 0
	var checked: int = 0
	var dumped: int = 0
	var x: int = -GROUND_Y_HALF_EXTENT
	while x <= GROUND_Y_HALF_EXTENT:
		var z: int = -GROUND_Y_HALF_EXTENT
		while z <= GROUND_Y_HALF_EXTENT:
			var gd_v: int = gd_gen.get_ground_voxel_y_at(x, z)
			var cpp_v: int = cpp_gen.get_ground_voxel_y_at(x, z)
			checked += 1
			if gd_v != cpp_v:
				mismatches += 1
				if dumped < VERBOSE_MISMATCH_CAP:
					printerr("[Parity-CI] ground_y mismatch at (x=%d, z=%d): gd=%d cpp=%d" % [
						x, z, gd_v, cpp_v
					])
					dumped += 1
			z += GROUND_Y_STEP
		x += GROUND_Y_STEP
	if mismatches == 0:
		print("[Parity-CI] ground_y: %d / %d match bit-for-bit." % [checked, checked])
	else:
		printerr("[Parity-CI] ground_y: %d / %d mismatches." % [mismatches, checked])
	return mismatches


func _test_column_is_cliff() -> int:
	# Run with cliff_slope_threshold=1 so virtually every sloped column
	# fires the cliff check — stress-tests the 4-neighbour sample agreement.
	var pair: Array = _make_pair()
	var gd_gen: CopperIslesHeightmapGenerator = pair[0]
	var cpp_gen: CopperIslesHeightmapGeneratorCpp = pair[1]
	gd_gen.cliff_slope_threshold_voxels = 1
	cpp_gen.cliff_slope_threshold_voxels = 1
	gd_gen.cliff_rule_max_lod = 0
	cpp_gen.cliff_rule_max_lod = 0

	var mismatches: int = 0
	var checked: int = 0
	var dumped: int = 0
	# Smaller grid — 4 neighbour samples each call, so heightmap cost
	# is roughly 5× the ground_y test. Use a denser grid (200 samples).
	var x: int = -3000
	while x <= 3000:
		var z: int = -3000
		while z <= 3000:
			var gy: int = gd_gen.get_ground_voxel_y_at(x, z)
			var gd_v: bool = gd_gen._column_is_cliff(x, z, gy)
			var cpp_v: bool = cpp_gen.column_is_cliff(x, z, gy)
			checked += 1
			if gd_v != cpp_v:
				mismatches += 1
				if dumped < VERBOSE_MISMATCH_CAP:
					printerr("[Parity-CI] column_is_cliff mismatch at (x=%d, z=%d, ground_y=%d): gd=%s cpp=%s" % [
						x, z, gy, gd_v, cpp_v
					])
					dumped += 1
			z += 300
		x += 300
	if mismatches == 0:
		print("[Parity-CI] column_is_cliff: %d / %d match (cliff_threshold=1)." % [checked, checked])
	else:
		printerr("[Parity-CI] column_is_cliff: %d / %d mismatches." % [mismatches, checked])
	return mismatches


# Diff CHANNEL_TYPE (and optionally CHANNEL_DATA5) byte-by-byte across a
# list of chunk origins at the given LOD. Returns mismatch count.
func _diff_chunks(label: String,
		gd_gen: CopperIslesHeightmapGenerator,
		cpp_gen: CopperIslesHeightmapGeneratorCpp,
		origins: Array[Vector3i],
		test_lod: int,
		check_data5: bool) -> int:
	const CHUNK_SIZE: int = 16
	var mismatches: int = 0
	var dumped: int = 0
	var voxels: int = 0
	for origin in origins:
		var gd_buf := VoxelBuffer.new()
		gd_buf.create(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
		gd_gen._generate_block(gd_buf, origin, test_lod)
		var cpp_buf := VoxelBuffer.new()
		cpp_buf.create(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
		cpp_gen.generate_block_into_buffer(cpp_buf, origin, test_lod)
		for cx in CHUNK_SIZE:
			for cy in CHUNK_SIZE:
				for cz in CHUNK_SIZE:
					var gd_t: int = gd_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_TYPE)
					var cpp_t: int = cpp_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_TYPE)
					voxels += 1
					if gd_t != cpp_t:
						mismatches += 1
						if dumped < VERBOSE_MISMATCH_CAP:
							var stride: int = 1 << test_lod
							printerr("[Parity-CI] %s TYPE mismatch origin=%s lod=%d local=(%d,%d,%d) world=(%d,%d,%d): gd=%d cpp=%d" % [
								label, origin, test_lod, cx, cy, cz,
								origin.x + cx * stride, origin.y + cy * stride, origin.z + cz * stride,
								gd_t, cpp_t,
							])
							dumped += 1
					if check_data5:
						var gd_w: int = gd_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_DATA5)
						var cpp_w: int = cpp_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_DATA5)
						if gd_w != cpp_w:
							mismatches += 1
							if dumped < VERBOSE_MISMATCH_CAP:
								printerr("[Parity-CI] %s DATA5 mismatch origin=%s local=(%d,%d,%d): gd=0x%02X cpp=0x%02X" % [
									label, origin, cx, cy, cz, gd_w, cpp_w,
								])
								dumped += 1
	var total_reads: int = (voxels * 2) if check_data5 else voxels
	print("[Parity-CI] %s: %d / %d voxel reads match across %d chunks (LOD %d, data5=%s)." % [
		label, total_reads - mismatches, total_reads,
		origins.size(), test_lod, check_data5,
	])
	return mismatches


# Pick chunk origins in the central Copper Isles area where the heightmap
# is populated (we're inside the rectangle origin..origin+extent).
const COPPER_TEST_ORIGINS: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(0, 200, 0),
	Vector3i(500, 100, -500),
	Vector3i(-1000, 50, 1000),
	Vector3i(2000, 300, -2000),
	Vector3i(-2500, 0, -2500),
]


func _test_chunk_bytes_lod1() -> int:
	# LOD=1 with bands + marble jitter only. Tier 1/2/4/5/6 disabled.
	# Water emission is LOD0-only so DATA5 is irrelevant here.
	var pair: Array = _make_pair()
	var gd_gen: CopperIslesHeightmapGenerator = pair[0]
	var cpp_gen: CopperIslesHeightmapGeneratorCpp = pair[1]
	return _diff_chunks("lod1_bands", gd_gen, cpp_gen, COPPER_TEST_ORIGINS, 1, false)


func _test_chunk_bytes_lod0() -> int:
	# LOD=0 with bands + marble + bedrock + water. Tier 1/2/4/5/6 off.
	# Origins include below-sea-level chunks for water byte coverage.
	var pair: Array = _make_pair()
	var gd_gen: CopperIslesHeightmapGenerator = pair[0]
	var cpp_gen: CopperIslesHeightmapGeneratorCpp = pair[1]
	var origins: Array[Vector3i] = [
		Vector3i(0, 0, 0),         # likely below sea (ground_y near 0 at gray~0)
		Vector3i(500, -10, 500),   # straddles sea level
		Vector3i(-1000, 200, 1000),# elevated
		Vector3i(0, -310, 0),      # bedrock-straddling (sea floor + below world floor)
		Vector3i(2000, 100, -2000),
	]
	return _diff_chunks("lod0_bands_water_bedrock", gd_gen, cpp_gen, origins, 0, true)


# Synthesize two ore materials in-code (matches the cubic harness pattern).
func _make_ores() -> Array[VoxelMaterial]:
	var iron := VoxelMaterial.new()
	iron.material_id = 15
	iron.replaces_material_id = 1
	iron.min_altitude_voxels = -1000
	iron.max_altitude_voxels = 30000
	iron.ore_noise_threshold = 0.4
	iron.ore_noise_scale = 0.05
	var copper := VoxelMaterial.new()
	copper.material_id = 12
	copper.replaces_material_id = 1
	copper.min_altitude_voxels = -1000
	copper.max_altitude_voxels = 30000
	copper.ore_noise_threshold = 0.45
	copper.ore_noise_scale = 0.04
	var ores: Array[VoxelMaterial] = [iron, copper]
	return ores


func _ores_to_dicts(list: Array[VoxelMaterial]) -> Array:
	var out: Array = []
	out.resize(list.size())
	for i in list.size():
		var m: VoxelMaterial = list[i]
		out[i] = {
			"material_id": m.material_id,
			"replaces_material_id": m.replaces_material_id,
			"min_altitude_voxels": m.min_altitude_voxels,
			"max_altitude_voxels": m.max_altitude_voxels,
			"ore_noise_threshold": m.ore_noise_threshold,
			"ore_noise_scale": m.ore_noise_scale,
		}
	return out


func _disks_to_dicts(list: Array[VoxelMaterial]) -> Array:
	var out: Array = []
	out.resize(list.size())
	for i in list.size():
		var m: VoxelMaterial = list[i]
		out[i] = {
			"material_id": m.material_id,
			"disk_radius_voxels": m.disk_radius_voxels,
			"disk_half_height_voxels": m.disk_half_height_voxels,
			"disk_anchor_density": m.disk_anchor_density,
			"disk_max_distance_to_water_voxels": m.disk_max_distance_to_water_voxels,
		}
	return out


func _test_chunk_bytes_ores() -> int:
	var pair: Array = _make_pair()
	var gd_gen: CopperIslesHeightmapGenerator = pair[0]
	var cpp_gen: CopperIslesHeightmapGeneratorCpp = pair[1]
	gd_gen.ore_vein_max_lod = 0
	cpp_gen.ore_vein_max_lod = 0
	var ores := _make_ores()
	gd_gen.set_ore_materials(ores)
	cpp_gen.set_ore_materials(_ores_to_dicts(ores))
	return _diff_chunks("ores", gd_gen, cpp_gen, COPPER_TEST_ORIGINS, 0, false)


func _test_chunk_bytes_disks() -> int:
	var pair: Array = _make_pair()
	var gd_gen: CopperIslesHeightmapGenerator = pair[0]
	var cpp_gen: CopperIslesHeightmapGeneratorCpp = pair[1]
	gd_gen.disk_rule_max_lod = 0
	cpp_gen.disk_rule_max_lod = 0
	var clay := VoxelMaterial.new()
	clay.material_id = 8  # clay
	clay.disk_radius_voxels = 8
	clay.disk_half_height_voxels = 1
	clay.disk_anchor_density = 0.20
	clay.disk_max_distance_to_water_voxels = 30
	var disks: Array[VoxelMaterial] = [clay]
	gd_gen.set_disk_materials(disks)
	cpp_gen.set_disk_materials(_disks_to_dicts(disks))
	# Disk match needs columns near sea level — focus origins on Y ranges
	# straddling sea_level_voxels = 0.
	var origins: Array[Vector3i] = [
		Vector3i(0, -8, 0),
		Vector3i(500, -8, -500),
		Vector3i(-1000, -8, 1000),
		Vector3i(1500, 8, -1500),
	]
	return _diff_chunks("disks", gd_gen, cpp_gen, origins, 0, false)


func _test_chunk_bytes_outcrops() -> int:
	# Tier 6 — cliff override + ore outcrop. Force cliff threshold=1 to
	# guarantee plenty of cliff columns, outcrop_chance=0.5 to fire often.
	var pair: Array = _make_pair()
	var gd_gen: CopperIslesHeightmapGenerator = pair[0]
	var cpp_gen: CopperIslesHeightmapGeneratorCpp = pair[1]
	gd_gen.cliff_rule_max_lod = 0
	cpp_gen.cliff_rule_max_lod = 0
	gd_gen.cliff_slope_threshold_voxels = 1
	cpp_gen.cliff_slope_threshold_voxels = 1
	gd_gen.cliff_ore_outcrop_chance = 0.5
	cpp_gen.cliff_ore_outcrop_chance = 0.5
	var ores := _make_ores()
	gd_gen.set_ore_materials(ores)
	cpp_gen.set_ore_materials(_ores_to_dicts(ores))
	return _diff_chunks("outcrops", gd_gen, cpp_gen, COPPER_TEST_ORIGINS, 0, false)
