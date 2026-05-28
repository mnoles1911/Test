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
		"cloud_coverage":   0.0,
		"cloud_speed":      0.012,
		# Multiplier on the sun's BASELINE light_volumetric_fog_energy
		# (snapshot once at _ready from the scene-shipped value, then
		# multiplied per tick by the live god_ray_multiplier). Phase K
		# bundle 2026-05-27. 1.5 = sharp shafts in clear weather (the
		# scene's "intended" look bumped a bit because clear sky has
		# the most light to scatter). Respected only when
		# GraphicsManager.is_effect_enabled("light_shafts") = true.
		# Phase K bundle v2 (2026-05-27): bumped 1.5 → 3.5 after designer
		# report: "I cant really tell. either its not working or its not
		# strong enough to see. I wanted god light rays coming down from
		# the sun." 1.5 was a perceptually-modest boost above the scene
		# baseline; 3.5 produces visibly volumetric shafts in CLEAR
		# weather without changing the ambient lighting curve (which
		# DayNightCycle owns independently).
		"god_ray_multiplier": 3.5,
	},
	State.OVERCAST: {
		"fog_color":        Color(0.6, 0.65, 0.7),
		"fog_density":      0.01,
		"ambient_dim":      0.85,
		"wind_strength":    1.0,
		"particle_density": 0,
		"ambient_audio":    "wind_med",
		"cloud_coverage":   0.92,
		"cloud_speed":      0.04,
		"god_ray_multiplier": 0.6,  # heavy cloud cover → diffused, modest shafts
	},
	State.LIGHT_RAIN: {
		"fog_color":        Color(0.55, 0.6, 0.65),
		"fog_density":      0.02,
		"ambient_dim":      0.75,
		"wind_strength":    1.5,
		"particle_density": 1500,
		"ambient_audio":    "rain_light",
		"cloud_coverage":   0.6,
		"cloud_speed":      0.05,
		"god_ray_multiplier": 0.3,  # mostly diffused through rain particles
	},
	State.HEAVY_RAIN: {
		"fog_color":        Color(0.4, 0.45, 0.5),
		"fog_density":      0.04,
		"ambient_dim":      0.55,
		"wind_strength":    3.5,
		"particle_density": 6000,
		"ambient_audio":    "rain_heavy",
		"cloud_coverage":   1.0,
		"cloud_speed":      0.08,
		"god_ray_multiplier": 0.0,  # no shafts in a downpour
	},
	State.FOG: {
		"fog_color":        Color(0.75, 0.75, 0.78),
		"fog_density":      0.08,
		"ambient_dim":      0.7,
		"wind_strength":    0.3,
		"particle_density": 0,
		"ambient_audio":    "wind_low",
		"cloud_coverage":   0.35,
		"cloud_speed":      0.01,
		"god_ray_multiplier": 0.4,  # some scatter through the fog volume
	},
	State.SNOW: {
		"fog_color":        Color(0.85, 0.88, 0.92),
		"fog_density":      0.03,
		"ambient_dim":      0.9,
		"wind_strength":    1.2,
		"particle_density": 2500,
		"ambient_audio":    "wind_low",
		"cloud_coverage":   0.75,
		"cloud_speed":      0.03,
		"god_ray_multiplier": 0.5,  # snow sparkles in sun shafts
	},
}


# ============================================================
# Tunables
# ============================================================

# How long it takes to interpolate from one state's profile values to
# another. 30 s feels organic — fast enough that the player notices
# the change happening, slow enough that it never feels jarring.
const TRANSITION_DURATION_S: float = 30.0

# Heavy interpolation work in _process_inner is gated to 10 Hz so the
# manager stops eating ~22 µs every render frame. With weather
# transitions spanning 30 s and wind drift in degrees-per-second, a
# 100 ms tick is well below the visible-change threshold. Accumulated
# delta is passed through so timer-driven logic stays correct.
const STATE_TICK_INTERVAL_S: float = 0.1

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
var _state_tick_accumulator: float = 0.0

# Default state lock — when true, _roll_state_for_today always returns
# CLEAR, bypassing both authored sequences and weighted random rolls.
# set_weather_override() and proximity zones still work for manually-
# driven non-CLEAR states. Defaults true so the dev/test environment
# stays predictable; flip to false when shipping a scene that wants
# the scheduled weather system live (or call disable_clear_default()).
@export var force_clear_default: bool = true


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
var _live_wetness: float = 0.0
var _live_rain_density: float = 0.0
var _live_snow_density: float = 0.0
var _live_cloud_coverage: float = STATE_PROFILES[State.CLEAR]["cloud_coverage"]
var _live_cloud_speed: float = STATE_PROFILES[State.CLEAR]["cloud_speed"]
var _live_god_ray_multiplier: float = STATE_PROFILES[State.CLEAR]["god_ray_multiplier"]  # Phase K bundle 2026-05-27

