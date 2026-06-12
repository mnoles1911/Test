@tool
extends Object
class_name _TreeReferenceDoNotUse

# TreeReference — pure GD reference for the C++ destructible-tree shape math
# in HeightmapGeneratorBase::resolve_tree. Used by the headless `trees`
# selector to validate determinism + the chunk-seam invariant against the
# C++ generator, the same way BiomeReference validates BiomeFieldCpp.
#
# WHAT THIS IS (plain English): a tree is a PURE FUNCTION of its lattice cell
# (lattice_x, lattice_z), the tree seed, and the biome's tree params at the
# trunk column. No noise, no RNG, no per-chunk state. Because of that, two
# different terrain blocks that both "see" the same tree compute the IDENTICAL
# shape and so emit the IDENTICAL voxels along their shared boundary — that's
# the seam correctness the gate proves. This file re-derives that shape in
# GDScript so the gate can cross-check the C++ output and also build a known
# tree by hand (to test the boundary).
#
# Mirrors HeightmapGeneratorBase::resolve_tree line-for-line. If you change one
# side you MUST change the other and re-run the `trees` gate.
#
# class_name is a tagged do-not-use placeholder so the editor doesn't offer
# the type; the call site preloads by path.

const _HASH := preload("res://scripts/VoxelGenerationMath.gd")
const GRASS_MATERIAL_ID: int = 3


# Resolve the tree at a lattice cell. `cfg` carries the generator-side knobs:
#   { tree_log_id, tree_seed, tree_lattice_voxels, tree_spawn_free_radius_voxels,
#     sea_level_voxels, voxels_per_metre }
# `biome_pick(trunk_x, trunk_z) -> int` returns the surface biome slot (the
# SAME weighted-hash pick the generator uses); `profiles` is the Array of
# pod dicts (BiomeProfile.to_pod_dict); `ground_y(x, z) -> int` returns the
# surface voxel-Y (the SAME compute_ground_y the generator uses).
#
# Returns a Dictionary mirroring TreeInstance:
#   { exists, trunk_x, trunk_z, ground_y, height_vox, trunk_radius,
#     canopy_radius, canopy_center_y, canopy_half_height, shape_salt }
static func resolve_tree(lattice_x: int, lattice_z: int, cfg: Dictionary,
		profiles: Array, biome_pick: Callable, ground_y_fn: Callable) -> Dictionary:
	var none := {"exists": false}
	if int(cfg.get("tree_log_id", 0)) == 0:
		return none
	if profiles.is_empty():
		return none
	var grid: int = maxi(int(cfg.get("tree_lattice_voxels", 80)), 1)
	var seed: int = int(cfg.get("tree_seed", 4242))

	# Jittered trunk position inside the cell (salts 1, 2).
	var jx: float = _HASH.hash3(lattice_x, 1, lattice_z, seed)
	var jz: float = _HASH.hash3(lattice_x, 2, lattice_z, seed)
	var trunk_x: int = lattice_x * grid + int(jx * float(grid))
	var trunk_z: int = lattice_z * grid + int(jz * float(grid))

	# Spawn-free disc around origin.
	var r0: int = int(cfg.get("tree_spawn_free_radius_voxels", 60))
	if r0 > 0 and (trunk_x * trunk_x + trunk_z * trunk_z) <= r0 * r0:
		return none

	# Biome at the trunk column → its tree params.
	var surf: int = int(biome_pick.call(trunk_x, trunk_z))
	if surf < 0 or surf >= profiles.size():
		return none
	var bp: Dictionary = profiles[surf]
	var tree_density: float = float(bp.get("tree_density", 0.0))
	if tree_density <= 0.0:
		return none

	# Existence roll (salt 0).
	var exist: float = _HASH.hash3(lattice_x, 0, lattice_z, seed)
	if exist >= tree_density:
		return none

	var gy: int = int(ground_y_fn.call(trunk_x, trunk_z))
	var sea: int = int(cfg.get("sea_level_voxels", 120))
	if gy <= sea:
		return none
	if int(bp.get("top_material_id", 3)) != GRASS_MATERIAL_ID:
		return none

	# Species params (salts 3, 4, 5).
	var h_t: float = _HASH.hash3(lattice_x, 3, lattice_z, seed)
	var tr_t: float = _HASH.hash3(lattice_x, 4, lattice_z, seed)
	var cr_t: float = _HASH.hash3(lattice_x, 5, lattice_z, seed)

	var vpm: float = float(cfg.get("voxels_per_metre", 10.0))
	var hmin: float = float(bp.get("tree_height_min_m", 8.0))
	var hmax: float = float(bp.get("tree_height_max_m", 14.0))
	var height_m: float = hmin + h_t * (hmax - hmin)
	var height_vox: int = maxi(int(height_m * vpm), 1)

	var trmin: float = float(bp.get("tree_trunk_radius_min_vox", 3.0))
	var trmax: float = float(bp.get("tree_trunk_radius_max_vox", 5.0))
	var trunk_radius: int = maxi(int(trmin + tr_t * (trmax - trmin) + 0.5), 1)

	var crmin: float = float(bp.get("tree_canopy_radius_min_vox", 15.0))
	var crmax: float = float(bp.get("tree_canopy_radius_max_vox", 25.0))
	var canopy_radius: int = maxi(int(crmin + cr_t * (crmax - crmin) + 0.5), 1)

	# Crown wraps the upper half of the tree (mirrors resolve_tree exactly):
	# bottom at ~45% of tree height, top ~8% above the trunk tip, half-extent
	# never thinner than the horizontal radius.
	var trunk_top_y: int = gy + height_vox
	var crown_bottom: int = gy + int(height_vox * 0.45)
	var crown_top: int = trunk_top_y + int(height_vox * 0.08)
	@warning_ignore("integer_division")
	var canopy_half_height: int = (crown_top - crown_bottom) / 2
	if canopy_half_height < canopy_radius:
		canopy_half_height = canopy_radius
	if canopy_half_height < 1:
		canopy_half_height = 1
	var canopy_center_y: int = crown_bottom + canopy_half_height

	var shape_salt: int = (seed ^ 0x5151) if _HASH.hash3(lattice_x, 6, lattice_z, seed) > 0.5 else (seed ^ 0x2727)

	return {
		"exists": true,
		"trunk_x": trunk_x,
		"trunk_z": trunk_z,
		"ground_y": gy,
		"height_vox": height_vox,
		"trunk_radius": trunk_radius,
		"canopy_radius": canopy_radius,
		"canopy_center_y": canopy_center_y,
		"canopy_half_height": canopy_half_height,
		"shape_salt": shape_salt,
	}


