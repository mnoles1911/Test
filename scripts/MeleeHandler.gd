extends Node3D
# MeleeHandler — handles sword + shield melee input (LMB swing, RMB parry/block).
#
# WHAT THIS DOES IN PLAIN ENGLISH
#
#   Sibling of ThrowableHandler and EditToolHandler. When the equipped weapon
#   is a melee_weapon (sword), this script owns the LMB action (swing) and
#   the RMB parry_block action (tap = parry, hold = block).
#
#   Directional combat: the direction Roland swings (or parries / blocks) is
#   read from the player's last ~120 ms of mouse motion at the moment of the
#   press. Up = overhead, Left = left sweep, Right = right sweep (default),
#   Down = thrust. The visible MeleeWeaponPivot tweens to a direction-specific
#   pose so the player can READ the swing in a v1 placeholder rig.
#
#   PHASE 1 (this commit): LMB tap swing + cone overlap damage + endurance
#   drain + sword-pivot tween + BloodVFX burst on hit.
#   PHASE 2: charged-attack hold + feint cancel + hyperarmor flag.
#   PHASE 3: RMB parry tap + block hold + shield raise + SkillManager dispatch.
#   PHASE 5: ParryChainTracker + wide-arc swings + riposte sweep.
#
#   Mirrors the input-routing pattern from ThrowableHandler / EditToolHandler:
#   _process polls the action state (rather than _unhandled_input subscribing)
#   so UI Control nodes with mouse_filter=STOP can't silently eat the press.
#
# MP-2 RULE: every Input.* call here MUST guard with Player3D._can_take_input.
# This handler is offline-only for v1 (gated at the top of _process by
# MultiplayerManager.is_offline()); MP routing for combat is a separate epic.
#
# Attached as a child of Player3D in scenes/Player3D.tscn.

const _DirectionSampler := preload("res://scripts/combat/MouseDirectionSampler.gd")
const _ParryChainTracker := preload("res://scripts/combat/ParryChainTracker.gd")


# =============================================================
# TIMING CONFIGURATION (designer-tunable)
# =============================================================

@export var attack_input_action: String = "attack"
@export var parry_input_action: String = "parry_block"

@export var windup_seconds: float = 0.18
# Time between pressing LMB and the actual strike. Long enough to read the
# direction commit visually; short enough to feel responsive.

@export var strike_seconds: float = 0.08
# How long the hitbox stays "live" once the swing reaches it. Short and
# explicit so enemies that step out at the last frame can avoid the hit.

@export var recovery_seconds: float = 0.25
# Cooldown after the strike before the next swing can begin. Keeps the
# player from machine-gunning swings and gives enemies a punish window.

@export var swing_cone_meters: float = 2.0
# Forward reach of the cone overlap test. Roland's sword + arm length.

@export var swing_cone_degrees_narrow: float = 90.0
# Cone arc for thrust + unwidened swings. Phase 5 widens overhead/left/
# right side swings to 110° via swing_cone_degrees_wide.

@export var swing_cone_degrees_wide: float = 110.0
# Phase 5 wide arc for the side swings + overhead — sweep up to 3 enemies.

@export var max_targets_per_swing: int = 3
# Cap on how many enemies a single wide swing can hit. Thrust is always 1.

# Charged-attack tuning (Phase 2)
@export var charge_threshold_seconds: float = 0.40
# How long LMB must be held before it becomes a charged attack. Below this
# threshold the release is treated as a normal tap.

@export var charge_full_seconds: float = 0.70
# Time from charge-start to full charge. CameraRig pinch ramps over this.

@export var charge_damage_multiplier: float = 2.0
# Charged-attack damage multiplier vs the weapon's combat_damage.

@export var feint_window_seconds: float = 0.10
# After a direction-flip during a charge, releasing within this window cancels
# the swing — no damage, no endurance cost. Per design.

# Parry / block tuning (Phase 3)
@export var parry_tap_max_seconds: float = 0.14
# Below this hold time, RMB counts as a parry tap; above, a block hold.

@export var parry_window_seconds: float = 0.30
# Window after an enemy committed_attack signal during which a matched
# parry tap succeeds.

@export var parry_refund_endurance: float = 5.0
# Endurance refunded on a successful (non-chained) parry.

@export var block_chip_fraction: float = 0.60
# Fraction of incoming damage that gets through when the player is blocking
# in the WRONG direction (mismatched block). 1.0 = no block, 0.0 = full block.
# 0.6 = 40% blocked, 60% chip damage taken. Designer-tunable.

@export var auto_block: bool = false
# Difficulty toggle (Bannerlord's "Auto Block" passive blocking option).
# When true, holding RMB blocks any incoming attack at full effectiveness
# regardless of the player's actual block direction. Lets the player focus
# on positioning + attack timing without learning directional reads.
# Toggle in CombatTest with the B key; production toggle lives in the
# Settings menu (deferred to v1.1).


# =============================================================
# STATE
# =============================================================

# Action cooldown — set by recovery. Below 0 = ready to swing.
var _next_swing_ready_t: float = 0.0

