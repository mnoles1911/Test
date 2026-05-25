# Goblin.gd — the v1 enemy. Lanky, green, glowing eyes, gibs spectacularly.
#
# What this does in plain English:
#
#   Extends Enemy3D to give a goblin its specific behaviors:
#     - When IDLE, stand still
#     - When ALERT (player spotted), eyes go from off to dim
#     - When COMBAT (player close enough to engage), eyes blaze full
#       green and the goblin walks toward the player
#     - When damaged, flinch + fire blood VFX (wired in Phase 4)
#     - When killed, hide the body and spawn a falling-voxel cluster
#       (wired in Phase 5) — topple for normal kills, explosion for
#       overkill (≥80 damage)
#
# v1 SCOPE:
#   No swing animation, no attack token system, no group alerting, no
#   fleeing. Goblin walks at the player and deals contact damage on
#   touch. The full attack-pool / token / swarm rules from
#   design/ENEMY_AI.md land in a later combat pass.
#
# SCENE STRUCTURE expected (Goblin.tscn):
#   Goblin (CharacterBody3D + this script)
#   ├── Visual (MeshInstance3D — green box placeholder until .glb lands)
#   ├── CollisionShape3D (capsule, 0.4 m radius, 1.8 m tall)
#   ├── ChestSocket (Node3D, Y=+1.2 — spear embed point)
#   └── EyeGlow (MeshInstance3D — small green box at head height with
#         an emissive StandardMaterial3D the script tweaks per state)

class_name Goblin
extends Enemy3D


# =============================================================
# MOVEMENT
# =============================================================

@export var walk_speed_meters_per_second: float = 2.8
## Slower than Roland (~4.5 m/s walk) so the player can outpace a
## goblin to set up a charged spear throw. Tweak after combat
## playtests — too slow feels like training dummies; too fast feels
## like the player can never breathe.


# =============================================================
# EYE GLOW STATE TABLE
# =============================================================
# Three intensities driven by Enemy3D.current_state. The values are
# emission_energy_multiplier passed to a StandardMaterial3D.
# 0.0 = invisible, 6.0 = strongly self-lit (overpowers ambient).

const _EYE_GLOW_BY_STATE: Dictionary = {
	State.IDLE:   0.0,
	State.ALERT:  2.0,
	State.COMBAT: 6.0,
}


# =============================================================
# NODE REFERENCES
# =============================================================

@onready var _visual: MeshInstance3D = $Visual
@onready var _eye_glow: MeshInstance3D = get_node_or_null("EyeGlow")
@onready var _chest_socket: Node3D = get_node_or_null("ChestSocket")
## Cached reference to the eye mesh's material. We read this once and
## then poke its emission_energy_multiplier directly each state change
## — cheaper than re-fetching every frame.
var _eye_material: StandardMaterial3D

# Composed Phase-3 attack state machine (directional windup + strike +
# unblockable telegraph). Picks an attack per-tick from the pool below;
# forwards the committed_attack signal to MeleeHandler / LockOnManager
# via Enemy3D.committed_attack (declared on the base).
var _attack_pool: EnemyAttackPool

# Goblin attack pool — weights per design/ENEMY_AI.md:
#   50% jab / thrust (1-target, fast)
#   35% swing (left or right, telegraphed)
#   15% leap (unblockable; player must dodge — Phase 1 has no dodge so
#         the unblockable just deals damage if not avoided positionally)
const _ATTACK_POOL_CONFIG: Array = [
	{ "id": "jab",          "weight": 0.50, "is_unblockable": false, "direction": 3, "windup": 0.45, "strike_window": 0.10, "recovery": 0.40 },  # 3 = DIR_THRUST
	{ "id": "swing_left",   "weight": 0.18, "is_unblockable": false, "direction": 1, "windup": 0.60, "strike_window": 0.10, "recovery": 0.45 },  # 1 = DIR_LEFT
	{ "id": "swing_right",  "weight": 0.17, "is_unblockable": false, "direction": 2, "windup": 0.60, "strike_window": 0.10, "recovery": 0.45 },  # 2 = DIR_RIGHT
	{ "id": "leap",         "weight": 0.15, "is_unblockable": true,  "direction": 0, "windup": 0.75, "strike_window": 0.12, "recovery": 0.55 },  # 0 = DIR_OVERHEAD (leap-down chop)
]


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	super._ready()
	# Configure the eye material if the EyeGlow node was authored.
	# (We tolerate the EyeGlow being missing so the placeholder Goblin
	# scene can ship without it — the goblin still walks and dies.)
	if _eye_glow != null:
		var mat := _eye_glow.get_active_material(0)
		if mat is StandardMaterial3D:
			_eye_material = mat
		else:
			# Build one inline so the placeholder works even if the
			# .tscn forgot to set up an emissive material.
			_eye_material = StandardMaterial3D.new()
			_eye_material.albedo_color = Color(0.0, 1.0, 0.25, 1.0)
			_eye_material.emission_enabled = true
			_eye_material.emission = Color(0.0, 1.0, 0.25, 1.0)
			_eye_material.emission_energy_multiplier = 0.0
			_eye_glow.material_override = _eye_material
	_apply_eye_glow_for_state()

	# Build the directional attack pool (Phase 3 — directional combat).
	_attack_pool = EnemyAttackPool.new()
	add_child(_attack_pool)
	_attack_pool.attack_pool = _ATTACK_POOL_CONFIG.duplicate(true)
	_attack_pool.strike_range_meters = 1.6
	_attack_pool.attack_cooldown_seconds = 0.8
	_attack_pool.initialize(self, _visual)
	# Forward the host's committed_attack signal to MeleeHandler so it can
	# open the parry window. The signal is declared on Enemy3D (base) and
	# emitted by EnemyAttackPool via self.committed_attack.emit(...).
	committed_attack.connect(_on_attack_pool_committed)


