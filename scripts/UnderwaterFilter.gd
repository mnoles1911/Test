extends CanvasLayer
# UnderwaterFilter — drives the underwater look while Roland's head is
# below the water surface.
#
# v2 architecture (2026-05-19, water-shader-v3-p4-underwater):
#   1. Godot 4 volumetric fog (WorldEnvironment.volumetric_fog_*) does
#      the real visibility murk — true 3D distance attenuation, and
#      god rays from the sun for free (when the Sun DirectionalLight3D
#      has light_volumetric_fog_energy > 0 and shadows on).
#   2. The CanvasLayer ColorRect (TintRect, alpha ~0.10) is a subtle
#      blue colour grade on top of the fog. It exists so close-up
#      water (looking straight up at the bright surface) still reads
#      tonally as "underwater" before the fog's distance term kicks in.
#   3. Day/night coupling: per-tick we observe the Sun's light_energy
#      (which DayNightCycle.gd animates 0.0 → 2.2 → 0.0 across dawn /
#      noon / dusk) and lerp the underwater fog density + colour +
#      god-ray energy between *_night and *_noon presets. As the sun
#      rises, visibility opens up and the rays brighten; as it sets,
#      fog deepens, rays fade. We never write to DayNightCycle's
#      properties; we read sun.light_energy.
#
# Why this is safe to co-exist with DayNightCycle:
#   DayNightCycle.gd only writes env.fog_light_color and env.fog_density
#   (classic depth fog) at 10 Hz. It never touches volumetric_fog_*
#   or sun.light_volumetric_fog_energy — verified by full-file grep.
#   We own those exclusively. (Earlier v1 of this script used a flat
#   ColorRect overlay precisely because we believed we couldn't use
#   env fog without fighting DayNightCycle — that was correct for the
#   classic-fog channels; volumetric fog is a separate, untouched set
#   of properties, so we can drive them freely.)
#
# Setup contract (matches scenes/World3D.tscn):
#   - WorldEnvironment node is in the "world_environment" group.
#   - The Sun DirectionalLight3D is in the "sun_light" group.
#   - The scene's Environment has `volumetric_fog_enabled = true` and a
#     baseline density / albedo / length for above-water atmospheric
#     haze. We tween from those baseline values to the underwater
#     preset on submerge, and back on emerge.
#
# Reference: design/SWIMMING_AND_WATER.md — "Underwater camera filter"
# and design/WATER_SHADER_V3_PLAN.md Phase 4 (underwater fog/god-rays).


# --- Tint overlay (cheap colour grade on top of the fog) -------------------
# Alpha 0.10 = subtle tonal cue, not the visibility-killing 0.42 it
# was in v1 (when the rect was doing all the work). The fog now closes
# distance; the rect just paints the close-up "I'm underwater" cast.
@export var tint_color: Color = Color(0.18, 0.32, 0.42, 0.10)


# --- Underwater volumetric fog presets ------------------------------------
# noon = bright sun overhead, water relatively clear, strong god rays.
# night = no sun, water reads inky, near-zero god rays. The live mix
# factor is clamp(sun.light_energy / sun_noon_energy_ref, 0, 1) so the
# transition tracks DayNightCycle's own sun-brightness curve.
# Tune in the .tscn / inspector — exported so the designer doesn't
# have to edit GDScript to taste-test.
@export var underwater_fog_density_noon: float = 0.55
@export var underwater_fog_density_night: float = 1.10
# Albedo MATCHES water_material.tres `deep_water_color = (0.02, 0.06,
# 0.11)` so the underwater fog and the body-of-water deep tint are
# the SAME colour — consistency between "looking down into water from
# above" (Beer-Lambert depth fade in water.gdshader) and "swimming
# inside water" (this volumetric fog). Night anchor is the same
# colour ramp pushed darker. Raise toward (0.04,0.10,0.18) for a
# brighter / more readable underwater look.
@export var underwater_fog_albedo_noon: Color = Color(0.02, 0.06, 0.11, 1.0)
@export var underwater_fog_albedo_night: Color = Color(0.005, 0.02, 0.04, 1.0)
# Emission — small non-zero values 2026-05-20 (was 0,0,0) so the
# underwater fog has a baseline glow even when the directional sun
# isn't contributing strongly. Without this, dawn/dusk underwater
# looked pitch-black because sun.light_volumetric_fog_energy alone
# can't carry the look at low sun angles. The emission gives the fog
# a constant dim blue glow that ambient light adds to.
@export var underwater_fog_emission_noon: Color = Color(0.04, 0.10, 0.16, 1.0)
@export var underwater_fog_emission_night: Color = Color(0.005, 0.015, 0.025, 1.0)
# Sun.light_volumetric_fog_energy — the god-ray dial. 0 = invisible
# (default Godot), bigger = brighter shafts. 6.0 at noon reads as
# "clear sunbeams in the water column". Night raised 2026-05-20 from
# 0.2 → 1.5: at dawn/dusk the sun is at a low angle and the directional
# light contribution to vol-fog drops fast on the mix curve; boosting
# the night anchor keeps SOMETHING reading as god rays at all times.
@export var underwater_god_ray_energy_noon: float = 6.0
@export var underwater_god_ray_energy_night: float = 1.5


