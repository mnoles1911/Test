extends CanvasLayer
# RainOverlay — full-screen mood tint applied during rainy weather.
#
# Mirrors the UnderwaterFilter pattern: a CanvasLayer with one
# translucent ColorRect child that fills the viewport. The alpha
# of the tint is set per-frame by WeatherManager so the overlay
# fades in/out smoothly with the rest of the state transition.
#
# Why this isn't a fog tweak: DayNightCycle owns fog. WeatherManager
# pushes fog through the override hook, but adding "screen-tint"
# darkening on top of that creates the "the world looks wet" mood
# that pure fog can't reach (fog gets denser with distance, but
# the screen still reads bright in close-up).
#
# Spawned by WeatherManager in _ready; lives at /root/WeatherManager/RainOverlay.
#
# Reference: design/WEATHER_AND_ENVIRONMENT.md → wet-terrain layered visual


# Final colour (RGB tuned blue-grey for "rain mood"). Alpha is overwritten
# per-frame by set_intensity().
const TINT_COLOR_RGB: Color = Color(0.15, 0.18, 0.22, 0.0)
# Maximum overlay alpha. 0.18 is enough to read as "rainy" without
# crushing visibility.
const MAX_ALPHA: float = 0.18

var _rect: ColorRect = null


func _ready() -> void:
	# Build the rect child programmatically so this script doesn't
	# require a .tscn companion. Fills the viewport via anchor preset.
	_rect = ColorRect.new()
	_rect.name = "TintRect"
	_rect.color = TINT_COLOR_RGB
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func set_intensity(value: float) -> void:
	# Idempotent. value in [0, 1]; gets multiplied by MAX_ALPHA so the
	# input is "how rainy", not "raw alpha".
	if _rect == null:
		return
	var alpha: float = clampf(value, 0.0, 1.0) * MAX_ALPHA
	if absf(_rect.color.a - alpha) < 0.001:
		return
	var c: Color = TINT_COLOR_RGB
	c.a = alpha
	_rect.color = c
