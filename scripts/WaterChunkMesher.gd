extends Node3D
# WaterChunkMesher — emits transparent surface meshes for water cells.
#
# What this does in plain English:
#
# Water cells in WaterFlowManager are pure data — invisible to the
# voxel terrain mesher. This node walks the WaterFlowManager dictionary
# and source regions, and emits one MeshInstance3D per voxel chunk
# that has water in it. The mesh is just a flat top plane (in Phase 2;
# Phases 4+ add partial-height side faces for level < 8 cells).
#
# Each MeshInstance3D shares assets/shaders/water_material.tres so the
# existing sine-sum vertex displacement shader animates every water
# surface uniformly. World-space XZ as the wave domain ensures phase
# alignment across chunk seams.
#
# Lives as a child of WaterFlowManager (autoload). MeshInstance3Ds are
# parented under THIS node so we can free the entire pool by clearing
# our children.
#
# Reference: design/SWIMMING_AND_WATER.md, design/3D_VOXEL_MIGRATION.md


# ============================================================
# Constants
# ============================================================

# Render radius (m) around the player for the per-CHUNK water mesh
# path. This path now only handles per-cell water (player bucket
# placements with potentially varying surface heights). Source
# regions (ocean, lake) are rendered as ONE giant flat plane each
# via _rebuild_source_region_planes — so the radius here doesn't
# constrain ocean visibility, only how far around the player we
# build cell-water meshes.
#
# 64 m is plenty for cell water — buckets place water localized to
# wherever the player is currently editing, well within this radius.
const MESH_RENDER_RADIUS_M: float = 64.0

# Per-frame mesh rebuild budget. Bumped from 2 → 16 because water
# mesh builds are extremely cheap (one subdivided quad per region
# overlap, a few hundred verts max), unlike voxel gravity scans.
# At 2/frame the dirty queue accumulated faster than it drained
# during world load — water was invisible for several minutes
# until the queue caught up.
const MESH_BUILDS_PER_FRAME: int = 16

# Chunk side length in meters — must match VoxelEditManager constants.
# Replicated here so this file doesn't need to call into a private
# helper.
const CHUNK_SIZE_VOXELS: int = 16
const VOXELS_PER_METER: float = 6.0
const CHUNK_SIZE_M: float = float(CHUNK_SIZE_VOXELS) / VOXELS_PER_METER  # ≈ 2.667 m


# ============================================================
# State
# ============================================================

var _meshes: Dictionary = {}
# Vector3i (chunk coord) → MeshInstance3D. One entry per chunk that
# currently has a visible water surface. Chunks freed get removed
# from this dict.

var _dirty_queue: Array = []
# FIFO of chunk coords pending rebuild. Drained at MESH_BUILDS_PER_FRAME
# per frame from _process. Membership tested via _dirty_set (O(1))
# rather than Array.has (O(n)) — the player-movement loop dirty-marks
# tens of thousands of chunks at once and per-call has() lookups would
# blow up to O(n²).

var _dirty_set: Dictionary = {}
# Mirror of _dirty_queue used as a Set for O(1) membership tests.
# Always kept in sync: append → set both, pop_front → erase from set.

var _player_chunk: Vector3i = Vector3i.ZERO
# Chunk the player is currently in. Updated when set_player_chunk is
# called from WaterFlowManager (which itself is updated by Player3D
# each physics frame).

var _shader_material: Material = null
# Cached water_material.tres reference. Loaded lazily on first build.

var _water_flow_manager: Node = null
# Cached parent (WaterFlowManager autoload). Resolved in _ready.

# ONE giant flat plane per source region (ocean, lake) — see
# _rebuild_source_region_planes(). Replaces the per-chunk source-region
# meshing path that used to choke on radius limits and miss most of the
# ocean. Source regions are flat by definition, so a single subdivided
# plane covering the whole AABB is one draw call and renders to the
# horizon. Per-chunk meshing now only handles per-cell water (player
# bucket placements) where each cell may have a different surface
# height.
var _source_region_planes: Array[MeshInstance3D] = []

