extends Node
# VoxelGravityManager — voxels obey gravity.
#
# How this works in plain English:
#
# Every time a player edit lands (pickaxe swing, axe felling, explosive
# blast — anything that goes through VoxelEditManager), this autoload
# wakes up and asks: "did that edit leave any voxels floating in
# midair without support?"
#
# It answers by reading every voxel in a small bubble around the edit
# (16 m default, capped at 32 m), running a flood-fill that marks
# anchored voxels (anything connected to the bubble's edge or to a
# NoEditZone), and treating everything else as an "unsupported island."
#
# Each unsupported island is then:
#   1. Carved out of the terrain (so it doesn't render twice).
#   2. Spawned as a FallingVoxelCluster RigidBody3D.
#   3. Allowed to fall, tip, and damage things on its way down.
#   4. Re-deposited as terrain wherever it comes to rest.
#
# Why local detection: a true bedrock-connectivity check would be
# unboundedly expensive (multi-second freezes for big excavations).
# Local detection caps work at ~32^3 = ~33k voxel reads per edit,
# which is bounded and matches Minecraft's behaviour.
#
# Registered as an autoload AFTER VoxelEditManager (load order matters
# so the edit_applied signal exists when we connect to it).
#
# Reference: design/3D_VOXEL_MIGRATION.md → "Voxel Gravity"


# =============================================================
# CONFIGURATION (tunable in the Inspector)
# =============================================================

@export var analysis_padding_m: float = 4.0
# Distance (meters) the analysis bubble extends past the edit centre
# on each axis. Anything past this radius is treated as anchored — a
# long arch whose support is removed > 4 m away will not fall. Bounded
# cost and matches the Minecraft model.
#
# History: started at 8.0 (16 m side) which produced 7.6-second freezes
# on a 3 m explosive blast in dense bedrock — the 96^3 = 880k voxel
# reads dominated wall time, and the work produced zero falling
# clusters because everything was anchored to the bottom face. Cutting
# to 4.0 (8 m side, ~13× smaller volume) drops the cost ~13× while
# still covering any disconnection caused by edits up to ~3 m radius
# (the largest player carve currently is the 3 m PowderCharge or 6 m
# Sapper's Bundle — for the 6 m case, raise this in the inspector).

@export var max_analysis_side_m: float = 8.0
# Hard cap on the bubble's side length. Even very large blasts won't
# scan more than this. 8 m at 6 vox/m = 48 voxels per side, ~110k
# bubble volume.

@export var use_bulk_read: bool = true
# Use Zylann's VoxelTool.copy() to read the bubble in one C++ call
# rather than calling tool.get_voxel() per voxel from GDScript. The
# per-voxel path was the dominant cost in the 7.6 s explosive freeze
# (6.07 s of 7.6 s). Bulk read trades a single C++ memcpy-class call
# for ~880k native crossings.
#
# Falls back to per-voxel reads automatically if the active Zylann
# build doesn't expose `copy` on VoxelTool — older / minimal builds
# may not. Set to false to force the legacy path for A/B comparison.

@export var max_cluster_voxels: int = 4096
# Skip clusters larger than this (treat as anchored). One Zylann chunk
# is 16^3 = 4096 voxels — keeping clusters within one chunk's worth
# means re-deposit fits comfortably in a single per-frame budget.

@export var min_cluster_voxels: int = 2
# Skip single-voxel "clusters." A lone floating voxel just disappears
# (we still carve it from terrain). Spawning a rigid body for one cube
# is wasteful and looks silly.

@export var max_scans_per_frame: int = 1
# At most one analysis bubble is processed per physics frame. Edits
# that fire the same frame queue up here.

@export var max_active_clusters: int = 32
# Beyond this count, new clusters skip the rigid-body step (they're
# just carved from terrain, no fall). Stops a chain reaction of
# explosions from spawning hundreds of bodies at once.

@export var scan_queue_max: int = 16
# Hard cap on the analysis-bubble queue. If this overflows we drop
# the OLDEST pending scan (the player's already moved on) and log it.

@export var enabled: bool = true
# Master kill-switch. Disable to debug whether a problem is gravity-
# related or terrain-related.

@export var perf_log_enabled: bool = false
# When true, dump phase-by-phase microsecond timings for each
# analysis bubble. Look for "[PERF VGM]" in the Output panel.
# OFF by default — gravity scans run on every voxel edit (every
# tool swing, every PICKUP_DROP collapse) and the print itself
# contributes to main-thread hitches. Flip on for diagnostics.
#
# Phases reported (in order):
#   read       — copying every voxel in the bubble into the `solids`
#                dictionary via tool.get_voxel(). 96^3 = ~880k reads
#                worst case at default settings; suspected hot path.
#   anchor_pre — NoEditZone AABB pre-flight + bottom-face anchor seed.
#   floodfill  — BFS flood-fill propagating "anchored" through 6-conn.
#   partition  — splitting unanchored set into LOOSE vs CLUSTER per
#                material fall_behavior.
#   loose      — sand-style instant column-fall pass.
#   cluster    — connected-component grouping + rigid-body spawning.
#   total      — sum from start to end of _process_bubble.
#
# Print only fires when total > perf_log_min_us (default 1 ms) so
# tiny pickaxe-bite scans don't spam the console.

