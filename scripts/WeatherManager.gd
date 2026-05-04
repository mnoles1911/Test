extends Node
# WeatherManager — global atmospheric state.
#
# What this does in plain English:
#
#   Holds one of six weather states (CLEAR, OVERCAST, LIGHT_RAIN,
#   HEAVY_RAIN, FOG, SNOW) and pushes the visual + audible side-effects
#   of that state out to other systems:
#
#     - DayNightCycle (fog colour + density via set_fog_override)
#     - WaterFlowManager (wind direction + strength via set_global_wind)
#     - WorldEnvironment (ambient_light_energy, direct write)
#     - Rain / snow particle scenes (Phase 6, 7 — not yet wired)
#     - Wet-terrain overlay + material_override (Phase 8 — not yet wired)
#     - Ambient audio crossfade (Phase 10 — not yet wired)
#     - Lightning + thunder during HEAVY_RAIN (Phase 12 — not yet wired)
#
#   Three trigger sources, applied in priority order:
#
#     1. Story override (set_weather_override) — timer-based.
#     2. Proximity zone (Phase 11 — not yet wired) — player inside a
#        WeatherZone Area3D forces a state.
#     3. Authored schedule + weighted random (Phase 9 — currently the
#        WorldClock hour_changed roll uses a baked default distribution).
#
#   When the active state changes, we tween toward the new state's
#   profile values (fog, ambient, wind_strength) over TRANSITION_DURATION_S
#   so transitions are gradual rather than snap. Wind DIRECTION is
#   independent of state changes and drifts on its own gradual lerp.
#
# Why an autoload?
#
#   Weather is a global property — exterior scenes everywhere need to
#   read or react to it. An autoload owns the state and emits signals
#   that any system can subscribe to.
#
# Reference: design/WEATHER_AND_ENVIRONMENT.md


# ============================================================
# State enum + names (string form used by save data and overrides)
# ============================================================

enum State { CLEAR, OVERCAST, LIGHT_RAIN, HEAVY_RAIN, FOG, SNOW }

const STATE_NAMES: Dictionary = {
	State.CLEAR:      "clear",
	State.OVERCAST:   "overcast",
	State.LIGHT_RAIN: "light_rain",
	State.HEAVY_RAIN: "heavy_rain",
	State.FOG:        "fog",
	State.SNOW:       "snow",
}


# ============================================================
# State profiles — what each weather state LOOKS like.
#
# Designer-tunable, six entries; a Resource file is overkill for v1.
# WeatherManager interpolates values toward the active state's profile
# during TRANSITION_DURATION_S so changes never snap.
# ============================================================

const STATE_PROFILES: Dictionary = {
	State.CLEAR: {
		"fog_color":        Color(0.7, 0.85, 1.0),
		"fog_density":      0.0,
		"ambient_dim":      1.0,
		"wind_strength":    0.5,
		"particle_density": 0,
		"ambient_audio":    "",
	},
	State.OVERCAST: {
		"fog_color":        Color(0.6, 0.65, 0.7),
		"fog_density":      0.01,
		"ambient_dim":      0.85,
		"wind_strength":    1.0,
		"particle_density": 0,
		"ambient_audio":    "wind_med",
	},
	State.LIGHT_RAIN: {
		"fog_color":        Color(0.55, 0.6, 0.65),
		"fog_density":      0.02,
		"ambient_dim":      0.75,
		"wind_strength":    1.5,
		"particle_density": 1500,
		"ambient_audio":    "rain_light",
	},
	State.HEAVY_RAIN: {
		"fog_color":        Color(0.4, 0.45, 0.5),
		"fog_density":      0.04,
		"ambient_dim":      0.55,
		"wind_strength":    3.5,
		"particle_density": 6000,
		"ambient_audio":    "rain_heavy",
	},
	State.FOG: {
		"fog_color":        Color(0.75, 0.75, 0.78),
		"fog_density":      0.08,
		"ambient_dim":      0.7,
		"wind_strength":    0.3,
		"particle_density": 0,
		"ambient_audio":    "wind_low",
	},
	State.SNOW: {
		"fog_color":        Color(0.85, 0.88, 0.92),
		"fog_density":      0.03,
		"ambient_dim":      0.9,
		"wind_strength":    1.2,
		"particle_density": 2500,
		"ambient_audio":    "wind_low",
	},
}


# ============================================================
# Tunables
# ============================================================

