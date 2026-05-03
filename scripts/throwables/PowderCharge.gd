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

@export var fuse_seconds: float = 3.0
# Fuse delay if the charge doesn't impact-detonate. Counts down
# from the moment the charge is spawned. 3 seconds is roughly
# Roland's reaction window — long enough to throw and back away,
# short enough that he can't camp it.


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
	# If the fuse expires mid-air or the charge fell past the
	# voxel terrain's collision radius (which only generates on
	# near LODs), the charge's current position is in empty
	# sky / underground — a sphere carve there removes nothing
	# visible. Raycast straight down from the charge's position
	# to find the nearest ground surface, and detonate there
	# instead. Falls back to the current position if no ground
	# is within 100m (e.g. thrown over the edge of the world).
	var detonate_pos: Vector3 = _find_ground_below(global_position, 100.0)
	if detonate_pos != global_position:
		_log("Snapped detonation from air %s to ground %s" % [global_position, detonate_pos])

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


func _find_ground_below(from_pos: Vector3, max_distance: float) -> Vector3:
	# Cast a downward ray to find the nearest solid surface. Returns
	# the impact position on success, or the original from_pos if
	# nothing hit within max_distance.
	#
	# Used to ensure the fuse-expired-mid-air case still carves
	# visible terrain instead of carving empty air at the charge's
	# floating position.
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		from_pos,
		from_pos + Vector3(0, -max_distance, 0),
	)
	# Exclude the charge itself so the ray doesn't hit its own
	# collision shape immediately.
	params.exclude = [get_rid()]
	var hit: Dictionary = space_state.intersect_ray(params)
	if hit.is_empty():
		return from_pos
	return hit.get("position", from_pos)


func _log(msg: String) -> void:
	# Centralized logger: feeds the in-game CONSOLE tab when
	# DebugOverlay is available, falls back to print otherwise.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("[PowderCharge] " + msg)
	else:
		print("[PowderCharge] " + msg)

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
