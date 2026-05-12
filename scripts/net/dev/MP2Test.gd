extends Node3D

# MP-2 + MP-3 acceptance test scene. Two Godot instances of the
# project can connect via ENet on 127.0.0.1, each spawn a local
# Player3D with full input, see the OTHER peer as a RemotePlayer
# capsule walking around in real time (MP-2), AND see voxel edits
# carved by either peer reflected on both sides within ~200 ms
# (MP-3). The "Carve hole at me" button issues a 1.5 m sphere edit
# at the local player's feet via VoxelEditManager — clients
# automatically forward to the host.
#
# Layout built programmatically:
#   - Flat 40 m × 40 m floor at Y = 0
#   - DirectionalLight3D + WorldEnvironment (basic lighting)
#   - One local Player3D (instantiated from scenes/Player3D.tscn)
#   - PlayerSpawner node — listens to MultiplayerManager and parents
#     RemotePlayer instances under this scene
#   - Top-left CanvasLayer with Host (ENet) / Join (ENet) / Leave
#     buttons + peer count label
#
# Acceptance:
#   1. Launch project, F6 on this scene → one window appears with
#      Roland + UI buttons. Click Host (ENet).
#   2. Launch second instance, F6 again, click Join (ENet) with
#      127.0.0.1 in the field (default).
#   3. Both windows show a blue RemotePlayer capsule. Walk Roland
#      with WASD in window 1 — the capsule moves in window 2, and
#      vice versa.

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const SPAWN_POS := Vector3(0, 1.5, 0)
const REMOTE_OFFSET := Vector3(3, 0, 0)  # second peer spawns slightly to the side

var _player: Node = null
var _spawner: PlayerSpawner = null
var _ui_root: CanvasLayer = null
var _status_label: Label = null
var _peer_count_label: Label = null
var _edit_status_label: Label = null
var _host_btn: Button = null
var _join_btn: Button = null
var _leave_btn: Button = null
var _carve_btn: Button = null
var _join_target_edit: LineEdit = null
var _last_edit_event: String = "(none)"


func _ready() -> void:
	add_to_group("dev_scene")  # keep gameplay HUD / Pause UI quiet
	_build_world()
	_spawn_local_player()
	_attach_spawner()
	_build_ui()
	_refresh()
	# MP-3: surface every applied edit (local + replica) in the dev
	# panel so we can see two-way carve replication land in real time.
	if get_node_or_null("/root/VoxelEditManager"):
		VoxelEditManager.edit_applied.connect(_on_edit_applied)
		VoxelEditManager.edit_rejected_no_edit_zone.connect(_on_edit_rejected)
	# Refresh on MultiplayerManager state changes.
	var mp: Node = get_node_or_null("/root/MultiplayerManager")
	if mp != null:
		if mp.has_signal("session_started"):
			mp.session_started.connect(func(_m): _refresh())
		if mp.has_signal("session_ended"):
			mp.session_ended.connect(func(_r): _refresh())
		if mp.has_signal("peer_joined"):
			mp.peer_joined.connect(func(_p): _refresh())
		if mp.has_signal("peer_left"):
			mp.peer_left.connect(func(_p): _refresh())


# =============================================================
# WORLD
# =============================================================

func _build_world() -> void:
	# DirectionalLight + WorldEnvironment for visibility.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.0
	add_child(light)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.5, 0.65)
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 0.35
	env_node.environment = env
	add_child(env_node)

	# Floor: 40 m × 40 m static body.
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40, 0.5, 40)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(40, 0.5, 40)
	floor_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.25)
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	floor_body.position = Vector3(0, -0.25, 0)
	add_child(floor_body)


func _spawn_local_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player3D"
	add_child(_player)
	if "global_position" in _player:
		_player.set("global_position", SPAWN_POS)


func _attach_spawner() -> void:
	_spawner = PlayerSpawner.new()
	_spawner.name = "PlayerSpawner"
	_spawner.spawn_position = SPAWN_POS + REMOTE_OFFSET
	add_child(_spawner)


# =============================================================
# UI
# =============================================================

func _build_ui() -> void:
	_ui_root = CanvasLayer.new()
	_ui_root.layer = 5
	add_child(_ui_root)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_top = 8
	panel.offset_left = 8
	panel.custom_minimum_size = Vector2(280, 220)
	panel.size = Vector2(280, 220)
	_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_top = 8
	vbox.offset_left = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MP-2 Test"
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.text = "Mode: ?"
	vbox.add_child(_status_label)

	_peer_count_label = Label.new()
	_peer_count_label.text = "Peers: 0"
	vbox.add_child(_peer_count_label)

	_join_target_edit = LineEdit.new()
	_join_target_edit.text = "127.0.0.1"
	vbox.add_child(_join_target_edit)

	_host_btn = Button.new()
	_host_btn.text = "Host (ENet)"
	vbox.add_child(_host_btn)

	_join_btn = Button.new()
	_join_btn.text = "Join (ENet)"
	vbox.add_child(_join_btn)

	_leave_btn = Button.new()
	_leave_btn.text = "Leave"
	vbox.add_child(_leave_btn)

	_carve_btn = Button.new()
	_carve_btn.text = "Carve hole at me (MP-3)"
	vbox.add_child(_carve_btn)

	_edit_status_label = Label.new()
	_edit_status_label.text = "Last edit: (none)"
	_edit_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_edit_status_label.custom_minimum_size = Vector2(260, 0)
	vbox.add_child(_edit_status_label)


