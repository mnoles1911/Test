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
# Reverted from 8.0 -> 12.0 on 2026-05-13. The 2026-05-13 Copper
# Isles capture showed 14-19 M primitives per frame; the 2 M-tri
# 8 m skirt was a meaningful slice of that (the original 8 m setting
# generated ~1 M quads = ~2 M tris static-drawn every frame).
# Backing off to 12 m gives ~444 K quads = ~890 K tris -- still
# tight enough that distant peaks read with crisp silhouettes (12 m
# is well within Mira's voxel scale for visual coherence at distance),
# but cuts the skirt's GPU contribution by ~55 %. To go finer-grained
# again (mix-resolution: e.g. 8 m inner ring + 24 m outer ring),
# split the bake_mesh inner loop on radius — non-trivial, do only
# if 12 m silhouettes don't read as crisp enough at peak elevations.
#
# REQUIRES RE-BAKE: changing this constant alone doesn't regenerate
# the skirt -- the .res file at assets/voxel/copper_isles_skirt.res
# was built with the old constant and continues to ship 2 M tris
# until you run the bake. In Godot: F6 scenes/_dev/BakeWorld.tscn,
# click "4. Bake horizon skirt → assets/voxel/copper_isles_skirt.res",
# wait a few seconds, then commit the regenerated .res file.

const Y_OFFSET_DOWN_M: float = 1.5
# Larger offset 2026-05-08 because the previous 0.1 m was insufficient.
# The voxel terrain is stair-stepped (cube voxels), and the skirt's
# flat triangulated surface interpolates BETWEEN voxel ledges. With a
# 0.1 m drop the skirt poked up through some LOD0 cubes on slopes
# (visible as smooth light bands cutting through chunky terrain).
# 1.5 m drop puts the skirt safely below voxel cube tops at the ~16.7 cm
# voxel size — never visible inside the streamed area but still close
# enough to read as "ground" past view_distance where there's no
# voxel mesh to compare to.

const SKIRT_SAMPLE_MIN_NEIGHBOURHOOD: bool = true
# When true, each skirt vertex is positioned at the MIN ground-Y of a
# small neighbourhood around its sample coord, not the centre value.
# Eliminates the stair-step pokethrough on slopes — the flat skirt
# triangle ends up at or below every voxel top in that area, never
# above. Costs four extra heightmap samples per vertex (cheap; only
# hurts the bake-time scan, not runtime).

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

const SNOW_LINE_LATITUDE_OFFSET_M: float = 200.0
# How far the snow line slides between the south edge of the bake
# region (Z = -2500 m, snow line raised by this amount → less snow)
# and the north edge (Z = +2500 m, snow line lowered by this amount
# → more snow). 200 m gives a subtle but readable N/S asymmetry
# from the spawn vantage. Bump to 400 m for a more dramatic
# Skyrim-style "northern peaks are colder" gradient. Set to 0 to
# disable latitude shifting entirely.

const CLIFF_THRESHOLD_M: float = 20.0
# When two neighbouring grid vertices differ in height by more than
# this, we splice a vertical wall of geometry into the gap so the
# coastline reads as a sheer drop instead of a smoothly-ramped
# slope. 20 m at 8 m quad spacing is a 2.5:1 slope — anything
# steeper than that is rendered as a cliff face.