# Rainbow-after-rain (Phase K bundle, 2026-05-27).
# State machine: detect a transition rainy → CLEAR/OVERCAST, ramp
# rainbow_factor 0 → 1 over RAMP_UP_S, hold for HOLD_S, ramp 1 → 0
# over RAMP_DOWN_S, idle. Pushed to global shader parameter
# `rainbow_factor` (declared in project.godot [shader_globals]).
# sky_atmosphere.gdshader reads it and renders the rainbow arc.
const RAINBOW_RAMP_UP_S: float = 30.0
const RAINBOW_HOLD_S: float = 60.0
const RAINBOW_RAMP_DOWN_S: float = 60.0
enum RainbowState { IDLE, RAMPING_UP, HOLDING, RAMPING_DOWN }
var _rainbow_state: int = RainbowState.IDLE
var _rainbow_factor: float = 0.0
var _rainbow_elapsed: float = 0.0
var _rainbow_log_accum: float = 0.0  # 1 Hz log throttle
# Sun light_volumetric_fog_energy baseline — snapshot at first apply
# from the scene-shipped sun. The per-state god_ray_multiplier is a
# MULTIPLIER on this baseline, not an absolute. snapshot exists so we
# can restore the baseline if the player turns light_shafts off via
# the DebugOverlay GRAPHICS sub-view.
var _sun_baseline_volfog_energy: float = -1.0  # -1 = not yet snapshotted

# Blend origins for the transition tween. Snapshotted from _live_* every
# time the target state changes. Without this, mid-transition target
# changes (A→B then B→A while halfway through the first tween) snap
# the visuals back to the original state's profile values before
# re-tweening, producing a visible jump. With the snapshot, every
# transition starts from "where the visuals are right now" and walks
# smoothly to the new target.
var _blend_origin_fog_color: Color = STATE_PROFILES[State.CLEAR]["fog_color"]
var _blend_origin_fog_density: float = STATE_PROFILES[State.CLEAR]["fog_density"]
var _blend_origin_ambient_dim: float = 1.0
var _blend_origin_wind_strength: float = STATE_PROFILES[State.CLEAR]["wind_strength"]
var _blend_origin_wetness: float = 0.0
var _blend_origin_rain_density: float = 0.0
var _blend_origin_snow_density: float = 0.0
var _blend_origin_cloud_coverage: float = STATE_PROFILES[State.CLEAR]["cloud_coverage"]
var _blend_origin_cloud_speed: float = STATE_PROFILES[State.CLEAR]["cloud_speed"]
var _blend_origin_god_ray_multiplier: float = STATE_PROFILES[State.CLEAR]["god_ray_multiplier"]  # Phase K bundle 2026-05-27

# Particle systems. Spawned lazily on the first transition that needs
# them so a CLEAR-only world never builds the rigs. Position follows
# the active camera every frame.
var _rain_particles: GPUParticles3D = null
var _snow_particles: GPUParticles3D = null
# Last gravity vector pushed to each particle process material. Skipping
# redundant writes saves a per-frame GPU buffer rebuild.
var _rain_last_gravity: Vector3 = Vector3.ZERO
var _snow_last_gravity: Vector3 = Vector3.ZERO

# Wet-terrain visual layers (Phase 8).
# Layer A: full-screen blue-grey tint — RainOverlay child of WeatherManager.
# Layer B: StandardMaterial3D applied to VoxelLodTerrain.material_override
# during rain so wet stone reads with specular sheen + slight darkening.
var _rain_overlay: CanvasLayer = null
var _wet_terrain_material: StandardMaterial3D = null
# Tracks whether material_override has been applied. Avoids redundant
# writes every frame on a stable state.
var _wet_terrain_active: bool = false

# Ambient audio (Phase 10). _ambient_player advances synchronously to
# the active state's player; outgoing players each get their own
# fade-out tween that queue_frees them when done. No shared finaliser,
# so rapid swaps can't race on a single _finalise callback.
var _ambient_player: AudioStreamPlayer = null
var _ambient_current_key: String = ""
var _ambient_warned_missing: Dictionary = {}   # key -> true once warned
# Wind-gust state. _ambient_settle_timer counts down the crossfade so
# gust modulation only takes over once the fade-in tween has finished.
var _ambient_settle_timer: float = 0.0
var _ambient_gust_time: float = 0.0
const AMBIENT_AUDIO_DIR: String = "res://assets/audio/ambient/"
const AMBIENT_CROSSFADE_S: float = 30.0  # Phase K bundle 2026-05-27: was 5s; designer report — audio finished fading in ~5s while the visual transition took 30s, reading as "audio jumps instantly." Match the visual TRANSITION_DURATION_S so the bed crossfade and the visual lerp stay in sync.
const AMBIENT_TARGET_DB: float = -8.0          # comfortable bed level
# Wind ambience gusts — the wind bed's volume swells and lulls instead
# of droning flat. Depth in dB the volume dips below AMBIENT_TARGET_DB
# at the bottom of a lull.
const WIND_GUST_DEPTH_DB: float = 14.0

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

	# Audio: no initial player needed. Swaps spawn a player on demand;
	# fade-out tweens queue_free outgoing players. Empty key (CLEAR)
	# means no ambient bed at all.

	# Seed the scheduled state immediately so Aldenholt's authored
	# day-1 weather (or the global random distribution) takes effect on
	# world load — without this, the world stays forced-CLEAR until the
	# first transition hour [6, 12, 18] passes (up to 4 in-game hours
	# of nothing-happens with WorldClock starting at hour 8).
	_seed_initial_state()


