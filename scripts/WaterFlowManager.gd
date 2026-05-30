extends Node

# Single-authority water-identity (path preload — headless-safe; see
# WaterMaterial.gd for why it has no class_name).
const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

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
const ACTIVE_RADIUS_M: float = 75.0  # Stage 6 connectivity-fill bound (was 20; designer 2026-05-18)

# Tick interval for the flow simulation (frames between ticks). At
# 60 fps physics, 15 frames = 4 Hz. Tuned to Minecraft's 5 Hz update
# rate — close enough that water "feels" right without burning frames
# on every physics tick.
const TICK_INTERVAL_FRAMES: int = 15

# Water Voxel V2 (2026-05-16): ENABLED. Routes _run_flow_tick to the
# v2 TYPE-5 sim (_run_flow_tick_v2 / _flow_chunk) — gravity drop +
# carve-gated flood, writes via VoxelEditManager.queue_set_water_voxel.
# Set false to fall back to static-water-only (no dig-to-flood) if the
# sim ever needs disabling for diagnosis.
const _FLOW_SIM_ENABLED: bool = true

# Water Voxel V2 / native-fluid pivot: "is this CHANNEL_TYPE value
# water?" is now owned by WaterMaterial (single authority — Phase 1).
# WATER_TYPE_ID stays as the canonical single representative id (writes
# / "full source water" synthesis); every READ test goes through
# WaterMaterial.is_water_type() so Phase 2/3 multi-id is one edit there.
const WATER_TYPE_ID: int = WaterMaterial.BODY_ID

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

var _sea_level_voxel_y: int = 72
# Voxel-grid Y where the generator writes water source bytes into
# CHANNEL_DATA5. WaterChunkMesher needs this to know which chunk-Y
# row to scan for water surfaces. Default 72 = Mira's
# CubicHeightmapGenerator.SEA_LEVEL_VOXELS — no behaviour change for
# World3D. Copper Isles overrides via set_sea_level_voxel_y(720) at
# bootstrap so the mesher scans the correct chunk-Y row (45) instead
# of the wrong-by-default chunk-Y row (4) where there are no water
# bytes for that scene.

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

var _diag_ticks_since_print: int = 0
# DIAG counter — _run_flow_tick prints a status line every 20 ticks
# (~5 sec at 4 Hz) when work is happening. Confirms whether _cells
# and _dirty_chunks are growing without bound (cascade bug) or
# stable (workload-driven).

const _MAX_FLOW_BUDGET_PER_TICK: int = 4096
# Cap on cells placed in a single flow tick. Prevents a sudden flood
# (e.g. a deep mineshaft carved under the ocean) from spiking frame
# time. Excess work spills to the next tick via _dirty_chunks
# remaining populated.

const WATER_FILL_CELLS_PER_TICK: int = 12
# THE FILL-SPEED DIAL (2026-05-18 bottom-up rewrite) — designer-tunable:
# edit, stop, run. Max water cells the connectivity fill converts per
# tick (4 Hz), clamped under the _MAX_FLOW_BUDGET_PER_TICK frame ceiling.
# This is now the ONLY rate knob. The previous "tiered" model (a fast
# 256/tick bulk tier for falling/submerged cells + a slow surface tier)
# was removed: it filled TOP-DOWN and ~20x too fast, because any cell
# with air below it ("falling") converted at the bulk rate regardless of
# height. The fill is now strictly BOTTOM-UP — the lowest reachable air
# cell always converts first (Y-bucketed frontier), so a basin fills
# from the floor and the waterline rises evenly, like real water. With
# one uniform rate the dial maps directly to that rise speed.
# Rough feel at 4 Hz (cells/s ≈ value × 4):
#   80 ≈ brisk   32 ≈ steady   12 ≈ slow, deliberate (default;
#   ~1/20 of the old effective bulk rate, per designer 2026-05-18)
#   4  ≈ very slow trickle
# A huge blasted cavern (tens of thousands of cells) deliberately takes
# minutes at 12 — the designer chose slow-but-complete over fast. Small
# ponds/trenches still finish in seconds. Coverage is guaranteed
# regardless of rate: the frontier is pure connectivity (no TTL, no
# carve-permission window) and dropped async writes self-heal (see the
# pending-expiry verify in _run_flow_tick_v2), so a low rate can never
# leave a cave half-full or holey.

var _edit_cell_ttl: Dictionary = {}
# Vector3i (voxel coord) → int (ticks remaining). Cells inside a recent
# VoxelEditManager edit aabb. Lateral spread can only write source
# bytes into cells that appear in this dictionary — so mining at water
# level fills the carved void from the adjacent sea source, but the
# new source can't propagate further onto natural beach-air cells
# (which were never edited and don't appear in this map). TTL counts
# down once per flow tick.
const EDIT_CELL_TTL: int = 600  # ~150 s at 4 Hz
# Stage 6 Phase 1 (2026-05-18): was 4 (~1 s). That 1-second carve-
# permission window was the root cause of two reported failures: a
# slowed fill (low WATER_FILL_CELLS_PER_TICK) or a large/overhung cave
# let the flood FRONT arrive at far cells AFTER their permission had
# already expired, so those cells became permanently unfillable and
# the cave stalled half-full. (Confirmed in the field: blasting more
# charges nearby "fixed" it only because _on_edit_applied re-stamped
# the TTL — not because water re-simulated.) Permission must outlive
# the time it takes a slow front to traverse the whole connected
# sub-sea void, so it is now generous. Still self-terminating and
# bounded: propagation only stamps sub-sea (npos.y <= sea_y) neighbours
# of cells that actually flooded, capped by _chunk_in_active_radius
# (20 m) and the per-tick budget; once the void is full there are no
# air cells left to flood, no new propagation, _dirty_chunks drains,
# the sim idles, and the stale entries age out. A connectivity-based
# gate (fill iff connected to a sub-sea source) is the proper Phase 3
# replacement; this is the correct, low-risk Phase 1 decoupling.

var _pending_water: Dictionary = {}
# Vector3i (voxel coord) → int (ticks remaining). #5 front-advance fix
# (2026-05-17). Flood/gravity writes go through VoxelEditManager's
# ASYNC queue, so a cell the sim filled this tick still reads as air
# from the next tick's CHANNEL_TYPE buffer copy until the queue drains
# (200-500 writes/window under load → multi-tick lag). The flood front
# then can't see its own just-written water, the "is a neighbour wet?"
# test fails, EDIT_CELL_TTL expires on far cells, and a cave/trench
# never finishes filling (measured: rej_unfed in the hundreds-to-1300
# with rej_above_sea=0). Every voxel the sim queues as water is added
# here and treated as water by the flood/gravity decision IMMEDIATELY,
# decoupling front advance from queue latency. Pruned two ways:
# confirm-on-read (erased the moment the buffer shows it really is
# water) + PENDING_WATER_TTL (safety net for writes that never land,
# e.g. NoEditZone-rejected). This is the role the abandoned legacy
# _cells cache used to play.
const PENDING_WATER_TTL: int = 40  # ~10 s at 4 Hz; confirm-on-read prunes sooner

# Stage 6 CONNECTIVITY FILL (2026-05-18) — replaces the incremental
# neighbour front (_edit_cell_ttl/fed/_flow_chunk). Cells reachable from
# a water source through connected sub-sea air/water are seeded by edits
# and expanded purely by connectivity, converted at the
# WATER_FILL_CELLS_PER_TICK rate. Deterministic: can't stall, never needs
# a re-mine kick; auto-levels at sea_y because nothing above it is ever
# enqueued; structures cleared when fully idle (memory reclaim). The
# frontier is Y-BUCKETED (lowest first) so the fill is bottom-up — see
# the _fill_buckets block below for the data structure.
# Y-BUCKETED frontier (2026-05-18 bottom-up rewrite). _fill_buckets maps
# an int voxel-Y to an Array of cells waiting at that height; the
# processor always drains the LOWEST non-empty bucket first, so water
# pools on the cave floor and the level rises evenly (bottom-up) instead
# of converting in seed-distance order (which looked top-down).
# _fill_enqueued is the in-queue guard (one entry per bucketed cell,
# erased on pop) so a cell is never double-queued but CAN be re-queued
# later by the dropped-write self-heal. _fill_active is the live cell
# count across all buckets (O(1) _frontier_count). _fill_retry caps how
# many times a rejected write (queue-full / NoEditZone) is retried so a
# transient drop self-heals while a permanent reject can't loop forever.
var _fill_buckets: Dictionary = {}
var _fill_enqueued: Dictionary = {}
var _fill_active: int = 0
var _fill_retry: Dictionary = {}
const FILL_MAX_RETRY: int = 40
# Raised 6 → 40 (2026-05-18). 6 was abandoning cells that lost the
# VoxelEditManager async-queue race a few times while the player was
# mining/blasting AND the fill was writing into the same queue — those
# became permanent surface holes. 40 retries × PENDING_WATER_TTL is
# plenty of real time; still bounded so a true NoEditZone reject ends.

