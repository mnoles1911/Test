extends SceneTree

# Local GPU screenshot probe (RX 7800 XT). Boots World3D, renders chosen
# vantages through an offscreen SubViewport (reliable regardless of the
# main window), saves PNGs to _renders/. SHOT env: skirt | terrain | water.
# Dev-only scratch (tools/_dev), never shipped.

var _frames: int = 0
var _phase: int = 0
var _set: String = "skirt"
var _world: Node = null
var _sub: SubViewport = null
var _cam: Camera3D = null
var _base: Vector3 = Vector3.ZERO

# Long settle: voxel chunks stream in, flora + far-grass impostors
# populate, AND SDFGI global illumination needs many stationary frames
# to CONVERGE (until it does, the terrain renders too bright — the
# "not dark enough" the designer caught). The SubViewport must actually
# render every frame during settle so SDFGI accumulates, so we keep it
# UPDATE_ALWAYS through the settle and only freeze right at the capture.
const SETTLE_FRAMES: int = 1200
const OUT_DIR: String = "res://_renders/"

func _initialize() -> void:
	_set = OS.get_environment("SHOT")
	if _set == "":
		_set = "skirt"
	_world = (load("res://scenes/World3D.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_sub = SubViewport.new()
	_sub.size = Vector2i(1280, 720)
	_sub.own_world_3d = false
	# Render EVERY frame so SDFGI converges during the settle (a frozen
	# viewport never accumulates GI → perpetually bright terrain).
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sub)
	_cam = Camera3D.new()
	_cam.far = 2000.0
	_sub.add_child(_cam)
	_cam.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("[SHOT] set=%s; settling %d frames..." % [_set, SETTLE_FRAMES])

# Re-settle after each camera move so SDFGI reconverges for the new view.
const RESETTLE_FRAMES: int = 400

func _process(_d: float) -> bool:
	_frames += 1
	# Phase 0: boot, set noon, aim shot 0, then long initial settle.
	if _phase == 0:
		if _frames == 30:
			var wc := root.get_node_or_null("/root/WorldClock")
			if wc != null and wc.has_method("set_time"):
				wc.set_time(12, 0)
			_base = _ground_world_near(_player_pos())
			print("[SHOT] ground anchor %s — settling %d frames (stream+flora+SDFGI)..." % [_base, SETTLE_FRAMES])
			_aim(0)
		if _frames >= SETTLE_FRAMES:
			_snap(_shot_name(0))
			_phase = 1
			_frames = 0
			if _shot_count() <= 1:
				print("[SHOT] DONE")
				return true
			_aim(1)
		return false
	# Subsequent shots: re-settle for SDFGI, then capture.
	if _frames >= RESETTLE_FRAMES:
		_snap(_shot_name(_phase))
		_phase += 1
		_frames = 0
		if _phase >= _shot_count():
			print("[SHOT] DONE")
			return true
		_aim(_phase)
	return false

func _shot_count() -> int:
	match _set:
		"skirt": return 3
		"water": return 1
		"flora": return 3
		_: return 4

func _shot_name(i: int) -> String:
	match _set:
		"skirt": return ["skirt_01_handoff_low", "skirt_02_handoff_high", "skirt_03_panorama"][i]
		"water": return ["water_01_flow"][i]
		"flora": return ["flora_01_feet", "flora_02_crouch", "flora_03_ring"][i]
		_: return ["terrain_01_grain", "terrain_02_eye", "terrain_03_vista", "terrain_04_horizon"][i]

func _aim(i: int) -> void:
	var b := _base
	if _set == "flora":
		# Tight, low angles to actually SEE 10cm grass blades right at the
		# player (the LOD0 ring). If these are bare, real flora isn't
		# generating; if blades are here, the DLL works.
		match i:
			0: _cam.position = b + Vector3(0, 0.45, -0.3); _cam.look_at(b + Vector3(0.1, 0.05, 2.0))
			1: _cam.position = b + Vector3(0, 0.25, 0);    _cam.look_at(b + Vector3(1.5, 0.0, 0.6))
			2: _cam.position = b + Vector3(0, 6, -6);      _cam.look_at(b + Vector3(0, -1, 4))
	elif _set == "skirt":
		match i:
			0: _cam.position = b + Vector3(0, 3, 0);  _cam.look_at(b + Vector3(70, 6, 30))
			1: _cam.position = b + Vector3(0, 22, 0); _cam.look_at(b + Vector3(90, -4, 40))
			2: _cam.position = b + Vector3(0, 45, 0); _cam.look_at(b + Vector3(120, -20, 60))
	elif _set == "terrain":
		match i:
			0: _cam.position = b + Vector3(1.2, 0.8, 1.2); _cam.look_at(b + Vector3(3.5, -0.4, 3.5))
			1: _cam.position = b + Vector3(0, 1.7, 0);     _cam.look_at(b + Vector3(25, 0, 18))
			2: _cam.position = b + Vector3(-12, 30, -12);  _cam.look_at(b + Vector3(60, -6, 60))
			3: _cam.position = b + Vector3(0, 5, 0);       _cam.look_at(b + Vector3(80, 12, 25))

func _player_pos() -> Vector3:
	for n in root.get_tree().get_nodes_in_group("player"):
		if n is Node3D:
			return (n as Node3D).global_position
	return Vector3(0, 32, 0)

func _ground_world_near(world_pos: Vector3) -> Vector3:
	const VoxelScale := preload("res://scripts/VoxelScale.gd")
	var vx := floori(world_pos.x * VoxelScale.VOXELS_PER_METER)
	var vz := floori(world_pos.z * VoxelScale.VOXELS_PER_METER)
	var terrain = _world.find_child("VoxelLodTerrain", true, false)
	if terrain != null:
		var tool = terrain.get_voxel_tool()
		if tool != null:
			tool.channel = VoxelBuffer.CHANNEL_TYPE
			for y in range(400, 120, -1):
				if tool.get_voxel(Vector3i(vx, y, vz)) != 0:
					return Vector3(vx, y + 1, vz) * VoxelScale.VOXEL_SIZE_M
	return world_pos

func _snap(name: String) -> void:
	_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_draw(true, 1.0 / 60.0)
	var tex := _sub.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		print("[SHOT] FAIL %s — no image" % name)
		return
	img.save_png(OUT_DIR + name + ".png")
	print("[SHOT] saved %s" % ProjectSettings.globalize_path(OUT_DIR + name + ".png"))
