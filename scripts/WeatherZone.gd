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
# (resolved by WeatherManager.set_proximity_state which tracks a stack).
#
# Reference: design/WEATHER_AND_ENVIRONMENT.md → proximity trigger


# Weather state name to force while the player is inside. Must match
# one of WeatherManager.STATE_NAMES values ("clear", "fog", etc.).
@export var weather_state: String = "fog"

# Higher priority overrides lower-priority active zones if multiple
# overlap. Default 1; bump to 2/3 for cinematic zones that should
# trump environmental ambiance.
@export var priority: int = 1


func _ready() -> void:
	add_to_group("weather_zone")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


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
	WeatherManager.push_proximity_zone(self, state_id, priority)


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
