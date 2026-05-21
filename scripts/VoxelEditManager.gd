extends Node

const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

# VoxelEditManager — central authority for all voxel terrain edits.
#
# How this works in plain English:
#
# Every voxel edit in the game (pickaxe swing, axe felling a tree,
# explosive blast, terrain-affecting spell) routes through this manager.
# It does four jobs:
#
# 1. NoEditZone check — asks NoEditZoneRegistry whether the edit is
#    inside a protected region. If yes, silently rejects. The caller
#    can then play Roland's bark "This place doesn't yield to me."
#
# 2. Async queueing — edits don't fire instantly. They go on a queue,
#    and a fixed number of voxels are processed per frame. This stops
#    a big explosion or spell from stuttering the frame rate.
#
# 3. EditedChunkRegistry tracking — when a chunk gets its first edit,
#    it's marked as "edited" in an in-memory set. This is what
#    distinguishes a chunk we should LOD-bake from one we can render
#    directly from the procedural baseline.
#
# 4. (Future) LOD-bake-on-eviction — when an edited chunk leaves the
#    player's edit-detail radius, generate a one-time LOD1/LOD2 mesh
#    from the edited state and cache it on disk. NOT implemented in
#    this first version. See the TODO block at the bottom of the file.
#
# IMPORTANT: voxel writes must NEVER bypass this manager. Direct
# `VoxelTool.do_*()` calls will desync the EditedChunkRegistry and skip
# the NoEditZone check. See CLAUDE.md → "Critical GDScript patterns"
# for the canonical rule.
#
# Registered as an autoload in Project Settings → Autoload with the
# node name "VoxelEditManager". Requires Zylann's Voxel Tools plugin
# installed and enabled — this script references VoxelLodTerrain,
# VoxelTool, and VoxelBuffer from that plugin and won't parse without
# it.
#
# Reference: design/3D_VOXEL_MIGRATION.md → "Destructible Terrain"


# ============================================================
# Save-format compatibility
# ============================================================

const WORLD_GENERATOR_VERSION: int = 16
# Bump this constant whenever the procedural baseline produced by
# the active generator (currently CubicHeightmapGenerator) changes
# shape OR encoding — e.g. swap to a new heightmap, change cave
# parameters, change biome material indices, or change which voxel
# channel terrain lives in.
#
# Version history:
#   v9  → CubicHeightmapGenerator. Voxels written as packed RGBA;
#         alpha byte was always 255 for solids. No material concept.
#   v10 → CubicHeightmapGenerator with material-band assignment.
#         Alpha byte now encodes the VoxelMaterialRegistry material_id
#         (1=stone, 2=dirt, 3=grass, 4=sand, …). Surface terrain looks
#         visibly different (grass-on-top, dirt layer, stone deep).
#   v12 → World-floor bedrock layer at WORLD_FLOOR_VOXEL_Y (= -50 m).
#         Generator writes mat_id=6 bedrock at that exact Y; voxels
#         below are air (the world has a finite bottom). Edits below
#         the floor are rejected at this manager.
#   v13 → CHANNEL_DATA5 water voxels (Minecraft-style ocean). Generator
#         now writes one byte per voxel into CHANNEL_DATA5 encoding
#         water level/source/tick (see WaterByteCodec). Below-sea-level
#         columns get water bytes at gen time; above-sea-level columns
#         do not. The legacy AABB ocean shortcut goes away. Old saves
#         have no CHANNEL_DATA5 stored, so they read as fully-dry —
#         hard-reject and require a new game.
#   v14 → Sea level raised from voxel Y=60 (world 10 m) to voxel Y=72
#         (world 12 m). Beach band raised from voxel 7 to 74 to match.
#         Shifts the land/water split from 50/50 to ~40/60 so ocean
#         basins are clearly visible between landmasses. Old saves'
#         water columns assume the v13 sea level and would mismatch.
#   v15 → VoxelMesherBlocky migration. Terrain voxels live in
#         CHANNEL_TYPE (8-bit integer = material_id directly), no
#         longer in CHANNEL_COLOR as packed RGBA. Library-driven
#         per-face textures via VoxelBlockyLibrary; water continues
#         to live in CHANNEL_DATA5 (orthogonal). Pre-v15 saves are
#         invalid — no migration path; the terrain channel changed.
#   v16 → Water Voxel V2 (Minecraft model, 2026-05-16). Water is now a
#         normal CHANNEL_TYPE block (id 5, transparent blocky model)
#         emitted by the generator at ALL LODs — NOT a CHANNEL_DATA5
#         side-channel byte. WaterChunkMesher + the horizon plane are
#         deleted; the terrain blocky mesher draws water. Pre-v16 saves
#         have water in DATA5 / no TYPE-5 — they'd render as dry and
#         must be hard-rejected. See design/SWIMMING_AND_WATER.md.


# ============================================================
# World floor (bedrock layer)
# ============================================================

const WORLD_FLOOR_VOXEL_Y: int = -300
# Y coordinate (in voxel units, 6 vox/m) of the bedrock layer. Edits
# whose AABB extends to or below this Y are rejected — bedrock is
# unbreakable. Mirror of the same constant in
# `CubicHeightmapGenerator.WORLD_FLOOR_VOXEL_Y`. Keep them in sync.

const WORLD_FLOOR_WORLD_Y: float = float(WORLD_FLOOR_VOXEL_Y) / 6.0
# Same value in world-space metres (6 vox/m). Used by world-coord
# AABB checks below.
#
# GameState.save_game() stamps this version into every save. On
# load, mismatch is treated as a HARD ERROR — the procedural
# baseline has changed, so player voxel deltas (stored against the
# old baseline) would float in nonsense terrain.
#
# There is no silent migration. If we want to keep old saves loading
# after a generator change, the policy needs an explicit decision per
# change (re-bake the baseline, discard deltas, whatever) — not a
# default behavior.


# ============================================================
# Configuration (tunable in the Inspector once registered)
# ============================================================

@export var voxels_per_frame: int = 200000
# Soft per-frame budget for the voxel edit queue. With one 2m
# explosive sphere at 6 vox/m costing ~7300 voxels, this lets
# ~10 sphere edits drain in a single physics frame, so rapid
# explosive throws don't bottleneck on the queue.
#
# (The earlier 256 was way too low — it forced one sphere per
# frame, which combined with rapid throws and Zylann's mesh
# rebuild timing produced the "spam-thrown explosives don't
# carve" bug. With this much higher budget, queued edits drain
# the same physics frame they're submitted.)
#
# A single command can still exceed the budget in one go — the
# budget gates how many commands we *start* per frame, not how
# big each one is allowed to be.

@export var max_queue_length: int = 2048
# Hard cap on how many edit commands can wait in the queue at once.
# Stops the queue from growing unbounded if something pathological
# happens (e.g. a runaway spell effect). Commands beyond this are
# rejected at queue time with a push_warning.

@export var perf_log_enabled: bool = false
# When true, log microsecond timings around each edit application
# AND every queue-drain / queue-push event. Look for "[PERF VEM]"
# and "[VoxelEditManager]" in the Output panel. OFF by default —
# the unconditional prints on every edit/drain were causing visible
# main-thread hitches during normal play (gravity-induced
# PICKUP_DROP carves alone push 27+ writes per swing). Flip on for
# specific diagnostics, then back off.


# ============================================================
# Internal state
# ============================================================

var _terrain: VoxelLodTerrain = null
# The active VoxelLodTerrain node. Set by the world scene at load time
# via set_terrain(). Until it's set, all edit queue methods silently
# return false — there's nothing to write to yet.

