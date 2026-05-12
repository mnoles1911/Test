extends Perk

# Tree Sense  (felling L28, milestone 6)
# Outlines the felling-direction line on a tree trunk.
#
# Visual TODO.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[fell_tree_sense] Active — tree felling-line highlight when axe drawn (renderer hook pending).")
