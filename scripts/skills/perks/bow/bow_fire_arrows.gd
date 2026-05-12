extends Perk

# Fire Arrows  (bow L44, milestone 10)
# Bow hits ignite for 2 dmg/s, 4 s.
#
# Apply 2 dmg/s burn for 4 s on bow hit.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "bow":
		return
	var tgt: Node = ctx.get("target", null)
	if tgt != null and tgt.has_method("apply_dot"):
		tgt.call("apply_dot", "burn", 2.0, 4.0)