# Snaps state machine + blend origins + audio to the rolled scheduled
# state without playing the 30 s transition tween. Used on world load
# so the initial frame already has correct atmosphere.
func _seed_initial_state() -> void:
	_scheduled_state = _roll_state_for_today()
	current_state = _scheduled_state
	_target_state = _scheduled_state
	_transition_progress = 1.0
	# Initialise live + blend-origin values to the seeded state's
	# profile so the first _process tick reads consistent values
	# rather than CLEAR defaults.
	var profile: Dictionary = STATE_PROFILES[current_state]
	_live_fog_color = profile["fog_color"]
	_live_fog_density = profile["fog_density"]
	_live_ambient_dim = profile["ambient_dim"]
	_live_wind_strength = profile["wind_strength"]
	_live_wetness = _state_wetness(current_state)
	_live_rain_density = _state_rain_density(current_state)
	_live_snow_density = _state_snow_density(current_state)
	_live_cloud_coverage = profile["cloud_coverage"]
	_live_cloud_speed = profile["cloud_speed"]
	_live_god_ray_multiplier = profile.get("god_ray_multiplier", 1.0)  # Phase K bundle 2026-05-27
	_snapshot_blend_origins()
	# Kick the audio crossfade off so the seeded state has its bed.
	_swap_ambient_audio(String(profile["ambient_audio"]))


func _snapshot_blend_origins() -> void:
	# Capture every interpolated value as the new "from" point of the
	# transition. Called when target changes mid-flight so the next
	# tween starts from where the visuals are RIGHT NOW.
	_blend_origin_fog_color = _live_fog_color
	_blend_origin_fog_density = _live_fog_density
	_blend_origin_ambient_dim = _live_ambient_dim
	_blend_origin_wind_strength = _live_wind_strength
	_blend_origin_wetness = _live_wetness
	_blend_origin_rain_density = _live_rain_density
	_blend_origin_snow_density = _live_snow_density
	_blend_origin_cloud_coverage = _live_cloud_coverage
	_blend_origin_cloud_speed = _live_cloud_speed
	_blend_origin_god_ray_multiplier = _live_god_ray_multiplier  # Phase K bundle 2026-05-27


func _process(delta: float) -> void:
	# Accumulate delta; only run the heavy interpolation body at 10 Hz.
	# All deltas-based logic inside _process_inner receives the
	# accumulated delta, so transition progress / wind drift / lightning
	# countdown remain frame-rate-independent.
	_state_tick_accumulator += delta
	if _state_tick_accumulator < STATE_TICK_INTERVAL_S:
		return
	var ticked_delta: float = _state_tick_accumulator
	_state_tick_accumulator = 0.0

	# Profiling wrapper — feeds the in-HUD [PERF] log + F3 Profiler overlay.
	var _t0_prof: int = Time.get_ticks_usec()
	_process_inner(ticked_delta)
	var _elapsed: int = Time.get_ticks_usec() - _t0_prof
	HUDOverlay.profile_record("WeatherManager", _elapsed)
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WEATHER", "WeatherManager", _elapsed)


