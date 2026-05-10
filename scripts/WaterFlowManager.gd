extends Node
# WaterFlowManager — autoload for Minecraft-style voxel water.
#
# What this is in plain English:
#
# Water in this game lives OUTSIDE the voxel terrain. Every water cell
# is an entry in a Dictionary<Vector3i, int> kept here. The voxel
# terrain (Zylann VoxelLodTerrain + VoxelMesherBlocky) never sees water
# voxels — material slot 5 in the VoxelBlockyLibrary is intentionally
# empty so writing TYPE=5 renders nothing. WaterChunkMesher emits the
# transparent surface mesh by walking this dictionary.
#
# Two kinds of "source" exist:
#   1. Source REGIONS: designer-placed AABBs (oceans, lakes, large
#      pools). Stored as a list, never materialized as individual
#      cells. is_position_in_water just AABB-tests against them. This
#      is how a 200×200 m ocean is represented in O(1) memory.
#   2. Per-cell sources: a single voxel marked is_source. River
#      headwaters, player-placed buckets. Stored in the cells
#      dictionary with the source bit set.
#
# Both kinds count as "is_source" for the flow rules that arrive in
# Phase 4 (monotone-decay). Source cells never decay; flowing cells
# do.
#
# Phase 1 scope (this file): dictionary + region storage, edit_applied
# subscription for dirty-chunk tracking, public query API. NO flow
# tick yet — sources stay where placed. Phases 3+ add the simulation.
#
# Reference: design/SWIMMING_AND_WATER.md, design/3D_VOXEL_MIGRATION.md


# ============================================================
# Constants
# ============================================================

# Active-simulation radius around the player, in meters. Cells beyond
# this radius freeze (flow tick skips them, monotone-decay halts).
# Phase 8 implements the freeze; Phase 1 just defines the constant.
const ACTIVE_RADIUS_M: float = 20.0

# Tick interval for the flow simulation (frames between ticks). At
# 60 fps physics, 15 frames = 4 Hz. Tuned to Minecraft's 5 Hz update
# rate — close enough that water "feels" right without burning frames
# on every physics tick.
const TICK_INTERVAL_FRAMES: int = 15

# Maximum water level. Source cells are always 8; flow cells decay
# from 8 → 7 → 6 → ... → 1, then evaporate at 0.
const MAX_LEVEL: int = 8

# Minimum water level. Cells at level 0 don't exist (they're removed
# from the dictionary).
const MIN_LEVEL: int = 1

# Bit layout for the packed cell int (Dictionary<Vector3i, int> value):
#   bits 0–3   : level (1–8; 0 means "removed" and shouldn't be stored)
#   bit  4     : is_source (1 = permanent, 0 = flow cell)
#   bits 5–12  : last_fed_tick (modulo 256, used by Phase 4 decay rule)
#   bits 13–15 : reserved
const _LEVEL_MASK: int = 0x000F
const _SOURCE_BIT: int = 0x0010
const _TICK_SHIFT: int = 5
const _TICK_MASK: int = 0x1FE0  # bits 5–12, shifted up

# Chunk dimensions — must match VoxelEditManager.CHUNK_SIZE_VOXELS and
# VoxelEditManager.VOXELS_PER_METER. Replicated here so this file
# doesn't need to call into private helpers on another autoload.
const VOXELS_PER_METER: float = 6.0
const CHUNK_SIZE_VOXELS: int = 16
const CHUNK_SIZE_M: float = float(CHUNK_SIZE_VOXELS) / VOXELS_PER_METER  # ≈ 2.667 m


# ============================================================
# Signals
# ============================================================

signal water_changed(chunk_coord: Vector3i)
# Fired when a chunk's water content changes (cell added/removed,
# region added/removed). WaterChunkMesher subscribes (Phase 2) to
# rebuild the affected chunk's surface mesh.


# ============================================================
# State
# ============================================================

var _cells: Dictionary = {}
# Vector3i (voxel coord) → int (packed). One entry per active water
# cell. Source regions are NOT materialized into _cells — they live
# in _source_regions only.

var _source_regions: Array = []
# List of dicts: {"aabb": AABB, "level": int}. Designer-placed water
# bodies (oceans, lakes). is_position_in_water tests against these
# AFTER checking _cells. Tested in insertion order; first match wins.

var _dirty_chunks: Dictionary = {}
# Vector3i (chunk coord) → true. Chunks that need their flow
# recomputed (Phase 3+) and surface mesh rebuilt (Phase 2). Populated
# by edit_applied subscription and by add_source / remove_source
# calls.

var _player_pos: Vector3 = Vector3.ZERO
# Cached most-recent player position, set by Player3D each physics
# frame via set_player_position(). Used to bound dirty-chunk scans
# to the active radius.

var _player_chunk: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
# Last seen player chunk coord. Used to detect chunk transitions and
# notify WaterChunkMesher (so it can update which chunks have meshes
# in the render radius).

