extends Perk

# Volley  (throwables L68, milestone 16)
# Each thrown weapon hit reduces the next throw's endurance cost by 50% for 3 s.
#
# Each throw discounts the next one's stamina by 50% for 3 s. ThrowableHandler reads ctx.next_stamina_discount on the following throw.

var _next_throw_discount_until: float = 0.0

func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "throwables":
		return
	var t: float = Time.get_ticks_msec() / 1000.0
	_next_throw_discount_until = t + 3.0
	ctx["next_stamina_discount"] = 0.50