# WATER SETTLE / EQUALIZE (2026-05-18) — "water finds its level". The
# connectivity fill can leave sparse holes when an async water write is
# dropped under heavy queue contention (mining while filling). This pass
# is the safety net + the realistic-physics smoothing: once the fill is
# idle, it sweeps the bounding box of everything converted this session,
# bottom-up, and re-queues ANY sub-sea AIR cell that still touches water
# — no retry cap, no dependence on per-cell pending tracking. It repeats
# until a whole pass finds nothing (the body is flat and solid), then
# clears. Bounded: one tracked AABB (the dug void — never the ocean,
# since only cells WE convert grow it), clamped to the active radius,
# capped per tick, and only while the player is near a dirty region.
var _settle_min: Vector3i = Vector3i(0x7fffffff, 0x7fffffff, 0x7fffffff)
var _settle_max: Vector3i = Vector3i(-0x7fffffff, -0x7fffffff, -0x7fffffff)
var _settle_dirty: bool = false        # a conversion happened → re-sweep
var _settle_y: int = 0x7fffffff        # bottom-up cursor (current scan Y)
var _settle_found: int = 0             # air-touching-water re-queued this pass
const SETTLE_SCAN_PER_TICK: int = 1024 # cells examined per flow tick (bounded)

var _prof: Node = null
# Cached /root/Profiler ref (see _ready) for the per-query WATER
# attribution wrapper. null when the Profiler autoload is absent.


# C++ port of the per-cell water-settle scan
# (extensions/voxel_gen/src/water_flow_cpp.cpp). When null, the autoload
# falls back to the original GD per-cell tool.get_voxel loop. Resolved
# in _ready via ClassDB.instantiate.
var _cpp_water: Resource = null


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

	# Cache the Profiler once so the per-query attribution wrapper
	# (_read_water_byte_at) doesn't do a /root lookup on every call —
	# the player hits this path ~4×/physics frame.
	_prof = get_node_or_null("/root/Profiler")

	# Resolve the C++ port for the per-cell settle-region scan
	# (extensions/voxel_gen/src/water_flow_cpp.cpp). The autoload stays
	# functional without it — _process_water_settle falls back to the
	# legacy per-cell GD loop when _cpp_water is null.
	if ClassDB.class_exists("WaterFlowCpp"):
		_cpp_water = ClassDB.instantiate("WaterFlowCpp")
		if _cpp_water != null:
			print("[WaterFlowManager] using C++ settle scan (WaterFlowCpp).")
		else:
			print("[WaterFlowManager] WaterFlowCpp registered but instantiate failed; using GD fallback.")
	else:
		print("[WaterFlowManager] WaterFlowCpp not registered; using GD fallback.")

	# Water Voxel V2 (2026-05-16): WaterChunkMesher + the horizon plane
	# are DELETED. Water is now a normal transparent TYPE block (id 5)
	# drawn by the terrain blocky mesher — there is no separate water
	# surface mesher to spawn. `_chunk_mesher` stays null; the few
	# remaining `if _chunk_mesher != null` call sites below are harmless
	# no-ops (left in place to keep this change minimal/low-risk for an
	# untested build; trimmed in a later cleanup).
	# See design/SWIMMING_AND_WATER.md.


func _physics_process(_delta: float) -> void:
	# MP-3: water flow simulation runs HOST-ONLY. Guests receive every
	# CHANNEL_DATA byte change as a normal voxel edit broadcast via
	# VoxelEditManager._rpc_replicate_edit, so the visible water state
	# stays in sync without each client running its own simulator.
	# In OFFLINE mode MultiplayerManager.is_host() returns true so
	# single-player path is unchanged.
	if get_node_or_null("/root/MultiplayerManager"):
		if not MultiplayerManager.is_host():
			return
	# Profiling wrapper — Profiler autoload + the in-HUD [PERF] log. The
	# Profiler call categorizes as WATER so the F3 overlay groups water
	# work together; HUDOverlay's profile_record keeps feeding the
	# always-on log line.
	var _t0_prof: int = Time.get_ticks_usec()
	_physics_process_inner()
	var _elapsed: int = Time.get_ticks_usec() - _t0_prof
	HUDOverlay.profile_record("WaterFlowManager", _elapsed)
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WATER", "WaterFlowManager", _elapsed)


func _physics_process_inner() -> void:
	# Flow tick at TICK_INTERVAL_FRAMES (~4 Hz). Cheap when no chunks
	# are dirty — drains _dirty_chunks dictionary and ticks the counter.
	_frames_since_tick += 1
	if _frames_since_tick < TICK_INTERVAL_FRAMES:
		return
	_frames_since_tick = 0
	_tick_count = (_tick_count + 1) & 0xFF
	# Stage 6 connectivity fill: the tick must keep firing while the BFS
	# frontier still has cells (or writes are in flight) — it is NOT
	# driven by dirty chunks any more. Gating only on _dirty_chunks here
	# was what stalled the fill after one tick (the "needs a re-mine
	# kick" bug). Goes cheap-idle the moment all three are empty.
	if not _dirty_chunks.is_empty() or _frontier_count() > 0 or not _pending_water.is_empty() or _settle_dirty:
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
		# revisit if _cells routinely holds 10k+ entries. Guarded by
		# is_empty() so the common no-flow-cells case (Copper Isles, Mira
		# pre-edit) doesn't pay the dictionary iteration setup cost on
		# every chunk crossing.
		if not _cells.is_empty():
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
	# This deletes the entire AABB-source-region path AND the
	# clear-vertical-path workaround that used to compensate for it.
	# The bug the workaround fixed (tunnels under sea level reading as
	# water just because they sat inside the ocean AABB) is now
	# impossible by construction: there's no AABB to be inside.
	#
	# Per-cell sources (player-placed buckets via add_source) ALSO go
	# through CHANNEL_DATA5 (Phase 3 redirected add_source via
	# VoxelEditManager). _cells is still maintained as a transient
	# in-memory cache for the legacy flow tick, but it's not consulted
	# here — a cell in _cells without a CHANNEL_DATA5 byte would be a
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
	# Profiler attribution wrapper around the actual read. Every player
	# water query (is_position_in_water / get_water_level_at) funnels
	# through here, so timing this single chokepoint attributes the
	# always-on query cost under the F3 overlay's WATER category
	# (the flow tick is wrapped separately in _physics_process).
	if _prof == null:
		return _read_water_byte_at_impl(world_pos)
	var _t0 := Time.get_ticks_usec()
	var _r := _read_water_byte_at_impl(world_pos)
	_prof.record("WATER", "WaterQuery", Time.get_ticks_usec() - _t0)
	return _r


func _read_water_byte_at_impl(world_pos: Vector3) -> int:
	# Water Voxel V2: water is a CHANNEL_TYPE=5 block. Read TYPE at the
	# voxel containing world_pos; if it's the water block, synthesise a
	# full WaterByteCodec source byte so every existing consumer
	# (is_position_in_water / get_water_level_at / velocity gradient)
	# keeps working unchanged. Returns 0 (no water) otherwise, or if
	# the terrain/tool isn't bound (briefly during world load).
	if get_node_or_null("/root/VoxelEditManager") == null:
		return 0
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return 0
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return 0
	var voxel_pos: Vector3i = _world_to_voxel(world_pos)
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	if WaterMaterial.is_water_type(tool.get_voxel(voxel_pos)):
		return WaterByteCodec.SOURCE_BYTE
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
	# Reads CHANNEL_DATA first (the new authoritative store), then
	# falls back to _cells for transient flow cells.
	if get_node_or_null("/root/VoxelEditManager") != null:
		var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
		if terrain != null:
			var tool: VoxelTool = terrain.get_voxel_tool()
			if tool != null:
				# Water Voxel V2: TYPE-5 block reads as full level 8.
				tool.channel = VoxelBuffer.CHANNEL_TYPE
				if WaterMaterial.is_water_type(tool.get_voxel(voxel_pos)):
					return MAX_LEVEL
	if _cells.has(voxel_pos):
		return (_cells[voxel_pos] as int) & _LEVEL_MASK
	return 0


func set_horizon_plane_y(world_y: float) -> void:
	# Configure the world-space Y for the distant-water horizon plane.
	# Called by World3DBootstrap (or any scene-specific bootstrap) so
	# the value can match that scene's generator SEA_LEVEL_VOXELS.
	#
	# Triggers a rebuild on the chunk mesher rather than waiting for
	# the per-frame follow-player update. Earlier we relied on the
	# follow-player path to reposition the plane, but that only fires
	# after the player actually moves more than FOLLOW_UPDATE_EPSILON_M
	# — in fly mode with no input the plane stayed at the build-time
	# default (Y=10) and ended up buried below the seabed in scenes
	# whose sea level is much higher (e.g. Copper Isles at Y=120).
	# Explicit rebuild closes the gap.
	_horizon_plane_y = world_y
	if _chunk_mesher != null and _chunk_mesher.has_method("_rebuild_horizon_plane"):
		_chunk_mesher.call("_rebuild_horizon_plane")


func get_horizon_plane_y() -> float:
	return _horizon_plane_y


func set_sea_level_voxel_y(voxel_y: int) -> void:
	# Set the voxel-grid Y where ocean water lives in CHANNEL_DATA5.
	# Determines which chunk-Y row WaterChunkMesher scans for surface
	# meshing. MUST match the active generator's sea_level_voxels —
	# bootstrap calls this with the same value it sets on the generator.
	_sea_level_voxel_y = voxel_y


