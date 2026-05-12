extends Perk

# Bury  (excavation L32, milestone 7)
# Spawn 1 dirt at every shovel strike to bury bodies.
#
# Flag for EditToolHandler to place a dirt voxel at the player's feet after a shovel swing (TODO: place-voxel path not in production for this trigger).



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "excavation":
		return
	ctx["spawn_dirt_at_player"] = true
