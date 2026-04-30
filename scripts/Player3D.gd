extends CharacterBody3D
# Player3D — Roland's movement controller in the 3D voxel world.
#
# This is the 3D counterpart to Player.gd (which controlled the 2D
# CharacterBody2D). Mechanically the feel is identical — 8-directional
# movement with snappy acceleration and quick deceleration — but the
# coordinate system is different:
#
#   2D:  X = horizontal, Y = vertical (down is positive)
#   3D:  X = east/west, Y = UP, Z = north/south
#
# The "ground plane" the player walks on is the XZ plane. Y is gravity.
# Input.get_vector returns a Vector2 (input_dir.x, input_dir.y), and we
# map that to Vector3(input_dir.x, 0, input_dir.y) so:
#   - left/right (input.x)  → world X
#   - up/down    (input.y)  → world Z
#
# Up on the keyboard moves the player AWAY from the camera (negative Z
# in Godot's default coordinate system, hence we don't negate input.y —
# the camera looks down -Z so positive input.y = towards camera = back).
# If movement feels reversed when the camera is added, flip the sign here.


const SPEED: float = 5.0
# Meters per second. 5.0 is a comfortable walking pace for a Hades-style
# camera. Roland is a tired traveller — we don't want him zipping around.

const ACCEL: float = 30.0
# How quickly velocity ramps up to SPEED. Higher = snappier start.

const DECEL: float = 40.0
# How quickly velocity drops to zero when input stops. Higher = sharper
# stop, more arcade-feeling. Lower = more glide.

const GRAVITY: float = 20.0
# Meters per second squared. Godot's default is 9.8 (real Earth) but
# games usually feel better with stronger gravity — characters fall
# fast, jumps feel weighty. We're not jumping yet, but voxel terrain
# can have drops, so we still apply gravity to keep the player grounded.


func _physics_process(delta: float) -> void:
	# Read the WASD / arrow key input as a 2D vector. Godot normalises
	# diagonals automatically with get_vector, so moving NE doesn't go
	# faster than moving N.
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# Map 2D input onto the 3D XZ plane (Y is up).
	var direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)

	# Horizontal movement — accelerate towards target, decelerate when idle.
	var target_velocity_x: float = direction.x * SPEED
	var target_velocity_z: float = direction.z * SPEED

	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, target_velocity_x, ACCEL * delta)
		velocity.z = move_toward(velocity.z, target_velocity_z, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, DECEL * delta)

	# Gravity — only apply when in the air. is_on_floor() comes from
	# CharacterBody3D and uses the floor_max_angle setting (default 45°).
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# move_and_slide() reads self.velocity, applies it, and resolves
	# collisions with walls/floor automatically. It also updates
	# is_on_floor() / is_on_wall() for the next frame.
	move_and_slide()