var _chunk_mesher: Node3D = null
# Spawned in _ready as a child of this autoload. Owns the per-chunk
# MeshInstance3Ds for visible water surfaces. See WaterChunkMesher.gd.

var _frames_since_tick: int = 0
# Counts physics frames since the last flow tick. Tick fires when
# this hits TICK_INTERVAL_FRAMES.

var _tick_count: int = 0
# Monotonically increasing tick counter (modulo 256 for the
# last_fed_tick byte). Phase 4 uses this; Phase 3 just keeps it
# advancing.

const _MAX_FLOW_BUDGET_PER_TICK: int = 4096
# Cap on cells placed in a single flow tick. Prevents a sudden flood
# (e.g. a deep mineshaft carved under the ocean) from spiking frame
# time. Excess work spills to the next tick via _dirty_chunks
# remaining populated.


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	# Subscribe to terrain edits so we know when the player digs near
	# water and the flow tick needs to rescan that area.
	# VoxelEditManager autoload must already be loaded at this point —
	# project.godot order guarantees it.
	if get_node_or_null("/root/VoxelEditManager") != null:
		VoxelEditManager.edit_applied.connect(_on_edit_applied)

	# Spawn the surface mesher as a child of this autoload. Doing it
	# in code (rather than as a sibling autoload) keeps the mesher's
	# parent guaranteed to be us, and lets the mesher pull source
	# regions and signals from us via get_parent().
	var ChunkMesherScript := load("res://scripts/WaterChunkMesher.gd")
	if ChunkMesherScript != null:
		_chunk_mesher = Node3D.new()
		_chunk_mesher.name = "WaterChunkMesher"
		_chunk_mesher.set_script(ChunkMesherScript)
		add_child(_chunk_mesher)


func _physics_process(_delta: float) -> void:
	# Flow tick at TICK_INTERVAL_FRAMES (~4 Hz). Cheap when no chunks
	# are dirty — drains _dirty_chunks dictionary and ticks the counter.
	_frames_since_tick += 1
	if _frames_since_tick < TICK_INTERVAL_FRAMES:
		return
	_frames_since_tick = 0
	_tick_count = (_tick_count + 1) & 0xFF
	if not _dirty_chunks.is_empty():
		_run_flow_tick()


# ============================================================
# Public API — Player3D query path
# ============================================================

func set_player_position(world_pos: Vector3) -> void:
	# Player3D calls this each physics frame. Used to bound the flow
	# tick to a ball around the player and to drive the chunk mesher's
	# render-radius cull.
	_player_pos = world_pos
	var chunk: Vector3i = _world_to_chunk(world_pos)
	if chunk != _player_chunk:
		_player_chunk = chunk
		if _chunk_mesher != null and _chunk_mesher.has_method("set_player_chunk"):
			_chunk_mesher.set_player_chunk(chunk)
		# Resume flow on previously-frozen cells now back inside the
		# active radius. Cells that froze when the player walked away
		# get re-dirtied so monotone decay + propagation resume. O(cells)
		# scan per chunk transition — acceptable for sparse cell maps,
		# revisit if _cells routinely holds 10k+ entries.
		for cell_pos in _cells.keys():
			var c: Vector3i = _voxel_to_chunk(cell_pos)
			if _dirty_chunks.has(c):
				continue
			if _chunk_in_active_radius(c):
				_dirty_chunks[c] = true


func is_position_in_water(world_pos: Vector3) -> bool:
	# True if the world-space point is inside any water cell or any
	# source region. Used by Player3D to drive swim physics and by
	# UnderwaterFilter for the submersion tint.
	#
	# CRITICAL: a source-region AABB by itself is NOT enough. Old code
	# returned true any time the query point was inside the ocean's
	# 20×20 km horizontal AABB and below sea level — which meant any
	# tunnel the player carved below sea level (even on a mountaintop)
	# read as flooded. The fix is a per-call check that there's a
	# clear vertical column of air-or-water from the query voxel up
	# to the source region's surface_y. Player-carved tunnels have
	# solid terrain above them (the rest of the hill), which blocks
	# the path → not water. Real ocean cells have nothing but air
	# above → water. Same for natural underground caverns whose
	# ceiling is open via the source AABB's vertical extent.
	var voxel_pos := _world_to_voxel(world_pos)
	if _cells.has(voxel_pos):
		# Cell exists in active dictionary.
		var packed: int = _cells[voxel_pos]
		return (packed & _LEVEL_MASK) > 0
	for region in _source_regions:
		var aabb: AABB = region["aabb"] as AABB
		if not aabb.has_point(world_pos):
			continue
		var surface_y: float = aabb.position.y + aabb.size.y
		if _has_clear_vertical_path_to_surface(voxel_pos, surface_y):
			return true
	return false


