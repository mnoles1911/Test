extends Perk

# Split Wood  (felling L100, milestone 24)
# Killing an enemy with an axe drops kindling.
#
# Axe-killing an enemy drops kindling.



func _init() -> void:
	pass

func on_kill(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "sword" and ctx.get("weapon", "") != "axe":
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv != null and inv.has_method("add_item"):
		inv.call("add_item", "raw_leaves", 1)