var _edit_queue: Array[Dictionary] = []
# Pending edits, processed FIFO each physics frame. Each entry is a
# small Dictionary describing one command:
#   { "type": "sphere", "pos": Vector3, "radius": float, "value": int }
#   { "type": "box",    "min": Vector3, "max": Vector3, "value": int }
#   { "type": "set",    "pos": Vector3, "value": int }

var _edited_chunks: Dictionary = {}
# In-memory set of chunk coordinates (Vector3i keys, bool values
# always true) that have at least one player edit. Used by the LOD
# render decision: edited chunks render LOD0 in edit-detail radius
# and LOD-baked beyond; un-edited chunks render procedural baseline.
#
# Godot 4 has no built-in typed Set, so we use Dictionary as a Set.
# Only the keys matter — the bool value is always true.


# ============================================================
# Signals
# ============================================================

signal edit_applied(world_pos: Vector3, chunk_coords: Vector3i, edit_aabb: AABB)
# Fired after every successfully applied edit. Caller systems listen to
# this — for example, to award XP to the Mining/Excavation/Felling
# sub-skills (per design/SKILLS_AND_PROGRESSION.md), or to spawn a
# particle effect at the impact site.
#
# `edit_aabb` is the world-space bounding box of the affected voxels.
# Used by VoxelGravityManager to size its analysis bubble — a tiny
# pickaxe carve does NOT need a 4 m flood-fill scan that costs
# ~117k voxel reads. Adaptive padding drops the per-scan cost from
# ~150 ms to a few ms for typical edits.

signal edit_rejected_no_edit_zone(world_pos: Vector3)
# Fired when an edit is rejected because it's inside a NoEditZone.
# The bark system listens and triggers Roland's "This place doesn't
# yield to me." line, throttled to once per session per zone.

signal water_changed_at(world_pos: Vector3, chunk_coords: Vector3i, edit_aabb: AABB)
# Fired after every CHANNEL_DATA water write. Distinct from edit_applied
# (which fires for COLOR/terrain edits) so the WaterChunkMesher
# subscribes ONLY to water changes and doesn't pay the cost of rebuilding
# its mesh on every pickaxe swing.
#
# The reverse is also true: VoxelGravityManager subscribes to
# edit_applied for terrain falling-voxel scans, and is NOT fired for
# water writes — placing a bucket of water doesn't trigger gravity
# analysis on neighbouring solid voxels.


# ============================================================
# Public API — scene wiring
# ============================================================

func set_terrain(terrain: VoxelLodTerrain) -> void:
	# Called by the world scene (typically World3D.tscn) on _ready.
	# Without this, the manager has no terrain to edit and rejects
	# all incoming edits.
	#
	# When the player loads a save, the EditedChunkRegistry should be
	# rehydrated from VoxelStreamSQLite so we know which chunks have
	# deltas. That rehydration is wired in by GameState.load_game()
	# at save-load time, NOT here — this function is just the live
	# wiring of the terrain node.
	_terrain = terrain


func clear_terrain() -> void:
	# Called when the world scene unloads. Drains the queue and
	# resets state so the next world load starts clean.
	_terrain = null
	_edit_queue.clear()
	_edited_chunks.clear()


func flush_pending_edits() -> void:
	# Force Zylann to write any in-memory voxel changes through to
	# VoxelStreamSQLite NOW (rather than waiting for its periodic
	# auto-flush). Called by GameState.save_game() before writing
	# the JSON state, so a save captures the latest voxel edits
	# even if the player saves immediately after digging.
	#
	# save_modified_blocks() returns an Array of pending tasks that
	# complete asynchronously on Zylann's worker thread. We don't
	# explicitly wait — the SQLite writes complete in the background
	# and the game is paused during the save dialog, so the
	# transition out of World3D won't pre-empt them.
	if _terrain == null:
		print("[VoxelEditManager] flush_pending_edits: no terrain bound")
		return
	if _terrain.has_method("save_modified_blocks"):
		_terrain.save_modified_blocks()
		print("[VoxelEditManager] Flushed voxel edits to VoxelStreamSQLite.")
	else:
		push_warning("[VoxelEditManager] terrain.save_modified_blocks() not available; voxel edits may not persist")


# ============================================================
# Public API — edit verbs
# ============================================================

func queue_edit_sphere(world_pos: Vector3, radius: float, voxel_value: int) -> bool:
	# MP-3: clients forward to host and return optimistically. Host
	# validates + broadcasts at the end of this function. See the
	# "MP-3 — multiplayer routing" section at the bottom of the file.
	if _mp_is_client():
		_mp_send_request_to_host({
			"type": "sphere", "pos": world_pos,
			"radius": radius, "value": voxel_value,
		})
		return true

	# Queue a spherical voxel edit centered at world_pos with the given
	# radius (in meters).
	#
	# voxel_value semantics for VoxelMesherBlocky:
	#   0 = AIR — carves out (the pickaxe / axe / shovel / explosive case)
	#   N = material_id — fills with that material from the
	#       VoxelBlockyLibrary (the place-block case). 1-254 only.
	#
	# Returns true if accepted into the queue, false if rejected by
	# NoEditZone or if the queue is full. The caller can use a false
	# return as the trigger to play Roland's "doesn't yield" bark.
	#
	# The actual VoxelTool.do_sphere() call happens later in
	# _physics_process when this command's turn comes up in the queue.

	if not _check_edit_allowed(world_pos):
		if perf_log_enabled:
			print("[VoxelEditManager] sphere edit rejected (NoEditZone): %s" % world_pos)
		return false
	# Bedrock floor: reject if the sphere extends to or below the world
	# floor. The bedrock layer is unbreakable; an explosive thrown at
	# the bedrock just doesn't carve. The voxel layer immediately above
	# the floor is normal stone and IS mineable.
	if (world_pos.y - radius) <= WORLD_FLOOR_WORLD_Y:
		return false
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping sphere edit")
		return false

	_edit_queue.append({
		"type": "sphere",
		"pos": world_pos,
		"radius": radius,
		"value": voxel_value,
	})
	if perf_log_enabled:
		print("[VoxelEditManager] queued sphere r=%.1f at %s; queue=%d" % [
			radius, world_pos, _edit_queue.size()
		])
	if _mp_is_host_with_peers():
		_mp_broadcast_replica({
			"type": "sphere", "pos": world_pos,
			"radius": radius, "value": voxel_value,
		})
	return true


func queue_edit_box(min_pos: Vector3, max_pos: Vector3, voxel_value: int) -> bool:
	# MP-3 routing — see queue_edit_sphere for the pattern.
	if _mp_is_client():
		_mp_send_request_to_host({
			"type": "box", "min": min_pos, "max": max_pos, "value": voxel_value,
		})
		return true

	# Queue a box-shaped voxel edit. min_pos and max_pos are world-space
	# corners (min on each axis < max on each axis).
	#
	# Same return semantics as queue_edit_sphere. The NoEditZone check
	# is performed at the box's center point only — a box that
	# straddles a zone boundary will be rejected if its center is
	# inside the zone, accepted otherwise. This is intentionally
	# coarse; if precision becomes a concern we can sample multiple
	# points later.

	var center: Vector3 = (min_pos + max_pos) * 0.5
	if not _check_edit_allowed(center):
		return false
	if min_pos.y <= WORLD_FLOOR_WORLD_Y:
		return false
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping box edit")
		return false

	_edit_queue.append({
		"type": "box",
		"min": min_pos,
		"max": max_pos,
		"value": voxel_value,
	})
	if _mp_is_host_with_peers():
		_mp_broadcast_replica({
			"type": "box", "min": min_pos, "max": max_pos, "value": voxel_value,
		})
	return true