# --- Above-water (surface) restore values --------------------------------
# Matches the baseline already set in scenes/World3D.tscn Environment_1.
# Used as the tween target when set_active(false) — we restore the
# scene's pre-submerge atmospheric haze look.
@export var surface_fog_density: float = 0.015
@export var surface_fog_albedo: Color = Color(0.85, 0.88, 0.95, 1.0)
@export var surface_fog_emission: Color = Color(0.00, 0.00, 0.00, 1.0)
@export var surface_god_ray_energy: float = 0.0
# Above-water sky_affect / ambient_inject — the Environment_1 defaults.
# UnderwaterFilter pushes them down on submerge so the underwater fog
# isn't lifted by the bright sky panorama (which was bleeding through
# as a "washed sky" look in the 2026-05-20 designer screenshot).
@export var surface_fog_sky_affect: float = 0.5
@export var surface_fog_ambient_inject: float = 1.0
# Underwater overrides — much lower so the fog reads as its own colour,
# not as a tinted sky. 0.0 sky_affect = no sky bleed at all underwater.
# ambient_inject raised 2026-05-20 from 0.3 → 0.5 so the diffuse sky
# brightness feeds the fog more — at dawn/dusk shallow sun angles, the
# directional god rays alone aren't enough; ambient carries the look.
@export var underwater_fog_sky_affect: float = 0.0
@export var underwater_fog_ambient_inject: float = 0.5


# --- Behaviour knobs -----------------------------------------------------
# Transition durations. C15 (2026-05-20) collapses both to 0 — instant
# snap, Minecraft-style. The previous 0.08s/0.12s tween combined with
# the asymmetric LEAD on Player3D produced backward hysteresis that
# flickered the filter at the surface transition. With an instant
# snap, no partial-fade window exists, so no LEAD is needed and no
# flicker is possible.
#
# Raise these toward 0.10 if you want a perceptible smooth cross-fade
# at the surface boundary (will trade flicker risk for that softness).
# transition_seconds is the legacy export, kept for .tscn back-compat.
@export var transition_seconds: float = 0.5
@export var submerge_transition_seconds: float = 0.0
@export var emerge_transition_seconds: float = 0.0
# Sun.light_energy peak — DayNightCycle uses 2.2 at noon (see
# DayNightCycle.SUN_ENERGY_DAY). The day/night mix factor divides the
# observed energy by this, so 2.2 = full "noon" preset. Tune if the
# day-curve changes.
@export var sun_noon_energy_ref: float = 2.2


@onready var _rect: ColorRect = $TintRect

# The shared water-surface material. We push `sun_direction_world` into
# it every frame so the water.gdshader back-face branch (visible from
# underwater) can place a soft sun glint on the underside of the
# surface that tracks day/night. Path-load (NOT class_name preload) so
# this script stays headless-safe.
const WATER_MATERIAL_PATH := "res://assets/shaders/water_material.tres"

