extends RigidBody3D
class_name ThrowableSpear
# ThrowableSpear — a thrown spear that sticks on impact and is retrievable.
#
# What this does in plain English:
#
#   When the player throws a spear, ThrowableHandler.gd spawns one of
#   these in front of Roland with a forward velocity. The spear flies
#   through the air, orienting itself along its travel direction (so
#   the shaft points where it's going), and on impact:
#
#     ENEMY HIT:
#       - Calls enemy.take_damage(combat_damage, hit_dir, hit_point).
#       - Freezes the rigidbody and reparents to the enemy's
#         ChestSocket node so the shaft visibly protrudes.
#       - The spear rides with the enemy through any topple or gib
#         explosion that follows (Enemy3D.die spawns the cluster, and
#         the cluster scoops up the spear automatically because it's
#         a child of the enemy at the moment the cluster forms).
#
#     TERRAIN HIT:
#       - Stops, embeds 1–3 voxels deep so the head buries.
#       - Becomes auto-pickup: when Roland walks within
#         PICKUP_RADIUS_M the spear despawns and adds 1× spear back
#         to inventory. Mirrors the VoxelDrop.gd pattern so the
#         pickup feel is consistent with mining drops.
#
#   Lifetime safety net: if the spear somehow never collides
#   (thrown into the void / past collision range), it auto-despawns
#   after LIFETIME_SECONDS_NO_IMPACT to prevent memory leaks. No
#   detonation, no inventory return — just silent cleanup.
#
# Phase 2 SCOPE:
#   Damage and velocity arrive pre-set on the rigidbody from
#   ThrowableHandler (which reads them from InventoryManager.
#   ITEM_REGISTRY["spear"]). Phase 3 wraps the input side with
#   charge tracking that scales those values; this script doesn't
#   need to know about that — it just uses whatever arrives.


# =============================================================
# CONFIGURATION
# =============================================================

@export var combat_damage: int = 30
## Damage dealt on enemy impact. ThrowableHandler overwrites this on
## spawn from InventoryManager.ITEM_REGISTRY["spear"]["combat_damage"]
## (Phase 3 will further scale this by charge level). The @export
## default is the light-throw value.

@export var pickup_radius_m: float = 1.5
## How close Roland must be for the embedded spear to auto-collect.
## Matches VoxelDrop.gd convention — comfortable walk-by collection.

@export var pickup_lockout_seconds: float = 0.5
## Cooldown after impact during which auto-pickup is disabled.
## Stops the spear from being collected mid-flight if Roland chases
## a goblin and the spear lands at his feet.

@export var lifetime_seconds_no_impact: float = 8.0
## Cleanup timer for spears that never hit anything (off a cliff,
## past collision range). Silent despawn on expiry — no inventory
## return.

@export var embed_depth_meters: float = 0.2
## How far the spear embeds along its travel direction on terrain
## hits. Visually anchors the shaft into the ground so it doesn't
## just float at the surface contact point.


# =============================================================
# RUNTIME STATE
# =============================================================

var _impacted: bool = false
## Single-use guard. body_entered can fire multiple times before
## the freeze + reparent settles; this prevents double-impact
## (which would otherwise double-damage the enemy).

var _embedded_in_terrain: bool = false
## True once the spear has stopped on terrain and is awaiting
## auto-pickup. Drives the proximity check in _physics_process.

var _pickup_lockout_remaining: float = 0.0
var _no_impact_remaining: float

var _player: Node3D
## Cached on first need. We don't grab it in _ready because the
## spear may spawn before the player tree settles in unusual cases.


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_no_impact_remaining = lifetime_seconds_no_impact
	contact_monitor = true
	max_contacts_reported = 4
	# Detonate-equivalent for the spear: stick to whatever it hits.
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _impacted:
		# Embedded in terrain — handle pickup.
		if _embedded_in_terrain:
			_tick_pickup(delta)
		return

	# In flight — orient the mesh so the shaft points along travel.
	# (Visual only; the capsule collider is symmetric so its rotation
	# doesn't affect physics.)
	var v: Vector3 = linear_velocity
	if v.length_squared() > 0.01:
		# Spear's local "forward" axis is +Y (the shaft runs up the
		# Y axis in the .glb / placeholder mesh). Rotate so +Y points
		# along the velocity direction.
		var forward: Vector3 = v.normalized()
		var up_ref: Vector3 = Vector3.UP if absf(forward.y) < 0.95 else Vector3.FORWARD
		# Renamed from `basis` to avoid shadowing Node3D.basis (which
		# raised SHADOWED_VARIABLE_BASE_CLASS in the parser warnings).
		var aim_basis: Basis = Basis.looking_at(-forward, up_ref)
		# looking_at rotates -Z to face the target. Since the spear's
		# forward is +Y, rotate the basis 90° around its local X to
		# remap -Z → +Y.
		aim_basis = aim_basis.rotated(aim_basis.x, deg_to_rad(90.0))
		global_transform.basis = aim_basis

	# No-impact safety net.
	_no_impact_remaining -= delta
	if _no_impact_remaining <= 0.0:
		queue_free()


# =============================================================
# IMPACT
# =============================================================