func queue_edit_box_voxels(voxel_min: Vector3i, voxel_max: Vector3i, voxel_value: int) -> bool:
	# MP-3 routing — see queue_edit_sphere for the pattern.
	if _mp_is_client():
		_mp_send_request_to_host({
			"type": "box_voxels", "min": voxel_min, "max": voxel_max, "value": voxel_value,
		})
		return true

	# Box edit using integer voxel-grid coordinates directly. Avoids the
	# floating-point rounding that collapses 3×3×3 carves to 1×1×1 when
	# queue_edit_box converts via _terrain.to_local() (which can return
	# -0.999... instead of -1.0, causing truncation to lose a voxel on
	# each edge). Use this whenever the caller already has voxel-grid
	# coords (e.g. EditToolHandler._carve).
	#
	# NoEditZone check is performed at the box centre in world space —
	# same coarse-centre policy as queue_edit_box.
	var world_center: Vector3 = (Vector3(voxel_min) + Vector3(voxel_max) + Vector3.ONE) * 0.5 / VOXELS_PER_METER
	if not _check_edit_allowed(world_center):
		return false
	# Bedrock floor: reject if any of the box's voxel-grid Y range is
	# at-or-below the floor row.
	if voxel_min.y <= WORLD_FLOOR_VOXEL_Y:
		return false
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping box_voxels edit")
		return false
	_edit_queue.append({
		"type": "box_voxels",
		"min": voxel_min,
		"max": voxel_max,
		"value": voxel_value,
	})
	if _mp_is_host_with_peers():
		_mp_broadcast_replica({
			"type": "box_voxels", "min": voxel_min, "max": voxel_max, "value": voxel_value,
		})
	return true


func queue_set_voxel(world_pos: Vector3, voxel_value: int) -> bool:
	# MP-3 routing — see queue_edit_sphere for the pattern.
	if _mp_is_client():
		_mp_send_request_to_host({
			"type": "set", "pos": world_pos, "value": voxel_value,
		})
		return true

	# Single-voxel write. Used for per-block placement in Build Mode →
	# Detail submode (design/CRAFTING.md → "Per-Voxel Placement"), and
	# for any fine-grained edit that touches exactly one voxel.

	if not _check_edit_allowed(world_pos):
		return false
	if world_pos.y <= WORLD_FLOOR_WORLD_Y:
		return false
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping set-voxel edit")
		return false

	_edit_queue.append({
		"type": "set",
		"pos": world_pos,
		"value": voxel_value,
	})
	if _mp_is_host_with_peers():
		_mp_broadcast_replica({
			"type": "set", "pos": world_pos, "value": voxel_value,
		})
	return true


func queue_set_water_voxel(voxel_pos: Vector3i, water_byte: int) -> bool:
	# MP-3 routing — see queue_edit_sphere for the pattern.
	if _mp_is_client():
		_mp_send_request_to_host({
			"type": "water_set", "voxel_pos": voxel_pos, "water_byte": water_byte,
		})
		return true

	# Write a single CHANNEL_DATA byte at the given voxel grid position.
	# Used by player buckets, river headwater authoring, and the flow
	# simulator for occasional out-of-band single-cell writes (most flow
	# tick writes go via terrain.paste of a whole region).
	#
	# Routes through the same async queue as terrain edits, so writes
	# don't stutter the frame and respect the same per-frame voxel
	# budget. NoEditZone gating uses blocks_water_flow (not the COLOR-
	# edit gate) — designers can have a zone that allows water flow but
	# rejects terrain edits, or vice versa.
	#
	# Returns true if accepted. Bedrock-floor rejection is intentionally
	# omitted: a flooded mineshaft can extend down to the bedrock floor;
	# the floor itself is solid and water above it is fine.
	var world_pos: Vector3 = (Vector3(voxel_pos) + Vector3(0.5, 0.5, 0.5)) / VOXELS_PER_METER
	if get_node_or_null("/root/NoEditZoneRegistry") != null:
		if NoEditZoneRegistry.is_water_flow_blocked_at(world_pos):
			return false
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping water-set edit")
		return false
	_edit_queue.append({
		"type": "water_set",
		"voxel_pos": voxel_pos,
		"water_byte": water_byte & 0xFF,
	})
	if _mp_is_host_with_peers():
		_mp_broadcast_replica({
			"type": "water_set", "voxel_pos": voxel_pos, "water_byte": water_byte & 0xFF,
		})
	return true


func queue_set_water_box(voxel_min: Vector3i, voxel_max: Vector3i, water_byte: int) -> bool:
	# MP-3 routing — see queue_edit_sphere for the pattern.
	if _mp_is_client():
		_mp_send_request_to_host({
			"type": "water_box", "voxel_min": voxel_min,
			"voxel_max": voxel_max, "water_byte": water_byte,
		})
		return true

	# Bulk water write: fill a voxel-grid box with the same water byte.
	# Used by World3DBootstrap to seed the test pond after Phase 5
	# (replaces the legacy add_source_region path), and by future
	# flood-trigger story events.
	#
	# voxel_min is inclusive, voxel_max is exclusive — matches the
	# semantics of queue_edit_box_voxels.
	#
	# NoEditZone gate applied at the box centre, same coarse policy as
	# queue_edit_box_voxels. A box that straddles a zone boundary is
	# rejected if the centre is inside the zone, accepted otherwise.
	var center_voxel: Vector3 = (Vector3(voxel_min) + Vector3(voxel_max)) * 0.5
	var world_center: Vector3 = center_voxel / VOXELS_PER_METER
	if get_node_or_null("/root/NoEditZoneRegistry") != null:
		if NoEditZoneRegistry.is_water_flow_blocked_at(world_center):
			return false
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping water-box edit")
		return false
	_edit_queue.append({
		"type": "water_box",
		"voxel_min": voxel_min,
		"voxel_max": voxel_max,
		"water_byte": water_byte & 0xFF,
	})
	if _mp_is_host_with_peers():
		_mp_broadcast_replica({
			"type": "water_box", "voxel_min": voxel_min,
			"voxel_max": voxel_max, "water_byte": water_byte & 0xFF,
		})
	return true


func queue_set_voxels_bulk(voxel_writes: Array, label: String = "bulk") -> bool:
	# MP-3 routing — see queue_edit_sphere for the pattern.
	if _mp_is_client():
		_mp_send_request_to_host({
			"type": "bulk", "writes": voxel_writes, "label": label,
		})
		return true

	# Bulk single-voxel writes — used for falling-voxel cluster re-deposits
	# where many voxels need to be written at exact grid positions in a
	# single operation. Each entry in voxel_writes is a Dictionary:
	#   { "pos": Vector3 (world-space), "value": int (packed RGBA32) }
	#
	# All writes are batched into one queue command, processed under one
	# VoxelTool acquisition. NoEditZone is queried per-voxel and any
	# rejected writes are silently dropped — a falling cluster that lands
	# partly inside a settlement will lose the boundary voxels.
	#
	# Returns true if the command was queued, false if the queue is full.
	# An empty voxel_writes array returns true (no-op).
	if voxel_writes.is_empty():
		return true
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping bulk write of %d voxels" % voxel_writes.size())
		return false

	_edit_queue.append({
		"type": "bulk",
		"writes": voxel_writes,
		"label": label,
	})
	if _mp_is_host_with_peers():
		_mp_broadcast_replica({
			"type": "bulk", "writes": voxel_writes, "label": label,
		})
	return true


