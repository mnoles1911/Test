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

# Active location profile. When null, _roll_random_state falls back to
# DEFAULT_RANDOM_DISTRIBUTION and SCHEDULE_TRANSITION_HOURS.
var _location_profile: WeatherLocationProfile = null


# ============================================================
# State
# ============================================================

# Trigger sources, applied in priority order in _resolve_active_state.
# -1 means "no override / no proximity zone active".
var _override_state: int = -1
var _override_hours_remaining: float = 0.0
# Proximity stack: array of {zone, state_id, priority}. The entry with
# highest priority wins. _proximity_state mirrors the resolved value
# so _resolve_active_state stays cheap.
var _proximity_stack: Array = []
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

# Particle systems. Spawned lazily on the first transition that needs
# them so a CLEAR-only world never builds the rigs. Position follows
# the active camera every frame.
var _rain_particles: GPUParticles3D = null
var _snow_particles: GPUParticles3D = null

# Wet-terrain visual layers (Phase 8).
# Layer A: full-screen blue-grey tint — RainOverlay child of WeatherManager.
# Layer B: StandardMaterial3D applied to VoxelLodTerrain.material_override
# during rain so wet stone reads with specular sheen + slight darkening.
var _rain_overlay: CanvasLayer = null
var _wet_terrain_material: StandardMaterial3D = null
# Tracks whether material_override has been applied. Avoids redundant
# writes every frame on a stable state.
var _wet_terrain_active: bool = false

# Ambient audio (Phase 10). One AudioStreamPlayer that crossfades on
# state change. Files live at res://assets/audio/ambient/{key}.ogg
# where key is the "ambient_audio" entry in STATE_PROFILES.
var _ambient_player: AudioStreamPlayer = null
var _ambient_player_next: AudioStreamPlayer = null   # destination of in-flight crossfade
var _ambient_current_key: String = ""
var _ambient_warned_missing: Dictionary = {}   # key -> true once warned
const AMBIENT_AUDIO_DIR: String = "res://assets/audio/ambient/"
const AMBIENT_CROSSFADE_S: float = 5.0
const AMBIENT_TARGET_DB: float = -8.0          # comfortable bed level

# How high above the camera the particle emitter sits (m). The
# particles fall from this height; tuning matters for "rain
# arriving from the sky" vs "rain spawning at face height".
const PARTICLE_HEIGHT_OFFSET: float = 8.0
# Half-extents of the emission box (m). Particles emit anywhere
# inside this, so the rain blanket roughly covers BOX_X*2 × BOX_Z*2 m
# around the player. 20 m matches typical voxel render distance.
const PARTICLE_EMISSION_BOX: Vector3 = Vector3(20.0, 0.0, 20.0)


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
	# Build the rain mood overlay once. Alpha 0 by default; we never
	# need to free it.
	var overlay_script := load("res://scripts/RainOverlay.gd")
	if overlay_script != null:
		_rain_overlay = overlay_script.new()
		_rain_overlay.name = "RainOverlay"
		add_child(_rain_overlay)
	# Wet-terrain material is also lazy — only built on first wet state.

	# Ambient audio bed — single AudioStreamPlayer at -80 dB. We
	# crossfade INTO this player and a second one we spawn on demand.
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AmbientAudio"
	_ambient_player.bus = "Master"
	_ambient_player.volume_db = -80.0
	add_child(_ambient_player)

	# Listen to our own state-changed signal so audio swaps fire only
	# on real state transitions (not every frame).
	weather_state_changed.connect(_on_weather_state_changed_for_audio)


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

	# Particle follow + amount ramp. Done every frame so the rain
	# blanket tracks the camera; amount is updated each frame from the
	# interpolated state so the particle count tweens smoothly with
	# the rest of the transition.
	_update_particles()

	# Wet-terrain layered visual (Phase 8). Both the screen tint and
	# the terrain material wetness ramp with the same "wetness"
	# fraction — currently rain density / max rain density.
	var wetness: float = lerpf(
		_state_wetness(current_state),
		_state_wetness(_target_state),
		_transition_progress)
	_update_wet_terrain_visual(wetness)

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


