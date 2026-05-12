extends Perk

# Pincushion  (bow L76, milestone 18)
# Each arrow lodged in an enemy adds +5% damage from your next hit (cap +25%).
#
# Each arrow lodged in an enemy adds +5% damage to the next shot, cap +25%. Tracks per-instance arrow counts.

var _lodged: Dictionary = {}

func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "bow":
		return
	var tgt: Node = ctx.get("target", null)
	if tgt == null:
		return
	var id: int = tgt.get_instance_id()
	var arrows: int = int(_lodged.get(id, 0))
	if arrows > 0:
		var bonus: float = clampf(0.05 * float(arrows), 0.0, 0.25)
		ctx["damage"] = int(ctx.get("damage", 0) * (1.0 + bonus))
	_lodged[id] = arrows + 1
