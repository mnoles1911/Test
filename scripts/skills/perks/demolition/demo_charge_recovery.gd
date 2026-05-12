extends Perk

# Charge Recovery  (demolition L72, milestone 17)
# 10% chance an unexploded charge can be recovered.
#
# 10% recovery chance when a charge fails to detonate. PowderCharge currently never marks duds, so this is wired but dormant.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("detonation_source", "") != "powder_charge":
		return
	if not ctx.get("is_dud", false):
		return
	if randf() > 0.10:
		return
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv != null and inv.has_method("add_item"):
		inv.call("add_item", "powder_charge", 1)
