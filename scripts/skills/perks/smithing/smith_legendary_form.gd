extends Perk

# Legendary Form  (smithing L92, milestone 22)
# Crafts at 100 condition with perfect rhythm get +1 tier.
#
# Wired at craft-time.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[smith_legendary_form] Active — perfect-rhythm crafts get +1 tier (SmithingForge reads PerkQuery).")
