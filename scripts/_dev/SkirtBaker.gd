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

const QUAD_SIZE_M: float = 12.0
# 12 m quads give finer silhouettes than 16 m without exploding tri
# count. At 8 km × 8 km = 666² = ~444k quads = ~890k tris — heavier
# than before but a one-time bake and a static draw, so the GPU
# laughs. If perf hurts later we can mix-resolution (8 m inner,
# 24 m outer ring).

const Y_OFFSET_DOWN_M: float = 0.1
# Tiny offset below true ground to break z-fighting against the live
# LOD0 voxel mesh. 0.1 m is enough; bigger creates a visible seam.

const SLOPE_TO_ROCK_THRESHOLD: float = 0.35
# Rise/run threshold above which we shift the vertex colour toward
# rock. ~0.35 ≈ 19° slope. Plays nicely against the elevation
# gradient: low elevation + steep = rocky cliff (gets rock-brown
# even though the elevation lerp would have placed forest there).

const SLOPE_TO_ROCK_BLEND_RANGE: float = 0.30
# Soft-shoulder beyond the threshold. Slopes from threshold to
# threshold + this value lerp from "elevation colour" to "full rock";
# steeper than that pegs at full rock. Avoids hard transitions on
# slopes that grade smoothly.


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
			# Vertex colours — alpha=1 always (defeats stray-alpha
			# rendering bugs). Per-biome palette + slope-aware shift +
			# multi-octave noise jitter. Three layered effects:
			#
			#   1. Elevation gradient (4 stops): water → sand →
			#      forest → rock → snow as you climb.
			#   2. Slope shift: steep faces (>~19°) lean toward rock,
			#      regardless of elevation. Cliffs read as cliffs even
			#      where the elevation says "should be forest".
			#   3. Two-octave noise: a coarse low-frequency band gives
			#      visual patches (different parts of a slope tinted
			#      slightly differently), plus a high-frequency band
			#      breaks up uniform colour at fine resolution.
			#      Hash-based so re-bakes from the same heightmap are
			#      bit-identical.
			var hash_lo: int = ((voxel_x * 374761393) ^ (voxel_z * 668265263)) & 0xFFFF
			var hash_hi: int = ((voxel_x * 73856093) ^ (voxel_z * 83492791)) & 0xFFFF
			var jitter_coarse: float = (float(hash_lo) / 65535.0 - 0.5) * 0.10  # ±5 % brightness
			var jitter_fine: float   = (float(hash_hi) / 65535.0 - 0.5) * 0.06  # ±3 % brightness
			var jitter: float = jitter_coarse + jitter_fine

			# Pick the elevation-band colour first (no slope adjust yet).
			var c_elev: Color
			if ground_voxels <= sea_level_voxels:
				# Below sea — deep stone tone, mostly hidden by water.
				c_elev = Color(0.18, 0.22, 0.28, 1.0)
			elif ground_voxels <= beach_y:
				c_elev = Color(0.82, 0.74, 0.52, 1.0)  # sand
			else:
				# Forest → rock → snowcap over 4500 vox (750 m world).
				var elev_above_beach: int = ground_voxels - beach_y
				var t1: float = clampf(float(elev_above_beach) / 4500.0, 0.0, 1.0)
				var c_lo: Color = Color(0.32, 0.48, 0.22, 1.0)   # deeper forest green
				var c_mid: Color = Color(0.55, 0.50, 0.42, 1.0)  # rock brown
				var c_hi: Color = Color(0.88, 0.90, 0.93, 1.0)   # snowcap, slightly cooler
				if t1 < 0.5:
					c_elev = c_lo.lerp(c_mid, t1 * 2.0)
				else:
					c_elev = c_mid.lerp(c_hi, (t1 - 0.5) * 2.0)

			# Slope-based shift toward rock. Need to peek at four
			# neighbours to compute height gradient. Out-of-bounds
			# neighbours return the centre value (zero gradient).
			var slope: float = _compute_slope_at(
				generator, voxel_x, voxel_z, voxels_per_metre,
			)
			var rock_color: Color = Color(0.50, 0.46, 0.40, 1.0)
			var slope_t: float = clampf(
				(slope - SLOPE_TO_ROCK_THRESHOLD) / SLOPE_TO_ROCK_BLEND_RANGE,
				0.0, 1.0,
			)
			var c: Color = c_elev.lerp(rock_color, slope_t)

			# Apply jitter, clamp, force alpha=1.
			c.r = clampf(c.r + jitter, 0.0, 1.0)
			c.g = clampf(c.g + jitter, 0.0, 1.0)
			c.b = clampf(c.b + jitter, 0.0, 1.0)
			c.a = 1.0
			colors[xi + zi * verts_x] = c

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

	# Quad indices (two triangles per quad). Winding order matters:
	# Godot considers triangles "front-facing" when their vertices
	# wind COUNTER-CLOCKWISE viewed from the side the normal points
	# toward. For an upward-pointing terrain surface, that means CCW
	# when viewed from ABOVE (camera at +Y looking down).
	#
	# Mapping vertex indices: i00 = (xi,zi), i10 = (xi+1,zi),
	# i01 = (xi,zi+1), i11 = (xi+1,zi+1). In world space with X right
	# and Z forward (away from camera looking down), going
	# i00 → i10 → i01 traces:
	#   (0,0) → (1,0) → (0,1)   = right, then back-left = CCW ✓
	# The previous winding (i00 → i01 → i10) was CW from above, so
	# CULL_BACK + camera-from-above hid every face — that's why the
	# skirt looked transparent before we hacked CULL_DISABLED on. With
	# the corrected winding below CULL_BACK works properly and lighting
	# is no longer washed-out by double-sided rendering.
	for zi in quads_z:
		for xi in quads_x:
			var i00: int = xi + zi * verts_x
			var i10: int = (xi + 1) + zi * verts_x
			var i01: int = xi + (zi + 1) * verts_x
			var i11: int = (xi + 1) + (zi + 1) * verts_x
			# Triangle 1: bottom-right-near corner
			indices.append(i00)
			indices.append(i10)
			indices.append(i01)
			# Triangle 2: top-left-far corner
			indices.append(i10)
			indices.append(i11)
			indices.append(i01)

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


# Compute the local slope (rise / run, dimensionless) at a voxel
# coordinate by sampling 4 neighbours from the generator. Used by
# the colour pipeline to shift steep faces toward rock regardless of
# elevation.
#
# Sample distance = 1 voxel. Slope = max-rise-over-run across the
# four cardinal neighbours. World-Y rises map to height differences
# of `vox_diff / voxels_per_metre`, run is one voxel = `1 /
# voxels_per_metre`. The two cancel — slope is just absolute
# vox_diff.
static func _compute_slope_at(
	generator: Resource,
	voxel_x: int,
	voxel_z: int,
	_voxels_per_metre: float,
) -> float:
	var h: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z)
	var hx_p: int = generator.get_ground_voxel_y_at(voxel_x + 1, voxel_z)
	var hx_m: int = generator.get_ground_voxel_y_at(voxel_x - 1, voxel_z)
	var hz_p: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z + 1)
	var hz_m: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z - 1)
	# Max absolute neighbour difference in voxels = max rise per
	# 1-voxel run = slope.
	var max_diff: int = 0
	for d in [absi(hx_p - h), absi(hx_m - h), absi(hz_p - h), absi(hz_m - h)]:
		if d > max_diff:
			max_diff = d
	return float(max_diff)
