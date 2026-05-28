extends Node
# DayNightCycle — drives the Sun, Moon, and Sky so they follow
# WorldClock's in-game time.
#
# What this does in plain English:
#
#   Each frame, we look up the current hour-of-day from WorldClock,
#   then update three things:
#
#     1. Sun + Moon DirectionalLight3D rotations — they orbit on the
#        same axis, 12 hours apart. Sun rises at 06:00, peaks at
#        12:00, sets at 18:00. Moon does the same arc shifted by 12h.
#
#     2. Sun + Moon energy / color — sun ramps from off (pre-dawn)
#        to bright white (mid-day) to red-orange (dusk) to off
#        (night). Moon is the inverse — only on while the sun is off.
#
#     3. Sky top/horizon colors and fog tint — interpolated through
#        the same dawn/day/dusk/night palette so the world's overall
#        mood matches the lighting.
#
#   The whole thing runs cheaply per-frame (a handful of lerps and
#   property writes). Per-frame instead of WorldClock.hour_changed
#   so transitions are smooth rather than 1-hour-step snaps.
#
# Why a node script and not an autoload?
#
#   The lights and sky live inside World3D.tscn. An autoload would
#   have to look them up by absolute path and worry about the world
#   not being loaded. A scene-attached node always knows where its
#   siblings are and does nothing while no world is open.
#
# Reference: design/WEATHER_AND_ENVIRONMENT.md → Six time-of-day periods


# Phase G — the time-of-day colour anchors now live in a Resource.
# Preloaded by path (AtmosphereProfile has no class_name) so the
# headless harness, which does not rescan global classes, still parses
# this script.
const AtmosphereProfile := preload("res://scripts/graphics/AtmosphereProfile.gd")


@export var sun_path: NodePath = "../Sun"
@export var moon_path: NodePath = "../Moon"
@export var environment_path: NodePath = "../WorldEnvironment"
@export var sun_mesh_path: NodePath = "../SunMesh"
@export var moon_mesh_path: NodePath = "../MoonMesh"

# --- Sky panorama anchors ---
# Four equirectangular panorama images representing the sky at four
# anchor times of day. Each frame we pick the two anchors flanking the
# current hour and cross-fade them via the sky shader. Drop the AI-
# generated PNGs into assets/sky/ and assign them to these slots in the
# Inspector on the DayNightCycle node. While any slot is null the sky
# update is skipped (the shader keeps showing whatever it last had);
# a one-shot warning is printed at startup so it's obvious art is missing.
@export var dawn_panorama:  Texture2D = null
@export var noon_panorama:  Texture2D = null
@export var dusk_panorama:  Texture2D = null
@export var night_panorama: Texture2D = null

# --- Atmosphere colour palette (Phase G) ---
# The sky/sun/fog colour anchors. Leave null to use the shipped palette
# (AtmosphereProfile's defaults reproduce it exactly); assign a custom
# .tres to retune the world's colour without touching code.
@export var atmosphere: AtmosphereProfile = null

# How far from the camera the moon mesh is positioned (metres).
# Far enough to appear celestial; no_depth_test on the material
# ensures fog and terrain depth don't obscure it.
const MOON_DISTANCE: float = 500.0


# Light energy ramps. Sun is bright at noon, moon is a fraction of that.
const SUN_ENERGY_DAY: float    = 2.2
# Bumped from 1.4 → 2.2 (mid-2026-05): daytime felt darker than
# expected with the new terrain material, especially at LOD2+ where
# vertex colour darkening compounds with mesh-edge shading. 2.2 is
# a normal "bright outdoor scene" sun energy in Godot 4 — readable
# without blowing out highlights.
const SUN_ENERGY_NIGHT: float  = 0.0
const MOON_ENERGY_NIGHT: float = 2.0
# The moon is the night's primary light source. Raised 0.6 → 2.0
# (2026-05-21 designer pass, ~3.3×): the night sky now renders very
# dark (sky_atmosphere.gdshader night_sky_darkness), so sky-sourced ambient
# at night is near-zero — the moon's directional light carries the
# whole night look. A cool-blue moon at this energy gives a bright,
# readable moonlit world against an almost-black sky.
const MOON_ENERGY_DAY: float   = 0.0

