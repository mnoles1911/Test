extends SpringArm3D
# CameraRig — Third-person over-shoulder follow camera.
#
# Scene hierarchy this script expects:
#
#   Player3D (CharacterBody3D)    ← _player reference points here
#   └── CameraTarget (Node3D)
#       └── SpringArm3D           ← THIS SCRIPT lives here
#           └── Camera3D
#
# TWO CAMERA MODES:
#
#   STANDARD (default, 98% of play):
#     Mouse horizontal → rotates the Player3D body so Roland turns to face
#     wherever you look. Camera stays centered behind the player.
#     Mouse vertical   → tilts the camera arm up/down only.
#     Result: wherever you look is where Roland faces and where W moves you.
#
#   FREELOOK (hold F2):
#     Mouse horizontal → orbits the camera around the player WITHOUT
#     rotating the player body. Roland keeps facing his current direction.
#     On F2 release → camera smoothly re-centers (yaw AND pitch both restore).
#     Moving the mouse while re-centering cancels pitch restoration so you
#     keep manual control if you deliberately move.
#
# SCROLL WHEEL ZOOM:
#     Mouse scroll up/down zooms in/out (arm length 2m–10m).
#     Works in both standard and freelook modes.
#     NOTE: scroll is an InputEventMouseButton, NOT InputEventMouseMotion.
#     The scroll check must run BEFORE the "not MouseMotion → return" guard.
#     If the guard ran first, scroll events would be silently dropped.
#
# MOVEMENT NOTE:
#   Player3D.gd multiplies input by the player body's transform.basis so
#   movement is always relative to where Roland (and the camera) faces.


@export var arm_length: float = 5.0
# How far the camera sits from Roland when unobstructed. SpringArm3D
# shortens this automatically in caves, doorways, and tight corridors.

@export var zoom_min: float = 2.0
# Closest the player can scroll in (meters). Prevents clipping into Roland.

@export var zoom_max: float = 10.0
# Furthest the player can scroll out (meters).

@export var zoom_speed: float = 0.5
# How much arm_length changes per scroll tick.

@export var elevation_degrees: float = 15.0
# Starting vertical tilt of the arm above horizontal. Player can adjust
# within vertical_min/max below.

@export var horizontal_sensitivity: float = 0.15
# Camera speed for mouse left/right. Raise if rotation feels sluggish.

@export var vertical_sensitivity: float = 0.10
# Camera speed for mouse up/down. Slightly lower than horizontal is natural.

@export var vertical_min_degrees: float = -80.0
# Lowest the player can tilt the camera (negative = looking down).
# -80° puts the aim almost straight down — Roland can mine voxels
# at his feet, dig pits directly under him, etc. Anything close to
# -90° looks weird because the camera arm starts clipping into the
# ground; -80° is the practical limit before that becomes ugly.

@export var vertical_max_degrees: float = 70.0
# Highest the player can tilt the camera (looking up).
# 70° lets Roland aim at overhead voxels (tunnel ceilings,
# overhanging cliffs) without flipping the camera over the top.

@export var key_rotation_speed: float = 90.0
# Degrees per second when using arrow keys to rotate the camera.

@export var dialogue_arm_length: float = 3.5
# Arm length tweened to when a Dialogic conversation opens.

@export var dialogue_tween_duration: float = 0.3
# Seconds for the dialogue arm length tween.

@export var lock_on_lerp_speed: float = 5.0
# How fast the camera swings to frame a lock-on target.

@export var lock_on_horizontal_offset: float = 0.3
# Radians to offset left so the target appears in the right frame half.

@export var first_person_mesh_path: NodePath = NodePath("../../Visual")
# Relative path from this SpringArm3D to Roland's visual mesh
# (the green-box placeholder in Player3D.tscn). Hidden when in
# first-person so the camera doesn't sit inside Roland's torso.
# Default path resolves to: SpringArm3D → CameraTarget → Player3D → Visual.
# If the scene is reorganized, retarget this in the inspector.


# --- Internal state ---