func _has_clear_vertical_path_to_surface(start_voxel: Vector3i, surface_y_world: float) -> bool:
	# Walk upward from `start_voxel` to the source region's surface_y.
	# Returns true if every voxel above start_voxel up to surface is air.
	# Solid terrain blocks the claim — that's how we tell a real ocean
	# cell (clear column above) from a player-carved tunnel below sea
	# level (terrain above blocks the claim).
	#
	# Cost: O(surface_y - start_y) tool.get_voxel calls per query. For a
	# Y=10 ocean and a player at Y=-7, that's ~17 voxels worst-case at
	# 6 vox/m → ~17 µs per call. Player3D queries this every physics
	# frame for swim state — ~1 ms/sec overhead, acceptable.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return true  # Defensive: terrain not yet bound, fall back to AABB-only.
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return true
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return true
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	# Surface voxel = floor of (surface_y * VPM) - 1, since the surface
	# is the TOP face of the highest water voxel and we want to walk up
	# through air to reach it.
	var surface_voxel_y: int = int(floor(surface_y_world * VOXELS_PER_METER)) - 1
	if surface_voxel_y < start_voxel.y:
		# Query is at or above the surface — trivially "clear" (we're at
		# the surface itself or above).
		return true
	var y: int = start_voxel.y + 1
	while y <= surface_voxel_y:
		var packed: int = tool.get_voxel(Vector3i(start_voxel.x, y, start_voxel.z))
		# Solid voxel detected. Material id lives in bits 24-31.
		if ((packed >> 24) & 0xFF) != 0:
			return false
		y += 1
	return true


func get_water_level_at(world_pos: Vector3) -> int:
	# Returns 0 (no water) or 1–8 (water level at this point). Source
	# regions report MAX_LEVEL. Used by Phase 2 mesher for partial-
	# height side faces and by Phase 6 currents for gradient.
	var voxel_pos := _world_to_voxel(world_pos)
	if _cells.has(voxel_pos):
		return (_cells[voxel_pos] as int) & _LEVEL_MASK
	for region in _source_regions:
		if (region["aabb"] as AABB).has_point(world_pos):
			return int(region["level"])
	return 0


func get_flow_velocity_at(world_pos: Vector3) -> Vector3:
	# Compute a 3D current vector from the level gradient in the 4
	# horizontal neighbors. Direction = sum over neighbors of (dir ×
	# max(0, self_level - neighbor_level)); magnitude scaled by max
	# delta and capped at FLOW_MAX_SPEED.
	#
	# In the middle of an ocean (every neighbor at level 8 too), the
	# vector cancels to zero — oceans don't push. Currents only
	# happen at transitions: a river flowing toward an ocean (river
	# at level 7, ocean cell at level 8) generates a downstream push.
	var voxel_pos: Vector3i = _world_to_voxel(world_pos)
	var self_level: int = _level_at_voxel(voxel_pos)
	if self_level <= MIN_LEVEL:
		return Vector3.ZERO

	var accum := Vector3.ZERO
	var max_delta: int = 0
	for dir in _LATERAL_DIRS:
		var neighbor: Vector3i = voxel_pos + dir
		var n_level: int = _level_at_voxel(neighbor)
		var delta: int = self_level - n_level
		# Push AWAY from higher-level neighbors (water flows from high
		# to low). Positive delta means neighbor is lower → push toward
		# neighbor.
		if delta > 0:
			accum += Vector3(dir) * float(delta)
			if delta > max_delta:
				max_delta = delta

	if max_delta == 0 or accum.length_squared() < 0.0001:
		return Vector3.ZERO
	# Scale: max delta MAX_LEVEL → max FLOW_MAX_SPEED. Linear ramp.
	var scale: float = (float(max_delta) / float(MAX_LEVEL)) * FLOW_MAX_SPEED
	return accum.normalized() * scale


const FLOW_MAX_SPEED: float = 3.0
# Maximum river-current push speed (m/s) the player feels. 3.0
# matches the "Aldwater main channel" guideline in
# design/SWIMMING_AND_WATER.md. Steeper gradients clamp here.


func _level_at_voxel(voxel_pos: Vector3i) -> int:
	# Voxel-space variant of get_water_level_at, for use inside the
	# flow loop where world↔voxel conversions would be wasteful.
	if _cells.has(voxel_pos):
		return (_cells[voxel_pos] as int) & _LEVEL_MASK
	var world_pos: Vector3 = _voxel_center_world(voxel_pos)
	for region in _source_regions:
		if (region["aabb"] as AABB).has_point(world_pos):
			return int(region["level"])
	return 0


func get_source_regions() -> Array:
	# Read-only accessor for the source-region list. WaterChunkMesher
	# uses this to find the AABBs that intersect a chunk for surface-
	# mesh emission. Returning the live list (not a copy) is fine
	# because the mesher only iterates and does AABB tests.
	return _source_regions


func get_cells() -> Dictionary:
	# Read-only accessor for the active water cells dictionary. Used
	# by WaterChunkMesher in Phase 4+ to emit per-cell partial-height
	# surfaces.
	return _cells