# Depth-gradient parameters. UnderwaterFilter snapshots the player's Y
# at the submerge moment as the "water surface reference" and pushes
# the current depth to both the water shader (back-face brightness
# attenuation) and the FogVolume's fog shader (depth-density ramp).
# Designer report 2026-05-20: water should feel "shallow = bright +
# clear, deep = dim + thick".
@export var depth_full_dark_meters: float = 12.0
@export var depth_shallow_density_multiplier: float = 0.45
@export var depth_deep_density_multiplier: float = 1.30
# Snapshot of the player's Y at the most recent set_active(true).
# Approximates the water surface Y; refined each new submersion.
var _submerge_y_snapshot: float = 0.0

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _water_mat: ShaderMaterial = null
# Cached reference to the FogVolume's material so we can push depth
# uniforms to it per-frame. Resolved in _ready from the FogVolume
# group lookup.
var _fog_volume_mat: ShaderMaterial = null
# Optional animated-noise FogVolume (group "underwater_fog_volume").
# Adds drifting density variety on top of the env's flat underwater
# baseline. Toggled on/off with .visible from set_active so it costs
# nothing above water.
var _underwater_fog_volume: FogVolume = null
# Optional drifting-particulate GPUParticles3D (group
# "underwater_particulates"). Toggled via .emitting (NOT .visible) so
# existing motes fade out gracefully when the player surfaces instead
# of popping out mid-flight.
var _underwater_particulates: GPUParticles3D = null
var _tween: Tween = null
var _submerged: bool = false


func _ready() -> void:
	_rect.color = tint_color
	_rect.visible = false

	# Resolve the WorldEnvironment and Sun via groups. We do this in
	# _ready so the scene's nodes are already in their groups by the
	# time we look them up. If either is missing (dev scene without
	# day/night), we degrade gracefully — the tint rect still works.
	var we_node := get_tree().get_first_node_in_group("world_environment")
	if we_node != null and we_node is WorldEnvironment:
		_env = (we_node as WorldEnvironment).environment
	_sun = get_tree().get_first_node_in_group("sun_light") as DirectionalLight3D
	if _env == null:
		push_warning("[UnderwaterFilter] no WorldEnvironment in 'world_environment' group; vol-fog underwater murk disabled (tint rect only).")
	if _sun == null:
		push_warning("[UnderwaterFilter] no DirectionalLight3D in 'sun_light' group; god rays disabled.")
	# Cache the water material so we can push sun_direction_world into
	# it once per submerged frame. Same shared instance the bootstrap
	# applies to every fluid model — proven by the [WaterFluidDiag]
	# `same_as_loaded_tres=true` line in the headless probe.
	_water_mat = load(WATER_MATERIAL_PATH) as ShaderMaterial
	if _water_mat == null:
		push_warning("[UnderwaterFilter] failed to load water_material.tres; underside-sun-glint disabled.")
	# Optional FogVolume for animated noise variety. Not required —
	# absent in dev scenes, the env baseline still works.
	_underwater_fog_volume = get_tree().get_first_node_in_group("underwater_fog_volume") as FogVolume
	if _underwater_fog_volume != null:
		_underwater_fog_volume.visible = false
		_fog_volume_mat = _underwater_fog_volume.material as ShaderMaterial
		print("[UnderwaterFilter] resolved UnderwaterFogVolume (variety noise).")
	else:
		print("[UnderwaterFilter] no FogVolume in 'underwater_fog_volume' group — variety patches disabled.")
	# Optional drifting particulates. Same fail-soft pattern.
	_underwater_particulates = get_tree().get_first_node_in_group("underwater_particulates") as GPUParticles3D
	if _underwater_particulates != null:
		_underwater_particulates.emitting = false
		_underwater_particulates.visible = false
		print("[UnderwaterFilter] resolved UnderwaterParticulates.")
	else:
		print("[UnderwaterFilter] no GPUParticles3D in 'underwater_particulates' group — motes disabled.")