# ============================================================
# Public API — queries
# ============================================================

func is_chunk_edited(chunk_coords: Vector3i) -> bool:
	# Has this chunk received any player edits? Used by the LOD render
	# decision (edited chunks: LOD0 near, LOD-baked far; un-edited
	# chunks: procedural baseline at appropriate LOD).
	return _edited_chunks.has(chunk_coords)


func get_edited_chunks() -> Array:
	# Returns the full set of edited chunk coordinates as an Array of
	# Vector3i. Used by the save system (to know which chunks to flush
	# to SQLite) and by the future LOD-bake-on-eviction system.
	return _edited_chunks.keys()


func mark_chunk_loaded_with_deltas(chunk_coords: Vector3i) -> void:
	# Called by the save-load path when VoxelStreamSQLite reports that
	# a chunk has stored deltas. Pre-populates the registry on game
	# load so the LOD decision is correct from frame one.
	_edited_chunks[chunk_coords] = true


func get_terrain() -> VoxelLodTerrain:
	# Read access to the active terrain node. Used by VoxelGravityManager
	# to acquire a VoxelTool for reading voxel values during flood-fill
	# connectivity analysis. Returns null if the world scene hasn't called
	# set_terrain yet.
	return _terrain


func world_to_voxel(world_pos: Vector3) -> Vector3i:
	# Public coord conversion — exposes the same math used internally
	# so other systems (gravity manager, build mode) can convert without
	# duplicating the constants.
	return _world_to_voxel(world_pos)


# ============================================================
# Frame tick — drain the queue
# ============================================================

func _physics_process(_delta: float) -> void:
	# Profiling wrapper — see CLAUDE.md "Per-autoload performance
	# attribution" pattern. Inner does the work; wrapper times it so the
	# Profiler overlay shows VoxelEditManager when edit traffic is heavy.
	var _t0_prof := Time.get_ticks_usec()
	_physics_process_inner()
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WORLD", "VoxelEditManager", Time.get_ticks_usec() - _t0_prof)


func _physics_process_inner() -> void:
	# Drain the edit queue, voxel-budget at a time, every physics
	# frame. We use _physics_process (not _process) because edits
	# affect collision/navigation that downstream physics should see
	# in the same frame.
	if _terrain == null:
		return
	if _edit_queue.is_empty():
		return

	var initial_queue: int = _edit_queue.size()
	var voxels_used: int = 0
	var processed: int = 0
	while not _edit_queue.is_empty() and voxels_used < voxels_per_frame:
		var cmd: Dictionary = _edit_queue.pop_front()
		voxels_used += _estimate_voxel_cost(cmd)
		_apply_edit(cmd)
		processed += 1
	if perf_log_enabled and processed > 0:
		print("[VoxelEditManager] frame drain: %d processed, %d remain (started with %d)" % [
			processed, _edit_queue.size(), initial_queue
		])


# ============================================================
# Private — edit application
# ============================================================

