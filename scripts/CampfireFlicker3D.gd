extends OmniLight3D
# CampfireFlicker3D — warm, uneven light flicker for 3D point lights.
#
# This is the 3D port of CampfireFlicker.gd (which extended PointLight2D).
# The math is identical: a slow sine wave gives the underlying breathing
# rhythm, plus a small random nudge on top so it never looks mechanical.
#
# In 3D, OmniLight3D is the equivalent of PointLight2D — a light source
# that radiates in all directions from a single point. Same property
# (light_energy) controls brightness, so the same flicker logic works.


@export var base_energy: float = 1.6
# The "resting" brightness. 3D lights generally need a bit more energy
# than 2D ones because they fall off with real distance attenuation.
# Adjust per scene — caves want a brighter fire, outdoor scenes can
# go lower because ambient light fills in.

@export var flicker_amount: float = 0.15
# How much the energy varies above and below base_energy. 0.15 = ±15%.
# Larger = more dramatic flicker (good for dying fires, wind), smaller
# = steadier glow (good for lanterns).

@export var flicker_speed: float = 2.5
# How fast the sine wave oscillates. Higher = faster flicker.
# 2.5 is a calm campfire. 4.0+ feels nervous, like a candle in a draft.

@export var random_nudge: float = 0.025
# A tiny random extra each frame so the flicker isn't perfectly periodic.
# Keep this small — too much makes it look like a strobe light.


var _time: float = 0.0

var _fire_loop_handle: int = 0
# Handle for the looping campfire crackle started in _ready (0 = none/none yet).


func _ready() -> void:
	# Start at the rest energy so the first frame doesn't pop.
	light_energy = base_energy
	# Start the looping campfire crackle at this fire's world position.
	# Safe BEFORE the .ogg is curated into the repo: AudioManager simply
	# logs one warning and returns 0, so the fire is just silent until
	# fire_campfire_crackle_loop.ogg is placed — no code change needed then.
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		_fire_loop_handle = am.play_loop(
			"fire_campfire_crackle_loop", global_position)


func _exit_tree() -> void:
	# Stop this fire's crackle when the campfire is removed / scene changes,
	# so the loop doesn't linger or leak a player node.
	var am := get_node_or_null("/root/AudioManager")
	if am != null and _fire_loop_handle != 0:
		am.stop_loop(_fire_loop_handle)


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	# Smooth oscillation around base_energy plus a tiny per-frame jitter.
	var sine_component: float = sin(_time) * flicker_amount
	var random_component: float = randf_range(-random_nudge, random_nudge)
	light_energy = base_energy + sine_component + random_component
