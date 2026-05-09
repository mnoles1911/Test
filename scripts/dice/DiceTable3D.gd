extends Node3D
# DiceTable3D — 3D physics table for the Bones mini-game.
#
# Builds the felt plane, oak rim, candle light, camera, and 5 dice
# programmatically in _ready(). DiceGameUI hosts this scene inside a
# SubViewport so the result composites under the 2D overlay UI.
#
# Public API:
#   roll(active_indices)            — drop & spin the selected dice
#   get_face_values()               — read current face values (1..6)
#   set_die_lock_visual(idx, locked) — small visual hint that a die is locked
#
# Signals:
#   roll_settled(face_values: PackedInt32Array) — fires when every rolling
#       die has come to rest. Read the 5-element array for face values 1..6.
#
# Asset hooks (optional — fall back to solid colors if missing):
#   res://assets/dice/felt_burgundy.jpg   — felt material albedo
#   res://assets/dice/table_oak_rim.jpg   — rim material albedo
#   res://assets/dice/dice_face_atlas.jpg — die material albedo (3×2 grid:
#       top row faces 1/2/3 left→right, bottom row faces 4/5/6 left→right)

signal roll_settled(face_values: PackedInt32Array)

const DIE_COUNT: int = 5
const DIE_SIZE: float = 0.04                # 4 cm cube
const TABLE_RADIUS: float = 0.30            # 30 cm felt circle
const RIM_HEIGHT: float = 0.025
const SPAWN_HEIGHT: float = 0.20            # drop dice from 20 cm
const SETTLE_VELOCITY_EPSILON: float = 0.05  # below = "stopped"
const SETTLE_DELAY_SEC: float = 0.35         # must stay stopped this long

const FELT_TEX_PATH: String = "res://assets/dice/felt_burgundy.jpg"
const RIM_TEX_PATH: String = "res://assets/dice/table_oak_rim.jpg"
const DIE_TEX_PATH: String = "res://assets/dice/dice_face_atlas.jpg"

var _dice: Array[RigidBody3D] = []
var _lock_markers: Array[MeshInstance3D] = []   # little ring above each die
var _settle_timers: Array[float] = []           # per-die "stopped" accumulator
var _rolling_indices: Array[int] = []
var _settle_pending: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Built once, shared by every die. When the atlas JPG is on disk we use
# the custom-UV ArrayMesh; otherwise we fall back to a plain BoxMesh.
var _shared_die_mesh: Mesh = null


func _ready() -> void:
	_rng.randomize()
	_build_table()
	_build_camera_and_lights()
	_build_dice()


# =============================================================
# CONSTRUCTION
# =============================================================

