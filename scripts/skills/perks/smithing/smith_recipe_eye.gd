extends Perk

# Recipe Eye  (smithing L52, milestone 12)
# Forge UI highlights ingredients that match a known recipe.
#
# Forge UI not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[smith_recipe_eye] Active — forge UI highlights recipe-matching ingredients (UI pending).")
