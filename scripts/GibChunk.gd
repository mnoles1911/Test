extends RigidBody3D
# GibChunk — one airborne chunk of a gibbed body.
#
# Combat Phase 5 (design/COMBAT_NEXT_PHASES.md): an overkill (≥80 dmg)
# lethal hit on an enemy hides the corpse and spawns N of these from the
# kill site with outward radial impulse from the hit point. Each chunk
# is a small (~16 cm) coloured box that tumbles under gravity, lands
# wherever it falls, and despawns after LIFETIME_S so the world doesn't
# accumulate visual debris over a long session.
#
# DESIGN CHOICE — small per-chunk RigidBody3D vs. one fused
# FallingVoxelCluster: clusters mesh into a single rigid body, so 80
# voxels in a cluster fall as ONE chunky brick. For a gib explosion we
# want chunks visibly flying APART — each one trying its own trajectory.
# A handful of independent rigid bodies is the right shape; capped at
# Enemy3D.GIB_CHUNK_COUNT (default 12) so we don't pay an unbounded
# physics cost per kill.
#
# No terrain re-deposit (unlike FallingVoxelCluster). Gibs are flesh,
# not stone — they don't merge back into the voxel grid.

const LIFETIME_S: float = 30.0
# Long enough that the designer can see chunks settle + walk around
# them; short enough that overnight sessions don't accumulate hundreds.

const VISUAL_SIZE_M: float = 0.10
# Voxel-grid-sized cube so chunks read as "body voxels" not abstract
# debris. Matches the 1/10 m voxel scale.

const GRAVITY_SCALE: float = 1.0
# Match the project's default gravity (which is tuned for Player3D
# falls). 1.0 = normal weight; tweak if gibs feel too floaty.


func _ready() -> void:
	mass = 0.15
	gravity_scale = GRAVITY_SCALE
	linear_damp = 0.4
	angular_damp = 2.0
	continuous_cd = true
	# Failsafe — even if the chunk gets stuck on geometry, free after
	# the lifetime. `create_timer` with process_always=false so a
	# scene change tears it down cleanly.
	var t := get_tree().create_timer(LIFETIME_S, false)
	t.timeout.connect(queue_free)


# Public spawn API — called by Enemy3D._spawn_gib_explosion.
# Builds the mesh + collision + initial velocity in one shot so the
# caller doesn't have to know about box / material details.
func configure(color: Color, impulse: Vector3) -> void:
	_build_visual(color)
	_build_collision()
	# Apply impulse as linear velocity (mass * v = impulse for a single-
	# frame application). Add a small random spin so chunks tumble.
	apply_central_impulse(impulse)
	angular_velocity = Vector3(
		randf_range(-8.0, 8.0),
		randf_range(-8.0, 8.0),
		randf_range(-8.0, 8.0))


func _build_visual(color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * VISUAL_SIZE_M
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * VISUAL_SIZE_M
	shape.shape = box
	add_child(shape)
