extends Perk

# Keen Nose  (alchemy L4, milestone 0)
# Reveal herb gather points within 8 m.
#
# Visual TODO.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[alch_keen_nose] Active — herb gather points highlight within 8 m (renderer pending).")