func get_sea_level_voxel_y() -> int:
	return _sea_level_voxel_y


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
	# Remove a water block (bucket scoop). Water Voxel V2: clear the
	# CHANNEL_TYPE-5 block back to air via the edit queue so the change
	# persists and the blocky mesher stops drawing it. (Previously this
	# only erased the transient _cells entry, which no longer drives
	# rendering.)
	if get_node_or_null("/root/VoxelEditManager") != null:
		VoxelEditManager.queue_set_water_voxel(voxel_pos, WaterByteCodec.AIR_BYTE)
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
	# Water Voxel V2 (2026-05-16): the legacy cellular automaton below
	# operates on CHANNEL_DATA5 bytes. In the Minecraft model water is a
	# CHANNEL_TYPE=5 block — this old algorithm reads water as "solid
	# terrain" (here_type != 0) and would behave unpredictably on the
	# new world. Static water (generator ocean/lakes + bucket-placed
	# TYPE-5) needs NO simulation and renders correctly via the blocky
	# mesher. Dynamic propagation (dig-to-flood spread, river decay) is
	# a deliberately-deferred follow-up pass that needs a validated
	# baseline to test against — it is NOT safe to rewrite this 400-line
	# automaton blind on an untested build. So the tick is inert for v1:
	# drain the dirty set (so it can't accumulate) and return.
	# See design/SWIMMING_AND_WATER.md + design/WATER_STAGE6_PLAN.md
	# (native-fluid pivot section, formerly the V2-plan Stage 4 notes).
	# Const-gated (not a bare `return`) so the legacy body stays
	# reachable to the parser — no unreachable-code warning, zero risk
	# to this autoload compiling. Flip true only when the Stage-4
	# rewrite is done and validated.
	if not _FLOW_SIM_ENABLED:
		_dirty_chunks.clear()
		return
	# Water Voxel V2 (2026-05-16): TYPE-5 Minecraft-equivalent gameplay
	# flow. Delegate to the v2 sim and return. The `if` keeps the legacy
	# body below reachable to the parser (no unreachable-code risk); it
	# is dead code, kept only as reference for the deferred level-tracked
	# river refinement.
	if _FLOW_SIM_ENABLED:
		_run_flow_tick_v2()
		return

	# --- legacy DATA5 flow automaton (disabled; kept for the Stage-4
	#     follow-up rewrite reference) -----------------------------------
	var snapshot: Dictionary = _dirty_chunks.duplicate()
	_dirty_chunks.clear()

	# Decrement edit-cell TTLs. Cells whose TTL drops to 0 fall out of
	# the "lateral spread target" set, so any further spread into them
	# is blocked. This is what stops the post-carve cascade from
	# climbing onto the beach.
	if not _edit_cell_ttl.is_empty():
		var expired: Array = []
		for ep in _edit_cell_ttl.keys():
			var nttl: int = (_edit_cell_ttl[ep] as int) - 1
			if nttl <= 0:
				expired.append(ep)
			else:
				_edit_cell_ttl[ep] = nttl
		for ep in expired:
			_edit_cell_ttl.erase(ep)

	# DIAG counters scoped to this tick. Surfaces what's actually
	# growing during a perf-runaway capture — without this, captures
	# only show total WFM frame cost, not chunks-touched or _cells size.
	var _diag_chunks_in_radius: int = 0
	var _diag_chunks_out_radius: int = 0
	var _diag_total_modified: int = 0

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
			_diag_chunks_out_radius += 1
			continue
		_diag_chunks_in_radius += 1
		var before_budget: int = budget
		budget -= _simulate_chunk_gravity(chunk, budget, terrain, tool)
		_diag_total_modified += (before_budget - budget)
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

	# Diagnostic — fires every ~5 sec when work is happening. The
	# next perf capture will surface whether _cells/_dirty_chunks
	# are growing (cascade-feedback bug) or stable (workload-driven).
	# Cheap when no work: this whole branch is skipped because
	# _run_flow_tick only fires when _dirty_chunks is non-empty.
	_diag_ticks_since_print += 1
	if _diag_ticks_since_print >= 20:
		_diag_ticks_since_print = 0
		if _diag_chunks_in_radius > 0 or not _cells.is_empty():
			print("[WFM-DIAG] chunks_in=%d chunks_out=%d modified=%d _cells=%d _dirty=%d snapshot=%d" % [
				_diag_chunks_in_radius, _diag_chunks_out_radius, _diag_total_modified,
				_cells.size(), _dirty_chunks.size(), snapshot.size(),
			])


# ============================================================
# Water Voxel V2 flow sim (2026-05-16) — Minecraft-equivalent GAMEPLAY
# flow on CHANNEL_TYPE=5 blocks. Two rules per dirty chunk in the
# active radius, under the per-tick write budget:
#   1. GRAVITY  — a water block with air directly below makes the cell
#                 below water (the source above is NOT consumed →
#                 infinite ocean/lake, exactly like a Minecraft source).
#   2. FLOOD    — an air cell the player recently CARVED (edit-cell
#                 gate), at/below sea level, touching water above or on
#                 any of 4 sides, becomes water. Flooding refreshes the
#                 carve-permission of its sub-sea air neighbours so the
#                 flood front advances through a dug-out volume over
#                 successive ticks but can never run away into uncarved
#                 generator air pockets or above sea level.
# Pure decision layer: one CHANNEL_TYPE buffer read per chunk, all
# writes enqueued through VoxelEditManager.queue_set_water_voxel (the
# proven TYPE-5 path — re-meshes, MP-replicated, save-tracked). It
# never writes voxels/meshes directly, so it cannot desync or brick.
# Directional flowing-river visuals (partial-height level blocks) are
# a deliberately-deferred refinement (needs Stage-6 partial models).
# ============================================================

# Flow-sim diagnostics (2026-05-17). The v2 sim previously logged
# NOTHING, so "is dig-to-flood working?" was unanswerable. These count
# gravity-drop + flood enqueues per ~2 s window and print a sample, so
# the Output panel shows exactly what the sim does when you dig.
var _diag_flow_flood: int = 0
var _diag_flow_gravity: int = 0
var _diag_flow_ticks: int = 0
var _diag_flow_last: Vector3i = Vector3i.ZERO

# #3 flow-Y instrumentation (2026-05-17). The historical complaint is
# "digging next to water creates water ABOVE the start plane". V2's
# flood rule is gated `wpos.y <= sea_y` and gravity only moves water
# DOWN, so structurally it shouldn't climb — but #3 is "re-judge now
# that water is enterable", and the only honest way to close it is to
# MEASURE every write, not argue from the code. Per ~2 s window these
# track: the highest Y any flow WRITE landed on, how many writes were
# strictly above sea level, and the worst offending voxel. A clean run
# prints maxWriteY == sea_voxY and above_sea=0; a reproduction prints
# the exact climbing voxel so the fix can target the responsible rule.
var _diag_flow_max_write_y: int = 0
var _diag_flow_any_write: bool = false
var _diag_flow_above_sea: int = 0
var _diag_flow_worst_above: Vector3i = Vector3i.ZERO

# #5 residual diagnostic (2026-05-17). After the chunk-dirty fix the
# flood reaches far via powder blasts (flood 200+/window) but a thin
# hand-dug trench/cave still doesn't fully fill. Two reasons are
# possible and the write counters above can't tell them apart:
#   rej_above_sea — an edit-flagged AIR cell skipped purely because
#                   wpos.y > sea_y. This is CORRECT (water must not
#                   climb above sea level — the #3 gate). High here =
#                   the unfilled cave is just an uneven trench whose
#                   floor rises above voxel sea_y; not a sim bug.
#   rej_unfed     — an edit-flagged AIR cell at/below sea_y, not
#                   blocked, that had NO adjacent water this tick so
#                   it couldn't flood. Persistently high = the real
#                   front-advance/readback-lag bug (the front can't
#                   see its own just-queued water, TTL expires).
# One re-run of the same trench tells us which fix to write.
var _diag_flow_rej_above_sea: int = 0
var _diag_flow_rej_unfed: int = 0

# Stage 6 Phase 1: per-window histogram of the LEVEL each flooded /
# gravity cell was written at (index = level 1..8; index 0 unused).
# Proves the sim is producing a gradient (8 under vertical inflow,
# thinning 7→1 outward) rather than the old all-or-nothing full cells.
# Reset with the other _diag_flow_* counters every ~8 ticks.
var _diag_level_hist: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])


func _diag_register_write(pos: Vector3i, sea_y: int) -> void:
	# Called at every flow write site (gravity drop + flood fill) so the
	# throttled [FlowDiag] line can report whether water ever climbed
	# above the sea/start plane during digging. Pure bookkeeping — no
	# SceneTree, no allocation; safe in the inner flow loop.
	if not _diag_flow_any_write or pos.y > _diag_flow_max_write_y:
		_diag_flow_max_write_y = pos.y
	_diag_flow_any_write = true
	if pos.y > sea_y:
		_diag_flow_above_sea += 1
		if pos.y > _diag_flow_worst_above.y:
			_diag_flow_worst_above = pos