@export var perf_log_min_us: int = 1000
# Minimum total bubble time (microseconds) for a perf log line. 1 ms
# default — anything below is noise. Raise to 10000 to filter to only
# noticeably-expensive scans.


# =============================================================
# CONSTANTS
# =============================================================

const VOXEL_SIZE_M: float = 1.0 / 6.0
const VOXELS_PER_METER: float = 6.0

const FALLING_CLUSTER_SCENE_PATH: String = "res://scenes/voxel/FallingVoxelCluster.tscn"


# =============================================================
# RUNTIME STATE
# =============================================================

var _scan_queue: Array[Dictionary] = []
# Pending analysis bubbles, FIFO. Each entry:
#   { "world_pos": Vector3, "chunk": Vector3i }

var _active_clusters: Array[Node] = []
# Live FallingVoxelCluster nodes. Cleaned up via notify_cluster_settled
# when each settles, or via tree-scan if a cluster is freed without
# notifying us.

var _cluster_scene: PackedScene = null
# Cached PackedScene reference — preloaded in _ready.

var _last_read_used_bulk: bool = false
# True if the most recent _process_bubble used VoxelTool.copy()
# (vs. the per-voxel get_voxel() fallback). Used only by the perf
# log to label which path was taken.


# =============================================================
# SIGNALS
# =============================================================

signal cluster_spawned(cluster: Node)
signal cluster_settled(cluster: Node, landing_pos: Vector3)


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Wire up to the edit signal. VoxelEditManager loads before us per
	# the autoload order in project.godot, so it's always available
	# here.
	if get_node_or_null("/root/VoxelEditManager"):
		VoxelEditManager.edit_applied.connect(_on_edit_applied)
		print("[VoxelGravityManager] connected to VoxelEditManager.edit_applied")
	else:
		push_warning("[VoxelGravityManager] VoxelEditManager not registered; gravity disabled")
		enabled = false

	# Preload the cluster scene so per-spawn cost is minimal.
	_cluster_scene = load(FALLING_CLUSTER_SCENE_PATH) as PackedScene
	if _cluster_scene == null:
		push_error("[VoxelGravityManager] could not load %s" % FALLING_CLUSTER_SCENE_PATH)
		enabled = false


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	# MP-3 host gate — same reasoning as the _on_edit_applied gate.
	# Falling clusters are spawned on host; MP-4 will add MultiplayerSpawner
	# wiring so guests receive them. Until then guests simply don't
	# simulate gravity locally.
	if get_node_or_null("/root/MultiplayerManager") != null and not MultiplayerManager.is_host():
		return
	# Drain pending drop spawns regardless of scan-queue state — they
	# pile up after a big carve and need to come out smoothly even on
	# frames when no new scan runs.
	_drain_pending_drops()
	if _scan_queue.is_empty():
		return
	# Process at most max_scans_per_frame bubbles.
	var processed: int = 0
	while not _scan_queue.is_empty() and processed < max_scans_per_frame:
		var bubble: Dictionary = _scan_queue.pop_front()
		_process_bubble(bubble["world_pos"], bubble.get("edit_aabb", AABB()))
		processed += 1


# =============================================================
# PUBLIC API
# =============================================================

func get_active_cluster_count() -> int:
	# Scrub stale entries (clusters freed by queue_free without
	# notifying us — e.g. fell off the world).
	_active_clusters = _active_clusters.filter(func(c): return is_instance_valid(c))
	return _active_clusters.size()


func clear_all_falling_clusters() -> void:
	# Called on world unload. Free every live cluster without
	# re-depositing — the world is going away anyway.
	for c in _active_clusters:
		if is_instance_valid(c):
			c.queue_free()
	_active_clusters.clear()
	_scan_queue.clear()


func notify_cluster_settled(cluster: Node, landing_pos: Vector3) -> void:
	# Called by FallingVoxelCluster._settle_and_redeposit so we can
	# update our active count and emit the public signal.
	_active_clusters.erase(cluster)
	cluster_settled.emit(cluster, landing_pos)


# =============================================================
# SIGNAL HANDLER
# =============================================================

