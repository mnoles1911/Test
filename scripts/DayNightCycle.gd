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

# How far from the camera the moon mesh is positioned (metres).
# Far enough to appear celestial; no_depth_test on the material
# ensures fog and terrain depth don't obscure it.
const MOON_DISTANCE: float = 500.0


# Light energy ramps. Sun is bright at noon, moon is a fraction of that.
const SUN_ENERGY_DAY: float    = 1.4
const SUN_ENERGY_NIGHT: float  = 0.0
const MOON_ENERGY_NIGHT: float = 0.35
const MOON_ENERGY_DAY: float   = 0.0

# Color palettes (tuned by eye — iterate once art direction lands).
const SUN_COLOR_DAWN: Color = Color(1.0, 0.65, 0.35)  # orange-pink
const SUN_COLOR_NOON: Color = Color(1.0, 0.97, 0.92)  # warm white
const SUN_COLOR_DUSK: Color = Color(1.0, 0.45, 0.25)  # red-orange
const MOON_COLOR: Color     = Color(0.55, 0.65, 0.85) # cool pale blue

const SKY_TOP_NOON: Color      = Color(0.32, 0.58, 0.82)
const SKY_HORIZON_NOON: Color  = Color(0.70, 0.85, 0.95)
const SKY_TOP_DAWN: Color      = Color(0.32, 0.30, 0.42)
const SKY_HORIZON_DAWN: Color  = Color(0.95, 0.55, 0.40)
const SKY_TOP_DUSK: Color      = Color(0.30, 0.20, 0.30)
const SKY_HORIZON_DUSK: Color  = Color(0.95, 0.35, 0.20)
const SKY_TOP_NIGHT: Color     = Color(0.04, 0.05, 0.10)
const SKY_HORIZON_NIGHT: Color = Color(0.06, 0.08, 0.14)

const FOG_COLOR_DAY: Color   = Color(0.55, 0.65, 0.78)
const FOG_COLOR_NIGHT: Color = Color(0.05, 0.07, 0.10)


var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: WorldEnvironment
var _sun_mesh: MeshInstance3D
var _moon_mesh: MeshInstance3D

# Cached reference to the sky's ShaderMaterial so we don't re-fetch it
# every frame. Resolved once in _ready(); null if the scene's Sky doesn't
# use our shader (in which case sky cross-fading is silently skipped and
# the sun/moon/light/fog logic still runs).
var _sky_mat: ShaderMaterial = null

# One-shot warning latch so a missing-panorama setup logs once at startup
# rather than spamming the console every frame from _process.
var _warned_missing_panoramas: bool = false

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
	# if the project's sky isn't using sky_blend.gdshader — in that case the
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


