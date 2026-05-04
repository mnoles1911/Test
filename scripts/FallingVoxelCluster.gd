extends RigidBody3D
# FallingVoxelCluster — one airborne chunk of voxels mid-fall.
#
# Spawned by VoxelGravityManager whenever flood-fill identifies a
# group of voxels that have lost their support after a player edit.
# The cluster's voxels are first carved from the terrain, then this
# RigidBody3D takes over: gravity (matched to Player3D.GRAVITY = 20
# m/s² via custom integrator), tipping for tall clusters, damage on
# impact, and re-deposit as terrain when it comes to rest.
#
# Lifecycle:
#   1. VoxelGravityManager carves the cluster's voxels from terrain
#      and instances this scene at the cluster's centroid.
#   2. Calls configure(snapshot, edit_origin) once to hand over the
#      voxel data and the world position of the edit that triggered
#      the fall (used for the directional tip impulse on rod-like
#      clusters — felled trees fall toward the cut).
#   3. Cluster falls, possibly tipping, possibly hitting things along
#      the way (each impact applies damage to bodies that have a
#      `health` property — the player today, enemies later).
#   4. When the rigid body sleeps OR the failsafe timeout fires, the
#      cluster's voxels are re-deposited as terrain edits via
#      VoxelEditManager.queue_set_voxels_bulk(). Voxels rejected by
#      NoEditZone (e.g. cluster fell into a settlement) are dropped.
#   5. queue_free()s itself.
#
# Reference: design/3D_VOXEL_MIGRATION.md → "Voxel Gravity"


# =============================================================
# CONFIGURATION (passed in by VoxelGravityManager.configure())
# =============================================================

const VOXEL_SIZE_M: float = 1.0 / 6.0
# Edge length of one voxel in meters. Mirrors VoxelClusterBuilder
# constant. Hardcoded here too so this file is parsable in isolation.

const GRAVITY: float = 20.0
# Must match Player3D.GRAVITY exactly so falling voxels accelerate at
# the same rate the player does. If you re-tune one, re-tune the other.

const SETTLE_TIMEOUT_SECONDS: float = 10.0
# Failsafe — if the cluster is still in motion after this long it gets
# force-settled at its current position (or queue_freed if it fell off
# the world). Without this, a cluster that hits an unbounded slope or
# slides into water with non-zero damping could spin forever.

const FALL_OFF_WORLD_Y: float = -200.0
# Below this Y the cluster is silently destroyed without re-depositing.
# At our scale terrain bottoms out well above this; if the cluster
# somehow tunnelled through or fell off the edge of generation, just
# drop it.

const DAMAGE_MIN_FALL_HEIGHT_M: float = 1.5
# Below this fall height, the cluster does no damage. Stops a 1-voxel
# pebble that drops 20 cm from killing anything; preserves the
# expectation that "one little block fell on me" is harmless.

const DAMAGE_PER_VOXEL_PER_METER: float = 0.05
# Damage = voxel_count * fall_height_m * this. Tuning:
#   Tiny fall (8 voxels, 2 m): 8 * 2 * 0.05 = 0.8 hp — trivial
#   Medium fall (200 voxels, 5 m): 200 * 5 * 0.05 = 50 hp — heavy
#   Big fall (1000 voxels, 10 m): 1000 * 10 * 0.05 = 500 hp — lethal
# Player has 100 max HP by default — a substantial cluster from any
# real height is dangerous. That's the desired feel: don't stand
# under what you're mining.

const ROD_ASPECT_THRESHOLD: float = 3.0
# Cluster height / max horizontal extent. Above this ratio the cluster
# is treated as "rod-like" (tree trunk, pillar) and gets a directional
# tip impulse so it falls toward the cut. Below, it's "blob-like" and
# drops mostly straight.

const TREE_FALL_IMPULSE_NEWTONS: float = 8.0
# Magnitude of the lateral impulse applied at the top of rod-like
# clusters, pushing away from the edit origin. Combined with custom
# centre-of-mass + the small equilibrium nudge below, this reliably
# tips a vertical column over instead of letting it stand on its end.

const EQUILIBRIUM_BREAK_RAD_S: float = 0.05
# Tiny random angular velocity applied to every cluster on spawn.
# Without this, a perfectly-vertical column whose CoM lies exactly
# over its support footprint would balance forever in physics. Real
# columns lean — this nudges them.


