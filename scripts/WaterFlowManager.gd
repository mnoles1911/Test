extends Node
# WaterFlowManager — autoload for Minecraft-style voxel water.
#
# What this is in plain English:
#
# Water in this game lives OUTSIDE the voxel terrain. Every water cell
# is an entry in a Dictionary<Vector3i, int> kept here. The voxel
# terrain (Zylann VoxelLodTerrain + VoxelMesherCubes) never sees water
# voxels — they're invisible to the cube mesher. WaterChunkMesher
# (Phase 2) emits a separate transparent surface mesh by walking this
# dictionary.
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


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	# Subscribe to terrain edits so we know when the player digs near
	# water and the flow tick (Phase 3+) needs to rescan that area.
	# VoxelEditManager autoload must already be loaded at this point —
	# project.godot order guarantees it.
	if get_node_or_null("/root/VoxelEditManager") != null:
		VoxelEditManager.edit_applied.connect(_on_edit_applied)

	# Spawn the surface mesher as a child of this autoload. Doing it
	# in code (rather than as a sibling autoload) keeps the mesher's
	# parent guaranteed to be us, and lets the mesher pull source
	# regions and signals from us via get_parent().
	var WaterChunkMesher := load("res://scripts/WaterChunkMesher.gd")
	if WaterChunkMesher != null:
		_chunk_mesher = Node3D.new()
		_chunk_mesher.name = "WaterChunkMesher"
		_chunk_mesher.set_script(WaterChunkMesher)
		add_child(_chunk_mesher)


# ============================================================
# Public API — Player3D query path
# ============================================================

func set_player_position(world_pos: Vector3) -> void:
	# Player3D calls this each physics frame. Used to bound the flow
	# tick (Phase 3+) to a ball around the player and to drive the
	# chunk mesher's render-radius cull.
	_player_pos = world_pos
	var chunk: Vector3i = _world_to_chunk(world_pos)
	if chunk != _player_chunk:
		_player_chunk = chunk
		if _chunk_mesher != null and _chunk_mesher.has_method("set_player_chunk"):
			_chunk_mesher.set_player_chunk(chunk)


func is_position_in_water(world_pos: Vector3) -> bool:
	# True if the world-space point is inside any water cell or any
	# source region. Used by Player3D to drive swim physics and by
	# UnderwaterFilter for the submersion tint.
	var voxel_pos := _world_to_voxel(world_pos)
	if _cells.has(voxel_pos):
		# Cell exists in active dictionary.
		var packed: int = _cells[voxel_pos]
		return (packed & _LEVEL_MASK) > 0
	for region in _source_regions:
		if (region["aabb"] as AABB).has_point(world_pos):
			return true
	return false


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


func get_flow_velocity_at(_world_pos: Vector3) -> Vector3:
	# Phase 1: always zero (no flow simulation yet). Phase 6 implements
	# the level-gradient → velocity computation.
	return Vector3.ZERO


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
	_source_regions.append({"aabb": aabb, "level": clampi(level, MIN_LEVEL, MAX_LEVEL)})
	# Mark every chunk overlapping the AABB as dirty so Phase 2 mesher
	# emits surface meshes for them on first frame.
	var min_chunk: Vector3i = _world_to_chunk(aabb.position)
	var max_chunk: Vector3i = _world_to_chunk(aabb.position + aabb.size)
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			for cz in range(min_chunk.z, max_chunk.z + 1):
				var chunk := Vector3i(cx, cy, cz)
				_dirty_chunks[chunk] = true
				water_changed.emit(chunk)


# ============================================================
# Edit subscription — dirty chunk tracking
# ============================================================

func _on_edit_applied(_world_pos: Vector3, chunk_coord: Vector3i) -> void:
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
	const CHUNK_M: float = 16.0 / 6.0
	return Vector3i(
		floori(world_pos.x / CHUNK_M),
		floori(world_pos.y / CHUNK_M),
		floori(world_pos.z / CHUNK_M),
	)


func _voxel_to_chunk(voxel_pos: Vector3i) -> Vector3i:
	# Voxel coord → chunk coord (each chunk is 16 voxels per axis).
	return Vector3i(
		voxel_pos.x >> 4 if voxel_pos.x >= 0 else (voxel_pos.x - 15) >> 4,
		voxel_pos.y >> 4 if voxel_pos.y >= 0 else (voxel_pos.y - 15) >> 4,
		voxel_pos.z >> 4 if voxel_pos.z >= 0 else (voxel_pos.z - 15) >> 4,
	)


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
