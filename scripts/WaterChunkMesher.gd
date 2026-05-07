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
# path. Only this radius renders per-voxel detail (waterline conforms
# to terrain heightmap, partial-fill cells, side faces). Past it the
# follow-player horizon plane (CULL_BACK so it's invisible from
# below) paints featureless distant water at sea level Y.
#
# 96 m gives a ~36×36 = ~1300 chunk fill at the sea-level row (vs
# ~35k at 250 m), keeping both initial-fill cost AND sustained
# render cost (mesh instance count) bounded. Going wider was the
# 2026-05-06 perf regression — 35k MeshInstance3Ds drew tens of
# millions of triangles per frame. Going narrower would expose the
# per-voxel detail cutoff to the player.
const MESH_RENDER_RADIUS_M: float = 96.0

# Per-frame mesh rebuild budget — adaptive. _adaptive_build_budget()
# scales between MIN and MAX based on the previous frame's delta:
# - Frame ≤ 18 ms (>= 55 fps): full MAX builds. Fast fill.
# - Frame ≥ 50 ms (≤ 20 fps): MIN builds. Yield to whatever else is
#   under load (typically the terrain LOD streamer during initial fill).
# - Linear lerp between.
#
# Constants tuned for the 96 m radius (~1300 chunks at sea-level row,
# fills in ~1.4 s at MAX, ~22 s at MIN — but only stays at MIN while
# the system is heavily loaded, so the actual fill blends).
const MESH_BUILDS_PER_FRAME_MAX: int = 16
const MESH_BUILDS_PER_FRAME_MIN: int = 1
const MESH_THROTTLE_FRAME_MS_FAST: float = 18.0
const MESH_THROTTLE_FRAME_MS_SLOW: float = 50.0


func _adaptive_build_budget(delta: float) -> int:
	# Maps last frame's delta to a per-frame build budget. Heavier
	# frames → smaller budget so we yield to the terrain streamer.
	var frame_ms: float = delta * 1000.0
	if frame_ms <= MESH_THROTTLE_FRAME_MS_FAST:
		return MESH_BUILDS_PER_FRAME_MAX
	if frame_ms >= MESH_THROTTLE_FRAME_MS_SLOW:
		return MESH_BUILDS_PER_FRAME_MIN
	var t: float = (frame_ms - MESH_THROTTLE_FRAME_MS_FAST) \
		/ (MESH_THROTTLE_FRAME_MS_SLOW - MESH_THROTTLE_FRAME_MS_FAST)
	return int(lerpf(float(MESH_BUILDS_PER_FRAME_MAX), float(MESH_BUILDS_PER_FRAME_MIN), t))

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

var _horizon_material: Material = null
# Same shader, but render_priority = -1 so the legacy follow-player
# horizon plane draws BEHIND the Phase 2 chunked mesh wherever they
# overlap at the same Y. Without this, both materials render at
# priority 0 and the GPU picks the winner per pixel (visible z-fighting
# at the inner-radius / horizon transition). Cleared in Phase 5 when
# the horizon path is rebuilt around a single fixed-Y plane.

var _water_flow_manager: Node = null
# Cached parent (WaterFlowManager autoload). Resolved in _ready.

# Sea-level voxel Y from the generator. Pulled at _ready so we don't
# touch CubicHeightmapGenerator on every chunk rebuild. Used by
# _chunk_could_have_water and set_player_chunk to bias chunk-dirty
# decisions toward the chunk-Y where the ocean surface lives.
#
# At 6 vox/m the sea level Y=60 sits in chunk Y = floor(60/16) = 3.
# Chunks above that row contain no ocean voxels (water is below
# sea level by definition). Chunks below contain submerged water but
# their TOP face isn't visible — only the chunk row at sea-level Y
# emits a top-face mesh. This optimisation keeps the dirty queue from
# walking the whole vertical column.
const _SEA_LEVEL_VOXELS_DEFAULT: int = 72  # Mira's CubicHeightmapGenerator default
@warning_ignore("integer_division")
const _SEA_LEVEL_CHUNK_Y_DEFAULT: int = _SEA_LEVEL_VOXELS_DEFAULT / CHUNK_SIZE_VOXELS  # 72/16 = 4

