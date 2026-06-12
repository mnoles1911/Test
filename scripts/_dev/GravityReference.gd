@tool
extends Object
class_name _GravityReferenceDoNotUse

# GravityReference — pure GD reference for VoxelGravityManager's
# _process_bubble inner-loop math. Used by the headless `gravity`
# selector to validate VoxelGravityCpp.analyze_bubble.
#
# All state is passed in by value — no SceneTree, no autoload, no
# VoxelMaterialRegistry / NoEditZoneRegistry. Mirrors lines 326-583 of
# scripts/VoxelGravityManager.gd's _process_bubble (the partition +
# flood-fill + LOOSE column-fall + cluster BFS).
#
# class_name is a tagged-do-not-use placeholder so the editor doesn't
# offer the type in autocomplete; the actual call site uses
# preload("res://scripts/_dev/GravityReference.gd").

# FallBehavior enum mirror (VoxelMaterial.gd). int values are the
# storage representation; reference + C++ agree by integer.
#   NEVER = 0, SOLID = 1, LOOSE = 2, LIQUID = 3, PICKUP_DROP = 4
const FALL_NEVER: int = 0
const FALL_SOLID: int = 1
const FALL_LOOSE: int = 2
const FALL_LIQUID: int = 3
const FALL_PICKUP_DROP: int = 4

const NEIGHBOURS_6: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# R4 flora id range (mirrors scripts/FloraMaterial.gd: 24..26). Flora is
# treated as PASS-THROUGH AIR in the gravity analysis: a grass blade or
# flower must never anchor a structure (so a tree can't "connect" to the
# ground through a blade) and must never be carried in a falling cluster.
# The C++ port (voxel_gravity_cpp.cpp) hardcodes the identical range, so
# the read pass that builds `solids` skips flora on both sides. Kept as a
# literal range (not a FloraMaterial preload) so the cross-language
# contract is a plain constant both sides agree on by value, exactly like
# the FALL_* enum mirror above.
const FLORA_BASE_ID: int = 24
const FLORA_COUNT: int = 3


static func _is_flora_type(type_id: int) -> bool:
	var t: int = type_id & 0xFF
	return t >= FLORA_BASE_ID and t < FLORA_BASE_ID + FLORA_COUNT


