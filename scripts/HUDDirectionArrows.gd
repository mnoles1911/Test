extends Control
# HUDDirectionArrows — over-head direction indicators for committed enemies.
#
# WHAT THIS DOES IN PLAIN ENGLISH
#
#   Phase 6 of the directional-melee v1. When an enemy commits to an
#   attack (Enemy3D.committed_attack signal via LockOnManager.tracked_
#   enemies), this control:
#
#     1. Projects the enemy's head position to screen space.
#     2. Draws a colored arrow above their head pointing in the matched
#        PARRY direction the player needs to flick the mouse.
#     3. Scales the arrow with time-to-impact — bigger / brighter as the
#        strike approaches.
#     4. If the enemy is OFF-SCREEN, clamps the arrow to the closest
#        screen edge so the player sees the threat coming from behind.
#
#   YELLOW (Colors.STAM) = parryable
#   RED    (Colors.HP_BRIGHT) = unblockable — dodge / don't parry
#
#   Added as a child of HUDOverlay._root in HUDOverlay._ready (so it
#   inherits visibility gating + dev-scene hide). Pure read-only Control;
#   no input handling (CLAUDE.md: Dialogic consumes mouse input globally).
#
# IMPLEMENTATION
#
#   _process re-snapshots LockOnManager.tracked_enemies once per frame
#   and walks committed attackers. We track our own per-enemy short-lived
#   record because the upstream committed_attack signal is fire-and-
#   forget — we need persisted state to draw the arrow for the duration
#   of the windup. Records expire on their own time_to_impact countdown.

const _DirectionSampler := preload("res://scripts/combat/MouseDirectionSampler.gd")

# How tall the arrow draws (px) at full size (impact <= 200 ms away).
const ARROW_MAX_SIZE: float = 56.0
# Minimum size (impact >= 600 ms away, just-committed).
const ARROW_MIN_SIZE: float = 28.0
# Vertical offset above enemy head where the arrow is drawn (px).
const ARROW_VERTICAL_OFFSET_PX: float = -8.0
# How far off-screen an enemy is before we draw the edge indicator.
const SCREEN_EDGE_MARGIN_PX: float = 36.0

# Per-enemy live record:
# instance_id → { "enemy": Node3D, "direction": int, "is_unblockable": bool,
#                 "expires_msec": int }
var _committed: Dictionary = {}

# Cached refs.
var _player: Node3D
var _camera: Camera3D
var _last_screen_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor to the full viewport so unproject_position results map 1:1
	# to local Control coordinates.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	# Connect to LockOnManager's tracked enemies — wait one frame so the
	# autoload is fully constructed in scene-load races.
	call_deferred("_subscribe_to_existing_enemies")


func _subscribe_to_existing_enemies() -> void:
	# Subscribe to committed_attack on every currently-tracked enemy.
	# New enemies caught via the SceneTree.node_added subscription below.
	get_tree().node_added.connect(_on_node_added)
	for e in get_tree().get_nodes_in_group("enemy"):
		_wire_enemy(e)


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node.is_in_group("enemy"):
		call_deferred("_wire_enemy", node)


func _wire_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not enemy.has_signal("committed_attack"):
		return
	# Avoid duplicate connection on re-arrival.
	if not enemy.committed_attack.is_connected(_on_enemy_committed.bind(enemy)):
		enemy.committed_attack.connect(_on_enemy_committed.bind(enemy))


func _on_enemy_committed(direction: int, time_to_impact: float, is_unblockable: bool, enemy: Node) -> void:
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	_committed[id] = {
		"enemy": enemy,
		"direction": direction,
		"is_unblockable": is_unblockable,
		"expires_msec": Time.get_ticks_msec() + int(maxf(0.05, time_to_impact) * 1000.0),
		"started_msec": Time.get_ticks_msec(),
		"window_msec": int(maxf(0.05, time_to_impact) * 1000.0),
	}
	queue_redraw()