func _on_edit_applied(world_pos: Vector3, chunk_coords: Vector3i, edit_aabb: AABB) -> void:
	if not enabled:
		return
	# MP-3 host gate — gravity scans + falling-cluster physics are
	# host-authoritative. Guests will receive cluster spawn/state via
	# MultiplayerSpawner once MP-4 wires it; for now they simply skip
	# the scan and never spawn local clusters of their own.
	# OFFLINE (no session) → is_host() returns true → unchanged.
	if get_node_or_null("/root/MultiplayerManager") != null and not MultiplayerManager.is_host():
		return
	# Drop oldest if the queue is full — the player's already moved on
	# from the older edit; the recent one is more interesting. Note that
	# our own bulk carve + re-deposit fire edit_applied too, which queues
	# follow-up scans. Those scans exit cheaply (the voxels involved are
	# anchored to the bubble's bottom face by construction), so the
	# re-entry is wasted work but not incorrect. If perf demands it, plumb
	# a "skip_gravity" flag through the bulk command.
	if _scan_queue.size() >= scan_queue_max:
		var dropped: Dictionary = _scan_queue.pop_front()
		if perf_log_enabled:
			print("[VoxelGravityManager] scan queue full, dropping bubble at %s" % dropped["world_pos"])
	_scan_queue.append({
		"world_pos": world_pos,
		"chunk": chunk_coords,
		"edit_aabb": edit_aabb,
	})


# =============================================================
# CORE — process one analysis bubble
# =============================================================

