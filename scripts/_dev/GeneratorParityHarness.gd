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


func _run() -> void:
	print("[Parity] ===== GeneratorParityHarness start =====")

	var probe := ParityProbe.new()

	var hash3_mismatches: int = _test_hash3(probe)
	var cliff_mismatches: int = _test_cliff_threshold(probe)
	var total: int = hash3_mismatches + cliff_mismatches

	print("[Parity] =====")
	if total == 0:
		print("[Parity] PASS — all checks bit-exact (hash3 over %d tuples + cliff_threshold sweep)." % HASH3_TUPLE_COUNT)
		print("[Parity] Phase 1 gate satisfied. Safe to proceed to Phase 2.")
	else:
		printerr("[Parity] FAIL — %d mismatches total (hash3=%d, cliff=%d). Phase 1 gate NOT satisfied." % [total, hash3_mismatches, cliff_mismatches])


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
