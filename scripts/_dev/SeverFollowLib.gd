@tool
extends Object
class_name _SeverFollowLibDoNotUse

# SeverFollowLib — the pure BFS core of the tree-sever follow-up
# (voxel-physics PR 6; see design/3D_VOxEL_MIGRATION note + the plan in
# the PR description).
#
# The problem in plain English: VoxelGravityManager's analysis bubble
# is small (max ~8 m side), so chopping a tall tree at the base only
# "sees" the first metre or two of trunk — the tree falls as a series
# of salami slices, one bubble-sized cluster per cascade scan, frames
# apart. This library lets the gravity manager FOLLOW the severed
# solids UPWARD past the bubble's roof in one bounded extension box, so
# the whole tree detaches as ONE falling cluster.
#
# Pure + headless-testable: operates on a VoxelBuffer snapshot (one
# bulk tool.copy by the caller), no SceneTree, no autoloads. Gated by
# the headless `sever` selector.
#
# CONSERVATIVE BY DESIGN — when in doubt, return "abort" and the
# caller keeps today's salami behaviour (correct, just less pretty):
#   touched_side — the extension grew to the box's side walls; it may
#                  be laterally connected to anchored terrain (an arch
#                  or overhang), so felling it could rip up ground we
#                  never proved was severed.
#   touched_top  — the tree is taller than the follow cap.
#   over budget  — caller's max_voxels exhausted.

const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

const _FACES_6: Array = [
	Vector3i(0, -1, 0), Vector3i(0, 1, 0),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func continue_bfs(
		buf,                       # VoxelBuffer — CHANNEL_TYPE snapshot of the extension box
		ext_min: Vector3i,         # absolute voxel coord of the buffer's (0,0,0)
		seeds: Array,              # absolute Vector3i positions to start from (just above the bubble roof)
		max_voxels: int) -> Dictionary:
	# Flood 6-connected SOLID voxels (non-air, non-water) inside the
	# snapshot, starting from the seed cells. Returns:
	#   voxels:       Dictionary[Vector3i abs -> int packed TYPE value]
	#   touched_side: bool — reached the box's X/Z walls (abort signal)
	#   touched_top:  bool — reached the box's top Y (abort signal)
	var out_voxels: Dictionary = {}
	var touched_side: bool = false
	var touched_top: bool = false

	var size: Vector3i = buf.get_size()
	var visited: Dictionary = {}
	var queue: Array[Vector3i] = []
	for s_v in seeds:
		var s_abs: Vector3i = s_v
		var s_loc: Vector3i = s_abs - ext_min
		if not _in_box(s_loc, size) or visited.has(s_loc):
			continue
		visited[s_loc] = true
		queue.append(s_loc)

	while not queue.is_empty():
		var loc: Vector3i = queue.pop_back()
		var t: int = buf.get_voxel(loc.x, loc.y, loc.z, VoxelBuffer.CHANNEL_TYPE)
		if t == 0:
			continue   # air — nothing to carry
		if WaterMaterial.is_water_type(t & 0xFF):
			continue   # water never rides a falling cluster
		# Solid. Edge checks BEFORE accepting — an edge hit poisons the
		# whole extension (conservative abort), so flag and keep going
		# only long enough for the caller to see the flag.
		if loc.x == 0 or loc.x == size.x - 1 or loc.z == 0 or loc.z == size.z - 1:
			touched_side = true
			break
		if loc.y == size.y - 1:
			touched_top = true
			break
		out_voxels[ext_min + loc] = t
		if out_voxels.size() > max_voxels:
			# Over budget — signal via touched_top semantics (caller
			# aborts either way); keep the flag honest though:
			touched_top = true
			break
		for d in _FACES_6:
			var nb: Vector3i = loc + (d as Vector3i)
			if nb.y < 0:
				continue   # never grow back DOWN past the bubble roof
			if not _in_box(nb, size) or visited.has(nb):
				continue
			visited[nb] = true
			queue.append(nb)

	return {
		"voxels": out_voxels,
		"touched_side": touched_side,
		"touched_top": touched_top,
	}


static func _in_box(p: Vector3i, size: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 \
		and p.x < size.x and p.y < size.y and p.z < size.z
