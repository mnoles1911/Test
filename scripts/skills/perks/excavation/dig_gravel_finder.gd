extends Perk

# Gravel Finder  (excavation L24, milestone 5)
# +25% chance to expose gravel disk when near water.
#
# 25% proc near water: gravel drop.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "excavation":
		return
	if not ctx.get("near_water", false):
		return
	if randf() > 0.25:
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv != null and inv.has_method("add_item"):
		inv.call("add_item", "raw_gravel", 1)
