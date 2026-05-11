extends Node
# BloodVFX — autoload manager for blood and dust particle effects.
#
# What this does in plain English:
#
#   This is the single API for every blood and dust effect in combat.
#   Call sites (ThrowableSpear, Enemy3D subclasses, future melee weapons)
#   ask this autoload to play an effect at a position; the autoload picks
#   an idle particle node from a pre-allocated pool, configures it for
#   the request, and emits it.
#
#   FOUR EFFECTS, FOUR APIs:
#
#     spawn_burst(world_pos, direction, intensity)
#       — Layer A. Big directional spray of cube blood particles. Fired
#         every time an enemy takes damage. Direction is the impact
#         direction (usually the spear's travel vector) so the spray
#         continues along the line of force.
#
#     spawn_dust(world_pos, normal)
#       — Tan dust burst for terrain impacts. Smaller and less dense
#         than blood. Aimed along the surface normal so dust sprays
#         outward from the hit face.
#
#     start_drip(target_node, socket_name)  /  stop_drip(target_node)
#       — Layer B. Continuous slow drip of small blood particles from
#         the target's chest socket. start_drip reparents the drip
#         node onto the target so it follows the enemy's movement;
#         stop_drip fades it out. Auto-cleans if the target is freed
#         before stop_drip is called (e.g. enemy dies before bleed-out).
#
#     spawn_pool(world_pos, max_size, grow_seconds)
#       — Layer C. Flat blood-pool Decal projected onto the ground
#         beneath the kill site. Grows in size over a few seconds.
#         Decal (not particles) — it's a single textured projection
#         that costs almost nothing per pool.
#
# WHY POOL THE PARTICLES:
#   GPUParticles3D nodes allocate GPU buffers on creation. During heavy
#   combat (10+ bursts per second) instantiate-on-demand causes 4 ms+
#   hitches right when the player wants the smoothest moments. Pre-
#   allocating the pool at scene load amortizes the cost.
#
#   Bursts and dust are pooled (frequent, fire-and-forget). Drips are
#   instantiate-per-target (one per enemy, longer lifetime, reparented
#   to the target so they follow movement — pooling these would mean
#   reparent dance every time which defeats the point).
#
# REGISTERED IN project.godot AS AUTOLOAD `BloodVFX`. Load order: must
# load BEFORE any script that calls into this API on _ready. In practice
# combat scripts find this via get_node_or_null("/root/BloodVFX") so the
# order is forgiving.


# =============================================================
# SCENE PRELOADS
# =============================================================

const _BURST_SCENE: PackedScene = preload("res://scenes/vfx/BloodBurst.tscn")
const _DUST_SCENE:  PackedScene = preload("res://scenes/vfx/DustBurst.tscn")
const _DRIP_SCENE:  PackedScene = preload("res://scenes/vfx/BloodDrip.tscn")


# =============================================================
# POOL SIZES
# =============================================================

const POOL_SIZE_BURST: int = 12
## Max simultaneous blood bursts in flight. 12 covers a chaotic 4-on-1
## fight with several damage events per goblin. If exceeded, new
## requests drop silently — the player won't notice one missing burst
## in a chaotic moment, and the alternative (force-restarting the
## oldest particle) creates worse glitches.

const POOL_SIZE_DUST: int = 8
## Max simultaneous dust bursts. Smaller than burst pool because spear
## terrain impacts are less frequent than enemy hits.


# =============================================================
# RUNTIME STATE
# =============================================================

var _burst_pool: Array[GPUParticles3D] = []
var _dust_pool: Array[GPUParticles3D] = []

var _active_drips: Dictionary = {}
## Map: target Node3D → GPUParticles3D drip node. Cleaned via the
## target's tree_exited signal so we never hold dangling references.