func _current_sea_level_chunk_y() -> int:
	# Read the live sea level from WaterFlowManager so each scene can
	# override (Mira keeps the 72-vox default, Copper Isles overrides
	# to 720). Without this dispatch the mesher would scan the wrong
	# chunk-Y row in any scene whose sea level differs from Mira's,
	# producing an empty ocean surface even when water voxels are
	# correctly cached.
	if _water_flow_manager == null or not _water_flow_manager.has_method("get_sea_level_voxel_y"):
		return _SEA_LEVEL_CHUNK_Y_DEFAULT
	@warning_ignore("integer_division")
	var chunk_y: int = (_water_flow_manager.get_sea_level_voxel_y() as int) / CHUNK_SIZE_VOXELS
	return chunk_y

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

# Half-width (m) of the follow-player horizon plane. The plane renders
# at sea-level Y for this distance on each axis, then ends — matching
# how terrain stops at its own view distance, so we don't have
# "infinite water past the terrain horizon" weirdness.
#
# Set to ~1.2× the terrain view radius (terrain view_distance is
# 1500 voxels ≈ 250 m). 300 m here gives a comfortable margin: water
# reaches a touch past where the last terrain chunks stop, so the
# coastline at the horizon doesn't appear to float over void. The
# chunked mesh overdraws the inner 96 m so the player only "sees"
# the horizon plane in the 96 m–300 m ring.
const SOURCE_REGION_VISIBLE_HORIZON_M: float = 3000.0
# Was 300 m. Bumped for the Copper Isles mountaintop vista — from a
# 500 m peak the player needs to see the ocean stretching kilometres
# in every direction, not a tiny 600 m × 600 m puddle around them.
# 3000 m gives a 6 km × 6 km plane, large enough to cover the full
# 5 km Copper Isles map regardless of player position. Cost is
# nothing — the plane is two triangles regardless of size.


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
	# Phase 3: also subscribe to VoxelEditManager.water_changed_at so
	# direct CHANNEL_DATA edits (buckets, flood-trigger boxes) trigger
	# a re-mesh of the affected chunk + neighbour ring. Without this,
	# placing a bucket of water in front of the player would not show
	# up until the next flow tick happened to dirty the chunk.
	if get_node_or_null("/root/VoxelEditManager") != null \
			and VoxelEditManager.has_signal("water_changed_at"):
		VoxelEditManager.water_changed_at.connect(_on_water_changed_at)
	# DEBUG (2026-05-06): wave shader temporarily disabled so the player
	# can see flat water surfaces while diagnosing the per-voxel ocean
	# rewrite. The wave shader (assets/shaders/water_material.tres +
	# water.gdshader) is unchanged on disk — flip _build_debug_water_material
	# back to `load("res://assets/shaders/water_material.tres")` to
	# restore the sine-sum surface displacement once the mechanics
	# are confirmed.
	_shader_material = _build_debug_water_material(false)
	_horizon_material = _build_debug_water_material(true)
	print("[WaterChunkMesher] DEBUG flat-water material in use (wave shader bypassed).")

	# Build the follow-player horizon plane. The chunked mesher only
	# renders water within MESH_RENDER_RADIUS_M (96 m); past that the
	# horizon plane paints featureless distant ocean. Uses CULL_BACK
	# so the plane's underside is invisible — solves the 2026-05-06
	# complaint that the old plane "tinted the screen blue when the
	# camera dipped below it." The chunked mesh near the player
	# overdraws the plane wherever they overlap, and render_priority
	# = -1 on the horizon material loses ties at the same Y.
	_rebuild_horizon_plane()