func _run_flow_tick_v2() -> void:
	var snapshot: Dictionary = _dirty_chunks.duplicate()
	_dirty_chunks.clear()

	# Age out edit-cell flood permissions (so flooding can't persist
	# forever once carving stops).
	if not _edit_cell_ttl.is_empty():
		var expired: Array = []
		for ep in _edit_cell_ttl.keys():
			var n: int = (_edit_cell_ttl[ep] as int) - 1
			if n <= 0:
				expired.append(ep)
			else:
				_edit_cell_ttl[ep] = n
		for ep in expired:
			_edit_cell_ttl.erase(ep)

	# Acquire the terrain tool first — the pending-water self-heal below
	# needs it to verify whether each expiring write actually landed.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var _heal_sea_y: int = get_sea_level_voxel_y()

	# Age out the pending-water set. Every cell the fill queued is tracked
	# here for PENDING_WATER_TTL ticks. When an entry EXPIRES we verify it:
	# if the cell really is water now, fine — drop it. If it is STILL air
	# (the async write was dropped — queue-full, or the chunk never became
	# editable) it is a would-be surface HOLE — re-bucket it so the fill
	# converts it again. This verify is the self-heal that makes a low
	# fill rate safe and kills the "holes in the top layer" the designer
	# reported. Bounded: only expiring entries are checked (few per tick),
	# and FILL_MAX_RETRY stops a permanent reject (NoEditZone) looping.
	if not _pending_water.is_empty():
		var pw_expired: Array = []
		for pp in _pending_water.keys():
			var pn: int = (_pending_water[pp] as int) - 1
			if pn <= 0:
				pw_expired.append(pp)
			else:
				_pending_water[pp] = pn
		for pp in pw_expired:
			_pending_water.erase(pp)
			var pv: Vector3i = pp as Vector3i
			if pv.y > _heal_sea_y:
				continue
			if tool.get_voxel(pv) != 0:
				continue   # confirmed water (or solid) — nothing to heal
			if _voxel_center_world(pv).distance_to(_player_pos) > ACTIVE_RADIUS_M + CHUNK_SIZE_M:
				continue   # out of range; a later edit/visit re-seeds it
			var rr: int = int(_fill_retry.get(pv, 0))
			if rr >= FILL_MAX_RETRY:
				continue   # permanent reject (e.g. NoEditZone) — stop looping
			_fill_retry[pv] = rr + 1
			_bucket_push(pv, true)   # force: pv is still in the visited set

	# Stage 6 Phase 1: throttle to the gradual-fill dial, still clamped
	# under the hard perf ceiling so a pathological flood can't spike
	# the frame. Unprocessed in-radius chunks already re-queue via the
	# budget-exhaustion spill below, so a low per-tick batch just means
	# the fill takes more ticks — exactly the slower, gradual rise we
	# want, and it also sharpens the level gradient.
	# Stage 6: connectivity fill replaces the per-chunk incremental
	# front. snapshot/_dirty_chunks are still cleared above because other
	# systems listen to water_changed; the fill itself is driven by the
	# Y-bucketed connectivity frontier (_fill_buckets), not dirty chunks.
	_process_connectivity_fill(tool)
	_process_water_settle(tool)   # "water finds its level" — runs only when fill is idle

	# Throttled diagnostic (~every 8 ticks ≈ 2 s) — only when the sim
	# actually did something, so the Output panel isn't flooded.
	_diag_flow_ticks += 1
	if _diag_flow_ticks >= 8:
		_diag_flow_ticks = 0
		if _diag_flow_flood > 0 or _frontier_count() > 0 or not snapshot.is_empty() or _settle_dirty:
			var _mwy_s: String = str(_diag_flow_max_write_y) if _diag_flow_any_write else "n/a"
			# Settle state — unambiguous "is the equalize pass still working
			# / has the surface converged". on(...) = sweeping (cursor Y of
			# the dug-void AABB + holes re-queued so far this pass); flat =
			# converged, body is solid + level, sweep stopped.
			var _settle_s: String = "flat"
			if _settle_dirty:
				_settle_s = "on(y%d found=%d)" % [_settle_y, _settle_found]
			# Stage 6 Phase 1: level histogram (cells written per level
			# 1..8 this window). A gradient prints as a spread (e.g.
			# lvl1-8=12/9/7/5/4/3/2/40); the OLD all-or-nothing sim would
			# put everything in slot 8 only. This is the Phase 1 in-game
			# gate — watch the spread populate as a pit fills.
			var _lvl_s: String = "%d/%d/%d/%d/%d/%d/%d/%d" % [
				_diag_level_hist[1], _diag_level_hist[2], _diag_level_hist[3],
				_diag_level_hist[4], _diag_level_hist[5], _diag_level_hist[6],
				_diag_level_hist[7], _diag_level_hist[8],
			]
			print("[FlowDiag] frontier=%d  filled=%d  gravity=%d  enqueued=%d  settle=%s  last=%s  sea_voxY=%d  maxWriteY=%s  above_sea=%d  worst=%s  rej_above_sea=%d  rej_unfed=%d  lvl1-8=%s  player=%s" % [
				_frontier_count(), _diag_flow_flood, _diag_flow_gravity,
				_fill_enqueued.size(), _settle_s, str(_diag_flow_last),
				get_sea_level_voxel_y(), _mwy_s, _diag_flow_above_sea,
				str(_diag_flow_worst_above), _diag_flow_rej_above_sea,
				_diag_flow_rej_unfed, _lvl_s, str(_world_to_voxel(_player_pos)),
			])
		_diag_flow_flood = 0
		_diag_flow_gravity = 0
		_diag_flow_any_write = false
		_diag_flow_above_sea = 0
		_diag_flow_worst_above = Vector3i.ZERO
		_diag_flow_rej_above_sea = 0
		_diag_flow_rej_unfed = 0
		_diag_level_hist = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])


func _bucket_push(p: Vector3i, force: bool = false) -> void:
	# Add a cell to its Y bucket. `_fill_enqueued` is a PERMANENT visited
	# set — a cell is queued at most once for the life of a fill, so the
	# BFS is linear and TERMINATES. (Erasing it on pop, as the first
	# bottom-up draft did, let every already-filled water cell perpetually
	# re-enqueue its neighbours: the frontier livelocked as a fixed-size
	# churn over the filled bottom and never advanced to the air front —
	# the "water stops after 8-10 voxels" stall.) `force` bypasses the
	# guard for the only two cases that legitimately re-queue a cell: an
	# out-of-range defer, and the dropped-write self-heal retrying a
	# specific cell whose async write never landed.
	if not force and _fill_enqueued.has(p):
		return
	_fill_enqueued[p] = true
	# NOTE: Dictionary.get(key, null) returns Nil on a miss, which GDScript
	# refuses to assign to a typed `Array` — use has() + create instead.
	if not _fill_buckets.has(p.y):
		_fill_buckets[p.y] = []
	var b: Array = _fill_buckets[p.y]
	b.append(p)   # Array is a reference type in Godot 4 — mutates in place
	_fill_active += 1


