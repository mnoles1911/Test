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

@export var analysis_padding_m: float = 8.0
# Distance (meters) the analysis bubble extends past the edit centre
# on each axis. Anything past this radius is treated as anchored — a
# long arch whose support is removed > 8 m away will not fall. Bounded
# cost and matches the Minecraft model.
#
# Perf budget: 8 m * 2 = 16 m per side, * 6 vox/m = 96 voxels per side,
# 96^3 ≈ 880K voxel reads worst case. With one scan per physics frame
# (max_scans_per_frame=1) and most edits small, in practice scans
# touch a small fraction of the bubble. If perf becomes a problem,
# either reduce this further or implement multi-frame scanning.

@export var max_analysis_side_m: float = 16.0
# Hard cap on the bubble's side length. Even very large blasts won't
# scan more than this. 16 m at 6 vox/m = 96 voxels per side. Larger
# than this exceeds the per-frame budget noticeably.

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
	if _scan_queue.is_empty():
		return
	# Process at most max_scans_per_frame bubbles.
	var processed: int = 0
	while not _scan_queue.is_empty() and processed < max_scans_per_frame:
		var bubble: Dictionary = _scan_queue.pop_front()
		_process_bubble(bubble["world_pos"])
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

func _on_edit_applied(world_pos: Vector3, chunk_coords: Vector3i) -> void:
	if not enabled:
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
		print("[VoxelGravityManager] scan queue full, dropping bubble at %s" % dropped["world_pos"])
	_scan_queue.append({
		"world_pos": world_pos,
		"chunk": chunk_coords,
	})


# =============================================================
# CORE — process one analysis bubble
# =============================================================

func _process_bubble(edit_world_pos: Vector3) -> void:
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
	tool.channel = VoxelBuffer.CHANNEL_COLOR

	# --- Define the analysis box in voxel-grid space ---
	# Half-side capped at max_analysis_side_m / 2.
	var half_side_m: float = minf(analysis_padding_m, max_analysis_side_m * 0.5)
	var half_side_vox: int = int(ceili(half_side_m * VOXELS_PER_METER))
	# Centre voxel.
	var centre_v: Vector3i = VoxelEditManager.world_to_voxel(edit_world_pos)
	var min_v: Vector3i = centre_v - Vector3i.ONE * half_side_vox
	var max_v: Vector3i = centre_v + Vector3i.ONE * half_side_vox
	var side: int = (max_v.x - min_v.x) + 1

	# --- Read the bubble into a flat dictionary ---
	# Keys: Vector3i (relative to min_v, so 0..side-1 on each axis).
	# Values: int (packed RGBA). Air voxels (alpha=0) are NOT inserted;
	# absence-from-dict means air. This keeps memory proportional to
	# solid-voxel count, not bubble volume.
	var solids: Dictionary = {}
	for x in range(side):
		for y in range(side):
			for z in range(side):
				var v_world_grid: Vector3i = min_v + Vector3i(x, y, z)
				var packed: int = tool.get_voxel(v_world_grid)
				# Alpha=0 means air for VoxelMesherCubes (CHANNEL_COLOR
				# encoding). Lowest byte = alpha.
				if (packed & 0xFF) == 0:
					continue
				solids[Vector3i(x, y, z)] = packed

	if solids.is_empty():
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
		# NoEditZone check — convert bubble-local back to world meters.
		var v_world_centre_m: Vector3 = (
			Vector3(min_v + v) + Vector3.ONE * 0.5
		) * VOXEL_SIZE_M
		var registry := get_node_or_null("/root/NoEditZoneRegistry")
		if registry != null and registry.is_point_inside_no_edit_zone(v_world_centre_m):
			anchored[v] = true
			frontier.append(v)

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

	# --- Collect unanchored voxels & flood-fill into clusters ---
	var unanchored: Dictionary = {}  # bubble-local → packed RGBA
	for v_pos_v in solids.keys():
		var v: Vector3i = v_pos_v
		if not anchored.has(v):
			unanchored[v] = solids[v]

	if unanchored.is_empty():
		return

	# Group unanchored voxels into connected components.
	var visited: Dictionary = {}
	var clusters: Array[Dictionary] = []
	for v_pos_v in unanchored.keys():
		var seed: Vector3i = v_pos_v
		if visited.has(seed):
			continue
		# BFS one cluster.
		var cluster_voxels: Dictionary = {}
		var queue: Array[Vector3i] = [seed]
		visited[seed] = true
		while not queue.is_empty():
			var cur2: Vector3i = queue.pop_back()
			cluster_voxels[cur2] = unanchored[cur2]
			for n_off2 in NEIGHBOURS_6:
				var nbr2: Vector3i = cur2 + (n_off2 as Vector3i)
				if not unanchored.has(nbr2):
					continue
				if visited.has(nbr2):
					continue
				visited[nbr2] = true
				queue.append(nbr2)
		clusters.append(cluster_voxels)

	# --- Spawn a falling cluster per group ---
	for cluster_voxels in clusters:
		_handle_cluster(cluster_voxels, min_v, edit_world_pos, terrain)


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

	# Spawn at the cluster's world centroid.
	var centroid_world: Vector3 = VoxelClusterBuilder.compute_centroid_world(absolute_voxels)
	cluster.global_position = centroid_world
	cluster.configure(absolute_voxels, edit_world_pos)

	_active_clusters.append(cluster)
	cluster_spawned.emit(cluster)
	print("[VoxelGravityManager] spawned cluster: %d voxels at %s (active=%d)" % [
		n, centroid_world, _active_clusters.size()
	])