# Voxel id this tree puts at world (wx, wy, wz), or 0 for "leave as terrain".
# Mirrors the per-voxel stamp test in generate_block_into_buffer's tree pass
# (trunk square column + eroded canopy ellipsoid). Used by the seam check to
# compare the tree's footprint independent of which block computed it.
static func tree_voxel_at(tree: Dictionary, wx: int, wy: int, wz: int,
		log_id: int, leaves_id: int) -> int:
	if not bool(tree.get("exists", false)):
		return 0
	var gy: int = int(tree["ground_y"])
	if wy <= gy:
		return 0
	var tx: int = int(tree["trunk_x"])
	var tz: int = int(tree["trunk_z"])
	var ddx: int = wx - tx
	var ddz: int = wz - tz
	var trunk_radius: int = int(tree["trunk_radius"])
	var height_vox: int = int(tree["height_vox"])
	var in_trunk_xz: bool = (ddx >= -trunk_radius and ddx <= trunk_radius
			and ddz >= -trunk_radius and ddz <= trunk_radius)
	if in_trunk_xz and wy >= gy + 1 and wy <= gy + height_vox:
		return log_id
	if leaves_id == 0:
		return 0
	var canopy_radius: int = int(tree["canopy_radius"])
	var canopy_center_y: int = int(tree["canopy_center_y"])
	var canopy_half_height: int = int(tree["canopy_half_height"])
	var ddy: int = wy - canopy_center_y
	var rx: float = float(canopy_radius)
	var ry: float = float(canopy_half_height)
	var canopy_xz_sq: int = ddx * ddx + ddz * ddz
	var norm: float = float(canopy_xz_sq) / (rx * rx) + float(ddy * ddy) / (ry * ry)
	if norm > 1.0:
		return 0
	if norm > 0.55:
		var e: float = _HASH.hash3(wx, wy, wz, int(tree["shape_salt"]))
		var erode: float = (norm - 0.55) / 0.45 * 0.5
		if e < erode:
			return 0
	return leaves_id
