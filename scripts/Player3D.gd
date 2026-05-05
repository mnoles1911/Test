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

const STEP_HEIGHT: float = 0.30
# Auto-step / climb height in metres. Roland walks over terrain
# obstacles up to this tall WITHOUT pressing jump. At 6 vox/m
# (16.7 cm per voxel), 0.30 m clears a single 1-voxel ledge with
# ~13 cm of margin to handle the rounded capsule bottom catching
# on cube corners. A 2-voxel ledge (33 cm) exceeds STEP_HEIGHT and
# still requires jumping — that's intentional, otherwise the
# terrain would feel mushy and walls would be meaningless.
#
# How it works (see _try_step_up below): after each move_and_slide
# call where the player hit a wall while walking, we try lifting
# Roland up to STEP_HEIGHT, sliding forward, and snapping down. If
# the elevated path is clear, the step succeeds and Roland lands on
# the ledge. If still blocked, it's a real wall and Roland stops.

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

const BREATH_RECOVERY_DELAY: float = 2.0
# Pause (seconds) between surfacing and the start of breath refill.
# Models the gasp-and-recover beat — Roland surfaces, you see his
# breath stay drained for a moment, then it climbs back up. Per
# design/SWIMMING_AND_WATER.md.

const HEAD_OFFSET_METERS: float = 1.6
# Roughly Roland's eye/head height above his pivot point. With the
# 1.8 m capsule centered at Y=0.9 above feet, the top is at Y=1.8;
# eye level sits a touch below the crown at ~1.6 m above feet.
# Used to determine when his head is below the water surface.

const SWIM_VERTICAL_SPEED: float = 3.0
# Max vertical climb / dive speed in water (m/s). Slower than the
# horizontal swim speed so diving feels like work, not flight.

const SWIM_VERTICAL_ACCEL: float = 8.0
# How fast Roland reaches SWIM_VERTICAL_SPEED when ascending or
# diving. Decoupled from _accel so swim feel can be tuned without
# affecting walk/sprint.

const SWIM_NATURAL_SINK_SPEED: float = 0.6
# Default downward drift (m/s) when no swim input is held. Negative
# Y direction. Models "Roland is heavier than water with his pack
# and gear" — without active swimming, he slowly sinks. Forces the
# player to actively press Space to stay afloat in deep water,
# adding drowning tension. Real humans are slightly buoyant, but
# slow-sink reads as more game-y and tense.

const SWIM_NATURAL_SINK_ACCEL: float = 2.5
# How fast the natural sink ramps in. Lower than SWIM_VERTICAL_ACCEL
# so the moment the player STOPS holding ascend, vertical velocity
# doesn't snap to negative — it eases down. Feels like buoyancy
# being lost gradually rather than a harsh "you let go, you sink".


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
# True if WaterFlowManager.is_position_in_water reports water at the
# player's pivot position this frame. When true: motion_mode flips to
# FLOATING, sprint is disabled, swim speed applies.

var _is_submerged: bool = false
# True if Roland's head (HEAD_OFFSET_METERS above his pivot) is below
# the current water volume's surface_y. When true: breath ticks down,
# drowning damage applies if breath reaches zero.

var _breath_remaining: float = BREATH_MAX_SECONDS
# Seconds of air left. Refills automatically when not submerged.

var _breath_recovery_remaining: float = 0.0
# Countdown that gates breath refill after surfacing. Reset to
# BREATH_RECOVERY_DELAY every frame Roland is submerged. While
# above water, ticks down to zero before refill begins. The pause
# only matters after a real breath drain — at full breath the gate
# is invisible.

@export var underwater_filter_path: NodePath = "UnderwaterFilter"
# Path to the UnderwaterFilter CanvasLayer child. Set in the
# inspector if the node is renamed or moved. Default matches
# Player3D.tscn.

