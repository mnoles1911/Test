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
		_detonate()


func _on_body_entered(_body: Node) -> void:
	# Impact detonation. Any solid body counts: terrain (voxel
	# collision), the ground, walls. The body argument is unused
	# — we just need the trigger.
	if _detonated:
		return
	_detonate()


func _detonate() -> void:
	_detonated = true

	# --- Voxel removal in the AOE ---
	if get_node_or_null("/root/VoxelEditManager"):
		# AIR_VOXEL = 0. queue_edit_sphere returns false if the
		# blast center is inside a NoEditZone — the visual still
		# plays but the masonry is preserved.
		var accepted: bool = VoxelEditManager.queue_edit_sphere(global_position, aoe_radius_meters, 0)
		if not accepted:
			print("[PowderCharge] Detonation inside NoEditZone — voxels preserved.")

	# --- Particle effect placeholder ---
	# TODO: spawn a GPUParticles3D preset once explosion VFX
	# assets exist. For now the only feedback is the voxel
	# crater + (future) audio.
	print("[PowderCharge] BOOM at %s (radius %.1fm)" % [global_position, aoe_radius_meters])

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
