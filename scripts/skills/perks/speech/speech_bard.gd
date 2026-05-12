extends Perk

# Bard  (speech L24, milestone 5)
# Singing in taverns grants +10 disposition to all nearby for 1 day.
#
# Tavern song trigger not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[speech_bard] Active — tavern song grants +10 disposition to nearby NPCs (tavern-song trigger pending).")
