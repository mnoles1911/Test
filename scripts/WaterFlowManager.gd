extends Node

# Single-authority water-identity (path preload — headless-safe; see
# WaterMaterial.gd for why it has no class_name).
const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

# The finite, volume-conserving water sim (W4 — the ledger-authority
# core; design/WATER_FINITE_SIM_PLAN.md). Path preload, no class_name.
const FiniteWaterCore := preload("res://scripts/FiniteWaterCore.gd")

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
# v2 sim (_run_flow_tick_v2 — connectivity fill + settle), writes via
# VoxelEditManager.queue_set_water_voxel.
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


const FINITE_CELL_UPDATES_PER_TICK: int = 256
# THE FINITE-SIM DIAL — max ledger cells stepped per 4 Hz tick. Same
# philosophy as WATER_FILL_CELLS_PER_TICK: spilled cells stay active
# and are processed next tick (lowest first), so a low value just slows
# the collapse, it can never lose water. Clamped under the
# _MAX_FLOW_BUDGET_PER_TICK write ceiling by construction (each stepped
# cell queues at most a handful of writes).

var _finite: RefCounted = FiniteWaterCore.new()
# The finite-water ledger sim. ITS DICTIONARY IS THE AUTHORITY for all
# player-placed / inland water; DATA5+TYPE in the voxel world are a
# write-only projection of it (the post-mortem lesson — see
# design/WATER_FINITE_SIM_PLAN.md).

var _unprojected: Dictionary = {}
# Vector3i -> Vector2i(passes_left, next_check_tick). Finite cells
# whose WORLD byte is not yet TRUSTED to match the ledger. Every
# changed cell enters this set; it leaves only after the read-back
# matched the ledger on RECONCILE_PASSES separate checks spaced
# RECONCILE_SPACING_TICKS apart.
#
# Why not fire-and-forget, and why multiple passes: writes can land
# LATE and OUT OF ORDER — VoxelEditManager's water_set drain requeues
# commands whose chunk isn't editable yet, and the finite_world
# headless gate caught world bytes REVERTING to an older write's value
# seconds after a single verification had passed. The ledger is the
# authority, so the cure is patience, not plumbing: keep re-checking,
# and re-issue the ledger's CURRENT truth whenever the world disagrees.
# A mismatch resets the pass count. This read-back is projection
# reconciliation ONLY — the SIM never reads the world to make flow
# decisions (the post-mortem rule).
# No TTL, no retry cap: a dropped write can never become a hole, it
# just lands late. Cells outside the active radius stay in the set,
# frozen, until the player returns.

const RECONCILE_PASSES: int = 3
const RECONCILE_SPACING_TICKS: int = 8   # ~2 s at 4 Hz between passes

var _finite_tick_no: int = 0
# Non-wrapping finite-sim tick counter (drives reconcile scheduling).

var _finite_tool: VoxelTool = null
# Borrowed per-tick terrain tool for the finite sim's solid/source
# callbacks. Refreshed at every entry point; never cached across frames.

var _finite_conserve_warned: bool = false
# One-shot guard so a (should-be-impossible) conservation break warns
# loudly once per session instead of spamming every diag window.

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
	if not _dirty_chunks.is_empty() or _frontier_count() > 0 or not _pending_water.is_empty() or _settle_dirty or _finite_busy():
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

