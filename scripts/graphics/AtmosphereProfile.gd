extends Resource
# AtmosphereProfile — the hand-tuned colour anchors that drive the
# time-of-day sky tint, sun/moon light colour, and fog.
#
# Phase G of the graphics roadmap (design/GRAPHICS_PASS_2026-05-19.md).
#
# What this is, in plain English:
#
#   DayNightCycle.gd ramps the world between four times of day (dawn,
#   noon, dusk, night). It used to carry every colour it ramps through
#   as a `const` wedged in among the control-flow code. This file pulls
#   those colours out into one tidy data object — a "profile" — so that:
#
#     - art tuning lives in one place, as data, not buried in code;
#     - a weather state or a biome can hand DayNightCycle a DIFFERENT
#       profile and the whole palette swaps with no code change. (That
#       is the groundwork for Water Phase 4c — per-biome underwater fog.)
#
# Scope note: the graphics roadmap also floated folding WeatherManager's
# per-state fog into here. That is deliberately NOT done. WeatherManager
# .STATE_PROFILES is already a clean designer-tunable table where each
# state's fog sits alongside its ambient / wind / cloud / particle
# values — splitting fog out would break that cohesion for no gain.
# AtmosphereProfile owns the TIME-OF-DAY anchors only.
#
# Why no `class_name`:
#
#   DayNightCycle preloads this file by path. That is the same rule
#   ShaderProfile.gd and WaterMaterial.gd follow, so the headless test
#   harness — which does not rescan global classes — still parses every
#   script that touches it. Do not add a class_name.
#
# The shipped look:
#
#   Every @export below already defaults to the exact value DayNightCycle
#   shipped with. So a plain `AtmosphereProfile.new()` IS the shipped
#   look, and a world with no profile assigned is unchanged. Never edit a
#   default here without an intentional art decision.

# --- Sun light colour at the three key times of day ---
@export var sun_color_dawn: Color = Color(1.0, 0.65, 0.35)  # orange-pink
@export var sun_color_noon: Color = Color(1.0, 0.97, 0.92)  # warm white
@export var sun_color_dusk: Color = Color(1.0, 0.45, 0.25)  # red-orange

# --- Moon light colour (constant across the night) ---
@export var moon_color: Color = Color(0.55, 0.65, 0.85)     # cool pale blue

# --- Sky dome tint — top of the dome, four times of day ---
@export var sky_top_dawn: Color  = Color(0.32, 0.30, 0.42)
@export var sky_top_noon: Color  = Color(0.32, 0.58, 0.82)
@export var sky_top_dusk: Color  = Color(0.30, 0.20, 0.30)
@export var sky_top_night: Color = Color(0.04, 0.05, 0.10)

# --- Sky dome tint — horizon band, four times of day ---
@export var sky_horizon_dawn: Color  = Color(0.95, 0.55, 0.40)
@export var sky_horizon_noon: Color  = Color(0.70, 0.85, 0.95)
@export var sky_horizon_dusk: Color  = Color(0.95, 0.35, 0.20)
@export var sky_horizon_night: Color = Color(0.06, 0.08, 0.14)

# --- Depth fog tint (day vs night) ---
@export var fog_color_day: Color   = Color(0.55, 0.65, 0.78)
@export var fog_color_night: Color = Color(0.05, 0.07, 0.10)

# --- Volumetric fog albedo (day vs night) ---
# The night value is near-black so the volumetric layer (sky_affect 0.5)
# does not wash the night sky pale blue.
@export var vol_fog_albedo_day: Color   = Color(0.85, 0.88, 0.95)
@export var vol_fog_albedo_night: Color = Color(0.06, 0.08, 0.14)
