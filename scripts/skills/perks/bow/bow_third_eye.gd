extends Perk

# Third Eye  (bow L88, milestone 21)
# On a hit, briefly outline the target through walls.
#
# Bow hit outlines target through walls for 5 s. TODO: x-ray outline shader pass not in production.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "bow":
		return
	var tgt: Node = ctx.get("target", null)
	if tgt != null and tgt.has_method("set_xray_outline"):
		tgt.call("set_xray_outline", true, 5.0)
