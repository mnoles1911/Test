extends Perk

# Grave Robber  (excavation L36, milestone 8)
# Excavating dropped corpses yields +1 random crafting mat.
#
# Digging on a corpse yields a random crafting mat.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "excavation":
		return
	if not ctx.get("on_corpse", false):
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv != null and inv.has_method("add_item"):
		var candidates: PackedStringArray = ["raw_clay", "raw_gravel", "copper_ore"]
		inv.call("add_item", candidates[randi() % candidates.size()], 1)