# ============================================================
# Public API — save/load
# ============================================================

func get_save_data() -> Array:
	# Returns the save-format Array of source cells. Flowing cells are
	# NOT persisted — they regenerate from sources on load via the
	# normal flow tick. Source REGIONS aren't saved here either; they
	# come from designer-placed scene data and are re-added by the
	# scene's bootstrap on each world load.
	#
	# Format: Array of {"x", "y", "z"} dicts. Source flag is implicit
	# (anything in this list is a source). Phase 5+ save format.
	var entries: Array = []
	for cell_pos in _cells.keys():
		var packed: int = _cells[cell_pos]
		if not _is_source_packed(packed):
			continue
		entries.append({"x": cell_pos.x, "y": cell_pos.y, "z": cell_pos.z})
	return entries


func load_save_data(data: Array) -> void:
	# Restore source cells from a previously-saved entries list. Called
	# by GameState.load_save_file after the rest of state has loaded.
	# Doesn't clear flowing cells — they were never saved and would be
	# empty. Source regions are added separately by the world scene's
	# bootstrap, not here.
	for entry in data:
		if entry is Dictionary and entry.has_all(["x", "y", "z"]):
			var pos := Vector3i(int(entry["x"]), int(entry["y"]), int(entry["z"]))
			_cells[pos] = _pack(MAX_LEVEL, true, _tick_count)
			var chunk: Vector3i = _voxel_to_chunk(pos)
			_dirty_chunks[chunk] = true
			water_changed.emit(chunk)


func clear_persistent_state() -> void:
	# Wipes all cells and source regions. Called by GameState before
	# loading a new save so no stale water carries over from the
	# previous session.
	_cells.clear()
	_source_regions.clear()
	_dirty_chunks.clear()


# ============================================================
# Public API — source placement
# ============================================================

func add_source(voxel_pos: Vector3i) -> void:
	# Mark a single voxel as a permanent water source. Used by Phase 7
	# bucket placement and by river-headwater authoring scripts.
	var packed: int = MAX_LEVEL | _SOURCE_BIT
	_cells[voxel_pos] = packed
	var chunk: Vector3i = _voxel_to_chunk(voxel_pos)
	_dirty_chunks[chunk] = true
	water_changed.emit(chunk)


func remove_source(voxel_pos: Vector3i) -> void:
	# Remove a per-cell source. The cell becomes air (and any cells
	# downstream of it will evaporate over the next several flow ticks
	# once Phase 4 lands).
	if not _cells.has(voxel_pos):
		return
	_cells.erase(voxel_pos)
	var chunk: Vector3i = _voxel_to_chunk(voxel_pos)
	_dirty_chunks[chunk] = true
	water_changed.emit(chunk)


func add_source_region(aabb: AABB, level: int = MAX_LEVEL) -> void:
	# Register a large body of water (ocean, lake, large pool) as a
	# source region. The region is stored as an AABB; no per-cell
	# materialization. is_position_in_water tests against the AABB
	# directly, so a 200×200 m ocean costs O(1) memory.
	#
	# Designer authoring pattern: drop a Node3D in World3D.tscn with
	# attached metadata, and the World3DBootstrap script calls this
	# method on _ready with the metadata's AABB.
	#
	# We deliberately do NOT iterate chunks inside the AABB here. A
	# 200×200 m ocean spans ~69k chunks; dirty-marking each on world
	# load would emit 69k signals and permanently bloat _dirty_chunks
	# (cells outside the player's active radius would re-queue every
	# tick forever). WaterChunkMesher.set_player_chunk lazily dirty-
	# marks chunks within its render radius on every player chunk
	# transition, which already covers the visible-water case. The
	# flow tick doesn't need pre-marking either: source regions exist
	# implicitly and only spread INTO neighbors when an edit dirties
	# the boundary chunk.
	_source_regions.append({"aabb": aabb, "level": clampi(level, MIN_LEVEL, MAX_LEVEL)})
	# Tell the chunk mesher to rebuild its giant source-region planes
	# now that we have a new region. Without this trigger, the mesher's
	# initial deferred call from _ready fires BEFORE World3DBootstrap
	# adds regions (the autoload's deferred queue runs on the next
	# idle, but the scene's _ready chain hasn't finished). Result: 0
	# planes built. Calling here is idempotent — the mesher clears
	# old planes and rebuilds from the current region list.
	if _chunk_mesher != null \
			and _chunk_mesher.has_method("_rebuild_source_region_planes"):
		_chunk_mesher._rebuild_source_region_planes()


# ============================================================
# Global wind (driven by WeatherManager)
# ============================================================

# Path to the shared water shader material. Every WaterChunkMesher surface
# references this same .tres, so writing the wind parameters here updates
# every visible water surface at once.
const _WATER_MATERIAL_PATH: String = "res://assets/shaders/water_material.tres"
var _global_water_material: ShaderMaterial = null


