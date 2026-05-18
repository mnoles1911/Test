class_name Player3D
extends CharacterBody3D
# Class name added so external scripts (e.g. CopperIslesTestBootstrap)
# can read the SPAWN_POSITION const as a single source of truth.
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

const BUOYANT_RISE_SPEED: float = 1.2
# Buoyancy (2026-05-18, #13). With no swim input while SUBMERGED,
# Roland is lighter than water and drifts UP toward the surface at
# this speed (m/s). Slower than SWIM_VERTICAL_SPEED so actively
# swimming up still feels faster and deliberate. Replaces the old
# slow-SINK model: real bodies float; *diving* is the thing that
# takes effort — which the descend input now meaningfully fights.

const BUOYANT_RISE_ACCEL: float = 3.0
# Ramp toward BUOYANT_RISE_SPEED when the player lets go underwater.
# Gentle, so surfacing reads as a natural float-up rather than a pop.

const BUOYANT_SETTLE_ACCEL: float = 4.0
# At the surface (in water but head NOT submerged) with no input,
# vertical velocity eases toward 0 at this rate — Roland settles and
# bobs at the waterline instead of sinking back under or launching
# out. This is the "floats at the surface" feel.


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

const WATER_EXIT_MARGIN_M: float = 0.20
# #4 waterline-jitter fix (2026-05-17). Standing at the exact sea
# surface, the pivot bobs sub-voxel (CharacterBody3D snap + float),
# so a raw per-frame is_position_in_water(pivot) flips true/false every
# few frames — _in_water chatters, motion_mode/sprint/swim flicker, and
# the WaterDiag surface-Y Δ swings 0.0-0.67 m. Hysteresis: ENTER water
# when the pivot is in water (unchanged), but only EXIT once a probe
# WATER_EXIT_MARGIN_M *below* the pivot is also dry — i.e. the pivot
# must rise a clear ~1.2 voxels above the surface before going dry.
# One extra query, only while already wet; no timer, no extra state.

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

var _spawn_freeze: bool = false
# When true, _physics_process skips ALL motion (gravity, input, water).
# Set briefly during scene load while we wait for VoxelLodTerrain
# chunks to stream in below the player — without this, a saved Y
# position is immediately pulled into the void by gravity because
# the voxel floor under the saved location may not have generated
# its collision mesh yet. World3DBootstrap.gd flips this off once a
# downward raycast confirms ground exists.

# =============================================================
# VOXEL VIEWER LOOKAHEAD (LOD streaming bias toward direction of travel)
# =============================================================
# The VoxelViewer node (a child of Player3D) defines the centre of
# Zylann's streaming sphere. By default the sphere is symmetric around
# the player — half the chunk-load budget covers chunks BEHIND, where
# the player will never look. We push the viewer's local position
# forward in the direction of travel so the sphere becomes lopsided:
# more LOD0 budget ahead, less behind. Same total streaming volume,
# biased toward what's about to be on-screen.
#
# OPINIONATED DESIGN — the offset scales with velocity in TWO ways:
#
#   1. Direction is horizontal velocity (dir = vel_xz.normalized()).
#      Y is excluded — gravity / jumping is not navigation intent.
#
#   2. Lookahead SECONDS itself ramps with speed. Idle and slow walk
#      get a small bias (no point reaching far ahead — the player
#      may turn). Sprint gets a much bigger bias (long straight runs
#      need maximum forward priority). This is the "function of
#      velocity" knob: faster motion = aggressively further ahead.
#
# Then a hard distance cap (MAX_OFFSET_METERS) prevents fly mode
# (~45 m/s) from pushing the viewer past the LOD0 ring at 128 m,
# which would leave the chunks under the player's feet at LOD1+.
#
# Concrete values across the speed range:
#   idle (0 m/s):    seconds=1.5  →  offset = 0 m  (symmetric sphere)
#   walk (4.5 m/s):  seconds=2.0  →  offset = 9 m  (~7% of LOD0 ring)
#   sprint (8.5 m/s):seconds=3.5  →  offset = 30 m (~23% of LOD0 ring)
#   fly (45 m/s):    seconds=4.0  →  capped at 40 m (~31% of ring)
#
# All of this is tunable via the constants below. Set
# VIEWER_LOOKAHEAD_MAX_OFFSET_M = 0.0 to disable the lookahead entirely
# (viewer stays at the player's origin, original symmetric behaviour).

