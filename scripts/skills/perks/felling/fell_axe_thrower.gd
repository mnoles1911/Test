extends Perk

# Axe Thrower  (felling L72, milestone 17)
# Axes can be thrown (1-shot consumable until recovered).
#
# Flag perk. ThrowableHandler checks PerkQuery.has_flag("axe") when LMB-throw is held on an axe.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[fell_axe_thrower] Active — axes can be thrown (ThrowableHandler reads flag at draw time).")
