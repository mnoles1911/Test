extends Perk

# Archeologist  (excavation L40, milestone 9)
# 5% chance to unearth a small treasure when digging.
#
# 5% per dig: unearth a small treasure (5 coin).



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "excavation":
		return
	if randf() > 0.05:
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv == null:
		return
	if inv.has_method("add_coin"):
		inv.call("add_coin", 5)
