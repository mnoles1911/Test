extends Perk

# Perfect Aim  (throwables L72, milestone 17)
# First thrown weapon of an encounter has -50% spread.
#
# Once per encounter: first thrown weapon has -50% spread. ThrowableHandler reads ctx.spread_mult at aim time.

var _used_this_combat: bool = false

func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if _used_this_combat:
		return
	if ctx.get("skill", "") != "throwables":
		return
	if not ctx.get("first_hit", false):
		return
	_used_this_combat = true
	ctx["spread_mult"] = float(ctx.get("spread_mult", 1.0)) * 0.50


func on_kill(ctx: Dictionary) -> void:
	_used_this_combat = false  # crude combat-end reset
