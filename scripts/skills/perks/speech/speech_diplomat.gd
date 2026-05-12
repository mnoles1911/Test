extends Perk

# Diplomat  (speech L40, milestone 9)
# +10 disposition with all NPCs of one faction.
#
# Faction-pick UI not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[speech_diplomat] Active — +10 disposition with a chosen faction (UI to pick faction pending).")