# =============================================================
# RUNTIME STATE — populated by configure()
# =============================================================

var _voxel_snapshot: Dictionary = {}
# Vector3i (cluster-local voxel-grid) → int (packed RGBA32). Frozen
# at spawn. Used for re-deposit.

var _centre_offset_m: Vector3 = Vector3.ZERO
# The (cluster-local-meters) offset between the AABB-min corner and
# the centre of mass. Mesh vertices are placed at
# (voxel_pos * VOXEL_SIZE_M) - _centre_offset_m so the cluster
# pivots around its CoM. We need this to invert the math during
# re-deposit (going from "world position of a cluster vertex" back
# to "voxel-grid position to write to").

var _spawn_world_y: float = 0.0
# Y-coordinate where the cluster started falling. fall_height =
# _spawn_world_y - global_position.y at impact time. Drives damage.

var _seconds_alive: float = 0.0
# Failsafe timeout counter.

var _settled: bool = false
# Single-use guard. sleeping_state_changed can fire multiple times
# during a long settle; this stops us from re-depositing twice.

var _bodies_already_damaged: Dictionary = {}
# instance_id → true. Each body takes damage at most once per cluster
# fall, even if the cluster grinds along its surface for several frames.


# =============================================================
# NODE REFERENCES (assigned in _ready from the scene tree)
# =============================================================

var _mesh_inst: MeshInstance3D = null
var _collision_shape: CollisionShape3D = null


# =============================================================
# PUBLIC API
# =============================================================