# Hold state — non-zero while LMB is held. The Bannerlord model: press LMB
# starts the windup, flick during the hold to lock a direction, release to
# fire the swing. Quick release (< charge_threshold) = light damage; long
# hold release (>= charge_threshold) = charged 2x damage.
var _charge_pressed_t: int = 0        # ticks_usec when LMB went down (0 = not held)
var _charge_active: bool = false      # passed the charge threshold
# Direction locked at the FIRST flick during the hold. Persists for the rest
# of the hold even after the sampler window forgets the flick — so a 1-second
# hold with one flick at the start still fires in that direction on release.
# DIR_NONE = the player has not flicked yet this hold.
var _held_swing_direction: int = _DirectionSampler.DIR_NONE
# For feint detection: if the player changes direction during the hold and
# releases within feint_window_seconds of the change, the swing cancels.
var _last_direction_change_usec: int = 0
var _direction_before_last_flip: int = _DirectionSampler.DIR_NONE

# Auto-alternating direction for no-flick releases. Bannerlord cycles
# left, right, left, right... when you don't flick. Start with RIGHT so
# the first auto-swing matches the old "default RIGHT" behavior.
var _auto_alternate_next: int = _DirectionSampler.DIR_RIGHT

# Live attack state machine.
enum SwingPhase { IDLE, WINDUP, STRIKE, RECOVERY }
var _swing_phase: int = SwingPhase.IDLE
var _swing_phase_remaining: float = 0.0
var _current_swing_direction: int = _DirectionSampler.DIR_RIGHT
var _current_swing_damage: int = 0
var _current_swing_is_charged: bool = false
var _current_swing_hit_enemies: Array = []  # avoid hitting same enemy twice

# RMB parry/block state.
var _rmb_pressed_t: int = 0          # ticks_usec when RMB went down (0 = not held)
var _block_active: bool = false      # passed the tap threshold → holding block
var _block_direction: int = _DirectionSampler.DIR_RIGHT
var _last_incoming_attack_direction: int = _DirectionSampler.DIR_RIGHT
# Updated when a nearby enemy emits committed_attack — used as the block
# default direction so a quick RMB hold "matches" the last threat without
# the player having to re-aim the mouse.

# Active committed-attack events from nearby enemies, keyed by enemy
# instance ID. Pruned as their windows expire. Phase 3 fills this; the
# parry tap walks it to find a matching attack within window.
# Format: { instance_id: { "direction": int, "expires_t": float (Time.get_ticks_msec scaled) } }
var _pending_attacks: Dictionary = {}

# Mouse direction sampler — fed every motion event, queried on press.
var _direction_sampler: RefCounted

# Parry chain tracker (Phase 5) — public so HUDOverlay can read the
# current chain count for the on-screen indicator.
var parry_chain: RefCounted

# Cached references resolved in _ready().
var _player: CharacterBody3D
var _melee_pivot: Node3D
var _shield_pivot: Node3D
var _melee_weapon_hitbox: Area3D
var _swing_tween: Tween    # active sword tween, cancelled on new swing


# =============================================================
# CACHED HOME POSES (built at _ready)
# =============================================================

# Sword resting pose (when not swinging). Sword sits in Roland's right
# hand pointing forward+down at a relaxed angle. Set at _ready from the
# pivot's authored .tscn transform.
var _sword_home_transform: Transform3D
var _shield_home_transform: Transform3D


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_error("[MeleeHandler] Parent must be Player3D (CharacterBody3D)")
		return
	_melee_pivot = _player.get_node_or_null("MeleeWeaponPivot") as Node3D
	_shield_pivot = _player.get_node_or_null("ShieldPivot") as Node3D
	_melee_weapon_hitbox = _player.get_node_or_null("MeleeWeaponPivot/MeleeWeaponHitbox") as Area3D
	if _melee_pivot == null:
		push_warning("[MeleeHandler] No MeleeWeaponPivot child on Player3D — directional swings will be invisible.")
	if _shield_pivot == null:
		push_warning("[MeleeHandler] No ShieldPivot child on Player3D — block will be invisible.")
	if _melee_pivot != null:
		_sword_home_transform = _melee_pivot.transform
	if _shield_pivot != null:
		_shield_home_transform = _shield_pivot.transform
	_direction_sampler = _DirectionSampler.new()
	parry_chain = _ParryChainTracker.new()


# Called from EnemyAttackPool (Phase 3) when an enemy starts WINDUP.
# Opens the parry window for the matched direction and updates the
# "last incoming attack direction" so a quick block hold can default
# to the threat that's already coming at you.
func notify_enemy_committed(enemy: Node3D, direction: int, time_to_impact_s: float) -> void:
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	var expires_msec: int = Time.get_ticks_msec() + int(maxf(parry_window_seconds, time_to_impact_s) * 1000.0)
	_pending_attacks[id] = {
		"direction": direction,
		"expires_t": expires_msec,
		"enemy": enemy,
	}
	_last_incoming_attack_direction = direction


# =============================================================
# PUBLIC API (used by HUD)
# =============================================================

# True while a player swing is in WINDUP / STRIKE / RECOVERY. Used by the
# HUDDirectionArrows fade-in and by phase-2's hyperarmor flag — also
# kept as a public flag for any future system that wants to know "is
# the player committed to a swing right now?"
func is_attacking() -> bool:
	return _swing_phase != SwingPhase.IDLE


