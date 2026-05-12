@tool
extends EditorScript
class_name GeneratorParityHarness

# GeneratorParityHarness — Phase 1 verification gate.
#
# Runs deterministic test tuples through both the GDScript
# VoxelGenerationMath helpers and the C++ ParityProbe shim, then
# reports any mismatched outputs. Pass criterion for Phase 1:
# zero mismatches.
#
# How to run:
#   Open in the Godot editor, then File → Run (or Ctrl+Shift+X).
#   Watch the Output panel for the report.
#
# Why @tool / EditorScript: this runs inside the editor on demand,
# not as part of a played scene. Editor context is fine because we
# only call pure-math functions, no SceneTree, no autoloads, no I/O.
#
# What we check:
#   1. hash3 — 10 000 random (x, y, z, seed) tuples spanning the
#      project's realistic voxel coordinate range. We want bit-exact
#      double-precision equality.
#   2. cliff_threshold_for_angle_voxels — an angle sweep from 0° to
#      89° at 1° steps, with three sample-distance settings each.
#      Returns int; equality is straightforward.
#
# Why a fixed RNG seed: any mismatch needs to be reproducible. If
# the first run shows a failure at tuple #4732, the next run shows
# the same failure at the same tuple, so we can extract it and
# inspect manually.


const HASH3_TUPLE_COUNT: int = 10000
const HASH3_RNG_SEED: int = 0xDEADBEEF

# Coordinate ranges chosen to cover Copper Isles (5 km × 5 km map,
# 6 vox/m → ±15 000 voxels horizontal; Y from world floor -300 up
# past the snow line at 12 000+). Padded out to ±100 000 so we also
# exercise inputs that overflow 32-bit signed multiplication.
const X_RANGE: int = 100_000   # -100k..+100k
const Y_RANGE_LO: int = -1_000
const Y_RANGE_HI: int = 30_000
const Z_RANGE: int = 100_000
const SEED_RANGE: int = 1_000

# How many mismatches to dump in detail before stopping verbose logging.
const VERBOSE_MISMATCH_CAP: int = 5

# Phase 2 ground_y sweep — grid resolution + extent. A 50×50 grid at
# 200-voxel step covers ±5000 voxels in X/Z, which is plenty to exercise
# noise variance + the realistic playable area.
const GROUND_Y_GRID_HALF_EXTENT: int = 5000   # ±5000 voxels around origin
const GROUND_Y_GRID_STEP: int = 200            # one sample every 200 voxels


func _run() -> void:
	print("[Parity] ===== GeneratorParityHarness start =====")

	var probe := ParityProbe.new()

	var hash3_mismatches: int = _test_hash3(probe)
	var cliff_mismatches: int = _test_cliff_threshold(probe)
	var ground_y_mismatches: int = _test_ground_y()
	var chunk_mismatches: int = _test_chunk_bytes()
	var chunk_lod0_mismatches: int = _test_chunk_bytes_lod0()
	var total: int = hash3_mismatches + cliff_mismatches + ground_y_mismatches \
			+ chunk_mismatches + chunk_lod0_mismatches

	print("[Parity] =====")
	if total == 0:
		print("[Parity] PASS — all checks bit-exact (hash3 + cliff_threshold + ground_y + chunk_bytes + chunk_bytes_lod0).")
		print("[Parity] Phase 4a gate satisfied (bedrock + water bytes verified). Safe to proceed.")
	else:
		printerr("[Parity] FAIL — %d total mismatches (hash3=%d, cliff=%d, ground_y=%d, chunk_bytes=%d, chunk_lod0=%d)." % [
			total, hash3_mismatches, cliff_mismatches, ground_y_mismatches, chunk_mismatches, chunk_lod0_mismatches
		])


