extends Perk

# Oratorical  (speech L52, milestone 12)
# Persuade checks succeed at DC 5 above your Speech.
#
# Wired at check time in SpeechCheckBroker.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[speech_oratorical] Active — persuade checks succeed at DC 5 above your Speech (SpeechCheckBroker reads PerkQuery at check time).")