# Public block query for EnemyAttackPool — asked before applying damage so
# a matched-direction block can null the hit, a mismatched block can chip,
# and auto-block can clear everything. Returns the damage multiplier the
# caller should apply: 0.0 = fully blocked (no damage), 1.0 = no block,
# block_chip_fraction = mismatched block.
#
# attack_direction is the enemy's committed direction (the DIR_* the
# EnemyAttackPool emitted). Both characters use the same enum convention,
# so DIR_LEFT match-blocks DIR_LEFT (see design note in MouseDirection
# Sampler — "where the sword ends" is the same on both sides).
func is_blocking_against(attack_direction: int) -> float:
	if not _block_active:
		return 1.0
	if auto_block:
		# Bannerlord-style auto-block: the shield always aligns to the
		# incoming attack regardless of mouse direction. Easy mode.
		return 0.0
	if attack_direction == _block_direction:
		# Matched direction → full block.
		return 0.0
	# Mismatched block → chip damage gets through.
	return block_chip_fraction


# =============================================================
# INPUT — mouse motion feeds the direction sampler
# =============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if not _can_take_local_input():
		return
	var motion := event as InputEventMouseMotion
	_direction_sampler.push(motion.relative)


# =============================================================
# PER-FRAME UPDATE
# =============================================================

func _process(delta: float) -> void:
	# Profile so the F3 overlay can attribute time to the handler. Cheap.
	var _t0: int = Time.get_ticks_usec()
	_process_inner(delta)
	var _elapsed: int = Time.get_ticks_usec() - _t0
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("COMBAT", "MeleeHandler", _elapsed)
	var hud := get_node_or_null("/root/HUDOverlay")
	if hud != null:
		hud.profile_record("MeleeHandler", _elapsed)


func _process_inner(delta: float) -> void:
	# Prune expired parry-window entries.
	_prune_pending_attacks()
	# Decay the chain window — auto-breaks the chain if the player misses
	# the next parry within the schedule.
	if parry_chain != null:
		parry_chain.tick(delta)

	# v1 is offline-only. MP routing is a separate epic.
	if get_node_or_null("/root/MultiplayerManager"):
		if not MultiplayerManager.is_offline():
			return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not _can_take_local_input():
		return

	# Only handle melee input when a melee_weapon is equipped. Otherwise
	# the other handlers (Throwable, EditTool) own LMB.
	if not _has_melee_weapon_equipped():
		# If we previously had a charge or block in flight, cancel cleanly.
		if _charge_pressed_t != 0:
			_cancel_charge()
		if _block_active:
			_release_block()
		return

	# Drive swing state machine forward.
	if _swing_phase != SwingPhase.IDLE:
		_advance_swing(delta)
	if _next_swing_ready_t > 0.0:
		_next_swing_ready_t = maxf(0.0, _next_swing_ready_t - delta)

	# --- LMB: directional swing / charge ---
	_handle_attack_input()

	# --- RMB: parry tap / block hold ---
	_handle_parry_block_input()


func _can_take_local_input() -> bool:
	# Mirror Player3D._can_take_input via the parent reference so we honour
	# OFFLINE + local-authority modes the same way.
	if _player == null:
		return false
	if _player.has_method("_can_take_input"):
		return _player.call("_can_take_input")
	return true


func _has_melee_weapon_equipped() -> bool:
	if not get_node_or_null("/root/InventoryManager"):
		return false
	var eid: String = InventoryManager.get_equipped("weapon")
	if eid == "" or not InventoryManager.ITEM_REGISTRY.has(eid):
		return false
	return InventoryManager.ITEM_REGISTRY[eid].get("type", "") == "melee_weapon"


# =============================================================
# LMB — directional swing / charged attack
# =============================================================

