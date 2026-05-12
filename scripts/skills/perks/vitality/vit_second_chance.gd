extends Perk

# Second Chance  (vitality L64, milestone 15)
# Once per day, the next lethal blow leaves you at 1 HP.
#
# Same shape as sword_undying but on Vitality instead of Sword.

var _used_today: bool = false

func _init() -> void:
	pass

func on_take_damage(ctx: Dictionary) -> void:
	if _used_today:
		return
	var amt: int = int(ctx.get("amount", 0))
	if amt < int(ctx.get("self_hp", 999999)):
		return
	_used_today = true
	ctx["amount"] = max(int(ctx.get("self_hp", 1)) - 1, 0)
	ctx["second_chance_proc"] = true
