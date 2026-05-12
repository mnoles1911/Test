extends Perk

# Battle Rhythm  (sword L68, milestone 16)
# Each consecutive sword hit within 3 s adds +3% damage (cap +24%).
#
# Pattern B: stacking +3% damage per consecutive sword hit (3-s decay window), cap +24%.

var _stacks: int = 0
var _last_hit: float = 0.0

func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "sword":
		return
	var t: float = Time.get_ticks_msec() / 1000.0
	if t - _last_hit > 3.0:
		_stacks = 0
	_stacks = min(_stacks + 1, 8)
	_last_hit = t
	var bonus: float = 0.03 * float(_stacks - 1)
	if bonus > 0.0:
		ctx["damage"] = int(ctx.get("damage", 0) * (1.0 + bonus))
