extends CanvasLayer
# RainOverlay — full-screen rain visual layer.
#
# Two stacked ColorRects:
#   1. TintRect (bottom)   — blue-grey mood tint with alpha modulated by
#                            wetness; the "the world looks wet" feel that
#                            pure fog can't reach.
#   2. StreakRect (top)    — runs `assets/shaders/rain_screen.gdshader`,
#                            two procedural streak layers driven by
#                            `rain_density`, `rain_slant`, parallax and
#                            an aspect uniform pushed each frame.
#
# Weather rework 2026-05 (design/WEATHER_REWORK_2026-05.md → Phase A):
# this replaced the GPUParticles3D rain rig which vanished off-camera and
# read as on/off. Old `set_intensity(value)` API kept for the tint —
# `set_rain` is the new API for the streak layer.
#
# Spawned by WeatherManager in _ready; lives at /root/WeatherManager/RainOverlay.
#
# Reference: design/WEATHER_AND_ENVIRONMENT.md → wet-terrain layered visual


const TINT_COLOR_RGB: Color = Color(0.15, 0.18, 0.22, 0.0)
const MAX_ALPHA: float = 0.18

const _RAIN_SHADER_PATH: String = "res://assets/shaders/rain_screen.gdshader"

var _tint: ColorRect = null
var _streaks: ColorRect = null
var _streak_material: ShaderMaterial = null


func _ready() -> void:
	# Layer 1 — blue-grey tint (legacy behaviour).
	_tint = ColorRect.new()
	_tint.name = "TintRect"
	_tint.color = TINT_COLOR_RGB
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tint)

	# Layer 2 — screen-space streak shader. Built lazily-ish (created here
	# but pushes rain_density=0 until WeatherManager sets it), so the cost
	# at CLEAR is just one full-screen pass with an early-out.
	var shader: Shader = load(_RAIN_SHADER_PATH) as Shader
	if shader != null:
		_streak_material = ShaderMaterial.new()
		_streak_material.shader = shader
		_streaks = ColorRect.new()
		_streaks.name = "StreakRect"
		_streaks.color = Color(1.0, 1.0, 1.0, 1.0)  # ignored by the shader
		_streaks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_streaks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_streaks.material = _streak_material
		add_child(_streaks)
		# Default uniforms — kept consistent with the shader's defaults so a
		# first-frame read doesn't fight them.
		_streak_material.set_shader_parameter("rain_density", 0.0)
		_streak_material.set_shader_parameter("rain_slant", 0.10)
		_streak_material.set_shader_parameter("parallax_offset", Vector2.ZERO)
		_streak_material.set_shader_parameter("aspect", 1.778)
		_streak_material.set_shader_parameter("surface_visibility", 1.0)
	else:
		push_warning("[RainOverlay] failed to load %s — streaks disabled" % _RAIN_SHADER_PATH)


# --- Tint API (legacy — kept for the wetness mood feel) -------------------

func set_intensity(value: float) -> void:
	# Idempotent. value in [0, 1]; gets multiplied by MAX_ALPHA so the input
	# is "how rainy", not "raw alpha".
	if _tint == null:
		return
	var alpha: float = clampf(value, 0.0, 1.0) * MAX_ALPHA
	if absf(_tint.color.a - alpha) < 0.001:
		return
	var c: Color = TINT_COLOR_RGB
	c.a = alpha
	_tint.color = c


# --- Streak shader API (new — drives the screen-space rain layer) ---------

# Push the four per-frame uniforms in one call. Cheap when material is null
# (shader failed to load) — silently no-ops.
#
# density          — 0..1 from WeatherManager._live_rain_density / max.
# slant_radians    — wind-derived screen-space tilt. 0 = vertical streaks.
# parallax         — Vector2 UV offset from camera yaw/pitch; both layers
#                    shift with it so the streaks feel 3D under camera motion.
# surface_visible  — 1.0 above water, ramps to 0.0 underwater (set by the
#                    UnderwaterFilter coupling in WeatherManager).
func set_rain(density: float, slant_radians: float, parallax: Vector2, surface_visible: float) -> void:
	if _streak_material == null:
		return
	_streak_material.set_shader_parameter("rain_density", clampf(density, 0.0, 1.0))
	_streak_material.set_shader_parameter("rain_slant", clampf(slant_radians, -1.5, 1.5))
	_streak_material.set_shader_parameter("parallax_offset", parallax)
	_streak_material.set_shader_parameter("surface_visibility", clampf(surface_visible, 0.0, 1.0))


# Pushed once per viewport resize. WeatherManager polls the viewport size
# each tick — cheap and avoids needing a resize signal handler.
func set_aspect(a: float) -> void:
	if _streak_material == null:
		return
	_streak_material.set_shader_parameter("aspect", maxf(0.5, a))
