# Enemy3D — base class for all combat enemies (goblins, Ashfallen, wolves, bears).
#
# What this does in plain English:
#
#   This is the common chassis every enemy in the game inherits from. It
#   handles the things that don't change between enemy types — health
#   tracking, taking damage, dying, and the three-state awareness model
#   (idle / alert / combat) that drives detection cues like glowing eyes.
#
#   Subclasses (Goblin.gd, Ashfallen.gd, Wolf.gd, Bear.gd) extend this and
#   add the per-enemy specifics: movement style, attack patterns, sounds,
#   and visual flourishes like eye glow or armor variants.
#
# WHY a base class instead of one big switch statement:
#   Each enemy type has different AI rhythms (goblins swarm, wolves flank,
#   bears charge). Trying to express all of that in one Enemy script becomes
#   a tangle of "if type == ..." branches. A small base + per-enemy
#   subclasses keeps each enemy's behavior in one focused file.
#
# v1 SCOPE (Voxel Combat v1, 2026-05-10):
#   The state machine here only drives detection-state visuals. Combat AI
#   (attack tokens, group alerts, fleeing, swarms) is deferred to the
#   full combat pass per design/ENEMY_AI.md. v1 enemies just walk toward
#   the player in COMBAT state and deal contact damage on overlap.
#
# SCENE STRUCTURE expected:
#   EnemyNode (CharacterBody3D + this script's subclass)
#   ├── MeshInstance3D     ← visual (placeholder box or .glb model)
#   ├── CollisionShape3D   ← capsule for body collision
#   └── ChestSocket (Node3D, optional) ← attach point for embedded spears
#
# Subclasses may add hitbox Area3Ds, eye-material references, etc.

class_name Enemy3D
extends CharacterBody3D


# =============================================================
# DETECTION STATE MACHINE
# =============================================================

## Three awareness levels. Drives visual cues (eye glow intensity in
## Goblin.gd) and AI behavior (idle = stand still, combat = walk toward
## player). ALERT is a brief transition state — enemies linger here only
## long enough to play a "spotted you" reaction before going COMBAT.
enum State {
	IDLE,    ## No player nearby. Eyes off, no movement.
	ALERT,   ## Player detected but not yet engaged. Eyes dim, brief pause.
	COMBAT,  ## Engaging the player. Eyes full glow, walking toward player.
}

## Current awareness state. Subclasses change this via _set_state(); never
## write to it directly so the visual side-effects fire correctly.
var current_state: State = State.IDLE


# =============================================================
# HEALTH
# =============================================================

@export var max_health: int = 50
## Goblins die at 50. Charged spear (60 dmg) one-shots; light spear (30)
## wounds; second light hit kills. Subclasses override this for tougher
## enemies (Ashfallen, Bear). Single HP value in v1 — wound HP / regular
## HP split from design/COMBAT_DESIGN_3D.md is deferred.

var health: int

## Set true once die() has fired so multiple lethal hits in the same
## frame don't trigger the death cascade twice.
var _is_dead: bool = false


# =============================================================
# DETECTION RANGES
# =============================================================

@export var alert_range_meters: float = 10.0
## Distance at which IDLE enemies notice the player and transition to
## ALERT. Subclasses can override (wolves see further, bears hear better).

@export var combat_range_meters: float = 5.0
## Distance at which ALERT enemies escalate to COMBAT and start moving.
## Should be smaller than alert_range_meters so there's a visible "they
## see you" beat before they actually rush.


# =============================================================
# CONTACT DAMAGE (v1 placeholder for real attack animations)
# =============================================================

@export var contact_damage: int = 8
## Damage dealt to the player on physical overlap. v1 has no swing
## animations — just touch = damage with a short cooldown. Replaced by
## proper attack patterns when ENEMY_AI.md is fully wired.

@export var contact_damage_cooldown_seconds: float = 1.0
## How long after dealing contact damage before this enemy can deal it
## again. Prevents one frame of overlap from chunking the player to zero.

@export var corpse_lifetime_seconds: float = 300.0
## How long the corpse stays in the scene after death before being
## auto-freed. 5 minutes — long enough that the player can return to
## a kill site after exploring elsewhere and still loot any embedded
## items / ammo; short enough that overnight sessions don't
## accumulate hundreds of corpses. Dev-arena Reset bypasses this and
## frees all corpses immediately.

@export var corpse_interact_radius_meters: float = 2.0
## How close the player must be to press E and loot a corpse. The
## interact area is spawned in die() and reads this value on creation.

var _contact_cooldown_remaining: float = 0.0

# Corpse-interaction state. Set up in die() once the enemy becomes a
# lootable body. Not used while alive.
var _corpse_interact_area: Area3D
var _player_in_corpse_range: bool = false
var _corpse_looted: bool = false  # one-shot guard so E doesn't loot twice