func _handle_attack_input() -> void:
	# Bannerlord-style hold-flick-release attack:
	#   1. Press LMB → start windup tracking. No direction locked yet.
	#   2. Flick the mouse at any point during the hold → that direction is
	#      LOCKED for this swing (survives the rest of the hold even if the
	#      sampler window forgets the flick a moment later).
	#   3. Flick to a DIFFERENT direction during the hold → feint potential
	#      if released within feint_window_seconds.
	#   4. Release LMB:
	#      - If a flick was locked → swing in that direction.
	#      - If no flick was locked → auto-alternate (LRLR...) so silent
	#        presses still produce varied swings.
	#      - If a recent flick changed direction within the feint window
	#        → cancel cleanly (no swing, no damage, no EP).
	#   5. Hold time controls light vs charged: < charge_threshold = light,
	#      >= charge_threshold = charged (2x damage). Same flow either way.
	var just_pressed: bool = Input.is_action_just_pressed(attack_input_action)
	var just_released: bool = Input.is_action_just_released(attack_input_action)
	var is_pressed: bool = Input.is_action_pressed(attack_input_action)

	# --- Press: start tracking the hold. Reset direction lock.
	if just_pressed and _swing_phase == SwingPhase.IDLE and _next_swing_ready_t <= 0.0:
		_charge_pressed_t = Time.get_ticks_usec()
		_charge_active = false
		_held_swing_direction = _DirectionSampler.DIR_NONE
		_direction_before_last_flip = _DirectionSampler.DIR_NONE
		_last_direction_change_usec = _charge_pressed_t

	# --- Hold: lock direction on the first flick + track flips for feint.
	if is_pressed and _charge_pressed_t != 0:
		var held_s_hold: float = (Time.get_ticks_usec() - _charge_pressed_t) / 1_000_000.0
		# Promote to charged once threshold passed.
		if not _charge_active and held_s_hold >= charge_threshold_seconds:
			_charge_active = true
			_set_player_hyperarmor(true)
		# Camera FOV pinch ramps from 0 → 1 over charge_full_seconds.
		if _charge_active:
			var pinch_t: float = clampf(held_s_hold / charge_full_seconds, 0.0, 1.0)
			_apply_camera_pinch(pinch_t)
		# Direction lock: the first time the sampler returns a real direction
		# (not DIR_NONE), capture it. Subsequent samples only override the
		# lock if they're a DIFFERENT non-NONE direction (that's a feint
		# attempt; we remember the previous direction so we can detect the
		# flip on release).
		var sampled_dir: int = _direction_sampler.sample()
		if sampled_dir != _DirectionSampler.DIR_NONE and sampled_dir != _held_swing_direction:
			_direction_before_last_flip = _held_swing_direction
			_held_swing_direction = sampled_dir
			_last_direction_change_usec = Time.get_ticks_usec()

	# --- Release: fire the locked direction, auto-alternate, or feint-cancel.
	if just_released and _charge_pressed_t != 0:
		var held_s: float = (Time.get_ticks_usec() - _charge_pressed_t) / 1_000_000.0
		# Feint: the player locked direction A, then flicked to direction B,
		# then released within feint_window_seconds of the flip. The hold
		# must have been long enough to be "real" (above the tap threshold
		# of feint_window_seconds + a small grace) so reactive tap-releases
		# don't all read as feints.
		var since_flip_s: float = (Time.get_ticks_usec() - _last_direction_change_usec) / 1_000_000.0
		var did_feint: bool = (
			_direction_before_last_flip != _DirectionSampler.DIR_NONE
			and since_flip_s <= feint_window_seconds
			and held_s > feint_window_seconds + 0.05
		)
		if did_feint:
			_cancel_charge()
			return
		# Pick the swing direction. If the player flicked, use the lock.
		# Otherwise auto-alternate LRLR so silent presses still vary.
		var direction: int
		if _held_swing_direction != _DirectionSampler.DIR_NONE:
			direction = _held_swing_direction
		else:
			direction = _auto_alternate_next
			# Flip the toggle for next time.
			_auto_alternate_next = (
				_DirectionSampler.DIR_LEFT
				if _auto_alternate_next == _DirectionSampler.DIR_RIGHT
				else _DirectionSampler.DIR_RIGHT
			)
		_begin_swing(direction, _charge_active)
		_charge_pressed_t = 0
		_charge_active = false
		_set_player_hyperarmor(false)
		_apply_camera_pinch(0.0)


func _cancel_charge() -> void:
	# Feint or weapon-swap cancel. Clear charge state, snap FOV back, drop
	# the hyperarmor flag. No swing, no endurance cost.
	_charge_pressed_t = 0
	_charge_active = false
	_held_swing_direction = _DirectionSampler.DIR_NONE
	_direction_before_last_flip = _DirectionSampler.DIR_NONE
	_set_player_hyperarmor(false)
	_apply_camera_pinch(0.0)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("FEINT cancelled")


func _begin_swing(direction: int, is_charged: bool) -> void:
	# Resolve weapon damage / endurance from InventoryManager.
	var weapon_data: Dictionary = _resolve_weapon_data()
	var base_dmg: int = int(weapon_data.get("combat_damage", 15))
	var charged_dmg: int = int(weapon_data.get("power_damage", int(base_dmg * charge_damage_multiplier)))
	var end_light: float = float(weapon_data.get("endurance_light", 8.0))
	var end_charged: float = float(weapon_data.get("endurance_charged", 18.0))

	# Endurance drain. Charged-release cost only on release (not while held).
	var end_cost: float = end_charged if is_charged else end_light
	if _player != null and "endurance" in _player:
		_player.endurance = maxf(0.0, _player.endurance - end_cost)

	_swing_phase = SwingPhase.WINDUP
	_swing_phase_remaining = windup_seconds
	_current_swing_direction = direction
	_current_swing_damage = charged_dmg if is_charged else base_dmg
	_current_swing_is_charged = is_charged
	_current_swing_hit_enemies.clear()
	# Stage 1 of the 3-stage swing: sword tweens to the WINDUP pose (raised
	# back / cocked to the side / drawn back). Stage 2 fires when WINDUP
	# transitions to STRIKE inside _advance_swing.
	_tween_sword_to_windup(direction, windup_seconds)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("SWING dir=%d %s dmg=%d ep=%.0f" % [
			direction, ("CHARGED" if is_charged else "light"), _current_swing_damage, end_cost,
		])


