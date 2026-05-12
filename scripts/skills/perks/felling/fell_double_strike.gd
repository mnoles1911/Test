extends Perk

# Double Strike  (felling L44, milestone 10)
# 10% chance per swing to hit twice.
#
# 10% proc: caller fires an extra hit. EditToolHandler reads ctx.double_strike.



func _init() -> void:
	pass

func on_voxel_broken(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "felling":
		return
	if randf() < 0.10:
		ctx["double_strike"] = true
