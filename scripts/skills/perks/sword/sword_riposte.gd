extends Perk

# Riposte  (sword L24, milestone 5)
# After a successful parry, your next sword hit within 2 s deals +50% damage.
#
# Pattern A: post-parry window (2 s). on_parry opens it, the next sword attack consumes it for +50% damage.

var _parry_window_open_until: float = 0.0

func _init() -> void:
	pass

func on_parry(ctx: Dictionary) -> void:
	_parry_window_open_until = (Time.get_ticks_msec() / 1000.0) + 2.0


func on_attack(ctx: Dictionary) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	if ctx.get("skill", "") != "sword":
		return
	if t > _parry_window_open_until:
		return
	ctx["damage"] = int(ctx.get("damage", 0) * 1.50)
	ctx["riposte_active"] = true
	_parry_window_open_until = 0.0
