extends Perk

# Decoy  (lockpicking L64, milestone 15)
# Drop a fake pick to distract patrolling NPCs for 5 s.
#
# NPC distraction system not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[lock_decoy] Active — drop fake pick distracts patrolling NPCs (AI system pending).")