func _apply_edit(cmd: Dictionary) -> void:
	# DIAGNOSTIC — auto-print phase breakdown when this single edit
	# takes >30 ms. Lets us see whether the spike comes from the
	# carve (`tool.do_sphere`/etc.), `_mark_chunks_in_aabb`, the
	# emit, or something invisible inside Zylann's post-carve path.
	# Remove once the explosive-throw spike is traced.
	var t_apply_start: int = Time.get_ticks_usec()
	var t_phase_carve: int = 0
	var t_phase_mark: int = 0
	var t_phase_emit: int = 0

	# Pull a fresh VoxelTool from the terrain. We do NOT cache the
	# VoxelTool because it can become stale across frames — grab a
	# new one each time per Zylann's recommended usage.
	var tool: VoxelTool = _terrain.get_voxel_tool()
	if tool == null:
		push_warning("[VoxelEditManager] _apply_edit: terrain.get_voxel_tool() returned null")
		return

	if perf_log_enabled:
		print("[VoxelEditManager] _apply_edit: type=%s pos=%s value=%d" % [
			cmd.get("type", "?"),
			cmd.get("pos", Vector3.ZERO),
			cmd.get("value", 0),
		])

	# Edits target CHANNEL_TYPE because the world uses VoxelMesherBlocky,
	# which reads an integer per voxel and looks up the matching model
	# in the VoxelBlockyLibrary. The integer IS the material_id (0 = air,
	# 1-12 = active materials, see VoxelMaterialRegistry).
	#
	# Pre-v13 (CubicMesher era) this targeted CHANNEL_COLOR with packed
	# RGBA — that channel is now unused for terrain.
	tool.channel = VoxelBuffer.CHANNEL_TYPE

	# Blocky uses MODE_SET: tool.value is the type integer to write.
	# value 0 = air (carved); 1-254 = a material from the registry.
	# MODE_REMOVE / MODE_ADD only mean something for SDF channels.
	tool.mode = VoxelTool.MODE_SET
	tool.value = cmd.get("value", 0)

	# CRITICAL — VoxelTool.do_sphere / do_box take voxel-grid coords,
	# NOT world-space. The terrain has transform.scale = 0.166667
	# (6 vox per metre), so a world position must be divided by that
	# scale before being passed to the tool. terrain.to_local() applies
	# the inverse transform (which for our scale-only setup is *=6).
	#
	# Symptom of getting this wrong: queue drains, _apply_edit logs
	# correctly, BUT the carve appears 1/8 the size and 8x closer to
	# origin than where the player actually swung. Terrain looks
	# untouched because the tiny carve is nowhere near the impact.
	var inv_scale: float = 1.0 / _terrain.scale.x

	match cmd["type"]:
		"sphere":
			var voxel_pos: Vector3    = _terrain.to_local(cmd["pos"])
			var voxel_radius: float   = cmd["radius"] * inv_scale
			var t_carve_start: int = Time.get_ticks_usec()
			tool.do_sphere(voxel_pos, voxel_radius)
			t_phase_carve = Time.get_ticks_usec() - t_carve_start
			var s_aabb_min: Vector3 = cmd["pos"] - Vector3.ONE * cmd["radius"]
			var s_aabb_max: Vector3 = cmd["pos"] + Vector3.ONE * cmd["radius"]
			var t_mark_start: int = Time.get_ticks_usec()
			_mark_chunks_in_aabb(s_aabb_min, s_aabb_max)
			t_phase_mark = Time.get_ticks_usec() - t_mark_start
			var t_emit_start: int = Time.get_ticks_usec()
			edit_applied.emit(
				cmd["pos"],
				_world_to_chunk(cmd["pos"]),
				AABB(s_aabb_min, s_aabb_max - s_aabb_min),
			)
			t_phase_emit = Time.get_ticks_usec() - t_emit_start

		"box":
			var voxel_min: Vector3 = _terrain.to_local(cmd["min"])
			var voxel_max: Vector3 = _terrain.to_local(cmd["max"])
			var t_b_carve_start: int = Time.get_ticks_usec()
			tool.do_box(voxel_min, voxel_max)
			t_phase_carve = Time.get_ticks_usec() - t_b_carve_start
			var t_b_mark_start: int = Time.get_ticks_usec()
			_mark_chunks_in_aabb(cmd["min"], cmd["max"])
			t_phase_mark = Time.get_ticks_usec() - t_b_mark_start
			var center: Vector3 = (cmd["min"] + cmd["max"]) * 0.5
			var t_b_emit_start: int = Time.get_ticks_usec()
			edit_applied.emit(
				center,
				_world_to_chunk(center),
				AABB(cmd["min"], cmd["max"] - cmd["min"]),
			)
			t_phase_emit = Time.get_ticks_usec() - t_b_emit_start

		"box_voxels":
			# Integer voxel-grid coords — pass directly as Vector3 so
			# do_box sees exact values with no to_local() rounding.
			var t_bv_carve_start: int = Time.get_ticks_usec()
			tool.do_box(Vector3(cmd["min"]), Vector3(cmd["max"]))
			t_phase_carve = Time.get_ticks_usec() - t_bv_carve_start
			var bv_world_min: Vector3 = Vector3(cmd["min"]) / VOXELS_PER_METER
			var bv_world_max: Vector3 = (Vector3(cmd["max"]) + Vector3.ONE) / VOXELS_PER_METER
			var t_bv_mark_start: int = Time.get_ticks_usec()
			_mark_chunks_in_aabb(bv_world_min, bv_world_max)
			t_phase_mark = Time.get_ticks_usec() - t_bv_mark_start
			var bv_center: Vector3 = (bv_world_min + bv_world_max) * 0.5
			var t_bv_emit_start: int = Time.get_ticks_usec()
			edit_applied.emit(
				bv_center,
				_world_to_chunk(bv_center),
				AABB(bv_world_min, bv_world_max - bv_world_min),
			)
			t_phase_emit = Time.get_ticks_usec() - t_bv_emit_start

		"set":
			# Single-voxel write. Cubes meshing IS discrete; a 0.5 m
			# sphere clears ~3 cubes at 6 vox/m — feels like a
			# pickaxe-bite of stone rather than the bring-up-sized
			# 1.5 m crater. Bump back up only if a player swing needs
			# to look more dramatic.
			var set_world_radius: float = 0.5
			var set_voxel_pos: Vector3  = _terrain.to_local(cmd["pos"])
			var set_voxel_r: float      = set_world_radius * inv_scale
			tool.do_sphere(set_voxel_pos, set_voxel_r)
			var sv_aabb_min: Vector3 = cmd["pos"] - Vector3.ONE * set_world_radius
			var sv_aabb_max: Vector3 = cmd["pos"] + Vector3.ONE * set_world_radius
			_mark_chunks_in_aabb(sv_aabb_min, sv_aabb_max)
			edit_applied.emit(
				cmd["pos"],
				_world_to_chunk(cmd["pos"]),
				AABB(sv_aabb_min, sv_aabb_max - sv_aabb_min),
			)

		"water_set":
			# Single CHANNEL_DATA byte write. Switch the tool to the
			# DATA channel for this command — restored to COLOR after
			# the match block below for safety, though the tool is
			# discarded at end of _apply_edit so it doesn't matter for
			# the next command.
			var ws_voxel_pos: Vector3i = cmd["voxel_pos"]
			var ws_byte: int = cmd["water_byte"]
			# Water Voxel V2: water is a TYPE block (id 5), not a DATA5
			# byte. Callers still pass WaterByteCodec bytes (SOURCE_BYTE
			# to place, AIR_BYTE/0 to scoop); translate to a CHANNEL_TYPE
			# write so the blocky mesher draws/removes the water block.
			tool.channel = VoxelBuffer.CHANNEL_TYPE
			tool.value = WaterMaterial.render_id_for_level(WaterByteCodec.level_of(ws_byte), WaterByteCodec.dir_of(ws_byte))
			# Editability guard — Zylann's do_box prints "Area not editable"
			# and silently no-ops if the target chunk hasn't been streamed
			# in at LOD0 yet. Re-queue with a retry counter rather than
			# losing the write. Common at world boot when the test pond
			# tries to seed before terrain has finished its first stream.
			var ws_box := AABB(Vector3(ws_voxel_pos), Vector3.ONE)
			if not _try_requeue_if_not_editable(tool, ws_box, cmd):
				return
			# do_box on a 1-voxel box is the same write pattern used
			# by the bulk path. Avoids relying on tool.set_voxel which
			# has churned signatures across Zylann builds.
			tool.do_box(Vector3(ws_voxel_pos), Vector3(ws_voxel_pos) + Vector3.ONE)
			# Stage 6 Phase 1: ALSO persist the WaterByteCodec byte
			# (level + flow dir) into CHANNEL_DATA5. CHANNEL_TYPE above
			# stays the is-water flag the mesher/shader/collision read;
			# DATA5 carries the level the flow sim reads back and the
			# future surface mesher will slope/animate from. An air write
			# (byte not water) clears DATA5 to 0 too, so no stale level
			# lingers under removed water.
			tool.channel = VoxelBuffer.CHANNEL_DATA5
			tool.value = (ws_byte & 0xFF if WaterByteCodec.is_water(ws_byte) else 0)
			tool.do_box(Vector3(ws_voxel_pos), Vector3(ws_voxel_pos) + Vector3.ONE)
			var ws_world: Vector3 = (Vector3(ws_voxel_pos) + Vector3(0.5, 0.5, 0.5)) / VOXELS_PER_METER
			var ws_aabb := AABB(
				Vector3(ws_voxel_pos) / VOXELS_PER_METER,
				Vector3.ONE / VOXELS_PER_METER,
			)
			# Mark the chunk so save persistence picks it up — same
			# bookkeeping as terrain edits. Otherwise a flooded chunk
			# might not be flushed by save_modified_blocks.
			_mark_chunks_in_aabb(ws_aabb.position, ws_aabb.position + ws_aabb.size)
			water_changed_at.emit(ws_world, _world_to_chunk(ws_world), ws_aabb)

		"water_box":
			var wb_min: Vector3i = cmd["voxel_min"]
			var wb_max: Vector3i = cmd["voxel_max"]
			var wb_byte: int = cmd["water_byte"]
			# Water Voxel V2: TYPE-block water (see "water_set" above).
			tool.channel = VoxelBuffer.CHANNEL_TYPE
			tool.value = WaterMaterial.render_id_for_level(WaterByteCodec.level_of(wb_byte), WaterByteCodec.dir_of(wb_byte))
			# Editability guard — see "water_set" above for why.
			var wb_box := AABB(Vector3(wb_min), Vector3(wb_max - wb_min))
			if not _try_requeue_if_not_editable(tool, wb_box, cmd):
				return
			tool.do_box(Vector3(wb_min), Vector3(wb_max))
			# Stage 6 Phase 1: also persist the byte into CHANNEL_DATA5
			# (see "water_set" above for the why). Bulk seeds (test pond,
			# generator ocean via SOURCE_BYTE) get their level/source/dir
			# stored so the sim reads true levels at body edges.
			tool.channel = VoxelBuffer.CHANNEL_DATA5
			tool.value = (wb_byte & 0xFF if WaterByteCodec.is_water(wb_byte) else 0)
			tool.do_box(Vector3(wb_min), Vector3(wb_max))
			var wb_world_min: Vector3 = Vector3(wb_min) / VOXELS_PER_METER
			var wb_world_max: Vector3 = Vector3(wb_max) / VOXELS_PER_METER
			var wb_aabb := AABB(wb_world_min, wb_world_max - wb_world_min)
			_mark_chunks_in_aabb(wb_world_min, wb_world_max)
			var wb_center: Vector3 = (wb_world_min + wb_world_max) * 0.5
			water_changed_at.emit(wb_center, _world_to_chunk(wb_center), wb_aabb)

		"bulk":
			# Bulk single-voxel write — cluster re-deposit (and cluster
			# carve) path. We emit edit_applied ONCE for the whole batch
			# (with the AABB centre as the world position) so downstream
			# listeners still react to the overall event without firing
			# per-voxel.
			#
			# Implementation note: we use do_box on 1-voxel boxes rather
			# than set_voxel(pos, value) because do_box is the only
			# write API exercised by the existing edit verbs and is
			# therefore guaranteed to work here. set_voxel exists in
			# Zylann's API but signature has churned across versions —
			# do_box is the safer pick.
			#
			# NoEditZone perf — naive per-voxel intersect_point queries
			# would stutter for big bulks (a 1000-voxel cluster
			# re-deposit = 1000 physics queries in one frame). We
			# pre-flight with a single AABB shape-query: if no zone
			# overlaps the bulk's AABB at all, every per-voxel check is
			# guaranteed to return "allowed" and we skip the whole
			# inner check. Per-voxel checks only run when a zone IS in
			# the AABB (some voxels in, some out — must check each).
			var writes: Array = cmd.get("writes", [])
			if writes.is_empty():
				return

			# First pass: compute the bulk AABB.
			var bulk_min: Vector3 = writes[0]["pos"]
			var bulk_max: Vector3 = writes[0]["pos"]
			for w0 in writes:
				var p0: Vector3 = w0["pos"]
				bulk_min.x = minf(bulk_min.x, p0.x)
				bulk_min.y = minf(bulk_min.y, p0.y)
				bulk_min.z = minf(bulk_min.z, p0.z)
				bulk_max.x = maxf(bulk_max.x, p0.x)
				bulk_max.y = maxf(bulk_max.y, p0.y)
				bulk_max.z = maxf(bulk_max.z, p0.z)

			# AABB pre-flight against NoEditZone. If false, the per-voxel
			# is_point_inside_no_edit_zone check is provably unnecessary.
			var registry := get_node_or_null("/root/NoEditZoneRegistry")
			var bulk_overlaps_zone: bool = false
			if registry != null and registry.has_method("does_aabb_overlap_no_edit_zone"):
				bulk_overlaps_zone = registry.does_aabb_overlap_no_edit_zone(bulk_min, bulk_max)

			tool.channel = VoxelBuffer.CHANNEL_TYPE
			tool.mode = VoxelTool.MODE_SET
			var written: int = 0
			for w in writes:
				var w_pos: Vector3 = w["pos"]
				# Per-voxel zone check ONLY when a zone overlaps the bulk
				# AABB at all. Otherwise this is provably allowed.
				#
				# Note: we skip _check_edit_allowed() and call the
				# registry directly, because _check_edit_allowed emits
				# edit_rejected_no_edit_zone (the bark trigger) which
				# would fire per-voxel for a cluster falling into a
				# settlement — spammy and wrong (it's the cluster's
				# fault, not the player's).
				if bulk_overlaps_zone and registry != null \
						and registry.is_point_inside_no_edit_zone(w_pos):
					continue
				# Bedrock floor: silently drop any writes at or below the
				# floor. Falling clusters / re-deposits that would land
				# on bedrock just don't write — the bedrock layer wins.
				if w_pos.y <= WORLD_FLOOR_WORLD_Y:
					continue
				tool.value = int(w["value"])
				var v_pos_f: Vector3 = _terrain.to_local(w_pos)
				var v_pos: Vector3 = Vector3(
					floori(v_pos_f.x),
					floori(v_pos_f.y),
					floori(v_pos_f.z),
				)
				# 1-voxel box — min inclusive, max exclusive on each axis.
				tool.do_box(v_pos, v_pos + Vector3.ONE)
				written += 1
			if written == 0:
				return
			_mark_chunks_in_aabb(bulk_min, bulk_max)
			var bulk_center: Vector3 = (bulk_min + bulk_max) * 0.5
			if perf_log_enabled:
				print("[VoxelEditManager] bulk '%s': %d voxels written (zone_check=%s)" % [
					cmd.get("label", "?"), written, bulk_overlaps_zone
				])
			edit_applied.emit(
				bulk_center,
				_world_to_chunk(bulk_center),
				AABB(bulk_min, bulk_max - bulk_min),
			)

	# DIAGNOSTIC — auto-print phase breakdown for slow edits.
	var t_apply_total: int = Time.get_ticks_usec() - t_apply_start
	if t_apply_total > 30000:  # 30 ms
		print("[SPIKE _apply_edit] type=%s total=%d us (carve=%d  mark=%d  emit=%d)" % [
			cmd.get("type", "?"), t_apply_total,
			t_phase_carve, t_phase_mark, t_phase_emit,
		])


