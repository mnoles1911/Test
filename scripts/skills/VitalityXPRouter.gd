extends Node
class_name VitalityXPRouter

# Child of Player3D. Grants Vitality XP for passive survival actions
# (swimming for sustained periods, eating food). Fall-damage and
# hunger Vitality XP will hook in once those systems land — for now
# this router covers swimming, which is the only Vitality-relevant
# system in production today.
#
# Tuning:
#   Swimming: 1 XP per SWIM_TICK_SECONDS continuously submerged.

const SWIM_TICK_SECONDS: float = 5.0

var _swim_accum: float = 0.0

func _physics_process(delta: float) -> void:
	var player := get_parent()
	if player == null:
		return
	# Read public state from Player3D. The "_in_water" private field
	# is exposed via the get() interface on the script — falling back
	# to false if the field isn't present (defensive against future
	# refactors that rename it).
	var in_water: bool = false
	if "_in_water" in player:
		in_water = bool(player.get("_in_water"))
	if in_water:
		_swim_accum += delta
		while _swim_accum >= SWIM_TICK_SECONDS:
			_swim_accum -= SWIM_TICK_SECONDS
			if get_node_or_null("/root/SkillManager"):
				SkillManager.add_xp("vitality", 1.0)
	else:
		_swim_accum = 0.0
