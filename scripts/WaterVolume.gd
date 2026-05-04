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
# Wind state (wind_direction + wind_strength) drives the surface
# shader's wave direction and amplitude. WeatherManager (when it
# lands) calls set_wind(dir, strength) on every active water volume
# whenever weather changes. Until then, designers tune the @exports
# manually per body.
#
# Reference: design/SWIMMING_AND_WATER.md, design/WEATHER_AND_ENVIRONMENT.md


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

@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.0):
	set(value):
		wind_direction = value
		_push_wind_to_shader()
# Unit vector in world XZ for surface waves. The shader projects
# this onto its wave-A direction so the dominant wave rolls toward
# the wind. Y component is ignored.

@export_range(0.0, 5.0, 0.05) var wind_strength: float = 0.5:
	set(value):
		wind_strength = value
		_push_wind_to_shader()
# 0 = dead calm, 1 = breezy, 3 = stormy chop, 5 = lethal storm.
# Scales overall wave amplitude in the shader.

@export var surface_mesh_path: NodePath = "SurfaceMesh"
# Path to the MeshInstance3D rendering the water surface, so the
# script can find its ShaderMaterial and update wind uniforms.
# Default matches both shipping water scenes.

var _shader_material: ShaderMaterial = null


func _ready() -> void:
	# Add to the water_volume group so Player3D can find every water
	# region in the scene with one group scan rather than walking
	# the tree.
	add_to_group("water_volume")

	# Resolve the surface mesh's ShaderMaterial once. If the scene
	# is still using a placeholder StandardMaterial3D during the
	# transition, _shader_material stays null and the wind setters
	# become no-ops — graceful fallback, no crash.
	var mesh_instance := get_node_or_null(surface_mesh_path) as MeshInstance3D
	if mesh_instance != null and mesh_instance.material_override is ShaderMaterial:
		_shader_material = mesh_instance.material_override as ShaderMaterial
		_push_wind_to_shader()


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


func set_wind(direction: Vector3, strength: float) -> void:
	# Public hook for WeatherManager. Sets both wind values in one
	# call so the shader uniform push happens exactly once instead
	# of twice (one per @export setter).
	wind_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3(1.0, 0.0, 0.0)
	wind_strength = strength
	_push_wind_to_shader()


func _push_wind_to_shader() -> void:
	# No-op if the shader material wasn't resolved (placeholder
	# material, or _ready hasn't run yet because the @export setter
	# fired during scene load).
	if _shader_material == null:
		return
	var dir2 := Vector2(wind_direction.x, wind_direction.z)
	if dir2.length_squared() > 0.0001:
		dir2 = dir2.normalized()
	else:
		dir2 = Vector2(1.0, 0.0)
	_shader_material.set_shader_parameter("wind_dir", dir2)
	_shader_material.set_shader_parameter("wind_strength", wind_strength)