func _build_debug_water_material(is_horizon: bool) -> StandardMaterial3D:
	# Bright opaque cyan-blue so the surface is unambiguously visible
	# during the per-voxel ocean bring-up. Once the mesher path is
	# confirmed working visually, we can re-introduce alpha blending and
	# eventually swap back to the wave shader.
	#
	# UNSHADED so the colour reads identically regardless of where the
	# sun is in the day/night cycle — flat saturated blue is easier to
	# spot in a dim Output-panel-and-engine workflow than a lit blue
	# that goes near-black at night.
	#
	# Cull mode differs by surface kind:
	# - Chunked surface (is_horizon=false): CULL_DISABLED so it's visible
	#   from both above (looking at the ocean) and below (looking up at
	#   the surface from a carved-out underwater tunnel — the water
	#   should still appear to have a "ceiling" above the player's head).
	# - Horizon plane (is_horizon=true): CULL_BACK — the player should
	#   never see the underside. The plane spans the visible window so
	#   when the player drops below sea level (deep mine, ocean trench)
	#   a CULL_DISABLED plane would draw a giant blue ceiling overhead.
	#   render_priority = -1 makes the chunked mesh win z-fighting
	#   wherever they overlap at sea level Y.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.50, 0.90)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if is_horizon:
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mat.render_priority = -1
	else:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _process(delta: float) -> void:
	# Drain up to _adaptive_build_budget(delta) chunks from the queue.
	# Builds are throttled when frame time is high — during the initial
	# load window the terrain streamer competes for CPU and any cycles
	# we steal here directly delay terrain LOD streaming. The throttle
	# yields gracefully back to terrain when frames get heavy.
	var budget: int = _adaptive_build_budget(delta)
	current_budget = budget
	var built: int = 0
	while built < budget and not _dirty_queue.is_empty():
		var chunk: Vector3i = _dirty_queue.pop_front()
		_dirty_set.erase(chunk)
		_rebuild_chunk(chunk)
		built += 1
	meshed_this_second += built
	dirty_queue_len = _dirty_queue.size()

	# Horizon plane removed — the per-frame follow-player update is
	# a no-op now (no _source_region_planes to position). Kept the
	# call site so the legacy code structure is preserved; it bails
	# immediately once it sees the empty plane list.
	# Skip entirely when the player hasn't
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
	# Ocean lives in CHANNEL_DATA at SEA_LEVEL_VOXELS, which falls inside
	# _SEA_LEVEL_CHUNK_Y. Iterate that one chunk-Y row in the active
	# 2D radius. Per-cell water above sea level (player buckets) is
	# surfaced via the water_changed_at edit path (Phase 3) — those
	# chunks dirty themselves on the edit, no scan needed here.
	var surface_chunk_ys: Dictionary = {}
	surface_chunk_ys[_current_sea_level_chunk_y()] = true
	for y_chunk in surface_chunk_ys.keys():
		# Concentric-ring iteration: enqueue chunks closest to the player
		# first, then progressively farther ones. The previous row-major
		# `for dx in -radius..radius: for dz in -radius..radius` filled
		# the queue starting at the (-radius, -radius) corner — water
		# materialised at the horizon and crept inward over ~10 s.
		# Ring-by-ring queues the player's own chunk first, then the
		# 8-neighbourhood, then the 24-neighbourhood, etc. Visible water
		# appears around the player on the first frame and the load
		# expands outward.
		for r in range(radius_chunks + 1):
			for offset in _ring_offsets(r):
				var c := Vector3i(
					_player_chunk.x + offset.x,
					y_chunk,
					_player_chunk.z + offset.y,
				)
				if _meshes.has(c) or _dirty_set.has(c):
					continue
				if not _chunk_could_have_water(c):
					continue
				_dirty_queue.append(c)
				_dirty_set[c] = true


func _ring_offsets(r: int) -> Array:
	# Return the (dx, dz) offsets that lie on the square ring at
	# Chebyshev distance `r` from the origin. r=0 is just (0,0); r=1 is
	# the 8-neighbourhood; r=2 is the next outer 16 cells; etc.
	# Used by set_player_chunk to fill the dirty queue in close-to-far
	# order so visible water materialises around the player first.
	if r == 0:
		return [Vector2i(0, 0)]
	var ring: Array = []
	# Top and bottom edges (full width including corners).
	for d in range(-r, r + 1):
		ring.append(Vector2i(d, -r))
		ring.append(Vector2i(d, r))
	# Left and right edges (excluding corners already added).
	for d in range(-r + 1, r):
		ring.append(Vector2i(-r, d))
		ring.append(Vector2i(r, d))
	return ring


func _chunk_could_have_water(chunk: Vector3i) -> bool:
	# Cheap pre-filter before the per-chunk terrain.copy() in
	# _rebuild_chunk. The ocean surface lives at the active scene's
	# sea-level chunk-Y row (Mira: 4, Copper Isles: 45). Edits via
	# water_changed_at dirty their own chunks, so per-cell buckets
	# above sea level still get rebuilt without a special check here.
	return chunk.y == _current_sea_level_chunk_y()


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


