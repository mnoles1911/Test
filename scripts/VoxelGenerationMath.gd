class_name VoxelGenerationMath extends RefCounted
# VoxelGenerationMath — pure math helpers for the voxel generation
# pipeline. RefCounted with `class_name`, so callers use it like a
# namespace: `VoxelGenerationMath.hash3(x, y, z)`. NOT an autoload.
#
# Lives outside the generator scripts so multiple generators
# (CopperIslesHeightmapGenerator, CubicHeightmapGenerator, future
# biome generators) can share the same deterministic primitives —
# stone-jitter, snow-line jitter, ore-noise lookups, disk-anchor
# placement all need the same hash and the same cliff math, and
# we don't want any one of those to drift.


# =============================================================
# DETERMINISTIC 3D HASH
# =============================================================

static func hash3(x: int, y: int, z: int, seed: int = 0) -> float:
	# Triple-prime XOR hash, lifted from the per-voxel jitter pattern
	# in CubicHeightmapGenerator. Returns a deterministic float in
	# [0, 1] for any integer (x, y, z, seed) tuple — same input always
	# yields the same output, across loads and across machines.
	#
	# Used by Tier 3 (marble jitter), Tier 4 (ore vein placement),
	# Tier 5 (Worley disk anchors), and Tier 6 (cliff outcrop dice
	# rolls). Different callers pass different `seed` values so
	# their hash fields don't collide.
	#
	# Worker-thread safe (pure integer + float math, no SceneTree).
	var h: int = ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 39916801)) & 0xFFFFFF
	return float(h) / float(0xFFFFFF)


# =============================================================
# CLIFF SLOPE MATH
# =============================================================

static func cliff_threshold_for_angle_voxels(angle_degrees: float, sample_distance_voxels: int) -> int:
	# Convert a desired slope angle into the voxel-Y-drop threshold
	# the cliff rule should use, given the horizontal sample distance.
	#
	# Math: tan(angle) = vertical_drop / horizontal_distance, so
	# `min_drop = tan(angle) × distance`. ceil() rounds up so an angle
	# of "exactly threshold" still triggers.
	#
	# At the canonical 10 vox/m scale and sample_distance=10 voxels (=1 m):
	#   45° → 6, 50° → 8, 55° → 9, 60° → 11, 65° → 13, 70° → 17, 75° → 23
	#
	# Callers usually hardcode the threshold in the generator
	# (Inspector-tunable) but use this helper to compute the default
	# from "60° slope" rather than memorising the table.
	return int(ceil(tan(deg_to_rad(angle_degrees)) * float(sample_distance_voxels)))