func _enqueue_fill_neighbors(c: Vector3i, sea_y: int) -> void:
	# Enqueue the 6 neighbours of a just-filled / water cell, NEVER above
	# sea_y (the waterline ceiling that auto-levels the body with the
	# ocean). Enqueue order no longer matters: the Y-bucketed processor
	# imposes strict bottom-up ordering globally, so a down-neighbour
	# lands in a lower bucket and is always serviced before higher cells.
	for d in [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
		var nb: Vector3i = c + d
		if nb.y > sea_y:
			continue
		_bucket_push(nb)


func _lowest_bucket_y() -> int:
	# The current waterline floor: smallest key with a non-empty bucket.
	# Bucket count is bounded by the cave's vertical span (tens of Y
	# levels), so this linear scan is trivially cheap at the fill rate.
	var lo: int = 0x7fffffff
	for k in _fill_buckets.keys():
		if k < lo:
			lo = k
	return lo


func _frontier_count() -> int:
	# Live cell count across all Y buckets (drives the tick gate + diag).
	return _fill_active


func _process_connectivity_fill(tool: VoxelTool) -> void:
	# Drain the BFS frontier at the gradual-fill rate. Everything in the
	# frontier is provably connected to a water source (it was enqueued
	# as a neighbour of a seed or an already-converted cell), so there
	# is no per-cell "fed" guess, no TTL, no stall, no re-mine kick.
	if _fill_active <= 0:
		# Genuinely idle (nothing reachable AND nothing in flight) →
		# reclaim every per-fill structure so the next dig starts fresh.
		# The pending self-heal ran earlier this tick, so if a hole still
		# needed filling _fill_active would be > 0 and we would not be
		# here — reaching this with pending empty means truly complete.
		if _pending_water.is_empty() and not _fill_enqueued.is_empty():
			_fill_buckets.clear()
			_fill_enqueued.clear()
			_fill_retry.clear()
		return
	var cap: int = clampi(WATER_FILL_CELLS_PER_TICK, 1, _MAX_FLOW_BUDGET_PER_TICK)
	var sea_y: int = get_sea_level_voxel_y()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var done: int = 0
	var scanned: int = 0
	var scan_cap: int = cap * 8 + 4096   # bound skips / water-passthrough / defers
	var out_of_range: Array[Vector3i] = []   # re-queued AFTER the loop (no in-tick spin)
	while done < cap and _fill_active > 0 and scanned < scan_cap:
		var y: int = _lowest_bucket_y()
		if y == 0x7fffffff:
			break
		var b: Array = _fill_buckets[y]
		var c: Vector3i = b.pop_back()
		_fill_active -= 1
		if b.is_empty():
			_fill_buckets.erase(y)
		# NOTE: do NOT erase _fill_enqueued[c] here. It is a permanent
		# visited set (see _bucket_push) — erasing on pop is exactly what
		# caused the filled-body livelock. Re-queues happen only via the
		# explicit force=true paths below (out-of-range / retry / heal).
		scanned += 1
		if _voxel_center_world(c).distance_to(_player_pos) > ACTIVE_RADIUS_M + CHUNK_SIZE_M:
			out_of_range.append(c)   # defer; fills when the player nears
			continue
		if c.y > sea_y:
			continue   # at/above waterline → drop (caps fill at sea level)
		if _pending_water.has(c):
			continue   # already queued this cell; heal/confirm handles it
		var t: int = tool.get_voxel(c)
		if WaterMaterial.is_water_type(t):
			# TERMINAL. Do NOT expand the frontier through water. Water is
			# the SOURCE BOUNDARY (pond / the generator's world ocean),
			# not something to traverse: propagating through it walked the
			# entire connected ocean — enqueued exploded to >1.3M, the
			# processor starved, and the surface layer never finished
			# (the "missing blocks / uneven top"). Connectivity is carried
			# purely by converting AIR and enqueuing the converted cell's
			# neighbours (seed = air-next-to-water); the fill therefore
			# stops dead at the ocean boundary instead of exploding into
			# it, while still filling the whole dug void.
			continue
		if t != 0:
			continue   # solid terrain blocks the void here
		# AIR, sub-sea, in range, connected → convert it to water. Bottom-
		# up ordering is implicit: this IS the lowest reachable cell.
		var ok: bool = VoxelEditManager.queue_set_water_voxel(c, WaterByteCodec.pack(WaterByteCodec.MAX_LEVEL, false, WaterByteCodec.DIR_STILL))
		if not ok:
			# Rejected: queue-full (transient) or NoEditZone (permanent).
			# Retry a bounded number of times so a transient drop self-
			# heals into a filled cell instead of a permanent hole; give
			# up after FILL_MAX_RETRY so a NoEditZone cell can't loop.
			var r: int = int(_fill_retry.get(c, 0))
			if r < FILL_MAX_RETRY:
				_fill_retry[c] = r + 1
				_bucket_push(c, true)   # force: c is still in the visited set
			continue
		_fill_retry.erase(c)
		_pending_water[c] = PENDING_WATER_TTL
		_diag_flow_flood += 1
		_diag_level_hist[WaterByteCodec.MAX_LEVEL] += 1
		_diag_flow_last = c
		_diag_register_write(c, sea_y)
		done += 1
		_enqueue_fill_neighbors(c, sea_y)
		_settle_note(c)   # grow the settle AABB; arm the equalize sweep
	for oc in out_of_range:
		_bucket_push(oc, true)   # force: still in visited set, must re-defer


func _settle_note(c: Vector3i) -> void:
	# Every cell the fill converts grows the settle AABB and re-arms the
	# equalize sweep. The box only ever covers cells WE filled (the dug
	# void), never the generator ocean — so the settle sweep stays bounded.
	_settle_min.x = mini(_settle_min.x, c.x)
	_settle_min.y = mini(_settle_min.y, c.y)
	_settle_min.z = mini(_settle_min.z, c.z)
	_settle_max.x = maxi(_settle_max.x, c.x)
	_settle_max.y = maxi(_settle_max.y, c.y)
	_settle_max.z = maxi(_settle_max.z, c.z)
	_settle_dirty = true


func _process_water_settle(tool: VoxelTool) -> void:
	# WATER FINDS ITS LEVEL. Runs only when the connectivity fill is idle
	# (so it never fights the active bottom-up front). Sweeps the tracked
	# dug-void AABB bottom-up, a bounded slice per tick; any sub-sea AIR
	# cell that still touches water is re-queued for conversion (forced,
	# no retry cap). When a FULL pass re-queues nothing the body is flat
	# and solid → the region is cleared and the sweep stops. This is the
	# permanent hole fix (independent of pending/retry) and the realistic
	# "equalize to a level surface" behaviour.
	if _fill_active > 0 or not _pending_water.is_empty():
		return   # fill still working — don't interfere
	if not _settle_dirty:
		return   # nothing converted since the last clean pass → settled
	if _settle_min.x > _settle_max.x:
		return   # no region yet
	var sea_y: int = get_sea_level_voxel_y()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	# Resume the bottom-up cursor; a fresh dig (dirty just re-armed with a
	# lower floor) restarts it at the region's lowest Y.
	if _settle_y > _settle_max.y or _settle_y < _settle_min.y:
		_settle_y = _settle_min.y
		_settle_found = 0
	var y_top: int = mini(_settle_max.y, sea_y)

	# ----- C++ FAST PATH -----------------------------------------------
	# WaterFlowCpp.scan_settle_region replaces the per-cell tool.get_voxel
	# inner loop (up to ~7 Variant calls per cell × scan_cap) with one
	# bulk-channel read + a tight native scan. GD still owns the
	# _bucket_push wiring and the settle bookkeeping.
	if _cpp_water != null and tool.has_method("copy"):
		var copy_min: Vector3i = Vector3i(_settle_min.x, _settle_y, _settle_min.z) - Vector3i(1, 1, 1)
		# We need the current Y stripe plus its +/- 1 Y neighbours for the
		# face-touch test, so the copied buffer's Y extent must cover from
		# _settle_y - 1 up to y_top + 1.
		var copy_max: Vector3i = Vector3i(_settle_max.x, y_top, _settle_max.z) + Vector3i(1, 1, 1)
		var copy_size: Vector3i = copy_max - copy_min + Vector3i.ONE
		var snap: VoxelBuffer = VoxelBuffer.new()
		snap.create(copy_size.x, copy_size.y, copy_size.z)
		var type_mask: int = 1 << VoxelBuffer.CHANNEL_TYPE
		tool.copy(copy_min, snap, type_mask)
		var result: Dictionary = _cpp_water.scan_settle_region(
			snap, copy_min, copy_max, _settle_y, y_top,
			SETTLE_SCAN_PER_TICK,
			_player_pos, ACTIVE_RADIUS_M + CHUNK_SIZE_M, VOXELS_PER_METER,
			_pending_water, _fill_retry, FILL_MAX_RETRY)
		var hits: PackedInt32Array = result["hits"]
		@warning_ignore("integer_division")
		var hit_count: int = hits.size() / 3
		for i in range(hit_count):
			var p_hit: Vector3i = Vector3i(hits[i * 3], hits[i * 3 + 1], hits[i * 3 + 2])
			_bucket_push(p_hit, true)
			_settle_found += 1
		_settle_y = int(result["next_y"])
		# fall through to the "did we finish?" tail below
	else:
		# ----- GD fallback path (legacy per-cell loop) ----------------
		var scanned: int = 0
		while _settle_y <= y_top and scanned < SETTLE_SCAN_PER_TICK:
			for x in range(_settle_min.x, _settle_max.x + 1):
				for z in range(_settle_min.z, _settle_max.z + 1):
					scanned += 1
					var p: Vector3i = Vector3i(x, _settle_y, z)
					if _voxel_center_world(p).distance_to(_player_pos) > ACTIVE_RADIUS_M + CHUNK_SIZE_M:
						continue
					if _pending_water.has(p):
						continue
					if int(_fill_retry.get(p, 0)) >= FILL_MAX_RETRY:
						continue   # permanently unfillable (e.g. NoEditZone) — let the sweep converge
					if tool.get_voxel(p) != 0:
						continue   # solid or already water — fine
					# AIR at/below sea level inside the filled region. If it
					# touches water it is a hole / not yet level → re-fill it.
					for d in [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
						if WaterMaterial.is_water_type(tool.get_voxel(p + d)):
							_bucket_push(p, true)
							_settle_found += 1
							break
			_settle_y += 1
	if _settle_y > y_top:
		# Finished a full bottom-up pass over the region.
		if _settle_found == 0:
			# Nothing left to level anywhere → the body is solid + flat.
			_settle_dirty = false
			_settle_min = Vector3i(0x7fffffff, 0x7fffffff, 0x7fffffff)
			_settle_max = Vector3i(-0x7fffffff, -0x7fffffff, -0x7fffffff)
		# else: re-buckets were made; the fill will drain them, go idle
		# again, and _settle_dirty stays set so we sweep once more — this
		# repeats until a pass is clean (true convergence).
		_settle_y = 0x7fffffff
		_settle_found = 0


func _seed_fill_from_aabb(vmin: Vector3i, vmax: Vector3i) -> void:
	# An edit landed. Seed the BFS at every AIR cell in the edit box
	# that the carve just put NEXT TO water (pond/ocean or water already
	# placed) and that is at/below sea level. Connectivity expands from
	# there through the rest of the dug-out air, so the whole connected
	# sub-sea void floods and levels out — no edit-region gate (a tunnel
	# into a natural sub-sea cave floods it too, by design). If nothing
	# in the box touches water, nothing seeds (a sealed dry pit stays
	# dry until a later edit connects it to a source).
	if get_node_or_null("/root/VoxelEditManager") == null:
		return
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var sea_y: int = get_sea_level_voxel_y()
	var dirs: Array = [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for x in range(vmin.x, vmax.x + 1):
		for y in range(vmin.y, mini(vmax.y, sea_y) + 1):   # nothing above sea_y
			for z in range(vmin.z, vmax.z + 1):
				var p: Vector3i = Vector3i(x, y, z)
				if _fill_enqueued.has(p):
					continue
				if tool.get_voxel(p) != 0:
					continue   # only AIR cells can seed the fill
				for d in dirs:
					if WaterMaterial.is_water_type(tool.get_voxel(p + d)):
						_bucket_push(p, true)   # force: a fresh carve must (re)seed even if visited
						break


func _eff_level(data5_byte: int) -> int:
	# Stage 6 Phase 1: the effective LEVEL of a neighbour that
	# CHANNEL_TYPE already says is water. A DATA5 level of 0 means the
	# cell is water (TYPE 5) but has no Stage-6 byte yet — generator
	# ocean, a pre-Stage-6 save, or water placed before this code. Treat
	# that as FULL (8): existing water is conservatively a full feed, so
	# the gradient only thins where the sim itself produced a thin cell.
	var lvl: int = WaterByteCodec.level_of(data5_byte)
	return WaterByteCodec.MAX_LEVEL if lvl == 0 else lvl


func _flow_chunk(chunk: Vector3i, budget: int, tool: VoxelTool) -> int:
	# One CHANNEL_TYPE copy of this chunk + the chunk below (gravity at
	# y=0) + the chunk above (flood "water directly above" at y=15).
	# Cheap byte reads thereafter; decisions only.
	var vmin: Vector3i = chunk * CHUNK_SIZE_VOXELS
	tool.channel = VoxelBuffer.CHANNEL_TYPE

	var tbuf := VoxelBuffer.new()
	tbuf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(vmin, tbuf, 1 << VoxelBuffer.CHANNEL_TYPE)

	var tbelow := VoxelBuffer.new()
	tbelow.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(vmin - Vector3i(0, CHUNK_SIZE_VOXELS, 0), tbelow, 1 << VoxelBuffer.CHANNEL_TYPE)

	var tabove := VoxelBuffer.new()
	tabove.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(vmin + Vector3i(0, CHUNK_SIZE_VOXELS, 0), tabove, 1 << VoxelBuffer.CHANNEL_TYPE)

	# Stage 6 Phase 1: also snapshot CHANNEL_DATA5 (the WaterByteCodec
	# level/dir byte) for this chunk + the chunk above, so the flood
	# rule can read a feeding neighbour's actual LEVEL (gradient water)
	# instead of treating every water cell as full. Lateral neighbours
	# are always in-chunk here (cross-chunk spread rides the dirty-chunk
	# front, §_flow_chunk below); only the vertical-above neighbour can
	# be in the chunk above. Gravity (falling water) is always full so
	# it needs no DATA5 read of the chunk below.
	tool.channel = VoxelBuffer.CHANNEL_DATA5
	var dbuf := VoxelBuffer.new()
	dbuf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(vmin, dbuf, 1 << VoxelBuffer.CHANNEL_DATA5)
	var dabove := VoxelBuffer.new()
	dabove.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(vmin + Vector3i(0, CHUNK_SIZE_VOXELS, 0), dabove, 1 << VoxelBuffer.CHANNEL_DATA5)

	var sea_y: int = get_sea_level_voxel_y()
	var changed: int = 0
	var n: int = CHUNK_SIZE_VOXELS

	for lx in range(n):
		for lz in range(n):
			for ly in range(n):
				if changed >= budget:
					return changed
				var here: int = tbuf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_TYPE)
				var wpos: Vector3i = vmin + Vector3i(lx, ly, lz)

				# Confirm-on-read: the queued write for this cell has
				# landed in the buffer -- drop it from the pending set.
				if WaterMaterial.is_water_type(here) and _pending_water.has(wpos):
					_pending_water.erase(wpos)

				if WaterMaterial.is_water_type(here) or _pending_water.has(wpos):
					# --- GRAVITY: water (incl. just-queued pending water)
					# with air directly below falls, so a freshly-flooded
					# column keeps draining each tick instead of stalling
					# on the async edit queue. ---
					var below: int
					if ly > 0:
						below = tbuf.get_voxel(lx, ly - 1, lz, VoxelBuffer.CHANNEL_TYPE)
					else:
						below = tbelow.get_voxel(lx, n - 1, lz, VoxelBuffer.CHANNEL_TYPE)
					var bpos: Vector3i = wpos - Vector3i(0, 1, 0)
					if below == 0 and not _pending_water.has(bpos):
						if not _is_water_blocked_at_voxel(bpos):
							# Stage 6 Phase 1: falling water is a FULL (level 8)
							# NON-source flow cell — not SOURCE_BYTE. Only the
							# generator's ocean/lake cells keep the source bit
							# (foundation for #14); sim water must be drainable.
							VoxelEditManager.queue_set_water_voxel(bpos, WaterByteCodec.pack(WaterByteCodec.MAX_LEVEL, false, WaterByteCodec.DIR_STILL))
							_pending_water[bpos] = PENDING_WATER_TTL
							_dirty_chunks[_voxel_to_chunk(bpos)] = true
							changed += 1
							_diag_flow_gravity += 1
							_diag_level_hist[WaterByteCodec.MAX_LEVEL] += 1
							_diag_flow_last = bpos
							_diag_register_write(bpos, sea_y)
					continue

				if here != 0:
					continue  # solid terrain (TYPE != 0 and != water)

				# --- FLOOD: air cell. ---
				if not _edit_cell_ttl.has(wpos):
					continue  # only fill what the player carved
				if wpos.y > sea_y:
					_diag_flow_rej_above_sea += 1
					continue  # no source pressure above sea level
				if _is_water_blocked_at_voxel(wpos):
					continue

				var fed: bool = false
				var av: int
				if ly < n - 1:
					av = tbuf.get_voxel(lx, ly + 1, lz, VoxelBuffer.CHANNEL_TYPE)
				else:
					av = tabove.get_voxel(lx, 0, lz, VoxelBuffer.CHANNEL_TYPE)
				if WaterMaterial.is_water_type(av):
					fed = true
				if not fed and lx > 0 and WaterMaterial.is_water_type(tbuf.get_voxel(lx - 1, ly, lz, VoxelBuffer.CHANNEL_TYPE)):
					fed = true
				if not fed and lx < n - 1 and WaterMaterial.is_water_type(tbuf.get_voxel(lx + 1, ly, lz, VoxelBuffer.CHANNEL_TYPE)):
					fed = true
				if not fed and lz > 0 and WaterMaterial.is_water_type(tbuf.get_voxel(lx, ly, lz - 1, VoxelBuffer.CHANNEL_TYPE)):
					fed = true
				if not fed and lz < n - 1 and WaterMaterial.is_water_type(tbuf.get_voxel(lx, ly, lz + 1, VoxelBuffer.CHANNEL_TYPE)):
					fed = true
				# Stage 6 hydrostatic rise (2026-05-18): water directly
				# BELOW also feeds this cell, so a connected sub-sea void
				# fills UPWARD and levels out, instead of the front dying
				# the moment the only way left is up (the "cave only
				# half-fills, needs a re-mine kick" bug). Safe: the
				# `wpos.y > sea_y` gate above already rejected anything
				# above sea level, so water can only rise TO it, never past.
				if not fed:
					var _vb: int
					if ly > 0:
						_vb = tbuf.get_voxel(lx, ly - 1, lz, VoxelBuffer.CHANNEL_TYPE)
					else:
						_vb = tbelow.get_voxel(lx, n - 1, lz, VoxelBuffer.CHANNEL_TYPE)
					if WaterMaterial.is_water_type(_vb):
						fed = true
				if not fed and (
						_pending_water.has(wpos + Vector3i(0, 1, 0))
						or _pending_water.has(wpos + Vector3i(-1, 0, 0))
						or _pending_water.has(wpos + Vector3i(1, 0, 0))
						or _pending_water.has(wpos + Vector3i(0, 0, -1))
						or _pending_water.has(wpos + Vector3i(0, 0, 1))
						or _pending_water.has(wpos + Vector3i(0, -1, 0))):
					# Neighbour flooded this tick but its async write has
					# not landed in the buffer yet -- treat pending water
					# as water so the front advances every tick (#5 fix).
					fed = true

				if not fed:
					# Edit-flagged, at/below sea_y, not blocked, yet no
					# adjacent water this tick → the front-stall signature.
					_diag_flow_rej_unfed += 1
				if fed:
					# Stage 6 Phase 1: level of this newly-flooded cell.
					# Water (or not-yet-landed pending water) directly
					# above, or any pending neighbour (#5), = a full
					# column (8). Otherwise this is pure lateral spread:
					# strongest lateral water neighbour's level minus one,
					# floored at MIN_LEVEL (the Minecraft thinning rule).
					# The proven `fed` detection above is left untouched;
					# this only recomputes feed strength for cells already
					# being written, so flood COVERAGE is unchanged.
					var _vabove: int = (tbuf.get_voxel(lx, ly + 1, lz, VoxelBuffer.CHANNEL_TYPE) if ly < n - 1 else tabove.get_voxel(lx, 0, lz, VoxelBuffer.CHANNEL_TYPE))
					var _full_feed: bool = (
						WaterMaterial.is_water_type(_vabove)
						or WaterMaterial.is_water_type(tbuf.get_voxel(lx, ly - 1, lz, VoxelBuffer.CHANNEL_TYPE) if ly > 0 else tbelow.get_voxel(lx, n - 1, lz, VoxelBuffer.CHANNEL_TYPE))
						or _pending_water.has(wpos + Vector3i(0, 1, 0))
						or _pending_water.has(wpos + Vector3i(-1, 0, 0))
						or _pending_water.has(wpos + Vector3i(1, 0, 0))
						or _pending_water.has(wpos + Vector3i(0, 0, -1))
						or _pending_water.has(wpos + Vector3i(0, 0, 1))
					)
					var _mlat: int = 0
					if lx > 0 and WaterMaterial.is_water_type(tbuf.get_voxel(lx - 1, ly, lz, VoxelBuffer.CHANNEL_TYPE)):
						_mlat = max(_mlat, _eff_level(dbuf.get_voxel(lx - 1, ly, lz, VoxelBuffer.CHANNEL_DATA5)))
					if lx < n - 1 and WaterMaterial.is_water_type(tbuf.get_voxel(lx + 1, ly, lz, VoxelBuffer.CHANNEL_TYPE)):
						_mlat = max(_mlat, _eff_level(dbuf.get_voxel(lx + 1, ly, lz, VoxelBuffer.CHANNEL_DATA5)))
					if lz > 0 and WaterMaterial.is_water_type(tbuf.get_voxel(lx, ly, lz - 1, VoxelBuffer.CHANNEL_TYPE)):
						_mlat = max(_mlat, _eff_level(dbuf.get_voxel(lx, ly, lz - 1, VoxelBuffer.CHANNEL_DATA5)))
					if lz < n - 1 and WaterMaterial.is_water_type(tbuf.get_voxel(lx, ly, lz + 1, VoxelBuffer.CHANNEL_TYPE)):
						_mlat = max(_mlat, _eff_level(dbuf.get_voxel(lx, ly, lz + 1, VoxelBuffer.CHANNEL_DATA5)))
					var _flvl: int = WaterByteCodec.MAX_LEVEL if _full_feed else clampi(_mlat - 1, WaterByteCodec.MIN_LEVEL, WaterByteCodec.MAX_LEVEL)
					VoxelEditManager.queue_set_water_voxel(wpos, WaterByteCodec.pack(_flvl, false, WaterByteCodec.DIR_STILL))
					_pending_water[wpos] = PENDING_WATER_TTL
					_dirty_chunks[_voxel_to_chunk(wpos)] = true
					changed += 1
					_diag_flow_flood += 1
					_diag_level_hist[_flvl] += 1
					_diag_flow_last = wpos
					_diag_register_write(wpos, sea_y)
					# Carry carve-permission to sub-sea air neighbours so
					# the flood front keeps advancing through the dug-out
					# volume on later ticks (self-limited: re-checked
					# against sea_y + edit gate every cell).
					#
					# #5 flood-coverage fix (2026-05-17): ALSO dirty the
					# chunk each propagation target sits in. Previously
					# only _voxel_to_chunk(wpos) was dirtied, so when the
					# front reached a chunk boundary the next cell's chunk
					# was never in _dirty_chunks → _run_flow_tick_v2 never
					# processed it → the front stalled at the boundary and
					# the carried TTL expired before that chunk was ever
					# re-dirtied (hard waterline, dirty_chunks=1, large
					# multi-chunk dug-out volumes only partly filled). A
					# whole dug-out region now fills across chunk seams;
					# still self-terminating (no air cells left to flood →
					# no propagation → _dirty_chunks drains → idle) and
					# still bounded by _chunk_in_active_radius + budget.
					for d in _LATERAL_DIRS:
						var npos: Vector3i = wpos + d
						if npos.y <= sea_y:
							_edit_cell_ttl[npos] = EDIT_CELL_TTL
							_dirty_chunks[_voxel_to_chunk(npos)] = true
					var down_np: Vector3i = wpos - Vector3i(0, 1, 0)
					_edit_cell_ttl[down_np] = EDIT_CELL_TTL
					_dirty_chunks[_voxel_to_chunk(down_np)] = true
					# Hydrostatic rise: also carry permission UP, capped at
					# sea_y by the very rule the flood obeys, so the body
					# can climb to the source level and the front never
					# dies just because the only remaining direction is up.
					var up_np: Vector3i = wpos + Vector3i(0, 1, 0)
					if up_np.y <= sea_y:
						_edit_cell_ttl[up_np] = EDIT_CELL_TTL
						_dirty_chunks[_voxel_to_chunk(up_np)] = true
	return changed


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
	# Now: copy the chunk's CHANNEL_DATA5 + CHANNEL_TYPE into local
	# 16³ buffers ONCE per call, plus the chunk-above's CHANNEL_DATA5
	# for cross-chunk "above" reads at the y=15 boundary. Then walk the
	# buffers with cheap byte reads. Cross-chunk lateral neighbours fall
	# back to _is_water_at_voxel (rare — only voxels at chunk edges).
	#
	# Returns the number of cells modified (caller subtracts from budget).

	var voxel_min: Vector3i = chunk * CHUNK_SIZE_VOXELS
	var voxel_max: Vector3i = voxel_min + Vector3i(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)

	# Default the shared tool to CHANNEL_TYPE so any slow-path
	# _is_solid_at fallback reads the right channel for terrain
	# solidity (post-VoxelMesherBlocky migration: material_id lives
	# directly in CHANNEL_TYPE, 0 = air, anything else = solid).
	# tool.copy() takes an explicit channel_mask so the buffer copies
	# below are unaffected by this setting.
	tool.channel = VoxelBuffer.CHANNEL_TYPE

	# ---- Pre-copy chunk buffers ----
	var data_buf := VoxelBuffer.new()
	data_buf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(voxel_min, data_buf, 1 << VoxelBuffer.CHANNEL_DATA5)

	var type_buf := VoxelBuffer.new()
	type_buf.create(CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS, CHUNK_SIZE_VOXELS)
	tool.copy(voxel_min, type_buf, 1 << VoxelBuffer.CHANNEL_TYPE)

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

	# ---- 1. Decay pass ----
	# Note: the previous "gravity-feed → refresh tick" rule was REVERTED
	# (commit 0c6934b). It kept flow cells alive forever whenever water
	# sat above them, causing _cells to grow unbounded as the simulator
	# spread further each tick (70k+ cells after coastal mining, 2-7 fps).
	# Source-ness is now propagated downward in the gravity-drop pass
	# below (see "SOURCE CASCADE" comment) — gravity drops from a source
	# write a SOURCE byte, not a transient flow cell, so the cavity-fill
	# case doesn't create _cells entries at all.
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
				var here_type: int = type_buf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_TYPE)
				if here_type != 0:
					continue  # solid terrain (CHANNEL_TYPE: 0 = air, anything else = solid)

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
				# EDIT-CELL GATE: gravity drop only fills cells the
				# player recently carved. Without this, gen-side gaps
				# (sub-sea air cells the generator missed) get
				# auto-backfilled in cascading ticks — produces the
				# same modified=694 storm even when no climbing
				# happens. Carved cells are still filled correctly
				# because _on_edit_applied marks the edit aabb voxels.
				if not _edit_cell_ttl.has(pos):
					continue
				# Permanent SOURCE byte; never a transient flow cell.
				#
				# History: the previous "above-sea flow cell" path
				# generated thousands of cells per mining strike at the
				# coastline. Each new flow cell got added to _cells; the
				# lateral-spread pass below then mutually refreshed
				# adjacent flow cells' fed_ticks every tick (line ~847),
				# so the decay rule never fired. _cells grew unbounded
				# (1846 → 10205 → 11077 in three strikes at the beach),
				# pushing WFM to 500+ µs/frame.
				#
				# All-source: carved cavities fill permanently with sea
				# water. Lateral spread can't change Y so water still
				# cannot climb above sea level visually. Minecraft-style
				# finite-bucket puddles are not currently a feature; if
				# they're added later, route them through add_source()
				# with explicit source_bit cells (already protected from
				# decay) rather than the gravity/spread path.
				if _cells.has(pos):
					_cells.erase(pos)
				data5_writes.append({
					"pos": pos, "byte": WaterByteCodec.SOURCE_BYTE
				})
				modified += 1
				dirty_neighbors[_voxel_to_chunk(pos)] = true
				dirty_neighbors[_voxel_to_chunk(pos + Vector3i(0, -1, 0))] = true
			if modified >= budget:
				break
		if modified >= budget:
			break

	# ---- 3. Lateral spread pass ----
	# Per design rule (2026-05-13): lateral spread is allowed at the
	# SAME Y or BELOW the source (lateral never moves water up), but
	# the spread can only WRITE to cells that the player recently
	# carved (tracked via _edit_cell_ttl). Natural air-above-beach
	# cells outside any edit aabb stay dry no matter how many adjacent
	# sea sources they have.
	#
	# This combination satisfies the constraints:
	#  - Mining sub-sea: carved cells are edit-flagged, adjacent
	#    sources fill them, sub-sea cavity fills correctly.
	#  - Mining AT water level: same — carved Y=72 void fills from
	#    adjacent sea source, but the new source can't spread into
	#    neighboring natural beach cells (not edit-flagged).
	#  - Mining above water level: no flooding — no source is adjacent
	#    to spread from, and even if one were, the target isn't
	#    edit-flagged unless the player carved it.
	#  - Beach climb bug: eliminated because climb required cascading
	#    through non-edited cells.
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
		# RULE: lateral spread target must be at neighbor.y <= src.y.
		# _LATERAL_DIRS are all horizontal so neighbor.y == src.y by
		# construction — this preserves the "no upward movement" rule.
		# The y-condition is restated here as documentation so future
		# refactors that add diagonal-downward spread vectors stay
		# consistent.
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
			# EDIT-CELL GATE: only allow source writes into cells the
			# player recently carved. Without this, lateral spread
			# cascades across natural air-above-beach cells.
			if not _edit_cell_ttl.has(neighbor):
				continue

			# Neighbour already in _cells. If it's a permanent
			# source-marker (add_source API), leave it alone. If it's a
			# transient flow cell (legacy cache, or already-decaying),
			# promote it to a permanent SOURCE byte by erasing the _cells
			# entry and queueing a SOURCE write.
			if _cells.has(neighbor):
				var n_packed: int = _cells[neighbor]
				if _is_source_packed(n_packed):
					continue
				_cells.erase(neighbor)
				data5_writes.append({
					"pos": neighbor, "byte": WaterByteCodec.SOURCE_BYTE
				})
				modified += 1
				dirty_neighbors[_voxel_to_chunk(neighbor)] = true
				continue
			# Already water in CHANNEL_DATA5? Skip.
			var n_water_byte: int
			var n_type: int
			if n_in_chunk:
				var nlx: int = neighbor.x - voxel_min.x
				var nly: int = neighbor.y - voxel_min.y
				var nlz: int = neighbor.z - voxel_min.z
				n_water_byte = data_buf.get_voxel(nlx, nly, nlz, VoxelBuffer.CHANNEL_DATA5)
				n_type = type_buf.get_voxel(nlx, nly, nlz, VoxelBuffer.CHANNEL_TYPE)
			else:
				# Cross-chunk fallback (rare — only at chunk edges).
				if _is_water_at_voxel(neighbor):
					continue
				if _is_solid_at(tool, neighbor):
					continue
				n_water_byte = 0
				n_type = 0
			if WaterByteCodec.is_water(n_water_byte):
				continue
			if n_type != 0:
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
				below_solid = type_buf.get_voxel(blx, bly, blz, VoxelBuffer.CHANNEL_TYPE) != 0
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
			# ALL-SOURCE: every lateral spread writes a SOURCE byte. No
			# transient flow cells anywhere in the sim. Lateral spread
			# cannot change Y, so this can never climb above whatever
			# Y the source is already at — water still cannot rise above
			# sea level by simulator action.
			data5_writes.append({
				"pos": neighbor, "byte": WaterByteCodec.SOURCE_BYTE
			})
			modified += 1
			dirty_neighbors[_voxel_to_chunk(neighbor)] = true

	# ---- Apply CHANNEL_DATA5 writes in one batched pass ----
	if not data5_writes.is_empty():
		tool.channel = VoxelBuffer.CHANNEL_DATA5
		for w in data5_writes:
			var wp: Vector3i = w["pos"]
			tool.value = w["byte"]
			tool.do_box(Vector3(wp), Vector3(wp) + Vector3.ONE)
		# Restore tool to CHANNEL_TYPE — the caller may reuse the same
		# tool for the next chunk's solidity reads, and the remaining
		# decay / gravity reads we just did all assumed TYPE was the
		# active channel. Defensive: future code reusing this tool
		# won't silently read the wrong channel.
		tool.channel = VoxelBuffer.CHANNEL_TYPE

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

	# ---- O(1) fast path: uniform-water or uniform-dry chunks ----
	# When the whole chunk's CHANNEL_DATA5 is one value, every interior
	# voxel has the same lateral neighbours. There can be no in-chunk
	# "water adjacent to dry" pattern, so no sources to enumerate.
	#
	# This is the common case after mining near the ocean: _on_edit_applied
	# dirties a 3×3×3 neighborhood, including chunks that are entirely
	# water (ocean interior) or entirely dry (above sea level). Without
	# this short-circuit, the inner triple loop runs 4096 reads on each
	# of those chunks, then auto-classifies every chunk-boundary water
	# voxel as a source (out-of-chunk lateral lookups fall through to the
	# `is_edge = true` branch below), spawning ~1000 spurious sources per
	# ocean chunk. Each spurious source then issues 4 slow per-voxel
	# cross-chunk tool.get_voxel calls in _simulate_chunk_gravity's
	# spread loop — the dominant cost in the WaterFlowManager runaway
	# observed 2026-05-13 (peak ~1000 µs/frame after mining at the coast).
	#
	# Cross-chunk spread isn't lost because the *boundary* chunks that
	# mix water and dry (coastline, mined cavities) still go through the
	# Pass 1 + Pass 2 path below and find their own sources. Uniform-water
	# chunks have nothing useful to contribute to that anyway.
	if data_buf.has_method("is_uniform") and data_buf.call("is_uniform", VoxelBuffer.CHANNEL_DATA5):
		# Pass 2 still runs for transient _cells inside this chunk.
		return _gather_lateral_sources_buffered_cells_only(voxel_min, voxel_max, data_buf)

	# Pass 1: water voxels in the chunk's data buffer.
	#
	# A water voxel is "edge" — and therefore a candidate lateral source —
	# if at least one IN-CHUNK horizontal neighbour is dry. Cross-chunk
	# neighbours are conservatively treated as WATER and skipped, NOT
	# as dry.
	#
	# Why this asymmetry: the previous "treat cross-chunk as dry" rule
	# auto-classified every chunk-boundary water voxel as a source. For
	# the sea-level row chunks (Y=4 in Mira, water in lower half + air
	# in upper half), that meant ~576 spurious sources per chunk × 4
	# cross-chunk tool.get_voxel calls each in the spread loop → the
	# 800-1000 µs/frame WaterFlowManager runaway observed 2026-05-13
	# while mining at the coast. The uniform-water short-circuit above
	# catches the fully-water chunks (Y=3 deep ocean), but the mixed
	# sea-level chunks still fell through to this loop.
	#
	# Trade-off: a carved cavity that sits ENTIRELY past a chunk
	# boundary (no carving in the boundary chunk, only on the other
	# side) won't be filled on the first tick — the boundary chunk's
	# source water won't classify against the cross-chunk-only dry
	# voxels. In practice the 3×3×3 dirty propagation around any edit
	# marks both chunks anyway, and once water enters the carved chunk
	# via spread from in-chunk-classified sources nearby, the cavity
	# fills normally over subsequent ticks. Acceptable for water sim.
	for lx in range(CHUNK_SIZE_VOXELS):
		for ly in range(CHUNK_SIZE_VOXELS):
			for lz in range(CHUNK_SIZE_VOXELS):
				var byte: int = data_buf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_DATA5)
				var lvl: int = WaterByteCodec.level_of(byte)
				if lvl <= MIN_LEVEL:
					continue
				var pos := Vector3i(voxel_min.x + lx, voxel_min.y + ly, voxel_min.z + lz)
				var is_edge: bool = false
				for dir in _LATERAL_DIRS:
					var nlx: int = lx + dir.x
					var nly: int = ly + dir.y
					var nlz: int = lz + dir.z
					if nlx < 0 or nlx >= CHUNK_SIZE_VOXELS \
							or nly < 0 or nly >= CHUNK_SIZE_VOXELS \
							or nlz < 0 or nlz >= CHUNK_SIZE_VOXELS:
						# Cross-chunk: assume the adjacent chunk has the
						# same content as this one (water). Don't classify
						# as edge solely because the neighbour is in
						# another chunk — that's the spurious-source bug.
						continue
					var n_byte: int = data_buf.get_voxel(nlx, nly, nlz, VoxelBuffer.CHANNEL_DATA5)
					if not WaterByteCodec.is_water(n_byte):
						is_edge = true
						break
				if is_edge:
					sources.append({"pos": pos, "level": lvl})
	# Pass 2: _cells flow entries inside the chunk that aren't already
	# covered by the buffer scan above (some flow cells may not have
	# been written back to CHANNEL_DATA5 yet on the current tick).
	_append_transient_cells_in_chunk(sources, voxel_min, voxel_max, data_buf)
	return sources


