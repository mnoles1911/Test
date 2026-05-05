extends Area3D
class_name WeatherZone
# WeatherZone — proximity-triggered weather override.
#
# Place an Area3D with this script in a scene. While the player
# (a body in the "player" group) is inside the zone's
# CollisionShape3D, WeatherManager treats this zone's weather_state
# as the active state — overriding the schedule but yielding to
# story overrides.
#
# Use cases:
#   - Localised micro-climate ("the moor is always foggy")
#   - Approaches to landmarks ("storm clouds gather over the volcano")
#   - Cinematic beats during exploration
#
# Multiple zones can be active at once; the highest priority wins
# (resolved by WeatherManager's stack-based push_proximity_zone /
# pop_proximity_zone API).
#
# Reference: design/WEATHER_AND_ENVIRONMENT.md → proximity trigger


# Weather state name to force while the player is inside. Must match
# one of WeatherManager.STATE_NAMES values ("clear", "fog", etc.).
@export var weather_state: String = "fog"

# Higher priority overrides lower-priority active zones if multiple
# overlap. Default 1; bump to 2/3 for cinematic zones that should
# trump environmental ambiance.
#
# NOTE: named `zone_priority` (not `priority`) because Area3D already
# has a built-in `priority` property for collision-resolution order.
# Using the same name shadows the parent and Godot rejects the script
# with a parse error.
@export var zone_priority: int = 1


func _ready() -> void:
	add_to_group("weather_zone")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Godot's body_entered only fires when bodies TRANSITION into the
	# area. If the player is already inside the zone when the scene
	# loads (common: zone authored to overlap a spawn point), we'd
	# never hear about them. call_deferred so the scene tree + physics
	# space have settled before we read overlapping bodies.
	call_deferred("_check_initial_overlap")


func _check_initial_overlap() -> void:
	# Treat any player-grouped body already inside the area at scene
	# load as if it just entered. Idempotent — re-running is safe
	# because WeatherManager.push_proximity_zone replaces existing
	# entries for the same zone.
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_body_entered(body)
			return


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if get_node_or_null("/root/WeatherManager") == null:
		return
	# Resolve state name -> int. Ignored if the state name is bogus.
	var state_id: int = _resolve_state_id()
	if state_id == -1:
		push_warning("[WeatherZone %s] Unknown weather_state: %s" % [name, weather_state])
		return
	WeatherManager.push_proximity_zone(self, state_id, zone_priority)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if get_node_or_null("/root/WeatherManager") == null:
		return
	WeatherManager.pop_proximity_zone(self)


func _resolve_state_id() -> int:
	if get_node_or_null("/root/WeatherManager") == null:
		return -1
	var lower: String = weather_state.to_lower()
	for state_id in WeatherManager.STATE_NAMES.keys():
		if WeatherManager.STATE_NAMES[state_id] == lower:
			return state_id
	return -1