const VIEWER_LOOKAHEAD_MIN_SECONDS: float = 1.5
# Lookahead time at and below VIEWER_LOOKAHEAD_LOW_SPEED_MPS.
# Smaller value → less bias when moving slowly. 1.5 s × 4.5 m/s walk
# = 6.75 m. Past this, seconds ramps up linearly with speed.

const VIEWER_LOOKAHEAD_MAX_SECONDS: float = 4.0
# Lookahead time at and above VIEWER_LOOKAHEAD_HIGH_SPEED_MPS. Combined
# with the speed at that point, this defines the maximum theoretical
# offset before the distance cap clamps it. Pick higher for more
# aggressive bias on long sprints / fly traversals.

const VIEWER_LOOKAHEAD_LOW_SPEED_MPS: float = 4.5
# Speed below which the lookahead seconds value pegs at MIN_SECONDS.
# Set to BASE_WALK_SPEED so casual exploration walking gets the gentle
# bias (the player may turn at any moment).

const VIEWER_LOOKAHEAD_HIGH_SPEED_MPS: float = 8.5
# Speed above which the lookahead seconds value pegs at MAX_SECONDS.
# Set to BASE_SPRINT_SPEED so committed sprints get full lookahead.
# Fly mode (~45 m/s) pegs here too and then gets clamped by the
# distance cap.

const VIEWER_LOOKAHEAD_MAX_OFFSET_M: float = 40.0
# Hard cap on the viewer offset in metres. Prevents fly mode (or any
# future high-speed traversal) from pushing the viewer past the LOD0
# ring, which would leave the chunks under the player at LOD1+ and
# create visible LOD pop directly under their feet. 40 m is ~31 % of
# the 128 m LOD0 ring — comfortably inside the safety margin.
# Set to 0.0 to disable the entire lookahead system.

const VIEWER_OFFSET_SMOOTH_HALFLIFE_S: float = 0.20
# Exponential half-life for VoxelViewer offset transitions. Without
# this, the offset SNAPS frame-to-frame:
#   - player stops → offset jumps to Vector3.ZERO
#   - player turns → offset flips sign in one frame
#   - speed crosses LOW_SPEED → lookahead_s jumps in one frame
# Each snap forces Zylann's CLIPBOX to recompute the required-blocks
# set and drop in-flight chunk loads. A single direction flip on
# 2026-05-14 produced 3262 dropped_block_loads + 9.2 ms detect_us in
# one frame (see design/captures/profile_capture_96300.json frame
# context, [DIAG] log "lag_xz=0.6 m"). Smoothing turns that into a
# ~150 ms ramp so Zylann sees gradual viewer drift instead of a
# discontinuity. 0.20 s half-life ≈ 0.6 s to reach 87% of new target.
# Tightened from 0.35 s on 2026-05-14 to reduce trailing during
# direction changes; verified post-fix capture showed sprint had
# already gone to 0 drops, so the budget for snap protection
# could be relaxed.

@onready var _voxel_viewer: Node = get_node_or_null("VoxelViewer")
# Cached on first frame. The VoxelViewer node is added by Player3D.tscn;
# get_node_or_null guards against custom Player3D instances that don't
# include one (e.g. headless tests).

@onready var _camera_target: Node3D = get_node_or_null("CameraTarget") as Node3D
# Cached at _ready. Used by _smooth_camera_y to apply a Y offset that
# damps the small per-frame Y bobbing the body undergoes while walking
# over voxel ledges (auto-step + slope adjustments). See
# _smooth_camera_y below for the gating + math.

# Baseline Y of CameraTarget in local space (matches the .tscn value).
# The smoothing system applies offsets RELATIVE to this baseline so a
# return-to-zero offset always re-centres the camera at chest height.
const CAMERA_TARGET_BASE_Y: float = 1.5