func _process_inner(delta: float) -> void:
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

	# Interpolate live values from the snapshotted blend origin toward
	# the target profile. Using the snapshot (instead of
	# STATE_PROFILES[current_state]) means a mid-transition target
	# change starts the new tween from "where we are right now," not
	# from the original from-state's profile values — no visible snap.
	var target_profile: Dictionary = STATE_PROFILES[_target_state]
	var t: float = _transition_progress
	_live_fog_color = _blend_origin_fog_color.lerp(target_profile["fog_color"], t)
	_live_fog_density = lerpf(_blend_origin_fog_density, target_profile["fog_density"], t)
	_live_ambient_dim = lerpf(_blend_origin_ambient_dim, target_profile["ambient_dim"], t)
	_live_wind_strength = lerpf(_blend_origin_wind_strength, target_profile["wind_strength"], t)
	_live_wetness = lerpf(_blend_origin_wetness, _state_wetness(_target_state), t)
	_live_rain_density = lerpf(_blend_origin_rain_density, _state_rain_density(_target_state), t)
	_live_snow_density = lerpf(_blend_origin_snow_density, _state_snow_density(_target_state), t)
	_live_cloud_coverage = lerpf(_blend_origin_cloud_coverage, target_profile["cloud_coverage"], t)
	_live_cloud_speed = lerpf(_blend_origin_cloud_speed, target_profile["cloud_speed"], t)
	_live_god_ray_multiplier = lerpf(
		_blend_origin_god_ray_multiplier,
		float(target_profile.get("god_ray_multiplier", 1.0)),
		t)
	weather_intensity_changed.emit(_live_wetness)

	# Push fog into DayNightCycle's override slot. We try to find the
	# DayNightCycle node by group; the script in World3D.tscn registers
	# itself in "day_night_cycle" on _ready (Phase 1 hook).
	var dnc: Node = _find_day_night_cycle()
	if dnc != null and dnc.has_method("set_fog_override"):
		dnc.set_fog_override(_live_fog_color, _live_fog_density)
	# Push weather-driven cloud coverage + drift speed into the sky
	# shader (Phase H + the 2026-05-21 weather-driven-clouds pass).
	if dnc != null and dnc.has_method("set_cloud_coverage"):
		dnc.set_cloud_coverage(_live_cloud_coverage)
	if dnc != null and dnc.has_method("set_cloud_speed"):
		dnc.set_cloud_speed(_live_cloud_speed)

	# Push ambient light directly to WorldEnvironment.environment. We
	# don't go through DayNightCycle here because DayNightCycle never
	# touches ambient — only fog and sky. Writing it here every frame
	# is fine; WorldEnvironment treats the property as a simple float.
	var env_node: WorldEnvironment = _find_world_environment()
	if env_node != null and env_node.environment != null:
		env_node.environment.ambient_light_energy = _live_ambient_dim

	# Phase K bundle (2026-05-27): light shafts per weather state.
	# Multiply the sun's BASELINE light_volumetric_fog_energy (snapshot
	# once from the scene-shipped value) by the live god_ray_multiplier.
	# Respects GraphicsManager.is_effect_enabled("light_shafts"): when
	# false, restore the baseline directly so the sun's god ray energy
	# returns to scene defaults. UnderwaterFilter's on-submerge override
	# of the same property is independent — it overwrites this each
	# frame the camera is under water and our write re-applies the
	# moment the camera surfaces. No coordination needed.
	_apply_light_shafts_to_sun()

	# Phase K bundle (2026-05-27): rainbow-after-rain factor tick. Pure
	# state machine driven by elapsed time; pushes to the
	# `rainbow_factor` global shader parameter every frame (declared in
	# project.godot [shader_globals], read by sky_atmosphere.gdshader).
	_tick_rainbow(delta)

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
	# blanket tracks the camera; amount uses the interpolated _live_*
	# values so the particle count tweens smoothly with the rest of
	# the transition (and never snaps on mid-transition target change).
	_update_particles()

	# Wet-terrain layered visual (Phase 8). Both the screen tint and
	# the terrain material use _live_wetness, which is interpolated
	# from the blend origin so it never snaps either.
	_update_wet_terrain_visual(_live_wetness)

	# Lightning strike timer — only ticks during HEAVY_RAIN.
	_process_lightning(delta)

	# Wind ambience gusts — swell/lull the wind bed instead of a drone.
	_update_wind_gust(delta)

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
	# Drop entries whose zone has been freed (scene change without
	# explicit pop_proximity_zone). Without this, scene transitions
	# leak stale entries that hold the wrong state forever.
	for i in range(_proximity_stack.size() - 1, -1, -1):
		if not is_instance_valid(_proximity_stack[i].zone):
			_proximity_stack.remove_at(i)

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
	# Sync live values + blend origins to the loaded current_state's
	# profile so the first frame after load reads consistent values
	# rather than stale ones from before the load.
	var profile: Dictionary = STATE_PROFILES[current_state]
	_live_fog_color = profile["fog_color"]
	_live_fog_density = profile["fog_density"]
	_live_ambient_dim = profile["ambient_dim"]
	_live_wind_strength = profile["wind_strength"]
	_live_wetness = _state_wetness(current_state)
	_live_rain_density = _state_rain_density(current_state)
	_live_snow_density = _state_snow_density(current_state)
	_live_cloud_coverage = profile["cloud_coverage"]
	_live_cloud_speed = profile["cloud_speed"]
	_live_god_ray_multiplier = profile.get("god_ray_multiplier", 1.0)  # Phase K bundle 2026-05-27
	_snapshot_blend_origins()