var _pool_texture: Texture2D
## Procedural radial-gradient texture generated once at startup and
## reused by every blood-pool Decal. Saves loading a .png from disk
## and keeps the pool art tunable from code.


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Pre-build the procedural blood-pool texture before anything else.
	_pool_texture = _build_pool_texture()

	# Pre-instantiate the burst and dust pools as children of the
	# autoload itself. Particles will be repositioned via global_position
	# at spawn time — being parented here doesn't constrain them spatially.
	for i in POOL_SIZE_BURST:
		var p := _BURST_SCENE.instantiate() as GPUParticles3D
		p.emitting = false
		add_child(p)
		_burst_pool.append(p)

	for i in POOL_SIZE_DUST:
		var p := _DUST_SCENE.instantiate() as GPUParticles3D
		p.emitting = false
		add_child(p)
		_dust_pool.append(p)


# =============================================================
# PUBLIC API — Layer A: blood burst
# =============================================================

## Spawn a directional blood burst at world_pos, spraying outward along
## direction. intensity scales the particle count from 0.5 (light hit)
## to 1.0 (normal) to ~2.0 (overkill explosion). Caller is responsible
## for picking a sensible intensity from damage amount.
##
## Silently no-ops if the pool is exhausted — there's no exception or
## return value, the player would not benefit from a "burst dropped"
## warning during combat.
func spawn_burst(world_pos: Vector3, direction: Vector3, intensity: float = 1.0) -> void:
	var p := _grab_idle(_burst_pool)
	if p == null:
		return  # pool exhausted; drop request silently
	p.global_position = world_pos
	# Aim the cone: look_at_from_position points the node's -Z toward
	# the target. The particle scene is configured with direction
	# Vector3(0, 0, -1) so spawned particles travel along -Z, which
	# becomes the world `direction` after this rotation.
	var aim_target: Vector3 = world_pos + direction.normalized()
	# Use FORWARD as up reference for near-vertical throws to avoid the
	# look_at degenerate case when direction is parallel to UP.
	var up_ref: Vector3 = Vector3.UP if absf(direction.normalized().y) < 0.95 else Vector3.FORWARD
	p.look_at_from_position(world_pos, aim_target, up_ref)
	# Scale particle count by intensity, clamped to scene's max amount.
	var base_amount: int = int(p.get_meta("base_amount", 80))
	p.amount = clampi(int(base_amount * intensity), 8, base_amount * 2)
	p.restart()  # restart() resets simulation state AND sets emitting=true


# =============================================================
# PUBLIC API — Dust burst (terrain impacts)
# =============================================================

## Spawn a dust puff at world_pos, spraying outward along normal (the
## surface normal at the impact point). Smaller and shorter-lived than
## a blood burst; appropriate for spear-on-stone, footsteps, etc.
func spawn_dust(world_pos: Vector3, normal: Vector3) -> void:
	var p := _grab_idle(_dust_pool)
	if p == null:
		return
	p.global_position = world_pos
	var aim_target: Vector3 = world_pos + normal.normalized()
	var up_ref: Vector3 = Vector3.UP if absf(normal.normalized().y) < 0.95 else Vector3.FORWARD
	p.look_at_from_position(world_pos, aim_target, up_ref)
	p.restart()


# =============================================================
# PUBLIC API — Layer B: wound drip
# =============================================================

## Begin a continuous bleed effect on target. The drip particle node
## is reparented to target's child node named socket_name (default
## "ChestSocket") so it tracks the target's movement. If the target
## doesn't have that child, the drip parents to target itself.
##
## No-op if a drip is already active on this target (we don't stack
## bleeds — one wound per enemy in v1).
func start_drip(target: Node3D, socket_name: String = "ChestSocket") -> void:
	if target == null or _active_drips.has(target):
		return
	var socket: Node3D = target.get_node_or_null(socket_name) as Node3D
	if socket == null:
		socket = target
	var drip := _DRIP_SCENE.instantiate() as GPUParticles3D
	socket.add_child(drip)
	drip.emitting = true
	_active_drips[target] = drip
	# Auto-cleanup if the target is freed before stop_drip is called
	# (enemy dies mid-bleed). CONNECT_ONE_SHOT so we don't need to
	# disconnect manually.
	target.tree_exited.connect(_on_drip_target_freed.bind(target), CONNECT_ONE_SHOT)