# Cache for the follow-player position update early-out. _process runs
# every frame but the plane positions are a deterministic function of
# the player's XZ — when the player hasn't moved meaningfully, the
# work is wasted. Re-running the update when player_pos == last is
# noise that adds up every frame even when the player is far above
# water. 0.05 m epsilon (squared = 0.0025) means we re-run on actual
# movement but skip when standing still or doing micro-physics jitter.
const FOLLOW_UPDATE_EPSILON_SQ: float = 0.0025
var _last_follow_pos: Vector3 = Vector3(INF, INF, INF)

# Subdivision target for source-region planes. Each quad is roughly
# this many metres on a side. Smaller = more vertices for finer wave
# displacement; larger = fewer verts for cheaper rendering. 4 m gives
# clean wave detail (waves have ~2 m wavelength so 4 m sampling
# captures crests/troughs reasonably). Capped at 256 subdivisions per
# side total. For our default visible window of 600 m square, that's
# 600/4 = 150 subdivisions — well under the cap.
const SOURCE_REGION_QUAD_SIZE_M: float = 4.0
const SOURCE_REGION_MAX_SUBDIV: int = 256

# Visibility window (m) for source-region water planes. The plane
# follows the player and renders only this far on each axis, then
# is clipped by the source region's actual AABB. Beyond this radius
# the player sees no water — matching how terrain stops at its own
# view distance, so we don't have "infinite water past the terrain
# horizon" weirdness.
#
# Set to roughly 1.5× the terrain view radius (terrain view_distance
# is 1500 voxels ≈ 250 m). 400 m here gives a comfortable margin —
# water reaches a touch past where the last terrain chunks stop, so
# the visible coastline doesn't appear to float over void.
const SOURCE_REGION_VISIBLE_HORIZON_M: float = 150.0


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	_water_flow_manager = get_parent()
	if _water_flow_manager == null:
		push_error("[WaterChunkMesher] no parent (expected WaterFlowManager).")
		return
	# Connect to the water_changed signal so we know which chunks need
	# rebuilding.
	if _water_flow_manager.has_signal("water_changed"):
		_water_flow_manager.connect("water_changed", _on_water_changed)
	# Lazy-load the shared wave shader material. Failure is logged
	# loudly so we don't ship invisible water by accident.
	_shader_material = load("res://assets/shaders/water_material.tres") as Material
	if _shader_material == null:
		push_error("[WaterChunkMesher] failed to load water_material.tres — water surfaces will be invisible.")
	else:
		print("[WaterChunkMesher] water_material.tres loaded: %s" % _shader_material.get_class())

	# Don't pre-build here — WaterFlowManager.add_source_region calls
	# _rebuild_source_region_planes for us whenever a region is
	# registered. That guarantees we always rebuild AFTER the region
	# list is populated, regardless of scene-load timing.


func _process(_delta: float) -> void:
	# Drain up to MESH_BUILDS_PER_FRAME from the queue.
	var built: int = 0
	while built < MESH_BUILDS_PER_FRAME and not _dirty_queue.is_empty():
		var chunk: Vector3i = _dirty_queue.pop_front()
		_dirty_set.erase(chunk)
		_rebuild_chunk(chunk)
		built += 1

	# Reposition source-region planes to follow the player and clip
	# against their AABBs. Skip entirely when the player hasn't
	# moved more than FOLLOW_UPDATE_EPSILON_M since the last call —
	# the plane positions are deterministic from player_pos, so if
	# player_pos didn't change there's nothing to update. Without
	# this early-out the function ran every frame (its work was
	# small but constant noise) AND the diagnostic print fired
	# every 2 s even when the player was standing still or above
	# water.
	if _water_flow_manager != null and "_player_pos" in _water_flow_manager:
		var pp: Vector3 = _water_flow_manager._player_pos
		if pp.distance_squared_to(_last_follow_pos) > FOLLOW_UPDATE_EPSILON_SQ:
			_update_source_region_plane_positions(pp)
			_last_follow_pos = pp


# ============================================================
# Public API
# ============================================================

