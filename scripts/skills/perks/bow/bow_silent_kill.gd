extends Perk

# Silent Kill  (bow L28, milestone 6)
# Bow kills outside combat do not alert nearby enemies.
#
# Out-of-combat bow kills don't alert nearby enemies. Sets ctx.suppress_alert flag. TODO: stealth/aggro broadcast not wired yet.



func _init() -> void:
	pass

func on_kill(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "bow":
		return
	if not ctx.get("stealth", false):
		return
	ctx["suppress_alert"] = true  # combat / AI systems suppress aggro alert
