extends Perk

# Focus  (bow L32, milestone 7)
# Hold draw to slow time 25% for up to 3 s.
#
# Bow draw-and-hold triggers 25% time dilation for up to 3 s. Restores via SceneTree timer.

func _restore_time() -> void:
	Engine.time_scale = 1.0

func _init() -> void:
	pass

func on_attack(ctx: Dictionary) -> void:
	if not ctx.get("draw_hold", false):
		return
	if ctx.get("skill", "") != "bow":
		return
	Engine.time_scale = 0.75
	if Engine.get_main_loop() != null:
		Engine.get_main_loop().create_timer(3.0).timeout.connect(_restore_time)


func on_picked() -> void:
	pass
