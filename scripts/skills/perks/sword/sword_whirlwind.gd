extends Perk

# Whirlwind  (sword L40, milestone 9)
# Power attacks hit all enemies within 1.5 m.
#
# Power attacks gain a 1.5 m AoE. Caller (combat system) reads ctx.aoe_radius to apply to all enemies in range.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if not ctx.get("power_attack", false):
		return
	if ctx.get("skill", "") != "sword":
		return
	ctx["aoe_radius"] = max(float(ctx.get("aoe_radius", 0.0)), 1.5)
