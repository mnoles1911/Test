extends Perk

# Blood Arrow  (throwables L64, milestone 15)
# Thrown kills heal 5 HP.
#
# Thrown kill heals player +5 HP. Reads Player3D.hp / max_hp.



func _init() -> void:
	pass

func on_kill(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "throwables":
		return
	if Engine.get_main_loop() == null:
		return
	var player: Node = Engine.get_main_loop().root.get_node_or_null("World3D/Player3D")
	if player == null:
		return
	if "hp" in player:
		var cur: float = float(player.get("hp"))
		var mx: float = float(player.get("max_hp")) if "max_hp" in player else 100.0
		player.set("hp", minf(cur + 5.0, mx))
