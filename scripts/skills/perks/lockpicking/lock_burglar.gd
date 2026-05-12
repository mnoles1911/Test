extends Perk

# Burglar  (lockpicking L60, milestone 14)
# Open locks 30% faster on the third+ attempt of an evening.
#
# After 3rd+ attempt this evening, picking is 30% faster. LockpickingUI reads PerkQuery (with ctx.attempts >= 3) at start.

var _attempts_today: int = 0

func _init() -> void:
	pass

func on_lock_opened(ctx: Dictionary) -> void:
	_attempts_today += 1
	if _attempts_today >= 3:
		print("[lock_burglar] Speed-up active (3rd+ attempt this evening).")