# =============================================================
# MOVEMENT (override of Enemy3D._enemy_physics_step)
# =============================================================

func _enemy_physics_step(delta: float) -> void:
	# Drive the directional attack state machine first — it can lock us
	# out (STAGGERED) or freeze movement (WINDUP/STRIKE/RECOVERY).
	if _attack_pool != null:
		_attack_pool.tick(delta)

	# Only move during COMBAT. IDLE / ALERT goblins stand still.
	if current_state != State.COMBAT:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if _player == null:
		return
	# Stagger / mid-swing: clamp movement so the telegraph is readable
	# and the player can step in for a punish.
	var move_scale: float = 1.0
	if _attack_pool != null:
		move_scale = _attack_pool.velocity_scale()
	if move_scale <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		# Still face the player so the eyes track even while staggered.
		_face_player()
		return
	# Walk toward the player on the XZ plane only; Y is gravity.
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()
	# Stop a full body-width away (capsule radius 0.4 m each, so 0.8 m
	# is exactly touching). 1.7 m gives Roland comfortable space to
	# swing without the goblin's CharacterBody3D physics-shoving him
	# (designer test 2026-05-25 — enemies pushed the player around).
	# The goblin's sword reach (strike_range_meters = 1.6 m in
	# EnemyAttackPool) still covers this distance, so swings still
	# land in the cone.
	if distance < 1.7:
		velocity.x = 0.0
		velocity.z = 0.0
		_face_player()
		return
	var dir: Vector3 = to_player / distance
	velocity.x = dir.x * walk_speed_meters_per_second * move_scale
	velocity.z = dir.z * walk_speed_meters_per_second * move_scale
	_face_player()


func _face_player() -> void:
	if _player == null:
		return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return
	var look_target: Vector3 = global_position + to_player.normalized()
	look_at(look_target, Vector3.UP)


func _on_attack_pool_committed(direction: int, time_to_impact: float, is_unblockable: bool) -> void:
	# Bridge from base-class signal → MeleeHandler so the parry window
	# opens with the right direction + duration. LockOnManager subscribes
	# to its own copy of the signal directly via the base class.
	if _player == null:
		return
	var handler: Node = _player.get_node_or_null("MeleeHandler")
	if handler != null and handler.has_method("notify_enemy_committed"):
		handler.call("notify_enemy_committed", self, direction, time_to_impact)
	# Brief one-frame log so the dev arena shows what's happening even
	# before HUDDirectionArrows lands in Phase 6.
	if get_node_or_null("/root/DebugOverlay"):
		var tag := "UNBLOCKABLE" if is_unblockable else "parryable"
		DebugOverlay.log_action("Goblin %s commits attack: dir=%d (%s) tti=%.2fs" % [name, direction, tag, time_to_impact])


# =============================================================
# STATE → VISUALS
# =============================================================

func _on_state_changed(_old: State, new_state: State) -> void:
	_apply_eye_glow_for_state()
	# Brief log for v1 debugging; remove once combat AI lands.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Goblin %s → %s" % [name, State.keys()[new_state]])


func _apply_eye_glow_for_state() -> void:
	if _eye_material == null:
		return
	var energy: float = float(_EYE_GLOW_BY_STATE.get(current_state, 0.0))
	_eye_material.emission_energy_multiplier = energy


# =============================================================
# DAMAGE + DEATH (Phase 4 + Phase 5 wire blood + cluster here)
# =============================================================