func _process_bubble(edit_world_pos: Vector3, edit_aabb: AABB) -> void:
	# Cap on active clusters before we even read voxels — if we're
	# already at the limit, skip the whole thing.
	if get_active_cluster_count() >= max_active_clusters:
		return

	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return
	tool.channel = VoxelBuffer.CHANNEL_TYPE

	# DIAGNOSTIC — always capture t_start so we can auto-print slow
	# scans without needing perf_log_enabled. Phase timers below stay
	# gated for the detailed [PERF VGM] line; the auto-print is a
	# lightweight safety net specifically for hunting freeze sources.
	var t_start: int = Time.get_ticks_usec()
	var t_after_read: int = 0
	var t_after_anchor_pre: int = 0
	var t_after_floodfill: int = 0
	var t_after_partition: int = 0
	var t_after_loose: int = 0
	var t_after_cluster: int = 0

	# --- Define the analysis box in voxel-grid space ---
	# Adaptive padding: the bubble extends a small buffer beyond the
	# edit's own AABB so we catch voxels that just lost support, but
	# not so large that scan cost dwarfs the edit cost.
	# Old behaviour (fixed analysis_padding_m=4 m → 49^3=117k cells per
	# scan = ~150 ms) caused the explosive-throw freeze: a 0.8 m carve
	# was triggering a 4 m bubble read. With adaptive padding, that
	# same carve runs ~1.8 m → ~22^3 ≈ 10k cells, ~10× faster.
	# Cascade scans (the bulk write of carved unsupported voxels fires
	# its own edit_applied) get the same shrinking treatment because
	# their AABB matches their carve.
	var max_extent: float = maxf(edit_aabb.size.x, maxf(edit_aabb.size.y, edit_aabb.size.z))
	# Empty/zero AABB (older callers, or carves of zero size) falls back
	# to the legacy padding so we don't accidentally shrink to zero.
	var adaptive_half_side_m: float
	if max_extent <= 0.01:
		adaptive_half_side_m = analysis_padding_m
	else:
		# Half the longest extent + 1 m of buffer for cascade catch.
		adaptive_half_side_m = max_extent * 0.5 + 1.0
	var half_side_m: float = clampf(adaptive_half_side_m, 1.0, max_analysis_side_m * 0.5)
	var half_side_vox: int = int(ceili(half_side_m * VOXELS_PER_METER))
	# Centre voxel.
	var centre_v: Vector3i = VoxelEditManager.world_to_voxel(edit_world_pos)
	var min_v: Vector3i = centre_v - Vector3i.ONE * half_side_vox
	var max_v: Vector3i = centre_v + Vector3i.ONE * half_side_vox
	var side: int = (max_v.x - min_v.x) + 1
	var bubble_volume: int = side * side * side

	# --- Read the bubble into a flat dictionary ---
	# Keys: Vector3i (relative to min_v, so 0..side-1 on each axis).
	# Values: int (material_id from CHANNEL_TYPE). Air voxels (type=0)
	# are NOT inserted; absence-from-dict means air. This keeps memory
	# proportional to solid-voxel count, not bubble volume.
	#
	# Two read paths:
	#   1. BULK (preferred) — VoxelTool.copy() pulls the full bubble
	#      into a VoxelBuffer in one C++ call, then we iterate the
	#      buffer (which is in-process memory) to build the dict.
	#      Avoids the per-voxel GDScript→native cross, which was the
	#      6.07 s hot path in the 7.6 s explosive freeze.
	#   2. PER-VOXEL (fallback) — original tool.get_voxel() loop. Used
	#      if the active Zylann build doesn't expose `copy` on
	#      VoxelTool, OR if `use_bulk_read = false`.
	var solids: Dictionary = {}
	_last_read_used_bulk = use_bulk_read and tool.has_method("copy")
	if _last_read_used_bulk:
		# Zylann's VoxelTool.copy() signature in this build is
		#   copy(src_origin: Vector3i, dst_buffer: VoxelBuffer, channels_mask: int)
		# The destination buffer's pre-allocated size determines how much
		# is copied — the source rectangle is implicitly
		# [src_origin .. src_origin + buf.size). Older docs and other
		# bindings used (AABB, VoxelBuffer, int); this one wants the
		# raw integer corner. We size the buffer first, then pass the
		# minimum-corner voxel coord directly.
		var buf: VoxelBuffer = VoxelBuffer.new()
		buf.create(side, side, side)
		# Channels mask = bit for CHANNEL_TYPE. The mesher (Blocky) reads
		# TYPE (material_id integer); COLOR/SDF channels are unused.
		var type_mask: int = 1 << VoxelBuffer.CHANNEL_TYPE
		tool.copy(min_v, buf, type_mask)
		for x in range(side):
			for y in range(side):
				for z in range(side):
					var packed: int = buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE)
					if (packed & 0xFF) == 0:
						continue
					solids[Vector3i(x, y, z)] = packed
	else:
		for x in range(side):
			for y in range(side):
				for z in range(side):
					var v_world_grid: Vector3i = min_v + Vector3i(x, y, z)
					var packed: int = tool.get_voxel(v_world_grid)
					if (packed & 0xFF) == 0:
						continue
					solids[Vector3i(x, y, z)] = packed
	if perf_log_enabled:
		t_after_read = Time.get_ticks_usec()

	if solids.is_empty():
		if perf_log_enabled:
			var early_total: int = Time.get_ticks_usec() - t_start
			if early_total >= perf_log_min_us:
				print("[PERF VGM] empty bubble: vol=%d  read=%d us  total=%d us" % [
					bubble_volume, t_after_read - t_start, early_total,
				])
		return

	# --- Anchor identification ---
	# Two anchor sources:
	#   1. Solid voxels at the BOTTOM face of the bubble — they're
	#      assumed to be connected to the world floor below. We do
	#      NOT use the top or side faces as anchor sources because
	#      that produces wrong results (a floating pillar at the
	#      bubble's top would be falsely "anchored to whatever's
	#      above"). Bottom-only is the physically-correct local
	#      approximation: gravity pulls down, so support comes from
	#      below.
	#   2. Solid voxels overlapping a NoEditZone — settlements and
	#      lore landmarks never fall.
	#
	# Flood-fill from these anchors through 6-connected solids to find
	# everything that's still supported. Anything left over is loose.
	#
	# Side effect of bottom-only: a structure that's only laterally
	# attached to neighbouring solids OUTSIDE the bubble (e.g. a long
	# horizontal beam jutting in from beyond our scan radius) won't
	# anchor through that lateral connection — it would fall. In
	# practice this is rare because the bubble is centred on a recent
	# edit, and most edits aren't at the end of a long unsupported
	# overhang.
	#
	# NoEditZone perf — naive per-voxel queries would run an
	# intersect_point physics call for every non-bottom solid voxel
	# (potentially thousands). We pre-flight the bubble's world AABB
	# against the registry once: if no zone overlaps the bubble at all,
	# every per-voxel check is provably "not in a zone" and we skip the
	# whole inner check. Per-voxel checks only run when a zone IS in
	# the bubble.
	var bubble_min_world: Vector3 = Vector3(min_v) * VOXEL_SIZE_M
	var bubble_max_world: Vector3 = Vector3(max_v + Vector3i.ONE) * VOXEL_SIZE_M
	var registry := get_node_or_null("/root/NoEditZoneRegistry")
	var bubble_has_zones: bool = false
	if registry != null and registry.has_method("does_aabb_overlap_no_edit_zone"):
		bubble_has_zones = registry.does_aabb_overlap_no_edit_zone(
			bubble_min_world, bubble_max_world
		)

	var anchored: Dictionary = {}  # Vector3i (bubble-local) → true
	var frontier: Array[Vector3i] = []
	for v_pos_v in solids.keys():
		var v: Vector3i = v_pos_v
		# Bottom face only (y == 0 in bubble-local coords means the
		# lowest layer of the bubble).
		if v.y == 0:
			anchored[v] = true
			frontier.append(v)
			continue
		# NoEditZone check — only run if the AABB pre-flight said zones
		# exist in this bubble. Otherwise it's provably empty.
		if bubble_has_zones:
			var v_world_centre_m: Vector3 = (
				Vector3(min_v + v) + Vector3.ONE * 0.5
			) * VOXEL_SIZE_M
			if registry.is_point_inside_no_edit_zone(v_world_centre_m):
				anchored[v] = true
				frontier.append(v)
	if perf_log_enabled:
		t_after_anchor_pre = Time.get_ticks_usec()

	# Flood-fill anchors through the solid set. 6-connected.
	const NEIGHBOURS_6: Array = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	while not frontier.is_empty():
		var cur: Vector3i = frontier.pop_back()
		for n_off in NEIGHBOURS_6:
			var nbr: Vector3i = cur + (n_off as Vector3i)
			if not solids.has(nbr):
				continue
			if anchored.has(nbr):
				continue
			anchored[nbr] = true
			frontier.append(nbr)
	if perf_log_enabled:
		t_after_floodfill = Time.get_ticks_usec()

	# --- Collect unanchored voxels & partition by fall behavior ---
	# LOOSE voxels (sand-style) bypass the rigid-body cluster path
	# entirely — they fall column-by-column instantly. NEVER + SOLID
	# voxels go through the cluster path where they spawn as rigid
	# bodies that tip and tumble.
	#
	# Material-aware partition: read each unanchored voxel's material
	# id from its alpha byte, look up the VoxelMaterial in the
	# registry, and route by fall_behavior. If the registry isn't
	# loaded (shouldn't happen at runtime), fall back to NEVER for
	# everything — current gravity behaviour pre-material-system.
	var unanchored_loose: Dictionary = {}    # bubble-local → packed RGBA (LOOSE)
	var unanchored_pickup: Dictionary = {}   # bubble-local → packed RGBA (PICKUP_DROP)
	var unanchored_cluster: Dictionary = {}  # bubble-local → packed RGBA (NEVER + SOLID)
	var mat_registry := get_node_or_null("/root/VoxelMaterialRegistry")
	for v_pos_v in solids.keys():
		var v: Vector3i = v_pos_v
		if anchored.has(v):
			continue
		var packed: int = solids[v]
		var mat_id: int = packed & 0xFF
		var fall: int = VoxelMaterial.FallBehavior.NEVER
		if mat_registry != null:
			var material: VoxelMaterial = mat_registry.get_by_id(mat_id)
			if material != null:
				fall = material.fall_behavior
		if fall == VoxelMaterial.FallBehavior.LOOSE:
			unanchored_loose[v] = packed
		elif fall == VoxelMaterial.FallBehavior.PICKUP_DROP:
			unanchored_pickup[v] = packed
		else:
			# NEVER and SOLID both go through the rigid-body cluster
			# path. Trees / wood materials use SOLID so a felled limb
			# physically tumbles down; the player can chop the resting
			# log afterwards as fresh terrain voxels.
			unanchored_cluster[v] = packed
	if perf_log_enabled:
		t_after_partition = Time.get_ticks_usec()

	# --- LOOSE column-fall ---
	# Sand model: each loose voxel falls straight down to the first
	# solid (or anchored) cell beneath it. No rigid body, no tumble.
	# Processed BEFORE cluster spawning because we don't want a
	# loose voxel that's part of a structurally-failing cliff to
	# both fall through the cluster path AND the loose path.
	if not unanchored_loose.is_empty():
		_handle_loose_voxels(unanchored_loose, anchored, min_v)
	if perf_log_enabled:
		t_after_loose = Time.get_ticks_usec()

	# --- PICKUP_DROP carve + spawn drops ---
	# Terrain materials (stone, dirt, grass) skip the rigid-body
	# tumble. Each unsupported voxel becomes a single VoxelDrop at
	# its world position — falls under gravity, hovers, auto-collects
	# when the player walks within pickup_radius_m. Better UX than
	# physics-tumbling re-deposits for routine terrain digging.
	if not unanchored_pickup.is_empty():
		_handle_pickup_voxels(unanchored_pickup, min_v)

	if unanchored_cluster.is_empty():
		if perf_log_enabled:
			_perf_log_bubble(
				bubble_volume, solids.size(), 0, 0,
				t_start, t_after_read, t_after_anchor_pre,
				t_after_floodfill, t_after_partition, t_after_loose,
				Time.get_ticks_usec(),
			)
		return

	# Group cluster-bound voxels into connected components.
	var visited: Dictionary = {}
	var clusters: Array[Dictionary] = []
	for v_pos_v in unanchored_cluster.keys():
		# `seed_pos` not `seed` — `seed()` is a GDScript built-in
		# (random-seed setter). Using `seed` as a variable shadows it.
		var seed_pos: Vector3i = v_pos_v
		if visited.has(seed_pos):
			continue
		# BFS one cluster.
		var cluster_voxels: Dictionary = {}
		var queue: Array[Vector3i] = [seed_pos]
		visited[seed_pos] = true
		while not queue.is_empty():
			var cur2: Vector3i = queue.pop_back()
			cluster_voxels[cur2] = unanchored_cluster[cur2]
			for n_off2 in NEIGHBOURS_6:
				var nbr2: Vector3i = cur2 + (n_off2 as Vector3i)
				if not unanchored_cluster.has(nbr2):
					continue
				if visited.has(nbr2):
					continue
				visited[nbr2] = true
				queue.append(nbr2)
		clusters.append(cluster_voxels)

	# --- Spawn a falling cluster per group ---
	for cluster_voxels in clusters:
		_handle_cluster(cluster_voxels, min_v, edit_world_pos, terrain)

	if perf_log_enabled:
		t_after_cluster = Time.get_ticks_usec()
		_perf_log_bubble(
			bubble_volume, solids.size(),
			unanchored_cluster.size(), clusters.size(),
			t_start, t_after_read, t_after_anchor_pre,
			t_after_floodfill, t_after_partition, t_after_loose,
			t_after_cluster,
		)

	# DIAGNOSTIC — always print when a single bubble scan exceeds 30 ms.
	# Helps trace where the explosive-throw freeze is going.
	var t_end: int = Time.get_ticks_usec()
	var total_us: int = t_end - t_start
	if total_us > 30000:
		print("[SPIKE _process_bubble] total=%d us  bubble_vol=%d  solids=%d  cluster_voxels=%d  clusters=%d" % [
			total_us, bubble_volume, solids.size(),
			unanchored_cluster.size(), clusters.size(),
		])