# Time-of-day colour anchors (sun / sky / fog / volumetric-fog albedo)
# moved into AtmosphereProfile in Phase G. `_atmo` is resolved once in
# _ready() from the `atmosphere` export (or a fresh default profile)
# and read as _atmo.<field> throughout _apply().
var _atmo: AtmosphereProfile = null

# Aurora colour follows a fixed cycle — a smooth loop through these 3
# anchor colours, completing once every AURORA_CYCLE_DAYS in-game days
# then repeating. _update_night_palette() lerps between anchors so each
# night's hue drifts gradually rather than snapping.
const AURORA_CYCLE_DAYS: int = 7
const AURORA_CYCLE: Array[Color] = [
	Color(0.20, 0.85, 0.92),  # teal / cyan
	Color(0.25, 0.95, 0.55),  # classic green
	Color(0.60, 0.40, 0.95),  # violet
]
# The nebula drifts around the sky's azimuth — NEBULA_DRIFT_PER_CYCLE of
# a full revolution every NEBULA_CYCLE_DAYS in-game days. Continuous: it
# never snaps back (a circle has no seam). Its colour is constant — the
# shader's nebula_color default.
const NEBULA_CYCLE_DAYS: float = 7.0
const NEBULA_DRIFT_PER_CYCLE: float = 0.30


var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: WorldEnvironment
var _sun_mesh: MeshInstance3D
var _moon_mesh: MeshInstance3D

# Track shadow-on/off state per light so we only flip shadow_enabled at the
# transitions (dawn/dusk crossings). Setting shadow_enabled triggers a
# rendering-server call internally, so we avoid hammering it every frame.
# -1 = uninitialised (forces first _apply() to write); 0 = off; 1 = on.
var _sun_shadow_state: int = -1
var _moon_shadow_state: int = -1
# Threshold below which a light's shadow rendering is wasted work — its
# energy is so low the shadows it casts are invisible against the ambient.
const SHADOW_DISABLE_ENERGY: float = 0.05

# Cached reference to the sky's ShaderMaterial so we don't re-fetch it
# every frame. Resolved once in _ready(); null if the scene's Sky doesn't
# use our shader (in which case sky cross-fading is silently skipped and
# the sun/moon/light/fog logic still runs).
var _sky_mat: ShaderMaterial = null

# One-shot warning latch so a missing-panorama setup logs once at startup
# rather than spamming the console every frame from _process.
var _warned_missing_panoramas: bool = false

# The in-game day the aurora/nebula palette was last refreshed for.
# -1 forces _apply() to pick a palette on the first tick.
var _night_palette_day: int = -1

# _apply() updates sun/moon orbit, light energy/color, sky tint, and
# fog from WorldClock state. With WorldClock running at 240 real-s
# per game-hour, the sun moves 0.0625°/real-second — totally invisible
# between adjacent render frames. Tick this at 10 Hz instead of every
# frame (was ~13 µs/frame × 100 % hit rate ≈ 4.9 ms/sec steady cost).
const STATE_TICK_INTERVAL_S: float = 0.1
var _state_tick_accumulator: float = 0.0

# Weather fog override. While WeatherManager wants to drive fog, it calls
# set_fog_override(color, density). _apply() then writes those values instead
# of the time-of-day-driven palette every frame. WeatherManager interpolates
# the values it passes in (over the 30s state-transition tween), so the
# override doesn't need its own blend logic here. clear_fog_override() hands
# fog control back to the day/night palette.
var _fog_override_active: bool = false
var _override_fog_color: Color = Color.WHITE
var _override_fog_density: float = 0.0


