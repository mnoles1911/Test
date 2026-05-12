extends Perk

# Taster  (alchemy L28, milestone 6)
# Reveal first effect of unknown ingredients by tasting.
#
# Ingredient taste flow not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[alch_taster] Active — taste an unknown ingredient to reveal first effect (UI pending).")