func configure(
	voxel_snapshot: Dictionary,
	edit_origin_world: Vector3,
) -> void:
	# Called by VoxelGravityManager exactly once, immediately after
	# the cluster scene is instanced and added to the world. After
	# this returns the cluster is fully alive and physics takes over.
	#
	# voxel_snapshot: cluster-local voxel positions → packed RGBA.
	#                 Cluster-local means: the keys are the original
	#                 voxel-grid coords (NOT shifted to start at
	#                 origin). The mesh-build math handles the shift.
	# edit_origin_world: world-space position of the edit that caused
	#                    the cluster to lose support. Used for
	#                    rod-like clusters (trees) so they tip away
	#                    from the cut, not in a random direction.

	_voxel_snapshot = voxel_snapshot
	_spawn_world_y = global_position.y

	if _voxel_snapshot.is_empty():
		# Defensive — shouldn't happen, but a zero-voxel cluster has
		# no mesh and no business existing.
		queue_free()
		return

	# Build mesh + AABB + CoM offset.
	_centre_offset_m = VoxelClusterBuilder.compute_centre_offset(_voxel_snapshot)
	var mesh: ArrayMesh = VoxelClusterBuilder.build_cluster_mesh(_voxel_snapshot, _centre_offset_m)
	var aabb: AABB = VoxelClusterBuilder.compute_local_aabb(_voxel_snapshot)

	if _mesh_inst == null or _collision_shape == null:
		_resolve_node_refs()

	_mesh_inst.mesh = mesh
	_mesh_inst.material_override = VoxelClusterBuilder.get_shared_material()

	var box := BoxShape3D.new()
	# AABB.size is the full cluster extent. BoxShape3D.size is full
	# extent too (NOT half-extent), so we can pass it straight in.
	# Minimum 1 voxel so single-voxel clusters still have a shape.
	box.size = Vector3(
		maxf(aabb.size.x, VOXEL_SIZE_M),
		maxf(aabb.size.y, VOXEL_SIZE_M),
		maxf(aabb.size.z, VOXEL_SIZE_M),
	)
	_collision_shape.shape = box
	# Position the collision shape at the AABB centre IN LOCAL SPACE.
	# For uniform clusters this is the local origin (centroid is at
	# the geometric centre). For L-shaped clusters, the centroid is
	# offset from the box centre, so the BoxShape3D must move with it
	# or collision will be wrong.
	var box_centre_local: Vector3 = aabb.position + aabb.size * 0.5
	_collision_shape.position = box_centre_local

	# Custom centre of mass — voxel-weighted centroid is at the local
	# origin by construction, so CoM offset is Vector3.ZERO. Setting
	# CUSTOM (rather than relying on the AUTO box-centre default)
	# means an L-shaped overhang's CoM lives at its true centroid,
	# not the geometric centre of its box — so it tumbles correctly.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO

	# Apply custom gravity via custom_integrator so the project's
	# default gravity (likely 9.8) doesn't override our 20 m/s².
	custom_integrator = false  # we still want default linear/angular damping
	gravity_scale = GRAVITY / _project_gravity_magnitude()
	# Example: project default 9.8, we want 20 → gravity_scale = 2.04.

	# Damping — minimal linear (clusters fall like rocks, not feathers),
	# modest angular (so a tipped cluster doesn't spin chaotically once
	# it lands).
	linear_damp = 0.0
	angular_damp = 0.5

	# Continuous collision detection — a 4096-voxel cluster falling
	# 10 m hits ~14 m/s, which can tunnel through a 1-voxel-thick
	# floor without CCD. We use the DISCRETE → CONTINUOUS switch.
	continuous_cd = true

	# Hook the body_entered signal for impact damage.
	contact_monitor = true
	max_contacts_reported = 8
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not sleeping_state_changed.is_connected(_on_sleeping_state_changed):
		sleeping_state_changed.connect(_on_sleeping_state_changed)

	# --- Initial conditions: tipping ---
	# Always nudge — breaks the perfectly-vertical equilibrium case.
	# X and Z only; spinning around the vertical axis looks weird and
	# real falling rocks/trees don't do it.
	angular_velocity = Vector3(
		randf_range(-EQUILIBRIUM_BREAK_RAD_S, EQUILIBRIUM_BREAK_RAD_S),
		0.0,
		randf_range(-EQUILIBRIUM_BREAK_RAD_S, EQUILIBRIUM_BREAK_RAD_S),
	)

	# Rod-like cluster (tree trunk, pillar)?  height >> width → tip away
	# from the cut. The impulse is applied at the top of the cluster so
	# it produces torque around the base, exactly like an axe blow.
	var max_horizontal: float = maxf(aabb.size.x, aabb.size.z)
	if max_horizontal > 0.0:
		var aspect: float = aabb.size.y / max_horizontal
		if aspect >= ROD_ASPECT_THRESHOLD:
			var fall_dir: Vector3 = global_position - edit_origin_world
			fall_dir.y = 0.0
			if fall_dir.length_squared() < 0.0001:
				# Edit was directly under the cluster — pick a random
				# horizontal direction so the tree still falls somewhere.
				fall_dir = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
			fall_dir = fall_dir.normalized()
			# Apply impulse near the top of the cluster (40% above CoM).
			var top_offset: Vector3 = Vector3(0, aabb.size.y * 0.4, 0)
			var impulse: Vector3 = fall_dir * TREE_FALL_IMPULSE_NEWTONS
			apply_impulse(impulse, top_offset)


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_resolve_node_refs()


func _resolve_node_refs() -> void:
	# Find the MeshInstance3D and CollisionShape3D children. The scene
	# defines them with fixed names; this lookup is one-time per
	# cluster spawn so the cost is negligible.
	if _mesh_inst == null:
		_mesh_inst = get_node_or_null("Mesh") as MeshInstance3D
	if _collision_shape == null:
		_collision_shape = get_node_or_null("Collision") as CollisionShape3D


func _physics_process(delta: float) -> void:
	if _settled:
		return
	_seconds_alive += delta

	# Fell off the world?
	if global_position.y < FALL_OFF_WORLD_Y:
		print("[FallingVoxelCluster] fell off world at %s — discarding" % global_position)
		_settled = true
		queue_free()
		return

	# Failsafe timeout.
	if _seconds_alive >= SETTLE_TIMEOUT_SECONDS:
		print("[FallingVoxelCluster] settle timeout (%.1fs) — force re-deposit at %s" % [
			_seconds_alive, global_position
		])
		_settle_and_redeposit()


# =============================================================
# IMPACT
# =============================================================