# Persistent state for the exponential smoother on the viewer offset.
# Initialised to Vector3.ZERO so the first frame's smoothing pulls
# *toward* the velocity-scaled target rather than jumping straight to
# it. See VIEWER_OFFSET_SMOOTH_HALFLIFE_S above.
var _viewer_offset_smoothed: Vector3 = Vector3.ZERO

# Half-life of the Y smoothing — every CAMERA_Y_SMOOTH_HALFLIFE_S the
# offset between smoothed and real body Y halves. 0.08 s ≈ 5 frames at
# 60 fps; small enough that the lag isn't perceptible, large enough
# that single-voxel auto-step bumps (≈ 0.167 m at 6 vox/m) get
# noticeably smoothed.
const CAMERA_Y_SMOOTH_HALFLIFE_S: float = 0.08

# Hard cap on how far the smoothed Y is allowed to lag behind the real
# Y. Stops the camera from drifting away during a long slope climb;
# also caps the snap-back distance if the gate suddenly flips off.
# 0.5 m ≈ 3 voxels — comfortably bounded.
const CAMERA_Y_SMOOTH_MAX_OFFSET: float = 0.5

# Smoothing state — _camera_smoothed_y is the camera's "memory" of
# where the body was, lerped toward the body's actual Y. Difference
# between the two is applied as a CameraTarget.position.y offset.
var _camera_smoothed_y: float = 0.0
var _camera_smoothed_initialized: bool = false

# Crouch camera drop (2026-05-17). Standing eye = CAMERA_TARGET_BASE_Y
# (1.5 m on the 1.8 m capsule). Crouching lowers the first-person
# camera by this much → ~0.9 m eye height (~60% of standing, a natural
# crouch). Applied as a smoothed offset layered on top of the existing
# bob-damping in _smooth_camera_y, so toggling C eases the camera
# down/up instead of snapping. Camera-only by design — the collision
# capsule is NOT shrunk here (crouch-under-overhangs was not requested).
const CROUCH_CAMERA_DROP: float = 0.6
const CROUCH_CAM_HALFLIFE_S: float = 0.10
var _crouch_cam_y: float = 0.0

# Jump-cooldown gate. Set to JUMP_DISABLE_SMOOTHING_S when the player
# presses jump (dodge action) so the camera tracks the jump arc 1:1.
# Decays in _smooth_camera_y each frame. Crucially this is ONLY set by
# the explicit jump button — auto-step's velocity kick (~3.46 m/s up)
# does NOT trigger it, so walking up a 1-voxel slope keeps smoothing
# active and the camera glides over the small auto-step arc.
var _camera_jump_cooldown_s: float = 0.0

# Camera Y smoothing tunables (continued from CAMERA_* block above).
#
# Free-fall snap threshold. Camera tracks 1:1 during a real fall so the
# player feels air-time, but a brief off-floor frame during a downward
# step (gravity only pulls ~0.7 m/s in that single frame) should NOT
# snap. -5.0 m/s is "definitely falling, not a 1-voxel step transition".
const CAMERA_Y_FREEFALL_VEL: float = -5.0

# Jump cooldown duration. JUMP_VELOCITY=7 with GRAVITY=20 → arc time
# ≈ 0.7 s up + 0.7 s down ≈ 1.4 s in the air at worst case. Use 1.0 s
# as the smoothing-disabled window — covers a normal jump comfortably,
# is_on_floor() takes over after the cooldown decays.
const JUMP_DISABLE_SMOOTHING_S: float = 1.0


const FLY_SPEED_MULT: float = 10.0
# Multiplier on walk speed while flying. 10x means ~50 m/s — fast
# enough to cross the test world in seconds, slow enough that the
# camera can keep up.

