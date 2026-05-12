extends Perk

# Hidden Caches  (lockpicking L48, milestone 11)
# Reveal hidden cache markers within 16 m.
#
# Cache discovery system not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[lock_hidden_caches] Active — hidden cache markers within 16 m (cache system pending).")