func _advance_swing(delta: float) -> void:
	_swing_phase_remaining -= delta
	if _swing_phase_remaining > 0.0:
		return
	match _swing_phase:
		SwingPhase.WINDUP:
			# Enter STRIKE: perform the damage check this frame and on each
			# subsequent strike-window frame (only one chance to hit each
			# enemy via _current_swing_hit_enemies).
			# Stage 2 of the 3-stage swing: tween from the windup pose to
			# the STRIKE pose (chopped down / swept across / thrust forward).
			# This is the visible "swing" — fast, with EASE_IN so the sword
			# accelerates through contact.
			_swing_phase = SwingPhase.STRIKE
			_swing_phase_remaining = strike_seconds
			_tween_sword_to_strike(_current_swing_direction, strike_seconds)
			_perform_strike_check()
		SwingPhase.STRIKE:
			# Move to recovery + start tween back to home pose.
			_swing_phase = SwingPhase.RECOVERY
			_swing_phase_remaining = recovery_seconds
			_tween_sword_to_home(recovery_seconds)
		SwingPhase.RECOVERY:
			_swing_phase = SwingPhase.IDLE
			_next_swing_ready_t = 0.0
			# Reset accumulated hit list so the next swing can hit
			# the same enemies again.
			_current_swing_hit_enemies.clear()


func _perform_strike_check() -> void:
	if _player == null:
		return
	# Cone test: forward N metres from player, ±half_arc degrees from facing.
	# Side swings + overhead get the wide arc; thrust stays narrow.
	var arc_degrees: float = swing_cone_degrees_narrow
	if _current_swing_direction != _DirectionSampler.DIR_THRUST:
		arc_degrees = swing_cone_degrees_wide
	var max_targets: int = 1 if _current_swing_direction == _DirectionSampler.DIR_THRUST else max_targets_per_swing
	var forward: Vector3 = -_player.transform.basis.z.normalized()
	var origin: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)  # chest height
	var half_arc_cos: float = cos(deg_to_rad(arc_degrees * 0.5))

	var hits: int = 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if hits >= max_targets:
			break
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy in _current_swing_hit_enemies:
			continue
		var e_node := enemy as Node3D
		if e_node == null:
			continue
		# Skip dead enemies.
		if "_is_dead" in e_node and e_node._is_dead:
			continue
		var to_enemy: Vector3 = e_node.global_position - _player.global_position
		var dist: float = to_enemy.length()
		if dist > swing_cone_meters:
			continue
		if dist < 0.01:
			# Co-located — count as a hit regardless of direction.
			pass
		else:
			var to_dir: Vector3 = to_enemy.normalized()
			to_dir.y = 0.0
			to_dir = to_dir.normalized() if to_dir.length() > 0.0001 else to_dir
			var dot: float = forward.dot(to_dir)
			if dot < half_arc_cos:
				continue
		# Hit. Apply damage and spawn blood burst.
		_current_swing_hit_enemies.append(enemy)
		hits += 1
		_apply_damage_to(enemy as Node3D, origin)


func _apply_damage_to(enemy: Node3D, origin: Vector3) -> void:
	if enemy == null or not enemy.has_method("take_damage"):
		return
	var hit_point: Vector3 = enemy.global_position + Vector3(0.0, 1.0, 0.0)
	var hit_dir: Vector3 = (hit_point - origin)
	hit_dir.y = 0.0
	if hit_dir.length() > 0.0001:
		hit_dir = hit_dir.normalized()
	else:
		hit_dir = -_player.transform.basis.z.normalized()
	# Set last_hit_skill so CombatXPRouter attributes the kill/hit to sword.
	if "last_hit_skill" in enemy:
		enemy.last_hit_skill = "sword"
	enemy.take_damage(_current_swing_damage, hit_dir, hit_point)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("SWORD HIT %s for %d dmg" % [enemy.name, _current_swing_damage])
	# Spawn blood burst at the hit point. Intensity scales with damage so
	# charged hits read as gorier.
	if get_node_or_null("/root/BloodVFX"):
		var intensity: float = 1.4 if _current_swing_is_charged else 1.0
		BloodVFX.spawn_burst(hit_point, hit_dir, intensity)


# =============================================================
# RMB — parry tap / block hold
# =============================================================

func _handle_parry_block_input() -> void:
	var just_pressed: bool = Input.is_action_just_pressed(parry_input_action)
	var just_released: bool = Input.is_action_just_released(parry_input_action)
	var is_pressed: bool = Input.is_action_pressed(parry_input_action)

	if just_pressed and _rmb_pressed_t == 0:
		_rmb_pressed_t = Time.get_ticks_usec()
		_block_active = false

	# Promote tap → block hold once threshold passes.
	if is_pressed and _rmb_pressed_t != 0 and not _block_active:
		var held_s: float = (Time.get_ticks_usec() - _rmb_pressed_t) / 1_000_000.0
		if held_s >= parry_tap_max_seconds:
			_block_active = true
			_engage_block()

	# Update block direction continuously while held (the player can re-aim
	# mid-block to track a new incoming attack).
	if _block_active:
		_update_block_direction()

	if just_released and _rmb_pressed_t != 0:
		var held_s: float = (Time.get_ticks_usec() - _rmb_pressed_t) / 1_000_000.0
		if held_s <= parry_tap_max_seconds and not _block_active:
			# Parry tap.
			_attempt_parry()
		else:
			# Was blocking. Release.
			_release_block()
		_rmb_pressed_t = 0