# =============================================================
# INPUT — manual click dispatch per CLAUDE.md
# =============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _hits(_host_btn, mb.position):
		_on_host_pressed()
	elif _hits(_join_btn, mb.position):
		_on_join_pressed()
	elif _hits(_leave_btn, mb.position):
		_on_leave_pressed()
	elif _hits(_carve_btn, mb.position):
		_on_carve_pressed()


func _hits(ctrl: Control, pos: Vector2) -> bool:
	if ctrl == null or not ctrl.visible or ctrl.disabled:
		return false
	return ctrl.get_global_rect().has_point(pos)


# =============================================================
# Button handlers
# =============================================================

func _on_host_pressed() -> void:
	if get_node_or_null("/root/MultiplayerManager"):
		MultiplayerManager.host_session()
		_refresh()


func _on_join_pressed() -> void:
	if get_node_or_null("/root/NetTransport") and get_node_or_null("/root/MultiplayerManager"):
		var addr: String = _join_target_edit.text.strip_edges()
		if addr == "":
			addr = "127.0.0.1"
		# MultiplayerManager.join_session takes address + optional port;
		# fall back to NetTransport directly if the helper signature
		# differs.
		if MultiplayerManager.has_method("join_session"):
			MultiplayerManager.call("join_session", addr)
		else:
			NetTransport.join(addr)
		_refresh()


func _on_leave_pressed() -> void:
	if get_node_or_null("/root/MultiplayerManager"):
		if MultiplayerManager.has_method("leave_session"):
			MultiplayerManager.call("leave_session")
		elif MultiplayerManager.has_method("end_session"):
			MultiplayerManager.call("end_session")
		_refresh()


func _refresh() -> void:
	if _status_label == null:
		return
	var mode: String = "OFFLINE"
	var local: int = 0
	if get_node_or_null("/root/MultiplayerManager"):
		if MultiplayerManager.is_host():
			mode = "HOST"
		elif MultiplayerManager.is_client():
			mode = "CLIENT"
		else:
			mode = "OFFLINE"
		local = MultiplayerManager.local_peer_id()
	_status_label.text = "Mode: %s   Local: %d" % [mode, local]
	var remotes: int = _spawner.get_remote_player_count() if _spawner != null else 0
	_peer_count_label.text = "Remote peers: %d" % remotes


# =============================================================
# MP-3 carve demo
# =============================================================

func _on_carve_pressed() -> void:
	# Issue a 1.5 m sphere carve at the local player's feet. On the
	# host this enqueues + broadcasts; on a client it forwards to the
	# host via _rpc_request_edit and returns optimistically.
	if _player == null or not get_node_or_null("/root/VoxelEditManager"):
		return
	var pos: Vector3 = Vector3.ZERO
	if "global_position" in _player:
		pos = _player.get("global_position")
	# Carve below the player's feet so the hole opens DOWN, not into
	# the air above. (No actual voxel terrain in this dev scene — the
	# acceptance test is the dispatch round-trip, not visual carving.
	# The flat StaticBody3D floor here is not VoxelLodTerrain.)
	var ok: bool = VoxelEditManager.queue_edit_sphere(pos + Vector3(0, -0.5, 0), 1.5, 0)
	_last_edit_event = "Sent sphere edit @ %s   ok=%s" % [pos, ok]
	if _edit_status_label != null:
		_edit_status_label.text = "Last edit: " + _last_edit_event


func _on_edit_applied(world_pos: Vector3, _chunk_coords: Vector3i, _aabb: AABB) -> void:
	_last_edit_event = "APPLIED @ (%.1f, %.1f, %.1f)" % [world_pos.x, world_pos.y, world_pos.z]
	if _edit_status_label != null:
		_edit_status_label.text = "Last edit: " + _last_edit_event


func _on_edit_rejected(world_pos: Vector3) -> void:
	_last_edit_event = "REJECTED @ (%.1f, %.1f, %.1f) — NoEditZone or bedrock" % [world_pos.x, world_pos.y, world_pos.z]
	if _edit_status_label != null:
		_edit_status_label.text = "Last edit: " + _last_edit_event
