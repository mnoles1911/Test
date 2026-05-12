extends Perk

# Marked Target  (throwables L40, milestone 9)
# First thrown hit on an enemy marks them: +20% damage from all sources for 5 s.
#
# First thrown hit marks an enemy for 5 s — they take +20% damage from any source. Combat code reads ctx.target_marked to apply.

var _marked: Dictionary = {}

func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if ctx.get("skill", "") != "throwables":
		return
	var tgt: Node = ctx.get("target", null)
	if tgt == null:
		return
	var tgt_id: int = tgt.get_instance_id()
	if _marked.has(tgt_id):
		return
	_marked[tgt_id] = (Time.get_ticks_msec() / 1000.0) + 5.0
	if tgt.has_method("apply_status"):
		tgt.call("apply_status", "marked", 5.0)