func _engage_block() -> void:
	# Default block direction = the most recent incoming attack direction.
	# If the player flicks the mouse before/while engaging, that flick
	# wins. With the new DIR_NONE sentinel we can cleanly distinguish
	# "no flick → default to last incoming" from "flicked deliberately."
	var sampled: int = _direction_sampler.sample()
	if sampled == _DirectionSampler.DIR_NONE:
		_block_direction = _last_incoming_attack_direction
	else:
		_block_direction = sampled
	_tween_shield_to_direction(_block_direction, parry_tap_max_seconds)


func _update_block_direction() -> void:
	# Re-sample each frame so the player can adjust mid-block (Bannerlord's
	# "active blocking" — the shield direction follows the mouse as the
	# player tracks incoming threats). DIR_NONE means "no flick happened
	# recently, keep the current block direction" — don't churn the
	# tween on stationary mouse.
	var sampled: int = _direction_sampler.sample()
	if sampled != _DirectionSampler.DIR_NONE and sampled != _block_direction:
		_block_direction = sampled
		_tween_shield_to_direction(_block_direction, 0.08)


func _release_block() -> void:
	_block_active = false
	_tween_shield_to_home(0.15)


func _attempt_parry() -> void:
	# Walk pending attacks. Successful parry = direction matches the parry
	# direction the player chose with their mouse flick.
	var parry_dir: int = _direction_sampler.sample()
	for id in _pending_attacks.keys():
		var rec: Dictionary = _pending_attacks[id]
		var attack_dir: int = int(rec["direction"])
		if attack_dir == parry_dir:
			var enemy: Node3D = rec.get("enemy") as Node3D
			if enemy != null and is_instance_valid(enemy):
				_succeed_parry(enemy, parry_dir)
				_pending_attacks.erase(id)
				return
	# No matching attack — parry failed visually (brief shield flash, no
	# stagger, no refund). The damage path is whatever the player would
	# have eaten anyway — we don't add extra damage here.
	# Failed parry breaks any in-flight chain.
	if parry_chain != null:
		parry_chain.break_chain()
	_tween_shield_pulse()


func _succeed_parry(enemy: Node3D, direction: int) -> void:
	# Update the chain BEFORE deciding refund, so chain count includes this
	# parry. should_refund_endurance() returns true once we're at chain ≥ 2.
	var new_chain: int = 1
	if parry_chain != null:
		new_chain = parry_chain.register_parry()
		# Echo chain count to DebugOverlay so the dev arena (where the
		# in-HUD chain label is hidden by _hide_all_chrome) can still
		# verify the mechanic visually via the F1 debug log.
		if get_node_or_null("/root/DebugOverlay"):
			DebugOverlay.log_action("PARRY dir=%d chain=x%d enemy=%s" % [direction, new_chain, enemy.name])
	# Refund: first parry returns parry_refund_endurance (cheap by design);
	# chained parries (≥ 2) refund the full block-equivalent cost so the
	# net endurance change is roughly zero — that's the chain reward.
	var refund: float = parry_refund_endurance
	if parry_chain != null and parry_chain.should_refund_endurance():
		# Refund the offhand's per-block cost to match the "free chain" feel.
		var offhand_data: Dictionary = _resolve_offhand_data()
		refund = float(offhand_data.get("endurance_per_block", 12.0))
	if _player != null and "endurance" in _player:
		_player.endurance = minf(_player.endurance + refund, _player.max_endurance)
	# Stagger the enemy. Enemy3D.stagger(duration) added in Phase 3.
	if enemy.has_method("stagger"):
		enemy.call("stagger", 1.5)
	_ignore_unused(new_chain)
	# Visual feedback — shield pulse + brief sword counter pose.
	_tween_shield_pulse()
	_tween_sword_riposte()
	# Phase 5: riposte sweep — fires a free counter-swing.
	_fire_riposte_sweep(direction)
	# SkillManager dispatch — perks like Spin-Parry hook here.
	if get_node_or_null("/root/SkillManager"):
		SkillManager.dispatch("on_parry", {
			"direction": direction,
			"enemy": enemy,
		})


func _fire_riposte_sweep(direction: int) -> void:
	# Counter-swing in the parry direction. Light damage, no extra EP cost.
	# Hits everything in cone (so a 1-vs-many parry can clear two more
	# enemies that were lined up in front of Roland).
	if _player == null:
		return
	var weapon_data: Dictionary = _resolve_weapon_data()
	var dmg: int = int(weapon_data.get("combat_damage", 15))
	var forward: Vector3 = -_player.transform.basis.z.normalized()
	var origin: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)
	var half_arc_cos: float = cos(deg_to_rad(swing_cone_degrees_narrow * 0.5))
	var hits: int = 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if hits >= max_targets_per_swing:
			break
		if enemy == null or not is_instance_valid(enemy):
			continue
		var e_node := enemy as Node3D
		if "_is_dead" in e_node and e_node._is_dead:
			continue
		var to_enemy: Vector3 = e_node.global_position - _player.global_position
		var dist: float = to_enemy.length()
		if dist > swing_cone_meters:
			continue
		if dist > 0.01:
			var to_dir: Vector3 = to_enemy.normalized()
			to_dir.y = 0.0
			if to_dir.length() < 0.0001:
				continue
			to_dir = to_dir.normalized()
			if forward.dot(to_dir) < half_arc_cos:
				continue
		# Hit.
		hits += 1
		if "last_hit_skill" in e_node:
			e_node.last_hit_skill = "sword"
		var hit_dir: Vector3 = (e_node.global_position - origin)
		hit_dir.y = 0.0
		if hit_dir.length() > 0.0001:
			hit_dir = hit_dir.normalized()
		else:
			hit_dir = forward
		if e_node.has_method("take_damage"):
			e_node.take_damage(dmg, hit_dir, e_node.global_position + Vector3(0.0, 1.0, 0.0))
		if get_node_or_null("/root/BloodVFX"):
			BloodVFX.spawn_burst(e_node.global_position + Vector3(0.0, 1.0, 0.0), hit_dir, 0.9)
	_ignore_unused(direction)