func _build_table() -> void:
	# Felt circle — flat cylinder, very thin, dark burgundy.
	var felt: MeshInstance3D = MeshInstance3D.new()
	felt.name = "Felt"
	var felt_mesh: CylinderMesh = CylinderMesh.new()
	felt_mesh.top_radius = TABLE_RADIUS
	felt_mesh.bottom_radius = TABLE_RADIUS
	felt_mesh.height = 0.005
	felt_mesh.radial_segments = 48
	felt.mesh = felt_mesh
	var felt_mat: StandardMaterial3D = StandardMaterial3D.new()
	felt_mat.albedo_color = Color(0.30, 0.10, 0.12)   # dark burgundy fallback
	felt_mat.roughness = 0.95
	felt_mat.metallic = 0.0
	_apply_optional_texture(felt_mat, FELT_TEX_PATH)
	felt.set_surface_override_material(0, felt_mat)
	felt.position = Vector3.ZERO
	add_child(felt)

	# Floor below the table — invisible collider to catch any escaped dice.
	# Sits at a low Y so the camera doesn't see it framed.
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "Floor"
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.0, 0.02, 2.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, 0.0, 0.0)
	add_child(floor_body)

	# Oak rim — torus around the felt edge, slightly above the surface.
	var rim: MeshInstance3D = MeshInstance3D.new()
	rim.name = "Rim"
	var rim_mesh: TorusMesh = TorusMesh.new()
	rim_mesh.inner_radius = TABLE_RADIUS - 0.01
	rim_mesh.outer_radius = TABLE_RADIUS + 0.02
	rim_mesh.rings = 6
	rim_mesh.ring_segments = 48
	rim.mesh = rim_mesh
	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.27, 0.18, 0.12)   # dark oak fallback
	rim_mat.roughness = 0.85
	_apply_optional_texture(rim_mat, RIM_TEX_PATH)
	rim.set_surface_override_material(0, rim_mat)
	rim.position = Vector3(0.0, RIM_HEIGHT * 0.5, 0.0)
	add_child(rim)

	# Invisible inner wall — keeps dice on the felt. A tube made of
	# four StaticBody3D walls forming a rough square inside the rim.
	# Cylinder collision would be ideal but Godot lacks a hollow-cylinder
	# primitive; thin boxes around the perimeter are accurate enough.
	var wall_count: int = 12
	for i in wall_count:
		var theta: float = TAU * (float(i) / float(wall_count))
		var wall_body: StaticBody3D = StaticBody3D.new()
		wall_body.name = "RimWall_%d" % i
		var wall_shape: CollisionShape3D = CollisionShape3D.new()
		var wall_box: BoxShape3D = BoxShape3D.new()
		wall_box.size = Vector3(0.16, 0.06, 0.02)
		wall_shape.shape = wall_box
		wall_body.add_child(wall_shape)
		wall_body.position = Vector3(cos(theta) * (TABLE_RADIUS + 0.01),
									  0.03,
									  sin(theta) * (TABLE_RADIUS + 0.01))
		add_child(wall_body)
		wall_body.look_at(Vector3.ZERO, Vector3.UP)


func _build_camera_and_lights() -> void:
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	# Position the camera above and slightly forward of the table,
	# tilted ~30° downward. Frames the entire felt circle with a small
	# margin around the rim.
	cam.position = Vector3(0.0, 0.55, 0.55)
	cam.fov = 50.0
	add_child(cam)
	# look_at must run after add_child so the global transform exists.
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true

	# Warm candle key light (OmniLight3D) above the table.
	var candle: OmniLight3D = OmniLight3D.new()
	candle.name = "Candle"
	candle.position = Vector3(0.0, 0.50, 0.0)
	candle.light_color = Color(1.0, 0.78, 0.50)
	candle.light_energy = 1.4
	candle.omni_range = 1.8
	add_child(candle)

	# Cool fill light from the player side — lifts shadows on the dice
	# nearest the camera.
	var fill: OmniLight3D = OmniLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(0.0, 0.30, 0.55)
	fill.light_color = Color(0.65, 0.70, 0.85)
	fill.light_energy = 0.4
	fill.omni_range = 1.2
	add_child(fill)


func _build_dice() -> void:
	# Build each of the 5 dice. They start sleeping in a row above the
	# felt; roll() drops them with random impulses.
	var spacing: float = 0.07
	var row_y: float = SPAWN_HEIGHT
	var start_x: float = -spacing * 2.0
	for i in DIE_COUNT:
		var die: RigidBody3D = _make_die(i)
		die.position = Vector3(start_x + spacing * float(i), row_y, 0.0)
		die.sleeping = true
		add_child(die)
		_dice.append(die)
		_settle_timers.append(0.0)

		var marker: MeshInstance3D = _make_lock_marker()
		marker.visible = false
		add_child(marker)
		_lock_markers.append(marker)


