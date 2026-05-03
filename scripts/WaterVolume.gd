extends Area3D
# WaterVolume — a region of water Roland can swim in.
#
# What this does in plain English:
#
# This is the script attached to any water Area3D. It exposes the
# water surface height and any river current via exported vars,
# and it adds itself to the "water_volume" group on _ready so the
# player can find it by group scan.
#
# The player polls the water (via overlaps_body() and the methods
# below) — the water doesn't push state to the player. That keeps
# the player's swimming logic in one place (Player3D.gd) and
# keeps water volumes pure data.
#
# Reference: design/SWIMMING_AND_WATER.md


@export var surface_y: float = 0.0
# World-space Y coordinate of the water surface. Positions above
# this are dry; positions below are wet. Update this in the
# Inspector if you move or resize the water Area3D — there's no
# automatic alignment with the collision shape.

@export var current_direction: Vector3 = Vector3.ZERO
# Direction of any river current that pushes the player while
# inside this volume. Zero vector = still water (lake, pond).
# For a flowing river, set a unit vector in the flow direction;
# the magnitude in current_strength scales it.

@export var current_strength: float = 0.0
# Magnitude in m/s of the current. 0 = still. 1 = gentle (about
# walking pace). 3 = strong, hard to swim against.


func _ready() -> void:
	# Add to the water_volume group so Player3D can find every water
	# region in the scene with one group scan rather than walking
	# the tree.
	add_to_group("water_volume")


func is_position_submerged(pos: Vector3, head_offset: float = 1.5) -> bool:
	# Returns true if a point with the given head offset is below
	# the water surface — i.e., the player's head is underwater.
	#
	# head_offset defaults to 1.5m, which is roughly Roland's eye
	# height above his pivot point (capsule bottom).
	return (pos.y + head_offset) < surface_y


func get_current_velocity() -> Vector3:
	# Returns the river-current push vector. Zero for still water.
	if current_direction.length_squared() < 0.0001 or current_strength <= 0.0:
		return Vector3.ZERO
	return current_direction.normalized() * current_strength
