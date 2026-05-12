extends Perk

# Bleed  (sword L32, milestone 7)
# Sword hits apply a bleed dealing 1 dmg/s for 6 s.
#
# Apply 1 dmg/s bleed for 6 s. Uses Enemy3D.apply_dot if present, else stashes the DoT request in ctx for whoever wires DoT next.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "sword":
		return
	var tgt: Node = ctx.get("target", null)
	if tgt == null:
		return
	if tgt.has_method("apply_dot"):
		tgt.call("apply_dot", "bleed", 1.0, 6.0)
	else:
		ctx["pending_dot"] = {"type": "bleed", "dps": 1.0, "duration": 6.0}
