extends Node
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

const WORLD_GENERATOR_VERSION: int = 11
# Bump this constant whenever the procedural baseline produced by
# the active generator (currently CubicHeightmapGenerator) changes
# shape OR encoding — e.g. swap to a new heightmap, change cave
# parameters, change biome material indices, or change what the
# alpha byte means.
#
# Version history:
#   v9  → CubicHeightmapGenerator. Voxels written as packed RGBA;
#         alpha byte was always 255 for solids. No material concept.
#   v10 → CubicHeightmapGenerator with material-band assignment.
#         Alpha byte now encodes the VoxelMaterialRegistry material_id
#         (1=stone, 2=dirt, 3=grass, 4=sand, …). Surface terrain looks
#         visibly different (grass-on-top, dirt layer, stone deep).
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

signal edit_applied(world_pos: Vector3, chunk_coords: Vector3i)
# Fired after every successfully applied edit. Caller systems listen to
# this — for example, to award XP to the Mining/Excavation/Felling
# sub-skills (per design/SKILLS_AND_PROGRESSION.md), or to spawn a
# particle effect at the impact site.

signal edit_rejected_no_edit_zone(world_pos: Vector3)
# Fired when an edit is rejected because it's inside a NoEditZone.
# The bark system listens and triggers Roland's "This place doesn't
# yield to me." line, throttled to once per session per zone.


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
	# Queue a spherical voxel edit centered at world_pos with the given
	# radius (in meters).
	#
	# voxel_value semantics for VoxelMesherCubes (blocky terrain):
	#   0 = AIR — carves out (the pickaxe / axe / shovel / explosive case)
	#   N = material index — fills with material N (the place-block case)
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
	return true


func queue_edit_box(min_pos: Vector3, max_pos: Vector3, voxel_value: int) -> bool:
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
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping box edit")
		return false

	_edit_queue.append({
		"type": "box",
		"min": min_pos,
		"max": max_pos,
		"value": voxel_value,
	})
	return true


func queue_edit_box_voxels(voxel_min: Vector3i, voxel_max: Vector3i, voxel_value: int) -> bool:
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
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping box_voxels edit")
		return false
	_edit_queue.append({
		"type": "box_voxels",
		"min": voxel_min,
		"max": voxel_max,
		"value": voxel_value,
	})
	return true


func queue_set_voxel(world_pos: Vector3, voxel_value: int) -> bool:
	# Single-voxel write. Used for per-block placement in Build Mode →
	# Detail submode (design/CRAFTING.md → "Per-Voxel Placement"), and
	# for any fine-grained edit that touches exactly one voxel.

	if not _check_edit_allowed(world_pos):
		return false
	if _edit_queue.size() >= max_queue_length:
		push_warning("VoxelEditManager: queue full, dropping set-voxel edit")
		return false

	_edit_queue.append({
		"type": "set",
		"pos": world_pos,
		"value": voxel_value,
	})
	return true


func queue_set_voxels_bulk(voxel_writes: Array, label: String = "bulk") -> bool:
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

	# Edits target CHANNEL_COLOR because the world uses VoxelMesherCubes,
	# which reads packed RGBA per-voxel. CHANNEL_SDF / CHANNEL_TYPE are
	# the wrong channel for Cubes — writes go through but the mesher
	# never sees them, so terrain looked untouched even though the queue
	# drained. (When/if we ever swap mesher, this is the line to revisit
	# alongside the generator's _get_used_channels_mask.)
	tool.channel = VoxelBuffer.CHANNEL_COLOR

	# Cubes uses one mode: SET. The packed RGBA value to write goes in
	# tool.value. value 0 means alpha=0 = air = "carved" (no cube emitted
	# by the mesher). Non-zero = fill of that color (Build-Mode block
	# placement, future). MODE_REMOVE / MODE_ADD only mean something for
	# SDF channels — they were silently no-oping for the COLOR channel
	# even when the channel was right.
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
			var t_sphere_start: int = 0
			if perf_log_enabled:
				t_sphere_start = Time.get_ticks_usec()
			tool.do_sphere(voxel_pos, voxel_radius)
			if perf_log_enabled:
				var sphere_us: int = Time.get_ticks_usec() - t_sphere_start
				var est_voxels: int = _estimate_voxel_cost(cmd)
				print("[PERF VEM] sphere r=%.1fm est_vox=%d  do_sphere=%d us  (%.2f ms)" % [
					cmd["radius"], est_voxels, sphere_us, sphere_us / 1000.0
				])
			_mark_chunks_in_aabb(
				cmd["pos"] - Vector3.ONE * cmd["radius"],
				cmd["pos"] + Vector3.ONE * cmd["radius"],
			)
			edit_applied.emit(cmd["pos"], _world_to_chunk(cmd["pos"]))

		"box":
			var voxel_min: Vector3 = _terrain.to_local(cmd["min"])
			var voxel_max: Vector3 = _terrain.to_local(cmd["max"])
			tool.do_box(voxel_min, voxel_max)
			_mark_chunks_in_aabb(cmd["min"], cmd["max"])
			var center: Vector3 = (cmd["min"] + cmd["max"]) * 0.5
			edit_applied.emit(center, _world_to_chunk(center))

		"box_voxels":
			# Integer voxel-grid coords — pass directly as Vector3 so
			# do_box sees exact values with no to_local() rounding.
			tool.do_box(Vector3(cmd["min"]), Vector3(cmd["max"]))
			var bv_world_min: Vector3 = Vector3(cmd["min"]) / VOXELS_PER_METER
			var bv_world_max: Vector3 = (Vector3(cmd["max"]) + Vector3.ONE) / VOXELS_PER_METER
			_mark_chunks_in_aabb(bv_world_min, bv_world_max)
			var bv_center: Vector3 = (bv_world_min + bv_world_max) * 0.5
			edit_applied.emit(bv_center, _world_to_chunk(bv_center))

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
			_mark_chunks_in_aabb(
				cmd["pos"] - Vector3.ONE * set_world_radius,
				cmd["pos"] + Vector3.ONE * set_world_radius,
			)
			edit_applied.emit(cmd["pos"], _world_to_chunk(cmd["pos"]))

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

			tool.channel = VoxelBuffer.CHANNEL_COLOR
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
			edit_applied.emit(bulk_center, _world_to_chunk(bulk_center))


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