# =============================================================
# SIGNALS
# =============================================================

## Fires every time this enemy takes non-lethal damage. Args: amount of
## damage, world position of the hit. Subclasses can listen for visual
## reactions (flinch, blood splatter trigger, etc).
signal damaged(amount: int, hit_point: Vector3)

## Fires when this enemy dies. Arg: the damage amount at the killing
## blow. ThrowableSpear listens to know whether to embed in the gib
## cluster, and Enemy3D.die() itself uses it to pick topple vs. explosion.
signal died(damage_at_kill: int)

## Set by damage sources (sword swing, spear hit, bow shot) before they
## call take_damage(). CombatXPRouter reads this to attribute the
## damaged/died events to the right combat skill. Empty string means
## "unknown source"; the router falls back to its current_weapon_skill.
var last_hit_skill: String = ""


# =============================================================
# REFERENCES
# =============================================================

var _player: Node3D
## Cached reference to the player. Found on _ready() by group lookup.


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	# Cache the player reference. Player3D.tscn root joins the "player"
	# group on instance, per the existing project convention.
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D
	else:
		push_warning("[Enemy3D] No node in 'player' group found — detection will not work.")


func _physics_process(delta: float) -> void:
	if _is_dead:
		# Dead enemies poll for corpse interaction (E to loot) instead
		# of running movement / detection logic. The interact area
		# tracks player overlap via signals; we only check the input
		# action here. Guarded by _corpse_looted so multiple E presses
		# don't double-loot.
		if _player_in_corpse_range and not _corpse_looted:
			if Input.is_action_just_pressed("interact"):
				_corpse_looted = true
				_loot_corpse()
		return

	# Tick down the contact-damage cooldown.
	if _contact_cooldown_remaining > 0.0:
		_contact_cooldown_remaining -= delta

	# Update detection state based on distance to player.
	_update_detection_state()

	# Apply gravity so enemies stay grounded on the dev arena floor.
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	# Subclasses do their movement in _enemy_physics_step. We call it
	# here so the base class can wrap it with shared logic later
	# (stagger, knockback, etc.) without subclasses having to remember
	# to call super().
	_enemy_physics_step(delta)

	move_and_slide()

	# v1 contact damage: if the player is overlapping us and our
	# cooldown has expired, deal damage.
	if current_state == State.COMBAT and _contact_cooldown_remaining <= 0.0:
		_check_contact_damage()


# Subclasses override this to provide movement behavior. Default is
# stationary — Goblin overrides to walk toward the player.
func _enemy_physics_step(_delta: float) -> void:
	pass


# =============================================================
# DETECTION
# =============================================================

func _update_detection_state() -> void:
	if _player == null:
		return
	var d: float = global_position.distance_to(_player.global_position)
	if d <= combat_range_meters:
		_set_state(State.COMBAT)
	elif d <= alert_range_meters:
		# Don't downgrade COMBAT to ALERT just because the player walked
		# slightly out — once committed, enemies stay engaged. Only
		# enter ALERT when coming up from IDLE.
		if current_state == State.IDLE:
			_set_state(State.ALERT)
	else:
		# Out of range — drop back to idle. (Real AI would have a
		# search-and-return behavior; v1 just toggles cleanly.)
		_set_state(State.IDLE)


## Change state and notify subclasses via _on_state_changed so they can
## update visuals (eye glow, posture, etc).
func _set_state(new_state: State) -> void:
	if new_state == current_state:
		return
	var old: State = current_state
	current_state = new_state
	_on_state_changed(old, new_state)


# Subclasses override this for visual reactions.
func _on_state_changed(_old: State, _new: State) -> void:
	pass


# =============================================================
# CONTACT DAMAGE
# =============================================================

func _check_contact_damage() -> void:
	if _player == null:
		return
	# Cheap proximity check — if the player is within 1.2 m we count it
	# as contact. (Capsule-vs-capsule physics overlap would be more
	# accurate but we don't need that precision in v1.)
	if global_position.distance_to(_player.global_position) > 1.2:
		return
	if not _player.has_method("apply_damage"):
		# Player3D doesn't have apply_damage yet — log once and skip.
		if get_node_or_null("/root/DebugOverlay"):
			DebugOverlay.log_action("Enemy contact dmg skipped — player has no apply_damage()")
		_contact_cooldown_remaining = contact_damage_cooldown_seconds
		return
	_player.call("apply_damage", contact_damage)
	_contact_cooldown_remaining = contact_damage_cooldown_seconds


# =============================================================
# DAMAGE
# =============================================================

