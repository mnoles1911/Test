extends Node3D
class_name PrefetchViewer

# PrefetchViewer — multi-viewer streaming train (refactored 2026-05-26).
#
# Spawns N inner VoxelViewers spaced along the player's motion direction
# so their LOD0 rings overlap into a CONTIGUOUS LOD0 CORRIDOR ahead of
# the player. The single-viewer version of this script created a single
# LOD0 sphere ~110 m ahead — which left a 21-90 m LOD1/2 gap that the
# player ran through, watching the cascade upgrade. The N-viewer version
# stitches that gap shut.
#
# How it differs from Player3D._update_viewer_lookahead:
#   * That system shifts the PRIMARY VoxelViewer's center forward,
#     producing a lopsided main streaming sphere (same volume, biased
#     to motion). When player turns 180° the backward chunks have to
#     re-stream.
#   * THIS system adds N SECONDARY viewers parked AHEAD of the player.
#     Total streaming volume goes up — every viewer's sphere is tracked —
#     but the chunks BEHIND the player stay loaded (the main viewer
#     covers them), and the N-deep ring up front guarantees that the
#     player's forward 0-to-lookahead corridor is all at LOD0 priority,
#     not at the LOD pyramid's distance-binned levels.
#
# Geometry at sprint (8.5 m/s, default settings N=3, lookahead=90m):
#   Main VoxelViewer LOD0 ring: 0-21 m around player
#   Inner viewer 1 (at +30 m):  LOD0 ring 9-51 m ahead
#   Inner viewer 2 (at +60 m):  LOD0 ring 39-81 m ahead
#   Inner viewer 3 (at +90 m):  LOD0 ring 69-111 m ahead
#   → Combined LOD0 corridor:   0-111 m straight ahead at full detail
#
# Spacing is lookahead/N; with N=3 and 90 m lookahead → 30 m spacing.
# Each LOD0 ring is 42 m diameter (Zylann's lod_distance hard-cap),
# so spacing < diameter ensures contiguity (no LOD1 gap between rings).
#
# Cost: ~3x prefetch streaming load vs single-viewer. Spread along a
# forward CONE, not 360°. Idle player → all viewers collapse to vd=0
# (existing zero-cost-when-stationary behavior).
#
# Attach as a CHILD of Player3D. The script auto-creates its inner
# viewers on _ready (no .tscn config required) so adding/configuring
# this is a single Inspector edit.

# --- Tunables (override per scene if needed) ---

## Number of inner VoxelViewers stacked along motion direction. Default
## 3 gives a contiguous LOD0 corridor 0 → ~111 m ahead at sprint with
## the default lookahead settings. Set to 1 for single-viewer mode
## (legacy behavior — equivalent to the pre-2026-05-26 PrefetchViewer).
## 2 thins coverage but halves prefetch chunk count. 4-5 widens the
## corridor at proportionally higher cost.
@export_range(1, 8, 1) var inner_viewer_count: int = 3

## View distance (voxels) per inner viewer. Sized to cover the 21 m
## LOD0 ring + a small buffer (24 m = 144 vox). Each inner viewer's
## job is purely to anchor a LOD0 ring at its position — view_distance
## past 21 m just streams LOD1/2 chunks unnecessarily. Keep tight.
## Bump up only if you want the prefetch viewers to ALSO contribute
## to the broader LOD pyramid past their own LOD0 rings.
@export_range(64, 1024, 16) var inner_viewer_view_distance_vox: int = 144

## Distance ahead of player (m) at idle/walk transition speed.
## Determines where the FARTHEST inner viewer sits (the others sit at
## proportional fractions of this — see _update_inner).
@export_range(0.0, 200.0, 1.0) var walk_lookahead_m: float = 45.0

## Distance ahead of player (m) at sprint speed. Combined with
## inner_viewer_count=3 and default per-viewer vd=144 vox, this builds
## a LOD0 corridor reaching 0 → ~111 m ahead at sprint.
@export_range(0.0, 400.0, 1.0) var sprint_lookahead_m: float = 90.0

## Hard cap on lookahead distance (m). Prevents fly-mode from pushing
## the train past sensible reach.
@export_range(0.0, 800.0, 1.0) var max_lookahead_m: float = 150.0

## Speed threshold below which the entire train collapses to player
## position with vd=0 (every viewer disabled). Costs nothing while
## the player is standing still.
@export_range(0.0, 5.0, 0.1) var min_active_speed_mps: float = 0.5

## Reference walk speed for the lookahead interpolation.
## Matches Player3D.BASE_WALK_SPEED.
@export_range(1.0, 20.0, 0.5) var walk_speed_mps: float = 4.5

