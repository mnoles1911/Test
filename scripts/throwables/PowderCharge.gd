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

@export var aoe_radius_meters: float = 3.0
# Sphere radius of the voxel-removal blast and damage area, in
# metres. ThrowableHandler overwrites this on spawn from
# InventoryManager.ITEM_REGISTRY[item_id]["voxel_aoe_radius"]
# (currently 3.0 for powder_charge, 6.0 for sappers_bundle), so the
# @export default only matters when an instance is spawned outside
# the normal flow (e.g. dropped via the editor for testing).

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
	# Join group so the Chain Reaction perk can find neighbors.
	add_to_group("powder_charge")


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
	var body_label: String = "?"
	if body != null:
		body_label = String(body.name)
	_log("Impact with '%s' at %s" % [body_label, global_position])
	_detonate()


func _detonate() -> void:
	_detonated = true

	# Carve a sphere centered slightly below the charge's position.
	# The 0.4m down-offset bites the sphere into the surface the
	# charge collided with so we get a visible crater instead of a
	# half-air-half-ground skim. (At 10 vox/m our voxels are ~10cm
	# each, so 0.4m is ~2-3 voxels deep — well into the solid.)
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

	# --- Visible detonation flash ---
	# Spawned before the queue_free() at the end of _detonate, parented
	# to the world so it survives the charge's removal. Without this
	# the only on-screen feedback is the voxel crater; with carves at
	# 3 m the crater alone is subtle from a distance and the player
	# reads "nothing happened." The light + emissive sphere combo gives
	# a one-frame "BOOM" that's unambiguous regardless of viewing angle.
	_spawn_detonation_effect(carve_center)

	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("BOOM at (%.1f, %.1f, %.1f) radius %.1fm" % [
			carve_center.x, carve_center.y, carve_center.z, aoe_radius_meters
		])

	# --- Demolition skill XP + active-perk dispatch ---
	# Per design/SKILLS_AND_PROGRESSION.md — explosive_detonated = 15.
	# The ctx is shared with active demo perks (chain, focused_blast,
	# smoker, concussion, charge_recovery) which read/mutate it.
	if get_node_or_null("/root/SkillManager"):
		SkillManager.add_xp("demolition", 15.0)
		var det_ctx: Dictionary = {
			"skill": "demolition",
			"detonation_source": "powder_charge",
			"world_pos": carve_center,
			"damage": combat_damage,
			"aoe_radius": aoe_radius_meters,
			"is_dud": false,
		}
		SkillManager.dispatch("on_attack", det_ctx)
		# If a perk flagged chain_explode, detonate nearby charges too.
		if det_ctx.get("chain_explode", false):
			_chain_detonate_nearby()

	# --- Damage enemies in the AOE ---
	# TODO: iterate over enemy nodes within aoe_radius_meters and
	# call take_damage(combat_damage). Blocked on EnemyAI not
	# existing yet.

	# Remove the charge from the world. queue_free defers actual
	# removal to the end of the frame so any in-flight signal
	# handling completes safely.
	queue_free()


func _chain_detonate_nearby() -> void:
	# Wake any other PowderCharge instances within 2 × aoe_radius so
	# they detonate too. Used by the Chain Reaction perk; harmless
	# when the perk is not owned (no flag set, function never called).
	var chain_radius: float = aoe_radius_meters * 2.0
	for body in get_tree().get_nodes_in_group("powder_charge"):
		if body == self or not is_instance_valid(body):
			continue
		if not (body is RigidBody3D):
			continue
		if body.global_position.distance_to(global_position) <= chain_radius:
			if body.has_method("_detonate"):
				body.call_deferred("_detonate")


func _spawn_detonation_effect(at_position: Vector3) -> void:
	# Build a self-cleaning Node3D containing an OmniLight3D and an
	# emissive sphere mesh that animates outward, then queue_free()s
	# itself when the tween finishes. Parented to the charge's parent
	# (the world scene) so it survives the charge's queue_free().
	var world_root: Node = get_parent()
	if world_root == null:
		return

	var fx_root := Node3D.new()
	world_root.add_child(fx_root)
	fx_root.global_position = at_position

	# Bright omnidirectional flash. Range scales with blast radius so
	# bigger charges illuminate more terrain on detonation.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 25.0
	light.omni_range = aoe_radius_meters * 3.0
	fx_root.add_child(light)

	# Emissive translucent sphere — the visible "fireball." Starts
	# small and animates out to aoe_radius_meters so the burst reads
	# as expanding rather than instantly appearing at full size.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.25, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.25)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # see inside if player is engulfed

	var sphere := SphereMesh.new()
	sphere.radius = aoe_radius_meters
	sphere.height = aoe_radius_meters * 2.0

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = sphere
	mesh_inst.material_override = mat
	mesh_inst.scale = Vector3(0.1, 0.1, 0.1)
	fx_root.add_child(mesh_inst)

	# Animation: 0.15 s expansion, then 0.3 s fade of both the
	# emissive sphere and the omni light, then free.
	var tween := fx_root.create_tween()
	tween.tween_property(mesh_inst, "scale", Vector3.ONE, 0.15)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.4)
	tween.tween_property(mat, "albedo_color", Color(1.0, 0.6, 0.25, 0.0), 0.3)
	tween.tween_callback(fx_root.queue_free)


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
