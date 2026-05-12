extends Perk

# Perfect Pick  (lockpicking L88, milestone 21)
# First attempt of the day on any lock auto-wins tier-2 or below.
#
# Auto-resolve first tier-≤2 lock per day. LockObject3D dispatches on_lock_opened with first_per_day=true before opening; the perk flips ctx.perfect_pick_fired to signal acceptance.

var _used_today: bool = false

func _init() -> void:
	pass

func on_lock_opened(ctx: Dictionary) -> void:
	if _used_today:
		return
	var tier: int = int(ctx.get("tier", 0))
	if tier > 1:
		return
	if not ctx.get("first_per_day", false):
		return
	_used_today = true
	ctx["perfect_pick_fired"] = true
