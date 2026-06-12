@tool
extends Object
class_name _WaterFlowReferenceDoNotUse

# WaterFlowReference — pure GD reference for WaterFlowCpp.scan_settle_region.
# Used by the headless `water_flow` selector to validate byte-for-set parity.
#
# Mirrors the inner loop of WaterFlowManager._process_water_settle,
# stripped of SceneTree access: no _bucket_push, no settle bookkeeping —
# just "for each cell in the settle Y-stripe, is it an AIR cell touching
# SOURCE water within range?".
#
# W2 (finite-water track, design/WATER_FINITE_SIM_PLAN.md): the settle
# scan is part of the OCEAN subsystem, so a hit now requires the
# touching water to be INFINITE (source) water. Finite water (DATA5
# level set, source bit clear) must NOT trigger a re-fill — otherwise
# digging next to a player-placed pond would conjure infinite ocean
# water out of it. Legacy water (TYPE is water but DATA5 == 0 — the
# generator ocean before DATA5 backfill, pre-Stage-6 saves) counts as
# source, matching the codec's documented conservative default.
#
# Returns the same Dictionary shape as the C++ port:
#   hits:    PackedInt32Array stream [x, y, z, ...]
#   next_y:  int
#   scanned: int

const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

const NEIGHBOURS_6: Array = [
	Vector3i(0, -1, 0),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(0, 1, 0),
]


static func scan_settle_region(
		buf,
		region_min: Vector3i,
		region_max: Vector3i,
		y_start: int,
		y_end_max: int,
		scan_cap: int,
		player_pos: Vector3,
		active_radius_m: float,
		voxels_per_metre: float,
		pending: Dictionary,
		retry: Dictionary,
		fill_max_retry: int) -> Dictionary:
	var out: Dictionary = {}
	var hits: PackedInt32Array = PackedInt32Array()
	var scanned: int = 0
	var next_y: int = y_start

	# Bulk read CHANNEL_TYPE + CHANNEL_DATA5 bytes — Y-fastest layout,
	# bytes-per-voxel derived per channel (depths can differ).
	var buf_size: Vector3i = buf.get_size()
	var ch_bytes: PackedByteArray = buf.get_channel_as_byte_array(VoxelBuffer.CHANNEL_TYPE)
	var d5_bytes: PackedByteArray = buf.get_channel_as_byte_array(VoxelBuffer.CHANNEL_DATA5)
	var sx: int = buf_size.x
	var sy: int = buf_size.y
	var sz: int = buf_size.z
	var voxel_count: int = sx * sy * sz
	@warning_ignore("integer_division")
	var bpv: int = ch_bytes.size() / voxel_count if voxel_count > 0 else 1
	@warning_ignore("integer_division")
	var bpv5: int = d5_bytes.size() / voxel_count if voxel_count > 0 else 1
	var voxel_size_m: float = 1.0 / voxels_per_metre if voxels_per_metre > 0.0 else (1.0 / 6.0)
	var radius_sq: float = active_radius_m * active_radius_m

	var y: int = y_start
	while y <= y_end_max and scanned < scan_cap:
		for x in range(region_min.x, region_max.x + 1):
			for z in range(region_min.z, region_max.z + 1):
				scanned += 1
				var wx: float = (float(x) + 0.5) * voxel_size_m
				var wy: float = (float(y) + 0.5) * voxel_size_m
				var wz: float = (float(z) + 0.5) * voxel_size_m
				var dx: float = wx - player_pos.x
				var dy: float = wy - player_pos.y
				var dz: float = wz - player_pos.z
				if dx * dx + dy * dy + dz * dz > radius_sq:
					continue
				var p: Vector3i = Vector3i(x, y, z)
				if pending.has(p):
					continue
				if retry.has(p) and int(retry[p]) >= fill_max_retry:
					continue
				var t: int = _buf_get(ch_bytes, sx, sy, sz, bpv,
					x - region_min.x, y - region_min.y, z - region_min.z)
				if t != 0:
					continue
				var touches: bool = false
				for off in NEIGHBOURS_6:
					var bx: int = (x + off.x) - region_min.x
					var by: int = (y + off.y) - region_min.y
					var bz: int = (z + off.z) - region_min.z
					var nt: int = _buf_get(ch_bytes, sx, sy, sz, bpv, bx, by, bz)
					if nt < 0:
						continue
					if not WaterMaterial.is_water_type(nt):
						continue
					# W2 source gate: only INFINITE water feeds the
					# settle re-fill. DATA5 == 0 on a water TYPE is the
					# legacy case and conservatively counts as source.
					var nd5: int = _buf_get(d5_bytes, sx, sy, sz, bpv5, bx, by, bz)
					if nd5 == 0 or WaterByteCodec.is_source(nd5):
						touches = true
						break
				if touches:
					hits.append(x)
					hits.append(y)
					hits.append(z)
		y += 1
		next_y = y
		if scanned >= scan_cap:
			break

	out["hits"] = hits
	out["next_y"] = next_y
	out["scanned"] = scanned
	return out


# Returns the low byte of voxel (bx, by, bz) in buffer-local coords, or
# -1 if the coord is out of buffer (treat as solid for is_water purposes).
static func _buf_get(ch_bytes: PackedByteArray, sx: int, sy: int, sz: int, bpv: int,
		bx: int, by: int, bz: int) -> int:
	if bx < 0 or by < 0 or bz < 0 or bx >= sx or by >= sy or bz >= sz:
		return -1
	var idx: int = (by + bx * sy + bz * sx * sy) * bpv
	return ch_bytes[idx] & 0xFF