var _underwater_filter: Node = null

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
	_underwater_filter = get_node_or_null(underwater_filter_path)


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
		# In water, crouch is reused as the dive control (held). Skip
		# the toggle so pressing crouch underwater doesn't pollute
		# _is_crouching state that would leak out on surfacing.
		if _in_water:
			return
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
	# Sets _in_water, _is_submerged based on WaterFlowManager queries.
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
		# In water, gravity is replaced by player-controlled vertical
		# swim. Space (dodge action) ascends; Crouch dives. Releasing
		# both decays vertical velocity to zero so Roland floats at
		# his current depth. Clamp to ±SWIM_VERTICAL_SPEED so a long
		# hold doesn't accumulate beyond the design max.
		# Ascend: Space (dodge action). Descend: Shift (sprint action)
		# OR C (crouch) — both work. Sprint is unused in water (the
		# swim-speed cap already handles "no extra speed underwater"),
		# so repurposing Shift for dive maps to player muscle memory
		# from most modern third-person swimmers (Skyrim, Witcher).
		var ascend: bool = Input.is_action_pressed("dodge")
		var descend: bool = Input.is_action_pressed("sprint") or Input.is_action_pressed("crouch")
		if ascend and not descend:
			velocity.y = move_toward(velocity.y, SWIM_VERTICAL_SPEED, SWIM_VERTICAL_ACCEL * delta)
		elif descend and not ascend:
			velocity.y = move_toward(velocity.y, -SWIM_VERTICAL_SPEED, SWIM_VERTICAL_ACCEL * delta)
		else:
			# No vertical input — Roland slowly sinks. Eases toward
			# SWIM_NATURAL_SINK_SPEED (a small negative value) rather
			# than zero, so the player must actively swim up to stay
			# afloat in deep water. Adds tension to drowning timing.
			velocity.y = move_toward(velocity.y, -SWIM_NATURAL_SINK_SPEED, SWIM_NATURAL_SINK_ACCEL * delta)
		velocity.y = clampf(velocity.y, -SWIM_VERTICAL_SPEED, SWIM_VERTICAL_SPEED)
		# River currents push the player horizontally based on the
		# water level gradient. Active anywhere a flow cell or source
		# region transition produces a level delta — middle of an
		# ocean is calm (all level 8 around), but a river feeding an
		# ocean pushes the player downstream.
		var wfm: Node = get_node_or_null("/root/WaterFlowManager")
		if wfm != null:
			var current: Vector3 = wfm.get_flow_velocity_at(global_position)
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
		_breath_recovery_remaining = BREATH_RECOVERY_DELAY
		# Reset every submerged frame so the gate restarts from
		# full delay when Roland surfaces, regardless of how long
		# he was under.
		if _breath_remaining <= 0.0:
			_breath_remaining = 0.0
			# Drowning: drain HP. Roland survives ~20 seconds of
			# zero-breath time at default HP/damage values.
			health = maxf(health - DROWN_DAMAGE_PER_SECOND * delta, 0.0)
	else:
		# Surfaced (or never submerged). Wait through the gasp-
		# and-recover delay before breath starts refilling. Once
		# the gate clears, refill at BREATH_REFRESH_RATE.
		if _breath_recovery_remaining > 0.0:
			_breath_recovery_remaining = maxf(_breath_recovery_remaining - delta, 0.0)
		else:
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

	# Capture pre-slide state so we can detect "tried to move but got
	# stopped by a ledge" — see auto-step block below.
	var pre_slide_pos: Vector3 = global_position
	var intended_h: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * delta

	move_and_slide()

	# --- Auto-step over small voxel ledges ---
	# Walking forward into a 1-voxel cube (16.7 cm at 6 vox/m, since
	# we run at 6 voxels per metre) catches the capsule's rounded
	# bottom on the cube's top corner at a near-45° contact normal.
	# Godot classifies that contact as a "wall" rather than a slope,
	# and the player gets stopped cold. Auto-step lifts Roland up to
	# STEP_HEIGHT, slides forward, and snaps back down to land on
	# the ledge.
	#
	# Trigger: any non-zero horizontal intent + ANY meaningful drag
	# (15% slowed counts). Previous threshold (50% blocked) missed
	# the case where the capsule partially-climbs the corner before
	# snagging — actual movement was 60-70% of intended, threshold
	# not met, no step. With 15% threshold any consistent snag
	# triggers, including very slow walks.
	#
	# Velocity floor lowered to 0.001 m of intended motion — a creep
	# of ~0.06 m/s is enough to trigger. Effectively "if you're
	# pressing forward at all".
	if not _in_water and is_on_floor() and velocity.y <= 0.01 \
			and intended_h.length_squared() > 0.000001:
		var actual_h: Vector3 = Vector3(
			global_position.x - pre_slide_pos.x,
			0.0,
			global_position.z - pre_slide_pos.z,
		)
		# Blocked-fraction: 1.0 = completely stopped, 0.0 = full movement.
		var blocked: float = 1.0 - clampf(
			actual_h.length() / intended_h.length(), 0.0, 1.0
		)
		if blocked > 0.15:
			# Use the INTENDED direction for the step probe — actual
			# may be near-zero, so it gives no direction info. Probe
			# distance is a fixed 0.4 m forward (about 2.4 voxels at
			# our scale) so the test reaches PAST the ledge edge even
			# at slow walking speeds where intended_h is tiny.
			var probe_dir: Vector3 = intended_h.normalized()
			_try_step_up(probe_dir * 0.4)


