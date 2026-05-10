class_name VoxelClusterBuilder
extends RefCounted
# VoxelClusterBuilder — pure-function utilities for turning a falling-voxel
# cluster (a Dictionary of voxel-grid positions → packed RGBA colors) into
# the data a FallingVoxelCluster RigidBody3D needs:
#
#   - an ArrayMesh (one quad per visible cube face, vertex-coloured)
#   - the cluster's AABB in cluster-local meters (drives BoxShape3D size)
#   - the cluster's voxel-weighted centroid (drives custom centre of mass)
#   - the cluster's voxel-count-weighted world centroid (drives spawn pos)
#
# Why a separate file: the mesh-build is the most testable piece of the
# whole gravity system — a bug in flood-fill produces wrong cluster
# membership, but a bug in mesh build produces *visibly* wrong geometry.
# Splitting it out lets us drive it from a one-shot test scene with a
# hand-coded Dictionary, no terrain, no flood-fill.
#
# All methods are static. No state.
#
# Coordinate convention used throughout this file:
#   - voxel-grid coords (Vector3i): integer per-voxel positions, exactly
#     as VoxelTool returns them
#   - cluster-local meters (Vector3): meters relative to the cluster's
#     local origin (which is the cluster's voxel-AABB minimum corner,
#     converted to meters and shifted so the cluster's centroid sits
#     at local-origin Vector3.ZERO)
#
# Reference: design/3D_VOXEL_MIGRATION.md → "Voxel Gravity"


const VOXEL_SIZE_M: float = 1.0 / 6.0
# Edge length of one voxel in meters. Matches VOXELS_PER_METER = 6 from
# VoxelEditManager. Hardcoded here to keep this file dependency-free
# (no autoload calls inside a static utility).


# ---------------------------------------------------------------
# Public — mesh build
# ---------------------------------------------------------------

