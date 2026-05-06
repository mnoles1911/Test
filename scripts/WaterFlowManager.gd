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
# Vector3i (voxel coord) → int (packed). Transient store for in-flight
# flow cells produced by the legacy 4 Hz tick. Sources and ocean live
# in CHANNEL_DATA via the generator + VoxelEditManager — `_cells` is
# kept around solely so the simulator's gravity/spread/decay rules can
# still iterate active flow cells without a full chunk scan. To be
# retired in a future flow-tick rewrite.

var _horizon_plane_y: float = 10.0
# World-space Y of the distant-water horizon plane the WaterChunkMesher
# draws past its 64 m chunked-mesh radius. Settable at world load via
# set_horizon_plane_y so the active scene can match its generator's
# SEA_LEVEL_VOXELS. Kept on the manager (not the mesher) because the
# mesher reads it on every frame's follow-player update and the manager
# is the natural single owner of "what is the configured water level."

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
	# True if the world-space point is inside a water voxel.
	#
	# Phase 4 (CHANNEL_DATA-first model): the answer comes from a single
	# CHANNEL_DATA byte read at the voxel containing world_pos. The
	# generator writes water bytes only for above-terrain voxels in
	# below-sea-level columns — so a tunnel carved into a hill above
	# sea level reads as DRY (the column never had water at that XZ),
	# and a hole carved into the seabed reads as wet because the
	# generator wrote water at every voxel from ground_y+1 up to sea
	# level for that column.
	#
	# This delete the entire AABB-source-region path AND the
	# clear-vertical-path workaround that used to compensate for it.
	# The bug the workaround fixed (tunnels under sea level reading as
	# water just because they sat inside the ocean AABB) is now
	# impossible by construction: there's no AABB to be inside.
	#
	# Per-cell sources (player-placed buckets via add_source) ALSO go
	# through CHANNEL_DATA (Phase 3 redirected add_source via
	# VoxelEditManager). _cells is still maintained as a transient
	# in-memory cache for the legacy flow tick, but it's not consulted
	# here — a cell in _cells without a CHANNEL_DATA byte would be a
	# bug, and adding _cells fallback would mask such bugs.
	var byte: int = _read_water_byte_at(world_pos)
	return WaterByteCodec.is_water(byte)


func get_water_level_at(world_pos: Vector3) -> int:
	# Returns 0 (no water) or 1–8 (water level at this point). Used by
	# the water mesher for partial-height side faces and by current
	# computations for the velocity gradient.
	var byte: int = _read_water_byte_at(world_pos)
	return WaterByteCodec.level_of(byte)


func _read_water_byte_at(world_pos: Vector3) -> int:
	# One-voxel CHANNEL_DATA read at the voxel containing world_pos.
	# Returns 0 if the terrain isn't bound or the tool isn't available
	# (defensive — those conditions shouldn't happen during normal
	# play but might briefly during world load).
	if get_node_or_null("/root/VoxelEditManager") == null:
		return 0
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return 0
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return 0
	tool.channel = VoxelBuffer.CHANNEL_DATA5
	var voxel_pos: Vector3i = _world_to_voxel(world_pos)
	return tool.get_voxel(voxel_pos)


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
	# Reads CHANNEL_DATA first (the new authoritative store), then
	# falls back to _cells for transient flow cells.
	if get_node_or_null("/root/VoxelEditManager") != null:
		var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
		if terrain != null:
			var tool: VoxelTool = terrain.get_voxel_tool()
			if tool != null:
				tool.channel = VoxelBuffer.CHANNEL_DATA5
				var byte: int = tool.get_voxel(voxel_pos)
				var lvl: int = WaterByteCodec.level_of(byte)
				if lvl > 0:
					return lvl
	if _cells.has(voxel_pos):
		return (_cells[voxel_pos] as int) & _LEVEL_MASK
	return 0


func set_horizon_plane_y(world_y: float) -> void:
	# Configure the world-space Y for the distant-water horizon plane.
	# Called by World3DBootstrap (or any scene-specific bootstrap) so
	# the value can match that scene's generator SEA_LEVEL_VOXELS.
	# WaterChunkMesher consults the new value on its next follow-player
	# update — no explicit rebuild is needed for a tiny Y shift, but
	# call _rebuild_horizon_plane() if the mesher needs to re-spawn
	# (e.g. plane size change).
	_horizon_plane_y = world_y


