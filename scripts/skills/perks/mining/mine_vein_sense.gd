extends Perk

# Vein Sense  (mining L16, milestone 3)
# Briefly outlines ore veins within 8 m when a pickaxe is drawn.
#
# Visual perk. EditToolHandler queries PerkQuery.has_flag("ore", "while_pickaxe") to enable highlight.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[mine_vein_sense] Active — ore-vein highlights when pickaxe drawn (renderer hook pending).")