func _on_body_entered(body: Node) -> void:
	if _settled:
		return
	# Damage anything with a `health` property (Player3D today, enemies
	# later). Skip the terrain itself — VoxelLodTerrain will fire
	# body_entered too but it has no health and there's nothing to
	# damage. Skip duplicates within a single fall.
	if body == null or body == self:
		return
	var id: int = body.get_instance_id()
	if _bodies_already_damaged.has(id):
		return
	if not ("health" in body):
		return  # not a damageable body — terrain, props, etc.

	var fall_height: float = maxf(0.0, _spawn_world_y - global_position.y)
	if fall_height < DAMAGE_MIN_FALL_HEIGHT_M:
		return
	var voxel_count: int = _voxel_snapshot.size()
	var damage: float = float(voxel_count) * fall_height * DAMAGE_PER_VOXEL_PER_METER
	if damage <= 0.0:
		return
	# Apply damage. Player3D exposes `health` directly (no take_damage
	# method), so we read-modify-write. Enemies that grow a take_damage
	# method later will be picked up by has_method preference.
	if body.has_method("take_damage"):
		body.take_damage(damage)
	else:
		body.health = maxf(float(body.health) - damage, 0.0)
	_bodies_already_damaged[id] = true
	print("[FallingVoxelCluster] crushed '%s' for %.1f damage (voxels=%d, fall=%.1fm)" % [
		body.name, damage, voxel_count, fall_height
	])


# =============================================================
# SETTLING & RE-DEPOSIT
# =============================================================

func _on_sleeping_state_changed() -> void:
	# Triggered when the rigid body's `sleeping` property flips. We
	# only act on the transition INTO sleep (when the cluster has
	# come to rest).
	if _settled:
		return
	if sleeping:
		_settle_and_redeposit()


func _settle_and_redeposit() -> void:
	_settled = true

	# Build the bulk write list. Each snapshot voxel's local-grid
	# position has to be transformed:
	#   1. local-grid → cluster-local meters (multiply by voxel size,
	#      then subtract _centre_offset_m so we're CoM-relative)
	#   2. cluster-local meters → world meters (apply current
	#      RigidBody3D transform, which carries rotation + translation
	#      from the entire fall + landing)
	#   3. world meters → snap to nearest voxel-grid position
	# That snapped grid position becomes the world position handed to
	# VoxelEditManager.queue_set_voxels_bulk.
	#
	# The snap step is approximate — a fallen tree lying at 73° will
	# discretise into stair-stepped voxels, not a smooth diagonal log.
	# Acceptable for chunky-cube terrain; the alternative (rotating
	# the voxel grid itself) is way more work for marginal payoff.

	var writes: Array = []
	for v_pos_v in _voxel_snapshot.keys():
		var v_local_grid: Vector3i = v_pos_v
		# Match the mesh build: subtract _centre_offset_m (which IS
		# centroid_world from spawn time) so cluster-local coords
		# orbit the rigid body's CoM. Then add half-voxel so the write
		# targets the voxel CENTRE rather than its corner.
		var v_local_m: Vector3 = (Vector3(v_local_grid) * VOXEL_SIZE_M) - _centre_offset_m
		var v_local_centre_m: Vector3 = v_local_m + Vector3.ONE * (VOXEL_SIZE_M * 0.5)
		var v_world: Vector3 = global_transform * v_local_centre_m
		writes.append({
			"pos": v_world,
			"value": int(_voxel_snapshot[v_local_grid]),
		})

	if get_node_or_null("/root/VoxelEditManager"):
		# Bulk write — VoxelEditManager checks NoEditZone per-voxel and
		# silently drops any rejected (cluster fell into a settlement).
		var ok: bool = VoxelEditManager.queue_set_voxels_bulk(
			writes, "cluster_redeposit_n%d" % writes.size()
		)
		if not ok:
			push_warning("[FallingVoxelCluster] bulk re-deposit rejected (queue full)")
	else:
		push_error("[FallingVoxelCluster] VoxelEditManager autoload missing")

	# Notify the manager so it can update its active-cluster count.
	if get_node_or_null("/root/VoxelGravityManager"):
		VoxelGravityManager.notify_cluster_settled(self, global_position)

	queue_free()


# =============================================================
# HELPERS
# =============================================================

func _project_gravity_magnitude() -> float:
	# Read the project's default 3D gravity so we can scale ours to
	# the desired absolute value via gravity_scale. If the setting is
	# missing for some reason, fall back to Godot's stock 9.8.
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if g <= 0.0:
		return 9.8
	return g