# Returns a Dictionary with the same key set as VoxelGravityCpp.analyze_bubble:
#   loose: PackedInt32Array stream [from_x, from_y, from_z, to_x, to_y, to_z, packed, ...]
#   pickup: PackedInt32Array stream [x, y, z, packed, ...]
#   cluster_counts: PackedInt32Array
#   cluster_voxels: PackedInt32Array [x, y, z, packed, ...]
#   bubble_solid_count: int
#   unanchored_cluster_count: int
#
# Args:
#   buf - VoxelBuffer (side x side x side), CHANNEL_TYPE populated
#   side - int
#   fall_table - Dictionary[int, int]: material_id -> FallBehavior int
#   noeditzone_mask - PackedByteArray of side^3 bytes (1 = anchored), or empty
static func analyze_bubble(buf, side: int, fall_table: Dictionary, noeditzone_mask: PackedByteArray) -> Dictionary:
	# --- Read pass: build solids dict.
	# Iterate (x, y, z) outer-to-inner — same as VoxelGravityManager so
	# Dictionary insertion order matches for diagnostic comparison.
	var solids: Dictionary = {}
	for x in range(side):
		for y in range(side):
			for z in range(side):
				var packed: int = buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE)
				if (packed & 0xFF) == 0:
					continue
				if _is_flora_type(packed):
					continue   # R4: flora is pass-through air for gravity —
					           # never anchors, never joins a cluster
				solids[Vector3i(x, y, z)] = packed

	# --- Anchor identification: bottom-face seed + NoEditZone mask.
	var anchored: Dictionary = {}
	var frontier: Array = []
	var has_mask: bool = noeditzone_mask.size() == side * side * side
	for v_pos_v in solids.keys():
		var v: Vector3i = v_pos_v
		var is_anchor: bool = false
		if v.y == 0:
			is_anchor = true
		elif has_mask:
			var idx: int = v.x + v.y * side + v.z * side * side
			if noeditzone_mask[idx] != 0:
				is_anchor = true
		if is_anchor:
			anchored[v] = true
			frontier.append(v)

	# --- Flood-fill anchors through solids (6-connected).
	while not frontier.is_empty():
		var cur: Vector3i = frontier.pop_back()
		for n_off in NEIGHBOURS_6:
			var nbr: Vector3i = cur + (n_off as Vector3i)
			if not solids.has(nbr) or anchored.has(nbr):
				continue
			anchored[nbr] = true
			frontier.append(nbr)

	# --- Partition unanchored by fall_behavior.
	var unanchored_loose: Dictionary = {}
	var unanchored_pickup: Dictionary = {}
	var unanchored_cluster: Dictionary = {}
	for v_pos_v in solids.keys():
		var v: Vector3i = v_pos_v
		if anchored.has(v):
			continue
		var packed: int = solids[v]
		var mat_id: int = packed & 0xFF
		var fall: int = fall_table.get(mat_id, FALL_NEVER)
		if fall == FALL_LOOSE:
			unanchored_loose[v] = packed
		elif fall == FALL_PICKUP_DROP:
			unanchored_pickup[v] = packed
		else:
			unanchored_cluster[v] = packed

	# --- LOOSE column-fall. Deterministic sort by (y, x, z) lex so the
	# reference and C++ process columns in identical order.
	var loose_stream: PackedInt32Array = PackedInt32Array()
	if not unanchored_loose.is_empty():
		var loose_landings: Dictionary = {}
		var sorted_keys: Array = unanchored_loose.keys()
		sorted_keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			if a.y != b.y: return a.y < b.y
			if a.x != b.x: return a.x < b.x
			return a.z < b.z
		)
		for v_pos_v in sorted_keys:
			var v: Vector3i = v_pos_v
			var landing_y: int = v.y
			while landing_y > 0:
				var below: Vector3i = Vector3i(v.x, landing_y - 1, v.z)
				if anchored.has(below) or loose_landings.has(below):
					break
				landing_y -= 1
			if landing_y == v.y:
				continue
			var landing: Vector3i = Vector3i(v.x, landing_y, v.z)
			loose_stream.append(v.x)
			loose_stream.append(v.y)
			loose_stream.append(v.z)
			loose_stream.append(landing.x)
			loose_stream.append(landing.y)
			loose_stream.append(landing.z)
			loose_stream.append(unanchored_loose[v])
			loose_landings[landing] = true

	# --- PICKUP stream (order = solids insertion order = x,y,z lex).
	var pickup_stream: PackedInt32Array = PackedInt32Array()
	for v_pos_v in unanchored_pickup.keys():
		var v: Vector3i = v_pos_v
		pickup_stream.append(v.x)
		pickup_stream.append(v.y)
		pickup_stream.append(v.z)
		pickup_stream.append(unanchored_pickup[v])

	# --- Cluster connected-component BFS. Stack-based (pop_back) to
	# match VoxelGravityManager's queue treatment.
	var visited: Dictionary = {}
	var cluster_counts: PackedInt32Array = PackedInt32Array()
	var cluster_voxels: PackedInt32Array = PackedInt32Array()
	var unanchored_cluster_count: int = 0
	for v_pos_v in unanchored_cluster.keys():
		var seed_pos: Vector3i = v_pos_v
		if visited.has(seed_pos):
			continue
		var queue: Array = [seed_pos]
		visited[seed_pos] = true
		var count: int = 0
		while not queue.is_empty():
			var cur2: Vector3i = queue.pop_back()
			count += 1
			unanchored_cluster_count += 1
			cluster_voxels.append(cur2.x)
			cluster_voxels.append(cur2.y)
			cluster_voxels.append(cur2.z)
			cluster_voxels.append(unanchored_cluster[cur2])
			for n_off2 in NEIGHBOURS_6:
				var nbr2: Vector3i = cur2 + (n_off2 as Vector3i)
				if not unanchored_cluster.has(nbr2) or visited.has(nbr2):
					continue
				visited[nbr2] = true
				queue.append(nbr2)
		cluster_counts.append(count)

	var out: Dictionary = {}
	out["loose"] = loose_stream
	out["pickup"] = pickup_stream
	out["cluster_counts"] = cluster_counts
	out["cluster_voxels"] = cluster_voxels
	out["bubble_solid_count"] = solids.size()
	out["unanchored_cluster_count"] = unanchored_cluster_count
	out["phase"] = "ref"
	return out