func _process(_delta: float) -> void:
	# Resolve player / camera lazily.
	_resolve_refs()
	# Prune expired records + redraw if anything changed.
	var now_msec: int = Time.get_ticks_msec()
	var pruned: bool = false
	var dead_keys: Array = []
	for id in _committed.keys():
		var rec: Dictionary = _committed[id]
		var enemy: Node3D = rec.get("enemy") as Node3D
		if enemy == null or not is_instance_valid(enemy):
			dead_keys.append(id)
			pruned = true
			continue
		if "_is_dead" in enemy and enemy._is_dead:
			dead_keys.append(id)
			pruned = true
			continue
		if int(rec["expires_msec"]) <= now_msec:
			dead_keys.append(id)
			pruned = true
	for id in dead_keys:
		_committed.erase(id)
	# We always redraw — the arrow size / position lerps every frame.
	queue_redraw()
	_ignore(pruned)


func _draw() -> void:
	if _player == null or _camera == null:
		return
	if _committed.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size * 0.5
	var now_msec: int = Time.get_ticks_msec()

	# Resolve palette colors via the Colors autoload.
	var colors := get_node_or_null("/root/Colors")
	var yellow: Color = Color(0.78, 0.63, 0.29, 1.0)
	var red: Color = Color(0.92, 0.29, 0.23, 1.0)
	if colors != null:
		yellow = colors.STAM
		red = colors.HP_BRIGHT

	for id in _committed.keys():
		var rec: Dictionary = _committed[id]
		var enemy: Node3D = rec.get("enemy") as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		# Compute size from time-to-impact: bigger as impact approaches.
		var remaining_msec: int = int(rec["expires_msec"]) - now_msec
		var window_msec: int = int(rec.get("window_msec", 600))
		var t_to_impact_s: float = maxf(0.0, remaining_msec / 1000.0)
		var size_t: float = clampf(1.0 - (t_to_impact_s / 0.6), 0.0, 1.0)
		var size: float = lerpf(ARROW_MIN_SIZE, ARROW_MAX_SIZE, size_t)
		# Pulse intensity also ramps with size_t so the late arrows feel urgent.
		var pulse: float = 0.55 + 0.45 * size_t
		var col: Color = (red if bool(rec["is_unblockable"]) else yellow)
		col.a = clampf(pulse, 0.3, 1.0)

		# Project head position to screen.
		var head_world: Vector3 = enemy.global_position + Vector3(0.0, 2.0, 0.0)
		# Skip enemies behind the camera (unproject is undefined behind).
		if _camera.is_position_behind(head_world):
			# Behind camera — draw edge indicator on the appropriate side
			# instead of trying to project.
			_draw_edge_indicator(enemy, col, size)
			continue
		var screen_pos: Vector2 = _camera.unproject_position(head_world)
		# Off-screen clamp → edge indicator.
		var off_x: bool = screen_pos.x < SCREEN_EDGE_MARGIN_PX or screen_pos.x > viewport_size.x - SCREEN_EDGE_MARGIN_PX
		var off_y: bool = screen_pos.y < SCREEN_EDGE_MARGIN_PX or screen_pos.y > viewport_size.y - SCREEN_EDGE_MARGIN_PX
		if off_x or off_y:
			_draw_edge_indicator(enemy, col, size)
			continue
		_draw_arrow(screen_pos + Vector2(0, ARROW_VERTICAL_OFFSET_PX), int(rec["direction"]), size, col)
		_ignore(window_msec)
		_ignore(center)


