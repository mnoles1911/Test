extends Perk

# Storm Caller  (throwables L88, milestone 21)
# Detonating a powder charge near another causes both to chain.
#
# Powder charges flag chain_explode in ctx so PowderCharge.gd can detect neighboring charges and trigger them. TODO: PowderCharge chain-detect not in production.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "throwables":
		return
	if ctx.get("detonation_source", "") == "powder_charge":
		ctx["chain_explode"] = true
