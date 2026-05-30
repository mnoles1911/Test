extends CanvasLayer

# LensFlare — drives assets/shaders/lens_flare.gdshader. Spawned by
# World3DBootstrap (Phase K bundle, 2026-05-27).
#
# WHAT IT DOES (in plain English):
#   Every frame, finds the sun's screen-space position, sees if the
#   sun is in front of the camera AND above the horizon AND not
#   blocked by terrain, and pushes those values into the lens flare
#   shader. The shader paints a halo + ghost string. When the sun
#   is offscreen or behind the camera, the script pins sun_screen_uv
#   to a sentinel offscreen value so the shader paints nothing.
#
# RESPECTS the GraphicsManager.is_effect_enabled("lens_flare") toggle:
#   when false, the script hides this CanvasLayer entirely so the
#   shader doesn't even run.
#
# Spawned ONCE per world load (World3DBootstrap._ready). The script
# resolves the sun via the existing "sun_light" group convention.
# Headless-safe: when no camera / no sun, just hides itself.

const SHADER_PATH: String = "res://assets/shaders/lens_flare.gdshader"
const SUN_GROUP: String = "sun_light"

# Smoothing for the "sun is occluded" fade. Without smoothing, the
# halo pops on/off the moment a tree branch crosses in front of the
# sun — feels twitchy. EMA over a few frames hides the transition.
const VISIBILITY_LERP: float = 8.0    # higher = snappier

var _shader_material: ShaderMaterial = null
var _rect: ColorRect = null
var _camera: Camera3D = null
var _sun: DirectionalLight3D = null
var _smoothed_visibility: float = 0.0


func _ready() -> void:
	layer = 4  # below HUDOverlay (5) but above world (default 0)
	# Build the full-screen ColorRect once. Shader-painted, alpha-blended
	# on top of the rendered scene.
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(0, 0, 0, 0)  # the shader paints; this is just the canvas
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_warning("[LensFlare] %s missing — lens flare disabled." % SHADER_PATH)
		visible = false
		return
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	# Sentinel offscreen so the first frame before _resolve_refs() finds
	# a camera doesn't paint a spurious centre-of-screen flare.
	_shader_material.set_shader_parameter("sun_screen_uv", Vector2(-1.0, -1.0))
	_shader_material.set_shader_parameter("sun_visibility", 0.0)
	_rect.material = _shader_material
	add_child(_rect)

	# Subscribe to toggle changes so flipping the DebugOverlay GRAPHICS
	# button is instant (no waiting for next _process tick).
	var gm := get_node_or_null("/root/GraphicsManager")
	if gm != null and gm.has_signal("effect_toggles_changed"):
		gm.effect_toggles_changed.connect(_apply_toggle)
	_apply_toggle()
	print("[LensFlare] ready (CanvasLayer %d, shader OK)." % layer)


func _process(delta: float) -> void:
	if not visible:
		return
	_resolve_refs()
	if _camera == null or _sun == null or _shader_material == null:
		_shader_material.set_shader_parameter("sun_screen_uv", Vector2(-1.0, -1.0)) if _shader_material != null else null
		return

	# Sun is a DIRECTIONAL light — its global_basis.z points OPPOSITE the
	# light travel direction (Godot convention: directional light shines
	# in the -Z direction of its basis). So the sun's apparent position is
	# along +basis.z from the camera, at any "infinite" distance.
	var sun_dir_world: Vector3 = -_sun.global_basis.z
	# A point "at infinity" toward the sun: camera + sun_dir * BIG.
	var sun_world: Vector3 = _camera.global_position + sun_dir_world * 1000.0
	# Behind the camera? Local-z forward in Godot Camera3D is -Z.
	var cam_to_sun: Vector3 = sun_world - _camera.global_position
	var cam_forward: Vector3 = -_camera.global_basis.z
	if cam_to_sun.dot(cam_forward) <= 0.0:
		_set_offscreen(delta)
		return

	var sun_screen: Vector2 = _camera.unproject_position(sun_world)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		_set_offscreen(delta)
		return
	var sun_uv: Vector2 = Vector2(sun_screen.x / vp_size.x, sun_screen.y / vp_size.y)
	# Offscreen? Pin the sentinel so the shader bails.
	if sun_uv.x < 0.0 or sun_uv.x > 1.0 or sun_uv.y < 0.0 or sun_uv.y > 1.0:
		_set_offscreen(delta)
		return

	# Occlusion: raycast a tiny distance toward the sun. If anything
	# blocks, fade visibility toward 0. The ray is short (4 m) — the
	# halo should hide when a tree/hill is right in front of the player,
	# not when a distant mountain blocks the actual sun (the actual sun
	# isn't reachable by raycast; we only care about local occluders).
	var target_visibility: float = 1.0
	var space := _camera.get_world_3d().direct_space_state if _camera.get_world_3d() != null else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(
			_camera.global_position,
			_camera.global_position + sun_dir_world * 4.0)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			target_visibility = 0.0

	# Smooth the visibility transition (anti-popping).
	_smoothed_visibility = lerpf(
		_smoothed_visibility, target_visibility,
		clampf(delta * VISIBILITY_LERP, 0.0, 1.0))

	_shader_material.set_shader_parameter("sun_screen_uv", sun_uv)
	_shader_material.set_shader_parameter("sun_visibility", _smoothed_visibility)
	_shader_material.set_shader_parameter("viewport_aspect", vp_size.x / vp_size.y)


func _set_offscreen(delta: float) -> void:
	# Ease visibility down so transitioning off-screen also fades.
	_smoothed_visibility = lerpf(
		_smoothed_visibility, 0.0,
		clampf(delta * VISIBILITY_LERP, 0.0, 1.0))
	_shader_material.set_shader_parameter("sun_screen_uv", Vector2(-1.0, -1.0))
	_shader_material.set_shader_parameter("sun_visibility", _smoothed_visibility)


func _resolve_refs() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	if _sun == null or not is_instance_valid(_sun):
		var sun_node := get_tree().get_first_node_in_group(SUN_GROUP)
		if sun_node is DirectionalLight3D:
			_sun = sun_node as DirectionalLight3D


func _apply_toggle() -> void:
	var gm := get_node_or_null("/root/GraphicsManager")
	if gm == null:
		visible = true   # no manager (dev scene?) → default ON
		return
	visible = bool(gm.is_effect_enabled("lens_flare"))