func _make_die(index: int) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.name = "Die_%d" % index
	body.mass = 0.02
	body.linear_damp = 0.4
	body.angular_damp = 0.4
	body.continuous_cd = true
	body.can_sleep = true

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(DIE_SIZE, DIE_SIZE, DIE_SIZE)
	shape.shape = box_shape
	body.add_child(shape)

	# Build the shared mesh once. With the atlas, each face has its own
	# UV cell (3 columns × 2 rows on the JPG) so the cube actually shows
	# distinct pip patterns. Without it, a default BoxMesh + brown albedo
	# is the fallback.
	if _shared_die_mesh == null:
		if ResourceLoader.exists(DIE_TEX_PATH):
			_shared_die_mesh = _build_die_atlas_mesh()
		else:
			var box_mesh: BoxMesh = BoxMesh.new()
			box_mesh.size = Vector3(DIE_SIZE, DIE_SIZE, DIE_SIZE)
			_shared_die_mesh = box_mesh

	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = _shared_die_mesh
	var die_mat: StandardMaterial3D = StandardMaterial3D.new()
	die_mat.albedo_color = Color(0.78, 0.62, 0.40)   # honey oak fallback
	die_mat.roughness = 0.70
	_apply_optional_texture(die_mat, DIE_TEX_PATH)
	mesh.set_surface_override_material(0, die_mat)
	body.add_child(mesh)

	# Per-face Label3D fallbacks ONLY when the atlas is missing — the
	# atlas already paints the digit onto each face.
	if not ResourceLoader.exists(DIE_TEX_PATH):
		_attach_face_labels(body)

	return body


func _build_die_atlas_mesh() -> ArrayMesh:
	# Custom-UV cube mesh. The atlas is 3 cols × 2 rows. Each cube face
	# claims one cell, with the convention that opposite faces sum to 7
	# (matching _read_die_face).
	#
	# Atlas cell layout (col, row):
	#   (0,0)=face1  (1,0)=face2  (2,0)=face3
	#   (0,1)=face4  (1,1)=face5  (2,1)=face6
	#
	# Cube face → atlas cell:
	#   +Y (top)    value 1 → (0, 0)
	#   +X (right)  value 2 → (1, 0)
	#   +Z (front)  value 3 → (2, 0)
	#   -Z (back)   value 4 → (0, 1)
	#   -X (left)   value 5 → (1, 1)
	#   -Y (bottom) value 6 → (2, 1)
	#
	# Vertex winding for each face is CCW from outside so normals point
	# outward. UV order: v0=bottom-left, v1=bottom-right, v2=top-right,
	# v3=top-left of the texture cell.
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s: float = DIE_SIZE * 0.5

	var faces: Array = [
		# +Y top, value 1, cell (0,0)
		[Vector3(-s,  s,  s), Vector3( s,  s,  s), Vector3( s,  s, -s), Vector3(-s,  s, -s), Vector3.UP,      0, 0],
		# -Y bottom, value 6, cell (2,1)
		[Vector3(-s, -s, -s), Vector3( s, -s, -s), Vector3( s, -s,  s), Vector3(-s, -s,  s), Vector3.DOWN,    2, 1],
		# +X right, value 2, cell (1,0)
		[Vector3( s, -s,  s), Vector3( s, -s, -s), Vector3( s,  s, -s), Vector3( s,  s,  s), Vector3.RIGHT,   1, 0],
		# -X left, value 5, cell (1,1)
		[Vector3(-s, -s, -s), Vector3(-s, -s,  s), Vector3(-s,  s,  s), Vector3(-s,  s, -s), Vector3.LEFT,    1, 1],
		# +Z front, value 3, cell (2,0)
		[Vector3(-s, -s,  s), Vector3( s, -s,  s), Vector3( s,  s,  s), Vector3(-s,  s,  s), Vector3.BACK,    2, 0],
		# -Z back, value 4, cell (0,1)
		[Vector3( s, -s, -s), Vector3(-s, -s, -s), Vector3(-s,  s, -s), Vector3( s,  s, -s), Vector3.FORWARD, 0, 1],
	]

	for face in faces:
		var v0: Vector3 = face[0]
		var v1: Vector3 = face[1]
		var v2: Vector3 = face[2]
		var v3: Vector3 = face[3]
		var normal: Vector3 = face[4]
		var col: int = face[5]
		var row: int = face[6]

		var u_min: float = float(col) / 3.0
		var u_max: float = float(col + 1) / 3.0
		var v_min: float = float(row) / 2.0
		var v_max: float = float(row + 1) / 2.0

		# Triangle 1: v0 → v1 → v2
		st.set_normal(normal); st.set_uv(Vector2(u_min, v_max)); st.add_vertex(v0)
		st.set_normal(normal); st.set_uv(Vector2(u_max, v_max)); st.add_vertex(v1)
		st.set_normal(normal); st.set_uv(Vector2(u_max, v_min)); st.add_vertex(v2)
		# Triangle 2: v0 → v2 → v3
		st.set_normal(normal); st.set_uv(Vector2(u_min, v_max)); st.add_vertex(v0)
		st.set_normal(normal); st.set_uv(Vector2(u_max, v_min)); st.add_vertex(v2)
		st.set_normal(normal); st.set_uv(Vector2(u_min, v_min)); st.add_vertex(v3)

	return st.commit()


