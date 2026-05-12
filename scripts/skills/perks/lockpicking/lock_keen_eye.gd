extends Perk

# Keen Eye  (lockpicking L52, milestone 12)
# Reveal pick sweet spot for 1 s on entry.
#
# Flag for LockpickingUI hint.



func _init() -> void:
	pass

func on_lock_opened(ctx: Dictionary) -> void:
	pass  # LockpickingUI reads PerkQuery.has_flag('lock','on_enter') at open time to flash sweet spot.
