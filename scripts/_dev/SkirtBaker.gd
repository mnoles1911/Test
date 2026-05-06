class_name SkirtBaker
extends RefCounted
# SkirtBaker — builds a low-LOD terrain mesh covering the entire
# Copper Isles archipelago, saved as a single ArrayMesh resource.
#
# What this is for in plain English:
#
#   Zylann's view_distance is currently 250 m. Past that radius, the
#   player sees the sky cut off the world. For a 5 km map that's a
#   harsh limit — peaks 4 km away are invisible until you walk close.
#
#   The skirt is a single coarse mesh of the whole archipelago, baked
#   once from the EXR. It always renders, no matter where the player
#   stands, so distant peaks are visible at all times. Up close, the
#   real LOD0 voxel mesh draws on top (higher resolution, wins the
#   depth test) so the skirt is invisible inside the streamed area.
#
#   At 64 m × 64 m quad resolution, a 5 km map is ~80 × 80 quads ≈
#   12 800 triangles. Cheap to render even on integrated GPUs.
#
# Used by `WorldBakeController` (button in the BakeWorld UI) and at
# runtime via `scripts/HorizonSkirt.gd` which loads the saved mesh.

const QUAD_SIZE_M: float = 64.0  # one quad per 64 m of world
const Y_OFFSET_DOWN_M: float = 0.5  # render slightly below true ground to avoid z-fighting with LOD0


# Bake the skirt from the given generator + region. Returns an
# ArrayMesh that can be saved via ResourceSaver.save() to a .res file.
#
# generator: the CopperIslesHeightmapGenerator resource (must already
#            have its EXR loaded, since we sample heights via
#            get_ground_voxel_y_at).
# min_xz, max_xz: world-metres bounds (e.g. (-2500, -2500) to (2500, 2500)).
# voxels_per_metre: terrain.transform.scale^-1 (use 6.0 at canonical).
static func bake_mesh(
	generator: Resource,
	min_xz: Vector2,
	max_xz: Vector2,
	voxels_per_metre: float,
) -> ArrayMesh:
	if generator == null or not generator.has_method("get_ground_voxel_y_at"):
		push_error("[SkirtBaker] generator missing or doesn't expose get_ground_voxel_y_at()")
		return null

	var width: float = max_xz.x - min_xz.x
	var depth: float = max_xz.y - min_xz.y
	var quads_x: int = int(ceil(width / QUAD_SIZE_M))
	var quads_z: int = int(ceil(depth / QUAD_SIZE_M))
	var verts_x: int = quads_x + 1
	var verts_z: int = quads_z + 1

	# Pre-sample the height grid so neighbouring quads share corners.
	# heights[xi + zi * verts_x] = world_y for vertex (xi, zi).
	var heights := PackedFloat32Array()
	heights.resize(verts_x * verts_z)
	var colors := PackedColorArray()
	colors.resize(verts_x * verts_z)
	for zi in verts_z:
		for xi in verts_x:
			var world_x: float = min_xz.x + float(xi) * QUAD_SIZE_M
			var world_z: float = min_xz.y + float(zi) * QUAD_SIZE_M
			var voxel_x: int = int(world_x * voxels_per_metre)
			var voxel_z: int = int(world_z * voxels_per_metre)
			var ground_voxels: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z)
			var ground_world_y: float = float(ground_voxels) / voxels_per_metre
			heights[xi + zi * verts_x] = ground_world_y - Y_OFFSET_DOWN_M
			# Vertex colour mirrors the generator's material bands,
			# crudely. Sand below beach line, grass above; stone
			# colouring not represented (skirt only shows top surface).
			# Keeps the skirt visually close to the live LOD0 from
			# distance.
			var sea_level_voxels: int = 0
			if "sea_level_voxels" in generator:
				sea_level_voxels = generator.sea_level_voxels
			var beach_y: int = 12
			if "beach_y_threshold" in generator:
				beach_y = generator.beach_y_threshold
			if ground_voxels <= sea_level_voxels:
				# Below sea level — colour as deep ocean stone (not
				# rendered most of the time because the dynamic water
				# horizon plane covers it; included for completeness).
				colors[xi + zi * verts_x] = Color(0.18, 0.22, 0.28)
			elif ground_voxels <= beach_y:
				colors[xi + zi * verts_x] = Color(0.78, 0.72, 0.50)  # sand
			else:
				# Land. Greener at low elevations, rocker at high.
				var lerp_t: float = clampf(float(ground_voxels - beach_y) / 1000.0, 0.0, 1.0)
				colors[xi + zi * verts_x] = Color(0.30, 0.45, 0.20).lerp(Color(0.55, 0.50, 0.42), lerp_t)

	# Build vertex/index arrays.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var vert_colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(verts_x * verts_z)
	normals.resize(verts_x * verts_z)
	vert_colors.resize(verts_x * verts_z)
	for zi in verts_z:
		for xi in verts_x:
			var i: int = xi + zi * verts_x
			vertices[i] = Vector3(
				min_xz.x + float(xi) * QUAD_SIZE_M,
				heights[i],
				min_xz.y + float(zi) * QUAD_SIZE_M,
			)
			vert_colors[i] = colors[i]
			normals[i] = Vector3.UP  # cheap normal — recomputed below

	# Quad indices (two triangles per quad, CCW winding for upward-
	# facing surface in Godot's right-handed Y-up convention).
	for zi in quads_z:
		for xi in quads_x:
			var i00: int = xi + zi * verts_x
			var i10: int = (xi + 1) + zi * verts_x
			var i01: int = xi + (zi + 1) * verts_x
			var i11: int = (xi + 1) + (zi + 1) * verts_x
			indices.append(i00)
			indices.append(i01)
			indices.append(i10)
			indices.append(i10)
			indices.append(i01)
			indices.append(i11)

	# Compute per-vertex normals from the height field (central
	# differences). Cheap and gives the skirt subtle shading from the
	# directional light.
	for zi in verts_z:
		for xi in verts_x:
			var i: int = xi + zi * verts_x
			var hx0: float = heights[max(xi - 1, 0) + zi * verts_x]
			var hx1: float = heights[min(xi + 1, verts_x - 1) + zi * verts_x]
			var hz0: float = heights[xi + max(zi - 1, 0) * verts_x]
			var hz1: float = heights[xi + min(zi + 1, verts_z - 1) * verts_x]
			var dx: float = (hx1 - hx0) / (2.0 * QUAD_SIZE_M)
			var dz: float = (hz1 - hz0) / (2.0 * QUAD_SIZE_M)
			normals[i] = Vector3(-dx, 1.0, -dz).normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = vert_colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	@warning_ignore("integer_division")
	var tri_count: int = indices.size() / 3
	print("[SkirtBaker] Baked %d × %d quad skirt (%d tris) over %.0fm × %.0fm" % [
		quads_x, quads_z, tri_count, width, depth,
	])
	return mesh