func _on_water_changed_at(_world_pos: Vector3, chunk_coord: Vector3i, _edit_aabb: AABB) -> void:
	# VoxelEditManager fired water_changed_at — a CHANNEL_DATA edit
	# landed at chunk_coord. Queue rebuild for this chunk and its
	# 26-neighbour ring (an edit at a chunk boundary may visually
	# affect the neighbour). Mirrors the dirty-marking pattern in
	# WaterFlowManager._on_edit_applied.
	var radius_chunks: int = ceili(MESH_RENDER_RADIUS_M / CHUNK_SIZE_M)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var c := chunk_coord + Vector3i(dx, dy, dz)
				var d_to_player: Vector3i = c - _player_chunk
				if absi(d_to_player.x) > radius_chunks \
						or absi(d_to_player.y) > radius_chunks \
						or absi(d_to_player.z) > radius_chunks:
					continue
				if _dirty_set.has(c):
					continue
				_dirty_queue.append(c)
				_dirty_set[c] = true


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
		existing.extra_cull_margin = 16.0
		add_child(existing)
		# Position the MeshInstance3D at the chunk's world-space origin
		# corner. Verts are emitted local to that, so the mesh's local
		# AABB is small (~2.7 m on each side) and centered around the
		# node origin — Godot's frustum culler handles this cleanly.
		# global_position must be set AFTER add_child (only valid in
		# the tree).
		var chunk_world_origin := Vector3(
			float(chunk.x * CHUNK_SIZE_VOXELS) / VOXELS_PER_METER,
			float(chunk.y * CHUNK_SIZE_VOXELS) / VOXELS_PER_METER,
			float(chunk.z * CHUNK_SIZE_VOXELS) / VOXELS_PER_METER,
		)
		existing.global_position = chunk_world_origin
		_meshes[chunk] = existing
		_diag_chunks_meshed += 1
	# Always (re)apply the material — guards against a previously-built
	# MeshInstance3D persisting from before _shader_material was set
	# correctly. Cheap (just a property write) and idempotent.
	existing.material_override = _shader_material
	existing.mesh = mesh


var _diag_chunks_scanned: int = 0
var _diag_chunks_with_water: int = 0
var _diag_chunks_meshed: int = 0
var _diag_chunks_with_quads: int = 0
var _diag_first_water_chunk_logged: bool = false
var _diag_first_quads_logged: bool = false

# Read by VoxelStreamProfiler once per second. meshed_this_second is a
# rolling counter the profiler resets each tick. dirty_queue_len and
# current_budget are written every _process frame. All single-int reads
# from the main thread, no Mutex needed.
var meshed_this_second: int = 0
var dirty_queue_len: int = 0
var current_budget: int = 0


