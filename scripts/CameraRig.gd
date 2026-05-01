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
#     On F2 release → camera re-centers behind Roland.
#     Use this to glance around without changing Roland's facing.
#
# MOVEMENT NOTE:
#   Player3D.gd multiplies input by the player body's transform.basis so
#   movement is always relative to where Roland (and the camera) faces.


@export var arm_length: float = 5.0
# How far the camera sits from Roland when unobstructed. SpringArm3D
# shortens this automatically in caves, doorways, and tight corridors.

@export var elevation_degrees: float = 15.0
# Starting vertical tilt of the arm above horizontal. Player can adjust
# within vertical_min/max below.

@export var horizontal_sensitivity: float = 0.15
# Camera speed for mouse left/right. Raise if rotation feels sluggish.

@export var vertical_sensitivity: float = 0.10
# Camera speed for mouse up/down. Slightly lower than horizontal is natural.

@export var vertical_min_degrees: float = -20.0
# Lowest the player can tilt the camera (negative = looking more downward).

@export var vertical_max_degrees: float = 45.0
# Highest the player can tilt the camera.

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


# --- Internal state ---

var _pitch: float = 0.0
# Vertical tilt in radians. Applied to self.rotation.x each frame.

var _yaw_offset: float = 0.0
# Horizontal arm offset from the player body in radians.
# Standard mode: stays near 0 (camera centered behind Roland).
# Freelook mode: drifts freely as the mouse moves.

var _freelook: bool = false
# True while the freelook_camera action (F2) is held.

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


func _input(event: InputEvent) -> void:
	# _input fires for every input event regardless of whether another node
	# already handled it. This is correct for camera rotation — we always
	# want to respond to mouse motion during gameplay.
	if _in_dialogue:
		return
	if not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

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
	# --- Freelook toggle ---
	var was_freelook := _freelook
	_freelook = Input.is_action_pressed("freelook_camera")

	if was_freelook and not _freelook:
		# F2 just released — glide the arm offset back to center.
		_yaw_offset = lerp_angle(_yaw_offset, 0.0, 10.0 * delta)
		if abs(_yaw_offset) < 0.001:
			_yaw_offset = 0.0

	# --- Arrow key fallback rotation ---
	if not _in_dialogue and _lock_on_target == null:
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