func _on_damaged(amount: int, _hit_dir: Vector3, _hit_point: Vector3) -> void:
	# ThrowableSpear already fires the Layer A burst at the hit point
	# (it has the precise impact location + direction; we'd be guessing
	# from over here). Goblin is responsible for the Layer B wound
	# drip — start it on the first non-lethal hit. start_drip is a
	# no-op if a drip is already attached, so it's safe to call on
	# every wound event.
	if get_node_or_null("/root/BloodVFX"):
		BloodVFX.start_drip(self, "ChestSocket")
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Goblin %s wounded (%d) → HP %d" % [name, amount, health])


func _on_died(damage_at_kill: int, _hit_dir: Vector3, _hit_point: Vector3) -> void:
	# Phase 5 will branch on damage_at_kill (topple vs. explosion),
	# spawn FallingVoxelCluster, etc. v1 placeholder behavior:
	#   - Lay the visual flat (rotate forward 90°) so it reads as a
	#     fallen body rather than vanishing
	#   - Rotate the chest socket alongside the visual so any
	#     embedded spears pivot with the body and end up pointing
	#     up out of the corpse's back (face-down body)
	#   - Darken the color and kill the eye glow so it looks dead
	#   - Stop the wound drip
	#   - Drop a Layer C blood pool at the kill site
	# Enemy3D.die() handles the eventual queue_free via
	# corpse_lifetime_seconds (default 5 minutes) and spawns the
	# corpse-interaction Area3D for E-press loot.
	if _visual != null:
		# Rotate -90° on X (faceplant forward), then sink so the
		# now-horizontal box rests on the ground rather than floating
		# at original chest height. Box was 0.5×1.8×0.4 with origin
		# at Y=0.9; after the X-rotation its vertical extent becomes
		# 0.4, half-height 0.2, so origin Y=0.2 puts the bottom on
		# the ground.
		_visual.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_visual.position = Vector3(0.0, 0.2, 0.0)
		# Darken to dead-grey-green so the corpse reads visually
		# distinct from living goblins still in the area.
		var corpse_mat: StandardMaterial3D = StandardMaterial3D.new()
		corpse_mat.albedo_color = Color(0.18, 0.22, 0.14, 1.0)
		_visual.material_override = corpse_mat
	if _chest_socket != null:
		# Rotate the chest socket the same -90° X so any spears
		# parented inside it pivot with the body. The spear's local
		# transform (relative to ChestSocket) doesn't change — only
		# its global transform follows the rotation. A spear that
		# was sticking horizontally through the chest now points
		# vertically up from the corpse's back, like an arrow buried
		# in a fallen body.
		#
		# Drop the socket to the chest height of the lying-down
		# body (~0.5 m) so the spear ends up at the right place
		# spatially.
		_chest_socket.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_chest_socket.position = Vector3(0.0, 0.5, 0.0)
	if _eye_glow != null:
		_eye_glow.visible = false
	if get_node_or_null("/root/BloodVFX"):
		BloodVFX.stop_drip(self)
		# Pool grows larger and faster on overkill — a charged-spear
		# kill (60+ dmg) leaves more visible mess than a finishing tap.
		# Dialed up 2026-05-13 for the "aggressive blood" goal: pools
		# are now 3-4.5 m across, growing to full size in 1.5-2.5 s
		# so the kill instantly reads as gory rather than a slow stain.
		var size: float = 4.5 if damage_at_kill >= 50 else 3.0
		var grow: float = 1.5 if damage_at_kill >= 50 else 2.5
		BloodVFX.spawn_pool(global_position, size, grow)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Goblin %s killed (%d dmg)" % [name, damage_at_kill])


## Override of Enemy3D._loot_corpse. Walks the chest socket's child
## list, returns any embedded ThrowableSpear instances to the
## player's inventory, and frees them. Future: also deposit any
## non-spear items the goblin was carrying (none in v1).
##
## Called by Enemy3D._physics_process when the player is in the
## corpse interaction area and presses the "interact" action (E).
## The base class guards against double-loot via _corpse_looted.
func _loot_corpse() -> void:
	if _chest_socket == null:
		return
	var spears_recovered: int = 0
	# Iterate over a copy because we're going to free children
	# during the loop.
	var children := _chest_socket.get_children()
	for child in children:
		if child is ThrowableSpear:
			child.queue_free()
			spears_recovered += 1
	if spears_recovered > 0 and get_node_or_null("/root/InventoryManager"):
		InventoryManager.add_item("spear", spears_recovered)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Looted goblin %s — %d spear(s) recovered" % [name, spears_recovered])
