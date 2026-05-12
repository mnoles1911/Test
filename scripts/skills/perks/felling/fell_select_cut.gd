extends Perk

# Select Cut  (felling L60, milestone 14)
# Each tree felled grants +10% XP to other crafting skills.
#
# Each tree felled grants a small XP nudge to other crafting skills.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "felling":
		return
	if not ctx.get("on_tree_break", false):
		return
	if Engine.get_main_loop() == null:
		return
	var sm: Node = Engine.get_main_loop().root.get_node_or_null("SkillManager")
	if sm == null:
		return
	for s in ["mining", "excavation", "smithing", "alchemy"]:
		sm.call("add_xp", s, 1.0)