# Helper to keep direction in signature for future use (Phase 5 may use
# it to pick a counter-swing pose) without a "parameter never used" warning.
func _ignore_unused(_x) -> void:
	pass


func _prune_pending_attacks() -> void:
	var now_msec: int = Time.get_ticks_msec()
	var dead_keys: Array = []
	for id in _pending_attacks.keys():
		var rec: Dictionary = _pending_attacks[id]
		if int(rec["expires_t"]) <= now_msec:
			dead_keys.append(id)
	for id in dead_keys:
		_pending_attacks.erase(id)


# =============================================================
# SWORD + SHIELD POSE TWEENS
# =============================================================

# Direction-specific sword poses, applied via Tween on _melee_pivot.
# Local-space rotation Euler degrees per direction. Picked to read clearly
# as "where the sword went" at a glance — overhead = high & back, left =
# yawed left, right = yawed right, thrust = pushed forward + slight pitch.
#
# Keys are the integer values of MouseDirectionSampler.DIR_* constants:
#   0=OVERHEAD, 1=LEFT, 2=RIGHT, 3=THRUST.
# Numeric literals (not _DirectionSampler.DIR_*) so the Dictionary literal
# is fully resolvable at const-init time without depending on another
# preloaded script being parsed first.
# Two-stage swing animation:
#   WINDUP pose = where the sword sits during telegraphing (raised back,
#                 cocked to the side, drawn back near the body).
#   STRIKE pose = where the sword ends up at the end of the strike phase
#                 (chopped down, swept across, thrust forward). The
#                 visible motion BETWEEN windup → strike is what reads
#                 as "the swing" — a single tween that just goes to the
#                 strike pose without first going to the windup pose
#                 looks like a stiff teleport, not a swing.
const _SWORD_WINDUP_POSE_BY_DIRECTION := {
	# OVERHEAD: sword raised above and behind Roland's head, ready to chop down.
	0: { "rot": Vector3( 120.0,   0.0,   0.0), "pos": Vector3( 0.0,  0.5,  0.3) },
	# LEFT: sword cocked far on the right side, ready to sweep across to the left.
	1: { "rot": Vector3( -30.0, -55.0,  30.0), "pos": Vector3( 0.5,  0.3,  0.0) },
	# RIGHT: sword cocked far on the left side, ready to sweep across to the right.
	2: { "rot": Vector3( -30.0,  55.0, -30.0), "pos": Vector3(-0.5,  0.3,  0.0) },
	# THRUST: sword drawn back near the body (horizontal, tip forward), ready to push forward.
	3: { "rot": Vector3( -90.0,   0.0,   0.0), "pos": Vector3( 0.0,  0.1,  0.4) },
}

const _SWORD_STRIKE_POSE_BY_DIRECTION := {
	# OVERHEAD: sword chopped down and forward — tip points down/forward.
	0: { "rot": Vector3(-100.0,   0.0,   0.0), "pos": Vector3( 0.0, -0.4, -0.5) },
	# LEFT: sword sweep ended far on the left side — followed all the way through.
	1: { "rot": Vector3( -30.0,  90.0, -30.0), "pos": Vector3(-0.5,  0.0, -0.2) },
	# RIGHT: sword sweep ended far on the right side.
	2: { "rot": Vector3( -30.0, -90.0,  30.0), "pos": Vector3( 0.5,  0.0, -0.2) },
	# THRUST: sword thrust far forward (horizontal, tip pushed forward as far as it goes).
	3: { "rot": Vector3( -90.0,   0.0,   0.0), "pos": Vector3( 0.0,  0.0, -0.8) },
}

const _SHIELD_POSE_BY_DIRECTION := {
	0: { "rot": Vector3(  60.0, 0.0, 0.0),  "pos": Vector3(0.0, 0.6, -0.2) },     # OVERHEAD
	1: { "rot": Vector3(   0.0, -45.0, 0.0), "pos": Vector3(-0.4, 0.2, -0.2) },   # LEFT
	2: { "rot": Vector3(   0.0,  45.0, 0.0), "pos": Vector3(0.0, 0.2, -0.3) },    # RIGHT
	3: { "rot": Vector3( -45.0, 0.0, 0.0),  "pos": Vector3(0.0, -0.2, -0.3) },    # THRUST
}


func _tween_sword_to_windup(direction: int, duration: float) -> void:
	# Slow, telegraphing tween — moves the sword to its pre-strike pose
	# (raised, cocked, or drawn back). Easing OUT so the sword decelerates
	# into the held pose at the end of the windup.
	_tween_sword_to_pose(_SWORD_WINDUP_POSE_BY_DIRECTION, direction, duration, Tween.EASE_OUT)


