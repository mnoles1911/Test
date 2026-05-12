extends Perk

# Thicket  (sword L48, milestone 11)
# +10% damage per additional enemy within 3 m (cap +40%).
#
# +10% damage per extra enemy within 3 m, cap +40%. Reads ctx.extra_enemies set by combat code.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "sword":
		return
	var extra: int = int(ctx.get("extra_enemies", 0))
	var bonus: float = clampf(0.10 * float(extra), 0.0, 0.40)
	if bonus > 0.0:
		ctx["damage"] = int(ctx.get("damage", 0) * (1.0 + bonus))
