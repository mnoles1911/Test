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
	# === BIOME FRAMEWORK === for SHOT=biomes, flip the world into biome
	# mode BEFORE _ready runs so the generator streams the multi-biome
	# terrain. The default-OFF flag stays off for every other SHOT set.
	if _set == "biomes" and "biome_framework_enabled" in _world:
		_world.set("biome_framework_enabled", true)
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

# === BIOME FRAMEWORK === capture state. For SHOT=biomes we search the live
# biome field outward from origin for the first column whose DOMINANT biome
# weight >= 0.9 (a "pure" example of each biome), then capture an eye-level
# and a 30 m-high vantage there. 5 biomes x 2 shots = 10 PNGs.
const _BIOME_NAMES := ["plains", "hills", "forest", "desert", "mountains"]
var _biome_anchors := {}        # slot -> Vector3 (world metres, ground)
var _biome_shot_list: Array = [] # [ [name, world_pos, is_high], ... ]
var _biome_idx: int = -1         # index into _biome_shot_list (-1 = not started)
var _biome_settle: int = 0

func _process(_d: float) -> bool:
	if _set == "biomes":
		return _process_biomes()
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


# === BIOME FRAMEWORK === capture driver. ----------------------------------
# Phase A (_biome_idx == -1): long initial settle for streaming, then locate
# the five biome anchors + build the shot list. Phase B: for each shot move
# the camera, re-settle for SDFGI, capture.
func _process_biomes() -> bool:
	_frames += 1
	if _biome_idx == -1:
		if _frames == 30:
			var wc := root.get_node_or_null("/root/WorldClock")
			if wc != null and wc.has_method("set_time"):
				wc.set_time(12, 0)
		if _frames < SETTLE_FRAMES:
			return false
		# Settled — find anchors + build the shot list, then start phase B.
		_biome_find_anchors()
		if _biome_shot_list.is_empty():
			print("[SHOT] biomes — no anchors found (biome field inactive?). DONE")
			return true
		_biome_idx = 0
		_biome_aim(0)
		_biome_settle = 0
		return false
	# Phase B — re-settle then capture the current shot.
	_biome_settle += 1
	if _biome_settle < RESETTLE_FRAMES:
		return false
	var shot: Array = _biome_shot_list[_biome_idx]
	_snap("biome_%s_%s" % [shot[0], "high" if shot[2] else "eye"])
	_biome_idx += 1
	if _biome_idx >= _biome_shot_list.size():
		print("[SHOT] biomes DONE — %d captures." % _biome_shot_list.size())
		return true
	_biome_aim(_biome_idx)
	_biome_settle = 0
	return false


# Resolve the BiomeFieldCpp the bootstrap cached, search outward from origin
# for one pure (dominant weight >= 0.9) column per biome slot, store the
# ground world position. Builds _biome_shot_list = eye + high per found biome.
func _biome_find_anchors() -> void:
	const VoxelScale := preload("res://scripts/VoxelScale.gd")
	var field = _world.get("_biome_field_ref") if ("_biome_field_ref" in _world) else null
	if field == null or not field.has_method("dominant_biome"):
		print("[SHOT] biomes — bootstrap has no _biome_field_ref; is biome_framework_enabled?")
		return
	var terrain = _world.find_child("VoxelLodTerrain", true, false)
	var tool = terrain.get_voxel_tool() if terrain != null else null
	if tool != null:
		tool.channel = VoxelBuffer.CHANNEL_TYPE
	# Spiral-ish outward scan in voxel coords. Step 64 vox (~6.4 m) over a
	# wide radius so we cross every biome (biome cells are ~600 m wide).
	var vpm: float = VoxelScale.VOXELS_PER_METER
	var step: int = 64
	var max_r: int = 60000   # voxels (~6 km)
	var r: int = 0
	while r < max_r and _biome_anchors.size() < 5:
		# Walk a square ring at radius r.
		var coords: Array = []
		var x := -r
		while x <= r:
			coords.append(Vector2i(x, -r))
			coords.append(Vector2i(x, r))
			x += step
		var z := -r + step
		while z < r:
			coords.append(Vector2i(-r, z))
			coords.append(Vector2i(r, z))
			z += step
		if r == 0:
			coords = [Vector2i(0, 0)]
		for c in coords:
			var dom: int = field.dominant_biome(c.x, c.y)
			if dom < 0 or _biome_anchors.has(dom):
				continue
			var w: Dictionary = field.resolve_biome_weights(c.x, c.y)
			var wts: PackedFloat64Array = w["weights"]
			if wts.size() == 0 or wts[0] < 0.9:
				continue
			# Pure column — find the ground world Y here.
			var gy := _biome_ground_y(tool, c.x, c.y)
			if gy < 0:
				continue
			# Require DRY land (ground above the 120-vox sea level) so the
			# shot isn't underwater. Low-amplitude biomes (plains/desert) sit
			# just above the waterline, so the margin is small (4 vox).
			if gy < 124:   # 124 vox = 12.4 m world; sea is 12 m
				continue
			_biome_anchors[dom] = Vector3(c.x, gy + 1, c.y) * VoxelScale.VOXEL_SIZE_M
		r += step
	# Build the shot list in slot order.
	for slot in range(5):
		if _biome_anchors.has(slot):
			var base: Vector3 = _biome_anchors[slot]
			_biome_shot_list.append([_BIOME_NAMES[slot], base, false])  # eye
			_biome_shot_list.append([_BIOME_NAMES[slot], base, true])   # high
			print("[SHOT] biome anchor %s at %s" % [_BIOME_NAMES[slot], str(base)])
		else:
			print("[SHOT] biome %s — no pure (>=0.9) column found within scan radius." % _BIOME_NAMES[slot])


func _biome_ground_y(tool, vx: int, vz: int) -> int:
	if tool == null:
		return -1
	for y in range(900, 100, -1):
		if tool.get_voxel(Vector3i(vx, y, vz)) != 0:
			return y
	return -1


func _biome_aim(i: int) -> void:
	var shot: Array = _biome_shot_list[i]
	var b: Vector3 = shot[1]
	var is_high: bool = shot[2]
	if is_high:
		# 30 m-high vantage angled DOWN over the biome (more ground, less
		# sky/ocean) so flat biomes still show their floor from above.
		_cam.position = b + Vector3(0, 30, 0)
		_cam.look_at(b + Vector3(35, -14, 35))
	else:
		# Eye level (1.7 m) looking slightly DOWN across the near ground so
		# the foreground terrain fills the frame instead of the horizon.
		_cam.position = b + Vector3(0, 1.7, 0)
		_cam.look_at(b + Vector3(16, 0.2, 11))