func get_horizon_plane_y() -> float:
	return _horizon_plane_y


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
	# Wipes transient flow cells. Called by GameState before loading a
	# new save so no stale flow cells carry over from the previous
	# session. CHANNEL_DATA (the source of truth for ocean & sources)
	# is not touched here — it persists via SQLite chunk deltas and
	# reloads with the rest of the terrain.
	_cells.clear()
	_dirty_chunks.clear()


# ============================================================
# Public API — source placement
# ============================================================

func add_source(voxel_pos: Vector3i) -> void:
	# Mark a single voxel as a permanent water source. Used by Phase 7
	# bucket placement and by river-headwater authoring scripts.
	#
	# Phase 3: writes go through VoxelEditManager.queue_set_water_voxel
	# so the byte ends up in CHANNEL_DATA (the new source of truth)
	# rather than the legacy _cells dict. We still tag _cells and
	# _dirty_chunks for the brief Phase 3 transition window — the flow
	# tick continues to scan _cells until Phase 4 rewrites it around
	# the buffer-copy path. After that, _cells goes away entirely.
	if get_node_or_null("/root/VoxelEditManager") != null:
		VoxelEditManager.queue_set_water_voxel(voxel_pos, WaterByteCodec.SOURCE_BYTE)
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

	# Cache terrain + tool ONCE per tick. Previous code re-fetched
	# both per chunk per voxel — a 100× perf regression vs caching.
	# If the autoload/terrain isn't ready yet, drop the tick.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return

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
		budget -= _simulate_chunk_gravity(chunk, budget, terrain, tool)
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