func _gather_lateral_sources_buffered_cells_only(
	voxel_min: Vector3i, voxel_max: Vector3i, data_buf: VoxelBuffer,
) -> Array:
	# Fast-path variant used when the chunk's CHANNEL_DATA5 is uniform
	# (see the short-circuit at the top of _gather_lateral_sources_buffered).
	# Skips the 4096-voxel buffer walk entirely; only collects transient
	# in-memory _cells entries that fall inside the chunk's bounds.
	var sources: Array = []
	_append_transient_cells_in_chunk(sources, voxel_min, voxel_max, data_buf)
	return sources


func _append_transient_cells_in_chunk(
	sources: Array, voxel_min: Vector3i, voxel_max: Vector3i, data_buf: VoxelBuffer,
) -> void:
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
		# Already covered by the buffer scan? If the buffer says this cell
		# is water, Pass 1 above (in the full path) already added it.
		var lx: int = cell_pos.x - voxel_min.x
		var ly: int = cell_pos.y - voxel_min.y
		var lz: int = cell_pos.z - voxel_min.z
		if WaterByteCodec.is_water(data_buf.get_voxel(lx, ly, lz, VoxelBuffer.CHANNEL_DATA5)):
			continue
		sources.append({"pos": cell_pos, "level": lvl_cell})


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