const SPAWN_POSITION: Vector3 = Vector3(21.0, 253.0, 147.0)
# Single hardcoded spawn point used by CopperIslesTestBootstrap when
# placing the player on scene load. toggle_fly_mode() does NOT teleport
# here — it preserves the player's current position so testers can
# enter/exit fly mode without losing their place.

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
	# MP-2: claim local authority over our own player node. In OFFLINE
	# mode MultiplayerManager.is_offline() returns true and the
	# authority check below still permits input. When a session is
	# active, only the local peer's Player3D will pass _can_take_input.
	if get_node_or_null("/root/MultiplayerManager"):
		var local_id: int = MultiplayerManager.local_peer_id()
		if local_id != 0:
			set_multiplayer_authority(local_id)
	_attach_sync_node()
	_attach_combat_xp_router()


func _attach_sync_node() -> void:
	# Programmatic MultiplayerSynchronizer setup. Replicates the
	# minimal state RemotePlayer (and any future spectator UI) needs to
	# render this peer: position, body yaw rotation, sprint/crouch
	# flags. Built in code so existing .tscn files don't need editing.
	if get_node_or_null("MPSync") != null:
		return
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MPSync"
	sync.replication_interval = 0.05   # 20 Hz
	var cfg := SceneReplicationConfig.new()
	cfg.add_property(NodePath(".:position"))
	cfg.property_set_spawn(NodePath(".:position"), true)
	cfg.property_set_replication_mode(NodePath(".:position"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.add_property(NodePath(".:rotation:y"))
	cfg.property_set_spawn(NodePath(".:rotation:y"), true)
	cfg.property_set_replication_mode(NodePath(".:rotation:y"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.add_property(NodePath(".:_is_sprinting"))
	cfg.property_set_replication_mode(NodePath(".:_is_sprinting"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.add_property(NodePath(".:_is_crouching"))
	cfg.property_set_replication_mode(NodePath(".:_is_crouching"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = cfg
	add_child(sync)


func _attach_combat_xp_router() -> void:
	# CombatXPRouter listens for Enemy3D died/damaged signals and routes
	# kill/hit XP to Sword / Bow / Throwables based on which weapon was
	# last used. VitalityXPRouter ticks alongside it for swim-time XP.
	if get_node_or_null("CombatXPRouter") == null:
		var router: Node = CombatXPRouter.new()
		router.name = "CombatXPRouter"
		add_child(router)
	if get_node_or_null("VitalityXPRouter") == null:
		var vr: Node = VitalityXPRouter.new()
		vr.name = "VitalityXPRouter"
		add_child(vr)


# =============================================================
# MP-2 INPUT GATE
# =============================================================

func _can_take_input() -> bool:
	# Returns true if this Player3D should read local input. True in
	# OFFLINE mode (single-player) and when we are the multiplayer
	# authority over this specific node. Every Input.* read in this
	# script must guard with this — see CLAUDE.md.
	if not get_node_or_null("/root/MultiplayerManager"):
		return true
	if MultiplayerManager.is_offline():
		return true
	return get_multiplayer_authority() == multiplayer.get_unique_id()


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
	# MP gate — remote replicas of other players must never consume
	# our local crouch toggle.
	if not _can_take_input():
		return
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
	# Profiling wrapper — feeds the in-HUD [PERF] log + F3 Profiler overlay.
	#
	# Sub-instrumented (2026-05-12): time `_update_viewer_lookahead` and
	# `_physics_process_inner` separately. Inside `_physics_process_inner`
	# the `move_and_slide()` calls are themselves wrapped so the jump-
	# correlated spike can be attributed (move_and_slide vs auto-step
	# vs water-state checks vs the rest). The outer Player3D total is
	# also retained so the Overview can still rank by "total physics".
	#
	# get_node_or_null guards for the case Player3D runs outside the main
	# game (e.g. test harness without the autoloads registered).
	var _t0_prof: int = Time.get_ticks_usec()
	_physics_process_inner(delta)

	# Camera Y smoothing — applies a small offset to CameraTarget so the
	# camera glides over the body's per-frame Y bobs while walking. Gated
	# off during jumps / falls so air-time response stays 1:1. Cheap,
	# called every physics frame regardless. Profiled so the new cost is
	# visible in the F3 overlay.
	var _t_cam_start: int = Time.get_ticks_usec()
	_smooth_camera_y(delta)
	var _t_cam_us: int = Time.get_ticks_usec() - _t_cam_start

	var _t_view_start: int = Time.get_ticks_usec()
	_update_viewer_lookahead(delta)
	var _t_view_us: int = Time.get_ticks_usec() - _t_view_start

	var _elapsed: int = Time.get_ticks_usec() - _t0_prof
	if get_node_or_null("/root/HUDOverlay"):
		HUDOverlay.profile_record("Player3D_phys", _elapsed)
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("PHYS", "Player3D", _elapsed)
		prof.record("PHYS", "Player3D_camera_smooth", _t_cam_us)
		prof.record("PHYS", "Player3D_viewer_lookahead", _t_view_us)


func _update_viewer_lookahead(delta: float) -> void:
	# Velocity-scaled VoxelViewer offset — see the constants block above
	# for full design rationale. Two-stage scaling:
	#   1. Lookahead seconds ramps from MIN_SECONDS to MAX_SECONDS as
	#      speed climbs from LOW_SPEED to HIGH_SPEED.
	#   2. Direction is horizontal velocity (Y excluded so gravity /
	#      jump bobs don't shake the streaming sphere).
	# Final offset is then clamped to MAX_OFFSET_METERS to keep the
	# viewer inside the LOD0 ring at any speed (incl. fly mode).
	#
	# Final write is then EXPONENTIALLY SMOOTHED toward the target
	# offset — see VIEWER_OFFSET_SMOOTH_HALFLIFE_S. Snapping the offset
	# (player stops, turns, crosses the speed threshold) was causing
	# Zylann's CLIPBOX detector to drop thousands of in-flight chunk
	# requests in single frames.
	#
	# Runs every physics frame from _physics_process. Cost: a length
	# call + one lerp + one position write. Effectively free.
	if _voxel_viewer == null:
		return
	if VIEWER_LOOKAHEAD_MAX_OFFSET_M <= 0.0:
		# Lookahead disabled — keep viewer at player origin (symmetric).
		_viewer_offset_smoothed = Vector3.ZERO
		_voxel_viewer.position = Vector3.ZERO
		return

	# Compute the target offset (the previous direct-write value).
	var target_offset: Vector3 = Vector3.ZERO
	var horiz: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var speed: float = horiz.length()
	if speed >= 0.05:
		# Stage 1 — pick a lookahead-seconds value scaled by speed.
		# remap clamps the input to [LOW_SPEED, HIGH_SPEED] before lerping,
		# so speeds outside that band peg at MIN_SECONDS or MAX_SECONDS.
		var t: float = clampf(
			(speed - VIEWER_LOOKAHEAD_LOW_SPEED_MPS) \
				/ max(0.001, VIEWER_LOOKAHEAD_HIGH_SPEED_MPS - VIEWER_LOOKAHEAD_LOW_SPEED_MPS),
			0.0,
			1.0,
		)
		var lookahead_s: float = lerpf(VIEWER_LOOKAHEAD_MIN_SECONDS, VIEWER_LOOKAHEAD_MAX_SECONDS, t)

		# Stage 2 — offset = velocity vector * lookahead seconds. Direction
		# inherent in the vector, magnitude is speed * seconds.
		target_offset = horiz * lookahead_s

		# Distance cap — fly mode at 45 m/s with seconds=4 would request a
		# 180 m offset, way past the LOD0 ring. Clamp into the safe band.
		var offset_len: float = target_offset.length()
		if offset_len > VIEWER_LOOKAHEAD_MAX_OFFSET_M:
			target_offset *= VIEWER_LOOKAHEAD_MAX_OFFSET_M / offset_len
	# else: idle — target stays Vector3.ZERO, smoother decays toward symmetric.

	# Exponential smoothing: alpha = 1 - 2^(-delta / halflife). At
	# delta=1/60 s and halflife=0.35 s, alpha ≈ 0.032 — each frame
	# pulls 3.2% toward the new target. Direction reversals and
	# speed-threshold crossings stretch over ~250 ms instead of one
	# frame, eliminating the dropped_block_loads bursts.
	var alpha: float = 1.0 - pow(2.0, -delta / VIEWER_OFFSET_SMOOTH_HALFLIFE_S)
	_viewer_offset_smoothed = _viewer_offset_smoothed.lerp(target_offset, alpha)
	_voxel_viewer.position = _viewer_offset_smoothed


func _smooth_camera_y(delta: float) -> void:
	# Damps the per-frame Y bobbing the body undergoes walking over
	# voxel ledges (auto-step + slope adjustments). The camera "lags"
	# slightly behind the body's Y so the eye sees a smooth curve
	# instead of single-voxel steps.
	#
	# Math: maintain `_camera_smoothed_y`, a value that lerps toward the
	# real body Y with a half-life of CAMERA_Y_SMOOTH_HALFLIFE_S. The
	# offset between the two (smoothed - real) is applied as the
	# CameraTarget's local Y adjustment, so the camera's global Y =
	# body_y + (BASE + offset) = body_y + BASE + (smoothed - body_y) =
	# smoothed + BASE. In other words the camera renders at chest
	# height above the SMOOTHED body Y, not the raw one.
	#
	# Gates (snap to body, no smoothing) — REVISED 2026-05-12 because
	# the original |velocity.y| gate disabled smoothing during auto-step
	# (which uses a 3.46 m/s velocity kick to arc over 1-voxel ledges).
	# That made walking up slopes feel bumpy when the goal was to
	# smooth them. New gate:
	#   * _camera_jump_cooldown_s > 0 — player pressed jump. Set
	#     ONLY in the dodge-action handler (line ~745); auto-step
	#     does not touch it. So walking up a 1-voxel ledge keeps
	#     smoothing active even though vel.y briefly spikes.
	#   * velocity.y < CAMERA_Y_FREEFALL_VEL — clear free-fall.
	#     -5 m/s is well past the brief downward-step transition
	#     where gravity pulls only ~0.7 m/s in a single frame.
	#
	# is_on_floor() is NOT used as a gate anymore — it returns false
	# during the 1-2 frames a 1-voxel downward step takes, which used
	# to disable smoothing exactly when we wanted it most.
	#
	# Cheap (~1 µs/frame). No allocations.
	if _camera_target == null:
		return

	# Always decay the jump cooldown so it doesn't pin the gate open.
	_camera_jump_cooldown_s = maxf(0.0, _camera_jump_cooldown_s - delta)

	# Crouch camera offset — eased toward the crouched/standing target
	# every frame (frame-rate-independent half-life) so the C toggle
	# glides the eye down/up. Added to every CameraTarget.y assignment
	# below so it composes with the bob-damping and the snap cases.
	var _crouch_target: float = -CROUCH_CAMERA_DROP if _is_crouching else 0.0
	var _crouch_alpha: float = 1.0 - pow(0.5, delta / CROUCH_CAM_HALFLIFE_S)
	_crouch_cam_y = lerp(_crouch_cam_y, _crouch_target, _crouch_alpha)

	var raw_y: float = global_position.y
	if not _camera_smoothed_initialized:
		_camera_smoothed_y = raw_y
		_camera_smoothed_initialized = true
		_camera_target.position.y = CAMERA_TARGET_BASE_Y + _crouch_cam_y
		return

	var is_player_jumping: bool = _camera_jump_cooldown_s > 0.0
	var is_clear_freefall: bool = (not is_on_floor()) and velocity.y < CAMERA_Y_FREEFALL_VEL
	var is_flying_now: bool = is_flying
	if is_player_jumping or is_clear_freefall or is_flying_now:
		# Player-initiated jump / real fall / fly mode — snap so the
		# camera response is fully 1:1 (player needs to feel the
		# air-time, the fall, or the fly-mode movement).
		_camera_smoothed_y = raw_y
		_camera_target.position.y = CAMERA_TARGET_BASE_Y + _crouch_cam_y
		return

	# Frame-rate-independent exponential lerp toward the real body Y.
	# alpha = 1 - 0.5 ^ (delta / halflife) gives the fraction to lerp
	# this frame so the half-life is exact regardless of frame rate.
	var alpha: float = 1.0 - pow(0.5, delta / CAMERA_Y_SMOOTH_HALFLIFE_S)
	_camera_smoothed_y = lerp(_camera_smoothed_y, raw_y, alpha)

	# Apply the lag as a local Y offset on CameraTarget. Clamped so a
	# long climb (smoothed never catches up) can't push the camera
	# below the player's feet or above their head.
	var offset_y: float = _camera_smoothed_y - raw_y
	offset_y = clampf(offset_y, -CAMERA_Y_SMOOTH_MAX_OFFSET, CAMERA_Y_SMOOTH_MAX_OFFSET)
	_camera_target.position.y = CAMERA_TARGET_BASE_Y + offset_y + _crouch_cam_y


func _physics_process_inner(delta: float) -> void:
	# --- Spawn freeze short-circuit ---
	# While the world is still streaming chunks under the player's
	# saved/spawn position, do nothing — no gravity, no input. This
	# prevents the player falling through unloaded voxels during the
	# loading screen. World3DBootstrap clears the flag once it's
	# confirmed terrain exists below us.
	if _spawn_freeze:
		velocity = Vector3.ZERO
		return

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
	# MP gate: remote replicas read zero input; their position is
	# driven entirely by MultiplayerSynchronizer replicating the local
	# authority's transform.
	var input_dir: Vector2 = Vector2.ZERO
	if _can_take_input():
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var local_dir  := Vector3(input_dir.x, 0.0, input_dir.y)
	# Multiply through the player body's transform.basis so W always moves
	# in the direction Roland (and the camera) is currently facing.
	var direction  := (transform.basis * local_dir).normalized()
	var is_moving  := direction != Vector3.ZERO

	# --- Sprint logic (disabled in water — Roland can't sprint while swimming) ---
	if _sprint_locked and endurance >= ENDURANCE_SPRINT_THRESHOLD:
		_sprint_locked = false
	var wants_sprint := _can_take_input() \
		and Input.is_action_pressed("sprint") \
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
		var ascend: bool = _can_take_input() and Input.is_action_pressed("dodge")
		var descend: bool = _can_take_input() and (Input.is_action_pressed("sprint") or Input.is_action_pressed("crouch"))
		if ascend and not descend:
			velocity.y = move_toward(velocity.y, SWIM_VERTICAL_SPEED, SWIM_VERTICAL_ACCEL * delta)
		elif descend and not ascend:
			velocity.y = move_toward(velocity.y, -SWIM_VERTICAL_SPEED, SWIM_VERTICAL_ACCEL * delta)
		else:
			# No vertical input — BUOYANCY. Submerged: Roland is lighter
			# than water and drifts up toward the surface. At the surface
			# (in water but head clear): ease toward neutral so he settles
			# and bobs at the waterline instead of sinking back under or
			# launching out. Diving (descend) above overrides this and
			# fights the buoyant rise — that is what makes going deep feel
			# like effort, and lets the player surface just by letting go.
			if _is_submerged:
				velocity.y = move_toward(velocity.y, BUOYANT_RISE_SPEED, BUOYANT_RISE_ACCEL * delta)
			else:
				velocity.y = move_toward(velocity.y, 0.0, BUOYANT_SETTLE_ACCEL * delta)
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
		#
		# Set the camera-smoothing jump cooldown HERE (not in the
		# smoother). This is the only path that should disable Y
		# smoothing — auto-step's velocity kick goes through
		# _try_step_up and does NOT touch this cooldown, so walking up
		# 1-voxel slopes keeps smoothing active.
		elif _can_take_input() and Input.is_action_just_pressed("dodge"):
			velocity.y = JUMP_VELOCITY
			_camera_jump_cooldown_s = JUMP_DISABLE_SMOOTHING_S

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

	# Wrap move_and_slide() so the Profiler can isolate Godot's
	# CharacterBody3D collision work from the rest of our logic. The
	# 10ms jump-frame spike observed in early captures is suspected to
	# live here; sub-instrumentation pins it down.
	var _t_ms_start: int = Time.get_ticks_usec()
	move_and_slide()
	var _t_ms_us: int = Time.get_ticks_usec() - _t_ms_start
	var _prof_ms := get_node_or_null("/root/Profiler")
	if _prof_ms != null:
		_prof_ms.record("PHYS", "Player3D_move_and_slide", _t_ms_us)

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
	# Capture last frame's state BEFORE the reset — the hysteresis
	# exit test below needs to know whether we were already wet.
	var was_in_water: bool = _in_water
	_in_water = false
	_is_submerged = false

	var wfm: Node = get_node_or_null("/root/WaterFlowManager")
	if wfm != null:
		# Bound the player position cache so the flow tick can scan
		# only the active radius around the player.
		wfm.set_player_position(global_position)
		var pivot_wet: bool = wfm.is_position_in_water(global_position)
		if was_in_water:
			# Already wet: stay wet until a probe one exit-margin BELOW
			# the pivot is also dry. At the surface the pivot bobs but
			# pivot-margin stays submerged → no chatter. Only a genuine
			# climb-out (pivot a full margin clear of the surface) makes
			# the lower probe dry and flips _in_water false.
			var sink_probe := global_position - Vector3(0.0, WATER_EXIT_MARGIN_M, 0.0)
			_in_water = pivot_wet or wfm.is_position_in_water(sink_probe)
		else:
			_in_water = pivot_wet
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

	# WASD input. MP gate: remote replicas stay still in fly mode.
	var input_dir: Vector2 = Vector2.ZERO
	var v_input: float = 0.0
	if _can_take_input():
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_action_pressed("dodge"):
			v_input += 1.0
		if Input.is_action_pressed("sprint"):
			v_input -= 1.0
	# Forward = -Z, right = +X. Use the camera's basis directly so
	# pitch carries — if the camera looks down 30°, W flies 30° down.
	#
	# Input.get_vector("ui_left","ui_right","ui_up","ui_down") returns
	# y = ui_down - ui_up, so W → y=-1 and S → y=+1. To get W=forward
	# we negate input_dir.y when multiplying by forward (so W=-1 * -1
	# = +forward = away from camera). X axis is unchanged: D → +right,
	# A → -right. Pre-2026-05-12 this missed the negation, so flight
	# moved W=backward and S=forward — fixed now.
	var forward: Vector3 = -cam_basis.z
	var right:   Vector3 = cam_basis.x
	var dir: Vector3 = (right * input_dir.x) + (forward * -input_dir.y)
	dir.y += v_input

	if dir.length_squared() > 0.0001:
		dir = dir.normalized()

	var fly_speed: float = _walk_speed * FLY_SPEED_MULT
	# Direct velocity assignment — no acceleration ramp. Flying
	# should feel responsive, not weighty.
	velocity = dir * fly_speed
	# Profiler-instrumented (same pattern as the grounded path).
	var _t_ms_fly_start: int = Time.get_ticks_usec()
	move_and_slide()
	var _t_ms_fly_us: int = Time.get_ticks_usec() - _t_ms_fly_start
	var _prof_ms_fly := get_node_or_null("/root/Profiler")
	if _prof_ms_fly != null:
		_prof_ms_fly.record("PHYS", "Player3D_move_and_slide", _t_ms_fly_us)


func toggle_fly_mode() -> bool:
	# Public toggle for the F1 debug overlay. Returns the new state
	# (true = flying, false = grounded). Preserves position — testers
	# can pop in/out of fly mode mid-flight without losing their place.
	# Velocity is zeroed so Roland doesn't drift off after the toggle.
	is_flying = not is_flying
	velocity = Vector3.ZERO
	if is_flying:
		# Clear water state so the swim HUD doesn't linger.
		_in_water = false
		_is_submerged = false
		if _underwater_filter != null and _underwater_filter.has_method("set_active"):
			_underwater_filter.set_active(false)
	return is_flying