func _ready() -> void:
	# WeatherManager finds us via this group to push the fog override.
	# Group registration happens here rather than in the .tscn so adding
	# the script to a new World scene is enough — no node-property edit.
	add_to_group("day_night_cycle")

	# Phase G — resolve the colour palette. A null `atmosphere` export
	# falls back to a fresh AtmosphereProfile, whose defaults reproduce
	# the shipped look exactly.
	_atmo = atmosphere if atmosphere != null else AtmosphereProfile.new()

	_sun  = get_node_or_null(sun_path) as DirectionalLight3D
	_moon = get_node_or_null(moon_path) as DirectionalLight3D
	_env  = get_node_or_null(environment_path) as WorldEnvironment

	_sun_mesh  = get_node_or_null(sun_mesh_path) as MeshInstance3D
	_moon_mesh = get_node_or_null(moon_mesh_path) as MeshInstance3D

	if _sun == null:
		push_warning("[DayNightCycle] Sun not found at %s" % sun_path)
	if _moon == null:
		push_warning("[DayNightCycle] Moon not found at %s" % moon_path)
	if _env == null:
		push_warning("[DayNightCycle] WorldEnvironment not found at %s" % environment_path)
	if _moon_mesh == null:
		push_warning("[DayNightCycle] MoonMesh not found at %s" % moon_mesh_path)

	# Cache the sky's ShaderMaterial so _update_sky_blend can write to it
	# without re-fetching it 60 times a second. We accept that this is null
	# if the project's sky isn't using sky_atmosphere.gdshader — in that case the
	# sky cross-fade just becomes a no-op and the rest of the cycle keeps
	# working normally (sun/moon rotation, light energy, fog).
	if _env != null and _env.environment != null and _env.environment.sky != null:
		_sky_mat = _env.environment.sky.sky_material as ShaderMaterial
	if _sky_mat == null:
		push_warning("[DayNightCycle] Sky ShaderMaterial not found — sky cross-fade disabled")

	# Warn once if any of the four panorama slots is empty. The script
	# stays alive and skips just the sky update; everything else runs.
	if _sky_mat != null and (dawn_panorama == null or noon_panorama == null \
			or dusk_panorama == null or night_panorama == null):
		push_warning("[DayNightCycle] One or more sky panoramas not assigned in Inspector — sky cross-fade disabled until all four slots are filled")
		_warned_missing_panoramas = true

	# Apply once at world load so the first rendered frame already has
	# the right time-of-day look. Without this the lights would default
	# to whatever the .tscn baked in until the next _process tick.
	_apply()


func _process(delta: float) -> void:
	# Phase K bundle (2026-05-27). Advance cloud-phase EVERY FRAME (not at
	# the 10 Hz gate below) so the sky shader's drift is smooth across
	# weather transitions. The phase is the integral of cloud_scroll_speed
	# over real time — adding `delta * speed` per frame gives a continuous
	# trajectory even when `speed` changes (e.g. during a 30 s
	# clear→storm transition). Push to the shader each frame; one global
	# shader write is trivial.
	_cloud_phase += delta * _cloud_speed_live
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("cloud_phase", _cloud_phase)

	# Gate _apply() to 10 Hz. Sun motion at 0.0625°/real-second is well
	# below the per-frame visible-change threshold, and the lerps for
	# sun energy / color / sky tint span minutes of game time — none of
	# them suffer at 100 ms granularity.
	_state_tick_accumulator += delta
	if _state_tick_accumulator < STATE_TICK_INTERVAL_S:
		return
	_state_tick_accumulator = 0.0

	# Profiling wrapper — feeds the in-HUD [PERF] log + F3 Profiler overlay.
	var _t0_prof: int = Time.get_ticks_usec()
	_apply()
	var _elapsed: int = Time.get_ticks_usec() - _t0_prof
	HUDOverlay.profile_record("DayNightCycle", _elapsed)
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WEATHER", "DayNightCycle", _elapsed)


