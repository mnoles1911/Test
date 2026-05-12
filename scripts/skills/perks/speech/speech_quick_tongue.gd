extends Perk

# Quick Tongue  (speech L56, milestone 13)
# Speech checks can be retried once after fail.
#
# Wired at fail time in SpeechCheckBroker.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[speech_quick_tongue] Active — speech checks can be retried once after fail (SpeechCheckBroker reads PerkQuery at fail).")