func _on_body_entered(body: Node) -> void:
	if _impacted:
		return
	# Ignore the thrower. The spear's 2 m capsule, when oriented along
	# its travel vector, often has its rear half overlapping Roland's
	# collision capsule on spawn — body_entered fires the same frame
	# the spear leaves his hand, freezing it in mid-air. Filtering by
	# group is cheaper and more robust than spawn offsets, and it also
	# protects against corner cases like the spear arcing back through
	# the player on a high-angle throw.
	if body != null and body.is_in_group("player"):
		return
	_impacted = true

	# Lock the spear's current orientation as the "stuck" pose. The
	# shaft is already pointing along the travel vector from
	# _physics_process; freezing here preserves that.
	var travel_dir: Vector3 = linear_velocity.normalized() if linear_velocity.length() > 0.01 else -global_transform.basis.z

	# Branch: enemy vs. terrain.
	if body != null and body.is_in_group("enemy"):
		_impact_enemy(body, travel_dir)
	else:
		_impact_terrain(travel_dir)


func _impact_enemy(enemy: Node, travel_dir: Vector3) -> void:
	# Hit point: the spear's current position is approximately at
	# the contact, since body_entered fires the same frame as collision.
	var hit_point: Vector3 = global_position
	if enemy.has_method("take_damage"):
		enemy.call("take_damage", combat_damage, travel_dir, hit_point)

	# Layer A blood burst at the impact point, sprayed along the
	# spear's travel direction. Intensity scales with damage so a
	# charged-spear killshot sprays more than a light wound. Safe to
	# fire synchronously because BloodVFX doesn't touch our physics.
	if get_node_or_null("/root/BloodVFX"):
		var intensity: float = clampf(float(combat_damage) / 30.0, 0.5, 2.0)
		BloodVFX.spawn_burst(hit_point, travel_dir, intensity)

	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Spear hit %s for %d dmg" % [String(enemy.name), combat_damage])

	# Defer the physics state changes (freeze, collision layers,
	# reparent) to the next idle frame. We're inside a body_entered
	# physics callback right now; mutating CollisionObject state or
	# moving a physics node through reparent() during a physics
	# callback throws "Removing a CollisionObject node during a
	# physics callback is not allowed" and corrupts internal physics
	# state. call_deferred runs _attach_to_enemy_socket after the
	# physics step completes, where these mutations are safe.
	call_deferred("_attach_to_enemy_socket", enemy, travel_dir)


func _attach_to_enemy_socket(enemy: Node, travel_dir: Vector3) -> void:
	# Deferred handler — runs on the next idle frame after the
	# body_entered physics callback completes. Both the spear and the
	# enemy may have been freed in between (rare race: enemy died on
	# the impact frame and was queue_free'd before this fires); guard
	# both.
	if not is_instance_valid(self) or not is_instance_valid(enemy):
		return

	# Stop the rigidbody and disable its collision layers so it
	# doesn't keep interacting with the world while embedded.
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 0
	collision_mask = 0

	var socket: Node3D = enemy.get_node_or_null("ChestSocket") as Node3D
	if socket != null:
		# Reparent to the socket so we ride with the enemy through
		# any death animation or gib cluster spawn.
		var current_global := global_transform
		reparent(socket, true)
		# Reparent preserves the world transform when keep_global_transform
		# is true; offset slightly forward along travel to embed visually.
		global_transform.origin = current_global.origin + travel_dir * embed_depth_meters


func _impact_terrain(travel_dir: Vector3) -> void:
	# Dust puff outward from the surface — we don't have the true
	# surface normal here (body_entered doesn't carry contact details),
	# so use the spear's reverse travel direction as a "best guess
	# outward" axis. This is visually correct for any reasonable
	# impact angle except glancing skims along a wall. Safe to fire
	# synchronously because BloodVFX doesn't touch our physics.
	if get_node_or_null("/root/BloodVFX"):
		BloodVFX.spawn_dust(global_position, -travel_dir)

	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Spear embedded in terrain at %s" % global_position)

	# Same deferred-physics rule as _impact_enemy: freeze, collision
	# layer changes, and the embed-position nudge all need to happen
	# OUTSIDE the body_entered physics callback, otherwise Godot
	# throws and corrupts internal state.
	call_deferred("_settle_in_terrain", travel_dir)


func _settle_in_terrain(travel_dir: Vector3) -> void:
	# Deferred handler for terrain impact. self may have been freed
	# between the impact and this call (unlikely but safe).
	if not is_instance_valid(self):
		return
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 0
	collision_mask = 0
	# Nudge the mesh forward by embed_depth so the head buries in.
	global_transform.origin += travel_dir * embed_depth_meters
	_embedded_in_terrain = true
	_pickup_lockout_remaining = pickup_lockout_seconds


# =============================================================
# PICKUP (terrain-embedded only)
# =============================================================

func _tick_pickup(delta: float) -> void:
	if _pickup_lockout_remaining > 0.0:
		_pickup_lockout_remaining -= delta
		return
	if _player == null:
		_player = _find_player()
		if _player == null:
			return
	if global_position.distance_to(_player.global_position) > pickup_radius_m:
		return
	# Within pickup radius — collect.
	if get_node_or_null("/root/InventoryManager"):
		InventoryManager.add_item("spear", 1)
		if get_node_or_null("/root/DebugOverlay"):
			DebugOverlay.log_action("Spear retrieved")
	queue_free()


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return null
	return players[0] as Node3D