func set_player_chunk(chunk: Vector3i) -> void:
	# Called by WaterFlowManager when the player's chunk changes. Frees
	# meshes outside MESH_RENDER_RADIUS_M and dirty-marks chunks newly
	# inside the radius.
	if chunk == _player_chunk and not _meshes.is_empty():
		return
	_player_chunk = chunk

	# Free meshes outside the radius.
	var radius_chunks: int = ceili(MESH_RENDER_RADIUS_M / CHUNK_SIZE_M)
	for existing_chunk in _meshes.keys():
		var d: Vector3i = existing_chunk - _player_chunk
		if absi(d.x) > radius_chunks or absi(d.y) > radius_chunks or absi(d.z) > radius_chunks:
			var mesh_inst: MeshInstance3D = _meshes[existing_chunk]
			if mesh_inst != null:
				mesh_inst.queue_free()
			_meshes.erase(existing_chunk)

	# Dirty-mark chunks newly inside the radius. Water surfaces are 2D
	# planes at fixed Y values (one per source region — ocean at Y=10,
	# pond at Y=1.5, etc.), so we only need to check chunks at those
	# specific Y-chunks rather than every Y in the radius cube.
	#
	# Earlier impl iterated the full (2*radius+1)^3 cube — at radius
	# 24 chunks that's 117,649 iterations every time the player walked
	# 2.7 m (one chunk width). Each iteration did dictionary lookups
	# and an AABB test against every source region; total cost ran ~50-
	# 150 ms per chunk transition, producing the "moves OK rotating but
	# stutters when walking" hitch that's been present since the water
	# voxel refactor landed.
	#
	# New impl: collect the set of unique surface Y-chunks from
	# WaterFlowManager (typically 1-3 values), then iterate only the
	# 2D (dx,dz) ring at each of those Ys. With 2 source regions
	# (ocean + pond at different Ys) this is 49×49×2 = ~4800 iterations
	# instead of 117,649 — ~24× faster, fits comfortably under 1 ms.
	if _water_flow_manager == null:
		return
	if not _water_flow_manager.has_method("get_source_regions"):
		return
	var surface_chunk_ys: Dictionary = {}  # int Y → true (deduped set)
	for region_data in _water_flow_manager.get_source_regions():
		var aabb: AABB = region_data["aabb"] as AABB
		var surface_y_world: float = aabb.position.y + aabb.size.y
		var y_chunk: int = floori(surface_y_world / CHUNK_SIZE_M)
		surface_chunk_ys[y_chunk] = true
	# Iterate the 2D (dx, dz) ring once per distinct surface Y. Most
	# of the inner-loop chunks already pass _chunk_could_have_water by
	# construction — we landed at the right Y. We still call the
	# function to confirm horizontal AABB overlap (rejects ocean
	# chunks past the configured 20×20 km footprint, etc.).
	for y_chunk in surface_chunk_ys.keys():
		var dy: int = (y_chunk as int) - _player_chunk.y
		if absi(dy) > radius_chunks:
			continue  # surface is outside vertical render radius
		for dx in range(-radius_chunks, radius_chunks + 1):
			for dz in range(-radius_chunks, radius_chunks + 1):
				var c := Vector3i(_player_chunk.x + dx, y_chunk, _player_chunk.z + dz)
				if _meshes.has(c) or _dirty_set.has(c):
					continue
				if not _chunk_could_have_water(c):
					continue
				_dirty_queue.append(c)
				_dirty_set[c] = true


