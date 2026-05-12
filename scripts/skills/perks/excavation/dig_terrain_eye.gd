extends Perk

# Terrain Eye  (excavation L44, milestone 10)
# Outline buried objects within 4 m.
#
# Visual TODO.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[dig_terrain_eye] Active — buried objects highlight within 4 m (renderer pending).")