## Public entry point for taking damage. Called by ThrowableSpear, by
## PowderCharge AOE, by the debug F8 key, and eventually by melee
## hitboxes. hit_dir is the direction the damage came from (for blood
## spurt direction); hit_point is the world position of the impact.
func take_damage(amount: int, hit_dir: Vector3, hit_point: Vector3) -> void:
	if _is_dead:
		return
	health -= amount
	if health <= 0:
		# die() reads damage_at_kill to pick topple vs. explosion. We
		# pass the raw amount of the killing blow so a 60-dmg charged
		# spear gets the full explosion treatment regardless of what
		# the goblin had left.
		die(amount, hit_dir, hit_point)
		return
	# Non-lethal hit — fire signal so Goblin.gd can play a flinch,
	# trigger Layer A blood burst, start Layer B bleed, etc.
	damaged.emit(amount, hit_point)
	_on_damaged(amount, hit_dir, hit_point)


# Subclasses override this to react to damage (Goblin: spawn blood
# burst, start bleed). Base class does nothing on its own.
func _on_damaged(_amount: int, _hit_dir: Vector3, _hit_point: Vector3) -> void:
	pass


# =============================================================
# OVERKILL — gib explosion + time-slow + camera kick (Phase 5)
# =============================================================

const OVERKILL_DAMAGE_THRESHOLD: int = 80
## At/above this single-hit damage on a lethal blow, the enemy gibs
## (visual hidden, GibChunks spawn radially) and the global time-slow
## + camera kick fire. Below the threshold, the enemy topples normally.
## 80 lines up with the charged-spear damage ceiling (60 charged + a
## few perks) so charged kills satisfyingly explode and tap kills
## quietly topple.

const TIME_SLOW_SCALE: float = 0.05
const TIME_SLOW_DURATION_S: float = 0.15
const GIB_CHUNK_COUNT: int = 12
const GIB_IMPULSE_BASE: float = 0.9
const GIB_IMPULSE_RANDOM: float = 0.5
const GIB_VERTICAL_BOOST: float = 0.4

const _GibChunk := preload("res://scripts/GibChunk.gd")


## Public entry point for death. Called automatically by take_damage()
## when health reaches zero, but exposed publicly so debug tools can
## kill instantly without going through health math.
##
## CORPSE LIFETIME: dead enemies stay in the scene as a corpse (with
## _is_dead = true preventing further damage / movement / detection)
## until corpse_lifetime_seconds elapses, then queue_free. Subclasses
## decide what the corpse looks like in _on_died (lying body, gib
## cluster, dissolve, etc.). The dev arena's Reset Enemies command
## bypasses this timer and queue_frees all corpses immediately.
func die(damage_at_kill: int, hit_dir: Vector3 = Vector3.FORWARD, hit_point: Vector3 = Vector3.ZERO) -> void:
	if _is_dead:
		return
	_is_dead = true
	# Stop any pending physics so the corpse doesn't keep walking.
	velocity = Vector3.ZERO
	# Phase 5 — overkill lethal hits fire the global time-slow + camera
	# kick BEFORE _on_died so the subclass's gib spawn lands during
	# the slow window (looks like the explosion crystallises in slow-mo
	# at the moment of impact). The brief 0.15 s pause is well below
	# combat reaction time so it reads as punch, not pause.
	if damage_at_kill >= OVERKILL_DAMAGE_THRESHOLD:
		_trigger_overkill_feedback()
	# Fire signal first so listeners (ThrowableSpear) can react before
	# the visual swap happens.
	died.emit(damage_at_kill)
	# Subclasses do the corpse visual (lay down, change color, spawn
	# cluster, etc.).
	_on_died(damage_at_kill, hit_dir, hit_point)
	# Spawn the corpse-interaction area so the player can walk up and
	# press E to loot. Done AFTER _on_died so the area's transform
	# can be aligned to the corpse's lying-down position if subclasses
	# moved things around — but for v1 the area sits at the goblin
	# root's origin which is also the corpse's center.
	_spawn_corpse_interact_area()
	# Auto-free after a long delay so dead enemies don't accumulate
	# forever in long sessions, but stay visible long enough that the
	# player can see the consequence of their kill (and return to
	# loot). Dev arena Reset bypasses this timer.
	var timer := get_tree().create_timer(corpse_lifetime_seconds)
	timer.timeout.connect(queue_free)


