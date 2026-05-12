extends Perk

# Charged Throw  (throwables L44, milestone 10)
# Held throws (1 s) deal +30% damage and +10% range.
#
# ThrowableHandler sets ctx.charged when the throw was held ≥1 s before release.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "throwables":
		return
	if not ctx.get("charged", false):
		return
	ctx["damage"] = int(ctx.get("damage", 0) * 1.30)
	ctx["range_mult"] = float(ctx.get("range_mult", 1.0)) * 1.10
