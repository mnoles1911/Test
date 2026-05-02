extends CharacterBody3D
# Player3D — Roland's movement controller.
#
# PHYSICS MODEL
#   Every movement value scales from @export var mass. A lighter Roland
#   accelerates faster and reaches a higher sprint speed; a heavier one
#   carries more momentum and takes longer to stop. NPCs share this model
#   through their own mass exports — tune NPCData to set how each character
#   feels. All scaling uses fractional exponents so the curve is gentle:
#   doubling mass doesn't halve your speed, it just makes you noticeably slower.
#
# MOVEMENT STATES
#   WALK   — WASD, normal pace
#   SPRINT — hold Left Shift; drains endurance; locked until recovery after exhaustion
#   CROUCH — press C to toggle; slower; cannot sprint while crouching
#
# HEALTH AND ENDURANCE
#   health     — 0–100, reduced by combat (not yet wired to damage)
#   endurance  — 0–100, depletes while sprinting, regenerates while walking or idle
#                Sprint is locked at 0 until endurance recovers past the threshold
#
# HUDOverlay reads `health`, `max_health`, `endurance`, `max_endurance`, and
# `status_text` directly each frame to drive the on-screen bars.


# =============================================================
# MASS AND MOVEMENT CONSTANTS
# =============================================================

@export var mass: float = 80.0
# Roland's mass in kilograms. Exported so you can tweak it per-character
# in the Godot inspector without changing code. Higher = slower, more
# momentum. Lower = snappier, faster top speed.

const REF_MASS: float = 70.0
# The reference mass at which BASE_* values apply exactly.
# All other masses are scaled relative to this.

const BASE_WALK_SPEED: float   = 4.5    # m/s comfortable walk at REF_MASS
const BASE_SPRINT_SPEED: float = 8.5    # m/s full sprint at REF_MASS
const BASE_CROUCH_SPEED: float = 2.0    # m/s while crouching at REF_MASS
const BASE_ACCEL: float        = 18.0   # m/s² rate to ramp UP to target speed
const BASE_DECEL: float        = 12.0   # m/s² rate to ramp DOWN to zero
# DECEL is lower than ACCEL intentionally — characters spin up faster than
# they stop. This gives the natural momentum feel of a body with real weight,
# especially noticeable at higher mass values.

const GRAVITY: float = 20.0
# Stronger than real-world 9.8 m/s². Game gravity should feel snappy on drops.


# =============================================================
# HEALTH AND ENDURANCE CONSTANTS
# =============================================================

const MAX_HEALTH_DEFAULT: float    = 100.0
const MAX_ENDURANCE_DEFAULT: float = 100.0

const ENDURANCE_SPRINT_DRAIN: float     = 15.0
# Points per second drained while actively sprinting.

const ENDURANCE_WALK_REGEN: float       = 6.0
# Points per second recovered while walking (not sprinting).

const ENDURANCE_IDLE_REGEN: float       = 20.0
# Points per second recovered while standing completely still.
# Faster than walking regen to reward pausing to catch your breath.

const ENDURANCE_SPRINT_THRESHOLD: float = 20.0
# Sprint cannot re-engage after exhaustion until endurance recovers above
# this value. Prevents immediately re-entering sprint at 1 point.


# =============================================================
# RUNTIME STATE
# =============================================================

var health: float = MAX_HEALTH_DEFAULT
var max_health: float = MAX_HEALTH_DEFAULT

var endurance: float = MAX_ENDURANCE_DEFAULT
var max_endurance: float = MAX_ENDURANCE_DEFAULT

var _is_sprinting: bool  = false
var _is_crouching: bool  = false
var _sprint_locked: bool = false
# Locked = true when endurance hits 0. Sprint cannot start again until
# endurance recovers above ENDURANCE_SPRINT_THRESHOLD.

# Precomputed from mass — calculated once in _ready().
# Call _recalculate_movement_stats() if mass changes at runtime.
var _walk_speed:   float
var _sprint_speed: float
var _crouch_speed: float
var _accel:        float
var _decel:        float


# =============================================================
# STATUS TEXT (read by HUDOverlay for display)
# =============================================================

var status_text: String:
	get:
		if _sprint_locked:
			return "EXHAUSTED"
		if _is_crouching:
			return "CROUCHING"
		return ""


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_recalculate_movement_stats()


func _recalculate_movement_stats() -> void:
	# r > 1 for lighter than REF_MASS (faster), < 1 for heavier (slower).
	# Fractional exponents keep scaling gentle — 40 kg extra doesn't ruin mobility.
	var r: float = REF_MASS / mass
	_walk_speed   = BASE_WALK_SPEED   * pow(r, 0.20)
	_sprint_speed = BASE_SPRINT_SPEED * pow(r, 0.30)
	_crouch_speed = BASE_CROUCH_SPEED * pow(r, 0.15)
	_accel        = BASE_ACCEL        * pow(r, 0.50)
	_decel        = BASE_DECEL        * pow(r, 0.50)


# =============================================================
# INPUT — crouch toggle (fires once per press, not held)
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("crouch"):
		_is_crouching = not _is_crouching
		# Cannot crouch and sprint simultaneously.
		if _is_crouching:
			_is_sprinting = false


# =============================================================
# PHYSICS PROCESS
# =============================================================

func _physics_process(delta: float) -> void:
	# --- Read WASD input and convert to camera-relative world direction ---
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var local_dir  := Vector3(input_dir.x, 0.0, input_dir.y)
	# Multiply through the player body's transform.basis so W always moves
	# in the direction Roland (and the camera) is currently facing.
	var direction  := (transform.basis * local_dir).normalized()
	var is_moving  := direction != Vector3.ZERO

	# --- Sprint logic ---
	# Unlock sprint once endurance recovers enough after exhaustion.
	if _sprint_locked and endurance >= ENDURANCE_SPRINT_THRESHOLD:
		_sprint_locked = false
	# Shift must be held, crouching must be off, and sprint must not be locked.
	var wants_sprint := Input.is_action_pressed("sprint") \
		and not _is_crouching \
		and not _sprint_locked
	_is_sprinting = wants_sprint and is_moving

	# --- Target speed for this frame ---
	var target_speed: float
	if _is_crouching:
		target_speed = _crouch_speed
	elif _is_sprinting:
		target_speed = _sprint_speed
	else:
		target_speed = _walk_speed

	# --- Horizontal movement with momentum ---
	# move_toward() advances velocity toward the target at the configured
	# rate each frame, creating smooth acceleration and deceleration curves.
	# The character cannot snap to full speed or stop instantly — momentum
	# is determined by mass through _accel and _decel.
	if is_moving:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, _accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, _accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, _decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, _decel * delta)

	# --- Gravity ---
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# --- Endurance drain / regen ---
	if _is_sprinting:
		endurance -= ENDURANCE_SPRINT_DRAIN * delta
		if endurance <= 0.0:
			endurance    = 0.0
			_is_sprinting = false
			_sprint_locked = true   # Must recover before sprinting again.
	elif is_moving:
		# Walking recovers endurance slowly — moving costs less than sprinting
		# but you're still exerting yourself.
		endurance = minf(endurance + ENDURANCE_WALK_REGEN * delta, max_endurance)
	else:
		# Idle recovers fastest — reward stopping to rest.
		endurance = minf(endurance + ENDURANCE_IDLE_REGEN * delta, max_endurance)

	move_and_slide()