# =============================================================
# GIB EXPLOSION HELPER  (Phase 5)
# =============================================================
# Subclasses call this from _on_died on overkill. Spawns
# GIB_CHUNK_COUNT GibChunks at `world_pos` with radial outward impulse
# from `hit_point` toward each chunk, plus a small upward boost so the
# explosion has visible loft.
#
# Returns the array of spawned GibChunks so the subclass can reparent
# embedded items (spears) to them.
func _spawn_gib_explosion(world_pos: Vector3, hit_point: Vector3, hit_dir: Vector3,
		skin_color: Color, core_color: Color, count: int = GIB_CHUNK_COUNT) -> Array:
	var spawned: Array = []
	var parent: Node = get_parent()
	if parent == null:
		return spawned
	# Direction of the incoming hit, used as the explosion's primary
	# bias so chunks fly more strongly away from the kill blow.
	var hit_axis: Vector3 = hit_dir
	if hit_axis.length_squared() < 0.001:
		hit_axis = Vector3(0, 0, -1)
	hit_axis = hit_axis.normalized()
	for i in range(count):
		# Spawn slightly above / around the body centre so chunks don't
		# all originate from a single point.
		var spawn_offset := Vector3(
			randf_range(-0.2, 0.2),
			randf_range(0.5, 1.2),
			randf_range(-0.2, 0.2))
		var spawn_pos: Vector3 = world_pos + spawn_offset
		# Outward radial direction from the hit point, plus the
		# hit-axis bias (50/50 weighted), normalised then vertically
		# boosted so chunks arc up before falling.
		var radial: Vector3 = (spawn_pos - hit_point)
		if radial.length_squared() < 0.001:
			radial = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		radial = radial.normalized()
		var dir: Vector3 = (radial + hit_axis * 0.5).normalized()
		dir.y = maxf(dir.y, 0.0) + GIB_VERTICAL_BOOST
		dir = dir.normalized()
		var speed: float = GIB_IMPULSE_BASE + randf() * GIB_IMPULSE_RANDOM
		# 50/50 skin (outer body colour) vs core (red interior).
		var color: Color = skin_color if randf() < 0.5 else core_color
		var chunk: RigidBody3D = _GibChunk.new()
		chunk.name = "GibChunk_%d" % i
		parent.add_child(chunk)
		chunk.global_position = spawn_pos
		chunk.call("configure", color, dir * speed)
		spawned.append(chunk)
	return spawned


# Fire the global "lethal punch" feedback — brief time-slow + camera
# kick. Called once per overkill kill from die(). Restoration of
# Engine.time_scale uses a `process_mode = PROCESS` SceneTreeTimer so
# the unscaled-real-time elapsed is what we measure (the duration is
# in scaled seconds; a 0.15 s scaled duration at 0.05× time-scale =
# 3 s of real time, perceived as a momentary stutter).
#
# Idempotent across rapid kills: each call kills any in-flight restore
# tween and starts fresh.
func _trigger_overkill_feedback() -> void:
	# Engine.time_scale is global — read original, push the slow, queue
	# the restore.
	var original_scale: float = Engine.time_scale
	# Skip if we're already in a slow window (a second lethal during
	# the first slow would otherwise stack and never restore).
	if original_scale <= TIME_SLOW_SCALE + 0.001:
		return
	Engine.time_scale = TIME_SLOW_SCALE
	# Restore via a SceneTreeTimer. ignore_time_scale=true so the timer
	# measures REAL seconds, not scaled — without it the restore would
	# fire after TIME_SLOW_DURATION_S / TIME_SLOW_SCALE = 3 s of real
	# time, which is way too long.
	var restore_timer := get_tree().create_timer(TIME_SLOW_DURATION_S, true, false, true)
	restore_timer.timeout.connect(func() -> void:
		Engine.time_scale = original_scale)
	# Camera kick — find the CameraRig via group; safe-no-op if absent.
	var cam_rig: Node = get_tree().get_first_node_in_group("camera_rig")
	if cam_rig != null and cam_rig.has_method("kick"):
		cam_rig.call("kick", 0.08, 0.18)


# =============================================================
# CORPSE INTERACTION — Area3D + E-press loot
# =============================================================

func _spawn_corpse_interact_area() -> void:
	# Sphere area centered on the corpse's current position. Keeps
	# the loot prompt available wherever the body fell, including any
	# knockback offset from the kill blow.
	var area := Area3D.new()
	var coll := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = corpse_interact_radius_meters
	coll.shape = shape
	area.add_child(coll)
	# Collision mask 1 = the default physics layer where Player3D
	# lives. Keep collision_layer = 0 so this area only DETECTS
	# bodies, never participates in physics interactions.
	area.collision_layer = 0
	area.collision_mask = 1
	add_child(area)
	area.body_entered.connect(_on_corpse_interact_entered)
	area.body_exited.connect(_on_corpse_interact_exited)
	_corpse_interact_area = area


func _on_corpse_interact_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_in_corpse_range = true


func _on_corpse_interact_exited(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_in_corpse_range = false


## Override in subclasses to define what loot the corpse yields.
## Base implementation is a no-op (no items to give). Goblin
## overrides this to return any embedded throwables (spears) plus
## any future inventory drops.
func _loot_corpse() -> void:
	pass


# Subclasses override to do the actual death visuals (cluster spawn,
# mesh hide, sound). Base class does nothing — the timer above will
# free us regardless.
func _on_died(_damage_at_kill: int, _hit_dir: Vector3, _hit_point: Vector3) -> void:
	pass
