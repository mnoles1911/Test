extends Perk

# Water Finder  (excavation L48, milestone 11)
# Pings nearby water table within 12 m.
#
# Visual TODO.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[dig_water_finder] Active — minimap pings water table within 12 m (minimap pending).")