func _chunk_could_have_water(chunk: Vector3i) -> bool:
	# Cheap reject: does any source region's surface_y land inside
	# this chunk's vertical range AND overlap horizontally? Same
	# math as _gather_surface_quads but boolean — short-circuits as
	# soon as we find one match.
	if _water_flow_manager == null \
			or not _water_flow_manager.has_method("get_source_regions"):
		return false
	var chunk_min_x: float = float(chunk.x) * CHUNK_SIZE_M
	var chunk_min_y: float = float(chunk.y) * CHUNK_SIZE_M
	var chunk_min_z: float = float(chunk.z) * CHUNK_SIZE_M
	var chunk_max_x: float = chunk_min_x + CHUNK_SIZE_M
	var chunk_max_y: float = chunk_min_y + CHUNK_SIZE_M
	var chunk_max_z: float = chunk_min_z + CHUNK_SIZE_M
	for region_data in _water_flow_manager.get_source_regions():
		var aabb: AABB = region_data["aabb"] as AABB
		var surface_y: float = aabb.position.y + aabb.size.y
		# Y check first (cheap; rejects ~100% of irrelevant chunks).
		if surface_y < chunk_min_y or surface_y >= chunk_max_y:
			continue
		# XZ overlap check.
		var aabb_max_x: float = aabb.position.x + aabb.size.x
		var aabb_max_z: float = aabb.position.z + aabb.size.z
		if chunk_max_x > aabb.position.x and chunk_min_x < aabb_max_x \
				and chunk_max_z > aabb.position.z and chunk_min_z < aabb_max_z:
			return true
	return false


# ============================================================
# Signal handlers
# ============================================================

func _on_water_changed(chunk_coord: Vector3i) -> void:
	# WaterFlowManager fired water_changed — water cells in this chunk
	# changed. Queue a rebuild only if the chunk is within render radius.
	var d: Vector3i = chunk_coord - _player_chunk
	var radius_chunks: int = ceili(MESH_RENDER_RADIUS_M / CHUNK_SIZE_M)
	if absi(d.x) > radius_chunks or absi(d.y) > radius_chunks or absi(d.z) > radius_chunks:
		return
	if not _dirty_set.has(chunk_coord):
		_dirty_queue.append(chunk_coord)
		_dirty_set[chunk_coord] = true


# ============================================================
# Mesh construction
# ============================================================

func _rebuild_chunk(chunk: Vector3i) -> void:
	# Determine what water surface(s) exist in this chunk. Phase 2
	# implementation: one flat top-plane per (chunk, source_region)
	# overlap. Per-cell water ignored for v1 — Phase 2 only handles
	# source regions, which covers the test pond + ocean visually.
	# Phases 4+ extend this to per-cell partial-height surfaces.
	var quads: Array = _gather_surface_quads(chunk)
	var existing: MeshInstance3D = _meshes.get(chunk, null)

	if quads.is_empty():
		# No water — free the mesh if it exists, otherwise nothing to do.
		if existing != null:
			existing.queue_free()
			_meshes.erase(chunk)
		return

	var mesh: ArrayMesh = _build_array_mesh(quads)
	if existing == null:
		existing = MeshInstance3D.new()
		existing.material_override = _shader_material
		add_child(existing)
		_meshes[chunk] = existing
		# Verify the material survived the assignment. If
		# material_override reads back as null after the line above,
		# something rejected the assignment (type mismatch, missing
		# property, etc.). One-time print per chunk creation so we
		# can confirm the path is live.
		print("[WaterChunkMesher] CREATED chunk=%s pos=%s mesh_surfaces=%d  material_override=%s  visible=%s" % [
			chunk,
			existing.global_position if existing.is_inside_tree() else Vector3.ZERO,
			mesh.get_surface_count(),
			"present" if existing.material_override != null else "NULL",
			existing.visible,
		])
	# Always (re)apply the material — guards against a previously-built
	# MeshInstance3D persisting from before _shader_material was set
	# correctly. Cheap (just a property write) and idempotent.
	existing.material_override = _shader_material
	existing.mesh = mesh


func _gather_surface_quads(_chunk: Vector3i) -> Array:
	# Returns surface quads to mesh in this chunk. Source regions are
	# now rendered by the giant per-region planes built in
	# _rebuild_source_region_planes — NOT here. This function is
	# reserved for per-cell water (player bucket placements) where
	# each cell may have a different surface height. Currently empty
	# (cell rendering is a future phase); leaving the stub so the
	# call site keeps compiling and the future cell pass slots in
	# without ripple-changes.
	#
	# Returning [] always means _rebuild_chunk free's any old chunk
	# meshes and creates none — the mesher idles for source-region-
	# only worlds.
	return []


