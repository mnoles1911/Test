extends Perk

# Master Form  (smithing L40, milestone 9)
# Crafted weapons grant +5% damage with that weapon type.
#
# +5% damage when using a weapon Roland smithed himself. Combat code sets ctx.self_made by reading the equipped item's metadata.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if not ctx.get("self_made", false):
		return
	ctx["damage"] = int(ctx.get("damage", 0) * 1.05)
