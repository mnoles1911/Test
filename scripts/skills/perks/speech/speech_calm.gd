extends Perk

# Calming Voice  (speech L76, milestone 18)
# Reduce nearby enemy aggression for 5 s once per encounter.
#
# Enemy aggression system not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[speech_calm] Active — reduce nearby enemy aggression for 5 s once per encounter (AI aggro hook pending).")