# How long it takes to interpolate from one state's profile values to
# another. 30 s feels organic — fast enough that the player notices
# the change happening, slow enough that it never feels jarring.
const TRANSITION_DURATION_S: float = 30.0

# Wind direction drift (decoupled from state changes). Direction lerps
# toward _wind_target_direction at this many degrees per second. At
# TURN_RATE 3°/s, a 180° heading change takes 60 s to complete.
const WIND_DIRECTION_TURN_RATE_DEG_PER_S: float = 3.0

# How often the wind picks a new target heading. Values too low produce
# constant flux; too high produces long monotonous wind. 90 s is the
# sweet spot in testing.
const WIND_TARGET_RESAMPLE_INTERVAL_S: float = 90.0

# Default weighted random distribution applied when no location profile
# is set. Sums to 1.0. Phase 9 introduces per-region profiles that
# override this.
const DEFAULT_RANDOM_DISTRIBUTION: Dictionary = {
	State.CLEAR:      0.40,
	State.OVERCAST:   0.30,
	State.LIGHT_RAIN: 0.15,
	State.HEAVY_RAIN: 0.05,
	State.FOG:        0.07,
	State.SNOW:       0.03,
}

# Hours of the in-game day when the schedule rolls a new state. WorldClock
# emits hour_changed once per game-hour; we only roll on these hours so
# weather changes feel paced (~3 changes per day).
const SCHEDULE_TRANSITION_HOURS: Array[int] = [6, 12, 18]


# ============================================================
# State
# ============================================================

# Trigger sources, applied in priority order in _resolve_active_state.
# -1 means "no override / no proximity zone active".
var _override_state: int = -1
var _override_hours_remaining: float = 0.0
var _proximity_state: int = -1

# What the schedule wants right now. Updated by _on_hour_changed and
# fed into _resolve_active_state as the lowest-priority source.
var _scheduled_state: int = State.CLEAR

# The state we are actively rendering. May lag _target_state during
# the transition tween.
var current_state: int = State.CLEAR

# What we are tweening toward. When current_state == _target_state and
# _transition_progress == 1.0, we're stable.
var _target_state: int = State.CLEAR

# 0 → just changed target, 1 → fully on target. Each frame in _process
# we advance this by delta / TRANSITION_DURATION_S.
var _transition_progress: float = 1.0

# Wind direction tracking. _wind_target_direction is the heading we
# eventually want to face; wind_direction lerps toward it at
# WIND_DIRECTION_TURN_RATE_DEG_PER_S. NEVER snaps.
var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.0)
var _wind_target_direction: Vector3 = Vector3(1.0, 0.0, 0.0)
var _seconds_since_wind_resample: float = 0.0

# Last interpolated profile values, written every frame to environment.
# Stored so external systems can read the live values without
# recomputing the interpolation.
var _live_fog_color: Color = STATE_PROFILES[State.CLEAR]["fog_color"]
var _live_fog_density: float = STATE_PROFILES[State.CLEAR]["fog_density"]
var _live_ambient_dim: float = 1.0
var _live_wind_strength: float = STATE_PROFILES[State.CLEAR]["wind_strength"]


# ============================================================
# Signals
# ============================================================

signal weather_state_changed(new_state: int, old_state: int)
signal weather_intensity_changed(intensity: float)


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	# WorldClock autoload is loaded BEFORE WeatherManager (project.godot
	# autoload order), so this connection is safe.
	if get_node_or_null("/root/WorldClock") != null:
		WorldClock.hour_changed.connect(_on_hour_changed)
	# Pick an initial wind heading.
	_resample_wind_target()