func _test_hash3(probe: ParityProbe) -> int:
	# Use a separate RNG instance so we don't disturb Godot's global RNG state.
	var rng := RandomNumberGenerator.new()
	rng.seed = HASH3_RNG_SEED

	var mismatches: int = 0
	var dumped: int = 0

	for i in HASH3_TUPLE_COUNT:
		var x: int = rng.randi_range(-X_RANGE, X_RANGE)
		var y: int = rng.randi_range(Y_RANGE_LO, Y_RANGE_HI)
		var z: int = rng.randi_range(-Z_RANGE, Z_RANGE)
		var seed_v: int = rng.randi_range(0, SEED_RANGE)

		var gd_v: float = VoxelGenerationMath.hash3(x, y, z, seed_v)
		var cpp_v: float = probe.hash3(x, y, z, seed_v)

		# Bit-exact: GDScript float equality compares the underlying
		# float64 representation. If both came from the same integer
		# math + same divisor, they're equal.
		if gd_v != cpp_v:
			mismatches += 1
			if dumped < VERBOSE_MISMATCH_CAP:
				printerr("[Parity] hash3 mismatch #%d at tuple %d: (x=%d, y=%d, z=%d, seed=%d) gd=%.20f cpp=%.20f delta=%.20g" % [
					dumped + 1, i, x, y, z, seed_v, gd_v, cpp_v, gd_v - cpp_v
				])
				dumped += 1

	if mismatches == 0:
		print("[Parity] hash3: %d / %d tuples match bit-for-bit." % [HASH3_TUPLE_COUNT, HASH3_TUPLE_COUNT])
	else:
		printerr("[Parity] hash3: %d / %d tuples mismatched (showing up to %d above)." % [mismatches, HASH3_TUPLE_COUNT, VERBOSE_MISMATCH_CAP])

	return mismatches


func _test_cliff_threshold(probe: ParityProbe) -> int:
	var mismatches: int = 0
	var checked: int = 0
	var sample_distances: Array[int] = [3, 6, 12]

	# Angle sweep 0°..89° in 1° steps. 90° is the asymptote of tan; skip it
	# to avoid an infinity comparison that doesn't tell us anything new.
	for angle_deg in range(0, 90):
		for sd in sample_distances:
			var gd_v: int = VoxelGenerationMath.cliff_threshold_for_angle_voxels(float(angle_deg), sd)
			var cpp_v: int = probe.cliff_threshold_for_angle_voxels(float(angle_deg), sd)
			checked += 1
			if gd_v != cpp_v:
				mismatches += 1
				printerr("[Parity] cliff_threshold mismatch at angle=%d°, sd=%d: gd=%d cpp=%d" % [angle_deg, sd, gd_v, cpp_v])

	if mismatches == 0:
		print("[Parity] cliff_threshold: %d / %d (angle, sample_distance) pairs match." % [checked, checked])
	else:
		printerr("[Parity] cliff_threshold: %d / %d pairs mismatched." % [mismatches, checked])

	return mismatches


