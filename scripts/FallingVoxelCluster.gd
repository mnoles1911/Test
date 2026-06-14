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

const VOXEL_SIZE_M: float = 1.0 / 10.0
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
# Vector3i (ABSOLUTE world voxel-grid coords) → int (packed RGBA32).
# Frozen at spawn. Used for mesh build AND re-deposit.
#
# IMPORTANT: keys are absolute (e.g. Vector3i(523, 47, 1109)), NOT
# cluster-local. This is the coordinate system VoxelTool returned
# them in, and it's what compute_centre_offset / build_cluster_mesh
# expect — they handle the local-shift internally by subtracting
# the centroid.

var _centre_offset_m: Vector3 = Vector3.ZERO
# The cluster's centroid in ABSOLUTE world meters, as returned by
# VoxelClusterBuilder.compute_centre_offset(). Subtracted from each
# absolute voxel position (in world meters) to map ABSOLUTE → CLUSTER-
# LOCAL coords with the centre of mass at the rigid body's local
# origin. Used both at mesh-build time and during re-deposit (we
# need the same offset to round-trip absolute → local → world after
# the cluster has rotated).

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

var _gravity_scale_mat: float = 1.0
# Per-cluster gravity scale, aggregated from constituent materials in
# VoxelGravityManager._handle_cluster. 1.0 = standard fall speed
# (matches Player3D.GRAVITY = 20 m/s²). > 1.0 = heavier, falls faster.
# Multiplied INTO the rigid body's gravity_scale property at
# configure time.

var _damage_multiplier_mat: float = 1.0
# Per-cluster damage multiplier, aggregated from constituent materials
# (max across the cluster — the deadliest material wins). Multiplied
# INTO the impact-damage formula in _on_body_entered.

# --- Buoyancy (voxel-physics PR 7) ---
var _density_mat: float = 2.5
# Average density-relative-to-water across constituent voxels (set in
# configure). < 1 = the cluster floats; >= 1 sinks at reduced speed.
var _base_gravity_scale: float = 1.0
# gravity_scale as computed at configure time (dry). Restored when the
# cluster leaves water.
var _in_water: bool = false
var _water_poll_frame: int = 0
const WATER_POLL_EVERY_N_FRAMES: int = 6
# is_position_in_water costs a couple of voxel reads; every 6 physics
# frames (10 Hz) is plenty for entering/leaving water.
var _float_still_seconds: float = 0.0
const FLOAT_SETTLE_SPEED: float = 0.2     # |v_y| below this counts as "still"
const FLOAT_SETTLE_SECONDS: float = 3.0   # still this long -> re-deposit (raft)


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
	gravity_scale_material: float = 1.0,
	damage_multiplier_material: float = 1.0,
	density_material: float = 2.5,
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
	# gravity_scale_material: aggregated gravity_scale across the
	#                    cluster's constituent materials (average).
	#                    1.0 = matches Player3D.GRAVITY exactly.
	# damage_multiplier_material: aggregated damage_multiplier (max
	#                    across constituents). Applied to crush
	#                    damage. 1.0 = neutral.

	_voxel_snapshot = voxel_snapshot
	_spawn_world_y = global_position.y
	_gravity_scale_mat = gravity_scale_material
	_damage_multiplier_mat = damage_multiplier_material
	_density_mat = maxf(0.1, density_material)

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

	# Apply custom gravity via gravity_scale so the project's default
	# gravity (likely 9.8) doesn't override our 20 m/s², AND so the
	# cluster's material(s) modulate the fall speed:
	#
	#   gravity_scale = (GRAVITY * _gravity_scale_mat) / project_default
	#
	# Example: project default 9.8, GRAVITY = 20, material avg = 1.5
	# (heavy stone-iron-ore mix) → gravity_scale = (20 * 1.5) / 9.8 = 3.06.
	# A pure-stone cluster with material gravity_scale 1.0 falls at
	# the standard 20 m/s²; a heavy ore mix falls noticeably faster.
	custom_integrator = false  # we still want default linear/angular damping
	gravity_scale = (GRAVITY * _gravity_scale_mat) / _project_gravity_magnitude()
	_base_gravity_scale = gravity_scale

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

	# --- Buoyancy (PR 7): poll water every 6 physics frames. ---
	_water_poll_frame += 1
	if _water_poll_frame >= WATER_POLL_EVERY_N_FRAMES:
		_water_poll_frame = 0
		var wfm := get_node_or_null("/root/WaterFlowManager")
		var now_in_water: bool = wfm != null and wfm.is_position_in_water(global_position)
		if now_in_water != _in_water:
			_in_water = now_in_water
			if _in_water:
				# Archimedes, voxel edition: effective gravity scales by
				# (1 - 1/density). Density 2.5 stone -> sinks at 60%
				# speed; density 0.7 log -> NEGATIVE (floats up); the
				# heavy damping sells the through-water drag.
				gravity_scale = _base_gravity_scale * (1.0 - 1.0 / _density_mat)
				linear_damp = 2.0
				_float_still_seconds = 0.0
			else:
				gravity_scale = _base_gravity_scale
				linear_damp = 0.0

	# Floater settle: a buoyant cluster bobbing at the surface never
	# sleeps on terrain, so the normal sleep path can't end it. Once
	# it has been vertically still for a few seconds, re-deposit it in
	# place — a felled log becomes a little raft of log voxels at the
	# waterline.
	if _in_water and _density_mat < 1.0:
		if absf(linear_velocity.y) < FLOAT_SETTLE_SPEED:
			_float_still_seconds += delta
			if _float_still_seconds >= FLOAT_SETTLE_SECONDS:
				print("[FallingVoxelCluster] floated still for %.1fs — re-deposit raft at %s" % [
					_float_still_seconds, global_position])
				_settle_and_redeposit()
				return
		else:
			_float_still_seconds = 0.0
		# While floating, HOLD the generic timeout — drifting on a
		# current is healthy behaviour, not a stuck body.
		return

	# Failsafe timeout (dry clusters only — floaters handled above).
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
	# Per-cluster damage multiplier (set in configure from the
	# material aggregation). Stone clusters multiply by ~1.2;
	# dirt/grass by ~0.7; future iron-ore clusters by ~2.0.
	var damage: float = float(voxel_count) * fall_height * DAMAGE_PER_VOXEL_PER_METER * _damage_multiplier_mat
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
		# Snapshot keys are ABSOLUTE world voxel-grid positions (not
		# cluster-local). Same convention used at mesh-build time.
		var v_abs_grid: Vector3i = v_pos_v
		# Match the mesh build: subtract _centre_offset_m (which IS
		# the absolute centroid in world meters) to map this voxel's
		# absolute position into cluster-local meters orbiting the
		# rigid body's CoM. Then add half-voxel so the write targets
		# the voxel CENTRE rather than its corner.
		var v_local_m: Vector3 = (Vector3(v_abs_grid) * VOXEL_SIZE_M) - _centre_offset_m
		var v_local_centre_m: Vector3 = v_local_m + Vector3.ONE * (VOXEL_SIZE_M * 0.5)
		# Apply the rigid body's current transform (carries any
		# rotation + translation accumulated during the fall) to get
		# the world-space landing position. After a 90° tip, voxels
		# end up rotated relative to their original orientation —
		# this is what produces the "tree lying on its side" look.
		var v_world: Vector3 = global_transform * v_local_centre_m
		writes.append({
			"pos": v_world,
			"value": int(_voxel_snapshot[v_abs_grid]),
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