## Stop the active drip on target. Particles in flight finish their
## natural lifetime, then the node frees. No-op if target has no
## active drip.
func stop_drip(target: Node3D) -> void:
	if not _active_drips.has(target):
		return
	var drip: GPUParticles3D = _active_drips[target]
	_active_drips.erase(target)
	if not is_instance_valid(drip):
		return
	drip.emitting = false
	# Let existing particles finish their lifetime, then free.
	var t := get_tree().create_timer(drip.lifetime)
	t.timeout.connect(drip.queue_free)


func _on_drip_target_freed(target: Node3D) -> void:
	# Target is gone — drip was a child of target so it was freed too.
	# Just drop our reference; nothing left to clean up.
	_active_drips.erase(target)


# =============================================================
# PUBLIC API — Layer C: blood pool
# =============================================================

## Spawn a flat blood-pool quad beneath world_pos. Raycasts downward
## up to 3 m to find the ground; if no ground is hit (enemy died in
## mid-air over a void), the pool is placed at world_pos directly.
##
## The pool starts at 0.3 m diameter and grows to max_size_meters over
## grow_seconds, then lingers until the scene unloads.
##
## IMPLEMENTATION NOTE: Uses a flat PlaneMesh + transparent texture
## rather than a Decal node. Decals only render under the Forward+ /
## Mobile renderers; this project is on gl_compatibility per
## project.godot, where Decals are silently invisible. The plane-mesh
## approach works on every renderer at the cost of being a fixed-
## orientation flat quad (no surface projection). For the dev arena's
## flat ground that's fine; if Game One ever needs blood pools that
## conform to sloped terrain, switch to Decal AND switch the renderer.
func spawn_pool(world_pos: Vector3, max_size_meters: float = 1.5, grow_seconds: float = 8.0) -> void:
	# Find ground via downward raycast. Start 0.5 m above the kill site
	# so we don't miss when the enemy's feet are exactly on a surface.
	var space: PhysicsDirectSpaceState3D = get_tree().root.world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		world_pos + Vector3(0, 0.5, 0),
		world_pos + Vector3(0, -3.0, 0)
	)
	var hit: Dictionary = space.intersect_ray(query)
	var ground_pos: Vector3 = world_pos
	if hit.has("position"):
		ground_pos = hit["position"]

	# Build a flat quad with the procedural radial-gradient texture.
	# PlaneMesh defaults to facing +Y (lies flat on the ground when
	# placed at world position with no rotation), which is exactly
	# what we want for a pool seen from above.
	var plane := PlaneMesh.new()
	plane.size = Vector2(max_size_meters, max_size_meters)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _pool_texture
	mat.albedo_color = Color(0.5, 0.05, 0.05, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# render_priority = -1 keeps the pool behind the goblin corpse if
	# they overlap, so the corpse silhouette doesn't get visually
	# subtracted by the pool's alpha.
	mat.render_priority = -1

	var pool_mesh := MeshInstance3D.new()
	pool_mesh.mesh = plane
	pool_mesh.material_override = mat

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		# Fallback: parent to the autoload itself. Pool will follow the
		# autoload (always at origin) which is wrong, but better than
		# crashing during scene transitions.
		scene_root = self
	scene_root.add_child(pool_mesh)
	# Lift the quad slightly off the ground so it doesn't z-fight with
	# the surface below.
	pool_mesh.global_position = ground_pos + Vector3(0, 0.02, 0)

	# Tween the visible scale from a small starting size to full size
	# over grow_seconds. We tween the MeshInstance3D scale rather than
	# the PlaneMesh size because the latter can't be Property-tweened
	# directly (PlaneMesh is a sub-resource).
	pool_mesh.scale = Vector3(0.2, 1.0, 0.2)
	var tween := pool_mesh.create_tween()
	tween.tween_property(pool_mesh, "scale", Vector3(1.0, 1.0, 1.0), grow_seconds)


# =============================================================
# INTERNAL — pool management
# =============================================================

func _grab_idle(pool: Array[GPUParticles3D]) -> GPUParticles3D:
	for p in pool:
		if not p.emitting:
			return p
	return null


# =============================================================
# INTERNAL — procedural pool texture
# =============================================================

func _build_pool_texture() -> ImageTexture:
	# 64×64 RGBA radial gradient. Center is opaque red, edges fade to
	# transparent so the decal doesn't have a hard rim. Quadratic
	# falloff (1 - r²) gives a softer "puddle" look than linear.
	const SIZE: int = 64
	const HALF: float = 32.0
	var img: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var dx: float = float(x) - HALF
			var dy: float = float(y) - HALF
			var r: float = sqrt(dx * dx + dy * dy) / HALF  # 0 at center, 1 at edge
			var alpha: float = clampf(1.0 - r * r, 0.0, 1.0)
			# Slight noise on alpha so the pool edge isn't a perfect circle.
			var noise: float = (sin(float(x) * 1.7 + float(y) * 1.3) * 0.5 + 0.5) * 0.15
			alpha = clampf(alpha - noise * (1.0 - alpha), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.4, 0.04, 0.04, alpha))
	return ImageTexture.create_from_image(img)