func _gather_surface_quads(chunk: Vector3i) -> Array:
	# Phase 2 implementation: read CHANNEL_DATA for this chunk, find the
	# topmost water voxel per (X, Z) column, group columns by top-Y, then
	# greedy-merge each group into rectangles. Each rectangle becomes one
	# subdivided water quad.
	#
	# Why greedy-merge instead of one-quad-per-column: a fully-ocean
	# chunk (16×16 columns all at top_y=12 inside the chunk) collapses
	# to a single 16×16 quad — one mesh surface per chunk, ~256 verts at
	# our minimum subdivision instead of ~5k. Coastline chunks split
	# into a few rectangles. Cost per merged rectangle is small and the
	# algorithm runs in O(columns) overall.
	#
	# Side faces (level<8 partial-fill cells) are deferred to Phase 4
	# when the flow simulator starts producing them. Ocean voxels from
	# the generator are all level=8 → flat top, no side faces needed.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return []
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return []
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return []

	# ---- Read CHANNEL_DATA for the whole chunk in one bulk copy ----
	# tool.copy(src_origin: Vector3i, dst_buffer: VoxelBuffer, channels_mask: int)
	# Mirrors the bulk-read pattern from VoxelGravityManager (which
	# documented that per-voxel get_voxel was the 6 s hot path). Same
	# avoidance here — one C++ call into Zylann, then iterate the
	# in-process buffer.
	var buf := VoxelBuffer.new()
	buf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	var voxel_origin := Vector3i(
		chunk.x * CHUNK_SIZE_VOXELS,
		chunk.y * CHUNK_SIZE_VOXELS,
		chunk.z * CHUNK_SIZE_VOXELS,
	)
	var data_mask: int = 1 << VoxelBuffer.CHANNEL_DATA5
	tool.copy(voxel_origin, buf, data_mask)

	# ---- Early-out: uniform-channel fast path ----
	# is_uniform is an O(1) plugin call: most sea-level-row chunks are
	# either uniform 0 (above-water terrain — no water voxels) or
	# uniform SOURCE_BYTE (open ocean — every voxel is full source).
	# The first case skips meshing entirely; the second emits one
	# 16×16 quad without per-voxel scanning.
	if buf.has_method("is_uniform") and buf.call("is_uniform", VoxelBuffer.CHANNEL_DATA5):
		var uniform_byte: int = buf.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_DATA5)
		_diag_chunks_scanned += 1
		if uniform_byte == 0:
			return []  # uniform air — no water surface
		# Uniform water → one full-chunk top quad at local Y=16/6 (top
		# face of the topmost voxel). Greedy merge would converge to
		# the same single quad; this just bypasses the scan.
		_diag_chunks_with_water += 1
		_diag_chunks_with_quads += 1
		var top_y_local: int = CHUNK_SIZE_VOXELS - 1
		return [{
			"min_x": 0.0,
			"max_x": float(CHUNK_SIZE_VOXELS) / VOXELS_PER_METER,
			"min_z": 0.0,
			"max_z": float(CHUNK_SIZE_VOXELS) / VOXELS_PER_METER,
			"y": float(top_y_local + 1) / VOXELS_PER_METER,
		}]

	# ---- Per-column topmost-water search ----
	# For each (x, z) column inside the chunk, walk Y top-to-bottom and
	# stop at the first nonzero CHANNEL_DATA byte. Record top_y_local
	# (0..CHUNK_SIZE_VOXELS-1) or -1 if dry. We don't need the level
	# value here — only "is this a water voxel" — because Phase 2 only
	# emits flat top faces.
	#
	# In practice ocean chunks hit water at y=15 immediately (256 reads,
	# one per column). High-elevation sea-level-row chunks are worst case
	# (no water → 4096 reads). The throttle in _process bounds total
	# per-frame cost when many chunks are dirty at once.
	var column_top: Array = []  # column_top[x * 16 + z] → int top_y_local or -1
	column_top.resize(CHUNK_SIZE_VOXELS * CHUNK_SIZE_VOXELS)
	var any_water: bool = false
	var first_byte_seen: int = 0
	var first_byte_pos: Vector3i = Vector3i.ZERO
	for x in range(CHUNK_SIZE_VOXELS):
		for z in range(CHUNK_SIZE_VOXELS):
			var top: int = -1
			for y in range(CHUNK_SIZE_VOXELS - 1, -1, -1):
				var byte: int = buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_DATA5)
				if byte > 0:
					top = y
					if not any_water:
						first_byte_seen = byte
						first_byte_pos = Vector3i(x, y, z)
					break
			column_top[x * CHUNK_SIZE_VOXELS + z] = top
			if top >= 0:
				any_water = true
	_diag_chunks_scanned += 1
	if any_water:
		_diag_chunks_with_water += 1
		if not _diag_first_water_chunk_logged:
			_diag_first_water_chunk_logged = true
			print("[WaterChunkMesher] FIRST chunk with water: chunk=%s voxel_origin=%s first_byte=0x%02X at local=%s" % [
				chunk, voxel_origin, first_byte_seen, first_byte_pos,
			])
	# Periodic visibility into the full pipeline. If chunks_scanned grows
	# but chunks_with_water stays at 0, terrain.copy returns empty.
	# If with_water grows but with_quads stays at 0, the greedy merge
	# is broken. If with_quads grows but meshed stays at 0, the
	# rebuild path itself isn't running. Every counter advancing means
	# the path works end-to-end.
	if _diag_chunks_scanned % 200 == 0:
		print("[WaterChunkMesher] diag: scanned=%d with_water=%d with_quads=%d meshed=%d (player_chunk=%s)" % [
			_diag_chunks_scanned, _diag_chunks_with_water, _diag_chunks_with_quads,
			_diag_chunks_meshed, _player_chunk,
		])
	if not any_water:
		return []

	# ---- Group columns by top_y_local, then greedy-merge per group ----
	# For each distinct top_y_local value, build a 16×16 bool bitmap of
	# "this column is in this group", then run greedy 2D rectangle merge.
	#
	# Greedy algorithm: scan rows top-to-bottom; for each unvisited cell,
	# extend right as far as possible (longest contiguous run on this
	# row), then extend down as far as possible (every cell in the row
	# below within [start_x .. end_x] must also be in the group), mark
	# the rectangle visited, emit. Standard Minecraft greedy-mesher
	# pattern — produces close-to-optimal rectangle counts for typical
	# chunk shapes.
	var groups: Dictionary = {}  # int top_y_local → bool[16][16] (PackedByteArray of 0/1)
	for x in range(CHUNK_SIZE_VOXELS):
		for z in range(CHUNK_SIZE_VOXELS):
			var top: int = column_top[x * CHUNK_SIZE_VOXELS + z]
			if top < 0:
				continue
			# PackedByteArray in Godot 4 is value-typed when read out of
			# a Dictionary — mutating via the cast `(groups[top] as
			# PackedByteArray)[i] = 1` may write to a temporary copy
			# instead of the dict's stored array. Explicit read-modify-
			# write guarantees the change lands.
			var bmp: PackedByteArray = groups.get(top, PackedByteArray())
			if bmp.is_empty():
				bmp.resize(CHUNK_SIZE_VOXELS * CHUNK_SIZE_VOXELS)
			bmp[x * CHUNK_SIZE_VOXELS + z] = 1
			groups[top] = bmp

	var quads: Array = []
	for top_y_local in groups.keys():
		var bitmap: PackedByteArray = groups[top_y_local]
		_greedy_merge_into_quads(bitmap, chunk, top_y_local as int, quads)
	if not quads.is_empty():
		_diag_chunks_with_quads += 1
		if not _diag_first_quads_logged:
			_diag_first_quads_logged = true
			var q0: Dictionary = quads[0]
			print("[WaterChunkMesher] FIRST quads emitted: chunk=%s count=%d first_quad={x:[%.3f,%.3f] z:[%.3f,%.3f] y:%.3f}" % [
				chunk, quads.size(), q0["min_x"], q0["max_x"], q0["min_z"], q0["max_z"], q0["y"],
			])
	return quads