# Phase 11 hooks — WeatherZone calls these on entry/exit. Stack-based
# so multiple overlapping zones resolve by priority rather than fighting.
func push_proximity_zone(zone: Object, state_id: int, priority: int) -> void:
	# Replace any existing entry for this zone (re-entry, edge cases).
	for i in range(_proximity_stack.size() - 1, -1, -1):
		if _proximity_stack[i].zone == zone:
			_proximity_stack.remove_at(i)
	_proximity_stack.append({"zone": zone, "state_id": state_id, "priority": priority})
	_recompute_proximity_state()


func pop_proximity_zone(zone: Object) -> void:
	for i in range(_proximity_stack.size() - 1, -1, -1):
		if _proximity_stack[i].zone == zone:
			_proximity_stack.remove_at(i)
	_recompute_proximity_state()


func _recompute_proximity_state() -> void:
	var winner: int = -1
	var best_priority: int = -2147483648
	for entry in _proximity_stack:
		if int(entry.priority) > best_priority:
			best_priority = int(entry.priority)
			winner = int(entry.state_id)
	_proximity_state = winner
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
	_proximity_stack.clear()
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
	# The profile (if set) overrides the default hour list.
	var hours: Array = SCHEDULE_TRANSITION_HOURS
	if _location_profile != null and not _location_profile.transition_hours.is_empty():
		hours = _location_profile.transition_hours
	if not new_hour in hours:
		return
	_scheduled_state = _roll_state_for_today()
	_resolve_active_state()


func _roll_state_for_today() -> int:
	# If a profile is set and today (1-indexed) falls inside its
	# authored_sequence, use the authored entry deterministically.
	# Otherwise fall through to weighted random.
	if _location_profile != null:
		var day_idx: int = 0
		if get_node_or_null("/root/WorldClock") != null:
			day_idx = WorldClock.current_day - 1
		if day_idx >= 0 and day_idx < _location_profile.authored_sequence.size():
			return int(_location_profile.authored_sequence[day_idx])
	return _roll_random_state()


func _roll_random_state() -> int:
	# Weighted random pick. Profile overrides the default distribution.
	var dist: Dictionary = DEFAULT_RANDOM_DISTRIBUTION
	if _location_profile != null and not _location_profile.random_distribution.is_empty():
		dist = _location_profile.random_distribution
	var roll: float = randf()
	var cumulative: float = 0.0
	for state_id in dist.keys():
		cumulative += float(dist[state_id])
		if roll < cumulative:
			return int(state_id)
	return State.CLEAR


# Designer / region-transition hook. Pass null to clear.
func set_location_profile(profile: WeatherLocationProfile) -> void:
	_location_profile = profile


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
# Wet-terrain layered visual (Phase 8)
# ------------------------------------------------------------

# Maximum particle density we treat as 100% wet. Anything above this
# in a state's profile is clamped — keeps wetness in [0, 1].
const _MAX_WETNESS_DENSITY: float = 6000.0


func _state_wetness(state_id: int) -> float:
	# Rain states contribute wetness; everything else is dry.
	# Snow doesn't pre-wet stone (the world wouldn't read as "snowy
	# AND wet"); future polish could add a separate "frosty" channel.
	if state_id == State.LIGHT_RAIN or state_id == State.HEAVY_RAIN:
		var density: float = float(STATE_PROFILES[state_id]["particle_density"])
		return clampf(density / _MAX_WETNESS_DENSITY, 0.0, 1.0)
	return 0.0


func _update_wet_terrain_visual(wetness: float) -> void:
	# Layer A — screen tint always-on overlay.
	if _rain_overlay != null and _rain_overlay.has_method("set_intensity"):
		_rain_overlay.set_intensity(wetness)

	# Layer B — terrain material override. Apply once on the first
	# wet frame and animate albedo + roughness via the material's
	# properties. Remove it (set null) when wetness returns to 0 so
	# the default vertex-color rendering takes back over.
	var terrain: Node = _find_voxel_terrain()
	if terrain == null:
		return
	if not (terrain is GeometryInstance3D):
		# Some Zylann builds don't expose material_override; fall back
		# silently — Layer A still works.
		if not _wet_terrain_active and wetness <= 0.001:
			return
	if wetness <= 0.001:
		if _wet_terrain_active:
			(terrain as GeometryInstance3D).material_override = null
			_wet_terrain_active = false
		return

	if _wet_terrain_material == null:
		_wet_terrain_material = StandardMaterial3D.new()
		# vertex_color_use_as_albedo lets the underlying voxel-color
		# information through, so we still see grass-vs-stone tints.
		_wet_terrain_material.vertex_color_use_as_albedo = true
		_wet_terrain_material.metallic = 0.05

	# albedo darkens slightly with wetness; roughness drops so the sun
	# picks out a wet sheen on highlights.
	var darkening: float = lerpf(1.0, 0.85, wetness)
	_wet_terrain_material.albedo_color = Color(darkening, darkening, darkening, 1.0)
	_wet_terrain_material.roughness = lerpf(0.9, 0.3, wetness)

	if not _wet_terrain_active:
		(terrain as GeometryInstance3D).material_override = _wet_terrain_material
		_wet_terrain_active = true


