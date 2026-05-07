extends VoxelViewer
# ForwardLookaheadViewer.gd
#
# Plain English: Zylann's voxel terrain only knows where to stream chunks
# from VoxelViewer nodes — it streams a sphere around each viewer. With one
# viewer parented to the player, that sphere is centred on the player and
# treats every direction the same. So when you sprint forward, chunks
# behind you are loaded just as eagerly as chunks ahead, even though you'll
# never see what's behind you. This script adds a SECOND viewer that floats
# ahead of the player along the camera's forward direction, biased further
# in the direction you're moving when you're moving fast (sprint, horse).
# Zylann unions the two viewers' radii, so the result is "load priority
# along where I'm looking and going" without breaking the omnidirectional
# safety bubble of the main viewer.
#
# The main viewer (VoxelViewer in Player3D.tscn at view_distance=8000) keeps
# the full 1.33 km bubble. This lookahead viewer runs at a SHORTER radius
# (default 4000 vox = ~667 m) so we don't double the streaming load — we're
# just shifting some of the streaming budget along the heading.
#
# Spawned at runtime by CopperIslesTestBootstrap.gd._ready as a child of
# the Player3D node.

# How far ahead of the player to sit when standing still and looking around.
@export var base_offset: float = 60.0

# Lookahead seconds: actual offset = base_offset + speed * lookahead_seconds.
# At walk speed (~5 m/s) this adds ~12 m. At horse speed (~12 m/s) ~30 m.
@export var lookahead_seconds: float = 2.5

# Hard cap so the viewer never gets crazy far from the player.
@export var max_offset: float = 200.0

# Reference walking speed used to scale "velocity weight" — how much of the
# blended forward vector comes from velocity vs camera forward. At
# walk_speed_ref the velocity term equals the camera term; at sprint it
# dominates.
@export var walk_speed_ref: float = 5.0

# How fast the viewer's position chases its target each frame. Higher =
# snappier (whiplashes on rapid camera turns). Lower = smoother (lags
# behind). 6.0 feels good — converges in ~0.3 s.
@export var position_lerp: float = 6.0

# Seconds of "no input" (no movement, no camera rotation) before we shrink
# the offset toward 0 and converge on the omnidirectional viewer behaviour.
@export var idle_timeout: float = 2.0

# Internal state.
var _player: Node3D = null
var _camera_rig: Node = null
var _idle_seconds: float = 0.0
var _last_camera_basis: Basis = Basis()


func _ready() -> void:
	# Default Zylann config — safe to override in the inspector or from
	# the spawning script.
	if view_distance == 0:
		view_distance = 4000  # ~667 m at 6 vox/m
	_resolve_player_and_camera()


func _resolve_player_and_camera() -> void:
	# Player is in the "player" group (Player3D._ready adds itself).
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	# CameraRig sits on the SpringArm3D under CameraTarget — the script
	# is what we want, not the node type. Walk the player's children.
	for child in _player.get_children():
		if child.name == "CameraTarget":
			var arm: Node = child.get_node_or_null("SpringArm3D")
			if arm != null and arm.get_script() != null:
				_camera_rig = arm
				return


func _physics_process(delta: float) -> void:
	# Lazy resolve in case the player spawned after us.
	if _player == null or _camera_rig == null:
		_resolve_player_and_camera()
		if _player == null:
			return

	# Camera forward unit vector. Falls back to player's forward if the
	# rig helper isn't there.
	var fwd_cam: Vector3 = Vector3.FORWARD
	if _camera_rig != null and _camera_rig.has_method("get_camera_forward_unit"):
		fwd_cam = _camera_rig.call("get_camera_forward_unit")

	# Player horizontal velocity. We ignore the Y component because
	# voxel chunks are roughly cubic and vertical motion (jumping,
	# falling) shouldn't bias horizontal streaming.
	var v: Vector3 = Vector3.ZERO
	if "velocity" in _player:
		v = _player.velocity
	var v_horiz: Vector3 = Vector3(v.x, 0.0, v.z)
	var speed: float = v_horiz.length()

	# Blend camera forward with velocity direction. When standing still,
	# vel_w = 0 so the lookahead is purely along the camera. At
	# walk_speed_ref, vel_w = 1 (equal weight). Sprinting/riding
	# (>walk_speed_ref) tips the blend toward motion direction.
	var vel_w: float = clampf(speed / walk_speed_ref, 0.0, 2.0)
	var fwd: Vector3 = fwd_cam
	if speed > 0.5:
		fwd = (fwd_cam + v_horiz.normalized() * vel_w).normalized()

	# Distance to push the viewer ahead. Speed-aware so faster motion
	# pre-loads more aggressively. Capped to max_offset.
	var off: float = clampf(base_offset + speed * lookahead_seconds, 0.0, max_offset)

	# Idle damping: when neither moving nor rotating, shrink offset to 0
	# so we collapse to the omnidirectional viewer (no wasted streaming).
	var camera_moved: bool = false
	if _camera_rig != null and "global_transform" in _camera_rig:
		var b: Basis = _camera_rig.global_transform.basis
		if not b.is_equal_approx(_last_camera_basis):
			camera_moved = true
		_last_camera_basis = b
	if speed < 0.5 and not camera_moved:
		_idle_seconds += delta
	else:
		_idle_seconds = 0.0
	if _idle_seconds > idle_timeout:
		off = lerpf(off, 0.0, clampf((_idle_seconds - idle_timeout) * 0.5, 0.0, 1.0))

	# Damped chase to the target world position.
	var target: Vector3 = _player.global_position + fwd * off
	global_position = global_position.lerp(target, clampf(position_lerp * delta, 0.0, 1.0))
