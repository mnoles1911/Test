extends SpringArm3D
# CameraRig — fixed-elevation follow camera for the 3D voxel world.
#
# This is the camera style of Hades, Diablo 3, and Grim Dawn:
# the camera sits above and behind Roland at a fixed angle, and
# follows him through the world. The player NEVER controls the camera
# directly in Act I — they always see Roland from the same elevation,
# the same arm length, the same orientation.
#
# Why SpringArm3D? It's a Godot node that automatically pulls the
# camera in towards the target if a wall comes between them. Without
# this, the camera would clip through stone walls in caves and
# tunnels. SpringArm3D handles this for free — we just configure the
# arm length and elevation, and Godot does the rest.
#
# Scene hierarchy this script expects:
#
#   Player3D (CharacterBody3D)
#   └── CameraTarget (Node3D)         ← raised to Roland's chest height
#       └── SpringArm3D (this node)   ← THIS SCRIPT lives here
#           └── Camera3D              ← the actual camera
#
# The SpringArm3D is rotated to point UP-and-BACK from the target.
# The Camera3D at the end of the arm naturally looks back at the
# target because it's a child of the arm.


@export var elevation_degrees: float = 50.0
# Degrees above horizontal. 50° is the Hades/Diablo angle.
# 45° = more top-down, 38° = more cinematic shoulder.
# Per design/CAMERA_AND_PERSPECTIVE.md, this varies per location:
#   tight indoor space = higher angle (more overhead)
#   open outdoor zone  = lower angle  (more horizon visible)

@export var arm_length: float = 12.0
# Distance from the target in meters. 8–10 for tight indoor spaces,
# 12–15 for outdoor zones, 16+ for vistas.

@export var allow_horizontal_rotation: bool = false
# If true, Q/E rotate the camera horizontally around the player.
# Keep false for Act I — the world is hand-staged, the camera angle
# is part of the composition. Open exploration zones in later acts
# may enable this.

@export var rotation_speed_degrees: float = 90.0
# How fast horizontal rotation happens, in degrees per second.
# Only used when allow_horizontal_rotation is true.


func _ready() -> void:
	# Configure the spring arm itself (this node).
	# spring_length is built-in to SpringArm3D — it's how far the
	# camera sits from the pivot when nothing is in the way.
	spring_length = arm_length

	# Apply the elevation angle. The minus sign tilts the arm DOWN
	# towards the target (the camera at the end of the arm therefore
	# looks down at the world from above).
	rotation_degrees.x = -elevation_degrees


func _process(delta: float) -> void:
	if not allow_horizontal_rotation:
		return

	# Optional horizontal rotation for exploration zones.
	# Q rotates left, E rotates right.
	if Input.is_action_pressed("camera_left"):
		rotation_degrees.y += rotation_speed_degrees * delta
	if Input.is_action_pressed("camera_right"):
		rotation_degrees.y -= rotation_speed_degrees * delta
