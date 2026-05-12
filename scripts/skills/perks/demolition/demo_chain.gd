extends Perk

# Chain Reaction  (demolition L24, milestone 5)
# +50% chance a nearby charge chains on detonation.
#
# PowderCharge dispatches on_attack with detonation_source set; perk flags chain_explode for the engine to detonate neighbors.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("detonation_source", "") != "powder_charge":
		return
	if randf() < 0.50:
		ctx["chain_explode"] = true