# Render a triangular arrow at `pos`, rotated to point the way the player
# needs to flick the mouse to parry. Direction:
#   DIR_OVERHEAD → arrow points UP    (flick mouse up)
#   DIR_THRUST   → arrow points DOWN  (flick mouse down)
#   DIR_LEFT     → arrow points LEFT
#   DIR_RIGHT    → arrow points RIGHT
func _draw_arrow(pos: Vector2, direction: int, size: float, col: Color) -> void:
	var half: float = size * 0.5
	# Local triangle pointing up — we rotate per direction.
	var pts := PackedVector2Array([
		Vector2(0, -half),       # tip
		Vector2(-half * 0.7, half * 0.4),  # left base
		Vector2(half * 0.7, half * 0.4),   # right base
	])
	var rot_rad: float = 0.0
	match direction:
		_DirectionSampler.DIR_OVERHEAD: rot_rad = 0.0
		_DirectionSampler.DIR_RIGHT:    rot_rad = PI * 0.5
		_DirectionSampler.DIR_THRUST:   rot_rad = PI
		_DirectionSampler.DIR_LEFT:     rot_rad = -PI * 0.5
		_:                              rot_rad = 0.0
	var rotated := PackedVector2Array()
	for p in pts:
		rotated.append(p.rotated(rot_rad) + pos)
	# Fill + outline so it pops against bright skies.
	draw_colored_polygon(rotated, col)
	draw_polyline(_close(rotated), Color(0, 0, 0, col.a * 0.85), 2.0, true)


func _close(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _draw_edge_indicator(enemy: Node3D, col: Color, size: float) -> void:
	# Project the enemy's flat-ground position onto the screen-edge ring.
	# Build a 2D direction from the camera's yaw to the enemy and pick the
	# screen edge intersection point.
	if _player == null:
		return
	var to_enemy: Vector3 = enemy.global_position - _player.global_position
	to_enemy.y = 0.0
	if to_enemy.length_squared() < 0.0001:
		return
	# Camera yaw direction (player body forward).
	var forward: Vector3 = -_player.transform.basis.z.normalized()
	var right: Vector3 = _player.transform.basis.x.normalized()
	var to_norm: Vector3 = to_enemy.normalized()
	# 2D coords: x = right dot, y = forward dot (clamp so behind = -1).
	var x_comp: float = right.dot(to_norm)
	var y_comp: float = -forward.dot(to_norm)  # +y = down in screen space; behind = +1
	var dir2: Vector2 = Vector2(x_comp, y_comp).normalized()
	# Compute the screen-edge intersection.
	var vp: Vector2 = get_viewport_rect().size
	var half_w: float = vp.x * 0.5 - SCREEN_EDGE_MARGIN_PX
	var half_h: float = vp.y * 0.5 - SCREEN_EDGE_MARGIN_PX
	# Scale dir2 so it lands on the rectangle perimeter.
	var t: float = 1.0
	if absf(dir2.x) > 0.0001:
		t = minf(t, half_w / absf(dir2.x))
	if absf(dir2.y) > 0.0001:
		t = minf(t, half_h / absf(dir2.y))
	var center: Vector2 = vp * 0.5
	var pos: Vector2 = center + dir2 * t
	# Inward-pointing triangle so the player reads "threat coming from
	# this direction." Rotation = angle toward center.
	var to_center: Vector2 = (center - pos).normalized()
	var triangle := PackedVector2Array([
		Vector2(0, -size * 0.4),
		Vector2(-size * 0.35, size * 0.2),
		Vector2(size * 0.35, size * 0.2),
	])
	var rot_rad: float = atan2(to_center.x, -to_center.y)
	var rotated := PackedVector2Array()
	for p in triangle:
		rotated.append(p.rotated(rot_rad) + pos)
	draw_colored_polygon(rotated, col)
	draw_polyline(_close(rotated), Color(0, 0, 0, col.a * 0.85), 2.0, true)


# =============================================================
# REF RESOLUTION
# =============================================================

func _resolve_refs() -> void:
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0] as Node3D
	if _player == null:
		_camera = null
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = _player.get_node_or_null("CameraTarget/SpringArm3D/Camera3D") as Camera3D


func _ignore(_x) -> void:
	pass
