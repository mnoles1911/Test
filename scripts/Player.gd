extends CharacterBody2D
# Attached to the Player scene (scenes/Player.tscn).
#
# CharacterBody2D is Godot's built-in node for characters that move
# through the world and collide with walls and other bodies.
# It handles all the physics math — we just tell it which direction to go.


# How fast the player moves, in pixels per second.
# At 320x180 native resolution, 100 px/s covers the screen in about 1.6 seconds.
# Adjust this to taste once you can feel the movement.
const SPEED: float = 100.0

# How quickly the player brakes when no key is held, in pixels per second squared.
# DECEL = 400 means the player goes from full speed to stopped in 0.25 seconds.
# Higher = snappier stop. Lower = more sliding.
const DECEL: float = 400.0


func _physics_process(delta: float) -> void:
	# _physics_process runs every physics frame (default: 60 times per second).
	# delta is the time elapsed since the last frame (usually ~0.016 seconds at 60fps).
	# We need it here to make deceleration frame-rate independent.

	# Input.get_vector reads four directional inputs and returns a Vector2.
	# Vector2 is just two numbers: (x, y). Left/right changes x, up/down changes y.
	#
	# get_vector automatically handles diagonals: if you press right AND up at the
	# same time, it returns a normalized vector (length = 1.0) so diagonal movement
	# isn't faster than cardinal movement.
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if direction != Vector2.ZERO:
		# Player is pressing a direction — set velocity toward that direction.
		# velocity is a built-in property of CharacterBody2D.
		velocity = direction * SPEED
	else:
		# No input held — slow the player to a stop over time.
		# move_toward reduces velocity by at most (DECEL * delta) per frame.
		# Multiplying by delta keeps deceleration consistent regardless of frame rate.
		# Without delta, the step would be per-call instead of per-second, and the
		# player would stop instantly (100 step on a 100-unit velocity = zero in one frame).
		velocity = velocity.move_toward(Vector2.ZERO, DECEL * delta)

	# move_and_slide does the actual movement.
	# It reads self.velocity, moves the character, and slides along walls
	# instead of stopping dead when a collision is hit.
	# It also updates self.velocity to reflect any blocked directions.
	move_and_slide()
