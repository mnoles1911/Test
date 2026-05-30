extends Node
class_name EnemyAttackPool
# EnemyAttackPool — directional attack state machine for a single enemy.
#
# WHAT THIS DOES IN PLAIN ENGLISH
#
#   Composed (NOT inherited) into a subclass like Goblin via `add_child`.
#   Owns a small state machine that decides when to wind up, swing, and
#   recover an attack, picking the direction from a weighted pool per
#   design/ENEMY_AI.md. Independent of Enemy3D's detection state — only
#   ticks when the host is in COMBAT.
#
#   States:
#     READY      — idle, eligible to start a new windup.
#     WINDUP     — telegraph visible (Goblin tints visual). Emits
#                  committed_attack signal on entry so MeleeHandler can
#                  open the parry window + LockOnManager can re-prioritise.
#     STRIKE     — single overlap test against the player. If in range
#                  and the host's _contact_damage_suppressed isn't a
#                  better fit, deal contact_damage.
#     RECOVERY   — short cooldown.
#     STAGGERED  — locked out by a successful player parry; waits for
#                  Enemy3D._stagger_remaining to tick down.
#
#   Why composition instead of subclass methods on Enemy3D:
#     Enemy3D is the chassis (HP / detection / corpse / loot). Per-enemy
#     attack flavor (jab vs swing vs leap, attack-pool weights, windup
#     duration, unblockable mix) varies per species. Composing a small
#     state-machine node into the species subclass keeps each species'
#     attack logic in one file without bloating the base.
#
#   Used by:
#     - scripts/enemies/Goblin.gd — instantiates this in _ready(),
#       configures the attack pool weights.
#     - Future Ashfallen, Wolf, Bear — same pattern, different config.

const _DirectionSampler := preload("res://scripts/combat/MouseDirectionSampler.gd")


# =============================================================
# CONFIG — set by the host (Goblin, Ashfallen, ...) in _ready()
# =============================================================

# Weighted attack table. Sum of weights need not equal 1.0; we normalise
# internally. Each entry:
#   { "id": String, "weight": float, "is_unblockable": bool,
#     "direction": int (DIR_* or -1 = random), "windup": float,
#     "strike_window": float, "recovery": float }
# Untyped Array so the host can pass a duplicate() of a typed const Array
# without typed-array-assignment grief in Godot 4.
@export var attack_pool: Array = []

# Player-detection range for entering windup. The host's combat_range
# governs whether the AttackPool ticks; this controls melee reach for
# the strike check.
@export var strike_range_meters: float = 1.6

# Wait between RECOVERY → READY → next windup. Stops a goblin from
# bottomless-spamming attacks.
@export var attack_cooldown_seconds: float = 0.6

# Speed multiplier on the host's movement during WINDUP/STRIKE/RECOVERY.
# 0.0 = freeze in place, 1.0 = no slowdown. Designer-tunable.
@export var movement_scale_during_attack: float = 0.15

# Pruned reference to the host Enemy3D and (optional) visual mesh whose
# material_override the pool tints. Set in initialize().
var _host: Node3D
var _player: Node3D
var _visual: MeshInstance3D
# Cached tint base (used to restore after WINDUP). Read from the
# visual's material_override.albedo_color on initialize().
var _original_albedo: Color = Color(1, 1, 1, 1)


# =============================================================
# STATE MACHINE
# =============================================================

enum AttackState { READY, WINDUP, STRIKE, RECOVERY, STAGGERED }

var current_state: int = AttackState.READY

var _state_remaining: float = 0.0    # countdown within current state
var _ready_cooldown_remaining: float = 0.0    # between attacks
var _current_attack: Dictionary = {}
var _current_direction: int = _DirectionSampler.DIR_RIGHT
var _current_is_unblockable: bool = false


# =============================================================
# PUBLIC API (host wires + drives this)
# =============================================================

func initialize(host: Node3D, visual: MeshInstance3D) -> void:
	_host = host
	_visual = visual
	if _host != null:
		var players := _host.get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0] as Node3D
	if _visual != null:
		var mat := _visual.get_active_material(0)
		if mat is StandardMaterial3D:
			_original_albedo = (mat as StandardMaterial3D).albedo_color
		# Build a unique material_override so tinting doesn't bleed into
		# every other Goblin sharing the same authored material.
		var mat_copy := StandardMaterial3D.new()
		mat_copy.albedo_color = _original_albedo
		_visual.material_override = mat_copy


