extends Perk

# Focused Blast  (demolition L44, milestone 10)
# Explosions deal +30% damage in a 30° forward cone.
#
# Demo system sets ctx.cone_forward for enemies in a 30° forward cone.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("detonation_source", "") != "powder_charge":
		return
	if not ctx.get("cone_forward", false):
		return
	ctx["damage"] = int(ctx.get("damage", 0) * 1.30)