# The 4 horizontal neighbour offsets (current/gradient computations).
const _LATERAL_DIRS: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


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
	# W4: a fresh save must not inherit the previous session's finite
	# ledger. Saved finite water persists as DATA5 chunk deltas and is
	# re-adopted lazily when something disturbs it (_finite_wake_from_aabb).
	_finite = FiniteWaterCore.new()
	_unprojected.clear()
	_finite_conserve_warned = false


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
	# Diagnostic kill-switch: with the sim disabled, just drain the dirty
	# set (so it can't accumulate) and do nothing else.
	if not _FLOW_SIM_ENABLED:
		_dirty_chunks.clear()
		return
	# The legacy DATA5 cellular automaton that used to live here
	# (_flow_chunk / _simulate_chunk_gravity gradient flow) was DELETED
	# 2026-06-10 — it had zero callers since the 2026-05-18 connectivity-
	# fill pivot. Post-mortem + the finite-water replacement design:
	# design/WATER_FINITE_SIM_PLAN.md.
	_run_flow_tick_v2()


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
	_step_finite(tool)            # finite (player-placed) water — W4

	# Throttled diagnostic (~every 8 ticks ≈ 2 s) — only when the sim
	# actually did something, so the Output panel isn't flooded.
	_diag_flow_ticks += 1
	if _diag_flow_ticks >= 8:
		_diag_flow_ticks = 0
		if _diag_flow_flood > 0 or _frontier_count() > 0 or not snapshot.is_empty() or _settle_dirty or _finite_busy():
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
			# Finite-water ledger line — the live conservation audit. The
			# books MUST balance: units == placed - evap - absorbed -
			# merged - removed. If they ever don't, that is a real bug in
			# FiniteWaterCore (the headless `finite` gate should have
			# caught it) — warn loudly, once.
			if _finite_busy() or _finite.placed > 0:
				var fstats: Dictionary = _finite.stats()
				var conserve_s: String = "OK"
				if _finite.conservation_delta() != 0:
					conserve_s = "BROKEN(%+d)" % _finite.conservation_delta()
					if not _finite_conserve_warned:
						_finite_conserve_warned = true
						push_warning("[WaterFlowManager] FINITE WATER CONSERVATION BROKEN: delta=%d stats=%s" % [
							_finite.conservation_delta(), str(fstats)])
				print("[FlowDiag-finite] active=%d units=%d placed=%d evap=%d absorbed=%d merged=%d removed=%d unprojected=%d conserve=%s" % [
					int(fstats["active"]), int(fstats["units"]), int(fstats["placed"]),
					int(fstats["evaporated"]), int(fstats["absorbed"]), int(fstats["merged"]),
					int(fstats["removed"]), _unprojected.size(), conserve_s,
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
		# W2 (design/WATER_FINITE_SIM_PLAN.md): the connectivity fill is
		# the OCEAN subsystem — it writes SOURCE_BYTE (infinite water),
		# never finite water. The ocean refilling a blast crater stays
		# infinite by construction; finite (player-placed) water is a
		# separate subsystem that never routes through this fill.
		var ok: bool = VoxelEditManager.queue_set_water_voxel(c, WaterByteCodec.SOURCE_BYTE)
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
		# W2: DATA5 rides along so the native scan can tell INFINITE
		# (source-bit) water from finite water — only source water may
		# feed the ocean re-fill. See design/WATER_FINITE_SIM_PLAN.md.
		var type_mask: int = (1 << VoxelBuffer.CHANNEL_TYPE) | (1 << VoxelBuffer.CHANNEL_DATA5)
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
					# touches INFINITE (source) water it is a hole / not yet
					# level → re-fill it. Finite water never feeds the ocean
					# re-fill (W2, design/WATER_FINITE_SIM_PLAN.md).
					for d in [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
						if _is_source_water_at(tool, p + d):
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
					# W2: only INFINITE (source) water seeds the ocean fill.
					# A finite pond next to the carve must NOT trigger an
					# infinite refill out of itself — the finite sim handles
					# that water (design/WATER_FINITE_SIM_PLAN.md).
					if _is_source_water_at(tool, p + d):
						_bucket_push(p, true)   # force: a fresh carve must (re)seed even if visited
						break


# ============================================================
# Finite water (W4) — engine glue around FiniteWaterCore.
# The core is pure; everything terrain-shaped lives in this section.
# Design: design/WATER_FINITE_SIM_PLAN.md.
# ============================================================

func place_finite_water(voxel_pos: Vector3i, units: int = 8) -> int:
	# Pour player water into the world (bucket verb). Units land in the
	# ledger immediately; the world write rides the next tick\'s change
	# stream (<= 250 ms later). Returns units actually placed.
	if not _finite_bind_world():
		return 0
	var got: int = _finite.place(voxel_pos, units)
	_finite_tool = null
	return got


func scoop_water(world_pos: Vector3) -> bool:
	# Bucket fill. Finite water is CONSERVED: scooping a player pool
	# removes up to 8 units from the ledger (the pool visibly shrinks).
	# Ocean / legacy / source water stays infinite — scooping it changes
	# nothing. Returns true if the bucket may fill from this position.
	var voxel_pos: Vector3i = _world_to_voxel(world_pos)
	if _finite_bind_world():
		var got: int = _finite.remove(voxel_pos, WaterByteCodec.MAX_LEVEL)
		_finite_tool = null
		if got > 0:
			return true
	# Not finite water here — fall back to "is there any water at all"
	# (infinite sources fill the bucket for free, exactly as before).
	return is_position_in_water(world_pos)


func _finite_busy() -> bool:
	# True while the finite sim still owes the world anything: cells to
	# simulate, fresh placements to project, or rejected writes to retry.
	return _finite.has_pending_changes() or not _unprojected.is_empty()


func _finite_bind_world() -> bool:
	# Point the core\'s world callbacks at the live terrain for the
	# duration of one call/tick. Returns false (and leaves the sim
	# untouched) when terrain isn\'t ready — water just waits.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return false
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return false
	_finite_tool = terrain.get_voxel_tool()
	if _finite_tool == null:
		return false
	_finite.sea_y = get_sea_level_voxel_y()
	if not _finite.solid_cb.is_valid():
		_finite.solid_cb = Callable(self, "_finite_is_solid")
		_finite.source_cb = Callable(self, "_finite_is_source")
	return true


func _finite_is_solid(p: Vector3i) -> bool:
	# World callback for the core: does terrain block water here?
	# NoEditZones that block water flow count as walls so designer-
	# protected areas can\'t flood. Water TYPE blocks are NOT solid
	# (they\'re either our own projection or source water — the source
	# callback handles those).
	if _finite_tool == null:
		return true   # terrain gone mid-tick: freeze rather than leak
	if _is_water_blocked_at_voxel(p):
		return true
	_finite_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var t: int = _finite_tool.get_voxel(p)
	if t == 0:
		return false
	return not WaterMaterial.is_water_type(t)


func _finite_is_source(p: Vector3i) -> bool:
	# World callback for the core: is there INFINITE water here? Mirrors
	# _is_source_water_at but on the borrowed per-tick tool. Our own
	# finite cells read as water TYPE with a non-source DATA5 byte and
	# correctly return false.
	if _finite_tool == null:
		return false
	_finite_tool.channel = VoxelBuffer.CHANNEL_TYPE
	if not WaterMaterial.is_water_type(_finite_tool.get_voxel(p)):
		return false
	_finite_tool.channel = VoxelBuffer.CHANNEL_DATA5
	var d5: int = _finite_tool.get_voxel(p)
	_finite_tool.channel = VoxelBuffer.CHANNEL_TYPE
	return d5 == 0 or WaterByteCodec.is_source(d5)


func _step_finite(tool: VoxelTool) -> void:
	# One finite-sim tick: step the core, project its change stream into
	# the world through the normal edit queue (re-mesh + DATA5 persist +
	# save-marking + MP replication all happen in VoxelEditManager\'s
	# water_set drain), and retry anything the queue rejected earlier.
	if not _finite_busy():
		return
	_finite_tool = tool
	_finite.sea_y = get_sea_level_voxel_y()
	if not _finite.solid_cb.is_valid():
		_finite.solid_cb = Callable(self, "_finite_is_solid")
		_finite.source_cb = Callable(self, "_finite_is_source")

	_finite_tick_no += 1
	var res: Dictionary = _finite.step(FINITE_CELL_UPDATES_PER_TICK)
	var ch: PackedInt32Array = res["changes"]
	@warning_ignore("integer_division")
	var n: int = ch.size() / 4
	for i in range(n):
		var pos: Vector3i = Vector3i(ch[i * 4], ch[i * 4 + 1], ch[i * 4 + 2])
		var byte: int = ch[i * 4 + 3]
		VoxelEditManager.queue_set_water_voxel(pos, byte)
		# Fresh change: needs the full reconcile schedule from scratch.
		_unprojected[pos] = Vector2i(RECONCILE_PASSES, _finite_tick_no + 1)

	# Verified projection (see _unprojected docs above): read each due
	# cell's WORLD byte; match -> one pass done, re-check later;
	# mismatch -> re-issue the ledger's CURRENT byte and start over.
	# WRITE BARRIER: read-backs are only meaningful when no writes are
	# in flight — skip the pass until the edit queue has drained (it
	# drains every frame; this just delays a check a tick or two).
	if not _unprojected.is_empty() and VoxelEditManager.is_edit_queue_empty():
		var done: Array = []
		for pos in _unprojected.keys():
			var sched: Vector2i = _unprojected[pos]
			if _finite_tick_no < sched.y:
				continue   # not due yet
			if _voxel_center_world(pos).distance_to(_player_pos) > ACTIVE_RADIUS_M + CHUNK_SIZE_M:
				continue   # frozen until the player comes back
			var want: int = _finite.projected_byte(pos)
			_finite_tool.channel = VoxelBuffer.CHANNEL_DATA5
			var have: int = _finite_tool.get_voxel(pos)
			_finite_tool.channel = VoxelBuffer.CHANNEL_TYPE
			if have == want:
				if sched.x <= 1:
					done.append(pos)   # trusted: matched on every pass
				else:
					_unprojected[pos] = Vector2i(sched.x - 1, _finite_tick_no + RECONCILE_SPACING_TICKS)
			else:
				VoxelEditManager.queue_set_water_voxel(pos, want)
				_unprojected[pos] = Vector2i(RECONCILE_PASSES, _finite_tick_no + 1)
		for pos in done:
			_unprojected.erase(pos)
	_finite_tool = null


func _finite_wake_from_aabb(vmin: Vector3i, vmax: Vector3i) -> void:
	# Terrain changed inside this box. Two duties (W4 activation path):
	#   1. wake any ledger cells in/next to the box (their support may
	#      just have been carved away),
	#   2. ADOPT dormant finite water from a previous session: DATA5
	#      bytes with a level but no source bit that we aren\'t tracking
	#      (the ledger isn\'t saved — see the design doc; saved finite
	#      water sleeps in DATA5 until an edit pokes it).
	if not _finite_bind_world():
		return
	for x in range(vmin.x - 1, vmax.x + 2):
		for y in range(vmin.y - 1, vmax.y + 2):
			for z in range(vmin.z - 1, vmax.z + 2):
				var pp: Vector3i = Vector3i(x, y, z)
				if _finite.has_cell(pp):
					_finite.activate(pp)
					continue
				_finite_tool.channel = VoxelBuffer.CHANNEL_DATA5
				var d5: int = _finite_tool.get_voxel(pp)
				if WaterByteCodec.is_water(d5) and not WaterByteCodec.is_source(d5):
					_finite.ingest(pp, WaterByteCodec.level_of(d5))
	_finite_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_finite_tool = null


func _is_source_water_at(tool: VoxelTool, voxel_pos: Vector3i) -> bool:
	# OCEAN-subsystem feed test (W2, design/WATER_FINITE_SIM_PLAN.md).
	# True iff the voxel holds water AND that water is INFINITE:
	#   - DATA5 source bit set (generator ocean, designer headwaters), or
	#   - DATA5 == 0 on a water TYPE (legacy water from before DATA5
	#     backfill / old saves) — conservatively counts as source.
	# Finite water (level set, source bit clear) returns false: it must
	# never feed the infinite connectivity fill or the settle re-fill.
	# Leaves tool.channel on CHANNEL_TYPE (the callers' loop channel).
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	if not WaterMaterial.is_water_type(tool.get_voxel(voxel_pos)):
		return false
	tool.channel = VoxelBuffer.CHANNEL_DATA5
	var d5: int = tool.get_voxel(voxel_pos)
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	return d5 == 0 or WaterByteCodec.is_source(d5)


func _is_water_blocked_at_voxel(voxel_pos: Vector3i) -> bool:
	# Wraps NoEditZoneRegistry.is_water_flow_blocked_at with the world-
	# space conversion. Returns false if NoEditZoneRegistry isn't
	# loaded (fail-open: water flows freely if the registry is gone).
	if get_node_or_null("/root/NoEditZoneRegistry") == null:
		return false
	return NoEditZoneRegistry.is_water_flow_blocked_at(_voxel_center_world(voxel_pos))


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
	# W4: wake ledger cells whose support may have been carved away and
	# adopt dormant finite DATA5 water from older sessions.
	_finite_wake_from_aabb(vmin, vmax)


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

static func _is_source_packed(packed: int) -> bool:
	return (packed & _SOURCE_BIT) != 0


static func _pack(level: int, is_source: bool, last_fed_tick: int) -> int:
	var lvl: int = clampi(level, 0, MAX_LEVEL)
	var src: int = _SOURCE_BIT if is_source else 0
	var tick: int = (last_fed_tick & 0xFF) << _TICK_SHIFT
	return lvl | src | tick