func _perf_log_bubble(
	bubble_vol: int, solid_count: int,
	cluster_voxel_total: int, cluster_count: int,
	t_start: int, t_read: int, t_anchor: int,
	t_flood: int, t_part: int, t_loose: int, t_end: int,
) -> void:
	# Centralised single-line print so the phase columns stay aligned
	# regardless of which return path we took. Filtered by
	# perf_log_min_us — only logs scans worth investigating.
	var total_us: int = t_end - t_start
	if total_us < perf_log_min_us:
		return
	# `_used_bulk_read` is set during the read phase; this caches the
	# decision so the log line can show which path was taken.
	var read_label: String = "bulk" if _last_read_used_bulk else "per-vox"
	print("[PERF VGM] vol=%d solids=%d cluster_vox=%d clusters=%d  " % [
		bubble_vol, solid_count, cluster_voxel_total, cluster_count,
	] + "read[%s]=%d  anchor_pre=%d  flood=%d  part=%d  loose=%d  cluster=%d  TOTAL=%d us (%.2f ms)" % [
		read_label,
		t_read - t_start,
		t_anchor - t_read,
		t_flood - t_anchor,
		t_part - t_flood,
		t_loose - t_part,
		t_end - t_loose,
		total_us,
		total_us / 1000.0,
	])


