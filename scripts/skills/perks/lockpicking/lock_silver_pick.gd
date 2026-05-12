extends Perk

# Silver Pick  (lockpicking L24, milestone 5)
# Tier-1 locks open in one attempt.
#
# Flag perk — LockObject3D reads PerkQuery.has_flag('lock','tier_1') and auto-opens tier-1 locks. Hook fires after the open is granted.



func _init() -> void:
	pass

func on_lock_opened(ctx: Dictionary) -> void:
	pass  # Logged by LockObject3D when the perk auto-resolves the lock (gate handled at lock-open time via PerkQuery.has_flag).