func set_global_wind(direction: Vector3, strength: float) -> void:
	# Pushes wind into the water shader. Called by WeatherManager's per-frame
	# transition tween whenever the active weather state's wind values change.
	#
	# direction: world-space wind heading. Only the XZ component matters; the
	# shader takes a Vector2.
	# strength: 0..N multiplier on wave amplitude. State profiles range from
	# ~0.3 (FOG) to 3.5 (HEAVY_RAIN); the shader's sane upper bound is ~5.0.
	#
	# The material is loaded lazily on the first call so we don't pay the
	# load cost on cold worlds that never touch weather.
	if _global_water_material == null:
		_global_water_material = load(_WATER_MATERIAL_PATH) as ShaderMaterial
		if _global_water_material == null:
			push_warning("[WaterFlowManager] Could not load %s — wind parameters not applied" % _WATER_MATERIAL_PATH)
			return
	var dir_2d: Vector2 = Vector2(direction.x, direction.z)
	if dir_2d.length() > 0.0001:
		dir_2d = dir_2d.normalized()
	else:
		dir_2d = Vector2(1.0, 0.0)
	_global_water_material.set_shader_parameter("wind_dir", dir_2d)
	_global_water_material.set_shader_parameter("wind_strength", maxf(0.0, strength))


# ============================================================
# Edit subscription — dirty chunk tracking
# ============================================================

# ============================================================
# Flow simulation
# ============================================================

func _run_flow_tick() -> void:
	# Process every dirty chunk inside the active radius. Phase 3
	# implements gravity drop only — water in any cell or source
	# region cascades into air voxels directly below.
	#
	# Iterating the snapshot lets _on_edit_applied keep populating
	# _dirty_chunks during the tick (e.g. a cascade chain dirties
	# new chunks; those get processed next tick).
	var snapshot: Dictionary = _dirty_chunks.duplicate()
	_dirty_chunks.clear()

	var budget: int = _MAX_FLOW_BUDGET_PER_TICK
	for chunk in snapshot.keys():
		# Outside active radius? Drop. Cells in those chunks freeze in
		# place (no decay, no propagation). When the player returns,
		# either an edit or a player-chunk transition will re-dirty
		# them. Re-queueing every tick would permanently bloat
		# _dirty_chunks if the player ever flooded an area then walked
		# away.
		if not _chunk_in_active_radius(chunk):
			continue
		budget -= _simulate_chunk_gravity(chunk, budget)
		if budget <= 0:
			# Spilled the budget. Re-queue ONLY in-radius unprocessed
			# chunks for the next tick.
			for remaining in snapshot.keys():
				if remaining == chunk:
					continue
				if _dirty_chunks.has(remaining):
					continue
				if not _chunk_in_active_radius(remaining):
					continue
				_dirty_chunks[remaining] = true
			break