func _check_edit_allowed(world_pos: Vector3) -> bool:
	# Returns true if the edit may proceed (i.e., NOT inside a no-edit
	# zone). Returns false if rejected, after emitting the rejection
	# signal so listeners (bark system) can react.
	#
	# Naming note: this returns "is the edit allowed?" rather than
	# "is the point in a zone?" — easier to read at call sites.
	var registry := get_node_or_null("/root/NoEditZoneRegistry")
	if registry == null:
		# No registry autoload yet — defensive fallback. In production
		# the autoload must be registered before VoxelEditManager runs.
		return true

	if registry.is_point_inside_no_edit_zone(world_pos):
		edit_rejected_no_edit_zone.emit(world_pos)
		return false

	return true


# ============================================================
# Private — editability retry
# ============================================================

# Max times a water-edit cmd may be requeued before being dropped. At
# 60 fps the queue drain runs every physics frame, so 60 retries
# covers a 1-second window of "terrain not yet streamed for this
# voxel." If a chunk genuinely can't be streamed (way outside view
# distance, or a stream error), we eventually give up rather than
# pinning the queue forever.
const _MAX_WATER_RETRY: int = 60


func _try_requeue_if_not_editable(tool: VoxelTool, voxel_box: AABB, cmd: Dictionary) -> bool:
	# Returns true if the area is editable (caller proceeds with
	# do_box). Returns false if we requeued the command for a later
	# frame OR dropped it after exhausting retries.
	#
	# Why this exists: Zylann's `tool.do_box` prints "Area not editable"
	# and silently no-ops if the chunk hasn't been streamed in at LOD0.
	# That used to swallow the test-pond seed at world boot and
	# occasionally drop water writes for chunks the player walked
	# toward fast enough to outrun the streamer. With this guard we
	# requeue and retry instead.
	if not tool.has_method("is_area_editable"):
		# Older Zylann build without the probe API — assume editable.
		# Worst case is the same silent no-op we had before.
		return true
	if tool.call("is_area_editable", voxel_box):
		return true
	# Not editable yet. Requeue if we have retries left.
	var retries: int = int(cmd.get("_retry", 0))
	if retries >= _MAX_WATER_RETRY:
		push_warning("[VoxelEditManager] dropping water cmd after %d retries (area never became editable): %s" % [
			retries, cmd.get("type", "?"),
		])
		return false
	cmd["_retry"] = retries + 1
	# Push to the BACK of the queue so we don't spin in a tight loop
	# blocking subsequent commands; this gives the streamer a chance
	# to catch up before we look at this voxel again.
	_edit_queue.append(cmd)
	return false


# ============================================================
# Private — chunk bookkeeping
# ============================================================

func _mark_chunks_in_aabb(min_pos: Vector3, max_pos: Vector3) -> void:
	# A spherical or box edit can overlap multiple chunks. Mark every
	# chunk the edit's bounding box overlaps. We use a coarse AABB
	# rather than walking the actual sphere shape — much cheaper, and
	# a slight over-estimate doesn't hurt anything.
	#
	# At our defaults (16-voxel chunks, 6 voxels per meter = ~2.67 m
	# chunk side), even a 5m-radius sphere only touches a handful of chunks.
	var min_chunk: Vector3i = _world_to_chunk(min_pos)
	var max_chunk: Vector3i = _world_to_chunk(max_pos)
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				_mark_chunk(Vector3i(x, y, z))


