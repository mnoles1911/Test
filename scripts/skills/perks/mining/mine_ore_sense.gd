extends Perk

# Ore Sense  (mining L52, milestone 12)
# Minimap pings within 16 m when ore veins are near.
#
# Minimap system not in production; perk registers as active so it shows owned.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[mine_ore_sense] Active — minimap pings ore within 16 m (minimap pending).")