# ------------------------------------------------------------
# Ambient audio (Phase 10)
# ------------------------------------------------------------

func _on_weather_state_changed_for_audio(new_state: int, _old_state: int) -> void:
	var key: String = String(STATE_PROFILES[new_state]["ambient_audio"])
	_swap_ambient_audio(key)


func _swap_ambient_audio(key: String) -> void:
	# Idempotent — if the new key matches what's already playing, no-op.
	if key == _ambient_current_key:
		return

	# Empty key (CLEAR has no ambient bed) — fade the current player
	# out to silence and stop it.
	if key.is_empty():
		_fade_player_out(_ambient_player)
		_ambient_current_key = ""
		return

	# Try to load the OGG. Missing files log once and silently skip.
	var path: String = AMBIENT_AUDIO_DIR + key + ".ogg"
	if not ResourceLoader.exists(path):
		if not _ambient_warned_missing.has(key):
			_ambient_warned_missing[key] = true
			push_warning("[WeatherManager] Missing ambient audio: %s — see DESIGNER_TODO.md" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return

	# Spawn a second player to take over; crossfade the two together.
	# When the fade-in completes, the old player gets queue_free'd.
	if _ambient_player_next != null and is_instance_valid(_ambient_player_next):
		_ambient_player_next.queue_free()
	_ambient_player_next = AudioStreamPlayer.new()
	_ambient_player_next.bus = "Master"
	_ambient_player_next.volume_db = -80.0
	_ambient_player_next.stream = stream
	add_child(_ambient_player_next)
	_ambient_player_next.play()

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_ambient_player_next, "volume_db", AMBIENT_TARGET_DB, AMBIENT_CROSSFADE_S)
	t.tween_property(_ambient_player, "volume_db", -80.0, AMBIENT_CROSSFADE_S)
	t.chain().tween_callback(_finalise_ambient_swap)
	_ambient_current_key = key


func _finalise_ambient_swap() -> void:
	# The old player has faded out. Free it, promote _next.
	if _ambient_player != null and is_instance_valid(_ambient_player):
		_ambient_player.queue_free()
	_ambient_player = _ambient_player_next
	_ambient_player_next = null


func _fade_player_out(p: AudioStreamPlayer) -> void:
	if p == null or not is_instance_valid(p):
		return
	var t := create_tween()
	t.tween_property(p, "volume_db", -80.0, AMBIENT_CROSSFADE_S)


func _find_voxel_terrain() -> Node:
	# VoxelLodTerrain isn't in a group by default; walk the scene root.
	# Cached after first hit so the per-frame cost is one is_instance_valid.
	if _cached_voxel_terrain != null and is_instance_valid(_cached_voxel_terrain):
		return _cached_voxel_terrain
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	for child in root.get_children():
		# Match by class name string so we don't need to import a class
		# that may not exist if Zylann isn't installed yet.
		if child.get_class() == "VoxelLodTerrain" or child.get_class() == "VoxelTerrain":
			_cached_voxel_terrain = child
			return child
	return null


var _cached_voxel_terrain: Node = null


# ------------------------------------------------------------
# Particles
# ------------------------------------------------------------

