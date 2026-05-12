extends Perk

# Second Wind  (sword L76, milestone 18)
# Once per fight, regain 30% endurance when it hits 0.
#
# Once-per-fight: when stamina hits 0 from damage, refund 30%. Pattern A. Fight-boundary heuristic is reset on kill.

var _used_this_fight: bool = false

func _init() -> void:
	pass

func on_take_damage(ctx: Dictionary) -> void:
	if _used_this_fight:
		return
	if Engine.get_main_loop() == null:
		return
	var player: Node = Engine.get_main_loop().root.get_node_or_null("World3D/Player3D")
	if player == null:
		return
	var stam: float = float(player.get("endurance")) if "endurance" in player else 0.0
	var maxstam: float = float(player.get("max_endurance")) if "max_endurance" in player else 100.0
	if stam <= 0.01:
		_used_this_fight = true
		player.set("endurance", maxstam * 0.30)


func on_kill(ctx: Dictionary) -> void:
	_used_this_fight = false  # arbitrary fight-end heuristic: kill resets the once-per-fight flag
