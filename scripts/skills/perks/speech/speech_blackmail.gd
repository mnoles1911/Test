extends Perk

# Blackmail  (speech L68, milestone 16)
# Failed checks reveal a piece of leverage 25% of the time.
#
# Wired at fail-resolution time inside SpeechCheckBroker.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[speech_blackmail] Active — failed speech checks reveal leverage 25% of the time (SpeechCheckBroker reads on fail).")