# ============================================================
# MP-4 NETWORKING — visual events shared across peers.
#
# In a multiplayer session, a discrete visual event (a sword landing,
# a projectile sticking) happens on one peer's machine but should be
# visible to everyone. These _networked variants fire the local pool
# AND broadcast an unreliable RPC to all other peers so they spawn
# their own local pool instance at the same world position.
#
# Unreliable channel: blood is purely cosmetic. If a packet drops,
# the worst case is one peer doesn't see a single flash — acceptable.
# Reliable would cost more bandwidth + retransmits without improving
# the user's experience.
#
# call_local is intentionally NOT used here — the caller already
# plays the local event before the RPC, so adding call_local would
# double-play on the sender.
#
# In OFFLINE mode (no peer set) the .rpc() call is a no-op so the
# _networked variants degrade gracefully to a pure local play.
# ============================================================

## Cosmetic burst at a hit site. Mirrors spawn_burst() locally AND
## broadcasts to every other peer.
func spawn_burst_networked(world_pos: Vector3, direction: Vector3, intensity: float = 1.0) -> void:
	spawn_burst(world_pos, direction, intensity)
	_rpc_spawn_burst.rpc(world_pos, direction, intensity)


## Dust puff at a stone impact. Mirrors spawn_dust() locally AND
## broadcasts to every other peer.
func spawn_dust_networked(world_pos: Vector3, normal: Vector3) -> void:
	spawn_dust(world_pos, normal)
	_rpc_spawn_dust.rpc(world_pos, normal)


## Blood pool quad at a kill site. Mirrors spawn_pool() locally AND
## broadcasts to every other peer. Used by Enemy3D's death visual
## broadcast where the per-peer call would otherwise depend on the
## death event firing on every peer separately — using the networked
## variant lets a host-only callsite paint the pool everywhere.
func spawn_pool_networked(world_pos: Vector3, max_size_meters: float = 1.5, grow_seconds: float = 8.0) -> void:
	spawn_pool(world_pos, max_size_meters, grow_seconds)
	_rpc_spawn_pool.rpc(world_pos, max_size_meters, grow_seconds)


@rpc("any_peer", "unreliable")
func _rpc_spawn_burst(world_pos: Vector3, direction: Vector3, intensity: float) -> void:
	spawn_burst(world_pos, direction, intensity)


@rpc("any_peer", "unreliable")
func _rpc_spawn_dust(world_pos: Vector3, normal: Vector3) -> void:
	spawn_dust(world_pos, normal)


@rpc("any_peer", "unreliable")
func _rpc_spawn_pool(world_pos: Vector3, max_size_meters: float, grow_seconds: float) -> void:
	spawn_pool(world_pos, max_size_meters, grow_seconds)