func _simulate_chunk_gravity(chunk: Vector3i, budget: int) -> int:
	# Phase 4: full per-chunk simulation step.
	#   1. Decay: non-source cells in this chunk that weren't fed in
	#      the previous tick decrement their level. Level 0 → removed.
	#   2. Gravity: air voxels with water directly above become flow
	#      cells at MAX_LEVEL.
	#   3. Lateral spread: cells (and source-region boundaries) push
	#      water horizontally into neighbors with solid below, at
	#      level = self.level - 1.
	#
	# Returns the number of cells modified (caller subtracts from
	# budget). Pre-screen: skip the chunk if neither it nor the chunk
	# above has any water.
	var chunk_above: Vector3i = chunk + Vector3i(0, 1, 0)
	if not _chunk_has_any_water(chunk) and not _chunk_has_any_water(chunk_above):
		return 0

	var terrain: VoxelLodTerrain = null
	if get_node_or_null("/root/VoxelEditManager") != null and VoxelEditManager.has_method("get_terrain"):
		terrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return 0
	var tool = terrain.get_voxel_tool()
	if tool == null:
		return 0
	tool.channel = VoxelBuffer.CHANNEL_TYPE

	var voxel_min: Vector3i = chunk * CHUNK_SIZE_VOXELS
	var voxel_max: Vector3i = voxel_min + Vector3i(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)

	var modified: int = 0
	var dirty_neighbors: Dictionary = {}

	# ---- 1. Decay pass ----
	# Iterate cells whose voxel positions fall inside this chunk.
	# Non-source cells with last_fed_tick != current_tick - 1 (or older)
	# decrement; level 0 means removed.
	var prev_tick: int = (_tick_count - 1) & 0xFF
	var to_remove: Array = []
	var to_decrement: Array = []
	for cell_pos in _cells.keys():
		if cell_pos.x < voxel_min.x or cell_pos.x >= voxel_max.x:
			continue
		if cell_pos.y < voxel_min.y or cell_pos.y >= voxel_max.y:
			continue
		if cell_pos.z < voxel_min.z or cell_pos.z >= voxel_max.z:
			continue
		var packed_cell: int = _cells[cell_pos]
		if _is_source_packed(packed_cell):
			continue
		var fed_tick: int = _last_fed_tick(packed_cell)
		if fed_tick == prev_tick or fed_tick == _tick_count:
			continue  # was fed this tick or last — stays alive
		var current_level: int = _level_of(packed_cell)
		if current_level <= MIN_LEVEL:
			to_remove.append(cell_pos)
		else:
			to_decrement.append(cell_pos)
	for r in to_remove:
		_cells.erase(r)
		modified += 1
		dirty_neighbors[_voxel_to_chunk(r)] = true
	for d in to_decrement:
		var p: int = _cells[d]
		var lvl: int = _level_of(p)
		_cells[d] = _pack(lvl - 1, false, _last_fed_tick(p))
		modified += 1
		dirty_neighbors[_voxel_to_chunk(d)] = true

	# ---- 2. Gravity drop pass ----
	# Air voxel directly below water → place flow cell at MAX_LEVEL.
	for x in range(voxel_min.x, voxel_max.x):
		for z in range(voxel_min.z, voxel_max.z):
			for y in range(voxel_max.y - 1, voxel_min.y - 1, -1):
				if modified >= budget:
					break
				var pos := Vector3i(x, y, z)
				if _cells.has(pos):
					continue
				if _is_solid_at(tool, pos):
					continue
				var above := pos + Vector3i(0, 1, 0)
				if not _is_water_at_voxel(above):
					continue
				if _is_water_blocked_at_voxel(pos):
					continue
				_cells[pos] = _pack(MAX_LEVEL, false, _tick_count)
				modified += 1
				dirty_neighbors[_voxel_to_chunk(pos)] = true
				dirty_neighbors[_voxel_to_chunk(pos + Vector3i(0, -1, 0))] = true
			if modified >= budget:
				break
		if modified >= budget:
			break

	# ---- 3. Lateral spread pass ----
	# For each cell or source-region boundary in this chunk, attempt
	# to spread to 4 horizontal neighbors. Source regions push at
	# level=MAX_LEVEL; cells push at level-1.
	var spread_sources: Array = _gather_lateral_sources(chunk, voxel_min, voxel_max)
	for src in spread_sources:
		if modified >= budget:
			break
		var src_pos: Vector3i = src["pos"]
		var src_level: int = src["level"]
		if src_level <= MIN_LEVEL:
			continue  # nothing to share — level 1 cells don't propagate
		var target_level: int = src_level - 1
		for dir in _LATERAL_DIRS:
			if modified >= budget:
				break
			var neighbor: Vector3i = src_pos + dir
			# Already water at neighbor with sufficient level — refresh
			# its last_fed_tick so it doesn't decay this tick.
			if _cells.has(neighbor):
				var n_packed: int = _cells[neighbor]
				if _is_source_packed(n_packed):
					continue
				var n_lvl: int = _level_of(n_packed)
				if n_lvl >= target_level:
					_cells[neighbor] = _pack(n_lvl, false, _tick_count)
				continue
			# Source region overlap? Skip — water already here logically.
			if _is_water_at_voxel(neighbor):
				continue
			if _is_solid_at(tool, neighbor):
				continue
			if _is_water_blocked_at_voxel(neighbor):
				continue
			# Lateral spread requires solid (or water) directly below
			# OR water below (water can't sit on air laterally; gravity
			# wins). If the cell-below is air, the gravity pass will
			# handle the drop on the next tick — don't double-place.
			var below := neighbor + Vector3i(0, -1, 0)
			if not (_is_solid_at(tool, below) or _is_water_at_voxel(below)):
				continue
			_cells[neighbor] = _pack(target_level, false, _tick_count)
			modified += 1
			dirty_neighbors[_voxel_to_chunk(neighbor)] = true

	for c in dirty_neighbors.keys():
		_dirty_chunks[c] = true
		water_changed.emit(c)

	return modified


# ---- Helpers used by the simulation pass ----

const _LATERAL_DIRS: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


func _is_solid_at(tool: Object, voxel_pos: Vector3i) -> bool:
	var packed: int = tool.get_voxel(voxel_pos)
	var mat_id: int = 0
	if get_node_or_null("/root/VoxelMaterialRegistry") != null:
		mat_id = VoxelMaterialRegistry.material_id_from_packed(packed)
	else:
		mat_id = packed & 0xFF
	return mat_id != 0


func _is_water_blocked_at_voxel(voxel_pos: Vector3i) -> bool:
	# Wraps NoEditZoneRegistry.is_water_flow_blocked_at with the world-
	# space conversion. Returns false if NoEditZoneRegistry isn't
	# loaded (fail-open: water flows freely if the registry is gone).
	if get_node_or_null("/root/NoEditZoneRegistry") == null:
		return false
	return NoEditZoneRegistry.is_water_flow_blocked_at(_voxel_center_world(voxel_pos))


