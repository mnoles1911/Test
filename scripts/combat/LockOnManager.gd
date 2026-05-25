extends Node
# LockOnManager — autoload. Always-on lock-on with auto-switching.
#
# WHAT THIS DOES IN PLAIN ENGLISH
#
#   Implements the "always-on" lock-on layer of the directional combat
#   redesign. Watches every enemy in the world (via the "enemy" group)
#   and:
#
#     - Engages: when ANY hostile enters COMBAT within ~25 m of the
#       player, locks the camera onto the nearest one.
#     - Auto-switches: when an enemy emits its committed_attack signal
#       (via Enemy3D.committed_attack), evaluates a priority queue
#       (unblockable > shortest time_to_impact > nearest > current) and
#       eases the camera to the new threat — UNLESS player is mid-swing,
#       just parried, or has hard-locked via MMB.
#     - Cycles: MMB tap (lock_on_cycle action) cycles the camera to the
#       next visible enemy in the forward 180° arc, left-to-right by
#       screen position. Hard-locks for 2 s; auto-switching disabled.
#     - Clears: MMB hold ≥350 ms or all hostiles dropping out of COMBAT
#       for 2 s releases the lock-on.
#
# WHY AUTOLOAD
#
#   One instance per session, lives across scene reloads (so a player
#   walking from one combat zone to another doesn't need re-init).
#   Subscribes to SceneTree.node_added so it picks up enemies spawned
#   mid-encounter (Reset Enemies, future EntityStreamer chunks) without
#   the spawning site needing to know about us.
#
# DEPENDENCIES
#
#   - Player3D group "player" (resolved each frame; lazy)
#   - Enemy3D group "enemy" + Enemy3D.state_changed signal + Enemy3D
#     .committed_attack signal (both declared in Phase 3)
#   - CameraRig: set_lock_on_target(), cycle_lock_target(), clear_lock_target()
#   - Player3D/MeleeHandler.is_attacking() — used to suppress auto-switch
#     during the player's own swing window (so the camera doesn't yank
#     away mid-strike)
#
# LOAD ORDER (project.godot): AudioManager → LockOnManager → NoEditZoneRegistry.
# Sits between the SFX layer and the voxel/edit layer — no dependency on
# either side beyond what's resolved lazily through the SceneTree.

# =============================================================
# CONFIG
# =============================================================

# Distance at which a hostile in COMBAT triggers auto-engagement.
const ENGAGEMENT_RADIUS_METERS: float = 25.0

# Delay before disengaging when no hostiles are in COMBAT.
const DISENGAGE_GRACE_SECONDS: float = 2.0

# Suppression after a player attack-window OR after a successful parry.
const SUPPRESS_AFTER_ATTACK_SECONDS: float = 0.4
const SUPPRESS_AFTER_PARRY_SECONDS: float = 0.2

# Rate cap on auto-switches — prevents whip-cam churn when two enemies
# commit on near-identical frames.
const MIN_SECONDS_BETWEEN_AUTO_SWITCHES: float = 0.3

# Hard-lock duration after an MMB-tap cycle.
const HARD_LOCK_SECONDS: float = 2.0

# MMB hold threshold to clear the lock entirely (vs cycle).
const MMB_CLEAR_HOLD_SECONDS: float = 0.35


# =============================================================
# STATE
# =============================================================

# All enemies we've subscribed to. Keyed by instance_id so we can detect
# duplicates on respawn.
var _tracked_enemies: Dictionary = {}  # instance_id → Node3D

# Cached references resolved lazily each tick.
var _player: Node3D
var _camera_rig: Node                  # the SpringArm3D running CameraRig.gd
var _melee_handler: Node               # for is_attacking() suppression

# Engagement state.
var _current_target: Node3D = null
var _no_combat_seconds: float = 0.0    # counts up while no enemies are COMBAT

# Auto-switch suppression timers.
var _suppress_until_msec: int = 0
var _last_switch_msec: int = 0

# Hard-lock (MMB tap cycle) state.
var _hard_lock_until_msec: int = 0
var _mmb_press_msec: int = 0           # 0 = not held
var _mmb_consumed: bool = false        # true once a release fired cycle/clear

