extends Perk

# Tripwise  (excavation L96, milestone 23)
# Reveal pressure plates within 4 m while a shovel is drawn.
#
# Trap system not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[dig_no_traps] Active — pressure plates highlight within 4 m (trap system pending).")
