extends Perk

# Smoker  (demolition L52, milestone 12)
# Explosions leave a 5 s smoke cloud blinding enemies.
#
# Sets a flag for PowderCharge to spawn a 5-s smoke cloud (TODO: smoke particle scene not in production).



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("detonation_source", "") != "powder_charge":
		return
	ctx["leave_smoke_seconds"] = 5.0
