extends Control
# HUDCombatRadar — small bottom-center radar showing nearby enemies.
#
# WHAT THIS DOES IN PLAIN ENGLISH
#
#   Phase 6 of the directional-melee v1. A small circular widget at the
#   bottom-center of the screen renders:
#
#     - One dot per enemy in LockOnManager.tracked_enemies (colored by
#       alert state).
#     - An arc on the perimeter showing the bearing of the currently
#       locked target.
#     - A red flash for any enemy currently winding up an unblockable
#       attack (so the player can read "incoming red" even before the
#       HUDDirectionArrows arrow renders).
#
#   COLORS (from assets/ui/Colors.gd):
#     IDLE      → Colors.IRON
#     ALERT     → Colors.STAM  (yellow)
#     COMBAT    → Colors.HP    (red)
#     UNBLOCKABLE windup → Colors.HP_BRIGHT (pulses on draw frame)
#
#   Read-only — no input handling. Added as child of HUDOverlay._root.

const RADAR_RADIUS_PX: float = 56.0
const RADAR_RANGE_METERS: float = 24.0       # 1:1 with LockOnManager.ENGAGEMENT_RADIUS
const DOT_RADIUS_PX: float = 4.5
const ARC_DEGREES: float = 22.0
const ARC_THICKNESS_PX: float = 3.0

# Cached refs.
var _player: Node3D
var _lock_manager: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(RADAR_RADIUS_PX * 2, RADAR_RADIUS_PX * 2)
	# Anchor bottom-center.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -RADAR_RADIUS_PX
	offset_right = RADAR_RADIUS_PX
	# Sit just above the quick-slot bar (~206 px from bottom).
	offset_top = -(RADAR_RADIUS_PX * 2 + 260.0)
	offset_bottom = -260.0


func _process(_delta: float) -> void:
	_resolve_refs()
	queue_redraw()


func _draw() -> void:
	if _player == null:
		return
	var colors := get_node_or_null("/root/Colors")
	# Palette fallbacks (color literal copy of assets/ui/Colors.gd).
	var iron: Color = Color(0.43, 0.39, 0.34, 1.0)
	var stam: Color = Color(0.78, 0.63, 0.29, 1.0)
	var hp: Color = Color(0.72, 0.19, 0.16, 1.0)
	var hp_bright: Color = Color(0.91, 0.29, 0.23, 1.0)
	var ink_dim: Color = Color(0.71, 0.62, 0.48, 1.0)
	if colors != null:
		iron = colors.IRON
		stam = colors.STAM
		hp = colors.HP
		hp_bright = colors.HP_BRIGHT
		ink_dim = colors.INK_DIM

	# Background ring (subtle dark disc with a worn-iron rim).
	var center := Vector2(RADAR_RADIUS_PX, RADAR_RADIUS_PX)
	draw_circle(center, RADAR_RADIUS_PX, Color(0.06, 0.06, 0.06, 0.45))
	draw_arc(center, RADAR_RADIUS_PX - 1.5, 0.0, TAU, 64, ink_dim, 1.5, true)
	# Crosshair tick to anchor the player's facing direction (up = forward).
	draw_line(center + Vector2(0, -RADAR_RADIUS_PX), center + Vector2(0, -RADAR_RADIUS_PX + 4), ink_dim, 1.0)

	if _lock_manager == null:
		return
	# Pull tracked enemies snapshot from LockOnManager.
	var tracked: Array = _lock_manager.get("tracked_enemies") as Array
	if tracked == null:
		return
	# Player body forward + right for converting world → radar local coords.
	var forward: Vector3 = -_player.transform.basis.z.normalized()
	var right: Vector3 = _player.transform.basis.x.normalized()

	var current_target: Node3D = null
	if _lock_manager.has_method("get_current_target"):
		current_target = _lock_manager.call("get_current_target")

	for e in tracked:
		var enemy := e as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if "_is_dead" in enemy and enemy._is_dead:
			continue
		var to_e: Vector3 = enemy.global_position - _player.global_position
		to_e.y = 0.0
		var dist: float = to_e.length()
		if dist > RADAR_RANGE_METERS:
			continue
		# Translate to radar-local 2D coords. Forward = -y (up), Right = +x.
		var x_comp: float = right.dot(to_e)
		var y_comp: float = -forward.dot(to_e)
		var radar_pos: Vector2 = Vector2(x_comp, y_comp) * (RADAR_RADIUS_PX / RADAR_RANGE_METERS) + center
		# Pick dot color by alert state.
		var col: Color = iron
		var state_val: Variant = enemy.get("current_state")
		if state_val != null:
			var s: int = int(state_val)
			if s == Enemy3D.State.ALERT:
				col = stam
			elif s == Enemy3D.State.COMBAT:
				col = hp
		# Override with bright red flash if this enemy is mid-unblockable.
		# We approximate by checking the AttackPool child node directly
		# rather than tracking another signal — cheap, robust.
		if _is_unblockable_winding(enemy):
			col = hp_bright
		draw_circle(radar_pos, DOT_RADIUS_PX, col)
		# Outline for visibility against the dark background.
		draw_arc(radar_pos, DOT_RADIUS_PX + 0.5, 0.0, TAU, 12, Color(0, 0, 0, 0.7), 1.0, true)

	# Locked-target bearing arc on the perimeter (so the player can see
	# which dot is currently "the one").
	if current_target != null and is_instance_valid(current_target):
		var to_t: Vector3 = current_target.global_position - _player.global_position
		to_t.y = 0.0
		if to_t.length_squared() > 0.0001:
			var bearing_rad: float = atan2(right.dot(to_t), -forward.dot(to_t))
			var arc_start: float = bearing_rad - deg_to_rad(ARC_DEGREES * 0.5) - PI * 0.5
			var arc_end: float = bearing_rad + deg_to_rad(ARC_DEGREES * 0.5) - PI * 0.5
			draw_arc(center, RADAR_RADIUS_PX - 0.5, arc_start, arc_end, 16, hp_bright, ARC_THICKNESS_PX, true)


func _is_unblockable_winding(enemy: Node3D) -> bool:
	# Cheap: walk the attack pool child if it exists and ask its current
	# state. Goblin composes one as a direct child. Returns false if no
	# pool present (so this is harmless for non-AttackPool enemies).
	var pool: Node = enemy.get_node_or_null("EnemyAttackPool")
	if pool == null:
		return false
	# AttackPool may not have a constant for AttackState.WINDUP visible
	# here without preloading the script — use the numeric value (1).
	if int(pool.get("current_state")) != 1:
		return false
	var attack: Dictionary = pool.get("_current_attack") as Dictionary
	return bool(attack.get("is_unblockable", false))


func _resolve_refs() -> void:
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0] as Node3D
	if _lock_manager == null:
		_lock_manager = get_node_or_null("/root/LockOnManager")
