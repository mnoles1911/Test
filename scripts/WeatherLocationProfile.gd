extends Resource
class_name WeatherLocationProfile
# WeatherLocationProfile — per-region weather authoring data.
#
# A profile is a designer-authored .tres asset that tells WeatherManager:
#   - what scheduled state to use on each of the first few days
#     (authored_sequence — for deterministic scripted openings)
#   - how to weight random rolls beyond the authored window
#     (random_distribution — sums to ~1.0)
#   - which hours of the in-game day the schedule rolls a new state
#     (transition_hours)
#
# Mira-Thal locations have very different climates (Aldenholt is wet
# and overcast; Solgrade is sunny and dry; the Ash-lands are dust-storm
# territory). Each region gets one profile; the active profile is
# swapped via WeatherManager.set_location_profile when the player
# crosses a region boundary (Phase 11+ wiring — not yet automatic).
#
# v1 ships one default profile (assets/profiles/aldenholt.tres). Add
# new profiles by creating a new Resource of this type in the inspector.
#
# Reference: design/WEATHER_AND_ENVIRONMENT.md → per-region weather


# Stable identifier — used in save data and debug logs.
@export var profile_id: String = "default"

# Fixed weather sequence for the first N in-game days. Index 0 is
# day 1, index 1 is day 2, etc. Each int is a WeatherManager.State
# value. Empty array = pure-random from day 1.
#
# Authoring tip: open with at least 2 deterministic days so the player
# experiences clear weather while learning controls, then let random
# take over.
@export var authored_sequence: Array[int] = []

# Weighted random distribution applied beyond authored_sequence.
# Keys are WeatherManager.State int values; values are floats that
# sum to ~1.0 (WeatherManager normalises by cumulative roll). Missing
# states get 0% probability.
@export var random_distribution: Dictionary = {
	0: 0.40,  # CLEAR
	1: 0.30,  # OVERCAST
	2: 0.15,  # LIGHT_RAIN
	3: 0.05,  # HEAVY_RAIN
	4: 0.07,  # FOG
	5: 0.03,  # SNOW
}

# In-game hours (0–23) when the schedule rolls a new state. Default
# 06:00 / 12:00 / 18:00 — three rolls per day, paced at ~8h apart.
@export var transition_hours: Array[int] = [6, 12, 18]