# =============================================================
# LOOSE COLUMN-FALL — sand-style instant pour, no rigid body
# =============================================================

func _handle_loose_voxels(
	loose_voxels: Dictionary,    # bubble-local Vector3i → packed RGBA
	anchored: Dictionary,         # bubble-local Vector3i → true (the supported set)
	bubble_min_v: Vector3i,       # offset to convert bubble-local → absolute world voxels
) -> void:
	# For each LOOSE voxel: walk straight down through bubble-local
	# space until we hit something supported. Carve the original
	# position; place a copy at the landing position. No physics, no
	# rigid body, no tumble — just instant column-fall.
	#
	# Why we process BOTTOM-UP: a stack of three sand voxels above
	# an anchored block should all stack tightly on top of the
	# anchored block, not all collapse to the same Y. By processing
	# from lowest Y first, each voxel's landing becomes a surface
	# the next-higher voxel can stack on (we record landings in a
	# local set so subsequent walks see the new surface).
	#
	# Anything that would land BELOW the bubble's bottom face is
	# placed at the bottom face. We don't know what's below — by
	# convention "outside the bubble is solid" — so the bottom face
	# is the safest stop. Imperfect for floating islands; fine for
	# normal terrain.

	var loose_landings: Dictionary = {}  # bubble-local Vector3i → true
	var carve_writes: Array = []
	var place_writes: Array = []

	# Sort keys by Y ascending. This processes the bottom of every
	# vertical column first.
	var sorted_keys: Array = loose_voxels.keys()
	sorted_keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y)

	for v_pos_v in sorted_keys:
		var v: Vector3i = v_pos_v
		# Walk down looking for the first supported cell below.
		var landing_y: int = v.y
		while landing_y > 0:
			var below: Vector3i = Vector3i(v.x, landing_y - 1, v.z)
			if anchored.has(below) or loose_landings.has(below):
				break  # land on top of supported / already-landed voxel
			landing_y -= 1
		if landing_y == v.y:
			# No air below — already stable. Don't move.
			continue

		# Carve original position (write 0 = air).
		var orig_world_centre: Vector3 = (
			Vector3(bubble_min_v + v) + Vector3.ONE * 0.5
		) * VOXEL_SIZE_M
		carve_writes.append({"pos": orig_world_centre, "value": 0})

		# Place at landing position (write the original packed RGBA so
		# colour AND material id transfer intact).
		var landing_local: Vector3i = Vector3i(v.x, landing_y, v.z)
		var landing_world_centre: Vector3 = (
			Vector3(bubble_min_v + landing_local) + Vector3.ONE * 0.5
		) * VOXEL_SIZE_M
		place_writes.append({"pos": landing_world_centre, "value": loose_voxels[v]})

		loose_landings[landing_local] = true

	# Submit both batches via the existing bulk write API.
	# Two separate commands so the carve queues before the place —
	# Zylann processes them in order. (One combined command would
	# also work because each voxel is at a distinct world pos, but
	# keeping them separate makes the Output panel logs clearer.)
	if not carve_writes.is_empty():
		VoxelEditManager.queue_set_voxels_bulk(carve_writes, "loose_carve_n%d" % carve_writes.size())
	if not place_writes.is_empty():
		VoxelEditManager.queue_set_voxels_bulk(place_writes, "loose_place_n%d" % place_writes.size())