func _simulate_chunk_gravity(chunk: Vector3i, budget: int, _terrain: VoxelLodTerrain, tool: VoxelTool) -> int:
	# Phase 4 (perf rewrite): full per-chunk simulation step using
	# pre-copied VoxelBuffers instead of per-voxel tool.get_voxel.
	#
	# The previous version called _is_water_at_voxel and _is_solid_at
	# inside the gravity-drop and lateral-spread inner loops. Each call
	# did get_node_or_null + get_voxel_tool + tool.get_voxel — a SceneTree
	# walk and tool reacquisition per voxel. At 4096 voxels per chunk,
	# 27 chunks per edit, 4 Hz, that's ~324 k tool calls/sec → 200-300
	# ms/sec just on flow reads. Same pattern that previously caused the
	# 6 s freeze in VoxelGravityManager (LESSONS_LEARNED 2026-05-05).
	#
	# Now: copy the chunk's CHANNEL_DATA5 + CHANNEL_COLOR into local
	# 16³ buffers ONCE per call, plus the chunk-above's CHANNEL_DATA5
	# for cross-chunk "above" reads at the y=15 boundary. Then walk the
	# buffers with cheap byte reads. Cross-chunk lateral neighbours fall
	# back to _is_water_at_voxel (rare — only voxels at chunk edges).
	#
	# Returns the number of cells modified (caller subtracts from budget).

	var voxel_min: Vector3i = chunk * CHUNK_SIZE_VOXELS
	var voxel_max: Vector3i = voxel_min + Vector3i(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)

	# Default the shared tool to COLOR so any slow-path _is_solid_at
	# fallback reads the right channel. tool.copy() takes an explicit
	# channel_mask so the buffer copies below are unaffected by this
	# setting.
	tool.channel = VoxelBuffer.CHANNEL_COLOR

	# ---- Pre-copy chunk buffers ----
	var data_buf := VoxelBuffer.new()
	data_buf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(voxel_min, data_buf, 1 << VoxelBuffer.CHANNEL_DATA5)

	var color_buf := VoxelBuffer.new()
	color_buf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(voxel_min, color_buf, 1 << VoxelBuffer.CHANNEL_COLOR)

	# Chunk above's CHANNEL_DATA5 — needed for the gravity-drop check
	# "is the voxel above water?" when the candidate voxel sits at
	# y=15 (top of chunk) and "above" crosses into the next chunk Y.
	var data_above_buf := VoxelBuffer.new()
	data_above_buf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	var voxel_min_above: Vector3i = voxel_min + Vector3i(0, CHUNK_SIZE_VOXELS, 0)
	tool.copy(voxel_min_above, data_above_buf, 1 << VoxelBuffer.CHANNEL_DATA5)

	# ---- Pre-screen ----
	# Replaces the old _chunk_has_any_water double-call (one for chunk,
	# one for chunk above). Walk the two buffers we already copied —
	# zero extra C++ calls.
	var any_water_here: bool = _buf_has_any_water(data_buf)
	var any_water_above: bool = _buf_has_any_water(data_above_buf)
	if not any_water_here and not any_water_above:
		return 0

	var modified: int = 0
	var dirty_neighbors: Dictionary = {}
	# Batch of CHANNEL_DATA5 writes accumulated during this chunk's
	# simulation. Applied at the end via tool.do_box once per write.
	var data5_writes: Array = []

	# ---- 1. Decay pass (unchanged) ----
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
			continue
		var current_level: int = _level_of(packed_cell)
		if current_level <= MIN_LEVEL:
			to_remove.append(cell_pos)
		else:
			to_decrement.append(cell_pos)
	for r in to_remove:
		_cells.erase(r)
		data5_writes.append({"pos": r, "byte": 0})
		modified += 1
		dirty_neighbors[_voxel_to_chunk(r)] = true
	for d in to_decrement:
		var p: int = _cells[d]
		var lvl: int = _level_of(p)
		var new_pack: int = _pack(lvl - 1, false, _last_fed_tick(p))
		_cells[d] = new_pack
		data5_writes.append({"pos": d, "byte": new_pack & 0xFF})
		modified += 1
		dirty_neighbors[_voxel_to_chunk(d)] = true

	# ---- 2. Gravity drop pass (buffer reads) ----
	# Walk every voxel in the chunk. For each air voxel, check if water
	# sits directly above. All checks use the pre-copied buffers; only
	# the NoEditZone gate falls back to the slow path (and that gate is
	# rare in practice).
	for lx in range(CHUNK_SIZE_VOXELS):
		for lz in range(CHUNK_SIZE_VOXELS):
			for ly in range(CHUNK_SIZE_VOXELS - 1, -1, -1):
				if modified >= budget:
					break
				# Buffer reads — no SceneTree, no tool acquisition.
				var here_byte: int = data_buf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_DATA5)
				if WaterByteCodec.is_water(here_byte):
					continue  # already water (source or flow); don't overwrite
				var here_color: int = color_buf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_COLOR)
				if (here_color & 0xFF) != 0:
					continue  # solid terrain

				# Check the voxel directly above. If at the top of the
				# chunk, read from the chunk-above buffer at local y=0.
				var above_byte: int
				if ly < CHUNK_SIZE_VOXELS - 1:
					above_byte = data_buf.get_voxel(lx, ly + 1, lz, VoxelBuffer.CHANNEL_DATA5)
				else:
					above_byte = data_above_buf.get_voxel(lx, 0, lz, VoxelBuffer.CHANNEL_DATA5)
				if not WaterByteCodec.is_water(above_byte):
					continue

				var pos: Vector3i = voxel_min + Vector3i(lx, ly, lz)
				if _is_water_blocked_at_voxel(pos):
					continue
				var grav_pack: int = _pack(MAX_LEVEL, false, _tick_count)
				_cells[pos] = grav_pack
				data5_writes.append({"pos": pos, "byte": grav_pack & 0xFF})
				modified += 1
				dirty_neighbors[_voxel_to_chunk(pos)] = true
				dirty_neighbors[_voxel_to_chunk(pos + Vector3i(0, -1, 0))] = true
			if modified >= budget:
				break
		if modified >= budget:
			break

	# ---- 3. Lateral spread pass (buffer-based source gather) ----
	# Build the source list from the pre-copied data buffer rather than
	# re-copying it inside _gather_lateral_sources. Then spread, using
	# buffer reads for in-chunk neighbours and the slow path for
	# cross-chunk edge neighbours.
	var spread_sources: Array = _gather_lateral_sources_buffered(
		voxel_min, voxel_max, data_buf,
	)
	for src in spread_sources:
		if modified >= budget:
			break
		var src_pos: Vector3i = src["pos"]
		var src_level: int = src["level"]
		if src_level <= MIN_LEVEL:
			continue
		var target_level: int = src_level - 1
		for dir in _LATERAL_DIRS:
			if modified >= budget:
				break
			var neighbor: Vector3i = src_pos + dir
			# Read neighbour state via buffer if in-chunk, else fallback.
			var n_in_chunk: bool = (
				neighbor.x >= voxel_min.x and neighbor.x < voxel_max.x
				and neighbor.y >= voxel_min.y and neighbor.y < voxel_max.y
				and neighbor.z >= voxel_min.z and neighbor.z < voxel_max.z
			)
			# Already in _cells — refresh tick if applicable.
			if _cells.has(neighbor):
				var n_packed: int = _cells[neighbor]
				if _is_source_packed(n_packed):
					continue
				var n_lvl: int = _level_of(n_packed)
				if n_lvl >= target_level:
					var refreshed_pack: int = _pack(n_lvl, false, _tick_count)
					_cells[neighbor] = refreshed_pack
					data5_writes.append({"pos": neighbor, "byte": refreshed_pack & 0xFF})
				continue
			# Already water in CHANNEL_DATA5? Skip.
			var n_water_byte: int
			var n_color_packed: int
			if n_in_chunk:
				var nlx: int = neighbor.x - voxel_min.x
				var nly: int = neighbor.y - voxel_min.y
				var nlz: int = neighbor.z - voxel_min.z
				n_water_byte = data_buf.get_voxel(nlx, nly, nlz, VoxelBuffer.CHANNEL_DATA5)
				n_color_packed = color_buf.get_voxel(nlx, nly, nlz, VoxelBuffer.CHANNEL_COLOR)
			else:
				# Cross-chunk fallback (rare — only at chunk edges).
				if _is_water_at_voxel(neighbor):
					continue
				if _is_solid_at(tool, neighbor):
					continue
				n_water_byte = 0
				n_color_packed = 0
			if WaterByteCodec.is_water(n_water_byte):
				continue
			if (n_color_packed & 0xFF) != 0:
				continue
			if _is_water_blocked_at_voxel(neighbor):
				continue
			# Below check: solid OR water below.
			var below: Vector3i = neighbor + Vector3i(0, -1, 0)
			var below_in_chunk: bool = (
				below.x >= voxel_min.x and below.x < voxel_max.x
				and below.y >= voxel_min.y and below.y < voxel_max.y
				and below.z >= voxel_min.z and below.z < voxel_max.z
			)
			var below_solid: bool = false
			var below_water: bool = false
			if below_in_chunk:
				var blx: int = below.x - voxel_min.x
				var bly: int = below.y - voxel_min.y
				var blz: int = below.z - voxel_min.z
				below_solid = (color_buf.get_voxel(blx, bly, blz, VoxelBuffer.CHANNEL_COLOR) & 0xFF) != 0
				if not below_solid:
					below_water = WaterByteCodec.is_water(
						data_buf.get_voxel(blx, bly, blz, VoxelBuffer.CHANNEL_DATA5)
					)
			else:
				below_solid = _is_solid_at(tool, below)
				if not below_solid:
					below_water = _is_water_at_voxel(below)
			if not (below_solid or below_water):
				continue
			var spread_pack: int = _pack(target_level, false, _tick_count)
			_cells[neighbor] = spread_pack
			data5_writes.append({"pos": neighbor, "byte": spread_pack & 0xFF})
			modified += 1
			dirty_neighbors[_voxel_to_chunk(neighbor)] = true

	# ---- Apply CHANNEL_DATA5 writes in one batched pass ----
	if not data5_writes.is_empty():
		tool.channel = VoxelBuffer.CHANNEL_DATA5
		for w in data5_writes:
			var wp: Vector3i = w["pos"]
			tool.value = w["byte"]
			tool.do_box(Vector3(wp), Vector3(wp) + Vector3.ONE)
		# Restore tool to COLOR — the caller may reuse the same tool
		# for the next chunk's color reads, and the remaining decay /
		# gravity reads we just did all assumed COLOR was the active
		# channel. Defensive: future code reusing this tool won't
		# silently read the wrong channel.
		tool.channel = VoxelBuffer.CHANNEL_COLOR

	for c in dirty_neighbors.keys():
		_dirty_chunks[c] = true
		water_changed.emit(c)

	return modified