func clear_persistent_state() -> void:
	current_state = State.CLEAR
	_target_state = State.CLEAR
	_scheduled_state = State.CLEAR
	_override_state = -1
	_override_hours_remaining = 0.0
	_proximity_state = -1
	_proximity_stack.clear()
	_transition_progress = 1.0
	# Reset live + blend-origin values to CLEAR profile.
	var profile: Dictionary = STATE_PROFILES[State.CLEAR]
	_live_fog_color = profile["fog_color"]
	_live_fog_density = profile["fog_density"]
	_live_ambient_dim = profile["ambient_dim"]
	_live_wind_strength = profile["wind_strength"]
	_live_wetness = 0.0
	_live_rain_density = 0.0
	_live_snow_density = 0.0
	_live_cloud_coverage = profile["cloud_coverage"]
	_live_cloud_speed = profile["cloud_speed"]
	_live_god_ray_multiplier = profile.get("god_ray_multiplier", 1.0)  # Phase K bundle 2026-05-27
	_snapshot_blend_origins()


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

	# Snapshot the live values as the new blend origin so the next
	# tween starts from "where we are right now" rather than snapping
	# back to the original from-state's profile values. current_state
	# stays as the formal "from" for reporting purposes; the lerp
	# itself reads from _blend_origin_*.
	_snapshot_blend_origins()
	# Phase K bundle (2026-05-27): if we're leaving a rainy state for a
	# clearer one, kick off the rainbow-after-rain ramp. Skipped if a
	# rainbow is already in flight (a flicker rain → clear → rain → clear
	# inside ~150s shouldn't reset it from scratch — keep the existing
	# arc fading naturally).
	var was_rainy: bool = _target_state == State.LIGHT_RAIN or _target_state == State.HEAVY_RAIN
	var becoming_clear: bool = resolved == State.CLEAR or resolved == State.OVERCAST
	if was_rainy and becoming_clear and _rainbow_state == RainbowState.IDLE:
		_rainbow_state = RainbowState.RAMPING_UP
		_rainbow_elapsed = 0.0
		print("[WeatherManager] Rainbow starting (rain → clear transition).")
	_target_state = resolved
	_transition_progress = 0.0
	# Kick the audio crossfade off NOW so it lines up with the start
	# of the 30 s visual transition (audio crossfade itself is 5 s).
	var key: String = String(STATE_PROFILES[_target_state]["ambient_audio"])
	_swap_ambient_audio(key)


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
	# Default-lock: when force_clear_default is true, the schedule
	# always picks CLEAR. Manual overrides (set_weather_override,
	# proximity zones) still resolve normally on top of this.
	if force_clear_default:
		return State.CLEAR
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


# Designer / region-transition hook. Pass null to clear. Re-rolls the
# scheduled state immediately so the new profile takes visible effect
# without waiting for the next transition_hour.
func set_location_profile(profile: WeatherLocationProfile) -> void:
	_location_profile = profile
	_scheduled_state = _roll_state_for_today()
	_resolve_active_state()


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
		# Zylann's VoxelLodTerrain extends VoxelNode → Node3D, NOT
		# GeometryInstance3D, so `material_override` doesn't exist on
		# it. Layer A (the RainOverlay screen tint) already ran above
		# and gives us the wet-look feedback; just return.
		#
		# Earlier this branch only returned when wetness was already
		# near zero, then fell through to the cast on line below. The
		# `as` cast on a non-GeometryInstance3D returned null and the
		# next assignment crashed with "assignment of property...
		# 'material_override'... on a base object of type 'Nil'".
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

func _swap_ambient_audio(key: String) -> void:
	# Idempotent — if the new key matches what's already playing, no-op.
	if key == _ambient_current_key:
		return
	_ambient_current_key = key

	# A new bed is crossfading in — hold gust modulation off until the
	# fade-in tween has settled (see _update_wind_gust).
	_ambient_settle_timer = AMBIENT_CROSSFADE_S

	# Capture the outgoing player. _ambient_player advances to the new
	# one (or null) immediately; the captured reference gets its own
	# fade-out tween. Each tween operates on its own bound players, so
	# rapid swaps spawn independent tweens that never race on shared
	# state. The previous design used a shared _finalise_ambient_swap
	# callback that could run twice on rapid swaps and null out the
	# active player.
	var outgoing: AudioStreamPlayer = _ambient_player
	var incoming: AudioStreamPlayer = null

	# Empty key (CLEAR) → no incoming player; just fade the outgoing
	# one to silence and queue_free it.
	if not key.is_empty():
		var path: String = AMBIENT_AUDIO_DIR + key + ".ogg"
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			if stream != null:
				incoming = AudioStreamPlayer.new()
				incoming.bus = "Master"
				incoming.volume_db = -80.0
				incoming.stream = stream
				add_child(incoming)
				incoming.play()
		elif not _ambient_warned_missing.has(key):
			_ambient_warned_missing[key] = true
			push_warning("[WeatherManager] Missing ambient audio: %s — see DESIGNER_TODO.md" % path)

	_ambient_player = incoming

	# Fade in the new player, if any. Independent tween — no shared
	# state with the fade-out.
	if incoming != null:
		var fade_in := create_tween()
		fade_in.tween_property(incoming, "volume_db", AMBIENT_TARGET_DB, AMBIENT_CROSSFADE_S)

	# Fade out the outgoing player on its own tween that queue_frees it
	# at the end. The captured `outgoing` reference is bound to this
	# tween only — even if more swaps fire before this completes, this
	# tween still queue_frees its specific outgoing player.
	if outgoing != null and is_instance_valid(outgoing):
		var fade_out := create_tween()
		fade_out.tween_property(outgoing, "volume_db", -80.0, AMBIENT_CROSSFADE_S)
		fade_out.tween_callback(outgoing.queue_free)