func _process(delta: float) -> void:
	# Advance the transition tween. _transition_progress tracks how far
	# we've moved from the previous state's profile values toward the
	# target state's profile values.
	if _transition_progress < 1.0:
		_transition_progress = minf(1.0, _transition_progress + delta / TRANSITION_DURATION_S)
		# At the moment we reach 1.0, the state has fully changed —
		# emit the signal and update current_state. We fire AT 1.0 so
		# subscribers can rely on current_state matching the visible
		# atmosphere by the time they react.
		if _transition_progress >= 1.0 and current_state != _target_state:
			var old_state: int = current_state
			current_state = _target_state
			weather_state_changed.emit(current_state, old_state)

	# Interpolate live values toward target profile.
	var prev_profile: Dictionary = STATE_PROFILES[current_state]
	var target_profile: Dictionary = STATE_PROFILES[_target_state]
	var t: float = _transition_progress
	_live_fog_color = (prev_profile["fog_color"] as Color).lerp(target_profile["fog_color"], t)
	_live_fog_density = lerpf(prev_profile["fog_density"], target_profile["fog_density"], t)
	_live_ambient_dim = lerpf(prev_profile["ambient_dim"], target_profile["ambient_dim"], t)
	_live_wind_strength = lerpf(prev_profile["wind_strength"], target_profile["wind_strength"], t)

	# Push fog into DayNightCycle's override slot. We try to find the
	# DayNightCycle node by group; the script in World3D.tscn registers
	# itself in "day_night_cycle" on _ready (Phase 1 hook).
	var dnc: Node = _find_day_night_cycle()
	if dnc != null and dnc.has_method("set_fog_override"):
		dnc.set_fog_override(_live_fog_color, _live_fog_density)

	# Push ambient light directly to WorldEnvironment.environment. We
	# don't go through DayNightCycle here because DayNightCycle never
	# touches ambient — only fog and sky. Writing it here every frame
	# is fine; WorldEnvironment treats the property as a simple float.
	var env_node: WorldEnvironment = _find_world_environment()
	if env_node != null and env_node.environment != null:
		env_node.environment.ambient_light_energy = _live_ambient_dim

	# Wind direction drift. Resample heading periodically; lerp toward
	# the current target every frame.
	_seconds_since_wind_resample += delta
	if _seconds_since_wind_resample >= WIND_TARGET_RESAMPLE_INTERVAL_S:
		_resample_wind_target()
	_advance_wind_direction(delta)

	# Push wind to the water shader (Phase 5 wiring). Strength is the
	# interpolated profile value, direction is the gradually-drifting
	# heading.
	if get_node_or_null("/root/WaterFlowManager") != null:
		WaterFlowManager.set_global_wind(wind_direction, _live_wind_strength)

	# Story override countdown — tick down in seconds, ticking the
	# remaining "hours" by delta/3600 of a real-world hour. We use real
	# seconds here, not WorldClock hours, so the override expires on a
	# real-world clock independent of game-time pause.
	if _override_hours_remaining > 0.0:
		_override_hours_remaining = maxf(0.0, _override_hours_remaining - delta / 3600.0)
		if _override_hours_remaining <= 0.0:
			_override_state = -1
			_resolve_active_state()


# ============================================================
# Public API
# ============================================================

# Story-beat hook. Force a weather state for `hours` real-world hours,
# bypassing the schedule and proximity stack. After the timer expires,
# weather returns to whatever the schedule + proximity layer wanted.
#
# state_name: case-insensitive string ("heavy_rain", "fog", ...). Must
# match one of the entries in STATE_NAMES.
# hours: real-world hours the override stays active. Use 99.0 for
# debug-overlay "set and forget".
func set_weather_override(state_name: String, hours: float) -> void:
	var lower: String = state_name.to_lower()
	var matched: int = -1
	for state_id in STATE_NAMES.keys():
		if STATE_NAMES[state_id] == lower:
			matched = state_id
			break
	if matched == -1:
		push_warning("[WeatherManager] Unknown weather state: %s" % state_name)
		return
	_override_state = matched
	_override_hours_remaining = maxf(0.0, hours)
	_resolve_active_state()


func clear_weather_override() -> void:
	_override_state = -1
	_override_hours_remaining = 0.0
	_resolve_active_state()


func get_current_state() -> int:
	return current_state


func get_state_name() -> String:
	return STATE_NAMES.get(current_state, "unknown")


# Returns the wind as a velocity vector (direction × strength). Useful
# for any future system that wants to apply wind force to particles or
# cloth without computing the product themselves.
func get_wind_velocity() -> Vector3:
	return wind_direction * _live_wind_strength


# Phase 11 hook — WeatherZone calls these on entry/exit.
func set_proximity_state(state_id: int) -> void:
	_proximity_state = state_id
	_resolve_active_state()


func clear_proximity_state() -> void:
	_proximity_state = -1
	_resolve_active_state()


# ============================================================
# Save / load (called from GameState — Phase 4)
# ============================================================

func get_save_data() -> Dictionary:
	return {
		"current_state":             current_state,
		"target_state":              _target_state,
		"override_state":            _override_state,
		"override_hours_remaining":  _override_hours_remaining,
	}


