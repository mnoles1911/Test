extends Perk

# Grand Strike  (sword L84, milestone 20)
# +50% damage on first sword hit after entering combat.
#
# +50% damage on first sword hit after entering combat. Combat system marks ctx.first_hit on the opening swing.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "sword":
		return
	if not ctx.get("first_hit", false):
		return
	ctx["damage"] = int(ctx.get("damage", 0) * 1.50)
