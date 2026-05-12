extends Perk

# Double Brew  (alchemy L44, milestone 10)
# +25% chance to craft 2 potions instead of 1.
#
# Wired at craft-time, not consumption-time. Hook here is a no-op intentionally.



func _init() -> void:
	pass

func on_potion_drunk(ctx: Dictionary) -> void:
	pass  # AlchemyStation reads PerkQuery.sum('proc_chance', 'potion', {'on_craft': true}) at craft time.