func _process(_delta: float) -> void:
	# While submerged, continuously re-target the underwater preset
	# values from the live sun brightness. The tween started in
	# set_active(true) handles the *transition*; once it finishes, we
	# keep the env in sync with day/night here so a sunrise / sunset
	# while the player is underwater is reflected smoothly.
	if not _submerged:
		return
	if _env == null:
		return
	# Only touch env fog params when no tween is mid-flight — letting
	# the tween finish prevents fighting it. After the tween finishes,
	# we own the values directly and lerp toward day/night targets.
	if _tween != null and _tween.is_running():
		return
	var mix: float = _sun_day_mix()
	_env.volumetric_fog_density = lerpf(
		underwater_fog_density_night, underwater_fog_density_noon, mix)
	_env.volumetric_fog_albedo = underwater_fog_albedo_night.lerp(
		underwater_fog_albedo_noon, mix)
	_env.volumetric_fog_emission = underwater_fog_emission_night.lerp(
		underwater_fog_emission_noon, mix)
	if _sun != null:
		_sun.light_volumetric_fog_energy = lerpf(
			underwater_god_ray_energy_night,
			underwater_god_ray_energy_noon,
			mix)
	# Push the live sun direction (world-space, pointing AWAY from sun,
	# i.e. the direction sunlight travels) into the water shader so its
	# back-face branch can render a sun glint on the underside that
	# tracks where the sun actually is. Updated every frame so the
	# glint follows the day/night rotation smoothly.
	if _water_mat != null and _sun != null:
		var light_dir_world: Vector3 = -_sun.global_transform.basis.z.normalized()
		_water_mat.set_shader_parameter("sun_direction_world", light_dir_world)

	# Depth gradient: compute the player's current depth below the
	# surface snapshot, push to BOTH the water shader (back-face
	# brightness attenuation) and the env fog (density modulation).
	# Shallow → less fog + brighter underside; deep → dense fog + dim
	# underside.
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player is Node3D:
		var depth: float = maxf(0.0, _submerge_y_snapshot - (player as Node3D).global_position.y)
		if _water_mat != null:
			_water_mat.set_shader_parameter("underwater_depth_meters", depth)
			_water_mat.set_shader_parameter("depth_for_full_dark", depth_full_dark_meters)
		# Depth-modulate env volumetric_fog_density. Only do this once
		# the submerge tween has settled (else we'd fight the tween).
		if (_tween == null or not _tween.is_running()):
			var depth_t: float = clampf(depth / maxf(depth_full_dark_meters, 0.5), 0.0, 1.0)
			var base_density: float = lerpf(
				underwater_fog_density_night,
				underwater_fog_density_noon,
				mix)
			var density_mult: float = lerpf(
				depth_shallow_density_multiplier,
				depth_deep_density_multiplier,
				depth_t)
			_env.volumetric_fog_density = base_density * density_mult