static func build_cluster_mesh(
	voxels: Dictionary,
	centre_offset_m: Vector3,
) -> ArrayMesh:
	# Build a single-surface ArrayMesh from the cluster.
	#
	# voxels: Dictionary keyed by Vector3i (voxel-grid positions),
	#         value is int (material_id from CHANNEL_TYPE — same
	#         format VoxelTool.get_voxel returns post-v13).
	# centre_offset_m: a Vector3 (meters) subtracted from each voxel
	#         position so the cluster's centroid sits at the mesh's
	#         local origin. This is what makes the RigidBody3D rotate
	#         around its true center of mass instead of one corner.
	#
	# Per-face culling: only emit a quad for a voxel face if the
	# neighbour voxel on that face is NOT in the cluster. This is the
	# same "no-interior-faces" trick VoxelMesherBlocky uses internally.
	# A 4096-voxel solid cube has 4096*6 = 24576 faces naive but only
	# the ~1500 boundary faces actually need rendering — ~94% saving.
	#
	# Returns an ArrayMesh with exactly one surface (PRIMITIVE_TRIANGLES).
	# Empty dict → empty mesh (no surfaces).

	if voxels.is_empty():
		return ArrayMesh.new()

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# Index of the next vertex to be appended. SurfaceTool would manage
	# this for us, but doing it by hand is faster for our scale and
	# avoids the SurfaceTool de-dupe pass we don't need (every quad
	# has 4 unique verts here).
	var next_idx: int = 0

	# Six face directions, each with the four corner offsets that make
	# up the quad on that face (in cube-local coords, before scale and
	# voxel position are applied). Order is CCW when viewed from outside
	# so the face normal points outward.
	#
	# Index layout for each face:
	#   0 -- 1
	#   |    |
	#   3 -- 2
	# Triangles: (0,1,2) and (0,2,3) — both CCW from outside.
	const FACES := [
		# +X (east) — neighbour offset (1, 0, 0)
		{
			"neighbour": Vector3i(1, 0, 0),
			"normal": Vector3(1, 0, 0),
			"corners": [
				Vector3(1, 1, 0), Vector3(1, 1, 1),
				Vector3(1, 0, 1), Vector3(1, 0, 0),
			],
		},
		# -X (west)
		{
			"neighbour": Vector3i(-1, 0, 0),
			"normal": Vector3(-1, 0, 0),
			"corners": [
				Vector3(0, 1, 1), Vector3(0, 1, 0),
				Vector3(0, 0, 0), Vector3(0, 0, 1),
			],
		},
		# +Y (top)
		{
			"neighbour": Vector3i(0, 1, 0),
			"normal": Vector3(0, 1, 0),
			"corners": [
				Vector3(0, 1, 1), Vector3(1, 1, 1),
				Vector3(1, 1, 0), Vector3(0, 1, 0),
			],
		},
		# -Y (bottom)
		{
			"neighbour": Vector3i(0, -1, 0),
			"normal": Vector3(0, -1, 0),
			"corners": [
				Vector3(0, 0, 0), Vector3(1, 0, 0),
				Vector3(1, 0, 1), Vector3(0, 0, 1),
			],
		},
		# +Z (south)
		{
			"neighbour": Vector3i(0, 0, 1),
			"normal": Vector3(0, 0, 1),
			"corners": [
				Vector3(1, 1, 1), Vector3(0, 1, 1),
				Vector3(0, 0, 1), Vector3(1, 0, 1),
			],
		},
		# -Z (north)
		{
			"neighbour": Vector3i(0, 0, -1),
			"normal": Vector3(0, 0, -1),
			"corners": [
				Vector3(0, 1, 0), Vector3(1, 1, 0),
				Vector3(1, 0, 0), Vector3(0, 0, 0),
			],
		},
	]

	# Look up the registry once — falling-cluster vertex colors come
	# from the per-material color_high field rather than packed RGBA.
	# Pre-v13 this script unpacked color from the alpha-byte-encoded
	# voxel value. Post-migration, the voxel value IS just the
	# material_id, so we lift the registry once outside the inner loop
	# and tint each voxel's vertices using that material's chosen
	# representative colour.
	var registry := Engine.get_main_loop().root.get_node_or_null("VoxelMaterialRegistry") if Engine.get_main_loop() else null
	for v_pos_v in voxels.keys():
		var v_pos: Vector3i = v_pos_v
		var mat_id: int = int(voxels[v_pos]) & 0xFF
		var color: Color = _color_for_material_id(mat_id, registry)
		# Cube origin in cluster-local meters, then shifted so the
		# whole cluster pivots around its centre of mass.
		var origin_m: Vector3 = (Vector3(v_pos) * VOXEL_SIZE_M) - centre_offset_m

		for face in FACES:
			# Skip faces shared with another cluster voxel.
			if voxels.has(v_pos + (face["neighbour"] as Vector3i)):
				continue
			var corners: Array = face["corners"]
			var normal: Vector3 = face["normal"]
			# Append 4 verts.
			for c in corners:
				verts.append(origin_m + (c as Vector3) * VOXEL_SIZE_M)
				normals.append(normal)
				colors.append(color)
			# Two triangles — (0,1,2) and (0,2,3) relative to next_idx.
			indices.append(next_idx + 0)
			indices.append(next_idx + 1)
			indices.append(next_idx + 2)
			indices.append(next_idx + 0)
			indices.append(next_idx + 2)
			indices.append(next_idx + 3)
			next_idx += 4

	if verts.is_empty():
		return ArrayMesh.new()

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------
# Public — geometry queries
# ---------------------------------------------------------------

static func compute_local_aabb(voxels: Dictionary) -> AABB:
	# Returns the cluster's bounding box in CLUSTER-LOCAL meters
	# (i.e., after the centre_offset has been subtracted, matching the
	# mesh's local space). The AABB's position field is the offset to
	# the box-min corner; AABB.size is the box extent.
	#
	# For a uniform cluster (centroid at geometric centre) the AABB is
	# symmetric around the local origin: position = -size/2.
	# For an L-shaped cluster (centroid offset from geometric centre),
	# the AABB is shifted: the BoxShape3D must use both `size` AND a
	# matching translation on the CollisionShape3D so it covers the
	# mesh's actual extent rather than centring on the rigid body.
	#
	# Empty cluster → AABB(ZERO, ZERO).
	if voxels.is_empty():
		return AABB()
	var min_v: Vector3i = voxels.keys()[0]
	var max_v: Vector3i = min_v
	for v_pos_v in voxels.keys():
		var v: Vector3i = v_pos_v
		min_v.x = mini(min_v.x, v.x)
		min_v.y = mini(min_v.y, v.y)
		min_v.z = mini(min_v.z, v.z)
		max_v.x = maxi(max_v.x, v.x)
		max_v.y = maxi(max_v.y, v.y)
		max_v.z = maxi(max_v.z, v.z)
	# +1 because a voxel at (5,5,5) actually occupies (5..6, 5..6, 5..6).
	var size_m: Vector3 = Vector3(max_v - min_v + Vector3i.ONE) * VOXEL_SIZE_M
	# Compute the local-space offset to the AABB-min corner. The mesh
	# build subtracts the absolute centroid from each absolute voxel
	# position, so the AABB-min corner ends up at:
	#   (min_v * voxel_size) - centroid_world
	var centroid_world: Vector3 = compute_centroid_world(voxels)
	var min_local: Vector3 = Vector3(min_v) * VOXEL_SIZE_M - centroid_world
	return AABB(min_local, size_m)


