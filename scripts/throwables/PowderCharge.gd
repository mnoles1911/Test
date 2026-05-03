extends RigidBody3D
# PowderCharge — a thrown explosive that removes voxels in its blast
# radius and damages enemies caught nearby.
#
# What this does in plain English:
#
# When the player presses the throw input (currently quick_slot_1
# bound to "1"), ThrowableHandler.gd spawns one of these in front
# of Roland with a forward velocity. The charge flies through the
# air, hits something, and detonates after either:
#
#   - any solid impact (body_entered fires), OR
#   - a 3-second fuse expires (whichever comes first)
#
# Detonation:
#   1. Calls VoxelEditManager.queue_edit_sphere(pos, radius, AIR=0)
#      — removes voxels in a sphere. Inside a NoEditZone the call
#      returns false; voxel removal is silently skipped but the
#      visual + (future) damage still happen.
#   2. Spawns a placeholder particle burst (TODO: real GPUParticles3D
#      preset once VFX assets land).
#   3. queue_free()s itself.
#
# Combat damage to nearby enemies is a TODO — no enemies exist yet.
# When EnemyAI lands, this script will iterate over enemies in
# the radius and call enemy.take_damage(combat_damage).
#
# Reference: design/ITEM_LIBRARY.md → Section 4 → "Explosives"
# Reference: design/3D_VOXEL_MIGRATION.md → "Player Edit Verbs"


# =============================================================
# CONFIGURATION
# =============================================================

@export var aoe_radius_meters: float = 2.0
# Sphere radius of the voxel-removal blast and damage area. The
# Powder Charge default is 2m; Sapper's Bundle uses ~4m. Set per
# instance from the inventory item's voxel_aoe_radius field.

@export var combat_damage: int = 40
# Damage applied to enemies in the AOE on detonation. Hooked up
# when EnemyAI exists; currently unused but stored so the value
# survives the throw → detonate flow.

@export var fuse_seconds: float = 2.0
# Fuse delay if the charge doesn't impact-detonate. Counts down
# from the moment the charge is spawned. 2 seconds is short
# enough that charges thrown from a high point detonate before
# falling out of Zylann's near-LOD collision range (~30-60m
# from the player). Bumped down from 3s after charges were
# observed falling to Y=-60+ during the fuse and detonating in
# unloaded territory below the world.


# =============================================================
# RUNTIME STATE
# =============================================================

var _detonated: bool = false
# Single-use guard. body_entered can fire multiple times before
# queue_free completes; this prevents double-detonation.

var _fuse_remaining: float


func _ready() -> void:
	_fuse_remaining = fuse_seconds
	# Connect the impact signal so we detonate on collision. The
	# signal is fired once per body that enters our area.
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_fuse_remaining -= delta
	if _fuse_remaining <= 0.0:
		_log("Fuse expired mid-air at %s — detonating" % global_position)
		_detonate()


func _on_body_entered(body: Node) -> void:
	# Impact detonation. Any solid body counts: terrain (voxel
	# collision), the ground, walls.
	if _detonated:
		return
	_log("Impact with '%s' at %s" % [body.name if body != null else "?", global_position])
	_detonate()