func set_active(submerged: bool) -> void:
	# Idempotent — Player3D._update_water_state calls every frame; we
	# only act when the state actually flips.
	if _submerged == submerged:
		return
	_submerged = submerged
	# Snapshot the player's Y at submerge as the "water surface" reference
	# for depth-gradient calculations in _process. Cheap, single read per
	# submersion. Approximate — refined each new submersion if the player
	# enters a different water body at a different Y.
	if submerged:
		var player := get_tree().get_first_node_in_group("player")
		if player != null and player is Node3D:
			_submerge_y_snapshot = (player as Node3D).global_position.y + 0.85
			# +0.85 ≈ HEAD_OFFSET so the snapshot is the actual surface
			# Y, not the player pivot Y (head was just below surface).
		# Push the surface Y to the FogVolume's fog shader so it can do
		# depth-modulated density even before the first _process tick.
		if _fog_volume_mat != null:
			_fog_volume_mat.set_shader_parameter("water_surface_y", _submerge_y_snapshot)
			_fog_volume_mat.set_shader_parameter("depth_full_density_meters", depth_full_dark_meters)
	# Tint rect: instant toggle (matches v1 behaviour; no fade needed
	# because the alpha is small).
	_rect.visible = submerged
	# Animated-noise FogVolume: instant toggle (the noise field is
	# already in motion; appearing/disappearing in 1 frame at the
	# water surface boundary reads as expected — the env fog tween
	# below cross-fades the static portion).
	if _underwater_fog_volume != null:
		_underwater_fog_volume.visible = submerged
	# Particulates: toggle BOTH .visible and .emitting. v1 only set
	# .emitting=false on emerge, but existing motes (8-10 s lifetime)
	# then drifted UPWARD past the water surface and were visible
	# floating in mid-air for several seconds — designer reported the
	# bug 2026-05-20. Setting .visible=false on emerge kills them
	# immediately. On submerge, restart the system so new motes emit
	# fresh around the player rather than continuing wherever the
	# previous batch left off.
	if _underwater_particulates != null:
		_underwater_particulates.visible = submerged
		_underwater_particulates.emitting = submerged
		if submerged:
			_underwater_particulates.restart()
	# Tween the env fog and sun god-ray energy between surface and
	# underwater presets. submerge → underwater (target depends on
	# live sun mix); emerge → surface baseline.
	if _env == null:
		return
	# Kill any in-flight tween so we don't fight a still-running one
	# (e.g. player bobs at the surface).
	if _tween != null:
		_tween.kill()
	# Asymmetric tween duration (designer pass 2026-05-20). Submerge is
	# near-instant so the underwater state activates before the player
	# can perceive a "still-above-water" gap as they sink. Emerge stays
	# at the slower 0.5s so the dark fog smoothly cross-fades out
	# (instant-snap on emerge would be a visual jolt back to the bright
	# surface look).
	var dur: float = submerge_transition_seconds if submerged else emerge_transition_seconds
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)
	if submerged:
		var mix: float = _sun_day_mix()
		var target_density: float = lerpf(
			underwater_fog_density_night, underwater_fog_density_noon, mix)
		var target_albedo: Color = underwater_fog_albedo_night.lerp(
			underwater_fog_albedo_noon, mix)
		var target_emission: Color = underwater_fog_emission_night.lerp(
			underwater_fog_emission_noon, mix)
		var target_rays: float = lerpf(
			underwater_god_ray_energy_night,
			underwater_god_ray_energy_noon,
			mix)
		_tween.tween_property(_env, "volumetric_fog_density",
			target_density, dur)
		_tween.tween_property(_env, "volumetric_fog_albedo",
			target_albedo, dur)
		_tween.tween_property(_env, "volumetric_fog_emission",
			target_emission, dur)
		# sky_affect and ambient_inject — drop these underwater so the
		# fog isn't tinted by the bright sky panorama (which produced
		# the "washed sky through water" screenshot 2026-05-20).
		_tween.tween_property(_env, "volumetric_fog_sky_affect",
			underwater_fog_sky_affect, dur)
		_tween.tween_property(_env, "volumetric_fog_ambient_inject",
			underwater_fog_ambient_inject, dur)
		if _sun != null:
			_tween.tween_property(_sun, "light_volumetric_fog_energy",
				target_rays, dur)
	else:
		_tween.tween_property(_env, "volumetric_fog_density",
			surface_fog_density, dur)
		_tween.tween_property(_env, "volumetric_fog_albedo",
			surface_fog_albedo, dur)
		_tween.tween_property(_env, "volumetric_fog_emission",
			surface_fog_emission, dur)
		_tween.tween_property(_env, "volumetric_fog_sky_affect",
			surface_fog_sky_affect, dur)
		_tween.tween_property(_env, "volumetric_fog_ambient_inject",
			surface_fog_ambient_inject, dur)
		if _sun != null:
			_tween.tween_property(_sun, "light_volumetric_fog_energy",
				surface_god_ray_energy, dur)


func _sun_day_mix() -> float:
	# 0 at midnight (sun off), 1 at noon (sun at peak). DayNightCycle
	# animates sun.light_energy via a continuous curve, so this gives
	# us a smooth day/night blend without subscribing to a signal.
	# If the sun ref is missing, default to full daylight rather than
	# full night (more legible default for dev scenes).
	if _sun == null:
		return 1.0
	if sun_noon_energy_ref <= 0.0:
		return 1.0
	return clampf(_sun.light_energy / sun_noon_energy_ref, 0.0, 1.0)