func _update_particles() -> void:
	# Active rain density (interpolated). Values < 1 act as "off".
	var prev_profile: Dictionary = STATE_PROFILES[current_state]
	var target_profile: Dictionary = STATE_PROFILES[_target_state]
	var t: float = _transition_progress

	# Rain — both LIGHT_RAIN and HEAVY_RAIN feed into the rain emitter.
	# We add the contributions from current_state and _target_state
	# weighted by the transition so rain ramps in/out smoothly.
	var rain_amount: int = int(round(lerpf(
		_state_rain_density(current_state),
		_state_rain_density(_target_state),
		t)))
	var snow_amount: int = int(round(lerpf(
		_state_snow_density(current_state),
		_state_snow_density(_target_state),
		t)))

	# Lazily build emitters the first time a non-zero amount is needed.
	if rain_amount > 0 and _rain_particles == null:
		_rain_particles = _build_rain_particles()
		add_child(_rain_particles)
	if snow_amount > 0 and _snow_particles == null:
		_snow_particles = _build_snow_particles()
		add_child(_snow_particles)

	# Position each emitter above the active camera. Emitters that are
	# sitting at amount = 0 still get repositioned so when they next
	# turn on, they don't dump particles in the wrong place.
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		var follow_pos: Vector3 = cam.global_position + Vector3(0.0, PARTICLE_HEIGHT_OFFSET, 0.0)
		if _rain_particles != null:
			_rain_particles.global_position = follow_pos
		if _snow_particles != null:
			_snow_particles.global_position = follow_pos

	if _rain_particles != null:
		_rain_particles.amount = maxi(1, rain_amount)
		_rain_particles.emitting = rain_amount > 0
		# Wind drift writes directly to the particle process material's
		# gravity vector; the result is rain that visibly slants when
		# the wind is strong.
		_apply_wind_to_particles(_rain_particles, _live_wind_strength * 0.3)

	if _snow_particles != null:
		_snow_particles.amount = maxi(1, snow_amount)
		_snow_particles.emitting = snow_amount > 0
		# Snow drifts more than rain at the same wind strength
		# because the lifetime is much longer; multiplier stays small.
		_apply_wind_to_particles(_snow_particles, _live_wind_strength * 0.5)


func _state_rain_density(state_id: int) -> float:
	if state_id == State.LIGHT_RAIN or state_id == State.HEAVY_RAIN:
		return float(STATE_PROFILES[state_id]["particle_density"])
	return 0.0


func _state_snow_density(state_id: int) -> float:
	if state_id == State.SNOW:
		return float(STATE_PROFILES[state_id]["particle_density"])
	return 0.0


func _build_rain_particles() -> GPUParticles3D:
	# Programmatic rain rig. Vertical line meshes falling at high speed
	# inside a 40×40 m box centred on (and following) the camera.
	var p := GPUParticles3D.new()
	p.name = "RainParticles"
	p.amount = 1
	p.lifetime = 0.6
	p.preprocess = 0.3   # so particles are present on first frame
	p.fixed_fps = 30
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = PARTICLE_EMISSION_BOX
	mat.gravity = Vector3(0.0, -25.0, 0.0)
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.scale_min = 0.6
	mat.scale_max = 1.0
	mat.color = Color(0.6, 0.7, 0.85, 0.55)
	p.process_material = mat

	# Thin vertical streak — a tall narrow quad is the cheapest
	# representation that still reads as falling rain at speed.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.02, 0.35)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.7, 0.8, 0.95, 0.75)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.billboard_keep_scale = true
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh
	return p


func _build_snow_particles() -> GPUParticles3D:
	# Snow falls slowly with longer lifetime and a softer particle.
	var p := GPUParticles3D.new()
	p.name = "SnowParticles"
	p.amount = 1
	p.lifetime = 4.0
	p.preprocess = 2.0
	p.fixed_fps = 30
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = PARTICLE_EMISSION_BOX
	mat.gravity = Vector3(0.0, -1.5, 0.0)
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.2
	mat.scale_min = 0.04
	mat.scale_max = 0.08
	mat.color = Color(1.0, 1.0, 1.0, 0.9)
	p.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.18, 0.18)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.billboard_keep_scale = true
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh
	return p


func _apply_wind_to_particles(p: GPUParticles3D, drift_factor: float) -> void:
	# Bias the gravity vector horizontally so falling particles slant
	# in the wind direction. The vertical component stays the dominant
	# force; horizontal is only ~drift_factor m/s² of nudge.
	var mat := p.process_material as ParticleProcessMaterial
	if mat == null:
		return
	var base_g: Vector3 = mat.gravity
	var horizontal: Vector3 = wind_direction * drift_factor
	mat.gravity = Vector3(horizontal.x, base_g.y, horizontal.z)


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
