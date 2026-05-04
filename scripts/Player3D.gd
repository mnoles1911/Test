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
# Initial upward velocity applied on jump. With GRAVITY=20 m/s², a
# 7 m/s jump peaks at v²/(2g) ≈ 1.22 m — well clear of a single voxel
# (~16.7 cm at 6 vox/m) or a stair-stepped two-voxel ledge, comfortable
# for hopping over rocks.
const JUMP_VELOCITY: float = 7.0
# Stronger than real-world 9.8 m/s². Game gravity should feel snappy on drops.


# =============================================================
# SWIMMING CONSTANTS
# =============================================================
# Per design/SWIMMING_AND_WATER.md.

const SWIM_SPEED_FRACTION: float = 0.55
# Multiplier on walk speed when swimming. Roland moves slower in
# water. Sprint is disabled in water entirely.

const BREATH_MAX_SECONDS: float = 30.0
# How long Roland can hold his breath underwater before drowning
# damage starts. Per the design doc.

const BREATH_REFRESH_RATE: float = 8.0
# How fast breath refills per second once Roland's head is above
# water. Faster than the drain rate so a quick surface fully
# refreshes within a few seconds.

const DROWN_DAMAGE_PER_SECOND: float = 5.0
# HP lost per second once breath reaches zero. Designed to give
# the player time to surface (a full HP bar lasts 20 seconds at
# 5/sec), not to be a punishing instant-death.

const HEAD_OFFSET_METERS: float = 1.6
# Roughly Roland's eye/head height above his pivot point. With the
# 1.8 m capsule centered at Y=0.9 above feet, the top is at Y=1.8;
# eye level sits a touch below the crown at ~1.6 m above feet.
# Used to determine when his head is below the water surface.


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

var _in_water: bool = false
# True if any part of Roland is inside a water_volume Area3D this frame.
# When true: motion_mode flips to FLOATING, sprint is disabled, swim
# speed applies. The water Area3D is found via group scan each frame.

var _is_submerged: bool = false
# True if Roland's head (HEAD_OFFSET_METERS above his pivot) is below
# the current water volume's surface_y. When true: breath ticks down,
# drowning damage applies if breath reaches zero.

var _breath_remaining: float = BREATH_MAX_SECONDS
# Seconds of air left. Refills automatically when not submerged.

var _current_water_volume: Node = null
# Cached reference to the water_volume Area3D Roland is currently
# inside, or null if dry. Used to query surface_y and current.

# =============================================================
# DEBUG FLY MODE
# =============================================================

var is_flying: bool = false
# When true, gravity is disabled, swim/water physics are skipped, and
# Roland flies in the direction the camera is facing at FLY_SPEED_MULT
# times normal walk speed. Toggled via the F1 debug overlay's
# TOGGLE FLY MODE command (see DebugOverlay.gd).

const FLY_SPEED_MULT: float = 10.0
# Multiplier on walk speed while flying. 10x means ~50 m/s — fast
# enough to cross the test world in seconds, slow enough that the
# camera can keep up.

