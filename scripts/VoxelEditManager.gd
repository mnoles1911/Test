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

const WORLD_GENERATOR_VERSION: int = 1
# Bump this constant whenever the procedural baseline produced by
# VoxelGeneratorGraph (or the placeholder VoxelGeneratorFlat) changes
# shape — e.g. when we swap to a new EXR heightmap, change cave
# parameters, or add new biome material indices.
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

@export var voxels_per_frame: int = 256
# Maximum number of voxels we'll attempt to write per physics frame.
# This is the throttle that prevents big edits (explosives, spells)
# from stuttering the frame rate.
#
# 256 is a starting guess. Real sweet spot depends on voxel size,
# mesher cost, and target hardware. Tune up if edits feel sluggish in
# play; tune down if you see frame drops during heavy edit traffic.
#
# A single command (e.g. one big sphere) can exceed this in one go —
# the budget gates how many commands we *start* per frame, not how
# big each one is allowed to be.

@export var max_queue_length: int = 2048
# Hard cap on how many edit commands can wait in the queue at once.
# Stops the queue from growing unbounded if something pathological
# happens (e.g. a runaway spell effect). Commands beyond this are
# rejected at queue time with a push_warning.


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

	var voxels_used: int = 0
	while not _edit_queue.is_empty() and voxels_used < voxels_per_frame:
		var cmd: Dictionary = _edit_queue.pop_front()
		voxels_used += _estimate_voxel_cost(cmd)
		_apply_edit(cmd)


# ============================================================
# Private — edit application
# ============================================================

func _apply_edit(cmd: Dictionary) -> void:
	# Pull a fresh VoxelTool from the terrain. We do NOT cache the
	# VoxelTool because it can become stale across frames — grab a
	# new one each time per Zylann's recommended usage.
	var tool: VoxelTool = _terrain.get_voxel_tool()
	if tool == null:
		return

	# Edits target the signed distance field channel (CHANNEL_SDF)
	# because the test world uses VoxelMesherTransvoxel which reads
	# SDF. When the world swaps to VoxelMesherBlocky + a
	# VoxelBlockyLibrary (the design intent), this becomes
	# CHANNEL_TYPE again with type-id writes.
	tool.channel = VoxelBuffer.CHANNEL_SDF

	# Voxel value 0 = air = "carve" (subtract). Anything else = "fill"
	# (add). For now every edit verb passes 0 (pickaxe carves, axe
	# carves a tree-shaped hole, explosive carves a sphere). Block
	# placement (Build Mode) will pass a non-zero material ID.
	var carve_mode: bool = cmd.get("value", 0) == 0
	tool.mode = VoxelTool.MODE_REMOVE if carve_mode else VoxelTool.MODE_ADD

	match cmd["type"]:
		"sphere":
			# do_sphere takes world-space center and radius (meters).
			tool.do_sphere(cmd["pos"], cmd["radius"])
			_mark_chunks_in_aabb(
				cmd["pos"] - Vector3.ONE * cmd["radius"],
				cmd["pos"] + Vector3.ONE * cmd["radius"],
			)
			edit_applied.emit(cmd["pos"], _world_to_chunk(cmd["pos"]))

		"box":
			# do_box takes two world-space corner positions.
			tool.do_box(cmd["min"], cmd["max"])
			_mark_chunks_in_aabb(cmd["min"], cmd["max"])
			var center: Vector3 = (cmd["min"] + cmd["max"]) * 0.5
			edit_applied.emit(center, _world_to_chunk(center))

		"set":
			# Single-voxel write. With SDF meshing there's no clean
			# "remove exactly one voxel" operation — the surface is
			# defined by smooth distance values, not discrete cells.
			# Use a small sphere (~0.3m, roughly 2-3 voxels at our
			# 8-vox/m scale) so a pickaxe click produces a visible
			# divot. When we move to VoxelMesherBlocky with a library,
			# this branch becomes a true single-cell write again.
			tool.do_sphere(cmd["pos"], 0.3)
			_mark_chunks_in_aabb(
				cmd["pos"] - Vector3.ONE * 0.3,
				cmd["pos"] + Vector3.ONE * 0.3,
			)
			edit_applied.emit(cmd["pos"], _world_to_chunk(cmd["pos"]))


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
	# At our defaults (16-voxel chunks, 8 voxels per meter = 2m chunk
	# side), even a 5m-radius sphere only touches a handful of chunks.
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

# Voxel scale: 8 voxels per meter, per design/3D_VOXEL_MIGRATION.md.
# Each voxel block is 12.5cm on a side.
const VOXELS_PER_METER: float = 8.0

# Chunk side length in voxels. Zylann's default for VoxelLodTerrain is
# 16 voxels. If you change `mesh_block_size` or `data_block_size` on
# the terrain node, update this constant to match.
const CHUNK_SIZE_VOXELS: int = 16

# Chunk side length in meters — derived. At default settings each
# chunk is 2m × 2m × 2m.
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
	# The 512 multiplier is voxels-per-cubic-meter at our scale:
	# 8 vox/m on each axis = 8^3 = 512 voxels per m^3.
	const VOXELS_PER_CUBIC_METER: float = 512.0
	match cmd["type"]:
		"sphere":
			# Sphere volume = 4/3 * pi * r^3.
			var r: float = cmd["radius"]
			return int(4.18879 * r * r * r * VOXELS_PER_CUBIC_METER)
		"box":
			var size: Vector3 = cmd["max"] - cmd["min"]
			return int(size.x * size.y * size.z * VOXELS_PER_CUBIC_METER)
		"set":
			return 1
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
