extends Perk

# Poisoner  (alchemy L36, milestone 8)
# Coat blade poison on swords for 30 s.
#
# Blade-coat UI not in production.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[alch_poisoner] Active — apply blade poison from inventory (oil-coat UI pending).")
