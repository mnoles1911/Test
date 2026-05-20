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
@export var underwater_fog_density_noon: float = 0.30
@export var underwater_fog_density_night: float = 0.70
# Albedo channels are TUNED FOR "DARKER BLUE": B kept noticeably above
# R+G so the murk reads cobalt rather than teal (the earlier 0.30 G
# made noon read green). Raise G back toward 0.20 if you want
# teal-leaning underwater (tropical-reef look) instead of dark cobalt.
@export var underwater_fog_albedo_noon: Color = Color(0.06, 0.14, 0.32, 1.0)
@export var underwater_fog_albedo_night: Color = Color(0.01, 0.03, 0.08, 1.0)
# Emission is fog glowing on its own. Near-zero values let albedo +
# scene lighting define the colour — keeps the look "committed dark"
# instead of lifted/washed.
@export var underwater_fog_emission_noon: Color = Color(0.01, 0.02, 0.03, 1.0)
@export var underwater_fog_emission_night: Color = Color(0.00, 0.00, 0.00, 1.0)
# Sun.light_volumetric_fog_energy — the god-ray dial. 0 = invisible
# (default Godot), bigger = brighter shafts. 6.0 at noon reads as
# "clear sunbeams in the water column"; 0.2 at night = faint moon hint.
@export var underwater_god_ray_energy_noon: float = 6.0
@export var underwater_god_ray_energy_night: float = 0.2


# --- Above-water (surface) restore values --------------------------------
# Matches the baseline already set in scenes/World3D.tscn Environment_1.
# Used as the tween target when set_active(false) — we restore the
# scene's pre-submerge atmospheric haze look.
@export var surface_fog_density: float = 0.015
@export var surface_fog_albedo: Color = Color(0.85, 0.88, 0.95, 1.0)
@export var surface_fog_emission: Color = Color(0.00, 0.00, 0.00, 1.0)
@export var surface_god_ray_energy: float = 0.0


# --- Behaviour knobs -----------------------------------------------------
@export var transition_seconds: float = 0.5
# Sun.light_energy peak — DayNightCycle uses 2.2 at noon (see
# DayNightCycle.SUN_ENERGY_DAY). The day/night mix factor divides the
# observed energy by this, so 2.2 = full "noon" preset. Tune if the
# day-curve changes.
@export var sun_noon_energy_ref: float = 2.2


@onready var _rect: ColorRect = $TintRect

var _env: Environment = null
var _sun: DirectionalLight3D = null
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


func set_active(submerged: bool) -> void:
	# Idempotent — Player3D._update_water_state calls every frame; we
	# only act when the state actually flips.
	if _submerged == submerged:
		return
	_submerged = submerged
	# Tint rect: instant toggle (matches v1 behaviour; no fade needed
	# because the alpha is small).
	_rect.visible = submerged
	# Tween the env fog and sun god-ray energy between surface and
	# underwater presets. submerge → underwater (target depends on
	# live sun mix); emerge → surface baseline.
	if _env == null:
		return
	# Kill any in-flight tween so we don't fight a still-running one
	# (e.g. player bobs at the surface).
	if _tween != null:
		_tween.kill()
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
			target_density, transition_seconds)
		_tween.tween_property(_env, "volumetric_fog_albedo",
			target_albedo, transition_seconds)
		_tween.tween_property(_env, "volumetric_fog_emission",
			target_emission, transition_seconds)
		if _sun != null:
			_tween.tween_property(_sun, "light_volumetric_fog_energy",
				target_rays, transition_seconds)
	else:
		_tween.tween_property(_env, "volumetric_fog_density",
			surface_fog_density, transition_seconds)
		_tween.tween_property(_env, "volumetric_fog_albedo",
			surface_fog_albedo, transition_seconds)
		_tween.tween_property(_env, "volumetric_fog_emission",
			surface_fog_emission, transition_seconds)
		if _sun != null:
			_tween.tween_property(_sun, "light_volumetric_fog_energy",
				surface_god_ray_energy, transition_seconds)


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