## Reference sprint speed for the lookahead interpolation.
## Tightened 2026-05-26 from 8.5 -> 7.0 m/s: actual in-game max
## horizontal speed is 8.2 m/s (terrain friction never lets the
## player hit nominal BASE_SPRINT_SPEED). Anchoring at 7.0 lets the
## train reach its full sprint config at the speed the player actually
## sustains.
@export_range(1.0, 30.0, 0.5) var sprint_speed_mps: float = 7.0

## Master toggle. Set false to disable the train entirely without
## removing the node (for A/B comparing with/without).
@export var enabled: bool = true


var _player: CharacterBody3D = null     # cached parent
var _viewers: Array = []                # Array[Node] of inner VoxelViewer instances
var _initial_log_done: bool = false


func _ready() -> void:
	# Walk up the tree for a CharacterBody3D parent. If we can't find
	# one we're being used in a test harness — log and disable, don't
	# crash.
	var p: Node = get_parent()
	while p != null and not (p is CharacterBody3D):
		p = p.get_parent()
	if p == null:
		push_warning("[PrefetchViewer] no CharacterBody3D ancestor found; disabling.")
		enabled = false
		return
	_player = p

	# Spawn N inner VoxelViewers. They attach as our own children rather
	# than siblings of the main viewer so their global_position can be
	# driven by this script's per-frame loop. The actual VoxelLodTerrain
	# discovers viewers anywhere in the tree by class.
	if not ClassDB.class_exists("VoxelViewer"):
		push_warning("[PrefetchViewer] VoxelViewer class missing — Zylann plugin not loaded?")
		enabled = false
		return
	for i in inner_viewer_count:
		var v: Node = ClassDB.instantiate("VoxelViewer")
		if v == null:
			push_warning("[PrefetchViewer] could not instantiate VoxelViewer #%d; disabling." % i)
			enabled = false
			return
		# Start with view_distance=0 so we don't load chunks before the
		# first _physics_process gets a chance to position the train.
		if "view_distance" in v:
			v.view_distance = 0
		add_child(v)
		_viewers.append(v)


func _physics_process(_delta: float) -> void:
	# Profiler-instrumented so the new steady-state cost is visible in
	# the F3 overlay. Sits under PHYS because it tracks player motion.
	var _t0: int = Time.get_ticks_usec()
	_update_inner()
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("PHYS", "PrefetchViewer", Time.get_ticks_usec() - _t0)


func _update_inner() -> void:
	if not enabled or _player == null or _viewers.is_empty():
		return

	# Horizontal velocity only — gravity/jump shouldn't yank the
	# train up and down on every jump frame.
	var vel: Vector3 = _player.velocity
	var horiz: Vector3 = Vector3(vel.x, 0.0, vel.z)
	var speed: float = horiz.length()
	var player_pos: Vector3 = _player.global_position

	# Below the active threshold: collapse every inner viewer to player
	# pos with vd=0. Zylann unloads the train's contribution and the
	# main viewer continues alone — train costs nothing at rest.
	if speed < min_active_speed_mps:
		for v in _viewers:
			v.global_position = player_pos
			if "view_distance" in v:
				v.view_distance = 0
		return

	# Compute the corridor's far end (where the LAST inner viewer sits).
	# Inner viewers space evenly between the player and this point.
	var lookahead_m: float = _interp_speed_to(walk_lookahead_m, sprint_lookahead_m, speed)
	lookahead_m = clampf(lookahead_m, 0.0, max_lookahead_m)
	var dir: Vector3 = horiz.normalized()

	# Position each inner viewer at lookahead_m * (i+1) / N along motion.
	# i=0 → closest to player, i=N-1 → at far end (lookahead_m).
	var n: int = _viewers.size()
	for i in n:
		var fraction: float = float(i + 1) / float(n)
		var v_pos: Vector3 = player_pos + dir * (lookahead_m * fraction)
		var v = _viewers[i]
		v.global_position = v_pos
		if "view_distance" in v:
			v.view_distance = inner_viewer_view_distance_vox

	# One-time log so the developer can confirm the train is active on
	# first movement (and what config it picked).
	if not _initial_log_done:
		_initial_log_done = true
		print("[PrefetchViewer] active — speed=%.1f m/s  count=%d  lookahead=%.1f m  per-viewer vd=%d vox" % [
			speed, n, lookahead_m, inner_viewer_view_distance_vox,
		])


func _interp_speed_to(at_walk: float, at_sprint: float, speed: float) -> float:
	# Linear scale: at walk_speed_mps return at_walk; at sprint_speed_mps
	# return at_sprint; extrapolate linearly beyond sprint. Below
	# walk_speed_mps the caller already filtered via min_active_speed_mps.
	var t: float = 0.0
	if sprint_speed_mps > walk_speed_mps:
		t = (speed - walk_speed_mps) / (sprint_speed_mps - walk_speed_mps)
	# Allow extrapolation beyond sprint (no upper clamp here — caller
	# clamps lookahead_m to its max value).
	return at_walk + (at_sprint - at_walk) * t
