@tool
extends Object
class_name _EmissiveReferenceDoNotUse

# EmissiveReference — pure GD reference for EmissiveLightManager's
# _scan_region inner loop (the per-voxel classification + air-neighbour
# gate). Used by the headless `emissive` selector to validate
# EmissiveLightCpp.scan_region.
#
# Mirrors the per-voxel logic in scripts/EmissiveLightManager.gd
# (_scan_region, _has_air_neighbor, _cell_of). The autoload's own
# diff-against-existing-state + OmniLight3D streaming stays in
# EmissiveLightManager — that's GD-only work touching the scene tree.

# Returns a Dictionary with the same key set as EmissiveLightCpp.scan_region:
#   now_lit: PackedInt32Array stream [g_x, g_y, g_z, mat_id, ...]
#       Every emissive voxel exposed to in-buffer air. World voxel-grid
#       coords (min_v + local).
#   affected_cells: PackedInt32Array stream [c_x, c_y, c_z, ...]
#       Deduplicated coarse-grid cells (negatives-safe floor-div) any
#       now_lit voxel falls into.
static func scan_region(buf, min_v: Vector3i, side: Vector3i,
		emissive_ids: PackedInt32Array, cell_size_voxels: int) -> Dictionary:
	var cell: int = cell_size_voxels if cell_size_voxels >= 1 else 1
	var sx: int = side.x
	var sy: int = side.y
	var sz: int = side.z

	var emissive_set: Dictionary = {}
	for id in emissive_ids:
		emissive_set[id] = true

	# Read CHANNEL_TYPE for the whole region into a flat int array — the
	# air-neighbour test needs random access and a single buffer scan
	# avoids the 6× duplicate reads a naive lookup would do.
	var sxsy: int = sx * sy
	var mids: PackedInt32Array = PackedInt32Array()
	mids.resize(sx * sy * sz)
	for x in range(sx):
		for y in range(sy):
			for z in range(sz):
				var idx: int = x + y * sx + z * sxsy
				mids[idx] = buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE) & 0xFF

	var now_lit: PackedInt32Array = PackedInt32Array()
	var affected_set: Dictionary = {}
	for x in range(sx):
		for y in range(sy):
			for z in range(sz):
				var idx: int = x + y * sx + z * sxsy
				var mid: int = mids[idx]
				if mid == 0:
					continue
				if not emissive_set.has(mid):
					continue
				var has_air: bool = false
				if x + 1 < sx and mids[idx + 1] == 0:
					has_air = true
				elif x - 1 >= 0 and mids[idx - 1] == 0:
					has_air = true
				elif y + 1 < sy and mids[idx + sx] == 0:
					has_air = true
				elif y - 1 >= 0 and mids[idx - sx] == 0:
					has_air = true
				elif z + 1 < sz and mids[idx + sxsy] == 0:
					has_air = true
				elif z - 1 >= 0 and mids[idx - sxsy] == 0:
					has_air = true
				if not has_air:
					continue
				var gx: int = min_v.x + x
				var gy: int = min_v.y + y
				var gz: int = min_v.z + z
				now_lit.append(gx)
				now_lit.append(gy)
				now_lit.append(gz)
				now_lit.append(mid)
				var cx: int = _floor_div(gx, cell)
				var cy: int = _floor_div(gy, cell)
				var cz: int = _floor_div(gz, cell)
				affected_set["%d,%d,%d" % [cx, cy, cz]] = Vector3i(cx, cy, cz)

	var affected_cells: PackedInt32Array = PackedInt32Array()
	for key in affected_set.keys():
		var c: Vector3i = affected_set[key]
		affected_cells.append(c.x)
		affected_cells.append(c.y)
		affected_cells.append(c.z)

	var out: Dictionary = {}
	out["now_lit"] = now_lit
	out["affected_cells"] = affected_cells
	out["phase"] = "ref"
	return out


# Negatives-safe floor division (matches GD floori(g.x / s)).
static func _floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q