var _first_person: bool = false
# True when the camera is in first-person mode (F3 toggle).
# In first-person:
#   * spring_length is forced to 0 (camera sits at SpringArm3D origin =
#     CameraTarget = Y 1.5 m on the player body, ≈ chest/neck height)
#   * Roland's visual mesh is hidden so we don't see his back through
#     the camera
#   * scroll-wheel zoom is suppressed (would make no sense at length 0)
#
# Pitch + yaw behaviour stays identical to standard third-person:
# mouse-X rotates the player body, mouse-Y tilts the arm. That means
# moving forward (W) in first-person walks you toward where you're
# looking — the same camera-relative movement contract.

var _arm_length_before_fp: float = 0.0
# Spring length saved when entering first-person, restored on exit.
# Captured separately from arm_length (the @export default) because
# the player may have scrolled in/out before pressing F3.

var _pitch: float = 0.0
# Vertical tilt in radians. Applied to self.rotation.x each frame.

var _yaw_offset: float = 0.0
# Horizontal arm offset from the player body in radians.
# Standard mode: always 0 (camera centered behind Roland).
# Freelook mode: drifts freely as the mouse moves.

var _freelook: bool = false
# True while the freelook_camera action (F2) is held.

var _recentering: bool = false
# True while the camera is lerping back to its pre-freelook position after
# F2 is released. Any mouse movement during re-centering cancels pitch
# restoration and lets the player take manual control immediately.

var _pitch_before_freelook: float = 0.0
# Pitch value saved when F2 is first pressed. Restored on F2 release.

var _in_dialogue: bool = false
var _lock_on_target: Node3D

var _player: CharacterBody3D
# Reference to the CharacterBody3D (grandparent node). Used to rotate
# the player body in standard mode so Roland faces where the camera looks.


func _ready() -> void:
	spring_length = arm_length
	_pitch = -deg_to_rad(elevation_degrees)

	# Walk up the hierarchy: SpringArm3D → CameraTarget → Player3D
	_player = get_parent().get_parent() as CharacterBody3D

	# Capture the mouse cursor so all motion feeds the camera during play.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Default to first-person view on game start. The player can toggle
	# back to standard third-person with F3 at any time. Deferred one
	# frame so the player body's children (Visual mesh) are fully ready
	# before _set_first_person tries to find and hide the mesh.
	call_deferred("_set_first_person", true)


func _input(event: InputEvent) -> void:
	# _input fires for every input event regardless of whether another node
	# already handled it. This is correct for camera rotation — we always
	# want to respond to mouse motion during gameplay.
	if _in_dialogue:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	# --- Scroll wheel zoom ---
	# IMPORTANT: this check must come BEFORE the "not MouseMotion → return"
	# guard below. InputEventMouseButton (scroll) is a separate class from
	# InputEventMouseMotion. If the guard ran first, scroll would never reach
	# this block and zoom would silently do nothing.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# In first-person mode the spring length is forced to 0 — scroll
		# would either be a no-op (clamped) or push us back to third-
		# person behaviour while the flag still says first-person. Just
		# ignore wheel input until the player toggles back out (F3).
		if _first_person:
			return
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				arm_length = clamp(arm_length - zoom_speed, zoom_min, zoom_max)
				spring_length = arm_length
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				arm_length = clamp(arm_length + zoom_speed, zoom_min, zoom_max)
				spring_length = arm_length
				get_viewport().set_input_as_handled()
		return  # Don't fall through to mouse motion handling.

	# --- Mouse motion ---
	if not (event is InputEventMouseMotion):
		return

	# Any deliberate mouse move cancels pitch re-centering so the player
	# immediately takes control. Yaw re-centering is unaffected — it always
	# returns to 0 in standard mode regardless.
	_recentering = false

	var motion := event as InputEventMouseMotion

	if _freelook:
		# Freelook: orbit the camera arm without rotating the player body.
		_yaw_offset -= motion.relative.x * horizontal_sensitivity * 0.01
	else:
		# Standard: rotate the player body so Roland faces where the camera looks.
		if _player:
			_player.rotation.y -= motion.relative.x * horizontal_sensitivity * 0.01

	_pitch -= motion.relative.y * vertical_sensitivity * 0.01
	_pitch = clamp(_pitch, deg_to_rad(vertical_min_degrees), deg_to_rad(vertical_max_degrees))