func _process(_delta: float) -> void:
	_apply()


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

	# --- Sun + moon orbit ---
	# Convert hour to an angle around the world's left axis. At hour 6
	# the sun is at the east horizon (angle 0), at hour 12 it's at
	# zenith (angle 90°), at hour 18 it's at the west horizon (180°).
	var sun_angle_rad: float = (h - 6.0) / 24.0 * TAU
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
		sun_color  = SUN_COLOR_DAWN
	elif h < 7.0:
		# DAWN ramp — energy off → on, color shifts orange → white
		var t: float = (h - 5.0) / 2.0
		sun_energy = lerp(SUN_ENERGY_NIGHT, SUN_ENERGY_DAY, t)
		sun_color  = SUN_COLOR_DAWN.lerp(SUN_COLOR_NOON, t)
	elif h < 17.0:
		sun_energy = SUN_ENERGY_DAY
		sun_color  = SUN_COLOR_NOON
	elif h < 20.0:
		# DUSK ramp — energy on → off, color shifts white → red
		var t: float = (h - 17.0) / 3.0
		sun_energy = lerp(SUN_ENERGY_DAY, SUN_ENERGY_NIGHT, t)
		sun_color  = SUN_COLOR_NOON.lerp(SUN_COLOR_DUSK, t)
	else:
		sun_energy = SUN_ENERGY_NIGHT
		sun_color  = SUN_COLOR_DUSK

	_sun.light_energy = sun_energy
	_sun.light_color  = sun_color

	# --- Sun mesh (visible celestial body) ---
	# Same technique as MoonMesh: position the sphere MOON_DISTANCE metres
	# from the active camera in the sun's sky direction (+Z of the sun node)
	# so it always appears in the correct part of the sky.
	if _sun_mesh != null:
		_sun_mesh.visible = sun_energy > 0.05
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			var sun_dir: Vector3 = _sun.global_transform.basis.z
			_sun_mesh.global_position = cam.global_position + sun_dir * MOON_DISTANCE

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
	_moon.light_color  = MOON_COLOR

	# --- Moon mesh (visible celestial body) ---
	# PhysicalSkyMaterial handles the sun disk automatically. The moon
	# needs a custom mesh because the sky shader can only show one sun-style
	# disk. We position the mesh MOON_DISTANCE metres from the active camera
	# in the direction the moon light comes FROM (its local +Z axis), so it
	# always appears in the correct part of the sky regardless of where the
	# player is standing. no_depth_test on the material means fog and terrain
	# depth don't hide it.
	if _moon_mesh != null:
		_moon_mesh.visible = moon_energy > 0.05
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			# The DirectionalLight3D shines along its local -Z axis, so the
			# body it represents appears at +Z in world space.
			var moon_dir: Vector3 = _moon.global_transform.basis.z
			_moon_mesh.global_position = cam.global_position + moon_dir * MOON_DISTANCE

	# --- Sky + fog ---
	var sky_top: Color
	var sky_horizon: Color
	var fog: Color
	if h < 5.0:
		sky_top     = SKY_TOP_NIGHT
		sky_horizon = SKY_HORIZON_NIGHT
		fog         = FOG_COLOR_NIGHT
	elif h < 6.0:
		# Late night → dawn: night palette → dawn palette
		var t: float = h - 5.0
		sky_top     = SKY_TOP_NIGHT.lerp(SKY_TOP_DAWN, t)
		sky_horizon = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAWN, t)
		fog         = FOG_COLOR_NIGHT.lerp(FOG_COLOR_DAY, t * 0.5)
	elif h < 8.0:
		# Dawn → noon: dawn palette → noon palette
		var t: float = (h - 6.0) / 2.0
		sky_top     = SKY_TOP_DAWN.lerp(SKY_TOP_NOON, t)
		sky_horizon = SKY_HORIZON_DAWN.lerp(SKY_HORIZON_NOON, t)
		fog         = FOG_COLOR_NIGHT.lerp(FOG_COLOR_DAY, 0.5 + t * 0.5)
	elif h < 17.0:
		sky_top     = SKY_TOP_NOON
		sky_horizon = SKY_HORIZON_NOON
		fog         = FOG_COLOR_DAY
	elif h < 19.0:
		# Afternoon → dusk
		var t: float = (h - 17.0) / 2.0
		sky_top     = SKY_TOP_NOON.lerp(SKY_TOP_DUSK, t)
		sky_horizon = SKY_HORIZON_NOON.lerp(SKY_HORIZON_DUSK, t)
		fog         = FOG_COLOR_DAY.lerp(FOG_COLOR_NIGHT, t * 0.5)
	elif h < 21.0:
		# Dusk → night
		var t: float = (h - 19.0) / 2.0
		sky_top     = SKY_TOP_DUSK.lerp(SKY_TOP_NIGHT, t)
		sky_horizon = SKY_HORIZON_DUSK.lerp(SKY_HORIZON_NIGHT, t)
		fog         = FOG_COLOR_DAY.lerp(FOG_COLOR_NIGHT, 0.5 + t * 0.5)
	else:
		sky_top     = SKY_TOP_NIGHT
		sky_horizon = SKY_HORIZON_NIGHT
		fog         = FOG_COLOR_NIGHT

	var env: Environment = _env.environment
	if env == null:
		return

	# Sky panorama cross-fade.
	# Old version tried to cast env.sky.sky_material to ProceduralSkyMaterial,
	# but the scene actually used PhysicalSkyMaterial — the cast silently
	# returned null and the sky_top / sky_horizon writes did nothing.
	# Now the scene uses our custom sky_blend.gdshader (a ShaderMaterial),
	# and _update_sky_blend picks two of the four anchor panoramas and
	# writes the blend factor to the shader. The sky_top/sky_horizon Color
	# variables computed above remain authoritative for the fog tint and
	# could be repurposed later (e.g. tinting the panoramas via a colour
	# multiplier uniform) but currently aren't pushed anywhere visible.
	_update_sky_blend(h)

	if _fog_override_active:
		env.fog_light_color = _override_fog_color
		env.fog_density     = _override_fog_density
	else:
		env.fog_light_color = fog


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


# Public API used by WeatherManager. Color and density are written verbatim
# every frame as long as the override is active — WeatherManager animates them.
func set_fog_override(color: Color, density: float) -> void:
	_fog_override_active = true
	_override_fog_color = color
	_override_fog_density = density


func clear_fog_override() -> void:
	_fog_override_active = false