# Phase 2 — ground_y per-column parity.
#
# Builds two generators (GD + C++) sharing IDENTICAL configuration: same
# FastNoiseLite resource (so all underlying noise samples are bit-identical)
# and same height params. Then walks a grid of (world_x, world_z) and
# compares the integer ground_y each side reports for that column.
#
# Both implementations are pure functions of their config + (x, z), so
# bit-exact integer equality is the right gate.
func _test_ground_y() -> int:
	# Shared noise resource — both generators reference the SAME instance,
	# so we don't have to worry about whether two FastNoiseLite resources
	# with the same seed produce identical outputs.
	var noise := FastNoiseLite.new()
	noise.seed = 0xC0FFEE
	noise.frequency = 0.005  # macro-scale by default
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	# GDScript generator.
	var gd_gen := CubicHeightmapGenerator.new()
	gd_gen.noise = noise
	gd_gen.height_range_voxels = 900.0
	gd_gen.height_offset_voxels = 60
	gd_gen.quantize_to_meters = false
	gd_gen.mid_amplitude_voxels = 10
	gd_gen.mid_frequency_multiplier = 3.0
	gd_gen.detail_amplitude_voxels = 2
	gd_gen.detail_frequency_multiplier = 12.0

	# C++ generator. Same params; same noise reference.
	var cpp_gen := CubicHeightmapGeneratorCpp.new()
	cpp_gen.noise = noise
	cpp_gen.height_range_voxels = 900.0
	cpp_gen.height_offset_voxels = 60
	cpp_gen.quantize_to_meters = false
	cpp_gen.mid_amplitude_voxels = 10
	cpp_gen.mid_frequency_multiplier = 3.0
	cpp_gen.detail_amplitude_voxels = 2
	cpp_gen.detail_frequency_multiplier = 12.0

	var mismatches: int = 0
	var checked: int = 0
	var dumped: int = 0

	var x := -GROUND_Y_GRID_HALF_EXTENT
	while x <= GROUND_Y_GRID_HALF_EXTENT:
		var z := -GROUND_Y_GRID_HALF_EXTENT
		while z <= GROUND_Y_GRID_HALF_EXTENT:
			var gd_v: int = gd_gen._ground_y_at(x, z)
			var cpp_v: int = cpp_gen.compute_ground_y(x, z)
			checked += 1
			if gd_v != cpp_v:
				mismatches += 1
				if dumped < VERBOSE_MISMATCH_CAP:
					printerr("[Parity] ground_y mismatch at (x=%d, z=%d): gd=%d cpp=%d" % [x, z, gd_v, cpp_v])
					dumped += 1
			z += GROUND_Y_GRID_STEP
		x += GROUND_Y_GRID_STEP

	# Also sweep quantize_to_meters=true (different code path inside _ground_y_at).
	gd_gen.quantize_to_meters = true
	cpp_gen.quantize_to_meters = true
	var quantize_mismatches: int = 0
	var quantize_checked: int = 0
	# Smaller grid for the quantize sweep — main job is to exercise the
	# roundi-vs-lround agreement, not to re-cover the whole map.
	var qx := -2000
	while qx <= 2000:
		var qz := -2000
		while qz <= 2000:
			var qgd: int = gd_gen._ground_y_at(qx, qz)
			var qcpp: int = cpp_gen.compute_ground_y(qx, qz)
			quantize_checked += 1
			if qgd != qcpp:
				quantize_mismatches += 1
				if dumped < VERBOSE_MISMATCH_CAP:
					printerr("[Parity] ground_y mismatch (quantized) at (x=%d, z=%d): gd=%d cpp=%d" % [qx, qz, qgd, qcpp])
					dumped += 1
			qz += GROUND_Y_GRID_STEP
		qx += GROUND_Y_GRID_STEP
	mismatches += quantize_mismatches

	if mismatches == 0:
		print("[Parity] ground_y: %d unquantized + %d quantized samples match bit-for-bit." % [checked, quantize_checked])
	else:
		printerr("[Parity] ground_y: %d / %d total mismatches (%d unquantized, %d quantized)." % [
			mismatches, checked + quantize_checked, mismatches - quantize_mismatches, quantize_mismatches
		])

	return mismatches


