extends Perk

# Relentless  (mining L96, milestone 23)
# Mining swings never tire (endurance regen 100% while mining).
#
# Refill stamina to full on every mining break — equivalent to 100% regen while actively mining.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "mining":
		return
	if Engine.get_main_loop() == null:
		return
	var player: Node = Engine.get_main_loop().root.get_node_or_null("World3D/Player3D")
	if player == null or not "endurance" in player:
		return
	var mx: float = float(player.get("max_endurance")) if "max_endurance" in player else 100.0
	player.set("endurance", mx)