func _buf_has_any_water(buf: VoxelBuffer) -> bool:
	# Linear scan for any nonzero water byte in the chunk buffer.
	# Replaces the per-chunk terrain.copy in the old _chunk_has_any_water
	# — caller passes in the already-copied buffer, so this is a pure
	# in-memory walk.
	#
	# Optimisation: VoxelBuffer.is_uniform tells us in O(1) whether the
	# whole channel holds a single value. Almost all chunks are uniform
	# (fully air → uniform 0; fully ocean → uniform SOURCE_BYTE), so
	# this short-circuits the 4096-read walk for the common case. Only
	# heterogeneous chunks (coastline, edits in progress) walk the full
	# 16³ — and those are rare.
	if buf.has_method("is_uniform"):
		var uniform_val: int = buf.call("get_voxel", 0, 0, 0, VoxelBuffer.CHANNEL_DATA5)
		if buf.call("is_uniform", VoxelBuffer.CHANNEL_DATA5):
			return uniform_val > 0
	for x in range(CHUNK_SIZE_VOXELS):
		for y in range(CHUNK_SIZE_VOXELS):
			for z in range(CHUNK_SIZE_VOXELS):
				if buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_DATA5) > 0:
					return true
	return false


func _gather_lateral_sources_buffered(
	voxel_min: Vector3i, voxel_max: Vector3i, data_buf: VoxelBuffer,
) -> Array:
	# Buffer-based variant of _gather_lateral_sources. Walks the
	# pre-copied data buffer for water voxels with level > MIN_LEVEL and
	# at least one horizontal neighbour that is air. Includes _cells-
	# only flow cells (transient) by adding them as a separate scan
	# step so the simulator catches both source bytes and in-flight
	# flow cells.
	var sources: Array = []
	# Pass 1: water voxels in the chunk's data buffer.
	for lx in range(CHUNK_SIZE_VOXELS):
		for ly in range(CHUNK_SIZE_VOXELS):
			for lz in range(CHUNK_SIZE_VOXELS):
				var byte: int = data_buf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_DATA5)
				var lvl: int = WaterByteCodec.level_of(byte)
				if lvl <= MIN_LEVEL:
					continue
				# Edge test: at least one horizontal neighbour is dry
				# (no water byte in CHANNEL_DATA5). For neighbours
				# outside the chunk, conservatively assume "dry" so the
				# spread fires at chunk edges (the spread loop itself
				# does the actual cross-chunk check).
				var pos := Vector3i(voxel_min.x + lx, voxel_min.y + ly, voxel_min.z + lz)
				var is_edge: bool = false
				for dir in _LATERAL_DIRS:
					var nlx: int = lx + dir.x
					var nly: int = ly + dir.y
					var nlz: int = lz + dir.z
					if nlx < 0 or nlx >= CHUNK_SIZE_VOXELS \
							or nly < 0 or nly >= CHUNK_SIZE_VOXELS \
							or nlz < 0 or nlz >= CHUNK_SIZE_VOXELS:
						# Cross-chunk edge — treat as candidate; the
						# spread loop will check the actual neighbour.
						is_edge = true
						break
					var n_byte: int = data_buf.get_voxel(nlx, nly, nlz, VoxelBuffer.CHANNEL_DATA5)
					if not WaterByteCodec.is_water(n_byte):
						is_edge = true
						break
				if is_edge:
					sources.append({"pos": pos, "level": lvl})
	# Pass 2: _cells flow entries inside the chunk that aren't already
	# covered by the buffer scan above (some flow cells may not have
	# been written back to CHANNEL_DATA5 yet on the current tick).
	for cell_pos in _cells.keys():
		if cell_pos.x < voxel_min.x or cell_pos.x >= voxel_max.x:
			continue
		if cell_pos.y < voxel_min.y or cell_pos.y >= voxel_max.y:
			continue
		if cell_pos.z < voxel_min.z or cell_pos.z >= voxel_max.z:
			continue
		var packed: int = _cells[cell_pos]
		var lvl_cell: int = _level_of(packed)
		if lvl_cell <= MIN_LEVEL:
			continue
		# Already in sources from Pass 1? Skip dedupe by checking the
		# buffer byte — if the buffer already has this cell as water,
		# Pass 1 covered it.
		var lx: int = cell_pos.x - voxel_min.x
		var ly: int = cell_pos.y - voxel_min.y
		var lz: int = cell_pos.z - voxel_min.z
		if WaterByteCodec.is_water(data_buf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_DATA5)):
			continue
		sources.append({"pos": cell_pos, "level": lvl_cell})
	return sources


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
	# CHANNEL_DATA source-edge detection: walk every voxel in the chunk
	# whose CHANNEL_DATA byte has water set, and emit it as a lateral-
	# spread source if at least one horizontal neighbour is dry. This
	# replaces the previous AABB source-region scan — the ocean is now
	# stored as real water bytes per voxel, so the edge of the ocean is
	# defined by water-byte voxels with dry neighbours.
	#
	# Bulk-read the chunk's CHANNEL_DATA once via terrain.copy() so we
	# don't pay tool.get_voxel cost per voxel. Same pattern used by
	# WaterChunkMesher and the Phase 4 _chunk_has_any_water scan.
	if get_node_or_null("/root/VoxelEditManager") != null:
		var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
		if terrain != null:
			var tool: VoxelTool = terrain.get_voxel_tool()
			if tool != null:
				var buf := VoxelBuffer.new()
				buf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
				tool.copy(voxel_min, buf, 1 << VoxelBuffer.CHANNEL_DATA5)
				for lx in range(CHUNK_SIZE_VOXELS):
					for ly in range(CHUNK_SIZE_VOXELS):
						for lz in range(CHUNK_SIZE_VOXELS):
							var byte: int = buf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_DATA5)
							var lvl_byte: int = WaterByteCodec.level_of(byte)
							if lvl_byte <= MIN_LEVEL:
								continue
							var pos := Vector3i(
								voxel_min.x + lx,
								voxel_min.y + ly,
								voxel_min.z + lz,
							)
							# Edge test: at least one horizontal neighbour is dry.
							var is_edge: bool = false
							for dir in _LATERAL_DIRS:
								var n: Vector3i = pos + dir
								if not _is_water_at_voxel(n):
									is_edge = true
									break
							if is_edge:
								sources.append({"pos": pos, "level": lvl_byte})
	return sources