# Public read-only for HUD widgets (Phase 6).
var tracked_enemies: Array = []        # snapshot, refreshed each tick


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Subscribe to node_added so enemies spawned mid-encounter wire up
	# automatically (Reset Enemies, EntityStreamer).
	get_tree().node_added.connect(_on_node_added)
	# Also walk any enemies already present at autoload init (the auto-
	# load itself loads before scene's root, so this is usually empty,
	# but it costs nothing).
	call_deferred("_rescan_existing_enemies")


func _on_node_added(node: Node) -> void:
	# Catch enemies that join the SceneTree after we started watching.
	# Wait one frame so the new node's _ready has run (groups, signals).
	if node == null:
		return
	if node.is_in_group("enemy"):
		call_deferred("_register_enemy", node)


func _rescan_existing_enemies() -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		_register_enemy(n)


func _register_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var id: int = enemy.get_instance_id()
	if _tracked_enemies.has(id):
		return
	# Honour the Enemy3D base contract — state_changed + committed_attack
	# are declared in Phase 3. Connect via has_signal so we're tolerant of
	# random non-Enemy3D things accidentally grouped as "enemy".
	if not (enemy is Node3D):
		return
	if enemy.has_signal("state_changed"):
		enemy.state_changed.connect(_on_enemy_state_changed.bind(enemy))
	if enemy.has_signal("committed_attack"):
		enemy.committed_attack.connect(_on_enemy_committed_attack.bind(enemy))
	# Clean up on free.
	enemy.tree_exited.connect(_on_enemy_tree_exited.bind(enemy), CONNECT_ONE_SHOT)
	_tracked_enemies[id] = enemy


func _on_enemy_tree_exited(enemy: Node) -> void:
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	_tracked_enemies.erase(id)
	# If the current target died, clear immediately so _process re-engages
	# the next-nearest hostile.
	if _current_target != null and not is_instance_valid(_current_target):
		_current_target = null
	if _current_target != null and _current_target.get_instance_id() == id:
		_current_target = null


# =============================================================
# SIGNAL HANDLERS
# =============================================================

func _on_enemy_state_changed(_old: int, _new: int, _enemy: Node) -> void:
	# Engagement decision happens in _process from the snapshot — we just
	# notice that something changed and let the per-frame logic re-evaluate.
	# (Subscribing for the side effect of having a clean signal-driven
	# entry point in the future.)
	pass


func _on_enemy_committed_attack(direction: int, time_to_impact: float, is_unblockable: bool, enemy: Node) -> void:
	# Highest-stakes signal — drives auto-switch.
	_maybe_auto_switch(enemy as Node3D, direction, time_to_impact, is_unblockable)


# =============================================================
# PER-FRAME LOGIC
# =============================================================

func _process(delta: float) -> void:
	var _t0: int = Time.get_ticks_usec()
	_process_inner(delta)
	var _elapsed: int = Time.get_ticks_usec() - _t0
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("COMBAT", "LockOnManager", _elapsed)


func _process_inner(delta: float) -> void:
	# Refresh cached refs lazily.
	_resolve_player()
	if _player == null:
		# No player in the tree (main menu / loading). Clear any stale lock.
		if _current_target != null:
			_clear_camera_lock()
		return

	# Maintain the tracked snapshot (cheap — bounded by enemy count).
	_refresh_tracked_snapshot()

	# MMB cycle / clear handling.
	_handle_mmb_input(delta)

	# Engagement / disengagement decision.
	var in_combat: Array = _enemies_in_combat_radius()
	if in_combat.size() > 0:
		_no_combat_seconds = 0.0
		if _current_target == null or not is_instance_valid(_current_target):
			_engage(_nearest(in_combat))
	else:
		_no_combat_seconds += delta
		if _current_target != null and _no_combat_seconds >= DISENGAGE_GRACE_SECONDS:
			_clear_camera_lock()


func _refresh_tracked_snapshot() -> void:
	tracked_enemies.clear()
	for n in _tracked_enemies.values():
		if n != null and is_instance_valid(n):
			tracked_enemies.append(n)


# =============================================================
# ENGAGEMENT
# =============================================================

func _engage(enemy: Node3D) -> void:
	if enemy == null:
		return
	_current_target = enemy
	_apply_lock_to_camera(enemy)


func _apply_lock_to_camera(enemy: Node3D) -> void:
	_resolve_camera_rig()
	if _camera_rig != null and _camera_rig.has_method("set_lock_on_target"):
		_camera_rig.call("set_lock_on_target", enemy)


