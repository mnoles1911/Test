extends Perk

# Evergreen  (felling L76, milestone 18)
# Tree drops include +1 sapling per 10 felled.
#
# Every 10th tree felled drops a sapling (placeholder: raw_leaves).

var _trees_felled: int = 0

func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "felling":
		return
	if not ctx.get("on_tree_break", false):
		return
	_trees_felled += 1
	if _trees_felled % 10 != 0:
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv != null and inv.has_method("add_item"):
		inv.call("add_item", "raw_leaves", 1)  # sapling stand-in