func _apply() -> void:
	if not get_node_or_null("/root/WorldClock"):
		return
	if _sun == null or _moon == null or _env == null:
		return

	# Continuous hour-of-day in [0, 24). We add get_minute_fraction() so the
	# value advances every frame (not just once per minute), giving the sun and
	# moon perfectly smooth motion across the sky.
	var minute_frac: float = WorldClock.get_minute_fraction()
	var h: float = float(WorldClock.current_hour) + (float(WorldClock.current_minute) + minute_frac) / 60.0

	# Refresh the per-night aurora/nebula palette when the day rolls over,
	# so each night carries its own colour signature.
	if _sky_mat != null and WorldClock.current_day != _night_palette_day:
		_night_palette_day = WorldClock.current_day
		_update_night_palette(WorldClock.current_day)

	# --- Sun + moon orbit ---
	# Convert hour to an angle around the world's left axis. At hour 6
	# the sun is at the east horizon (angle 0), at hour 12 it's at
	# zenith (angle 90°), at hour 18 it's at the west horizon (180°).
	var sun_angle_rad: float = (h - 6.0) / 24.0 * TAU
	# Star-field rotation — the procedural night sky in sky_atmosphere.gdshader
	# pivots with the celestial sphere at the same rate as the sun/moon.
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("star_rotation", sun_angle_rad)
	# Tilt the orbit ~15° so the sun arcs through the south hemisphere
	# rather than dead-overhead — gives more natural shadow direction.
	var sun_basis: Basis = Basis().rotated(Vector3.LEFT, sun_angle_rad).rotated(Vector3.FORWARD, deg_to_rad(15.0))
	_sun.transform.basis = sun_basis
	# Moon is the anti-sun — same orbit, half a turn behind.
	_moon.transform.basis = sun_basis.rotated(Vector3.LEFT, PI)

	# --- Sun energy + color ---
	var sun_energy: float
	var sun_color: Color
	if h < 5.0:
		sun_energy = SUN_ENERGY_NIGHT
		sun_color  = _atmo.sun_color_dawn
	elif h < 7.0:
		# DAWN ramp — energy off → on, color shifts orange → white
		var t: float = (h - 5.0) / 2.0
		sun_energy = lerp(SUN_ENERGY_NIGHT, SUN_ENERGY_DAY, t)
		sun_color  = _atmo.sun_color_dawn.lerp(_atmo.sun_color_noon, t)
	elif h < 17.0:
		sun_energy = SUN_ENERGY_DAY
		sun_color  = _atmo.sun_color_noon
	elif h < 20.0:
		# DUSK ramp — energy on → off, color shifts white → red
		var t: float = (h - 17.0) / 3.0
		sun_energy = lerp(SUN_ENERGY_DAY, SUN_ENERGY_NIGHT, t)
		sun_color  = _atmo.sun_color_noon.lerp(_atmo.sun_color_dusk, t)
	else:
		sun_energy = SUN_ENERGY_NIGHT
		sun_color  = _atmo.sun_color_dusk

	_sun.light_energy = sun_energy
	_sun.light_color  = sun_color

	# Push an explicit night factor (0 = full day, 1 = full night) to the
	# sky shader. The shader uses THIS — not the indirect LIGHT0 energy,
	# which proved unreliable — to darken the night sky and fade in the
	# stars / aurora / nebula. DayNightCycle knows the real sun energy,
	# so this is deterministic.
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("night_factor",
			1.0 - clampf(sun_energy / SUN_ENERGY_DAY, 0.0, 1.0))

	# Disable shadow casting when the sun is below the visibility threshold —
	# at night the sun is pointing through the world from the wrong side and
	# its shadow map is being maintained for no visible benefit. We only flip
	# at transitions to avoid per-frame rendering-server overhead.
	var sun_shadow_target: int = 1 if sun_energy > SHADOW_DISABLE_ENERGY else 0
	if sun_shadow_target != _sun_shadow_state:
		_sun.shadow_enabled = sun_shadow_target == 1
		_sun_shadow_state = sun_shadow_target

	# --- Sun mesh (visible celestial body) ---
	# Same technique as MoonMesh: position the sphere MOON_DISTANCE metres
	# from the active camera in the sun's sky direction (+Z of the sun node)
	# so it always appears in the correct part of the sky.
	#
	# Visibility gate: BOTH the energy threshold AND a Y on the sky-direction
	# vector at/above a small negative threshold. As of 2026-05-20 SunMat
	# depth-tests normally (no_depth_test = false), so real terrain occludes
	# the orb INCREMENTALLY as it descends — hills on the horizon hide its
	# lower edge naturally. This gate is now just a safety hard-hide for when
	# the sun is clearly below the geometric horizon, so the orb can't render
	# from the far side of the world (e.g. poking up over open water where no
	# terrain depth exists to occlude it). -0.05 keeps it renderable right at
	# the horizon line so depth-occlusion does the visible work.
	if _sun_mesh != null:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			var sun_dir: Vector3 = _sun.global_transform.basis.z
			_sun_mesh.visible = sun_energy > 0.05 and sun_dir.y > -0.05
			_sun_mesh.global_position = cam.global_position + sun_dir * MOON_DISTANCE
		else:
			_sun_mesh.visible = false

	# --- Moon energy + color ---
	# Moon active 20:00 → 05:00 (NIGHT + DEEP_NIGHT), with crossfade
	# at the twilight boundaries.
	var moon_energy: float
	if h >= 20.0 or h < 5.0:
		moon_energy = MOON_ENERGY_NIGHT
	elif h < 6.0:
		# 5:00–6:00 — moon fades out as sun rises
		moon_energy = lerp(MOON_ENERGY_NIGHT, MOON_ENERGY_DAY, h - 5.0)
	elif h >= 19.0:
		# 19:00–20:00 — moon fades in as sun sets
		moon_energy = lerp(MOON_ENERGY_DAY, MOON_ENERGY_NIGHT, h - 19.0)
	else:
		moon_energy = MOON_ENERGY_DAY

	_moon.light_energy = moon_energy
	_moon.light_color  = _atmo.moon_color

	# Same dawn/dusk gating for the moon — during the day its shadow map is
	# wasted work since its light_energy is 0 and any shadows would be
	# invisible anyway.
	var moon_shadow_target: int = 1 if moon_energy > SHADOW_DISABLE_ENERGY else 0
	if moon_shadow_target != _moon_shadow_state:
		_moon.shadow_enabled = moon_shadow_target == 1
		_moon_shadow_state = moon_shadow_target

	# --- Moon mesh (visible celestial body) ---
	# PhysicalSkyMaterial handles the sun disk automatically. The moon
	# needs a custom mesh because the sky shader can only show one sun-style
	# disk. We position the mesh MOON_DISTANCE metres from the active camera
	# in the direction the moon light comes FROM (its local +Z axis), so it
	# always appears in the correct part of the sky regardless of where the
	# player is standing. no_depth_test on the material means fog and terrain
	# depth don't hide it.
	if _moon_mesh != null:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			# The DirectionalLight3D shines along its local -Z axis, so the
			# body it represents appears at +Z in world space. Same horizon
			# gate as the sun — MoonMat.no_depth_test would otherwise punch
			# the moon orb through terrain at dawn/dusk transitions.
			var moon_dir: Vector3 = _moon.global_transform.basis.z
			_moon_mesh.visible = moon_energy > 0.05 and moon_dir.y > -0.05
			_moon_mesh.global_position = cam.global_position + moon_dir * MOON_DISTANCE
		else:
			_moon_mesh.visible = false

	# --- Sky + fog ---
	var _sky_top: Color
	var _sky_horizon: Color
	var fog: Color
	if h < 5.0:
		_sky_top     = _atmo.sky_top_night
		_sky_horizon = _atmo.sky_horizon_night
		fog         = _atmo.fog_color_night
	elif h < 6.0:
		# Late night → dawn: night palette → dawn palette
		var t: float = h - 5.0
		_sky_top     = _atmo.sky_top_night.lerp(_atmo.sky_top_dawn, t)
		_sky_horizon = _atmo.sky_horizon_night.lerp(_atmo.sky_horizon_dawn, t)
		fog         = _atmo.fog_color_night.lerp(_atmo.fog_color_day, t * 0.5)
	elif h < 8.0:
		# Dawn → noon: dawn palette → noon palette
		var t: float = (h - 6.0) / 2.0
		_sky_top     = _atmo.sky_top_dawn.lerp(_atmo.sky_top_noon, t)
		_sky_horizon = _atmo.sky_horizon_dawn.lerp(_atmo.sky_horizon_noon, t)
		fog         = _atmo.fog_color_night.lerp(_atmo.fog_color_day, 0.5 + t * 0.5)
	elif h < 17.0:
		_sky_top     = _atmo.sky_top_noon
		_sky_horizon = _atmo.sky_horizon_noon
		fog         = _atmo.fog_color_day
	elif h < 19.0:
		# Afternoon → dusk
		var t: float = (h - 17.0) / 2.0
		_sky_top     = _atmo.sky_top_noon.lerp(_atmo.sky_top_dusk, t)
		_sky_horizon = _atmo.sky_horizon_noon.lerp(_atmo.sky_horizon_dusk, t)
		fog         = _atmo.fog_color_day.lerp(_atmo.fog_color_night, t * 0.5)
	elif h < 21.0:
		# Dusk → night
		var t: float = (h - 19.0) / 2.0
		_sky_top     = _atmo.sky_top_dusk.lerp(_atmo.sky_top_night, t)
		_sky_horizon = _atmo.sky_horizon_dusk.lerp(_atmo.sky_horizon_night, t)
		fog         = _atmo.fog_color_day.lerp(_atmo.fog_color_night, 0.5 + t * 0.5)
	else:
		_sky_top     = _atmo.sky_top_night
		_sky_horizon = _atmo.sky_horizon_night
		fog         = _atmo.fog_color_night

	var env: Environment = _env.environment
	if env == null:
		return

	# Sky panorama cross-fade.
	# Old version tried to cast env.sky.sky_material to ProceduralSkyMaterial,
	# but the scene actually used PhysicalSkyMaterial — the cast silently
	# returned null and the _sky_top / _sky_horizon writes did nothing.
	# Now the scene uses our custom sky_atmosphere.gdshader (a ShaderMaterial),
	# and _update_sky_blend picks two of the four anchor panoramas and
	# writes the blend factor to the shader. The _sky_top/_sky_horizon Color
	# variables computed above remain authoritative for the fog tint and
	# could be repurposed later (e.g. tinting the panoramas via a colour
	# multiplier uniform) but currently aren't pushed anywhere visible.
	_update_sky_blend(h)

	# Time-of-day darkening applies to fog ALWAYS — even under a weather
	# override. WeatherManager supplies a weather-state fog colour/density;
	# DayNightCycle still pulls that colour toward the dark night palette
	# by night_factor, so the fog (and the sky it aerial-blends into) goes
	# genuinely dark at night instead of staying weather-bright. Before
	# this, the override path bypassed all day/night darkening, which is
	# why the night sky stayed pale blue.
	var night_t: float = 1.0 - clampf(sun_energy / SUN_ENERGY_DAY, 0.0, 1.0)
	if _fog_override_active:
		env.fog_light_color = _override_fog_color.lerp(_atmo.fog_color_night, night_t)
		env.fog_density     = _override_fog_density
	else:
		env.fog_light_color = fog
	# Volumetric fog albedo is part of neither the weather override nor
	# the hour ramp above — drive it here so the volumetric layer darkens
	# at night too (its sky_affect otherwise washes the night sky pale).
	env.volumetric_fog_albedo = _atmo.vol_fog_albedo_day.lerp(_atmo.vol_fog_albedo_night, night_t)