func _greedy_merge_into_quads(
	bitmap: PackedByteArray,
	chunk: Vector3i,
	top_y_local: int,
	out_quads: Array,
) -> void:
	# Walk the 16×16 bitmap row-by-row. For each unvisited cell, grow
	# the rectangle as wide as possible on this row, then as tall as
	# possible (every column in the rectangle's X range must be in the
	# bitmap on the next row). Emit one quad per rectangle.
	#
	# Coordinate convention: vert positions are LOCAL to the chunk's
	# voxel origin (chunk.x * 16, chunk.y * 16, chunk.z * 16) divided
	# by VOXELS_PER_METER. _rebuild_chunk sets MeshInstance3D.position
	# = chunk_origin_world so the local verts land at correct world
	# coords. Local-space verts keep the mesh's AABB tight and centered
	# on origin, which Godot's frustum culler handles cleanly. Earlier
	# attempt emitted world-space verts with the MeshInstance3D at
	# world origin — that put the mesh's AABB hundreds of metres from
	# its node origin and the mesh failed to render despite all the
	# voxel data being correct.
	var quad_local_y: float = float(top_y_local + 1) / VOXELS_PER_METER
	@warning_ignore("unused_variable")
	var _chunk_unused = chunk

	# Use a mutable copy so we can zero out consumed cells.
	var work := bitmap.duplicate()
	for z_local in range(CHUNK_SIZE_VOXELS):
		for x_local in range(CHUNK_SIZE_VOXELS):
			if work[x_local * CHUNK_SIZE_VOXELS + z_local] == 0:
				continue
			# Extend right on this Z-row.
			var end_x: int = x_local
			while end_x + 1 < CHUNK_SIZE_VOXELS \
					and work[(end_x + 1) * CHUNK_SIZE_VOXELS + z_local] == 1:
				end_x += 1
			# Extend down — every cell in this row's [x_local..end_x]
			# must be set on row z_local+1, z_local+2, ...
			var end_z: int = z_local
			while end_z + 1 < CHUNK_SIZE_VOXELS:
				var row_ok: bool = true
				for xi in range(x_local, end_x + 1):
					if work[xi * CHUNK_SIZE_VOXELS + (end_z + 1)] == 0:
						row_ok = false
						break
				if not row_ok:
					break
				end_z += 1
			# Mark consumed.
			for xi in range(x_local, end_x + 1):
				for zi in range(z_local, end_z + 1):
					work[xi * CHUNK_SIZE_VOXELS + zi] = 0
			# Local-space rectangle bounds (top face of voxels).
			var min_local_x: float = float(x_local) / VOXELS_PER_METER
			var max_local_x: float = float(end_x + 1) / VOXELS_PER_METER
			var min_local_z: float = float(z_local) / VOXELS_PER_METER
			var max_local_z: float = float(end_z + 1) / VOXELS_PER_METER
			out_quads.append({
				"min_x": min_local_x,
				"max_x": max_local_x,
				"min_z": min_local_z,
				"max_z": max_local_z,
				"y": quad_local_y,
			})