func _update_wind_gust(delta: float) -> void:
	# Make the wind ambience swell and lull in bursts rather than
	# droning at a flat volume. Only runs once the crossfade has
	# settled, and only for wind beds (rain stays steady).
	if _ambient_settle_timer > 0.0:
		_ambient_settle_timer -= delta
		return
	if _ambient_player == null or not is_instance_valid(_ambient_player):
		return
	if not _ambient_current_key.begins_with("wind"):
		return
	_ambient_gust_time += delta
	var t: float = _ambient_gust_time
	# Summed slow sines -> an irregular -1..1 swell.
	var raw: float = sin(t * 0.13) * 0.5 + sin(t * 0.29 + 1.7) * 0.3 + sin(t * 0.61 + 4.1) * 0.2
	var g01: float = clampf((raw + 1.0) * 0.5, 0.0, 1.0)
	# Bias toward the low end so the loud swells read as gusts/bursts.
	g01 = pow(g01, 1.8)
	_ambient_player.volume_db = AMBIENT_TARGET_DB - WIND_GUST_DEPTH_DB + g01 * WIND_GUST_DEPTH_DB


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
# Lightning + thunder (Phase 12)
# ------------------------------------------------------------

# Time between strikes is randomised in [MIN, MAX]. Only ticks during
# HEAVY_RAIN; out of state, the timer is paused.
const LIGHTNING_INTERVAL_MIN_S: float = 8.0
const LIGHTNING_INTERVAL_MAX_S: float = 20.0
# Strike distance from the player on the XZ plane. Small range so the
# strike is always perceptible but never feels right next to the player.
const LIGHTNING_DIST_MIN_M: float = 80.0
const LIGHTNING_DIST_MAX_M: float = 250.0
# How high above the player the strike point sits. Sky-high so the
# directional light source feels like it's coming "from the clouds".
const LIGHTNING_STRIKE_HEIGHT_M: float = 60.0
# Speed of sound — used to delay the thunder audio after the visible
# flash. 343 m/s is real-world dry-air speed.
const SPEED_OF_SOUND_M_PER_S: float = 343.0

var _next_lightning_in_s: float = 0.0
var _lightning_armed: bool = false   # true while current_state is HEAVY_RAIN


func _process_lightning(delta: float) -> void:
	# Arm or disarm based on current state. We use current_state (not
	# _target_state) so lightning starts when HEAVY_RAIN actually
	# becomes visible, not when the transition begins.
	var should_arm: bool = (current_state == State.HEAVY_RAIN)
	if should_arm and not _lightning_armed:
		_lightning_armed = true
		_next_lightning_in_s = randf_range(LIGHTNING_INTERVAL_MIN_S, LIGHTNING_INTERVAL_MAX_S)
	elif not should_arm and _lightning_armed:
		_lightning_armed = false

	if not _lightning_armed:
		return

	_next_lightning_in_s -= delta
	if _next_lightning_in_s <= 0.0:
		trigger_lightning_strike()
		_next_lightning_in_s = randf_range(LIGHTNING_INTERVAL_MIN_S, LIGHTNING_INTERVAL_MAX_S)


func trigger_lightning_strike(strike_pos: Vector3 = Vector3(NAN, NAN, NAN)) -> void:
	# Public API — Phase 3a debug overlay calls this for FORCE LIGHTNING.
	# Default arg uses NAN sentinel; if any component is NaN, sample a
	# random position around the player.
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	var player_pos: Vector3 = cam.global_position
	if is_nan(strike_pos.x) or is_nan(strike_pos.y) or is_nan(strike_pos.z):
		var angle: float = randf() * TAU
		var dist: float = randf_range(LIGHTNING_DIST_MIN_M, LIGHTNING_DIST_MAX_M)
		strike_pos = player_pos + Vector3(cos(angle) * dist, LIGHTNING_STRIKE_HEIGHT_M, sin(angle) * dist)

	_spawn_lightning_flash(strike_pos)
	_spawn_thunder_audio(strike_pos, player_pos)