# =============================================================
# PICKUP_DROP — carve unsupported voxels and spawn pickups
# =============================================================

## Hard cap on VoxelDrops spawned per scan. A single huge collapse
## (carve out the base of a 100-voxel cliff) shouldn't spawn 100
## RigidBody3Ds in flight at once — performance + visual mess. If the
## set exceeds this number, we still carve every voxel (so the world
## state is consistent) but only spawn drops for the first N. The
## rest of the items are silently lost; that's the cost of not having
## a stacking-into-fewer-drops grouping pass yet (could add later).
@export var max_pickup_drops_per_scan: int = 32

## Max VoxelDrop instantiations per physics frame. RigidBody3D + mesh
## + collision-shape construction is expensive; spawning 32 in one
## frame caused a visible freeze on explosive throws (each carve uncovers
## many unsupported voxels at once). Drained from `_pending_drops` at
## this rate so the spike from a big AOE carve smears across multiple
## frames instead of hitching the main thread.
@export var max_drop_spawns_per_frame: int = 4

# Pending drop spawns queued by _handle_pickup_voxels, drained by
# _physics_process at max_drop_spawns_per_frame per tick. Each entry
# is a Dictionary: { "pos": Vector3, "item_id": String, "color": Color,
# "count": int }. The carves themselves still happen synchronously
# (in the bulk write batch) so the world state is consistent
# immediately; only the cosmetic drop spawn is deferred.
var _pending_drops: Array = []


func _handle_pickup_voxels(
	pickup_voxels: Dictionary,    # bubble-local Vector3i → packed RGBA
	bubble_min_v: Vector3i,
) -> void:
	# For each PICKUP_DROP voxel: queue a carve write AND queue a
	# pending drop spawn. The actual VoxelDrop instantiation happens
	# in _physics_process at max_drop_spawns_per_frame per tick — this
	# avoids the multi-RigidBody3D-construction freeze on big AOE
	# carves (explosives, future spells).
	#
	# Drops are parented to the World3D scene root (via the player's
	# parent in _drain_pending_drops) so they outlive the player's
	# own lifetime and stay where they fell.
	var mat_registry := get_node_or_null("/root/VoxelMaterialRegistry")
	if mat_registry == null:
		return
	var carve_writes: Array = []
	var drops_queued: int = 0
	for v_pos_v in pickup_voxels.keys():
		var v: Vector3i = v_pos_v
		var packed: int = pickup_voxels[v]
		var mat_id: int = packed & 0xFF
		var material: VoxelMaterial = mat_registry.get_by_id(mat_id)
		# World-space centre of this voxel cell.
		var world_centre: Vector3 = (
			Vector3(bubble_min_v + v) + Vector3.ONE * 0.5
		) * VOXEL_SIZE_M
		# Always carve the voxel — keeps the world consistent even if
		# we hit the spawn cap below or have no material registered.
		carve_writes.append({"pos": world_centre, "value": 0})
		# Skip the drop spawn when over the cap or when the material
		# has no yield (rare placeholder materials).
		if drops_queued >= max_pickup_drops_per_scan:
			continue
		if material == null or material.yield_item_id == "":
			continue
		_pending_drops.append({
			"pos": world_centre,
			"item_id": material.yield_item_id,
			"color": material.color_low,
			"count": material.yield_quantity,
		})
		drops_queued += 1
	if not carve_writes.is_empty():
		VoxelEditManager.queue_set_voxels_bulk(
			carve_writes, "pickup_carve_n%d" % carve_writes.size()
		)


func _drain_pending_drops() -> void:
	# Spawn at most max_drop_spawns_per_frame VoxelDrops per physics
	# frame from the pending queue. Each spawn = one new RigidBody3D
	# + mesh + collision shape, which is moderately expensive; trickle
	# the work out instead of doing 32 at once.
	if _pending_drops.is_empty():
		return
	var world_root: Node = _find_world_root_for_drops()
	if world_root == null:
		return
	var spawned: int = 0
	while spawned < max_drop_spawns_per_frame and not _pending_drops.is_empty():
		var d: Dictionary = _pending_drops.pop_front()
		var drop: VoxelDrop = VoxelDrop.new()
		drop.setup(d["item_id"], d["color"], int(d["count"]))
		world_root.add_child(drop)
		drop.global_position = d["pos"]
		spawned += 1


func _find_world_root_for_drops() -> Node:
	# VoxelDrops want the World3D scene root as a parent so they
	# outlive the player. The autoload itself doesn't have a direct
	# scene reference, so we walk up from any registered "player"
	# group node. Falls back to current_scene if no player exists.
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var p: Node = players[0]
		if p != null and p.get_parent() != null:
			return p.get_parent()
	return get_tree().current_scene