func _on_edit_applied(_world_pos: Vector3, chunk_coord: Vector3i, edit_aabb: AABB) -> void:
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

	# Mark every voxel inside the edit aabb as "recently edited" so the
	# lateral spread pass can write source bytes there. This is the
	# only path by which a new water source byte can appear at or above
	# sea level — natural air-above-beach cells outside any edit aabb
	# stay dry no matter how many sea-source neighbors they have. TTL
	# decrements once per flow tick, so the flag clears after ~1 sec.
	#
	# The aabb arrives in world-space metres; convert to voxel coords
	# via the local helper (matches VoxelEditManager.world_to_voxel).
	var vmin: Vector3i = _world_to_voxel(edit_aabb.position)
	var vmax: Vector3i = _world_to_voxel(edit_aabb.position + edit_aabb.size)
	# Cap aabb cell-marking to keep huge edits (eventual nuke/explosion
	# verbs) from blowing the dictionary. 343 voxels = 7^3 ≈ a typical
	# pickaxe/shovel sphere radius.
	var dx_n: int = vmax.x - vmin.x + 1
	var dy_n: int = vmax.y - vmin.y + 1
	var dz_n: int = vmax.z - vmin.z + 1
	if dx_n * dy_n * dz_n > 4096:
		return
	# Stage 6 connectivity fill: seed the BFS at the air this carve put
	# next to water. Replaces the old per-cell _edit_cell_ttl stamping
	# (that whole TTL/fed front was the source of the stall + re-mine
	# bugs and is gone).
	_seed_fill_from_aabb(vmin, vmax)


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