func _is_water_at_voxel(voxel_pos: Vector3i) -> bool:
	# True if this voxel position is occupied by water. Two sources:
	#   1. CHANNEL_DATA byte (the new authoritative store — ocean from
	#      generator, buckets via VoxelEditManager edits).
	#   2. Legacy _cells dict (transient flow cells produced by the
	#      4 Hz flow tick; not yet migrated to CHANNEL_DATA writes).
	#
	# Either gives "water" → return true. Source-region AABB lookup is
	# GONE — Phase 4 migrated to CHANNEL_DATA, which fixes the tunnel-
	# under-mountain flooding bug at the source: there's no AABB to
	# wrongly claim every air voxel below sea level.
	if get_node_or_null("/root/VoxelEditManager") != null:
		var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
		if terrain != null:
			var tool: VoxelTool = terrain.get_voxel_tool()
			if tool != null:
				tool.channel = VoxelBuffer.CHANNEL_DATA5
				var byte: int = tool.get_voxel(voxel_pos)
				if WaterByteCodec.is_water(byte):
					return true
	if _cells.has(voxel_pos):
		return ((_cells[voxel_pos] as int) & _LEVEL_MASK) > 0
	return false


func _chunk_has_any_water(chunk: Vector3i) -> bool:
	# Pre-screen for the gravity scan. True if (a) any in-flight flow
	# cell sits in this chunk, or (b) any CHANNEL_DATA voxel in this
	# chunk has the water bit set. The legacy AABB check is gone — the
	# ocean now lives in CHANNEL_DATA so AABB lookups would be both
	# wrong and redundant.
	var voxel_min: Vector3i = chunk * CHUNK_SIZE_VOXELS
	var voxel_max: Vector3i = voxel_min + Vector3i(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	for cell_pos in _cells.keys():
		if cell_pos.x >= voxel_min.x and cell_pos.x < voxel_max.x \
			and cell_pos.y >= voxel_min.y and cell_pos.y < voxel_max.y \
			and cell_pos.z >= voxel_min.z and cell_pos.z < voxel_max.z:
			return true
	# CHANNEL_DATA bulk scan via terrain.copy(). Mirrors the pattern
	# in WaterChunkMesher._gather_surface_quads — one C++ copy + a
	# linear byte walk. Only called on dirty chunks within the active
	# 20 m flow radius, so the overhead is bounded (a few dozen chunks
	# per tick at 4 Hz worst-case).
	if get_node_or_null("/root/VoxelEditManager") == null:
		return false
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return false
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return false
	var buf := VoxelBuffer.new()
	buf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(voxel_min, buf, 1 << VoxelBuffer.CHANNEL_DATA5)
	for x in range(CHUNK_SIZE_VOXELS):
		for y in range(CHUNK_SIZE_VOXELS):
			for z in range(CHUNK_SIZE_VOXELS):
				if buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_DATA5) > 0:
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
