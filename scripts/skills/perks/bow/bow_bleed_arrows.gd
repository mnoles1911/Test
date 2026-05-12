extends Perk

# Bleed Arrows  (bow L40, milestone 9)
# Bow hits apply 1 dmg/s bleed for 6 s.
#
# Apply 1 dmg/s bleed for 6 s on bow hit.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "bow":
		return
	var tgt: Node = ctx.get("target", null)
	if tgt != null and tgt.has_method("apply_dot"):
		tgt.call("apply_dot", "bleed", 1.0, 6.0)