func load_save_data(data: Dictionary) -> void:
	if data == null or data.is_empty():
		return
	current_state = int(data.get("current_state", State.CLEAR))
	_target_state = int(data.get("target_state", current_state))
	_override_state = int(data.get("override_state", -1))
	_override_hours_remaining = float(data.get("override_hours_remaining", 0.0))
	# Snap the transition tween — no in-flight interpolation across loads.
	_transition_progress = 1.0


func clear_persistent_state() -> void:
	current_state = State.CLEAR
	_target_state = State.CLEAR
	_scheduled_state = State.CLEAR
	_override_state = -1
	_override_hours_remaining = 0.0
	_proximity_state = -1
	_transition_progress = 1.0


# ============================================================
# Internals
# ============================================================

# Determines which trigger source wins right now and starts a transition
# tween toward its state if it differs from the current target.
func _resolve_active_state() -> void:
	var resolved: int = _scheduled_state
	if _proximity_state != -1:
		resolved = _proximity_state
	if _override_state != -1:
		resolved = _override_state

	if resolved == _target_state:
		return

	# The tween moves FROM the current visible state TO the new target.
	# We snap current_state to where the tween is right now so the
	# blend of profile values continues smoothly without snapping fog
	# darker before re-brightening.
	current_state = current_state  # unchanged; serves as "from" in lerp
	_target_state = resolved
	_transition_progress = 0.0


func _on_hour_changed(new_hour: int) -> void:
	# Roll a new scheduled state on the configured transition hours.
	if not new_hour in SCHEDULE_TRANSITION_HOURS:
		return
	_scheduled_state = _roll_random_state()
	_resolve_active_state()


func _roll_random_state() -> int:
	# Weighted random pick from DEFAULT_RANDOM_DISTRIBUTION. Phase 9
	# replaces this with a per-location profile lookup.
	var roll: float = randf()
	var cumulative: float = 0.0
	for state_id in DEFAULT_RANDOM_DISTRIBUTION.keys():
		cumulative += DEFAULT_RANDOM_DISTRIBUTION[state_id]
		if roll < cumulative:
			return state_id
	return State.CLEAR


# ------------------------------------------------------------
# Wind direction drift
# ------------------------------------------------------------

func _resample_wind_target() -> void:
	# Pick a new heading on the XZ plane uniformly. The slow lerp in
	# _advance_wind_direction means the actual wind doesn't snap to it.
	var angle: float = randf() * TAU
	_wind_target_direction = Vector3(cos(angle), 0.0, sin(angle))
	_seconds_since_wind_resample = 0.0


func _advance_wind_direction(delta: float) -> void:
	# Lerp wind_direction toward _wind_target_direction at a fixed
	# angular rate so transitions are perceptibly gradual. We compute
	# the angle between the two on the XZ plane, clamp the step to
	# WIND_DIRECTION_TURN_RATE_DEG_PER_S * delta, and rotate.
	var current_2d: Vector2 = Vector2(wind_direction.x, wind_direction.z)
	var target_2d: Vector2 = Vector2(_wind_target_direction.x, _wind_target_direction.z)
	if current_2d.length() < 0.0001 or target_2d.length() < 0.0001:
		return
	current_2d = current_2d.normalized()
	target_2d = target_2d.normalized()
	var angle_to: float = current_2d.angle_to(target_2d)
	var max_step: float = deg_to_rad(WIND_DIRECTION_TURN_RATE_DEG_PER_S) * delta
	var step: float = clampf(angle_to, -max_step, max_step)
	var new_2d: Vector2 = current_2d.rotated(step)
	wind_direction = Vector3(new_2d.x, 0.0, new_2d.y)


# ------------------------------------------------------------
# Node lookups (cached after first hit)
# ------------------------------------------------------------

var _cached_dnc: Node = null
var _cached_env: WorldEnvironment = null


func _find_day_night_cycle() -> Node:
	if _cached_dnc != null and is_instance_valid(_cached_dnc):
		return _cached_dnc
	var nodes: Array = get_tree().get_nodes_in_group("day_night_cycle")
	if nodes.is_empty():
		return null
	_cached_dnc = nodes[0]
	return _cached_dnc


func _find_world_environment() -> WorldEnvironment:
	if _cached_env != null and is_instance_valid(_cached_env):
		return _cached_env
	# WorldEnvironment is always a child of the active scene root; by
	# convention in this project it's a direct child of World3D.
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	for child in root.get_children():
		if child is WorldEnvironment:
			_cached_env = child
			return _cached_env
	return null