# =============================================================
# CLUSTER SPAWN
# =============================================================

func _handle_cluster(
	cluster_voxels: Dictionary,
	bubble_min_v: Vector3i,
	edit_world_pos: Vector3,
	terrain: VoxelLodTerrain,
) -> void:
	var n: int = cluster_voxels.size()

	# Too big? Treat as anchored — log and bail.
	if n > max_cluster_voxels:
		print("[VoxelGravityManager] cluster too large (%d > %d), leaving in place" % [
			n, max_cluster_voxels
		])
		return

	# Convert bubble-local Vector3i keys to absolute world voxel-grid
	# Vector3i keys (so the snapshot the cluster carries matches the
	# coordinate system its mesh + re-deposit math expects).
	var absolute_voxels: Dictionary = {}
	for v_pos_v in cluster_voxels.keys():
		var v_local: Vector3i = v_pos_v
		absolute_voxels[bubble_min_v + v_local] = cluster_voxels[v_local]

	# --- Carve from terrain via VoxelEditManager bulk write ---
	# Going through the manager keeps EditedChunkRegistry in sync with
	# the carve, which the LOD render decision and save-flush both
	# depend on. The bulk command emits edit_applied ONCE for the
	# whole batch — a follow-up scan WILL trigger, but it'll find the
	# carved voxels missing and any surviving solids well-anchored
	# (by construction — they were already anchored before the carve),
	# so it's a fast no-op.
	#
	# One-frame visual artefact: the carve queues this frame and
	# applies next frame, while the cluster mesh appears immediately.
	# For ~16 ms both the terrain voxels AND the cluster mesh occupy
	# the same space. Acceptable for our cube aesthetic; revisit if
	# it becomes visible during normal play.
	var carve_writes: Array = []
	for v_world_v in absolute_voxels.keys():
		var v: Vector3i = v_world_v
		var v_world_centre_m: Vector3 = (
			Vector3(v) + Vector3.ONE * 0.5
		) * VOXEL_SIZE_M
		carve_writes.append({
			"pos": v_world_centre_m,
			"value": 0,
		})
	if not VoxelEditManager.queue_set_voxels_bulk(carve_writes, "cluster_carve_n%d" % carve_writes.size()):
		# Queue full — abandon this cluster. The voxels stay where they
		# are; on the next eligible edit they'll be re-evaluated.
		return

	# --- Below-threshold cluster: just carve, don't spawn body ---
	if n < min_cluster_voxels:
		return

	# --- Active-cluster cap: carve but don't spawn ---
	if get_active_cluster_count() >= max_active_clusters:
		print("[VoxelGravityManager] active cluster cap reached, voxels carved without spawn")
		return

	# --- Spawn the rigid body cluster ---
	if _cluster_scene == null:
		return
	var cluster: Node = _cluster_scene.instantiate()
	if cluster == null:
		return

	# Find a parent — prefer the world scene root (sibling to terrain).
	# The terrain's parent is the world Node3D.
	var world_root: Node = terrain.get_parent()
	if world_root == null:
		world_root = get_tree().current_scene
	world_root.add_child(cluster)

	# --- Compute per-cluster gravity_scale and damage_multiplier ---
	# Mixed clusters can contain multiple materials (e.g. a chunk of
	# stone + dirt that detached together). Aggregate the per-material
	# values:
	#   gravity_scale: AVERAGE across constituent voxels — heterogeneous
	#                  rock falls at "rocks-and-dirt" speed, somewhere
	#                  between pure rock and pure dirt.
	#   damage_multiplier: MAX across constituents — the deadliest
	#                      material in the chunk wins, because impact
	#                      damage is dominated by the worst-case
	#                      crushing element.
	var gravity_scale_avg: float = 1.0
	var damage_multiplier_max: float = 1.0
	var mat_registry := get_node_or_null("/root/VoxelMaterialRegistry")
	if mat_registry != null:
		var sum_g: float = 0.0
		var max_d: float = 0.0
		var count: int = 0
		for v_pos_v in absolute_voxels.keys():
			var packed: int = absolute_voxels[v_pos_v]
			var mat_id: int = packed & 0xFF
			var material: VoxelMaterial = mat_registry.get_by_id(mat_id)
			if material != null:
				sum_g += material.gravity_scale
				if material.damage_multiplier > max_d:
					max_d = material.damage_multiplier
				count += 1
		if count > 0:
			gravity_scale_avg = sum_g / float(count)
			damage_multiplier_max = max_d

	# Spawn at the cluster's world centroid.
	var centroid_world: Vector3 = VoxelClusterBuilder.compute_centroid_world(absolute_voxels)
	cluster.global_position = centroid_world
	cluster.configure(absolute_voxels, edit_world_pos, gravity_scale_avg, damage_multiplier_max)

	_active_clusters.append(cluster)
	cluster_spawned.emit(cluster)
	print("[VoxelGravityManager] spawned cluster: %d voxels at %s (active=%d)" % [
		n, centroid_world, _active_clusters.size()
	])