func _attach_face_labels(die: RigidBody3D) -> void:
	# Six small Label3Ds, one per face, showing the digit 1..6. Pure
	# debug-time fallback — when the real atlas drops in, ResourceLoader
	# will see the file and we skip this branch entirely.
	var half: float = DIE_SIZE * 0.5 + 0.001
	var face_data: Array = [
		{"text": "1", "pos": Vector3(0, half, 0),  "rot": Vector3(-PI/2, 0, 0)},
		{"text": "6", "pos": Vector3(0, -half, 0), "rot": Vector3(PI/2, 0, 0)},
		{"text": "2", "pos": Vector3(half, 0, 0),  "rot": Vector3(0, PI/2, 0)},
		{"text": "5", "pos": Vector3(-half, 0, 0), "rot": Vector3(0, -PI/2, 0)},
		{"text": "3", "pos": Vector3(0, 0, half),  "rot": Vector3(0, 0, 0)},
		{"text": "4", "pos": Vector3(0, 0, -half), "rot": Vector3(0, PI, 0)},
	]
	for entry in face_data:
		var label: Label3D = Label3D.new()
		label.text = entry.text
		label.position = entry.pos
		label.rotation = entry.rot
		label.pixel_size = 0.0015
		label.modulate = Color(0.15, 0.10, 0.05)
		label.outline_modulate = Color(1, 1, 1, 0)
		label.no_depth_test = false
		label.fixed_size = false
		die.add_child(label)


func _make_lock_marker() -> MeshInstance3D:
	# A small wax-seal-red ring that sits above a locked die so the
	# player can read the lock state from the 3D viewport too.
	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.name = "LockMarker"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.012
	torus.outer_radius = 0.020
	torus.rings = 4
	torus.ring_segments = 24
	marker.mesh = torus
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.18, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.10, 0.10)
	mat.emission_energy_multiplier = 0.6
	marker.set_surface_override_material(0, mat)
	return marker


func _apply_optional_texture(mat: StandardMaterial3D, path: String) -> void:
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			mat.albedo_texture = tex


# =============================================================
# PUBLIC API
# =============================================================

