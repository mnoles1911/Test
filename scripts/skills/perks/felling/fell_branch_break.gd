extends Perk

# Branch Break  (felling L48, milestone 11)
# Felling a tree drops kindling for campfires.
#
# Tree fell → kindling. Uses raw_leaves as kindling stand-in until a kindling item lands.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "felling":
		return
	if not ctx.get("on_tree_break", false):
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv != null and inv.has_method("add_item"):
		inv.call("add_item", "raw_leaves", 2)  # kindling stand-in
