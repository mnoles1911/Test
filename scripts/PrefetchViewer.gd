extends Node3D
class_name PrefetchViewer

# PrefetchViewer — secondary, velocity-scaled VoxelViewer that loads
# chunks AHEAD of where the player is moving, so they're already in
# memory by the time the main viewer's sphere reaches them.
#
# How it differs from Player3D._update_viewer_lookahead:
#   * That system shifts the PRIMARY VoxelViewer's center forward,
#     producing a lopsided streaming sphere (same total volume, biased
#     toward direction of travel). When the player turns 180° the
#     backward chunks have to re-stream.
#   * THIS system adds a SECOND VoxelViewer node parked ahead of the
#     player. Total streaming volume goes up — both viewers' spheres
#     are tracked — but the chunks behind the player remain loaded.
#     Trade-off: more steady-state main-thread detect cost, less
#     spike cost when crossing chunk boundaries.
#
# Velocity scaling (matches Player3D's BASE_WALK_SPEED / BASE_SPRINT_SPEED):
#   idle  (0   m/s): viewer collapses to player pos, view_distance=0
#                    (effectively disabled — costs nothing)
#   walk  (~4.5 m/s): viewer at +30 m ahead, view_distance = 192 vox = 32 m
#   sprint(~8.5 m/s): viewer at +60 m ahead, view_distance = 256 vox = 43 m
#   fly   (~45 m/s):  clamped — +90 m ahead, view_distance = 384 vox = 64 m
#
# Reaches (lookahead + view_distance) extend BEYOND the main viewer's
# 512-vox (85 m) range only at sprint+. At walk pace the prefetch
# overlaps the main viewer mostly, providing earlier load for the
# transition zone where chunks are about to leave-then-rejoin LOD0.
#
# Attach as a CHILD of Player3D. The script auto-creates its
# VoxelViewer child on _ready (no .tscn config required) so adding
# this to a scene is a single "Add Child Node" operation.

# --- Tunables (override per scene if needed) ---

## Distance ahead of player (m) at idle/walk transition speed.
## Bumped 2026-05-26 from 30 → 45 m: the viewer-direction fix (a76d3ae)
## means the prefetch sphere is now genuinely in the player's path, so
## a deeper lookahead pulls real value instead of partly aiming sideways.
@export_range(0.0, 200.0, 1.0) var walk_lookahead_m: float = 45.0

## Distance ahead of player (m) at sprint speed.
## Bumped 2026-05-26 from 60 → 90 m. Sprint anchor is 8.5 m/s; a 90 m
## lookahead is roughly "where the player will be in 10 s." Combined
## with the new larger view_distance below, chunks at the 10 s horizon
## get LOD0 priority before the player closes on them.
@export_range(0.0, 400.0, 1.0) var sprint_lookahead_m: float = 90.0

## Hard cap on lookahead distance (m). Prevents fly-mode from pushing
## the prefetch viewer past sensible reach into uncached territory we
## won't actually visit.
## Bumped 2026-05-26 from 90 → 150 m. Headroom for fly mode now that
## the terrain-level cap is 120 m; prefetch can park ahead of the main
## viewer's sphere instead of inside it.
@export_range(0.0, 800.0, 1.0) var max_lookahead_m: float = 150.0

## View distance (voxels) at walk pace. Higher = larger streaming sphere
## around the prefetch viewer = more chunks loaded but better coverage.
## Bumped 2026-05-26 from 192 → 320 vox (~32 → 53 m). The wasted-streaming
## half of the bug (viewer pointing wrong direction) is gone, so the
## prefetch sphere does ~2× the useful work for the same chunk count.
@export_range(0, 1024, 16) var walk_view_distance_vox: int = 320

## View distance (voxels) at sprint pace.
## Bumped 2026-05-26 from 256 → 480 vox (~43 → 80 m).
@export_range(0, 1024, 16) var sprint_view_distance_vox: int = 480

## View distance (voxels) at the lookahead cap (fly mode). Larger
## prefetch sphere since the player is moving very fast.
## Bumped 2026-05-26 from 384 → 600 vox (~64 → 100 m).
@export_range(0, 1024, 16) var max_view_distance_vox: int = 600

## Speed threshold below which the prefetch is disabled (viewer
## collapses to player pos and view_distance is set to 0). Stops the
## prefetch from costing anything during idle/standing.
@export_range(0.0, 5.0, 0.1) var min_active_speed_mps: float = 0.5