# Phase 3 — chunk-byte parity over 50 chunks.
#
# For each test chunk:
#   1. Build a fresh VoxelBuffer of size 16^3.
#   2. Call GD's _generate_block (configured to run plan-Tier 1 + plan-Tier 3 only)
#      and C++'s generate_block_into_buffer with the same buffer dimensions
#      and same (origin, lod).
#   3. Read CHANNEL_TYPE byte-by-byte from each side and compare.
#
# We test at LOD=1 specifically to disable GD's water emission (`write_water =
# lod == 0`), keep all chunks safely above WORLD_FLOOR_VOXEL_Y=-300 so the
# bedrock legacy-bug discrepancy doesn't surface, and disable
# cliff/snow/ore/disk via the GD generator's *_max_lod=-1 settings so only
# bands + marble run.
func _test_chunk_bytes() -> int:
	const CHUNK_SIZE: int = 16
	const TEST_LOD: int = 1

	# Hand-picked chunk origins. Mix of low-noise (around y=50, ground likely
	# inside chunk) and higher-noise (y=200, ground may or may not be inside).
	# X/Z spread across a 5 km strip to exercise noise variance.
	var test_origins: Array[Vector3i] = []
	var y_targets: Array[int] = [50, 100, 200, -50, 0]   # 5 Y rows
	var xz_grid: Array[int] = [-2000, -1000, 0, 1000, 2000]  # 5×2 = 10 X/Z pairs (only 5 used per Y)
	for y in y_targets:
		for i in range(10):
			var x: int = xz_grid[i % 5]
			var z: int = xz_grid[(i / 5) % 5]  # 0..4 for i in 0..9 — varies independently
			test_origins.append(Vector3i(x, y, z))
	# That gives 50 chunks (5 Y × 10 X/Z pairs).

	var noise := FastNoiseLite.new()
	noise.seed = 0xC0FFEE
	noise.frequency = 0.005
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	# GD generator configured for plan-Tier 1 + plan-Tier 3 only.
	# proj-Tier 1 (cliff slope) -> cliff_rule_max_lod = -1
	# proj-Tier 2 (snow line)   -> snow_line_max_lod = -1
	# proj-Tier 4 (ores)        -> ore_vein_max_lod = -1
	# proj-Tier 5 (disks)       -> disk_rule_max_lod = -1
	# plan-Tier 3 (marble)      -> marble_jitter_max_lod = 1 (default; runs at TEST_LOD)
	var gd_gen := CubicHeightmapGenerator.new()
	gd_gen.noise = noise
	gd_gen.cliff_rule_max_lod = -1
	gd_gen.snow_line_max_lod = -1
	gd_gen.ore_vein_max_lod = -1
	gd_gen.disk_rule_max_lod = -1
	# Use default marble settings (block_size=4, seed=1, thresholds 0.92/0.75).

	var cpp_gen := CubicHeightmapGeneratorCpp.new()
	cpp_gen.noise = noise
	cpp_gen.height_range_voxels = gd_gen.height_range_voxels
	cpp_gen.height_offset_voxels = gd_gen.height_offset_voxels
	cpp_gen.quantize_to_meters = gd_gen.quantize_to_meters
	cpp_gen.mid_amplitude_voxels = gd_gen.mid_amplitude_voxels
	cpp_gen.mid_frequency_multiplier = gd_gen.mid_frequency_multiplier
	cpp_gen.detail_amplitude_voxels = gd_gen.detail_amplitude_voxels
	cpp_gen.detail_frequency_multiplier = gd_gen.detail_frequency_multiplier
	cpp_gen.grass_layer_thickness_voxels = gd_gen.grass_layer_thickness_voxels
	cpp_gen.dirt_layer_thickness_voxels = gd_gen.dirt_layer_thickness_voxels
	cpp_gen.beach_y_threshold = gd_gen.beach_y_threshold
	cpp_gen.marble_jitter_block_size = gd_gen.marble_jitter_block_size
	cpp_gen.marble_jitter_seed = gd_gen.marble_jitter_seed
	cpp_gen.marble_rare_threshold = gd_gen.marble_rare_threshold
	cpp_gen.marble_dark_threshold = gd_gen.marble_dark_threshold
	cpp_gen.marble_jitter_max_lod = gd_gen.marble_jitter_max_lod

	var mismatches: int = 0
	var voxels_checked: int = 0
	var dumped: int = 0
	var chunks_with_mismatches: int = 0

	for origin in test_origins:
		var gd_buf := VoxelBuffer.new()
		gd_buf.create(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
		gd_gen._generate_block(gd_buf, origin, TEST_LOD)

		var cpp_buf := VoxelBuffer.new()
		cpp_buf.create(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
		cpp_gen.generate_block_into_buffer(cpp_buf, origin, TEST_LOD)

		var chunk_mismatched: bool = false
		for cx in CHUNK_SIZE:
			for cy in CHUNK_SIZE:
				for cz in CHUNK_SIZE:
					var gd_v: int = gd_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_TYPE)
					var cpp_v: int = cpp_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_TYPE)
					voxels_checked += 1
					if gd_v != cpp_v:
						mismatches += 1
						chunk_mismatched = true
						if dumped < VERBOSE_MISMATCH_CAP:
							var stride: int = 1 << TEST_LOD
							var world_x: int = origin.x + cx * stride
							var world_y: int = origin.y + cy * stride
							var world_z: int = origin.z + cz * stride
							printerr("[Parity] chunk mismatch at origin=%s lod=%d local=(%d,%d,%d) world=(%d,%d,%d): gd=%d cpp=%d" % [
								origin, TEST_LOD, cx, cy, cz, world_x, world_y, world_z, gd_v, cpp_v
							])
							dumped += 1
		if chunk_mismatched:
			chunks_with_mismatches += 1

	if mismatches == 0:
		print("[Parity] chunk_bytes: %d / %d voxels match bit-for-bit across %d chunks (LOD %d)." % [
			voxels_checked, voxels_checked, test_origins.size(), TEST_LOD
		])
	else:
		printerr("[Parity] chunk_bytes: %d / %d voxels mismatched across %d / %d chunks." % [
			mismatches, voxels_checked, chunks_with_mismatches, test_origins.size()
		])

	return mismatches


