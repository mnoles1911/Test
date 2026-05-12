extends Perk

# Javelin Storm  (throwables L92, milestone 22)
# Killing with a spear refunds 50% chance to find the spear at the corpse.
#
# 50% chance to refund a spear on thrown kill (the spear may stay stuck in the corpse anyway; this is bonus on top).



func _init() -> void:
	pass

func on_kill(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "throwables":
		return
	if randf() > 0.50:
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv != null and inv.has_method("add_item"):
		inv.call("add_item", "spear", 1)