const FLY_TELEPORT_HEIGHT: float = 100.0
# Y coordinate Roland is teleported to when fly mode is first
# engaged (per the design ask "teleport up to Y=100").

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
		# Drowning takes priority — if Roland is out of breath the
		# player needs to know NOW, not after they read past sprint
		# state. Breath also wins over crouch.
		if _is_submerged and _breath_remaining <= 0.0:
			return "DROWNING"
		if _is_submerged:
			return "BREATH: %.0fs" % _breath_remaining
		if _in_water:
			return "SWIMMING"
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
	# --- Fly mode short-circuit ---
	# Debug-only flight that ignores gravity, water, and the
	# voxel-terrain collision floor. Movement direction comes from
	# the camera's forward vector (with pitch) instead of the
	# player body's rotation.
	if is_flying:
		_physics_process_flying(delta)
		return

	# --- Detect water (must run BEFORE movement decisions) ---
	# Walks the water_volume group; first overlapping water Area3D
	# wins. Sets _in_water, _is_submerged, _current_water_volume.
	_update_water_state()

	# Switch motion mode based on water state. FLOATING ignores the
	# floor (no fall damage, no automatic gravity application from
	# CharacterBody3D's grounded path); we still apply gravity below
	# explicitly, so the only behavioral difference is "no auto floor
	# snapping" — which is what we want in water.
	motion_mode = MOTION_MODE_FLOATING if _in_water else MOTION_MODE_GROUNDED

	# --- Read WASD input and convert to camera-relative world direction ---
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var local_dir  := Vector3(input_dir.x, 0.0, input_dir.y)
	# Multiply through the player body's transform.basis so W always moves
	# in the direction Roland (and the camera) is currently facing.
	var direction  := (transform.basis * local_dir).normalized()
	var is_moving  := direction != Vector3.ZERO

	# --- Sprint logic (disabled in water — Roland can't sprint while swimming) ---
	if _sprint_locked and endurance >= ENDURANCE_SPRINT_THRESHOLD:
		_sprint_locked = false
	var wants_sprint := Input.is_action_pressed("sprint") \
		and not _is_crouching \
		and not _sprint_locked \
		and not _in_water
	_is_sprinting = wants_sprint and is_moving

	# --- Target speed for this frame ---
	var target_speed: float
	if _in_water:
		# Swimming is slower than walking. Swim speed scales off
		# walk speed via the SWIM_SPEED_FRACTION constant.
		target_speed = _walk_speed * SWIM_SPEED_FRACTION
	elif _is_crouching:
		target_speed = _crouch_speed
	elif _is_sprinting:
		target_speed = _sprint_speed
	else:
		target_speed = _walk_speed

	# --- Horizontal movement with momentum ---
	if is_moving:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, _accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, _accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, _decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, _decel * delta)

	# --- Vertical motion ---
	if _in_water:
		# In water, gravity is replaced by gentle damping toward zero.
		# Roland floats wherever he entered. Walking out of the water
		# Area3D restores normal gravity. Vertical swim controls (Space
		# = up, Crouch = down) can be added later; for the slice the
		# player floats at entry depth.
		velocity.y = move_toward(velocity.y, 0.0, _decel * delta)
		# River currents push the player horizontally + vertically.
		if _current_water_volume != null:
			var current: Vector3 = _current_water_volume.get_current_velocity()
			if current.length_squared() > 0.0001:
				velocity += current * delta
	else:
		# Normal gravity when not in water.
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		# Jump: Space (dodge action) launches Roland straight up while
		# grounded. Gates on is_on_floor() so the player can't double-
		# jump or air-hop. Reuses the dodge action because there's no
		# combat dodge yet; when combat lands and dodge becomes a roll,
		# this can split into a dedicated `jump` Input Map action.
		elif Input.is_action_just_pressed("dodge"):
			velocity.y = JUMP_VELOCITY

	# --- Breath / drowning ---
	if _is_submerged:
		_breath_remaining -= delta
		if _breath_remaining <= 0.0:
			_breath_remaining = 0.0
			# Drowning: drain HP. Roland survives ~20 seconds of
			# zero-breath time at default HP/damage values.
			health = maxf(health - DROWN_DAMAGE_PER_SECOND * delta, 0.0)
	else:
		# Surfaced (or never submerged) — refresh breath. Faster
		# than the drain rate so coming up for air is responsive.
		_breath_remaining = minf(_breath_remaining + BREATH_REFRESH_RATE * delta, BREATH_MAX_SECONDS)

	# --- Endurance drain / regen ---
	if _is_sprinting:
		endurance -= ENDURANCE_SPRINT_DRAIN * delta
		if endurance <= 0.0:
			endurance    = 0.0
			_is_sprinting = false
			_sprint_locked = true   # Must recover before sprinting again.
	elif is_moving:
		endurance = minf(endurance + ENDURANCE_WALK_REGEN * delta, max_endurance)
	else:
		endurance = minf(endurance + ENDURANCE_IDLE_REGEN * delta, max_endurance)

	move_and_slide()