func roll(active_indices: PackedInt32Array) -> void:
	# Drops + spins the dice at the given indices. Other dice stay put.
	# Once all rolling dice settle, roll_settled is emitted with the
	# full 5-element face_values array (including non-rolled dice).
	_rolling_indices.clear()
	_settle_pending = true
	for idx in active_indices:
		if idx < 0 or idx >= DIE_COUNT:
			continue
		_rolling_indices.append(idx)
		_settle_timers[idx] = 0.0
		var die: RigidBody3D = _dice[idx]
		# Lift to spawn height with random horizontal jitter, give the
		# die a random spin and a small downward push.
		var jitter_x: float = _rng.randf_range(-0.06, 0.06)
		var jitter_z: float = _rng.randf_range(-0.06, 0.06)
		die.linear_velocity = Vector3.ZERO
		die.angular_velocity = Vector3.ZERO
		die.position = Vector3(jitter_x, SPAWN_HEIGHT, jitter_z)
		die.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		die.sleeping = false
		die.linear_velocity = Vector3(_rng.randf_range(-0.25, 0.25),
									   -0.30,
									   _rng.randf_range(-0.25, 0.25))
		die.angular_velocity = Vector3(_rng.randf_range(-12.0, 12.0),
										_rng.randf_range(-12.0, 12.0),
										_rng.randf_range(-12.0, 12.0))


func get_face_values() -> PackedInt32Array:
	# Reads current face value for every die based on which face normal
	# is closest to world up. Faces are numbered so opposite sides sum
	# to 7 (standard pip layout).
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(DIE_COUNT)
	for i in DIE_COUNT:
		out[i] = _read_die_face(_dice[i])
	return out


func set_die_lock_visual(idx: int, locked: bool) -> void:
	if idx < 0 or idx >= DIE_COUNT:
		return
	_lock_markers[idx].visible = locked


func get_die_world_position(idx: int) -> Vector3:
	if idx < 0 or idx >= DIE_COUNT:
		return Vector3.ZERO
	return _dice[idx].global_position


# =============================================================
# SETTLE DETECTION
# =============================================================

func _physics_process(delta: float) -> void:
	if not _settle_pending:
		_update_lock_marker_positions()
		return

	var all_settled: bool = true
	for idx in _rolling_indices:
		var die: RigidBody3D = _dice[idx]
		var v: float = die.linear_velocity.length()
		var av: float = die.angular_velocity.length()
		if v < SETTLE_VELOCITY_EPSILON and av < SETTLE_VELOCITY_EPSILON:
			_settle_timers[idx] += delta
		else:
			_settle_timers[idx] = 0.0
		if _settle_timers[idx] < SETTLE_DELAY_SEC:
			all_settled = false

	_update_lock_marker_positions()

	if all_settled and _rolling_indices.size() > 0:
		_settle_pending = false
		# Snap face value to integer perfectly by applying a tiny rotational
		# correction would be overkill; the dot-with-up read handles slight
		# tilts robustly because the closest face is always unambiguous unless
		# a die balances on an edge — which physics damping prevents in practice.
		roll_settled.emit(get_face_values())
	elif _rolling_indices.size() == 0:
		# Nothing to roll — emit immediately with current values.
		_settle_pending = false
		roll_settled.emit(get_face_values())


func _update_lock_marker_positions() -> void:
	# Lock markers float just above their associated die so the player
	# can see at a glance what's locked, even mid-tumble.
	for i in DIE_COUNT:
		if not _lock_markers[i].visible:
			continue
		var die: RigidBody3D = _dice[i]
		_lock_markers[i].global_position = die.global_position + Vector3(0.0, 0.035, 0.0)
		_lock_markers[i].rotation = Vector3(PI * 0.5, 0.0, 0.0)


func _read_die_face(die: RigidBody3D) -> int:
	# Convention (opposite faces sum to 7):
	#   +Y up → 1, -Y up → 6
	#   +X up → 2, -X up → 5
	#   +Z up → 3, -Z up → 4
	var basis: Basis = die.global_transform.basis
	var faces: Array = [
		{"normal": basis.y,       "value": 1},
		{"normal": -basis.y,      "value": 6},
		{"normal": basis.x,       "value": 2},
		{"normal": -basis.x,      "value": 5},
		{"normal": basis.z,       "value": 3},
		{"normal": -basis.z,      "value": 4},
	]
	var best_dot: float = -INF
	var best_value: int = 1
	for entry in faces:
		var d: float = (entry.normal as Vector3).normalized().dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best_value = entry.value
	return best_value