## Returns the per-frame velocity scalar the host should apply to its
## existing walk speed. Slows the goblin during attack states so the
## telegraph is readable AND so it stops short of the player when about
## to swing.
func velocity_scale() -> float:
	if current_state == AttackState.READY:
		return 1.0
	if current_state == AttackState.STAGGERED:
		return 0.0
	return movement_scale_during_attack


## Public flag for the host: "should I be moving / executing AI right
## now?" Stagger lockout returns false.
func is_locked_out() -> bool:
	return current_state == AttackState.STAGGERED


## Drive the state machine. Host calls this from its `_enemy_physics_step`
## or `_physics_process` once per frame.
func tick(delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	# Honour the host's stagger countdown. If parried while in WINDUP
	# the host's stagger() set _contact_damage_suppressed=true and bumped
	# _stagger_remaining; we mirror that on our state.
	if _host.get("_stagger_remaining") != null and float(_host.get("_stagger_remaining")) > 0.0:
		if current_state != AttackState.STAGGERED:
			_enter_staggered()
		_state_remaining = float(_host.get("_stagger_remaining"))
		return

	# State-specific work + countdown.
	match current_state:
		AttackState.READY:
			_tick_ready(delta)
		AttackState.WINDUP:
			_tick_windup(delta)
		AttackState.STRIKE:
			_tick_strike(delta)
		AttackState.RECOVERY:
			_tick_recovery(delta)
		AttackState.STAGGERED:
			_tick_staggered(delta)


# =============================================================
# STATE HANDLERS
# =============================================================

func _tick_ready(delta: float) -> void:
	if _ready_cooldown_remaining > 0.0:
		_ready_cooldown_remaining = maxf(0.0, _ready_cooldown_remaining - delta)
		return
	# Only consider attacking if the host is in COMBAT and player is in
	# strike range plus a small buffer (we want the windup to start while
	# the player is just out of reach so the player can react).
	if _host == null or _player == null:
		return
	if _host.get("current_state") != Enemy3D.State.COMBAT:
		return
	var distance: float = _host.global_position.distance_to(_player.global_position)
	if distance > strike_range_meters + 0.6:
		# Too far — keep walking (host handles movement). Don't burn the
		# pool by attacking thin air.
		return
	# Pick an attack from the weighted pool.
	if attack_pool.is_empty():
		return
	_current_attack = _pick_weighted(attack_pool)
	_current_direction = int(_current_attack.get("direction", -1))
	if _current_direction < 0:
		# Random pick across the four directions.
		_current_direction = randi() % 4
	_current_is_unblockable = bool(_current_attack.get("is_unblockable", false))
	# Enter windup.
	_state_remaining = float(_current_attack.get("windup", 0.6))
	current_state = AttackState.WINDUP
	# Tint the host (yellow parryable, red unblockable). Colors are the
	# authoritative palette — see assets/ui/Colors.gd.
	_apply_telegraph_tint()
	# Tell the host to suppress its passive contact damage during the
	# whole attack window so it doesn't double-dip.
	if "_contact_damage_suppressed" in _host:
		_host._contact_damage_suppressed = true
	# Emit signals — Enemy3D.committed_attack for global subscribers
	# (MeleeHandler, LockOnManager, HUD).
	if _host.has_signal("committed_attack"):
		_host.committed_attack.emit(_current_direction, _state_remaining, _current_is_unblockable)


func _tick_windup(delta: float) -> void:
	_state_remaining -= delta
	if _state_remaining > 0.0:
		return
	# Transition to STRIKE — single overlap test this frame.
	current_state = AttackState.STRIKE
	_state_remaining = float(_current_attack.get("strike_window", 0.10))
	_perform_strike()


func _tick_strike(delta: float) -> void:
	_state_remaining -= delta
	if _state_remaining > 0.0:
		return
	# Strike done, into recovery.
	current_state = AttackState.RECOVERY
	_state_remaining = float(_current_attack.get("recovery", 0.4))
	# Restore visual tint at the end of strike (no longer telegraphing).
	_restore_albedo()


func _tick_recovery(delta: float) -> void:
	_state_remaining -= delta
	if _state_remaining > 0.0:
		return
	# Done — back to READY with cooldown.
	current_state = AttackState.READY
	_ready_cooldown_remaining = attack_cooldown_seconds
	# Re-enable passive contact damage once we're past the active swing window.
	if _host != null and "_contact_damage_suppressed" in _host:
		_host._contact_damage_suppressed = false


func _tick_staggered(delta: float) -> void:
	_state_remaining -= delta
	if _state_remaining > 0.0:
		return
	# Stagger over. Pop back to READY with a normal cooldown so the goblin
	# isn't immediately swinging again the frame the lockout ends.
	current_state = AttackState.READY
	_ready_cooldown_remaining = attack_cooldown_seconds
	_restore_albedo()
	if _host != null and "_contact_damage_suppressed" in _host:
		_host._contact_damage_suppressed = false


func _enter_staggered() -> void:
	current_state = AttackState.STAGGERED
	# Visual: revert tint immediately (no more telegraph) so the player
	# reads "I broke their swing" instead of an in-progress red flash.
	_restore_albedo()


# =============================================================
# STRIKE — actual damage to the player
# =============================================================

func _perform_strike() -> void:
	if _host == null or _player == null:
		return
	var distance: float = _host.global_position.distance_to(_player.global_position)
	if distance > strike_range_meters + 0.3:
		# Player stepped out of reach during windup. Whiff — no damage.
		return
	# Ask the player's MeleeHandler if a directional block is up. Returns
	# a damage multiplier: 1.0 = no block, 0.0 = matched block (or auto-
	# block), block_chip_fraction (0.6) = mismatched block. Without this
	# query the block direction is stored but never consulted (the
	# previous bug where the shield raised but damage passed through).
	var dmg_mult: float = 1.0
	var melee: Node = _player.get_node_or_null("MeleeHandler")
	if melee != null and melee.has_method("is_blocking_against"):
		dmg_mult = float(melee.call("is_blocking_against", _current_direction))
	var final_dmg: int = int(round(float(_host.contact_damage) * dmg_mult))
	# Log the block outcome via DebugOverlay so dev-arena testing can verify
	# the block layer end-to-end without instrumenting the player HP.
	if get_node_or_null("/root/DebugOverlay"):
		if dmg_mult <= 0.001:
			DebugOverlay.log_action("BLOCK matched — 0 dmg taken (would have been %d)" % _host.contact_damage)
		elif dmg_mult < 1.0:
			DebugOverlay.log_action("BLOCK mismatched — %d chip dmg taken (of %d)" % [final_dmg, _host.contact_damage])
	if final_dmg <= 0:
		return  # Fully blocked — no damage path.
	if not _player.has_method("apply_damage"):
		# Player3D may not have apply_damage yet (Player3D doesn't expose
		# one in v1; combat HP is reduced by direct enemy contact). Drop
		# damage onto the player.health field directly as a fallback so
		# the directional attack still bites in the dev arena.
		if "health" in _player:
			_player.health = maxf(0.0, _player.health - float(final_dmg))
		return
	_player.call("apply_damage", final_dmg)


# =============================================================
# VISUAL TELEGRAPH
# =============================================================

func _apply_telegraph_tint() -> void:
	if _visual == null:
		return
	var mat := _visual.material_override as StandardMaterial3D
	if mat == null:
		return
	# Yellow for parryable, red for unblockable. Pulled from the project
	# palette (assets/ui/Colors.gd). EnemyAttackPool extends Node, so we
	# walk the SceneTree direct — `Engine.get_main_loop().root.get_node_or_
	# null("Colors")` is the cross-cutting pattern but it can't be used
	# with `:=` because MainLoop has no typed `.root` and the parser
	# can't infer the chain's return type.
	var colors: Node = get_node_or_null("/root/Colors")
	if colors != null:
		mat.albedo_color = colors.HP_BRIGHT if _current_is_unblockable else colors.STAM
	else:
		mat.albedo_color = Color(0.92, 0.29, 0.23, 1) if _current_is_unblockable else Color(0.78, 0.63, 0.29, 1)


func _restore_albedo() -> void:
	if _visual == null:
		return
	var mat := _visual.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = _original_albedo


# =============================================================
# UTIL — weighted attack pick
# =============================================================

func _pick_weighted(pool: Array) -> Dictionary:
	var total: float = 0.0
	for entry in pool:
		total += float(entry.get("weight", 1.0))
	if total <= 0.0:
		return pool[0]
	var r: float = randf() * total
	var acc: float = 0.0
	for entry in pool:
		acc += float(entry.get("weight", 1.0))
		if r <= acc:
			return entry
	return pool.back()