## Reference walk speed for the lookahead/view-distance interpolation.
## Matches Player3D.BASE_WALK_SPEED.
@export_range(1.0, 20.0, 0.5) var walk_speed_mps: float = 4.5

## Reference sprint speed for the lookahead/view-distance interpolation.
## Matches Player3D.BASE_SPRINT_SPEED.
@export_range(1.0, 30.0, 0.5) var sprint_speed_mps: float = 8.5

## Master toggle. Set false to disable the prefetch viewer entirely
## without removing the node (for A/B comparing with/without).
@export var enabled: bool = true


var _player: CharacterBody3D = null     # cached parent
var _viewer: Node = null                # the inner VoxelViewer instance
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

	# Create the inner VoxelViewer. We attach it as our own child rather
	# than a sibling of the main viewer so its global_position can be
	# driven by this script's own transform. The actual VoxelLodTerrain
	# discovers viewers anywhere in the tree by class.
	if not ClassDB.class_exists("VoxelViewer"):
		push_warning("[PrefetchViewer] VoxelViewer class missing — Zylann plugin not loaded?")
		enabled = false
		return
	_viewer = ClassDB.instantiate("VoxelViewer")
	if _viewer == null:
		push_warning("[PrefetchViewer] could not instantiate VoxelViewer; disabling.")
		enabled = false
		return
	# Start with view_distance=0 so we don't load chunks before the
	# first _physics_process gets a chance to scale us.
	if "view_distance" in _viewer:
		_viewer.view_distance = 0
	add_child(_viewer)


func _physics_process(_delta: float) -> void:
	# Profiler-instrumented so the new steady-state cost is visible in
	# the F3 overlay. Sits under PHYS because it tracks player motion.
	var _t0: int = Time.get_ticks_usec()
	_update_inner()
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("PHYS", "PrefetchViewer", Time.get_ticks_usec() - _t0)


func _update_inner() -> void:
	if not enabled or _player == null or _viewer == null:
		return

	# Horizontal velocity only — gravity/jump shouldn't yank the
	# prefetch sphere up and down on every jump frame.
	var vel: Vector3 = _player.velocity
	var horiz: Vector3 = Vector3(vel.x, 0.0, vel.z)
	var speed: float = horiz.length()

	# Below the active threshold: collapse to player pos with zero
	# view_distance. Zylann will unload the prefetch's contribution
	# and the main viewer continues alone, so the system costs nothing
	# while the player is standing still.
	if speed < min_active_speed_mps:
		global_position = _player.global_position
		if "view_distance" in _viewer:
			_viewer.view_distance = 0
		return

	# Lookahead distance interpolated between walk and sprint anchors,
	# extrapolated past sprint up to max_lookahead_m. Same approach for
	# view_distance.
	var lookahead_m: float = _interp_speed_to(walk_lookahead_m, sprint_lookahead_m, speed)
	lookahead_m = clampf(lookahead_m, 0.0, max_lookahead_m)

	var view_vox: float = _interp_speed_to(
			float(walk_view_distance_vox),
			float(sprint_view_distance_vox),
			speed)
	view_vox = clampf(view_vox, 0.0, float(max_view_distance_vox))

	var dir: Vector3 = horiz.normalized()
	global_position = _player.global_position + dir * lookahead_m
	if "view_distance" in _viewer:
		_viewer.view_distance = int(view_vox)

	# One-time log so the developer can confirm the prefetch is active
	# on first movement (and what config it picked).
	if not _initial_log_done:
		_initial_log_done = true
		print("[PrefetchViewer] active — speed=%.1f m/s  lookahead=%.1f m  view_distance=%d vox" % [
			speed, lookahead_m, int(view_vox),
		])


func _interp_speed_to(at_walk: float, at_sprint: float, speed: float) -> float:
	# Linear scale: at walk_speed_mps return at_walk; at sprint_speed_mps
	# return at_sprint; extrapolate linearly beyond sprint. Below
	# walk_speed_mps the caller already filtered via min_active_speed_mps.
	var t: float = 0.0
	if sprint_speed_mps > walk_speed_mps:
		t = (speed - walk_speed_mps) / (sprint_speed_mps - walk_speed_mps)
	# Allow extrapolation beyond sprint (no upper clamp here — caller
	# clamps lookahead_m / view_distance to their max values).
	return at_walk + (at_sprint - at_walk) * t