func _rebuild_source_region_planes() -> void:
	# One subdivided flat plane per source region (ocean, lake).
	# Spawns one MeshInstance3D each, parented under this node so a
	# scene unload frees them with us.
	#
	# Why a plane and not a chunk-mesh: source regions are flat by
	# design — the surface is a single Y, no per-cell variance. A
	# single mesh per region is one draw call regardless of size,
	# scales to 20+ km oceans for free. The previous chunk-based
	# path produced a hard cutoff at MESH_RENDER_RADIUS_M because
	# only chunks within that radius of the player got meshed.
	#
	# Idempotent: clears existing planes first so this can be called
	# again to react to runtime add_source_region (e.g. story event
	# floods a basin).
	for plane in _source_region_planes:
		if is_instance_valid(plane):
			plane.queue_free()
	_source_region_planes.clear()

	if _water_flow_manager == null \
			or not _water_flow_manager.has_method("get_source_regions"):
		return
	var regions: Array = _water_flow_manager.get_source_regions()
	for region_data in regions:
		var aabb: AABB = region_data["aabb"] as AABB
		var inst: MeshInstance3D = _build_source_region_plane(aabb)
		if inst == null:
			continue
		add_child(inst)
		# Position must be set AFTER add_child — global_position is
		# only defined inside the tree.
		var center_x: float = aabb.position.x + aabb.size.x * 0.5
		var center_z: float = aabb.position.z + aabb.size.z * 0.5
		var surface_y: float = aabb.position.y + aabb.size.y
		inst.global_position = Vector3(center_x, surface_y, center_z)
		_source_region_planes.append(inst)
	print("[WaterChunkMesher] built %d source-region plane(s)." % _source_region_planes.size())


func _build_source_region_plane(aabb: AABB) -> MeshInstance3D:
	# Build a fixed-size plane sized to the visibility window — NOT
	# the AABB. The plane FOLLOWS the player each frame (see
	# _update_source_region_plane_positions) and is clipped against
	# the source region's AABB so water never extends past the actual
	# water body's footprint.
	#
	# Subdivision: SOURCE_REGION_QUAD_SIZE_M per quad, capped at
	# SOURCE_REGION_MAX_SUBDIV. For our 800 m × 800 m visibility
	# window at 4 m/quad → 200 subdivisions on each side ≈ 40 k verts.
	# Single mesh, single draw call.
	var visible_size: float = SOURCE_REGION_VISIBLE_HORIZON_M * 2.0
	# Don't make the plane bigger than the AABB itself — for a tiny
	# pond (10 × 10 m), the plane stays at 10 × 10.
	var plane_x: float = minf(visible_size, aabb.size.x)
	var plane_z: float = minf(visible_size, aabb.size.z)
	var subdiv_x: int = mini(int(plane_x / SOURCE_REGION_QUAD_SIZE_M), SOURCE_REGION_MAX_SUBDIV)
	var subdiv_z: int = mini(int(plane_z / SOURCE_REGION_QUAD_SIZE_M), SOURCE_REGION_MAX_SUBDIV)
	subdiv_x = maxi(subdiv_x, 1)
	subdiv_z = maxi(subdiv_z, 1)

	var plane := PlaneMesh.new()
	plane.size = Vector2(plane_x, plane_z)
	plane.subdivide_width = subdiv_x
	plane.subdivide_depth = subdiv_z

	var inst := MeshInstance3D.new()
	inst.mesh = plane
	inst.material_override = _shader_material
	inst.extra_cull_margin = 64.0
	return inst