func _spawn_lightning_flash(strike_pos: Vector3) -> void:
	# Transient OmniLight3D. High energy, large range so the side of
	# the world facing the strike brightens visibly more than the
	# opposite side — that's what gives the directional cue.
	#
	# IMPORTANT: add_child() must come BEFORE assigning global_position.
	# Node3D.global_position resolves the world transform by walking up
	# the parent chain; outside the tree there's no parent, so the
	# assignment errors with "is_inside_tree() is true. Returning:
	# Transform3D()" and the light spawns at world origin. Light
	# properties (color, energy, range) are local state and CAN be
	# set before tree entry, so we keep those before add_child for
	# clarity.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 1.0, 1.0, 1.0)
	light.light_energy = 0.0
	light.omni_range = 300.0
	light.omni_attenuation = 1.0
	add_child(light)
	light.global_position = strike_pos

	# Energy curve: 0 → 30 over 40 ms (snap on), hold 80 ms, fade to 0
	# over 250 ms. queue_free at the end of the tween.
	var t := create_tween()
	t.tween_property(light, "light_energy", 30.0, 0.04)
	t.tween_interval(0.08)
	t.tween_property(light, "light_energy", 0.0, 0.25)
	t.tween_callback(light.queue_free)


func _spawn_thunder_audio(strike_pos: Vector3, listener_pos: Vector3) -> void:
	# Try to load a thunder OGG. If absent, skip silently — Phase 10
	# already logs missing-audio warnings on a different path; thunder
	# is rare enough that one warning per session is fine.
	var path: String = AMBIENT_AUDIO_DIR + "thunder_distant.ogg"
	if not ResourceLoader.exists(path):
		if not _ambient_warned_missing.has("thunder_distant"):
			_ambient_warned_missing["thunder_distant"] = true
			push_warning("[WeatherManager] Missing thunder audio: %s" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return

	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.global_position = strike_pos
	p.unit_size = 25.0
	p.max_distance = 500.0
	# Real-world delay between flash and rumble. 80 m → 0.23 s,
	# 250 m → 0.73 s. Plus a 0–0.5 s natural jitter for variety.
	var distance_m: float = listener_pos.distance_to(strike_pos)
	var delay_s: float = distance_m / SPEED_OF_SOUND_M_PER_S + randf_range(0.0, 0.5)
	add_child(p)

	# Wait `delay_s` then play. Free on finish.
	var t := create_tween()
	t.tween_interval(delay_s)
	t.tween_callback(p.play)
	# Best-effort cleanup — we connect finished, but also queue a
	# safety queue_free after a generous 12 s so a missed signal
	# doesn't leak the player.
	p.finished.connect(p.queue_free)
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


# ------------------------------------------------------------
# Particles
# ------------------------------------------------------------

func _update_particles() -> void:
	# Particle counts come straight from the live interpolated values
	# (already lerped from blend origin to target). _live_*_density is
	# updated each frame in _process; this function just rounds them.
	var rain_amount: int = int(round(_live_rain_density))
	var snow_amount: int = int(round(_live_snow_density))

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
	# Phase K bundle (2026-05-27). Designer report: aiming the camera DOWN
	# made rain particles disappear. Cause: Godot frustum-culls GPUParticles3D
	# by the node's `visibility_aabb`; without an explicit one, the auto-
	# computed AABB matches only the emitter region. With local_coords=false
	# the falling particles travel ~15 m below the emitter (gravity -25,
	# lifetime 0.6 → 15 m fall), but the auto-AABB doesn't extend to cover
	# the fall extent. When the camera pitch + position puts the emitter
	# behind the frustum, the whole particle system is culled — rain
	# vanishes even though the player is still IN it. Fix: set an explicit
	# generous AABB covering the full emission + fall volume around the
	# emitter so culling only happens when the player is genuinely 100 m+
	# away (which can't happen — emitter follows the camera).
	p.visibility_aabb = AABB(
		Vector3(-PARTICLE_EMISSION_BOX.x - 5.0, -25.0, -PARTICLE_EMISSION_BOX.z - 5.0),
		Vector3((PARTICLE_EMISSION_BOX.x + 5.0) * 2.0, 35.0, (PARTICLE_EMISSION_BOX.z + 5.0) * 2.0))

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
	# Phase K bundle (2026-05-27). Same visibility_aabb fix as
	# _build_rain_particles — snow also disappears on aim-down without
	# an explicit AABB. Snow falls only -1.5 × 4 = 6 m below the emitter
	# so the AABB Y-extent can be smaller than rain's.
	p.visibility_aabb = AABB(
		Vector3(-PARTICLE_EMISSION_BOX.x - 5.0, -8.0, -PARTICLE_EMISSION_BOX.z - 5.0),
		Vector3((PARTICLE_EMISSION_BOX.x + 5.0) * 2.0, 18.0, (PARTICLE_EMISSION_BOX.z + 5.0) * 2.0))

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
	#
	# Skip the write if the new vector is within 0.05 m/s² of the last
	# pushed value. ParticleProcessMaterial property writes dirty the
	# GPU buffer, so per-frame writes (with wind drifting at 3°/s)
	# trigger needless rebuilds.
	var mat := p.process_material as ParticleProcessMaterial
	if mat == null:
		return
	var base_g: Vector3 = mat.gravity
	var horizontal: Vector3 = wind_direction * drift_factor
	var new_g: Vector3 = Vector3(horizontal.x, base_g.y, horizontal.z)
	var last_g: Vector3 = _rain_last_gravity if p == _rain_particles else _snow_last_gravity
	if last_g.distance_to(new_g) < 0.05:
		return
	mat.gravity = new_g
	if p == _rain_particles:
		_rain_last_gravity = new_g
	else:
		_snow_last_gravity = new_g


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


# ============================================================
# Phase K bundle (2026-05-27): light shafts per weather + rainbow
# ============================================================

func _find_sun() -> DirectionalLight3D:
	# Sun is in group "sun_light" — set in scenes/World3D.tscn on the
	# Sun DirectionalLight3D. Same convention UnderwaterFilter uses.
	var n: Node = get_tree().get_first_node_in_group("sun_light")
	return n as DirectionalLight3D if n is DirectionalLight3D else null


func _apply_light_shafts_to_sun() -> void:
	var sun: DirectionalLight3D = _find_sun()
	if sun == null:
		return
	# First-tick snapshot of the scene-shipped baseline so the per-state
	# multiplier has a meaningful unit to scale.
	if _sun_baseline_volfog_energy < 0.0:
		_sun_baseline_volfog_energy = sun.light_volumetric_fog_energy
	# Toggle: when disabled, restore the baseline directly.
	var gm := get_node_or_null("/root/GraphicsManager")
	if gm != null and not gm.is_effect_enabled("light_shafts"):
		sun.light_volumetric_fog_energy = _sun_baseline_volfog_energy
		return
	# Multiply baseline by the live weather multiplier. Note:
	# UnderwaterFilter overwrites this same property each frame the
	# camera is submerged; our write re-applies the moment the camera
	# surfaces — no coordination needed.
	sun.light_volumetric_fog_energy = _sun_baseline_volfog_energy * _live_god_ray_multiplier


const RAINBOW_GLOBAL_PARAM: StringName = &"rainbow_factor"


func _tick_rainbow(delta: float) -> void:
	# Run the rainbow state machine. Always pushes a value to the global
	# shader param so the sky shader stays in sync; the value is 0 when
	# the GraphicsManager toggle is off, regardless of state.
	match _rainbow_state:
		RainbowState.IDLE:
			_rainbow_factor = 0.0
		RainbowState.RAMPING_UP:
			_rainbow_elapsed += delta
			_rainbow_factor = clampf(_rainbow_elapsed / RAINBOW_RAMP_UP_S, 0.0, 1.0)
			# 1 Hz progress log — confirms the state machine is advancing
			# and the value pushed to the shader matches what the designer
			# can see in-engine (visible arc opacity ≈ rainbow_factor).
			_rainbow_log_accum += delta
			if _rainbow_log_accum >= 1.0:
				_rainbow_log_accum = 0.0
				print("[WeatherManager] Rainbow ramping up: factor=%.2f (%.1f s / %.1f s)" % [
					_rainbow_factor, _rainbow_elapsed, RAINBOW_RAMP_UP_S])
			if _rainbow_elapsed >= RAINBOW_RAMP_UP_S:
				_rainbow_state = RainbowState.HOLDING
				_rainbow_elapsed = 0.0
		RainbowState.HOLDING:
			_rainbow_factor = 1.0
			_rainbow_elapsed += delta
			if _rainbow_elapsed >= RAINBOW_HOLD_S:
				_rainbow_state = RainbowState.RAMPING_DOWN
				_rainbow_elapsed = 0.0
		RainbowState.RAMPING_DOWN:
			_rainbow_elapsed += delta
			_rainbow_factor = clampf(1.0 - (_rainbow_elapsed / RAINBOW_RAMP_DOWN_S), 0.0, 1.0)
			if _rainbow_elapsed >= RAINBOW_RAMP_DOWN_S:
				_rainbow_state = RainbowState.IDLE
				_rainbow_factor = 0.0
				print("[WeatherManager] Rainbow finished.")

	# Toggle gate on the shader-side value. The state machine keeps
	# ticking either way so a toggle-off mid-rainbow still ends in
	# the correct state when re-enabled.
	var gm := get_node_or_null("/root/GraphicsManager")
	var pushed: float = _rainbow_factor
	if gm != null and not gm.is_effect_enabled("rainbow"):
		pushed = 0.0
	RenderingServer.global_shader_parameter_set(RAINBOW_GLOBAL_PARAM, pushed)
