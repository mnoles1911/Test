extends Perk

# Recipe Eye  (alchemy L48, milestone 11)
# Reveal recipe matches when 2 ingredients in cauldron.
#
# Recipe UI not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[alch_recipe_eye] Active — recipe matches highlight in cauldron UI (UI pending).")
