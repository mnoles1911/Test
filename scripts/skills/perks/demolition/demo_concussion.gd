extends Perk

# Concussion  (demolition L84, milestone 20)
# Stuns enemies within 4 m for 1 s on detonation.
#
# Stun enemies within 4 m of detonation for 1 s. Calls Enemy3D.apply_status if present.



func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("detonation_source", "") != "powder_charge":
		return
	var pos: Vector3 = ctx.get("world_pos", Vector3.ZERO)
	if Engine.get_main_loop() == null:
		return
	for n in Engine.get_main_loop().get_nodes_in_group("enemy"):
		if not is_instance_valid(n):
			continue
		if n.global_position.distance_to(pos) <= 4.0:
			if n.has_method("apply_status"):
				n.call("apply_status", "stunned", 1.0)
