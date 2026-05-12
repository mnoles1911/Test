extends Perk

# Proximity  (demolition L20, milestone 4)
# Charges detonate on enemy contact instead of timer.
#
# Flag for PowderCharge — body_entered already exists; the trigger check (any solid body) already detonates on enemy contact too, so this perk is effectively already 'on' once PowderCharge reads the flag.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[demo_proximity] Active — PowderCharge reads PerkQuery.has_flag('explosives','') to detonate on enemy contact.")