func _clear_camera_lock() -> void:
	_resolve_camera_rig()
	_current_target = null
	if _camera_rig != null and _camera_rig.has_method("clear_lock_target"):
		_camera_rig.call("clear_lock_target")
	elif _camera_rig != null and _camera_rig.has_method("set_lock_on_target"):
		_camera_rig.call("set_lock_on_target", null)


# =============================================================
# AUTO-SWITCH
# =============================================================

func _maybe_auto_switch(enemy: Node3D, direction: int, time_to_impact: float, is_unblockable: bool) -> void:
	if enemy == null or _player == null or _current_target == enemy:
		return
	# Hard-lock suppression (MMB tap cycle reserves the camera for 2 s).
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _hard_lock_until_msec:
		return
	# Rate cap.
	if now_msec - _last_switch_msec < int(MIN_SECONDS_BETWEEN_AUTO_SWITCHES * 1000.0):
		return
	# Player-attack suppression.
	if now_msec < _suppress_until_msec:
		return
	if _is_player_attacking():
		# MeleeHandler is mid-swing — note the priority for after the window.
		# Refresh suppression so the very next frame after release still
		# evaluates rather than auto-switching with no input cue.
		_suppress_until_msec = now_msec + int(SUPPRESS_AFTER_ATTACK_SECONDS * 1000.0)
		return

	# Priority scoring:
	#   * unblockable beats everything else if not already targeted
	#   * else shortest time_to_impact wins
	#   * tiebreaker = distance to player
	# Just compare against the current target's situation — we already know
	# the new candidate's stats; we only swap if the new one is strictly
	# more urgent.
	if not _candidate_outranks_current(enemy, time_to_impact, is_unblockable):
		return
	_last_switch_msec = now_msec
	_engage(enemy)
	# Audio cue (no-op-safe via AudioManager).
	if get_node_or_null("/root/AudioManager"):
		AudioManager.play("cmb_lock_switch", enemy.global_position)
	# Phase 6 will use this — keep the call here so the wiring is in
	# place. direction is the matched parry direction the player needs.
	_ignore(direction)
	_ignore(is_unblockable)


func _candidate_outranks_current(candidate: Node3D, candidate_tti: float, candidate_unblockable: bool) -> bool:
	# No current → always outrank.
	if _current_target == null or not is_instance_valid(_current_target):
		return true
	# Unblockable always beats parryable (most urgent telegraph).
	if candidate_unblockable:
		return true
	# Otherwise, prefer closer enemies — TTI doesn't help unless we know
	# the current target's TTI, which we don't track once a windup
	# starts. Distance to player is a serviceable tiebreaker because
	# attacker reach is roughly equal across the v1 enemy roster.
	if _player == null:
		return false
	var cur_d: float = _current_target.global_position.distance_to(_player.global_position)
	var cand_d: float = candidate.global_position.distance_to(_player.global_position)
	# Require a meaningful improvement so two equidistant enemies don't
	# ping-pong the camera back and forth on each commit.
	return cand_d + 0.5 < cur_d
	# Future Phase 6+: incorporate candidate_tti for unattacked threats.


# =============================================================
# MMB INPUT (cycle / clear)
# =============================================================

func _handle_mmb_input(delta: float) -> void:
	if _player == null:
		return
	if not _player.has_method("_can_take_input") or not _player.call("_can_take_input"):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var just_pressed: bool = Input.is_action_just_pressed("lock_on_cycle")
	var just_released: bool = Input.is_action_just_released("lock_on_cycle")
	var is_pressed: bool = Input.is_action_pressed("lock_on_cycle")
	if just_pressed:
		_mmb_press_msec = Time.get_ticks_msec()
		_mmb_consumed = false
	# If held longer than the clear threshold, fire CLEAR immediately
	# (don't wait for release) so the player sees the response.
	if is_pressed and _mmb_press_msec != 0 and not _mmb_consumed:
		var held_msec: int = Time.get_ticks_msec() - _mmb_press_msec
		if held_msec >= int(MMB_CLEAR_HOLD_SECONDS * 1000.0):
			_mmb_consumed = true
			_clear_camera_lock()
			_hard_lock_until_msec = 0
	if just_released and _mmb_press_msec != 0:
		if not _mmb_consumed:
			# Tap — cycle.
			_cycle_target()
		_mmb_press_msec = 0
		_mmb_consumed = false
	_ignore(delta)


