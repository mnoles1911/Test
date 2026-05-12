extends Perk

# Lucky Strike  (mining L72, milestone 17)
# 5% chance per break to drop a gem.
#
# 5% per mining break: spawn bonus drop. Uses marble as a stand-in until a gem item id is added.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "mining":
		return
	if randf() > 0.05:
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv != null and inv.has_method("add_item"):
		inv.call("add_item", "raw_marble", 1)  # gem stand-in until gem item id lands
