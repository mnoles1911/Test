extends SpringArm3D
# CameraRig — Third-person over-shoulder follow camera.
#
# This is the camera style of The Witcher 3, Dark Souls, and Elden Ring:
# Roland is visible in the left foreground, the world stretches out ahead,
# and the player rotates the view freely with the mouse.
#
# WHY SpringArm3D?
#   SpringArm3D is a Godot node with a built-in "collision shortener" — if a
#   wall or ceiling comes between the camera and Roland, the arm automatically
#   pulls the camera inward so it never clips through geometry. Caves, doorways,
#   and tight corridors just work. No per-room camera scripting required.
#
# Scene hierarchy this script expects:
#
#   Player3D (CharacterBody3D)
#   └── CameraTarget (Node3D)   ← positioned at Roland's shoulder height (~1.5m up)
#       └── SpringArm3D         ← THIS SCRIPT lives here
#           └── Camera3D        ← the actual camera, pointed back at Roland
#
# IMPORTANT: The Camera3D child does not need any rotation set on it manually.
# SpringArm3D automatically points the camera back toward the pivot. Just add
# Camera3D as a child node and leave its local transform at zero.
#
# HOW ROTATION WORKS:
#   _yaw   = horizontal spin (mouse left/right). Stored in radians; applied to self.rotation.y
#   _pitch = vertical tilt  (mouse up/down).   Stored in radians; applied to self.rotation.x
#   Both are stored separately so we can clamp pitch without fighting Euler order weirdness.
#
# HOW MOUSE INPUT WORKS:
#   Input.mouse_mode is set to CAPTURED during gameplay (cursor hidden, all mouse
#   motion goes to the camera). It switches to VISIBLE when a menu opens.
#   MouseMotion events feed _yaw and _pitch directly — no Input Map action needed.
#
# HOW LOCK-ON WORKS:
#   Call set_lock_on_target(enemy_node) from CombatManager when the player presses
#   lock_on. While locked, the camera lerps its yaw to keep the enemy in the right
#   60% of frame. Call set_lock_on_target(null) to disengage.
#
# HOW DIALOGUE MODE WORKS:
#   Call enter_dialogue_mode() when Dialogic opens a Tier 2/3 conversation.
#   The arm tweens shorter and the angle shifts slightly for a profile framing.
#   Call exit_dialogue_mode() when the timeline ends.


# --- Exports (tweak these in the Godot inspector) ---

@export var arm_length: float = 5.0
# Distance the camera sits from Roland in meters when nothing is blocking it.
# SpringArm3D shortens this automatically in tight spaces.
# Outdoors: 5.0–5.5m. Indoors: SpringArm clips naturally — do not override manually.

@export var elevation_degrees: float = 15.0
# Default pitch above horizontal in degrees. 15° = cinematic over-shoulder.
# The player can tilt within vertical_min/max below. This is the starting angle.

@export var horizontal_sensitivity: float = 0.15
# How fast the camera responds to mouse horizontal movement.
# Lower = slower, more deliberate rotation. Raise if it feels sluggish.
# This value is multiplied with the raw pixel delta from InputEventMouseMotion.

@export var vertical_sensitivity: float = 0.10
# How fast the camera responds to mouse vertical movement.
# Slightly lower than horizontal because vertical travel is smaller on most mice.

@export var vertical_min_degrees: float = -20.0
# How far down the player can tilt the camera (negative = looking more downward).
# -20° prevents looking straight at Roland's feet.

@export var vertical_max_degrees: float = 45.0
# How far up the player can tilt the camera.
# 45° gives a reasonable overhead view; going higher starts hiding the horizon.

@export var key_rotation_speed: float = 90.0
# How fast the camera rotates when using arrow keys (degrees per second).
# Arrow keys are a fallback for players who prefer not to use mouse drag.

@export var dialogue_arm_length: float = 3.5
# Arm length to tween to when a Dialogic conversation opens.
# Shorter = camera pulls in closer, Roland's profile and the NPC are both visible.

@export var dialogue_tween_duration: float = 0.3
# How long the dialogue arm-length tween takes in seconds.

@export var lock_on_lerp_speed: float = 5.0
# How fast the camera swings to frame a lock-on target. Higher = snappier.

@export var lock_on_horizontal_offset: float = 0.3
# How far left (in radians) to rotate away from the target's direction.
# This puts the target in the right ~60% of frame with Roland in left foreground.
# 0.3 radians ≈ 17°. Increase to push the target further right.


# --- Internal state ---

