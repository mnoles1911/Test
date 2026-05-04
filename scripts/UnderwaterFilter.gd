extends CanvasLayer
# UnderwaterFilter — full-screen tint shown while Roland's head is
# below the water surface.
#
# Implementation: a CanvasLayer with a translucent ColorRect child
# that fills the viewport. set_active(true) makes it visible;
# set_active(false) hides it. That's the whole story.
#
# Why a CanvasLayer instead of swapping WorldEnvironment fog:
# DayNightCycle.gd writes env.fog_light_color every frame, so any
# fog tweak from here would be overwritten on the next tick. The
# overlay decouples the underwater feel from the environment system
# and keeps both responsibilities in one node each.
#
# Future polish: replace ColorRect with a ShaderMaterial that adds
# screen-depth fog falloff and slight chromatic aberration. v1
# ships with the flat tint — readable and zero shader maintenance.
#
# Reference: design/SWIMMING_AND_WATER.md — "Underwater camera filter"


@export var tint_color: Color = Color(0.18, 0.32, 0.42, 0.42)
# Translucent blue-green. Alpha 0.42 is enough to read as
# "underwater" without making far terrain unreadable.

@onready var _rect: ColorRect = $TintRect


func _ready() -> void:
	_rect.color = tint_color
	_rect.visible = false


func set_active(submerged: bool) -> void:
	# Idempotent — safe to call every frame from Player3D, only
	# visibility actually flips when the state changes.
	if _rect.visible == submerged:
		return
	_rect.visible = submerged
