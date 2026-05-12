extends Perk

# Disarming Strike  (sword L28, milestone 6)
# 5% chance per sword hit to stagger the target.
#
# 5% proc per sword hit. Calls apply_stagger if the enemy supports it (TODO: stagger system not in production yet — flag is set in ctx for future readers).



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "sword":
		return
	if randf() < 0.05:
		var tgt: Node = ctx.get("target", null)
		if tgt != null and tgt.has_method("apply_stagger"):
			tgt.call("apply_stagger", 1.0)
		ctx["staggered"] = true
