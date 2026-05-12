extends Perk

# Thief's Eye  (lockpicking L16, milestone 3)
# Outline locked containers within 8 m.
#
# Visual TODO.



func _init() -> void:
	pass

func on_picked() -> void:
	print("[lock_thief_eye] Active — locked containers outline within 8 m (renderer pending).")