# Phase 4a — LOD=0 chunk parity covering CHANNEL_TYPE *and* CHANNEL_DATA5.
#
# Adds three things the LOD=1 test couldn't exercise:
#   1. Bedrock row at world_y == WORLD_FLOOR_VOXEL_Y = -300 (post-bugfix:
#      writes material_id 6, not a color-byte-truncated garbage value).
#   2. Water byte 0x18 (WaterByteCodec.SOURCE_BYTE) on CHANNEL_DATA5 for
#      air voxels above terrain and at or below sea level (LOD0 only).
#   3. World-floor air gate: voxels with world_y < -300 are written as
#      nothing (default 0 air) on both sides.
#
# Tiers gated off the same way as _test_chunk_bytes: only bands + marble
# + bedrock + water bytes are exercised here. Cliff/snow/ore/disk come
# online in 4b-4g and the harness will grow new chunks per phase.
func _test_chunk_bytes_lod0() -> int:
	const CHUNK_SIZE: int = 16
	const TEST_LOD: int = 0
	const BEDROCK_MATERIAL_ID: int = 6
	const WORLD_FLOOR_VOXEL_Y: int = -300
	const SEA_LEVEL_VOXELS: int = 72
	const WATER_SOURCE_BYTE: int = 0x18
	_unused(WATER_SOURCE_BYTE)

	# Chunk origins chosen to exercise each new code path:
	#   sea-straddling      — water bytes fill the air column above
	#                         ground_y up through SEA_LEVEL_VOXELS.
	#   deep-ocean          — entire chunk is air above terrain but
	#                         below sea level; every voxel is water.
	#   above-sea-no-water  — typical surface chunk that should emit
	#                         zero water bytes (parity must hold).
	#   bedrock-straddling  — chunk straddles WORLD_FLOOR_VOXEL_Y;
	#                         one row is bedrock, rows above are
	#                         stone band, rows below are air.
	var test_origins: Array[Vector3i] = [
		Vector3i(0, 64, 0),         # straddles sea level (64..79)
		Vector3i(1000, 64, -1000),  # straddles sea, offset noise
		Vector3i(-500, 0, 500),     # spans 0..15, far below sea level
		Vector3i(0, 100, 0),        # 100..115, above sea, no water
		Vector3i(2000, 200, 1500),  # well above terrain at this noise
		Vector3i(0, -310, 0),       # straddles bedrock floor (-310..-295)
		Vector3i(800, -304, -200),  # bedrock-straddling, different XZ
	]

	var noise := FastNoiseLite.new()
	noise.seed = 0xC0FFEE
	noise.frequency = 0.005
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	# GD generator: tiers not yet ported to C++ stay off via *_max_lod = -1.
	# Marble jitter DOES run at LOD0 with default settings; the C++ side
	# matches via the same default marble_jitter_max_lod=1.
	# _ensure_materials_cached() runs inside _generate_block and loads
	# _cached_bedrock from the .tres, so bedrock fires naturally on the GD side.
	var gd_gen := CubicHeightmapGenerator.new()
	gd_gen.noise = noise
	gd_gen.cliff_rule_max_lod = -1
	gd_gen.snow_line_max_lod = -1
	gd_gen.ore_vein_max_lod = -1
	gd_gen.disk_rule_max_lod = -1

	var cpp_gen := CubicHeightmapGeneratorCpp.new()
	cpp_gen.noise = noise
	cpp_gen.height_range_voxels = gd_gen.height_range_voxels
	cpp_gen.height_offset_voxels = gd_gen.height_offset_voxels
	cpp_gen.quantize_to_meters = gd_gen.quantize_to_meters
	cpp_gen.mid_amplitude_voxels = gd_gen.mid_amplitude_voxels
	cpp_gen.mid_frequency_multiplier = gd_gen.mid_frequency_multiplier
	cpp_gen.detail_amplitude_voxels = gd_gen.detail_amplitude_voxels
	cpp_gen.detail_frequency_multiplier = gd_gen.detail_frequency_multiplier
	cpp_gen.grass_layer_thickness_voxels = gd_gen.grass_layer_thickness_voxels
	cpp_gen.dirt_layer_thickness_voxels = gd_gen.dirt_layer_thickness_voxels
	cpp_gen.beach_y_threshold = gd_gen.beach_y_threshold
	cpp_gen.marble_jitter_block_size = gd_gen.marble_jitter_block_size
	cpp_gen.marble_jitter_seed = gd_gen.marble_jitter_seed
	cpp_gen.marble_rare_threshold = gd_gen.marble_rare_threshold
	cpp_gen.marble_dark_threshold = gd_gen.marble_dark_threshold
	cpp_gen.marble_jitter_max_lod = gd_gen.marble_jitter_max_lod
	# Phase 4a config — explicit (C++ has no autoloaded VoxelMaterialRegistry).
	cpp_gen.bedrock_material_id = BEDROCK_MATERIAL_ID
	cpp_gen.world_floor_voxel_y = WORLD_FLOOR_VOXEL_Y
	cpp_gen.sea_level_voxels = SEA_LEVEL_VOXELS

	var mismatches_type: int = 0
	var mismatches_data5: int = 0
	var voxels_checked: int = 0
	var dumped: int = 0
	var chunks_with_mismatches: int = 0

	for origin in test_origins:
		var gd_buf := VoxelBuffer.new()
		gd_buf.create(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
		gd_gen._generate_block(gd_buf, origin, TEST_LOD)

		var cpp_buf := VoxelBuffer.new()
		cpp_buf.create(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
		cpp_gen.generate_block_into_buffer(cpp_buf, origin, TEST_LOD)

		var chunk_mismatched: bool = false
		for cx in CHUNK_SIZE:
			for cy in CHUNK_SIZE:
				for cz in CHUNK_SIZE:
					var gd_t: int = gd_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_TYPE)
					var cpp_t: int = cpp_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_TYPE)
					var gd_w: int = gd_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_DATA5)
					var cpp_w: int = cpp_buf.get_voxel(cx, cy, cz, VoxelBuffer.CHANNEL_DATA5)
					voxels_checked += 1
					if gd_t != cpp_t:
						mismatches_type += 1
						chunk_mismatched = true
						if dumped < VERBOSE_MISMATCH_CAP:
							var wx: int = origin.x + cx
							var wy: int = origin.y + cy
							var wz: int = origin.z + cz
							printerr("[Parity] LOD0 TYPE mismatch at origin=%s local=(%d,%d,%d) world=(%d,%d,%d): gd=%d cpp=%d" % [
								origin, cx, cy, cz, wx, wy, wz, gd_t, cpp_t
							])
							dumped += 1
					if gd_w != cpp_w:
						mismatches_data5 += 1
						chunk_mismatched = true
						if dumped < VERBOSE_MISMATCH_CAP:
							var wx2: int = origin.x + cx
							var wy2: int = origin.y + cy
							var wz2: int = origin.z + cz
							printerr("[Parity] LOD0 DATA5 mismatch at origin=%s local=(%d,%d,%d) world=(%d,%d,%d): gd=0x%02X cpp=0x%02X" % [
								origin, cx, cy, cz, wx2, wy2, wz2, gd_w, cpp_w
							])
							dumped += 1
		if chunk_mismatched:
			chunks_with_mismatches += 1

	var total: int = mismatches_type + mismatches_data5
	if total == 0:
		print("[Parity] chunk_bytes_lod0: %d / %d voxels (TYPE+DATA5) match bit-for-bit across %d chunks (LOD 0)." % [
			voxels_checked * 2, voxels_checked * 2, test_origins.size()
		])
	else:
		printerr("[Parity] chunk_bytes_lod0: TYPE=%d, DATA5=%d mismatches across %d / %d chunks." % [
			mismatches_type, mismatches_data5, chunks_with_mismatches, test_origins.size()
		])

	return total


func _unused(_x) -> void:
	pass