func _cycle_target() -> void:
	if _player == null:
		return
	# Build a list of visible enemies in the forward 180° arc, sorted by
	# screen X (left to right). Skip dead.
	var camera: Camera3D = _resolve_camera()
	if camera == null:
		return
	var forward: Vector3 = -_player.transform.basis.z.normalized()
	var visible_arr: Array = []
	for e in tracked_enemies:
		var enemy := e as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if "_is_dead" in enemy and enemy._is_dead:
			continue
		var to_e: Vector3 = enemy.global_position - _player.global_position
		to_e.y = 0.0
		if to_e.length_squared() < 0.0001:
			continue
		if forward.dot(to_e.normalized()) < 0.0:
			continue  # behind
		# Frustum-ish check via unproject — if the projected x is offscreen
		# we still allow it (cycle can include just-offscreen enemies the
		# player would want to pick next).
		var screen_pos: Vector2 = camera.unproject_position(enemy.global_position + Vector3(0.0, 1.0, 0.0))
		visible_arr.append({ "enemy": enemy, "x": screen_pos.x })
	if visible_arr.is_empty():
		return
	visible_arr.sort_custom(func(a, b): return a["x"] < b["x"])
	# Find the current target's index; pick the next; wrap.
	var current_idx: int = -1
	for i in visible_arr.size():
		if visible_arr[i]["enemy"] == _current_target:
			current_idx = i
			break
	var next_idx: int = (current_idx + 1) % visible_arr.size()
	if current_idx == -1:
		next_idx = 0
	_engage(visible_arr[next_idx]["enemy"])
	_hard_lock_until_msec = Time.get_ticks_msec() + int(HARD_LOCK_SECONDS * 1000.0)


# =============================================================
# PUBLIC API used by MeleeHandler / Phase 6 HUD
# =============================================================

# MeleeHandler calls this after a successful parry to give the camera a
# moment of "stay where you are" while the riposte plays.
func notify_parry_success() -> void:
	_suppress_until_msec = Time.get_ticks_msec() + int(SUPPRESS_AFTER_PARRY_SECONDS * 1000.0)


# Phase 6 HUDDirectionArrows reads this to know which dot to highlight.
func get_current_target() -> Node3D:
	return _current_target


# =============================================================
# QUERIES
# =============================================================

func _enemies_in_combat_radius() -> Array:
	var out: Array = []
	for e in tracked_enemies:
		var enemy := e as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if "_is_dead" in enemy and enemy._is_dead:
			continue
		var d: float = enemy.global_position.distance_to(_player.global_position)
		if d > ENGAGEMENT_RADIUS_METERS:
			continue
		# Treat COMBAT as the trigger but also accept any enemy that has
		# recently committed an attack (preserves engagement during the
		# brief moment a goblin transitions IDLE → ALERT → COMBAT).
		if enemy.get("current_state") == Enemy3D.State.COMBAT:
			out.append(enemy)
	return out


func _nearest(arr: Array) -> Node3D:
	if arr.is_empty() or _player == null:
		return null
	var best: Node3D = null
	var best_d: float = INF
	for e in arr:
		var enemy := e as Node3D
		var d: float = enemy.global_position.distance_squared_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _is_player_attacking() -> bool:
	_resolve_melee_handler()
	if _melee_handler == null:
		return false
	if not _melee_handler.has_method("is_attacking"):
		return false
	return bool(_melee_handler.call("is_attacking"))


# =============================================================
# REFERENCE RESOLUTION
# =============================================================

func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D
	else:
		_player = null


func _resolve_camera_rig() -> void:
	if _camera_rig != null and is_instance_valid(_camera_rig):
		return
	if _player == null:
		return
	_camera_rig = _player.get_node_or_null("CameraTarget/SpringArm3D")


func _resolve_camera() -> Camera3D:
	if _player == null:
		return null
	return _player.get_node_or_null("CameraTarget/SpringArm3D/Camera3D") as Camera3D


func _resolve_melee_handler() -> void:
	if _melee_handler != null and is_instance_valid(_melee_handler):
		return
	if _player == null:
		return
	_melee_handler = _player.get_node_or_null("MeleeHandler")


# Helper to silence unused-arg warnings on placeholder paths.
func _ignore(_x) -> void:
	pass
