extends RefCounted

# FloraMeshBuilder — THE single source of truth for the micro-voxel flora
# cross-quad blade mesh.
#
# WHY THIS FILE EXISTS (plain English):
#   Two layers draw flora blades and they MUST look identical or the seam
#   the far-grass layer exists to hide just turns into a "near blade vs far
#   blade look different" seam:
#     1. The REAL destructible voxel flora (ids 24..26), injected as Zylann
#        VoxelBlockyModelMesh models in World3DBootstrap. Those meshes live
#        in CUBE-LOCAL space (a unit cube = one voxel).
#     2. The far-grass IMPOSTOR (FarGrassManager) — GPU-instanced blades in
#        WORLD space, where a MultiMesh transform is world metres.
#
#   Before this extraction the blade geometry lived only inside
#   World3DBootstrap._build_flora_cross_quad_mesh. Pulling it here lets both
#   layers call the SAME builder, so the cross-quad proportions, the
#   double-sided winding, and the vertex tint are guaranteed to match.
#
# NO class_name (headless-safe, same rule as VoxelScale / FloraMaterial):
# callers preload by path.
#     const FloraMeshBuilder := preload("res://scripts/FloraMeshBuilder.gd")

# Build the two-intersecting-quad "X" blade mesh.
#
# `height_m` / `half_width_m`  — blade size in WORLD METRES (e.g. 0.25 m
#     tall, 0.05 m half-width — the Lay-of-the-Land 10cm look).
# `color`                       — flat vertex tint baked into every vertex.
# `voxels_per_metre`            — VoxelScale.VOXELS_PER_METER (the grid scale).
# `world_space`                 — coordinate space of the OUTPUT mesh:
#     * false (Zylann blocky model): build in CUBE-LOCAL voxel units. A
#       Zylann blocky model lives in a unit cube (0,0,0)..(1,1,1) where 1
#       model-unit = 1 voxel, so sizes are converted metres -> voxels and
#       the blade is centred on the cube and clamped to fit it. This is the
#       exact behaviour the old World3DBootstrap builder had.
#     * true (MultiMesh impostor): build in WORLD METRES, rooted at y=0 and
#       centred on x=z=0, so a MultiMesh world transform places it directly.
#
# Both quads are emitted DOUBLE-SIDED (front + back winding) so the blade
# reads from any camera angle regardless of the material's cull mode.
static func build_cross_quad(
		height_m: float,
		half_width_m: float,
		color: Color,
		voxels_per_metre: float,
		world_space: bool) -> ArrayMesh:
	var h: float
	var hw: float
	var cx: float
	var cz: float
	if world_space:
		# World-metre mesh: real size, rooted at ground (y=0), centred at XZ 0.
		h = maxf(height_m, 0.001)
		hw = maxf(half_width_m, 0.001)
		cx = 0.0
		cz = 0.0
	else:
		# Cube-local (voxel-unit) mesh, matching the legacy bootstrap builder:
		# convert metres -> voxel units and clamp to the unit cube, centred.
		var v_per_m: float = voxels_per_metre
		h = clampf(height_m * v_per_m, 0.1, 1.0)
		hw = clampf(half_width_m * v_per_m, 0.05, 0.5)
		cx = 0.5
		cz = 0.5

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# Append one quad (4 corners, CCW from the front) plus its back-facing
	# twin so the surface is visible from both sides.
	var add_quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		var base: int = verts.size()
		for p in [a, b, c, d]:
			verts.append(p)
			normals.append(n)
			colors.append(color)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		var base2: int = verts.size()
		for p in [d, c, b, a]:
			verts.append(p)
			normals.append(-n)
			colors.append(color)
		indices.append_array([base2, base2 + 1, base2 + 2, base2, base2 + 2, base2 + 3])

	# Quad 1 — diagonal running NE-SW (varies in X and Z together).
	add_quad.call(
		Vector3(cx - hw, 0.0, cz - hw), Vector3(cx + hw, 0.0, cz + hw),
		Vector3(cx + hw, h,  cz + hw), Vector3(cx - hw, h,  cz - hw),
		Vector3(-1, 0, 1).normalized())
	# Quad 2 — diagonal running NW-SE (the other arm of the "X").
	add_quad.call(
		Vector3(cx - hw, 0.0, cz + hw), Vector3(cx + hw, 0.0, cz - hw),
		Vector3(cx + hw, h,  cz - hw), Vector3(cx - hw, h,  cz + hw),
		Vector3(1, 0, 1).normalized())

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
