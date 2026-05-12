extends Perk

# Versatility  (alchemy L88, milestone 21)
# Drinking 2 potions within 5 s doesn't break stack rules.
#
# Wired via flag query at stack-check time.



func _init() -> void:
	pass

func on_potion_drunk(ctx: Dictionary) -> void:
	pass  # Effect: drinking 2 potions within 5 s bypasses stack rules. Potion-stack manager (when wired) checks PerkQuery.has_flag('potion','').
