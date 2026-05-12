extends Perk

# Volley  (bow L68, milestone 16)
# Each consecutive hit within 3 s adds +5% damage (cap +30%).
#
# Pattern B: +5% per consecutive bow hit, 3-s decay, cap +30%.

var _stacks: int = 0
var _last_hit: float = 0.0

func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "bow":
		return
	var t: float = Time.get_ticks_msec() / 1000.0
	if t - _last_hit > 3.0:
		_stacks = 0
	_stacks = min(_stacks + 1, 6)
	_last_hit = t
	var bonus: float = 0.05 * float(_stacks - 1)
	if bonus > 0.0:
		ctx["damage"] = int(ctx.get("damage", 0) * (1.0 + bonus))
