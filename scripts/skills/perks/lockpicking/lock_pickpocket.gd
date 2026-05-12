extends Perk

# Pickpocket  (lockpicking L32, milestone 7)
# Begin pickpocketing without alerting NPCs.
#
# Pickpocket system not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[lock_pickpocket] Active — pickpocket without alerting NPCs (pickpocket system pending).")