func _mark_chunk(chunk_coords: Vector3i) -> void:
	# Add this chunk to the EditedChunkRegistry. Idempotent — re-adding
	# is a no-op since Dictionary keys are unique.
	_edited_chunks[chunk_coords] = true


# ============================================================
# Private — coordinate helpers
# ============================================================

# Voxel scale: 6 voxels per meter — locked in 2026-05-03 as the
# project-wide default. Each voxel block is ~16.67 cm (1/6 m) on a
# side. The VoxelLodTerrain in World3D.tscn has transform.scale =
# 0.166667 to match.
const VOXELS_PER_METER: float = 6.0

# Chunk side length in voxels. Zylann's default for VoxelLodTerrain is
# 16 voxels. If you change `mesh_block_size` or `data_block_size` on
# the terrain node, update this constant to match.
const CHUNK_SIZE_VOXELS: int = 16

# Chunk side length in meters — derived. At 6 vox/m, each chunk is
# 16/6 ≈ 2.67 m on a side.
const CHUNK_SIZE_METERS: float = float(CHUNK_SIZE_VOXELS) / VOXELS_PER_METER


func _world_to_chunk(world_pos: Vector3) -> Vector3i:
	# Convert a world-space position (meters) to the chunk coordinate
	# that contains it.
	return Vector3i(
		floori(world_pos.x / CHUNK_SIZE_METERS),
		floori(world_pos.y / CHUNK_SIZE_METERS),
		floori(world_pos.z / CHUNK_SIZE_METERS),
	)


func _world_to_voxel(world_pos: Vector3) -> Vector3i:
	# Convert a world-space position (meters) to its voxel grid
	# coordinate (each voxel = 1 unit on the grid).
	return Vector3i(
		floori(world_pos.x * VOXELS_PER_METER),
		floori(world_pos.y * VOXELS_PER_METER),
		floori(world_pos.z * VOXELS_PER_METER),
	)


func _estimate_voxel_cost(cmd: Dictionary) -> int:
	# Rough estimate of how many voxels a command will touch. Used to
	# throttle the per-frame budget. Doesn't have to be exact — a
	# small over-estimate just means we're conservative about stutter,
	# which is the safer direction.
	#
	# The 216 multiplier is voxels-per-cubic-meter at our scale:
	# 6 vox/m on each axis = 6^3 = 216 voxels per m^3.
	const VOXELS_PER_CUBIC_METER: float = 216.0
	match cmd["type"]:
		"sphere":
			# Sphere volume = 4/3 * pi * r^3.
			var r: float = cmd["radius"]
			return int(4.18879 * r * r * r * VOXELS_PER_CUBIC_METER)
		"box":
			var size: Vector3 = cmd["max"] - cmd["min"]
			return int(size.x * size.y * size.z * VOXELS_PER_CUBIC_METER)
		"box_voxels":
			var size: Vector3i = cmd["max"] - cmd["min"] + Vector3i.ONE
			return size.x * size.y * size.z
		"set":
			return 1
		"water_set":
			return 1
		"water_box":
			var wb_size: Vector3i = cmd["voxel_max"] - cmd["voxel_min"]
			return maxi(1, wb_size.x * wb_size.y * wb_size.z)
		"bulk":
			return cmd.get("writes", []).size()
		_:
			return 1


# ============================================================
# TODOs — features deferred past the first vertical slice
# ============================================================
#
# 1. LOD-bake-on-eviction. When an edited chunk leaves the player's
#    edit-detail radius, generate a one-time LOD1/LOD2 mesh from the
#    edited voxel state and cache it under
#    `user://saves/slot_{N}/mesh_cache/`. On chunk re-entry, prefer
#    the cached mesh until LOD0 is needed again.
#
#    Why deferred: get the basic edit → save → reload loop working
#    first. The cache is a render-side optimization; correctness
#    doesn't depend on it.
#
# 2. Multi-point NoEditZone check for large box/sphere edits. Right
#    now we check only the center point. A 4m Sapper's Bundle blast
#    centered just outside a NoEditZone could clip into the zone.
#    Fix: sample 8 corners (for boxes) or N points around the surface
#    (for spheres) and reject if ANY point is inside a zone.
#
#    Why deferred: in practice, settlement NoEditZones are authored
#    with 50–100m buffers, so this edge case is rare. Revisit if it
#    actually shows up in playtest.
#
# 3. Save-load rehydration. GameState.load_game() needs to call
#    mark_chunk_loaded_with_deltas() for every chunk that
#    VoxelStreamSQLite reports as having deltas. Wire this in when
#    the save-load path is built.


# ============================================================
# MP-3 — multiplayer routing
# ============================================================
#
# Design (per the approved plan):
#   - OFFLINE / HOST: existing public queue_* functions enqueue and
#     execute locally exactly as before. After the local enqueue,
#     HOST also broadcasts the same command to every connected peer
#     so their client VoxelEditManager re-runs the edit on their
#     local terrain.
#   - CLIENT: public queue_* functions short-circuit at the top —
#     they pack the args into a Dictionary and rpc-send it to the
#     host. The host validates (NoEditZone, queue capacity, bedrock)
#     and either applies+broadcasts or rejects. The client returns
#     true OPTIMISTICALLY so caller code (Roland's tools) doesn't
#     stall waiting for a network round-trip.
#
# NoEditZone enforcement:
#   - Host validates on the request RPC. If rejected, host fires
#     _rpc_edit_rejected back to the originating peer so the client
#     can play Roland's "doesn't yield" bark.
#   - Replica edits on clients (received via _rpc_replicate_edit)
#     SKIP the NoEditZone check — the host already authorized; the
#     client's NoEditZone registry may be transiently out of sync
#     during settlement-load and we trust the host's decision.
#
# WaterFlowManager interaction:
#   - Water byte writes (queue_set_water_voxel / queue_set_water_box)
#     route through the same RPC path. WaterFlowManager itself only
#     simulates flow on the HOST (gated in its _physics_process); the
#     simulator's per-tick byte writes go through this manager's MP
#     path so guests receive every cell change as a normal edit.

const _MP_RPC_RELIABLE_REQUEST: String = "_rpc_request_edit"
const _MP_RPC_RELIABLE_REPLICATE: String = "_rpc_replicate_edit"
const _MP_RPC_RELIABLE_REJECTED: String = "_rpc_edit_rejected"

# Per-peer rate limit: max requests/second a single guest can send.
# Prevents accidental flood from a misbehaving client tool. Host
# tracks per-sender request timestamps in a sliding window.
const _MP_RATE_LIMIT_PER_SECOND: int = 60
var _mp_request_window: Dictionary = {}   # peer_id -> Array[float] (timestamps)


func _mp_is_active() -> bool:
	# True when a multiplayer session is live. In OFFLINE mode the rest
	# of the MP routing collapses to no-ops.
	if not get_node_or_null("/root/MultiplayerManager"):
		return false
	return not MultiplayerManager.is_offline()


func _mp_is_client() -> bool:
	return _mp_is_active() and MultiplayerManager.is_client()