func _gather_lateral_sources(_chunk: Vector3i, voxel_min: Vector3i, voxel_max: Vector3i) -> Array:
	# `_chunk` is the chunk Vector3i whose bounds are voxel_min..voxel_max.
	# Currently unused (the bounds fully determine which voxels we walk),
	# so it's underscore-prefixed to silence Godot's UNUSED_PARAMETER
	# warning. Kept in the signature so callers stay readable — passing
	# the chunk identity makes the call site self-documenting.
	# Build the list of "where can lateral spread originate from in
	# this chunk?" — cell-based water and source-region cells.
	#
	# Cell-based: every cell inside the chunk with level > 1.
	# Source-region: every voxel position inside this chunk that is
	# inside a source region. We enumerate the AABB ∩ chunk bounding
	# box. For source regions much larger than a chunk (the ocean),
	# every voxel position in the chunk overlapping the region counts —
	# but lateral spread only matters at the AABB EDGE (interior cells
	# spread into the same source region, no-op). So we walk the AABB
	# edge slice intersecting the chunk only.
	var sources: Array = []
	for cell_pos in _cells.keys():
		if cell_pos.x < voxel_min.x or cell_pos.x >= voxel_max.x:
			continue
		if cell_pos.y < voxel_min.y or cell_pos.y >= voxel_max.y:
			continue
		if cell_pos.z < voxel_min.z or cell_pos.z >= voxel_max.z:
			continue
		var packed: int = _cells[cell_pos]
		var lvl: int = _level_of(packed)
		if lvl > MIN_LEVEL:
			sources.append({"pos": cell_pos, "level": lvl})
	# Source-region edge cells. For each region whose AABB intersects
	# the chunk, identify the edge voxels along the AABB's XZ
	# perimeter at the AABB's top Y, intersected with the chunk.
	# Simpler approach: for every voxel in the chunk, test "is it
	# inside the region AND has at least one horizontal neighbor that
	# isn't?" — only edge voxels propagate.
	for region in _source_regions:
		var aabb: AABB = region["aabb"] as AABB
		var lvl_region: int = int(region["level"])
		# Quick chunk-vs-AABB overlap test in voxel space.
		var aabb_voxel_min := Vector3i(
			floori(aabb.position.x * 6.0),
			floori(aabb.position.y * 6.0),
			floori(aabb.position.z * 6.0),
		)
		var aabb_voxel_max := Vector3i(
			ceili((aabb.position.x + aabb.size.x) * 6.0),
			ceili((aabb.position.y + aabb.size.y) * 6.0),
			ceili((aabb.position.z + aabb.size.z) * 6.0),
		)
		var ix_min: int = maxi(voxel_min.x, aabb_voxel_min.x)
		var ix_max: int = mini(voxel_max.x, aabb_voxel_max.x)
		var iy_min: int = maxi(voxel_min.y, aabb_voxel_min.y)
		var iy_max: int = mini(voxel_max.y, aabb_voxel_max.y)
		var iz_min: int = maxi(voxel_min.z, aabb_voxel_min.z)
		var iz_max: int = mini(voxel_max.z, aabb_voxel_max.z)
		if ix_min >= ix_max or iy_min >= iy_max or iz_min >= iz_max:
			continue
		for x in range(ix_min, ix_max):
			for z in range(iz_min, iz_max):
				# Only the topmost source-region voxel per column
				# matters for surface-edge spread. Below the surface
				# we're inside the region — no edge.
				var top_y: int = iy_max - 1
				var pos := Vector3i(x, top_y, z)
				# Edge test: at least one horizontal neighbor NOT in
				# any source region.
				var is_edge: bool = false
				for dir in _LATERAL_DIRS:
					var n: Vector3i = pos + dir
					if not _is_water_at_voxel(n):
						is_edge = true
						break
				if is_edge:
					sources.append({"pos": pos, "level": lvl_region})
	return sources


func _is_water_at_voxel(voxel_pos: Vector3i) -> bool:
	# True if this voxel position is occupied by water — either an
	# active cell or inside a source region.
	if _cells.has(voxel_pos):
		return ((_cells[voxel_pos] as int) & _LEVEL_MASK) > 0
	# Source-region check: AABB.has_point on the voxel's center
	# (in world space).
	var world_pos: Vector3 = _voxel_center_world(voxel_pos)
	for region in _source_regions:
		if (region["aabb"] as AABB).has_point(world_pos):
			return true
	return false


