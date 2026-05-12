extends Perk

# Sword's Dance  (sword L80, milestone 19)
# +10% damage and -10% endurance cost while moving with sword.
#
# Conditional damage + stamina mult while moving with sword drawn. Pattern C.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if not ctx.get("moving", false):
		return
	if ctx.get("skill", "") != "sword":
		return
	ctx["damage"] = int(ctx.get("damage", 0) * 1.10)
	ctx["stamina_cost_mult"] = float(ctx.get("stamina_cost_mult", 1.0)) * 0.90
