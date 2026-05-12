extends Perk

# Runed  (smithing L64, milestone 15)
# 1 in 5 crafts produces a +1 quality result.
#
# Wired at craft-time in SmithingForge.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[smith_runed] Active — 1/5 forge crafts produce +1 quality result (SmithingForge reads PerkQuery on craft).")
