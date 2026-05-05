extends RigidBody3D
class_name VoxelDrop
# VoxelDrop — a physical pickup spawned when the player breaks
# voxels with a manual tool (pickaxe / shovel / axe).
#
# What this does in plain English:
#
#   When Roland mines a 3×3×3 chunk of grass with the shovel, we
#   spawn one of these at the carve point carrying the yield (e.g.
#   27× raw_dirt). The cube falls under gravity, lands on whatever's
#   below (terrain, water, another drop), and waits. If Roland walks
#   within PICKUP_RADIUS_M, the drop disappears and the items move
#   into his inventory automatically. If nothing collects it within
#   DESPAWN_SECONDS (2 minutes), the drop quietly removes itself so
#   abandoned mining sites don't accumulate forever.
#
# Visual: a small coloured cube using the source material's color_low
# so a grass drop reads as green, dirt as brown, stone as grey.
# After the body settles (lands and stops moving) the mesh bobs +
# spins gently as a "pick me up" cue.
#
# Spawned in code by EditToolHandler._carve — no .tscn required.
# Lives under whatever world parent EditToolHandler picks (typically
# the World3D root) so its lifetime is tied to the world, not the
# player. Save/load is OUT OF SCOPE for v1: drops on the ground when
# you save just disappear on reload. Worth revisiting once the
# inventory grid lands.


# ============================================================
# Tunables
# ============================================================

## How close (in metres) the player must be for auto-pickup.
## 1.5 m — comfortable walk-by collection without vacuuming items
## from across the carve site. Roland's collision capsule is ~0.5 m
## wide so 1.5 m means "the drop is within arm's reach as you pass
## the spot where it landed." Decoupled from the 3.5 m manual-tool
## reach so picking up doesn't require the same precise aim mining
## does.
@export var pickup_radius_m: float = 1.5

## Seconds before an uncollected drop despawns. 300 s = 5 minutes,
## long enough for the player to mine a chunk, run home to drop
## extra inventory, and come back; short enough that abandoned
## mining sites don't leave permanent litter on the world.
@export var despawn_seconds: float = 300.0

## Cube edge length for the visual mesh + collision shape (metres).
## Smaller than a single voxel (16.7 cm) so the drop reads as an
## item, not a chunk of terrain.
@export var visual_size_m: float = 0.20

## Cooldown after spawn during which pickup is disabled. Prevents
## the drop from being instantly auto-collected by the player who
## triggered the carve while still standing in pickup radius.
## After this window, normal pickup applies.
@export var pickup_lockout_seconds: float = 0.4


# ============================================================
# Constants — visual polish
# ============================================================

# Hover bob (post-settle).
const HOVER_AMPLITUDE_M: float = 0.06
const HOVER_PERIOD_S: float = 1.4
# Y rotation per second.
const SPIN_SPEED_DEG_PER_SEC: float = 70.0
# Body considered "settled" once horizontal speed drops below this.
const SETTLE_SPEED_THRESHOLD: float = 0.3


# ============================================================
# Runtime state
# ============================================================

var item_id: String = ""
var item_count: int = 1
var _color: Color = Color(0.5, 0.5, 0.5, 1.0)
var _picked_up: bool = false
var _settled: bool = false
var _spawn_time: float = 0.0
# `_mesh_local_origin_y` is captured AFTER the body settles so the
# bob animation oscillates around the resting y, not around 0.
var _mesh_local_origin_y: float = 0.0
var _mesh_inst: MeshInstance3D


# ============================================================
# Public API — call BEFORE add_child so the values are set when
# _ready runs. add_child triggers _ready, which builds the visual
# from the configured colour + count.
# ============================================================

func setup(p_item_id: String, p_color: Color, p_count: int) -> void:
	item_id = p_item_id
	_color = p_color
	item_count = maxi(p_count, 1)


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	# Physics tuning — moderately bouncy so drops settle visibly
	# rather than dead-thumping into the ground. Linear/angular
	# damp keep them from sliding forever on slopes.
	mass = 0.4
	gravity_scale = 1.0
	linear_damp = 1.5
	angular_damp = 2.0
	# We want this body to interact with terrain but NOT with the
	# player capsule (the player walks through the cubes for
	# pickup). Layer 1 = world; player capsule layer is also 1
	# typically, so use a separate collision_layer.
	# (If the player layer needs special treatment, configure
	# Project Settings → Physics → Layers and adjust here.)

	_build_visual()
	_build_collision()
	_apply_initial_impulse()

	# Despawn watchdog — even if the player abandons the drop, it
	# self-cleans after the timer.
	var timer := get_tree().create_timer(despawn_seconds, false)
	timer.timeout.connect(_on_despawn_timeout)


func _build_visual() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * visual_size_m

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.roughness = 0.7
	mat.metallic = 0.0

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = mesh
	_mesh_inst.material_override = mat
	add_child(_mesh_inst)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * visual_size_m
	shape.shape = box
	add_child(shape)


func _apply_initial_impulse() -> void:
	# Small upward + random horizontal pop so the drop bursts out
	# of the carve site rather than dropping straight down. Lifts
	# ~0.3 m, scatters within ~1 m of spawn.
	var horiz: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 1.2
	var vertical: float = randf_range(2.5, 3.5)
	apply_impulse(Vector3(horiz.x, vertical, horiz.z))


# ============================================================
# Per-frame: pickup proximity + hover animation
# ============================================================

func _physics_process(delta: float) -> void:
	if _picked_up:
		return
	_spawn_time += delta

	# Detect settle: horizontal speed has dropped below threshold
	# AND we're not flying upward. Once settled, we capture the
	# mesh's current local y to anchor the hover bob.
	if not _settled and linear_velocity.length() < SETTLE_SPEED_THRESHOLD:
		_settled = true
		if _mesh_inst != null:
			_mesh_local_origin_y = _mesh_inst.position.y

	# Hover + spin only after settle. Pre-settle the body is
	# still tumbling under gravity; overlaying our own animation
	# would fight the physics.
	if _settled and _mesh_inst != null:
		var bob: float = sin(_spawn_time * TAU / HOVER_PERIOD_S) * HOVER_AMPLITUDE_M
		_mesh_inst.position.y = _mesh_local_origin_y + bob
		_mesh_inst.rotation.y += deg_to_rad(SPIN_SPEED_DEG_PER_SEC) * delta

	# Pickup proximity check — only after the spawn lockout to
	# avoid instant-collect by the player who triggered the carve.
	if _spawn_time < pickup_lockout_seconds:
		return
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= pickup_radius_m:
		_try_pickup()


func _try_pickup() -> void:
	if _picked_up:
		return
	_picked_up = true
	if get_node_or_null("/root/InventoryManager"):
		InventoryManager.add_item(item_id, item_count)
	queue_free()


func _on_despawn_timeout() -> void:
	# If the timer fires after we've already been picked up,
	# queue_free is a no-op (node already freed). Safe.
	if not _picked_up:
		queue_free()
