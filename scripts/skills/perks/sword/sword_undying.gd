extends Perk

# Undying  (sword L92, milestone 22)
# Once per day, surviving a killing blow leaves you at 1 HP.
#
# Once-per-day: lethal damage leaves player at 1 HP. Caller must populate ctx.self_hp before calling on_take_damage. Day reset wires onto WorldClock.day_changed when that hook lands.

var _used_today: bool = false

func _init() -> void:
	pass

func on_take_damage(ctx: Dictionary) -> void:
	var amt: int = int(ctx.get("amount", 0))
	if amt < int(ctx.get("self_hp", 999999)):
		return
	if _used_today:
		return
	_used_today = true
	ctx["amount"] = max(int(ctx.get("self_hp", 1)) - 1, 0)
	ctx["undying_proc"] = true


func on_xp_gained(ctx: Dictionary) -> void:
	pass  # day-boundary reset wired when WorldClock day_changed signal is hooked in
