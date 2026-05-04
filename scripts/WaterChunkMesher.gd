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

# Render radius (m) around the player. Chunks outside this radius get
# their meshes freed; chunks inside get meshes built/refreshed.
const MESH_RENDER_RADIUS_M: float = 64.0

# Per-frame mesh rebuild budget. Mirrors VoxelGravityManager's
# 1-scan-per-frame budget — keeps mesh churn from spiking frame time.
const MESH_BUILDS_PER_FRAME: int = 2

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
# per frame from _process.

var _player_chunk: Vector3i = Vector3i.ZERO
# Chunk the player is currently in. Updated when set_player_chunk is
# called from WaterFlowManager (which itself is updated by Player3D
# each physics frame).

var _shader_material: Material = null
# Cached water_material.tres reference. Loaded lazily on first build.

var _water_flow_manager: Node = null
# Cached parent (WaterFlowManager autoload). Resolved in _ready.


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
	# Lazy-load the shader material once. Failure is logged loudly so
	# we don't ship invisible water by accident.
	_shader_material = load("res://assets/shaders/water_material.tres") as Material
	if _shader_material == null:
		push_error("[WaterChunkMesher] failed to load water_material.tres — water surfaces will be invisible.")


func _process(_delta: float) -> void:
	# Drain up to MESH_BUILDS_PER_FRAME from the queue.
	var built: int = 0
	while built < MESH_BUILDS_PER_FRAME and not _dirty_queue.is_empty():
		var chunk: Vector3i = _dirty_queue.pop_front()
		_rebuild_chunk(chunk)
		built += 1


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

	# Dirty-mark chunks inside the radius that don't have meshes yet.
	# This populates the queue lazily as the player moves.
	for dx in range(-radius_chunks, radius_chunks + 1):
		for dy in range(-radius_chunks, radius_chunks + 1):
			for dz in range(-radius_chunks, radius_chunks + 1):
				var c := _player_chunk + Vector3i(dx, dy, dz)
				if not _meshes.has(c) and not _dirty_queue.has(c):
					_dirty_queue.append(c)


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
	if not _dirty_queue.has(chunk_coord):
		_dirty_queue.append(chunk_coord)


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
	existing.mesh = mesh


func _gather_surface_quads(chunk: Vector3i) -> Array:
	# Returns an Array of dicts: {"min_x", "min_z", "max_x", "max_z", "y"}
	# for each top-surface quad that should render in this chunk.
	var quads: Array = []
	if _water_flow_manager == null:
		return quads

	# Chunk's world-space AABB.
	var chunk_min := Vector3(
		float(chunk.x) * CHUNK_SIZE_M,
		float(chunk.y) * CHUNK_SIZE_M,
		float(chunk.z) * CHUNK_SIZE_M,
	)
	var chunk_max := chunk_min + Vector3.ONE * CHUNK_SIZE_M

	# Walk source regions. For each region whose AABB overlaps this
	# chunk's column AND whose top is inside this chunk's vertical
	# range, emit a quad at the AABB top.
	var regions: Array = []
	if _water_flow_manager.has_method("get_source_regions"):
		regions = _water_flow_manager.get_source_regions()
	for region_data in regions:
		var aabb: AABB = region_data["aabb"] as AABB
		# Horizontal overlap test (XZ rectangle).
		var overlap_min_x: float = maxf(chunk_min.x, aabb.position.x)
		var overlap_max_x: float = minf(chunk_max.x, aabb.position.x + aabb.size.x)
		var overlap_min_z: float = maxf(chunk_min.z, aabb.position.z)
		var overlap_max_z: float = minf(chunk_max.z, aabb.position.z + aabb.size.z)
		if overlap_min_x >= overlap_max_x or overlap_min_z >= overlap_max_z:
			continue
		# Top Y of the source region (the surface plane).
		var surface_y: float = aabb.position.y + aabb.size.y
		# Render the surface only if it lies within this chunk's
		# vertical range. Otherwise the chunk above (or below) owns it.
		if surface_y < chunk_min.y or surface_y >= chunk_max.y:
			continue
		quads.append({
			"min_x": overlap_min_x,
			"max_x": overlap_max_x,
			"min_z": overlap_min_z,
			"max_z": overlap_max_z,
			"y": surface_y,
		})

	return quads


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
