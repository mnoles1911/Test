extends Perk

# Double Grab  (throwables L32, milestone 7)
# Drawing a spear pulls 2 into hand (if 2+ in inventory).
#
# Pure flag perk; ThrowableHandler queries PerkQuery.has_flag("spear") at draw time.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[throw_double_grab] Active — drawing a spear pulls 2 (UI surfaces via ThrowableHandler).")