func _tween_sword_to_strike(direction: int, duration: float) -> void:
	# Fast, snappy tween — moves the sword from its windup pose to its
	# follow-through pose. This is the visible STRIKE — the sword
	# sweeps across, chops down, or thrusts forward. Easing IN so the
	# sword accelerates through the strike (fastest at the contact moment).
	_tween_sword_to_pose(_SWORD_STRIKE_POSE_BY_DIRECTION, direction, duration, Tween.EASE_IN)


func _tween_sword_to_pose(pose_table: Dictionary, direction: int, duration: float, ease_mode: int) -> void:
	if _melee_pivot == null:
		return
	var pose: Dictionary = pose_table.get(direction, pose_table[2])  # 2 = DIR_RIGHT
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(ease_mode)
	var target_xform := _sword_home_transform
	target_xform.basis = Basis.from_euler(Vector3(
		deg_to_rad(pose["rot"].x),
		deg_to_rad(pose["rot"].y),
		deg_to_rad(pose["rot"].z),
	))
	target_xform.origin = _sword_home_transform.origin + pose["pos"]
	_swing_tween.tween_property(_melee_pivot, "transform", target_xform, duration)


func _tween_sword_to_home(duration: float) -> void:
	if _melee_pivot == null:
		return
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(_melee_pivot, "transform", _sword_home_transform, duration)


func _tween_sword_riposte() -> void:
	# Brief flourish — sword sweeps in a tight arc and returns. Distinct
	# from a normal swing pose so the player reads the counter visually.
	if _melee_pivot == null:
		return
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var counter_xform := _sword_home_transform
	counter_xform.basis = Basis.from_euler(Vector3(deg_to_rad(-30.0), deg_to_rad(-60.0), deg_to_rad(-15.0)))
	counter_xform.origin = _sword_home_transform.origin + Vector3(0.2, 0.1, -0.1)
	_swing_tween.tween_property(_melee_pivot, "transform", counter_xform, 0.12)
	_swing_tween.tween_property(_melee_pivot, "transform", _sword_home_transform, 0.18)


func _tween_shield_to_direction(direction: int, duration: float) -> void:
	if _shield_pivot == null:
		return
	var pose: Dictionary = _SHIELD_POSE_BY_DIRECTION.get(direction, _SHIELD_POSE_BY_DIRECTION[2])  # 2 = DIR_RIGHT
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var target_xform := _shield_home_transform
	target_xform.basis = Basis.from_euler(Vector3(
		deg_to_rad(pose["rot"].x),
		deg_to_rad(pose["rot"].y),
		deg_to_rad(pose["rot"].z),
	))
	target_xform.origin = _shield_home_transform.origin + pose["pos"]
	tween.tween_property(_shield_pivot, "transform", target_xform, duration)


func _tween_shield_to_home(duration: float) -> void:
	if _shield_pivot == null:
		return
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_shield_pivot, "transform", _shield_home_transform, duration)


func _tween_shield_pulse() -> void:
	# Quick scale-up / scale-down on the shield to read as a parry beat.
	if _shield_pivot == null:
		return
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var pulsed_xform := _shield_pivot.transform
	pulsed_xform.basis = pulsed_xform.basis.scaled(Vector3(1.25, 1.25, 1.25))
	tween.tween_property(_shield_pivot, "transform", pulsed_xform, 0.08)
	# Snap back to the position we were in (block or home).
	var restore_xform := _shield_home_transform if not _block_active else _shield_pivot.transform
	tween.tween_property(_shield_pivot, "transform", restore_xform, 0.12)


# =============================================================
# CAMERA + HYPERARMOR HELPERS
# =============================================================

func _apply_camera_pinch(t: float) -> void:
	if _player == null:
		return
	var rig := _player.get_node_or_null("CameraTarget/SpringArm3D")
	if rig != null and rig.has_method("set_charge_pinch"):
		rig.call("set_charge_pinch", t)


func _set_player_hyperarmor(active: bool) -> void:
	# Sets the hyperarmor flag on Player3D so damage during charge windup
	# doesn't interrupt the swing. Player3D reads this flag in its own
	# damage path (apply_damage when added). For Phase 1 this is just the
	# flag — no apply_damage caller exists yet beyond enemy contact, which
	# already only chunks health; combat behaviour is correct in v1 even
	# without the flag being read, but setting it now keeps Phase 2 honest.
	if _player != null and "_melee_hyperarmor" in _player:
		_player._melee_hyperarmor = active


func _resolve_weapon_data() -> Dictionary:
	if not get_node_or_null("/root/InventoryManager"):
		return {}
	var eid: String = InventoryManager.get_equipped("weapon")
	if eid == "" or not InventoryManager.ITEM_REGISTRY.has(eid):
		return {}
	return InventoryManager.ITEM_REGISTRY[eid]


func _resolve_offhand_data() -> Dictionary:
	if not get_node_or_null("/root/InventoryManager"):
		return {}
	var oid: String = InventoryManager.get_equipped("offhand")
	if oid == "" or not InventoryManager.ITEM_REGISTRY.has(oid):
		return {}
	return InventoryManager.ITEM_REGISTRY[oid]