func _rebuild_horizon_plane() -> void:
	# Phase 5: one follow-player horizon plane at the configured sea
	# level Y. Replaces the per-source-region plane fleet — the AABB
	# regions are gone, water is per-voxel in CHANNEL_DATA, and the
	# horizon plane just paints a featureless sheet so the player
	# perceives water past the chunked-mesh radius.
	#
	# Idempotent: any existing plane is freed first. Called from _ready
	# (after _shader_material loads) and any time the active scene
	# changes the configured sea level.
	for plane in _source_region_planes:
		if is_instance_valid(plane):
			plane.queue_free()
	_source_region_planes.clear()

	var inst: MeshInstance3D = _build_horizon_plane()
	if inst == null:
		return
	add_child(inst)
	# Initial position — _update_source_region_plane_positions will
	# reposition next frame as the player moves.
	var horizon_y: float = _get_horizon_world_y()
	inst.global_position = Vector3(0.0, horizon_y, 0.0)
	_source_region_planes.append(inst)
	print("[WaterChunkMesher] horizon plane built at world Y=%.2f" % horizon_y)


func _build_horizon_plane() -> MeshInstance3D:
	# Build the single horizon plane sized to the visibility window.
	# Subdivision matches the legacy SOURCE_REGION_QUAD_SIZE_M target so
	# the wave shader has interior verts to displace.
	var visible_size: float = SOURCE_REGION_VISIBLE_HORIZON_M * 2.0
	var subdiv: int = mini(int(visible_size / SOURCE_REGION_QUAD_SIZE_M), SOURCE_REGION_MAX_SUBDIV)
	subdiv = maxi(subdiv, 1)

	var plane := PlaneMesh.new()
	plane.size = Vector2(visible_size, visible_size)
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv

	var inst := MeshInstance3D.new()
	inst.mesh = plane
	# render_priority = -1 on the horizon material loses ties to the
	# Phase 2 chunked mesh wherever they overlap at the same Y.
	inst.material_override = _horizon_material if _horizon_material != null else _shader_material
	inst.extra_cull_margin = 64.0
	return inst


func _get_horizon_world_y() -> float:
	# Read configured sea level from WaterFlowManager. Defaults to 10.0
	# (the project's historical sea-level Y) if the manager isn't yet
	# bound, so a startup-order race doesn't spawn the plane at Y=0.
	if _water_flow_manager == null:
		return 10.0
	if _water_flow_manager.has_method("get_horizon_plane_y"):
		return _water_flow_manager.get_horizon_plane_y()
	return 10.0


func _update_source_region_plane_positions(player_world_pos: Vector3) -> void:
	# Per-frame reposition for the single horizon plane. Centre on the
	# player's XZ at the configured horizon Y. No AABB clipping (the
	# horizon is conceptually infinite — the chunked mesh handles the
	# "real" water near the player; this plane is just background).
	if _source_region_planes.is_empty():
		return
	var inst: MeshInstance3D = _source_region_planes[0]
	if inst == null or not is_instance_valid(inst):
		return
	var horizon_y: float = _get_horizon_world_y()
	inst.global_position = Vector3(player_world_pos.x, horizon_y, player_world_pos.z)


func _build_array_mesh(quads: Array) -> ArrayMesh:
	# Build a single ArrayMesh containing every quad. Each quad is two
	# triangles. Subdivide each quad into a 4×4 grid so the wave-shader
	# vertex displacement has interior vertices to move (a 2-tri quad
	# would only displace at corners, which looks flat).
	#
	# Now emits NORMAL and TEX_UV alongside VERTEX. Without normals,
	# Godot's renderer was producing invisible ArrayMesh surfaces even
	# in UNSHADED material mode — the explicit normal array is the fix.
	# Normals all point +Y (water surface faces up).
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const SUBDIV: int = 4
	const UP_NORMAL: Vector3 = Vector3(0.0, 1.0, 0.0)

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
				normals.append(UP_NORMAL)
				uvs.append(Vector2(tx, tz))
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
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