static func compute_centroid_voxels(voxels: Dictionary) -> Vector3:
	# Voxel-count-weighted centroid in voxel-grid coords (returned as
	# Vector3 for fractional precision). Each voxel contributes its
	# centre point (v + 0.5).
	#
	# This is the cluster's TRUE centre of mass assuming uniform voxel
	# density, which is the right answer for chunky-cube terrain. A
	# tree with a heavy crown on top will get a CoM near the crown,
	# making it tip and accelerate properly.
	if voxels.is_empty():
		return Vector3.ZERO
	var sum: Vector3 = Vector3.ZERO
	for v_pos_v in voxels.keys():
		var v: Vector3i = v_pos_v
		sum += Vector3(v) + Vector3(0.5, 0.5, 0.5)
	return sum / float(voxels.size())


static func compute_centroid_world(voxels: Dictionary) -> Vector3:
	# Same centroid as compute_centroid_voxels but converted to world
	# meters. This is where the cluster RigidBody3D should be spawned
	# so its visual matches where the voxels used to live in the world.
	return compute_centroid_voxels(voxels) * VOXEL_SIZE_M


static func compute_centre_offset(voxels: Dictionary) -> Vector3:
	# The offset (in absolute world meters) that the mesh build subtracts
	# from each voxel position to map ABSOLUTE voxel-grid coords into
	# CLUSTER-LOCAL coords with the cluster's centroid at the origin.
	#
	# Math: the snapshot's keys are absolute voxel-grid positions (set
	# by VoxelGravityManager._handle_cluster). For a cluster placed at
	# global_position = centroid_world, a vertex with local position L
	# lands at world position centroid_world + L. We want each voxel's
	# corner vertex to land at its original world position
	# (v_pos * voxel_size). Solving for L:
	#
	#   L = v_pos * voxel_size - centroid_world
	#
	# So the offset to subtract IS centroid_world. Same value as
	# compute_centroid_world; this function is just the named slot the
	# mesh-build expects, kept separate for readability.
	return compute_centroid_world(voxels)


# ---------------------------------------------------------------
# Public — material
# ---------------------------------------------------------------

static var _shared_material: StandardMaterial3D = null

static func get_shared_material() -> StandardMaterial3D:
	# Single shared material for every falling cluster. Vertex colors
	# carry the per-voxel RGBA, so one material works for every cluster
	# regardless of what colour its voxels are. Cached to avoid
	# allocating a new StandardMaterial3D for every cluster spawned.
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.roughness = 1.0
		_shared_material.metallic = 0.0
	return _shared_material


# ---------------------------------------------------------------
# Internal — color packing
# ---------------------------------------------------------------

static func _color_for_material_id(mat_id: int, registry) -> Color:
	# Look up the representative vertex color for a falling cluster
	# voxel of this material. Returns color_high from the material
	# .tres if the registry is available, otherwise a magenta debug
	# colour so missing materials are visible.
	#
	# Why color_high (and not color_low or a lerp)? Falling clusters
	# are airborne fragments of the surface — visually closer to the
	# top-of-band tint than the deep-band tint. Picking one constant
	# also keeps the cluster tinted uniformly, which reads better
	# during the brief seconds it spends tumbling than a per-voxel
	# height-lerped colour would.
	if registry == null:
		return Color(1.0, 0.0, 1.0)
	var mat = registry.get_by_id(mat_id)
	if mat == null:
		return Color(1.0, 0.0, 1.0)
	return mat.color_high


static func _unpack_rgba32(packed: int) -> Color:
	# DEPRECATED — kept only so any out-of-tree code that called this
	# helper compiles. Pre-v13 this decoded the packed RGBA stored in
	# CHANNEL_COLOR. After the VoxelMesherBlocky migration the value
	# is just a material_id integer; there's no RGB to unpack.
	# Returns the legacy decode for callers that still rely on it.
	var r: int = (packed >> 24) & 0xFF
	var g: int = (packed >> 16) & 0xFF
	var b: int = (packed >>  8) & 0xFF
	var a: int =  packed        & 0xFF
	return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)