var _yaw: float = 0.0          # Current horizontal camera angle in radians
var _pitch: float = 0.0        # Current vertical camera angle in radians (negative = looking down)
var _lock_on_target: Node3D    # The enemy currently locked on (null if not locked)
var _in_dialogue: bool = false  # True while a Dialogic conversation is open


func _ready() -> void:
	# Set the arm length. spring_length is the built-in SpringArm3D property.
	spring_length = arm_length

	# Start at the default elevation angle.
	# We store pitch in radians; deg_to_rad converts the export value.
	_pitch = -deg_to_rad(elevation_degrees)

	# Capture the mouse so all mouse movement feeds the camera, not the OS cursor.
	# This is the standard mode for 3D games during gameplay.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Only read mouse motion when the cursor is captured (i.e., during gameplay).
	# When a menu is open the cursor is VISIBLE and we do not want mouse motion
	# to accidentally rotate the camera.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Do not rotate manually while locked on — lock-on drives the yaw in _process.
		if _lock_on_target == null:
			_yaw   -= event.relative.x * horizontal_sensitivity * 0.01
			_pitch -= event.relative.y * vertical_sensitivity   * 0.01
			_pitch  = clamp(_pitch, deg_to_rad(vertical_min_degrees), deg_to_rad(vertical_max_degrees))


func _process(delta: float) -> void:
	# --- Arrow key fallback rotation ---
	# For players who prefer keys over mouse drag, or for controller right-stick
	# when using the Input Map actions. These add on top of (or instead of) mouse.
	if _lock_on_target == null:
		if Input.is_action_pressed("camera_left"):
			_yaw += deg_to_rad(key_rotation_speed) * delta
		if Input.is_action_pressed("camera_right"):
			_yaw -= deg_to_rad(key_rotation_speed) * delta
		if Input.is_action_pressed("camera_up"):
			_pitch -= deg_to_rad(key_rotation_speed * 0.5) * delta
		if Input.is_action_pressed("camera_down"):
			_pitch += deg_to_rad(key_rotation_speed * 0.5) * delta
		_pitch = clamp(_pitch, deg_to_rad(vertical_min_degrees), deg_to_rad(vertical_max_degrees))

	# --- Lock-on camera tracking ---
	# When locked on, lerp the yaw so the enemy stays in the right frame half.
	if _lock_on_target != null:
		_update_lock_on_rotation(delta)

	# --- Apply rotation to this node ---
	# Setting rotation.x and rotation.y directly is safe here because we never
	# touch rotation.z (no roll), so there is no Euler order ambiguity.
	rotation.x = _pitch
	rotation.y = _yaw


# --- Lock-on API ---
# Called by CombatManager when the player presses lock_on.

func set_lock_on_target(target: Node3D) -> void:
	_lock_on_target = target


func _update_lock_on_rotation(delta: float) -> void:
	if not is_instance_valid(_lock_on_target):
		# Target was freed (enemy died or moved out of range). Disengage.
		_lock_on_target = null
		return

	# Get the world-space position of both Roland and the target.
	# global_position on this node is the SpringArm3D, which is at CameraTarget
	# height — close enough to Roland's position for this calculation.
	var player_pos: Vector3 = get_parent().global_position  # CameraTarget's world pos
	var target_pos: Vector3 = _lock_on_target.global_position

	# Compute the horizontal angle from Roland to the target.
	# atan2 on the XZ plane gives us the yaw that points at the target.
	var to_target: Vector3 = target_pos - player_pos
	var target_yaw: float = atan2(to_target.x, to_target.z)

	# Offset leftward so the target appears in the RIGHT side of frame.
	# Roland's silhouette occupies the left foreground — standard Souls framing.
	var desired_yaw: float = target_yaw - lock_on_horizontal_offset

	# Lerp toward desired yaw. lerp_angle handles the 360°→0° wraparound correctly.
	_yaw = lerp_angle(_yaw, desired_yaw, lock_on_lerp_speed * delta)


# --- Dialogue mode API ---
# Call these from a Dialogic signal connection in the scene that starts dialogue.

func enter_dialogue_mode() -> void:
	if _in_dialogue:
		return
	_in_dialogue = true
	# Tween the arm shorter to pull the camera in for a profile conversation framing.
	var tween: Tween = create_tween()
	tween.tween_property(self, "spring_length", dialogue_arm_length, dialogue_tween_duration)


func exit_dialogue_mode() -> void:
	if not _in_dialogue:
		return
	_in_dialogue = false
	# Tween back out to the standard gameplay arm length.
	var tween: Tween = create_tween()
	tween.tween_property(self, "spring_length", arm_length, dialogue_tween_duration)