func _update_water_state() -> void:
	# Find the first water_volume Area3D overlapping the player.
	# If multiple overlap, the first one in the group wins — water
	# volumes shouldn't overlap in practice.
	#
	# This is a per-frame poll rather than a signal-driven model.
	# Fewer connections to manage, and the cost is trivial (a few
	# nodes in the group at most). If the group ever grows large
	# (hundreds of water bodies), revisit.
	_current_water_volume = null
	_in_water = false

	for area in get_tree().get_nodes_in_group("water_volume"):
		if not area is Area3D:
			continue
		var area3d := area as Area3D
		if not area3d.overlaps_body(self):
			continue
		# Even if the trigger Area3D overlaps the player, only count
		# this as "in water" if the player's FEET are at-or-below the
		# water's surface_y. Without this guard, a water volume whose
		# collision shape extends above its surface (e.g. the ocean's
		# 30m-tall box that overhangs the air above sea level for
		# editor-resilience) would put the player into swim physics
		# while still standing on dry land or hovering above the
		# surface.
		var surface_y: float = INF
		if "surface_y" in area3d:
			surface_y = float(area3d.surface_y)
		if global_position.y <= surface_y:
			_current_water_volume = area3d
			_in_water = true
			break

	# Submersion check uses the cached water volume's surface_y.
	if _in_water and _current_water_volume.has_method("is_position_submerged"):
		_is_submerged = _current_water_volume.is_position_submerged(global_position, HEAD_OFFSET_METERS)
	else:
		_is_submerged = false


# =============================================================
# DEBUG — FLY MODE
# =============================================================

func _physics_process_flying(_delta: float) -> void:
	# Movement uses the camera's forward vector (with pitch) so the
	# player flies wherever they're looking. Held WASD steers
	# horizontally relative to that forward, Space climbs, Crouch
	# descends. No gravity, no water, no floor snapping.
	motion_mode = MOTION_MODE_FLOATING

	# Camera basis: walk up the rig — Player3D > CameraTarget >
	# SpringArm3D > Camera3D — so we get the actual look direction
	# including yaw + pitch. Falls back to body forward if the rig
	# isn't where we expect.
	var camera: Camera3D = get_node_or_null("CameraTarget/SpringArm3D/Camera3D") as Camera3D
	# Renamed from `basis` to avoid shadowing Node3D.basis.
	var cam_basis: Basis
	if camera != null:
		cam_basis = camera.global_transform.basis
	else:
		cam_basis = transform.basis

	# WASD input.
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# Forward = -Z, right = +X. Use the camera's basis directly so
	# pitch carries — if the camera looks down 30°, W flies 30° down.
	var forward: Vector3 = -cam_basis.z
	var right:   Vector3 = cam_basis.x
	var dir: Vector3 = (right * input_dir.x) + (forward * input_dir.y)

	# Vertical input — Space (dodge action) ascends, Left Shift
	# (sprint action) descends. Both held, not toggled.
	var v_input: float = 0.0
	if Input.is_action_pressed("dodge"):
		v_input += 1.0
	if Input.is_action_pressed("sprint"):
		v_input -= 1.0
	dir.y += v_input

	if dir.length_squared() > 0.0001:
		dir = dir.normalized()

	var fly_speed: float = _walk_speed * FLY_SPEED_MULT
	# Direct velocity assignment — no acceleration ramp. Flying
	# should feel responsive, not weighty.
	velocity = dir * fly_speed
	move_and_slide()


func toggle_fly_mode() -> bool:
	# Public toggle for the F1 debug overlay. Returns the new state
	# (true = flying, false = grounded).
	#
	# On engagement: teleport up to FLY_TELEPORT_HEIGHT so the player
	# pops above any terrain peaks and can see the world from above.
	# On disengagement: zero velocity so we don't suddenly fall at
	# whatever fly-speed Roland was moving at.
	is_flying = not is_flying
	if is_flying:
		global_position.y = FLY_TELEPORT_HEIGHT
		velocity = Vector3.ZERO
		# Clear water state so the swim HUD doesn't linger.
		_in_water = false
		_is_submerged = false
		_current_water_volume = null
	else:
		velocity = Vector3.ZERO
	return is_flying
