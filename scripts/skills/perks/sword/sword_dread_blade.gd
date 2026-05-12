extends Perk

# Dread Blade  (sword L88, milestone 21)
# Killing an enemy with a sword frightens others within 5 m for 3 s.
#
# Kill with sword → frighten other enemies within 5 m. Uses Enemy3D.apply_status if it exists (TODO: fear AI state not in production).



func _init() -> void:
	pass

func on_kill(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "sword":
		return
	var tgt: Node = ctx.get("target", null)
	if tgt == null:
		return
	var origin: Vector3 = tgt.global_position if "global_position" in tgt else Vector3.ZERO
	for n in tgt.get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or n == tgt:
			continue
		if n.global_position.distance_to(origin) <= 5.0:
			if n.has_method("apply_status"):
				n.call("apply_status", "feared", 3.0)