func _mp_is_host_with_peers() -> bool:
	# Host with at least one connected guest. No point broadcasting if
	# nobody's listening. In OFFLINE mode is_host() returns true but
	# _mp_is_active() returns false, so this collapses cleanly.
	if not _mp_is_active():
		return false
	if not MultiplayerManager.is_host():
		return false
	if "peers" in MultiplayerManager:
		var peers: Dictionary = MultiplayerManager.peers
		# peers includes the host itself; >1 means at least one guest.
		return peers.size() > 1
	return false


func _mp_send_request_to_host(cmd: Dictionary) -> void:
	# Client → host. Reliable so a dropped packet doesn't silently
	# lose Roland's swing.
	rpc_id(1, _MP_RPC_RELIABLE_REQUEST, cmd)


func _mp_broadcast_replica(cmd: Dictionary) -> void:
	# Host → all clients (excluding self via call_remote in @rpc).
	rpc(_MP_RPC_RELIABLE_REPLICATE, cmd)


func _mp_check_rate_limit(peer_id: int) -> bool:
	# Sliding-window rate limit. Returns false if this peer has hit
	# the cap in the last second; true otherwise. Sender's window is
	# trimmed to the last 1 s on every check.
	var now: float = Time.get_ticks_msec() / 1000.0
	var window: Array = _mp_request_window.get(peer_id, [])
	# Drop entries older than 1 s.
	while window.size() > 0 and (now - float(window[0])) > 1.0:
		window.pop_front()
	if window.size() >= _MP_RATE_LIMIT_PER_SECOND:
		_mp_request_window[peer_id] = window
		return false
	window.append(now)
	_mp_request_window[peer_id] = window
	return true


func _mp_apply_replica(cmd: Dictionary) -> void:
	# A host-authoritative edit just arrived. Apply it WITHOUT the
	# NoEditZone gate (host already approved). Other guards (bedrock,
	# queue capacity) still apply — if our queue is full we drop the
	# replica and rely on visual reconciliation when the chunk
	# eventually re-syncs from the host's saved deltas.
	var t: String = String(cmd.get("type", ""))
	match t:
		"sphere":
			var p: Vector3 = cmd.get("pos", Vector3.ZERO)
			var r: float = float(cmd.get("radius", 0.0))
			if (p.y - r) <= WORLD_FLOOR_WORLD_Y:
				return
			if _edit_queue.size() < max_queue_length:
				_edit_queue.append({
					"type": "sphere",
					"pos": p,
					"radius": r,
					"value": int(cmd.get("value", 0)),
				})
		"box":
			var mn: Vector3 = cmd.get("min", Vector3.ZERO)
			var mx: Vector3 = cmd.get("max", Vector3.ZERO)
			if mn.y <= WORLD_FLOOR_WORLD_Y:
				return
			if _edit_queue.size() < max_queue_length:
				_edit_queue.append({
					"type": "box",
					"min": mn,
					"max": mx,
					"value": int(cmd.get("value", 0)),
				})
		"box_voxels":
			var vmn: Vector3i = cmd.get("min", Vector3i.ZERO)
			var vmx: Vector3i = cmd.get("max", Vector3i.ZERO)
			if vmn.y <= WORLD_FLOOR_VOXEL_Y:
				return
			if _edit_queue.size() < max_queue_length:
				_edit_queue.append({
					"type": "box_voxels",
					"min": vmn,
					"max": vmx,
					"value": int(cmd.get("value", 0)),
				})
		"set":
			var sp: Vector3 = cmd.get("pos", Vector3.ZERO)
			if sp.y <= WORLD_FLOOR_WORLD_Y:
				return
			if _edit_queue.size() < max_queue_length:
				_edit_queue.append({
					"type": "set",
					"pos": sp,
					"value": int(cmd.get("value", 0)),
				})
		"water_set":
			if _edit_queue.size() < max_queue_length:
				_edit_queue.append({
					"type": "water_set",
					"voxel_pos": cmd.get("voxel_pos", Vector3i.ZERO),
					"water_byte": int(cmd.get("water_byte", 0)) & 0xFF,
				})
		"water_box":
			if _edit_queue.size() < max_queue_length:
				_edit_queue.append({
					"type": "water_box",
					"voxel_min": cmd.get("voxel_min", Vector3i.ZERO),
					"voxel_max": cmd.get("voxel_max", Vector3i.ZERO),
					"water_byte": int(cmd.get("water_byte", 0)) & 0xFF,
				})
		"bulk":
			# Replica bulk writes are trusted whole — no per-voxel
			# NoEditZone re-check.
			if _edit_queue.size() < max_queue_length:
				_edit_queue.append({
					"type": "bulk",
					"writes": cmd.get("writes", []),
					"label": "replica:" + String(cmd.get("label", "bulk")),
				})


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_edit(cmd: Dictionary) -> void:
	# Client → host. Re-runs the public queue_* path on the host so
	# every guard (NoEditZone, bedrock, queue capacity) executes
	# identically to a host-local edit. On success the same path
	# broadcasts to peers via _mp_broadcast_replica; on failure the
	# host pings the originator with a rejection.
	if not get_node_or_null("/root/MultiplayerManager"):
		return
	if not MultiplayerManager.is_host():
		return  # only host accepts requests
	var sender: int = multiplayer.get_remote_sender_id()
	if not _mp_check_rate_limit(sender):
		push_warning("[VoxelEditManager] Rate-limit drop from peer %d" % sender)
		return
	var t: String = String(cmd.get("type", ""))
	var ok: bool = false
	match t:
		"sphere":
			ok = queue_edit_sphere(
				cmd.get("pos", Vector3.ZERO),
				float(cmd.get("radius", 0.0)),
				int(cmd.get("value", 0)),
			)
		"box":
			ok = queue_edit_box(
				cmd.get("min", Vector3.ZERO),
				cmd.get("max", Vector3.ZERO),
				int(cmd.get("value", 0)),
			)
		"box_voxels":
			ok = queue_edit_box_voxels(
				cmd.get("min", Vector3i.ZERO),
				cmd.get("max", Vector3i.ZERO),
				int(cmd.get("value", 0)),
			)
		"set":
			ok = queue_set_voxel(
				cmd.get("pos", Vector3.ZERO),
				int(cmd.get("value", 0)),
			)
		"water_set":
			ok = queue_set_water_voxel(
				cmd.get("voxel_pos", Vector3i.ZERO),
				int(cmd.get("water_byte", 0)),
			)
		"water_box":
			ok = queue_set_water_box(
				cmd.get("voxel_min", Vector3i.ZERO),
				cmd.get("voxel_max", Vector3i.ZERO),
				int(cmd.get("water_byte", 0)),
			)
		"bulk":
			ok = queue_set_voxels_bulk(cmd.get("writes", []), String(cmd.get("label", "bulk")))
	if not ok:
		# Host-side validation failed (NoEditZone, bedrock, queue full).
		# Tell the originator so it can play Roland's bark.
		var rej_pos: Vector3 = cmd.get("pos", Vector3.ZERO)
		rpc_id(sender, _MP_RPC_RELIABLE_REJECTED, rej_pos)


@rpc("authority", "call_remote", "reliable")
func _rpc_replicate_edit(cmd: Dictionary) -> void:
	# Host → all clients. Apply the trusted edit locally without
	# re-validating NoEditZone.
	_mp_apply_replica(cmd)


@rpc("authority", "call_remote", "reliable")
func _rpc_edit_rejected(world_pos: Vector3) -> void:
	# Host → originating client. Surface as the existing rejection
	# signal so listeners (Roland's "doesn't yield" bark) fire on the
	# client too.
	edit_rejected_no_edit_zone.emit(world_pos)