# Decide which two anchor panoramas flank the current hour-of-day, then
# write them and the blend factor to the sky shader.
#
# Plain English: The sky is built from four painted images (dawn, noon,
# dusk, night). At any moment the sky is between two of them — e.g. at
# 06:30 we're halfway between night and dawn. We sample both and lerp
# rather than swapping at hard boundaries, which would look like a TV
# channel change.
#
# The hour ranges below match the same dawn/noon/dusk/night breakpoints
# used by the sun-energy and fog-colour ramps above, so the painted sky
# transitions stay synchronised with the lighting.
#
# Why only two textures, not four? A shader runs per-pixel of the sky
# every frame. Sampling four panoramas and weighting them is wasteful
# when by definition only two are ever active at once — the cross-fade
# happens between adjacent anchors, never across them.
func _update_sky_blend(h: float) -> void:
	if _sky_mat == null:
		return
	if dawn_panorama == null or noon_panorama == null \
			or dusk_panorama == null or night_panorama == null:
		return

	var from_tex: Texture2D
	var to_tex:   Texture2D
	var blend:    float

	if h < 5.0:
		from_tex = night_panorama; to_tex = night_panorama; blend = 0.0
	elif h < 7.0:
		# Pre-dawn → dawn: 05:00–07:00
		from_tex = night_panorama; to_tex = dawn_panorama
		blend = (h - 5.0) / 2.0
	elif h < 11.0:
		# Dawn → midday: 07:00–11:00
		from_tex = dawn_panorama; to_tex = noon_panorama
		blend = (h - 7.0) / 4.0
	elif h < 17.0:
		from_tex = noon_panorama; to_tex = noon_panorama; blend = 0.0
	elif h < 19.0:
		# Late afternoon → dusk: 17:00–19:00
		from_tex = noon_panorama; to_tex = dusk_panorama
		blend = (h - 17.0) / 2.0
	elif h < 21.0:
		# Dusk → night: 19:00–21:00
		from_tex = dusk_panorama; to_tex = night_panorama
		blend = (h - 19.0) / 2.0
	else:
		from_tex = night_panorama; to_tex = night_panorama; blend = 0.0

	_sky_mat.set_shader_parameter("texture_from", from_tex)
	_sky_mat.set_shader_parameter("texture_to",   to_tex)
	_sky_mat.set_shader_parameter("blend",        blend)


