extends RigidBody3D
# PowderCharge — a thrown explosive that removes voxels in its blast
# radius and damages enemies caught nearby.
#
# What this does in plain English:
#
# When the player presses the throw input (currently quick_slot_1
# bound to "1"), ThrowableHandler.gd spawns one of these in front
# of Roland with a forward velocity. The charge flies through the
# air and detonates ONLY when it physically collides with a solid
# body — terrain, walls, ground, props.
#
# Charges that never hit anything (thrown off a cliff, into the
# void, past collision range) silently despawn after their
# lifetime expires. No mid-air fuse explosions; the player always
# gets an explosion exactly where the charge landed.
#
# Detonation:
#   1. Calls VoxelEditManager.queue_edit_sphere(pos, radius, AIR=0)
#      — removes voxels in a sphere centered slightly below the
#      charge so the carve bites into the surface it hit.
#      Inside a NoEditZone the call returns false; voxel removal
#      is silently skipped (visual + future damage still happen).
#   2. Awards Crafting/demolition sub-skill XP.
#   3. (Future) spawns a GPUParticles3D burst once VFX assets land.
#   4. queue_free()s itself.
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

@export var lifetime_seconds: float = 10.0
# Cleanup timer for charges that never impact anything (thrown
# off a cliff, into deep water, past collision range). On expire
# the charge is despawned silently — NO detonation, NO BOOM, NO
# XP, NO carve. Charges only ever produce explosions when they
# physically hit something.
#
# 10 seconds is generous; most thrown charges hit terrain within
# 1-3 seconds. The window only matters as a memory cleanup
# safety net so abandoned charges don't accumulate.
#
# (Earlier this was a 'fuse_seconds' that triggered mid-air
# detonation on expiry. That produced confusing 'BOOM with no
# crater' results when charges fell past Zylann's near-LOD
# collision range. Switched to impact-only detonation — simpler
# and the player always sees an explosion exactly where they
# expect: where the charge actually landed.)


# =============================================================
# RUNTIME STATE
# =============================================================

var _detonated: bool = false
# Single-use guard. body_entered can fire multiple times before
# queue_free completes; this prevents double-detonation.

var _lifetime_remaining: float


func _ready() -> void:
	_lifetime_remaining = lifetime_seconds
	# Detonate on collision with any solid body.
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	# Cleanup timer — silently despawn if the charge has been
	# alive for longer than its lifetime without hitting anything.
	# No BOOM, no carve, no XP. Player understands the charge
	# disappeared into nothing.
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		_log("Lifetime expired without impact — despawning silently at %s" % global_position)
		_detonated = true
		queue_free()


func _on_body_entered(body: Node) -> void:
	# The only path to detonation. Any solid body fires this:
	# terrain, walls, ground, props. Impact-only behavior is
	# simpler and means the player always gets an explosion
	# exactly where the charge landed.
	if _detonated:
		return
	_log("Impact with '%s' at %s" % [body.name if body != null else "?", global_position])
	_detonate()


func _detonate() -> void:
	_detonated = true

	# Carve a sphere centered slightly below the charge's position.
	# The 0.4m down-offset bites the sphere into the surface the
	# charge collided with so we get a visible crater instead of a
	# half-air-half-ground skim. (At 8 vox/m our voxels are 12.5cm
	# each, so 0.4m is roughly 3 voxels deep — well into the solid.)
	var carve_center: Vector3 = global_position + Vector3(0, -0.4, 0)

	if get_node_or_null("/root/VoxelEditManager"):
		var accepted: bool = VoxelEditManager.queue_edit_sphere(
			carve_center, aoe_radius_meters, 0
		)
		if accepted:
			_log("Carve queued: center=%s radius=%.1fm" % [carve_center, aoe_radius_meters])
		else:
			_log("Detonation inside NoEditZone — voxels preserved.")
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