func _process(delta: float) -> void:
	# --- First-person toggle (F3) ---
	# is_action_just_pressed fires for exactly one frame on key-down, so
	# tapping F3 flips the mode once instead of rapidly toggling for as
	# long as the key is held.
	if Input.is_action_just_pressed("toggle_first_person") and not _in_dialogue:
		_set_first_person(not _first_person)

	# --- Freelook toggle ---
	var was_freelook := _freelook
	_freelook = Input.is_action_pressed("freelook_camera")

	if not was_freelook and _freelook:
		# Entering freelook: save current pitch so we can restore it on exit.
		_pitch_before_freelook = _pitch
		_recentering = false

	if was_freelook and not _freelook:
		# Exiting freelook: start smooth re-centering of yaw and pitch.
		_recentering = true

	# --- Yaw re-centering (always runs when not in freelook) ---
	# _yaw_offset must be 0 in standard mode. This lerp is persistent — it
	# runs every frame until the offset is gone, not just for one frame.
	if not _freelook:
		if abs(_yaw_offset) > 0.001:
			_yaw_offset = lerp_angle(_yaw_offset, 0.0, 10.0 * delta)
		else:
			_yaw_offset = 0.0

	# --- Pitch re-centering (cancelled by mouse movement — see _input) ---
	if _recentering:
		_pitch = lerp(_pitch, _pitch_before_freelook, 10.0 * delta)
		if abs(_pitch - _pitch_before_freelook) < 0.001:
			_pitch = _pitch_before_freelook
			_recentering = false

	# --- Arrow key fallback rotation ---
	# Disabled during re-centering to avoid fighting the lerp.
	if not _in_dialogue and _lock_on_target == null and not _recentering:
		if Input.is_action_pressed("camera_left"):
			if _freelook:
				_yaw_offset += deg_to_rad(key_rotation_speed) * delta
			elif _player:
				_player.rotation.y += deg_to_rad(key_rotation_speed) * delta
		if Input.is_action_pressed("camera_right"):
			if _freelook:
				_yaw_offset -= deg_to_rad(key_rotation_speed) * delta
			elif _player:
				_player.rotation.y -= deg_to_rad(key_rotation_speed) * delta
		if Input.is_action_pressed("camera_up"):
			_pitch -= deg_to_rad(key_rotation_speed * 0.5) * delta
		if Input.is_action_pressed("camera_down"):
			_pitch += deg_to_rad(key_rotation_speed * 0.5) * delta
		_pitch = clamp(_pitch, deg_to_rad(vertical_min_degrees), deg_to_rad(vertical_max_degrees))

	# --- Lock-on tracking ---
	if _lock_on_target != null:
		_update_lock_on_rotation(delta)

	# Apply rotation. The player body handles world-facing direction (Y axis).
	# This node only needs to store the vertical tilt and the freelook offset.
	rotation.x = _pitch
	rotation.y = _yaw_offset


# --- Lock-on API (called by CombatManager) ---

func set_lock_on_target(target: Node3D) -> void:
	_lock_on_target = target


func _update_lock_on_rotation(delta: float) -> void:
	if not is_instance_valid(_lock_on_target):
		_lock_on_target = null
		return

	var player_pos: Vector3 = get_parent().global_position
	var target_pos: Vector3 = _lock_on_target.global_position
	var to_target: Vector3 = target_pos - player_pos
	var target_yaw: float = atan2(to_target.x, to_target.z)

	if _player:
		_player.rotation.y = lerp_angle(_player.rotation.y, target_yaw, lock_on_lerp_speed * delta)
	_yaw_offset = lerp_angle(_yaw_offset, -lock_on_horizontal_offset, lock_on_lerp_speed * delta)


