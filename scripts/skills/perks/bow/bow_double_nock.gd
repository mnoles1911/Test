extends Perk

# Double Nock  (bow L36, milestone 8)
# 10% chance to fire a free second arrow per shot.
#
# 10% proc: caller fires a second arrow. TODO: bow firing system not in production.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "bow":
		return
	if randf() < 0.10:
		ctx["fire_extra_arrow"] = true