func _update_source_region_plane_positions(player_world_pos: Vector3) -> void:
	# Per-frame reposition (and visibility-cull) for each source-region
	# plane. Centre the plane on the player's XZ, but clamp into the
	# source region's AABB so we never render water past the body of
	# water's actual footprint. If the player is outside the AABB by
	# more than half the plane's width, the entire plane is hidden.
	if _water_flow_manager == null \
			or not _water_flow_manager.has_method("get_source_regions"):
		return
	var regions: Array = _water_flow_manager.get_source_regions()
	# Defensive: if the regions list size doesn't match our planes,
	# just bail — _rebuild_source_region_planes will fix it.
	if regions.size() != _source_region_planes.size():
		return
	for i in _source_region_planes.size():
		var inst: MeshInstance3D = _source_region_planes[i]
		if inst == null or not is_instance_valid(inst):
			continue
		var aabb: AABB = regions[i]["aabb"] as AABB
		var surface_y: float = aabb.position.y + aabb.size.y
		var plane_mesh: PlaneMesh = inst.mesh as PlaneMesh
		if plane_mesh == null:
			continue
		var plane_w: float = plane_mesh.size.x
		var plane_d: float = plane_mesh.size.y  # PlaneMesh is XZ-oriented; size.y = depth
		var half_w: float = plane_w * 0.5
		var half_d: float = plane_d * 0.5

		# AABB extents in world XZ.
		var aabb_min_x: float = aabb.position.x
		var aabb_max_x: float = aabb.position.x + aabb.size.x
		var aabb_min_z: float = aabb.position.z
		var aabb_max_z: float = aabb.position.z + aabb.size.z

		# Clamp the plane CENTRE so its full footprint stays inside
		# the AABB. If the AABB is smaller than the plane on an axis,
		# centre on the AABB centre instead (the min/max would cross).
		var center_x: float
		if plane_w >= aabb.size.x:
			center_x = (aabb_min_x + aabb_max_x) * 0.5
		else:
			center_x = clampf(player_world_pos.x, aabb_min_x + half_w, aabb_max_x - half_w)
		var center_z: float
		if plane_d >= aabb.size.z:
			center_z = (aabb_min_z + aabb_max_z) * 0.5
		else:
			center_z = clampf(player_world_pos.z, aabb_min_z + half_d, aabb_max_z - half_d)

		# Hide the plane if the player is far outside the AABB. We
		# consider "outside" as more than the visibility horizon
		# beyond any AABB edge.
		var horizon: float = SOURCE_REGION_VISIBLE_HORIZON_M
		var outside_x: bool = player_world_pos.x < aabb_min_x - horizon or player_world_pos.x > aabb_max_x + horizon
		var outside_z: bool = player_world_pos.z < aabb_min_z - horizon or player_world_pos.z > aabb_max_z + horizon
		inst.visible = not (outside_x or outside_z)

		inst.global_position = Vector3(center_x, surface_y, center_z)


func _build_array_mesh(quads: Array) -> ArrayMesh:
	# Build a single ArrayMesh containing every quad. Each quad is two
	# triangles. Subdivide each quad into a 4×4 grid so the wave-shader
	# vertex displacement has interior vertices to move (a 2-tri quad
	# would only displace at corners, which looks flat).
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	const SUBDIV: int = 4

	for q in quads:
		var min_x: float = q["min_x"]
		var max_x: float = q["max_x"]
		var min_z: float = q["min_z"]
		var max_z: float = q["max_z"]
		var y: float = q["y"]
		var v_start: int = verts.size()
		# Generate (SUBDIV+1)² vertices in a grid.
		for j in range(SUBDIV + 1):
			var tz: float = float(j) / float(SUBDIV)
			var z: float = lerpf(min_z, max_z, tz)
			for i in range(SUBDIV + 1):
				var tx: float = float(i) / float(SUBDIV)
				var x: float = lerpf(min_x, max_x, tx)
				verts.append(Vector3(x, y, z))
		# Generate two triangles per cell. Winding: CCW from above
		# (cull_back in shader culls back faces, so this faces +Y).
		for j in range(SUBDIV):
			for i in range(SUBDIV):
				var top_left: int = v_start + j * (SUBDIV + 1) + i
				var top_right: int = top_left + 1
				var bot_left: int = top_left + (SUBDIV + 1)
				var bot_right: int = bot_left + 1
				indices.append(top_left)
				indices.append(bot_left)
				indices.append(top_right)
				indices.append(top_right)
				indices.append(bot_left)
				indices.append(bot_right)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