# --- First-person mode (F3 toggle) ---

func _set_first_person(enabled: bool) -> void:
	# Public-ish toggle for the first-person camera mode. Called from
	# _process when F3 is just-pressed. Idempotent — calling with the
	# same state we're already in is a no-op so we don't repeatedly
	# reassign spring_length / mesh visibility every frame.
	if _first_person == enabled:
		return
	_first_person = enabled

	# Resolve the visual mesh once per toggle. Done lazily here rather
	# than in _ready so a scene reorganisation that breaks
	# first_person_mesh_path only fails when the player presses F3,
	# not on every world load.
	var mesh_node: Node = get_node_or_null(first_person_mesh_path)

	if enabled:
		# Save whatever the player had scrolled to so we can restore it
		# on exit. arm_length is the @export default, but the player
		# may have scroll-zoomed it; we want the post-scroll value.
		_arm_length_before_fp = arm_length
		spring_length = 0.0
		# Hide Roland's visual mesh — without this, the camera (now at
		# the SpringArm3D origin = chest/neck height) renders the
		# inside of his torso. Collision is unaffected; the mesh hide
		# only changes what's drawn.
		if mesh_node is GeometryInstance3D:
			(mesh_node as GeometryInstance3D).visible = false
		print("[CameraRig] First-person ON")
	else:
		spring_length = _arm_length_before_fp
		if mesh_node is GeometryInstance3D:
			(mesh_node as GeometryInstance3D).visible = true
		print("[CameraRig] First-person OFF")


# --- Dialogue mode API (called by Dialogic signal connections) ---

func enter_dialogue_mode() -> void:
	if _in_dialogue:
		return
	_in_dialogue = true
	var tween: Tween = create_tween()
	tween.tween_property(self, "spring_length", dialogue_arm_length, dialogue_tween_duration)


func exit_dialogue_mode() -> void:
	if not _in_dialogue:
		return
	_in_dialogue = false
	var tween: Tween = create_tween()
	tween.tween_property(self, "spring_length", arm_length, dialogue_tween_duration)


# --- Forward raycast helper (used by EditToolHandler for voxel targeting) ---

func get_camera_forward_hit(max_distance_from_player: float = 5.0) -> Dictionary:
	# Casts a ray forward from the center of the screen (where the
	# crosshair sits). max_distance_from_player is measured from the
	# player's position, NOT the camera's position — the camera sits
	# spring_length meters behind the player on the spring arm, so
	# we extend the ray length to account for that gap.
	#
	# The player's own CharacterBody3D is excluded from the raycast.
	# Without this exclusion, the ray (which starts behind the player
	# and goes forward) hits Roland's capsule before reaching any
	# terrain — every aim returns a "hit" on Roland's body, even when
	# the crosshair is pointing at empty sky.
	#
	# Returns the standard Godot intersect_ray hit dict on hit, or
	# an empty dict on miss.
	#
	# Hit dict keys: "position" (world Vector3), "normal" (Vector3),
	# "collider" (Object), "collider_id" (int), "rid" (RID), "shape" (int).
	var camera: Camera3D = get_node_or_null("Camera3D")
	if camera == null:
		return {}

	# Center of the viewport — where the crosshair would be drawn.
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var screen_center: Vector2 = viewport_size * 0.5

	var origin: Vector3 = camera.project_ray_origin(screen_center)
	var direction: Vector3 = camera.project_ray_normal(screen_center)

	# Extend the ray length so max_distance_from_player is measured
	# from the player's position rather than the camera's.
	var ray_length: float = max_distance_from_player + spring_length

	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, origin + direction * ray_length)

	# Exclude the player's CharacterBody3D RID. _player is set in
	# _ready (one parent up the tree). If it's null for any reason,
	# we fall through with no exclusion — the ray hitting the player
	# is degraded behavior but not a crash.
	if _player != null:
		params.exclude = [_player.get_rid()]

	return space_state.intersect_ray(params)