func _try_step_up(probe_motion: Vector3) -> void:
	# Smooth auto-step via velocity kick (NOT instant teleport).
	#
	# Old approach: teleport up STEP_HEIGHT, slide forward, snap down.
	# Felt like a snap because the entire vertical change happened
	# in one frame — camera jumped by 0.3 m instantly per voxel.
	#
	# New approach: probe whether a step IS possible (is the path
	# forward clear at lifted height?). If yes, apply an UPWARD
	# velocity kick sized so gravity exactly converts it back to PE
	# at STEP_HEIGHT. Player traces a smooth parabolic arc — rises,
	# moves forward (carried by existing horizontal velocity), then
	# falls onto the new ledge. Reads as a small natural hop.
	#
	# Energy math: v = sqrt(2 * g * h). With g=GRAVITY (20) and
	# h=STEP_HEIGHT (0.3): v = sqrt(12) ≈ 3.46 m/s. Add a small
	# safety margin (×1.15) so we definitely clear the ledge before
	# falling. Arc time to apex: v/g ≈ 0.17 s. Horizontal travel in
	# that time at walk speed 4.5 m/s: ~0.77 m — well past the
	# 0.4 m probe distance, so the player is over the ledge by the
	# time they descend.
	#
	# Done with move_and_collide(test_only=true) for the probes —
	# we don't actually want to move during testing, just check
	# whether the path is clear. The position is unchanged either way.
	if probe_motion.length_squared() < 0.0001:
		return

	# 1. Probe up — is there headroom for a STEP_HEIGHT lift?
	#    test_only=true so we don't actually move; just check.
	var up_test: KinematicCollision3D = move_and_collide(
		Vector3.UP * STEP_HEIGHT, true
	)
	var available_up: float = STEP_HEIGHT
	if up_test != null:
		# Ceiling somewhere in the lift range — get_travel returns
		# how far we MOVED before hitting (less than full up vector).
		available_up = absf(up_test.get_travel().y)
		if available_up < 0.10:
			# Less than ~0.6 voxels of headroom — can't usefully step.
			return

	# 2. Probe forward AT the lifted position. We need a multi-step
	#    test_only check because move_and_collide tests from the
	#    CURRENT position. Trick: temporarily teleport up, test
	#    forward, restore — all within one frame, no visual change.
	var saved_pos: Vector3 = global_position
	global_position += Vector3.UP * available_up
	var fwd_test: KinematicCollision3D = move_and_collide(probe_motion, true)
	global_position = saved_pos

	if fwd_test != null:
		# Path is still blocked at the lifted height. Real wall.
		return

	# 3. Apply the upward kick. Gravity (in the next frame's
	#    velocity update) will arc the player up + over the ledge
	#    AND back down on its own — no manual snap-down needed.
	#    velocity.y = max(...) avoids killing an existing upward
	#    velocity (e.g. the rising edge of a jump that overlapped
	#    with the auto-step trigger).
	var kick: float = sqrt(2.0 * GRAVITY * available_up) * 1.15
	velocity.y = maxf(velocity.y, kick)


func _update_water_state() -> void:
	# Query WaterFlowManager (autoload) for water at the player's feet
	# and head. This replaces the Area3D group-scan model from PR #130
	# — water now lives in a voxel cell dictionary, not in scene-placed
	# Area3Ds. See scripts/WaterFlowManager.gd for the storage model.
	#
	# WaterFlowManager.is_position_in_water tests the active dictionary
	# AND any registered source regions (oceans, lakes), so a single
	# query covers per-cell water and large body-of-water AABBs.
	_in_water = false
	_is_submerged = false

	var wfm: Node = get_node_or_null("/root/WaterFlowManager")
	if wfm != null:
		# Bound the player position cache so the flow tick can scan
		# only the active radius around the player.
		wfm.set_player_position(global_position)
		_in_water = wfm.is_position_in_water(global_position)
		if _in_water:
			# Submersion = head also under water. Reusing the existing
			# HEAD_OFFSET_METERS so the threshold matches PR #130.
			var head_pos := global_position + Vector3(0.0, HEAD_OFFSET_METERS, 0.0)
			_is_submerged = wfm.is_position_in_water(head_pos)

	# Drive the underwater camera tint. set_active is idempotent —
	# the filter only updates visibility on actual state changes.
	if _underwater_filter != null and _underwater_filter.has_method("set_active"):
		_underwater_filter.set_active(_is_submerged)


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
		if _underwater_filter != null and _underwater_filter.has_method("set_active"):
			_underwater_filter.set_active(false)
	else:
		velocity = Vector3.ZERO
	return is_flying
