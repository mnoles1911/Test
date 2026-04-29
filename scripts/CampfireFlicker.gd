extends PointLight2D
# Attached directly to the Campfire PointLight2D node in World.tscn.
#
# This script makes the campfire light flicker by varying its energy
# (brightness) over time. It uses two techniques combined:
#
#   1. A sine wave: smoothly oscillates energy up and down on a regular cycle.
#      This gives the flicker a natural rhythm.
#
#   2. A small random nudge each frame: breaks the perfect regularity of the
#      sine wave so the flicker never feels mechanical or looping.
#
# Together these produce something that reads as a real, organic fire.


# The center brightness. PointLight2D energy: 0 = off, 1 = normal, 2 = double.
# ART_DIRECTION.md specifies 1.2–1.5 for the campfire — 1.3 is the midpoint.
@export var base_energy: float = 1.3

# How much the energy varies above and below base_energy.
# At 0.1, the light ranges from 1.2 to 1.4.
@export var flicker_amount: float = 0.1

# How fast the sine wave cycles. Higher = faster flicker.
# 2.5 gives a relaxed campfire pace — not frantic, not slow.
@export var flicker_speed: float = 2.5

# Internal timer. Advances each frame and feeds into the sine function.
var time: float = 0.0


func _process(delta: float) -> void:
	# Advance the timer by how much real time has passed this frame.
	time += delta * flicker_speed

	# sin() returns a value between -1 and +1 that cycles smoothly.
	# Multiply by flicker_amount to scale it to a small energy offset.
	# Named energy_offset (not just "offset") to avoid shadowing PointLight2D.offset.
	var energy_offset: float = sin(time) * flicker_amount

	# Add a tiny random nudge each frame to break the mechanical regularity.
	# randf_range(-0.02, 0.02) is subtle — just enough to feel alive.
	energy_offset += randf_range(-0.02, 0.02)

	# Apply the result to this node's energy property.
	# self.energy is inherited from PointLight2D.
	energy = base_energy + energy_offset
