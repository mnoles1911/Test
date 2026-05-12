extends Perk

# Quick Burial  (excavation L92, milestone 22)
# Burying a corpse refreshes endurance to full.
#
# Refill stamina to full after burying a corpse.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "excavation":
		return
	if not ctx.get("on_corpse", false):
		return
	if Engine.get_main_loop() == null:
		return
	var p: Node = Engine.get_main_loop().root.get_node_or_null("World3D/Player3D")
	if p == null or not "endurance" in p:
		return
	var mx: float = float(p.get("max_endurance")) if "max_endurance" in p else 100.0
	p.set("endurance", mx)
