extends Perk

# Well Rested  (vitality L44, milestone 10)
# Sleeping in a bed grants +10% all skill XP for 1 day.
#
# Pattern A daily-ish flag. Rest system pokes _rested_until_unix when Roland sleeps. Re-entry guard prevents infinite hook recursion.

var _rested_until_unix: int = 0
var _in_bonus: bool = false
var _in_bonus_reentry: bool = false

func _init() -> void:
	pass

func on_xp_gained(ctx: Dictionary) -> void:
	if not _rested_until_unix > 0:
		return
	var now: int = int(Time.get_unix_time_from_system())
	if now > _rested_until_unix:
		_rested_until_unix = 0
		return
	var amt: float = float(ctx.get("amount", 0.0))
	if amt <= 0.0:
		return
	var bonus: float = amt * 0.10
	var skill: String = String(ctx.get("skill", ""))
	if skill == "" or Engine.get_main_loop() == null:
		return
	var sm: Node = Engine.get_main_loop().root.get_node_or_null("SkillManager")
	if sm != null and sm.has_method("add_xp"):
		# Cap recursion: don't double-fire the on_xp_gained hook.
		_in_bonus = true
		if not _in_bonus_reentry:
			_in_bonus_reentry = true
			sm.call("add_xp", skill, bonus)
			_in_bonus_reentry = false


func on_picked() -> void:
	pass  # Caller (rest system) sets _rested_until_unix to (now + 86400) on sleeping.
