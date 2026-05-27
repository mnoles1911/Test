@tool
extends Object
class_name _EmissiveBakedReferenceDoNotUse

# EmissiveBakedReference — pure GD reference for the Phase J baked
# emissive-light volume bake. Used by the headless `baked_light`
# selector to validate EmissiveBakedCpp.bake_light_volume byte-exact.
#
# Algorithm (mirror of emissive_baked_cpp.cpp):
#
#   1. Pre-compute per-cell "open" by reading CHANNEL_TYPE at the centre
#      voxel of each cell. Cells whose centre is solid (or out-of-buffer)
#      are closed — the BFS never crosses through them.
#
#   2. For each emitter (g_x, g_y, g_z, r, g, b, energy_byte):
#        - Translate world voxel coord to cell-local via cell_size.
#        - If outside grid: skip.
#        - Compute seed colour: (r * energy / 255) per channel, clamped 0..255.
#        - Deposit seed colour at emitter cell (max-blend) regardless of
#          whether the cell is open (the emitter voxel itself always glows).
#        - BFS through OPEN neighbours only (6-connected). FIFO queue,
#          neighbour iteration order +x/-x/+y/-y/+z/-z so both impls hit
#          the same "first visit" per cell.
#        - Per step: colour = (colour * falloff_q12) >> 12 (integer truncate).
#          Stop a path when max(channel) drops below 1 OR step >= max_steps.
#        - First visit's colour is max-blended into the output (shortest path
#          from THIS emitter wins; later paths can't darken it).
#
#   3. Across emitters, channel-wise max-blend keeps the brightest source per cell.
#
# Output is N^3 * 4 bytes (RGBA8, A unused for now). Default volume:
# N=64, K=4 -> 256-voxel cube ~42 m, 1 MB.

const NEIGHBOURS_6: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func bake_light_volume(
		buf,
		volume_origin_v: Vector3i,
		cell_size_voxels: int,
		cells_per_axis: int,
		emitters: PackedInt32Array,
		max_steps: int,
		falloff_q12: int) -> PackedByteArray:
	var n: int = clampi(cells_per_axis, 1, 256)
	var k: int = max(cell_size_voxels, 1)
	var steps_cap: int = clampi(max_steps, 1, n)
	var falloff: int = clampi(falloff_q12, 1, 4096)

	var n2: int = n * n
	var n3: int = n2 * n
	var out: PackedByteArray = PackedByteArray()
	out.resize(n3 * 4)

	# --- Pre-compute open[]: cell's centre voxel must be air. ---
	# Centre voxel of cell (cx,cy,cz) at buffer-local
	#   (cx*K + K/2, cy*K + K/2, cz*K + K/2).
	#
	# Bulk read CHANNEL_TYPE in one call — Zylann's get_channel_as_byte_array
	# returns the whole channel as a contiguous PackedByteArray. One Variant
	# crossing instead of N^3 per-cell calls in production.
	#
	# Layout: Zylann packs voxels Y-FASTEST (linear byte index =
	# (y + x*sy + z*sx*sy) * bytes_per_voxel — confirmed by 2026-05-27
	# probe). bytes_per_voxel is derived from byte_count / voxel_count so
	# the same code works at 8-bit (production CHANNEL_TYPE) and 16-bit
	# (Zylann default). Material id is always the LOW byte (offset 0
	# within the voxel) since mat_ids are < 256.
	var open: PackedByteArray = PackedByteArray()
	open.resize(n3)
	var buf_size: Vector3i = buf.get_size()
	var ch_bytes: PackedByteArray = buf.get_channel_as_byte_array(VoxelBuffer.CHANNEL_TYPE)
	var sx: int = buf_size.x
	var sy: int = buf_size.y
	var sz: int = buf_size.z
	var voxel_count: int = sx * sy * sz
	@warning_ignore("integer_division")
	var bpv: int = ch_bytes.size() / voxel_count if voxel_count > 0 else 1
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
				# Y-fastest linear index, low byte = mat_id.
				var byte_idx: int = (by + bx * sy + bz * sx * sy) * bpv
				open[idx] = 1 if ch_bytes[byte_idx] == 0 else 0

	# --- Per-emitter BFS, max-blend into out[]. ---
	@warning_ignore("integer_division")
	var emitter_count: int = emitters.size() / 7
	for i in range(emitter_count):
		var base: int = i * 7
		var gx: int = emitters[base]
		var gy: int = emitters[base + 1]
		var gz: int = emitters[base + 2]
		var er: int = emitters[base + 3]
		var eg: int = emitters[base + 4]
		var eb: int = emitters[base + 5]
		var energy: int = emitters[base + 6]

		# World voxel coord -> cell-local. Use floor division so negative
		# inputs map cleanly (rare but possible — the volume can be
		# centred at a negative origin).
		var dx: int = gx - volume_origin_v.x
		var dy: int = gy - volume_origin_v.y
		var dz: int = gz - volume_origin_v.z
		var cx0: int = _floor_div(dx, k)
		var cy0: int = _floor_div(dy, k)
		var cz0: int = _floor_div(dz, k)
		if cx0 < 0 or cy0 < 0 or cz0 < 0 or cx0 >= n or cy0 >= n or cz0 >= n:
			continue

		# Seed colour = (channel * energy / 255), clamped 0..255.
		var sr: int = clampi((er * energy) / 255, 0, 255)
		var sg: int = clampi((eg * energy) / 255, 0, 255)
		var sb: int = clampi((eb * energy) / 255, 0, 255)
		if sr == 0 and sg == 0 and sb == 0:
			continue

		var seed_idx: int = cx0 + cy0 * n + cz0 * n2
		_max_blend(out, seed_idx, sr, sg, sb)

		# BFS — FIFO queue. Each entry: [cx, cy, cz, r, g, b, step].
		var queue: Array = []
		queue.append([cx0, cy0, cz0, sr, sg, sb, 0])
		var visited: PackedByteArray = PackedByteArray()
		visited.resize(n3)
		visited[seed_idx] = 1
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