# Refresh the night sky's per-day state for a given in-game day: the
# aurora hue (a smooth 7-day loop through AURORA_CYCLE) and the nebula's
# drift position around the sky. The nebula's colour is constant — the
# shader's nebula_color default.
func _update_night_palette(day: int) -> void:
	if _sky_mat == null:
		return
	# Aurora: position within the cycle, 0 -> just under 1. day - 1 so
	# day 1 lands exactly on the first anchor.
	var phase: float = float((day - 1) % AURORA_CYCLE_DAYS) / float(AURORA_CYCLE_DAYS)
	# Map the phase onto the 3 anchors arranged on a loop (A -> B -> C -> A).
	var seg: float = phase * float(AURORA_CYCLE.size())
	var i: int = int(seg) % AURORA_CYCLE.size()
	var next_i: int = (i + 1) % AURORA_CYCLE.size()
	var aurora_col: Color = AURORA_CYCLE[i].lerp(AURORA_CYCLE[next_i], seg - floor(seg))
	_sky_mat.set_shader_parameter("aurora_color", aurora_col)
	# Nebula: drift its anchor around the sky's azimuth. day - 1 so day 1
	# starts at zero rotation; continuous, so it never snaps back.
	var nebula_rot: float = float(day - 1) / NEBULA_CYCLE_DAYS * NEBULA_DRIFT_PER_CYCLE * TAU
	_sky_mat.set_shader_parameter("nebula_rotation", nebula_rot)