func _chunk_has_any_water(chunk: Vector3i) -> bool:
	# Cheap pre-screen for the gravity scan. True if any cell in
	# this chunk is in _cells, OR any source region overlaps the
	# chunk's world-AABB.
	# O(cells_in_chunk + source_regions). For the common case of
	# a sparse cell map and a few source regions, this is fast.
	var voxel_min: Vector3i = chunk * CHUNK_SIZE_VOXELS
	var voxel_max: Vector3i = voxel_min + Vector3i(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	for cell_pos in _cells.keys():
		if cell_pos.x >= voxel_min.x and cell_pos.x < voxel_max.x \
			and cell_pos.y >= voxel_min.y and cell_pos.y < voxel_max.y \
			and cell_pos.z >= voxel_min.z and cell_pos.z < voxel_max.z:
			return true
	var chunk_aabb_min := Vector3(
		float(chunk.x) * CHUNK_SIZE_M,
		float(chunk.y) * CHUNK_SIZE_M,
		float(chunk.z) * CHUNK_SIZE_M,
	)
	var chunk_aabb := AABB(chunk_aabb_min, Vector3.ONE * CHUNK_SIZE_M)
	for region in _source_regions:
		if chunk_aabb.intersects(region["aabb"] as AABB):
			return true
	return false


func _chunk_in_active_radius(chunk: Vector3i) -> bool:
	var chunk_center := Vector3(
		(float(chunk.x) + 0.5) * CHUNK_SIZE_M,
		(float(chunk.y) + 0.5) * CHUNK_SIZE_M,
		(float(chunk.z) + 0.5) * CHUNK_SIZE_M,
	)
	return chunk_center.distance_to(_player_pos) <= ACTIVE_RADIUS_M + CHUNK_SIZE_M


func _voxel_center_world(voxel_pos: Vector3i) -> Vector3:
	return Vector3(
		(float(voxel_pos.x) + 0.5) / 6.0,
		(float(voxel_pos.y) + 0.5) / 6.0,
		(float(voxel_pos.z) + 0.5) / 6.0,
	)


# ============================================================
# Edit subscription — dirty chunk tracking
# ============================================================

func _on_edit_applied(_world_pos: Vector3, chunk_coord: Vector3i, _edit_aabb: AABB) -> void:
	# Voxel terrain changed. Mark the chunk + 1-chunk neighborhood
	# dirty so the flow tick (Phase 3+) rescans the area and the
	# surface mesher (Phase 2) rebuilds affected meshes.
	#
	# Why the neighborhood: an edit at the chunk boundary can affect
	# water flow in the adjacent chunk (water from chunk A spilling
	# into the new air voxel in chunk B).
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var c := chunk_coord + Vector3i(dx, dy, dz)
				_dirty_chunks[c] = true
				water_changed.emit(c)


# ============================================================
# Internal — coordinate helpers
# ============================================================

func _world_to_voxel(world_pos: Vector3) -> Vector3i:
	# Routes through VoxelEditManager so the conversion stays
	# canonical. If VEM isn't loaded yet (very early startup), fall
	# back to a local computation.
	if get_node_or_null("/root/VoxelEditManager") != null:
		return VoxelEditManager.world_to_voxel(world_pos)
	# Fallback: use the locked 6 vox/m scale.
	return Vector3i(
		floori(world_pos.x * 6.0),
		floori(world_pos.y * 6.0),
		floori(world_pos.z * 6.0),
	)


func _world_to_chunk(world_pos: Vector3) -> Vector3i:
	# Convert world-space (meters) to chunk coord. Chunk = 16 voxels =
	# 16/6 m on a side. Mirrors VoxelEditManager._world_to_chunk; the
	# constant lives there and we replicate to avoid a private call.
	return Vector3i(
		floori(world_pos.x / CHUNK_SIZE_M),
		floori(world_pos.y / CHUNK_SIZE_M),
		floori(world_pos.z / CHUNK_SIZE_M),
	)


func _voxel_to_chunk(voxel_pos: Vector3i) -> Vector3i:
	# Voxel coord → chunk coord (each chunk is 16 voxels per axis).
	#
	# GDScript's >> on int is an arithmetic right shift (sign-extends),
	# which is mathematically equivalent to floor(x / 16) for any signed
	# x. Earlier versions of this function added a `(x - 15) >> 4` for
	# negatives — that was over-correction that produced off-by-one
	# chunks for negative voxel coords (voxel x=-16 → chunk -2 instead
	# of -1), causing dirty marks and gravity scans to fire on the wrong
	# chunks for any work near the negative-coord side of origin (e.g.
	# the test pond at world x=-23).
	return Vector3i(voxel_pos.x >> 4, voxel_pos.y >> 4, voxel_pos.z >> 4)


# ============================================================
# Internal — packed-cell helpers (used Phase 3+)
# ============================================================

static func _level_of(packed: int) -> int:
	return packed & _LEVEL_MASK


static func _is_source_packed(packed: int) -> bool:
	return (packed & _SOURCE_BIT) != 0


static func _last_fed_tick(packed: int) -> int:
	return (packed & _TICK_MASK) >> _TICK_SHIFT


static func _pack(level: int, is_source: bool, last_fed_tick: int) -> int:
	var lvl: int = clampi(level, 0, MAX_LEVEL)
	var src: int = _SOURCE_BIT if is_source else 0
	var tick: int = (last_fed_tick & 0xFF) << _TICK_SHIFT
	return lvl | src | tick