const CLIFF_COLOR: Color = Color(0.55, 0.52, 0.48, 1.0)
# Exposed-rock tone for cliff faces, regardless of what the
# elevation band on top says. Slightly warmer than the marble-grey
# `rock_color` because cliff faces in this region are mineral-stained
# wave-eroded stone, not the bare marble of the summit caps.


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
			# When SKIRT_SAMPLE_MIN_NEIGHBOURHOOD is true, sample 4
			# additional points around the vertex (one quad-size
			# step in each cardinal direction) and take the MIN.
			# Result: the flat skirt triangle that connects this
			# vertex to its neighbours sits at or below every voxel
			# cube-top in the area — no pokethrough through LOD0.
			if SKIRT_SAMPLE_MIN_NEIGHBOURHOOD:
				var step: int = int(QUAD_SIZE_M * voxels_per_metre)
				var n0: int = generator.get_ground_voxel_y_at(voxel_x + step, voxel_z)
				var n1: int = generator.get_ground_voxel_y_at(voxel_x - step, voxel_z)
				var n2: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z + step)
				var n3: int = generator.get_ground_voxel_y_at(voxel_x, voxel_z - step)
				ground_voxels = mini(ground_voxels, mini(mini(n0, n1), mini(n2, n3)))
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

			# Palette is keyed to Copper Isles lore — see
			# `lore/copper_isles/GEOGRAPHY.md`: wave-eroded marble massifs,
			# white-marble summit outcroppings above ~350 m treeline,
			# weathered coastal woodland (dwarf-oak / salt-pine / sea-laurel)
			# below it, salt-bleached coastal sand at the shore. The
			# elevation-band stops below match those notes — anything
			# tweaked here should round-trip back to that doc.
			# Pick the elevation-band colour first (no slope adjust yet).
			var c_elev: Color
			if ground_voxels <= sea_level_voxels:
				# Below sea — submerged stone, slightly cooler/darker
				# than the old grey-blue so it doesn't read as ice
				# under the water shader.
				c_elev = Color(0.14, 0.18, 0.22, 1.0)
			elif ground_voxels <= beach_y:
				# Salt-bleached coastal sand — paler and cooler than
				# warm tropical sand, matches the windswept-island read.
				c_elev = Color(0.78, 0.72, 0.58, 1.0)
			else:
				# Forest → rock → snowcap. Snow band offset is applied
				# inside snow_line_offset_voxels (latitude-dependent —
				# see Task 5 below); base range still 4500 vox (750 m).
				var elev_above_beach: int = ground_voxels - beach_y
				# Slide the snow band based on world Z so northern
				# (high-Z) peaks ice over before southern peaks of
				# the same elevation. Solgrade sits north of the
				# Copper Isles → north reads as colder.
				var latitude_factor: float = clampf(world_z / 2500.0, -1.0, 1.0)
				var snow_line_offset_voxels: int = int(round(
					-latitude_factor * SNOW_LINE_LATITUDE_OFFSET_M * voxels_per_metre,
				))
				var t1: float = clampf(
					float(elev_above_beach + snow_line_offset_voxels) / 4500.0,
					0.0, 1.0,
				)
				var c_lo: Color = Color(0.26, 0.36, 0.20, 1.0)   # weathered coastal woodland (desaturated, salt-spray)
				var c_mid: Color = Color(0.62, 0.60, 0.56, 1.0)  # marble-grey base rock
				var c_hi: Color = Color(0.93, 0.94, 0.95, 1.0)   # bare marble peaks (slightly brighter than snow)
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
			# Marble-grey to match the new `c_mid` band — a steep
			# forested slope shifts toward the same exposed-marble tone
			# as a mid-elevation cliff would naturally show.
			var rock_color: Color = Color(0.60, 0.58, 0.54, 1.0)
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

	# Cliff-face geometry. Where two adjacent grid vertices differ in
	# height by more than CLIFF_THRESHOLD_M, the smooth ramp triangle
	# that connects them reads as an unconvincing slope at distance.
	# We splice in a short vertical wall (4 verts / 2 tris per cliff
	# edge) so coastlines and ridge drops read as actual cliffs in
	# the silhouette.
	#
	# Each interior grid edge is shared by two quads, so we dedupe
	# via a sorted-vertex-index dictionary key — without this, every
	# interior cliff face would be drawn twice (once per side) which
	# is wasteful and can cause z-fighting on the wall surface.
	var visited_edges: Dictionary = {}
	var cliff_verts := PackedVector3Array()
	var cliff_normals := PackedVector3Array()
	var cliff_colors := PackedColorArray()
	var cliff_indices := PackedInt32Array()
	for zi in quads_z:
		for xi in quads_x:
			var i00: int = xi + zi * verts_x
			var i10: int = (xi + 1) + zi * verts_x
			var i01: int = xi + (zi + 1) * verts_x
			var i11: int = (xi + 1) + (zi + 1) * verts_x
			# 4 edges of this quad: south, east, north, west.
			_maybe_add_cliff_edge(visited_edges, vertices, heights, i00, i10,
				cliff_verts, cliff_normals, cliff_colors, cliff_indices)
			_maybe_add_cliff_edge(visited_edges, vertices, heights, i10, i11,
				cliff_verts, cliff_normals, cliff_colors, cliff_indices)
			_maybe_add_cliff_edge(visited_edges, vertices, heights, i11, i01,
				cliff_verts, cliff_normals, cliff_colors, cliff_indices)
			_maybe_add_cliff_edge(visited_edges, vertices, heights, i01, i00,
				cliff_verts, cliff_normals, cliff_colors, cliff_indices)

	# Splice the cliff data onto the end of the main arrays. Indices
	# in cliff_indices are local to cliff_verts, so offset them by
	# the current grid-vertex count before merging.
	var cliff_base: int = vertices.size()
	if cliff_verts.size() > 0:
		vertices.append_array(cliff_verts)
		normals.append_array(cliff_normals)
		vert_colors.append_array(cliff_colors)
		for ci in cliff_indices.size():
			cliff_indices[ci] += cliff_base
		indices.append_array(cliff_indices)

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
	@warning_ignore("integer_division")
	var cliff_tri_count: int = cliff_indices.size() / 3
	print("[SkirtBaker] Baked %d × %d quad skirt (%d tris, of which %d are cliff faces) over %.0fm × %.0fm" % [
		quads_x, quads_z, tri_count, cliff_tri_count, width, depth,
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


# Cliff helper. For a single grid edge between two existing vertex
# slots (i_a, i_b), check whether the height delta exceeds
# CLIFF_THRESHOLD_M; if it does, append a 4-vertex / 2-triangle
# vertical wall into the cliff_* arrays.
#
# Dedupes via `visited` so each interior edge (shared by two adjacent
# quads) is only processed once. The dictionary key is a Vector2i of
# the two vertex indices in sorted order — same key from either quad's
# perspective.
#
# Wall geometry: a vertical rectangle in the XZ plane of the edge,
# spanning Y from min(h_a, h_b) up to max(h_a, h_b). The 4 corners
# share the two edge endpoints' XZ coords but pair-up at the high
# and low Y. Two triangles form the rectangular face.
#
# Wall normal: perpendicular to the edge in the XZ plane. The runtime
# material uses CULL_DISABLED, so both sides of the wall render —
# which side is "outward" matters only for lighting, not visibility.
# We pick the right-hand perpendicular (rotating the edge direction
# 90° clockwise as viewed from above). That keeps lighting consistent
# across the wall regardless of view angle.
#
# Cliff vertices land in their own buffers (`cliff_verts` etc.) and
# get spliced onto the main arrays after this loop completes; indices
# returned here are LOCAL to cliff_verts and the caller offsets them
# by `vertices.size()` before merging.
static func _maybe_add_cliff_edge(
	visited: Dictionary,
	grid_vertices: PackedVector3Array,
	heights_arr: PackedFloat32Array,
	i_a: int,
	i_b: int,
	cliff_verts: PackedVector3Array,
	cliff_normals: PackedVector3Array,
	cliff_colors: PackedColorArray,
	cliff_indices: PackedInt32Array,
) -> void:
	var key: Vector2i = Vector2i(mini(i_a, i_b), maxi(i_a, i_b))
	if visited.has(key):
		return
	visited[key] = true
	var h_a: float = heights_arr[i_a]
	var h_b: float = heights_arr[i_b]
	if absf(h_a - h_b) < CLIFF_THRESHOLD_M:
		return
	var pos_a: Vector3 = grid_vertices[i_a]
	var pos_b: Vector3 = grid_vertices[i_b]
	var y_high: float = maxf(h_a, h_b)
	var y_low: float = minf(h_a, h_b)
	# Outward normal — rotate the edge direction 90° clockwise in XZ.
	var edge_xz: Vector2 = Vector2(pos_b.x - pos_a.x, pos_b.z - pos_a.z)
	if edge_xz.length_squared() < 0.0001:
		return
	edge_xz = edge_xz.normalized()
	var wall_normal: Vector3 = Vector3(edge_xz.y, 0.0, -edge_xz.x)
	# 4 wall corners. Remember: pos_a / pos_b carry their original
	# Y values, but here we override to the high/low Y of the pair
	# so the wall is a true vertical rectangle.
	var v0: Vector3 = Vector3(pos_a.x, y_high, pos_a.z)
	var v1: Vector3 = Vector3(pos_b.x, y_high, pos_b.z)
	var v2: Vector3 = Vector3(pos_a.x, y_low, pos_a.z)
	var v3: Vector3 = Vector3(pos_b.x, y_low, pos_b.z)
	var base: int = cliff_verts.size()
	cliff_verts.append(v0)
	cliff_verts.append(v1)
	cliff_verts.append(v2)
	cliff_verts.append(v3)
	for _i in 4:
		cliff_normals.append(wall_normal)
		cliff_colors.append(CLIFF_COLOR)
	# Two triangles. CULL_DISABLED in HorizonSkirt.gd means winding
	# direction doesn't gate visibility, but we still wind CCW from
	# the wall_normal side so that any future switch back to
	# CULL_BACK behaves sensibly.
	cliff_indices.append(base + 0)
	cliff_indices.append(base + 1)
	cliff_indices.append(base + 2)
	cliff_indices.append(base + 1)
	cliff_indices.append(base + 3)
	cliff_indices.append(base + 2)