# Public API used by WeatherManager. Color and density are written verbatim
# every frame as long as the override is active — WeatherManager animates them.
func set_fog_override(color: Color, density: float) -> void:
	_fog_override_active = true
	_override_fog_color = color
	_override_fog_density = density


func clear_fog_override() -> void:
	_fog_override_active = false


# Public API (Phase G) — swap the whole time-of-day colour palette at
# runtime. A weather state or a biome trigger can call this to retint
# the world without touching code; pass null to restore the shipped
# palette. The next _apply() tick (10 Hz) picks the new colours up.
func set_atmosphere_profile(profile: AtmosphereProfile) -> void:
	_atmo = profile if profile != null else AtmosphereProfile.new()


# Public API used by WeatherManager — pushes the weather-driven cloud
# coverage (0 = clear, 1 = overcast) into the sky shader. The sky shader
# animates and lights the clouds itself; this is the only value it needs
# from the weather system. No-op if the sky isn't using sky_atmosphere.gdshader.
func set_cloud_coverage(coverage: float) -> void:
	if _sky_mat == null:
		return
	_sky_mat.set_shader_parameter("cloud_coverage", clampf(coverage, 0.0, 1.0))


# Public API used by WeatherManager — pushes the weather-driven cloud
# drift speed into the sky shader. Each weather state carries its own
# cloud_speed in STATE_PROFILES (calm clear day vs. fast-moving storm).
# The sky shader uses an accumulated cloud_phase (see _process tick) to
# avoid the TIME-multiplied speed-change jerk; this setter just records
# the current speed value the accumulator integrates each frame.
func set_cloud_speed(speed: float) -> void:
	_cloud_speed_live = maxf(0.0, speed)
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("cloud_scroll_speed", _cloud_speed_live)


# Phase K bundle fix (2026-05-27). The sky shader's drift formula used to
# be `TIME * cloud_scroll_speed + gust`, which produced a visible jerk
# every time cloud_scroll_speed changed mid-frame (the entire elapsed
# TIME was re-multiplied at the new speed → instant warp of the cloud
# position by ~TIME × ΔSpeed). Fix: accumulate the phase on the CPU
# each frame and push to the shader; the shader uses `cloud_phase +
# gust` so speed changes only affect FUTURE motion, not retroactively
# warp position. Smooth across the 30 s weather-transition tween.
var _cloud_speed_live: float = 0.012
var _cloud_phase: float = 0.0
