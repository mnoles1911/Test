@tool
extends Object
class_name _EmissiveBakedReferenceDoNotUse

# EmissiveBakedReference — pure GD reference for the Phase J baked
# emissive-light volume bake. Used by the headless `baked_light`
# selector to validate EmissiveBakedCpp.bake_light_volume byte-exact.
#
# Same algorithm shape as emissive_baked_cpp.cpp:
#
#   1. Pre-compute per-cell open[] (centre voxel is air).
#   2. Single pass over the bulk channel bytes — for each non-air voxel,
#      look up its emission colour + energy in a 256-entry table.
#      energy==0 means "not emissive, skip". When the air-neighbour
#      filter is on, only voxels with at least one face-neighbour of
#      air emit (the gate that stops buried copper from lighting its
#      own cell — the bug the v1 ship had).
#   3. Seed cell + BFS through open[] cells, FIFO queue, neighbour
#      order +x/-x/+y/-y/+z/-z, Q12 fixed-point per-step falloff.
#   4. Channel-wise max-blend across emitters.

const NEIGHBOURS_6: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


# Returns Dictionary-shape match with EmissiveBakedCpp.bake_light_volume:
# a flat PackedByteArray of N^3 * 4 bytes (RGBA8).
static func bake_light_volume(
		buf,
		volume_origin_v: Vector3i,
		cell_size_voxels: int,
		cells_per_axis: int,
		mat_color_table: PackedByteArray,
		air_neighbor_filter: bool,
		max_steps: int,
		falloff_q12: int) -> PackedByteArray:
	var _origin_unused: Vector3i = volume_origin_v  # parity-only signature mirror
	var n: int = clampi(cells_per_axis, 1, 256)
	var k: int = max(cell_size_voxels, 1)
	var steps_cap: int = clampi(max_steps, 1, n)
	var falloff: int = clampi(falloff_q12, 1, 4096)
	if mat_color_table.size() < 256 * 4:
		return PackedByteArray()

	var n2: int = n * n
	var n3: int = n2 * n
	var out: PackedByteArray = PackedByteArray()
	out.resize(n3 * 4)

	var buf_size: Vector3i = buf.get_size()
	var ch_bytes: PackedByteArray = buf.get_channel_as_byte_array(VoxelBuffer.CHANNEL_TYPE)
	var sx: int = buf_size.x
	var sy: int = buf_size.y
	var sz: int = buf_size.z
	var voxel_count: int = sx * sy * sz
	if voxel_count <= 0:
		return out
	@warning_ignore("integer_division")
	var bpv: int = ch_bytes.size() / voxel_count
	if bpv <= 0:
		return out

	# --- open[] ----------------------------------------------------------
	var open: PackedByteArray = PackedByteArray()
	open.resize(n3)
	var half_k: int = k / 2
	for cz in range(n):
		var bz: int = cz * k + half_k
		var z_in: bool = bz >= 0 and bz < sz
		for cy in range(n):
			var by: int = cy * k + half_k
			var y_in: bool = by >= 0 and by < sy
			for cx in range(n):
				var bx: int = cx * k + half_k
				var idx: int = cx + cy * n + cz * n2
				if not y_in or not z_in or bx < 0 or bx >= sx:
					open[idx] = 0
					continue
				var byte_idx: int = (by + bx * sy + bz * sx * sy) * bpv
				open[idx] = 1 if ch_bytes[byte_idx] == 0 else 0

	# --- Discover + BFS ---------------------------------------------------
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(n3)

	for z in range(sz):
		for x in range(sx):
			var row_base: int = (x * sy + z * sx * sy) * bpv
			for y in range(sy):
				var b: int = ch_bytes[row_base + y * bpv] & 0xFF
				if b == 0:
					continue
				var entry_off: int = b * 4
				var energy: int = mat_color_table[entry_off + 3]
				if energy == 0:
					continue
				if air_neighbor_filter:
					var exposed: bool = false
					if _buf_at(ch_bytes, sx, sy, sz, bpv, x + 1, y, z) == 0:
						exposed = true
					elif _buf_at(ch_bytes, sx, sy, sz, bpv, x - 1, y, z) == 0:
						exposed = true
					elif _buf_at(ch_bytes, sx, sy, sz, bpv, x, y + 1, z) == 0:
						exposed = true
					elif _buf_at(ch_bytes, sx, sy, sz, bpv, x, y - 1, z) == 0:
						exposed = true
					elif _buf_at(ch_bytes, sx, sy, sz, bpv, x, y, z + 1) == 0:
						exposed = true
					elif _buf_at(ch_bytes, sx, sy, sz, bpv, x, y, z - 1) == 0:
						exposed = true
					if not exposed:
						continue
				var cx0: int = _floor_div(x, k)
				var cy0: int = _floor_div(y, k)
				var cz0: int = _floor_div(z, k)
				if cx0 < 0 or cy0 < 0 or cz0 < 0 or cx0 >= n or cy0 >= n or cz0 >= n:
					continue
				var sr: int = clampi((mat_color_table[entry_off + 0] * energy) / 255, 0, 255)
				var sg: int = clampi((mat_color_table[entry_off + 1] * energy) / 255, 0, 255)
				var sb: int = clampi((mat_color_table[entry_off + 2] * energy) / 255, 0, 255)
				if sr == 0 and sg == 0 and sb == 0:
					continue
				var seed_idx: int = cx0 + cy0 * n + cz0 * n2
				_max_blend(out, seed_idx, sr, sg, sb)
				# Per-emitter visited reset.
				for vi in range(n3):
					visited[vi] = 0
				visited[seed_idx] = 1
				var queue: Array = [[cx0, cy0, cz0, sr, sg, sb, 0]]
				var head: int = 0
				while head < queue.size():
					var e: Array = queue[head]
					head += 1
					var step: int = e[6]
					if step >= steps_cap:
						continue
					var nr: int = (e[3] * falloff) >> 12
					var ng: int = (e[4] * falloff) >> 12
					var nb: int = (e[5] * falloff) >> 12
					if nr < 1 and ng < 1 and nb < 1:
						continue
					for off in NEIGHBOURS_6:
						var ncx: int = e[0] + off.x
						var ncy: int = e[1] + off.y
						var ncz: int = e[2] + off.z
						if ncx < 0 or ncy < 0 or ncz < 0 or ncx >= n or ncy >= n or ncz >= n:
							continue
						var nidx: int = ncx + ncy * n + ncz * n2
						if visited[nidx] != 0:
							continue
						if open[nidx] == 0:
							continue
						visited[nidx] = 1
						_max_blend(out, nidx, nr, ng, nb)
						queue.append([ncx, ncy, ncz, nr, ng, nb, step + 1])

	return out


static func _buf_at(ch_bytes: PackedByteArray, sx: int, sy: int, sz: int, bpv: int,
		bx: int, by: int, bz: int) -> int:
	if bx < 0 or by < 0 or bz < 0 or bx >= sx or by >= sy or bz >= sz:
		return -1
	return ch_bytes[(by + bx * sy + bz * sx * sy) * bpv] & 0xFF


static func _max_blend(out: PackedByteArray, cell_idx: int, r: int, g: int, b: int) -> void:
	var base: int = cell_idx * 4
	if out[base] < r: out[base] = r
	if out[base + 1] < g: out[base + 1] = g
	if out[base + 2] < b: out[base + 2] = b
	var max_chan: int = max(r, max(g, b))
	if out[base + 3] < max_chan: out[base + 3] = max_chan


static func _floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q
