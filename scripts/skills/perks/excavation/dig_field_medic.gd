extends Perk

# Field Medic  (excavation L72, milestone 17)
# Excavating a corpse heals you for 5 HP.
#
# Heal +5 HP per corpse excavation tick.



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
	if p == null or not "hp" in p:
		return
	var cur: float = float(p.get("hp"))
	var mx: float = float(p.get("max_hp")) if "max_hp" in p else 100.0
	p.set("hp", minf(cur + 5.0, mx))
