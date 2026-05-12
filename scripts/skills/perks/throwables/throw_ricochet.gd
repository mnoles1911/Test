extends Perk

# Ricochet  (throwables L36, milestone 8)
# Thrown spears bounce once off terrain.
#
# First terrain hit on a thrown spear flips request_ricochet so ThrowableSpear can spawn a follow-up. TODO: ThrowableSpear ricochet path not in production.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "throwables":
		return
	if ctx.get("surface_hit", false) and not ctx.get("ricochet_used", false):
		ctx["ricochet_used"] = true
		ctx["request_ricochet"] = true
