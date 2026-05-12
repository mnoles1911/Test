extends Perk

# Swing Through  (mining L56, milestone 13)
# Pickaxe hits can break 2 adjacent voxels of the same type.
#
# EditToolHandler reads extra_adjacent_breaks after the primary break to fire additional carves on same-material neighbors.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "mining":
		return
	ctx["extra_adjacent_breaks"] = max(int(ctx.get("extra_adjacent_breaks", 0)), 1)