func _detonate() -> void:
	_detonated = true

	# --- Pick a detonation point that actually hits terrain ---
	# Three cases to handle:
	#   1. Fuse expires while charge is above terrain (mid-air
	#      detonation in normal flight) — raycast DOWN to find
	#      the surface below.
	#   2. Charge fell past Zylann's near-LOD collision and is
	#      now BELOW the terrain mass (thrown from a high point,
	#      lands far from the player) — raycast UP finds the
	#      underside; carve there to leave a tunnel/cavity.
	#   3. No terrain in either direction (thrown into a void or
	#      far past Zylann's collision range entirely) — abort
	#      the carve so we don't queue a useless edit at empty
	#      coordinates that would never produce a visible crater.
	var detonate_pos: Vector3 = _find_nearest_terrain(global_position, 200.0)
	if detonate_pos == Vector3.INF:
		_log("No terrain found above or below charge at %s — aborting (fell into void / past collision LOD)" % global_position)
		queue_free()
		return
	if detonate_pos != global_position:
		_log("Snapped detonation from %s to nearest terrain %s" % [global_position, detonate_pos])

	# --- Voxel removal in the AOE ---
	if get_node_or_null("/root/VoxelEditManager"):
		# Offset the sphere center a bit BELOW the surface so the
		# carve bites into the terrain rather than skimming it.
		# 0.4m down from the hit point puts the sphere center
		# inside the solid voxels, producing a visible crater.
		var carve_center: Vector3 = detonate_pos + Vector3(0, -0.4, 0)
		var accepted: bool = VoxelEditManager.queue_edit_sphere(
			carve_center, aoe_radius_meters, 0
		)
		if not accepted:
			_log("Detonation inside NoEditZone — voxels preserved.")
		else:
			_log("Carve queued: center=%s radius=%.1fm" % [carve_center, aoe_radius_meters])
	else:
		_log("VoxelEditManager autoload missing — no terrain edit applied")

	# --- Action log entry for the in-game console ---
	# TODO: spawn a GPUParticles3D preset once explosion VFX
	# assets exist. For now the only feedback is the voxel
	# crater + (future) audio.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("BOOM at (%.1f, %.1f, %.1f) radius %.1fm" % [
			detonate_pos.x, detonate_pos.y, detonate_pos.z, aoe_radius_meters
		])

	# --- Crafting/Demolition sub-skill XP ---
	# Per design/SKILLS_AND_PROGRESSION.md — explosive_detonated = 15.
	if get_node_or_null("/root/GameState"):
		GameState.add_skill_xp(GameState.SkillDomain.CRAFTING, "demolition", 15)

	# --- Damage enemies in the AOE ---
	# TODO: iterate over enemy nodes within aoe_radius_meters and
	# call take_damage(combat_damage). Blocked on EnemyAI not
	# existing yet.

	# Remove the charge from the world. queue_free defers actual
	# removal to the end of the frame so any in-flight signal
	# handling completes safely.
	queue_free()


func _find_nearest_terrain(from_pos: Vector3, max_distance: float) -> Vector3:
	# Try DOWN first (charge floating above terrain): this is the
	# normal case. If a ray straight down hits something, return
	# the hit point.
	#
	# If the down-ray finds nothing, try UP — the charge probably
	# fell past Zylann's collision and is now below the terrain
	# mass. The up-ray hits the underside of the lowest voxel,
	# which is close enough to the surface that a 2m carve from
	# there cuts into the visible terrain.
	#
	# If neither direction finds terrain, return Vector3.INF as a
	# sentinel — the caller should abort the carve rather than
	# queue an edit at coordinates with nothing around them.
	var space_state := get_world_3d().direct_space_state

	var down_params := PhysicsRayQueryParameters3D.create(
		from_pos, from_pos + Vector3(0, -max_distance, 0)
	)
	down_params.exclude = [get_rid()]
	var hit_down: Dictionary = space_state.intersect_ray(down_params)
	if not hit_down.is_empty():
		return hit_down.get("position", from_pos)

	var up_params := PhysicsRayQueryParameters3D.create(
		from_pos, from_pos + Vector3(0, max_distance, 0)
	)
	up_params.exclude = [get_rid()]
	var hit_up: Dictionary = space_state.intersect_ray(up_params)
	if not hit_up.is_empty():
		return hit_up.get("position", from_pos)

	return Vector3.INF


func _log(msg: String) -> void:
	# Centralized logger: feeds the in-game CONSOLE tab when
	# DebugOverlay is available, falls back to print otherwise.
	#
	# (Earlier this function was accidentally polluted with the
	# tail of _detonate — XP awarding and queue_free were
	# attached here instead of staying in _detonate where they
	# belong. That made every single log call double-award XP
	# and try to free the charge. Now _log just logs.)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("[PowderCharge] " + msg)
	else:
		print("[PowderCharge] " + msg)
