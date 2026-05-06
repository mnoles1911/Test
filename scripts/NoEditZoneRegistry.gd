extends Node
# NoEditZoneRegistry — single source of truth for "where can the player NOT
# edit the voxel terrain?"
#
# How this works in plain English:
#
# 1. Anywhere in the world that should be protected from terrain edits
#    (settlements, dungeon entrances, lore landmarks), an Area3D node is
#    placed in the scene and added to the Godot group "no_edit_zone".
#
# 2. Before VoxelEditManager applies any voxel edit (a pickaxe swing,
#    an explosive blast, a spell), it asks this registry: "is the point
#    where this edit is happening inside any no-edit zone?"
#
# 3. If yes, the edit is silently rejected. If no, the edit proceeds.
#
# This script does NOT keep its own list of zones. It queries Godot's
# physics system at the moment of the question. That's simpler than
# tracking tree_entered / tree_exiting events ourselves, and it's
# automatically correct as zones load and unload via EntityStreamer.
#
# Registered as an autoload in Project Settings → Autoload with the node
# name "NoEditZoneRegistry". Until it's registered, scripts that call it
# should guard with `get_node_or_null("/root/NoEditZoneRegistry")`.
#
# Reference: design/3D_VOXEL_MIGRATION.md → "NoEditZones — The Opt-Out Model"


# ----------------------------------------------------------------------
# How to author a NoEditZone in a scene
# ----------------------------------------------------------------------
#
# 1. Add an Area3D node where you want protection — typically wrapping
#    a settlement, dungeon entrance, or lore landmark.
# 2. Add a CollisionShape3D as a child of the Area3D, with a BoxShape3D
#    or ConvexShape3D sized to cover the protected region. Aim for a
#    50–100m buffer around the structure (per the canonical spec).
# 3. With the Area3D selected, in the Inspector → Node tab → Groups,
#    add the group "no_edit_zone".
# 4. That's it. This registry will find it automatically the next time
#    a voxel edit is attempted nearby.
#
# Note: the Area3D's "monitorable" property must be true (this is the
# Godot default). If you've manually disabled it, point queries won't
# find the zone.
# ----------------------------------------------------------------------


func is_point_inside_no_edit_zone(world_pos: Vector3) -> bool:
	# Ask Godot's physics system: "what overlaps this single point?"
	# We're looking for any Area3D in the scene that contains world_pos
	# AND is in the "no_edit_zone" group.
	#
	# This is a per-edit query, not a per-frame poll — it only runs
	# when something is actually trying to write a voxel.

	var space_state: PhysicsDirectSpaceState3D = _get_space_state()
	if space_state == null:
		# No 3D physics world available yet (probably called before any
		# 3D scene is loaded). Treat as "not in a zone" — the caller
		# can edit freely. In practice this should never happen during
		# gameplay; it's a defensive fallback.
		return false

	# Build the point query. We want:
	#   - position: the point we're testing
	#   - collide_with_areas = true: we're looking for Area3D nodes
	#   - collide_with_bodies = false: we don't care about solid bodies
	var params := PhysicsPointQueryParameters3D.new()
	params.position = world_pos
	params.collide_with_areas = true
	params.collide_with_bodies = false

	# Run the query. Returns up to 32 hits (the second arg is the cap).
	# Each hit is a Dictionary; the "collider" key holds the Area3D.
	# 32 is far more than we'd ever expect — overlapping no-edit zones
	# are rare. Plenty of headroom.
	var hits: Array[Dictionary] = space_state.intersect_point(params, 32)

	# If any hit is an Area3D in the "no_edit_zone" group, the point is
	# protected. We only need one match — short-circuit on the first.
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Node and (collider as Node).is_in_group("no_edit_zone"):
			return true

	return false


func does_aabb_overlap_no_edit_zone(aabb_min: Vector3, aabb_max: Vector3) -> bool:
	# AABB overlap query — single physics call instead of N point queries.
	# Used as a pre-flight by bulk voxel writes (VoxelEditManager bulk
	# handler) and by gravity-system flood-fill (VoxelGravityManager) so
	# that the common case "no zone anywhere near this batch of voxels"
	# costs ONE physics query instead of one per voxel. Per-voxel point
	# checks remain the right call when the AABB does overlap a zone
	# (some voxels in, some out), so this method is a fast-path filter
	# rather than a replacement.
	#
	# Symptom of NOT having this: bulk writes of 1,000+ voxels (a
	# settled cluster re-depositing) stutter the frame because each
	# voxel runs intersect_point. With this pre-flight, the cluster
	# redeposit costs one shape query.

	var space_state: PhysicsDirectSpaceState3D = _get_space_state()
	if space_state == null:
		return false

	# Box covering the AABB. Setting size = max - min and translating
	# by the AABB's centre (since BoxShape3D is centred on its origin).
	var box := BoxShape3D.new()
	box.size = aabb_max - aabb_min
	# Edge case — degenerate AABB (point or line): clamp to a 1-voxel-ish
	# minimum so the BoxShape3D is non-zero. Otherwise the query may
	# silently return zero hits even when the point IS inside a zone.
	box.size.x = maxf(box.size.x, 0.01)
	box.size.y = maxf(box.size.y, 0.01)
	box.size.z = maxf(box.size.z, 0.01)

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.transform = Transform3D(Basis.IDENTITY, (aabb_min + aabb_max) * 0.5)
	params.collide_with_areas = true
	params.collide_with_bodies = false

	var hits: Array[Dictionary] = space_state.intersect_shape(params, 32)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Node and (collider as Node).is_in_group("no_edit_zone"):
			return true
	return false


func is_water_flow_blocked_at(world_pos: Vector3) -> bool:
	# True if any NoEditZone overlapping world_pos has blocks_water_flow
	# set to true. Bare Area3Ds (no NoEditZone.gd script attached) are
	# treated as blocking by default — matching the previous behavior
	# from before the per-zone flag landed.
	#
	# Used by WaterFlowManager when deciding whether to place a flow
	# cell at a candidate voxel position. See scripts/NoEditZone.gd
	# for the @export and design/3D_VOXEL_MIGRATION.md for the
	# locked design.
	var space_state: PhysicsDirectSpaceState3D = _get_space_state()
	if space_state == null:
		return false
	var params := PhysicsPointQueryParameters3D.new()
	params.position = world_pos
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var hits: Array[Dictionary] = space_state.intersect_point(params, 32)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Node and (collider as Node).is_in_group("no_edit_zone"):
			# If the script provides the flag, honor it. Otherwise
			# default to "blocks" for backward compatibility with bare
			# Area3D zones.
			if "blocks_water_flow" in collider:
				if (collider as Object).blocks_water_flow:
					return true
			else:
				return true
	return false


func get_water_blocking_aabbs_snapshot() -> Array[AABB]:
	# Walks the "no_edit_zone" group ON THE MAIN THREAD and returns
	# the world-space AABBs of every zone that has
	# blocks_water_generation=true. Bare Area3Ds without the
	# NoEditZone.gd script default to FALSE (water generation is the
	# opt-in case — see NoEditZone.gd for rationale).
	#
	# WHY THIS EXISTS: the world generator runs on Zylann's worker
	# threads. Worker threads cannot touch the SceneTree (no
	# get_node_or_null, no physics queries). They also cannot call this
	# method directly — it walks the tree. World3DBootstrap calls this
	# once at load on the main thread and pushes the result into the
	# generator resource via set_no_edit_water_aabbs(). The generator
	# then reads the snapshot from a plain var on its own resource,
	# which IS safe across worker threads (idempotent reads).
	#
	# CONSEQUENCE: zones added to the scene at runtime (e.g. via
	# EntityStreamer) are NOT in the snapshot and will not retroactively
	# affect chunks that already generated. This is documented as a v1
	# limitation — settlements that need to be dry below sea level must
	# be in the scene tree at world load.
	var snapshot: Array[AABB] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return snapshot
	for zone_node in tree.get_nodes_in_group("no_edit_zone"):
		# Honour the opt-in flag — bare Area3Ds and zones with the flag
		# off are skipped (water-generation default is "let the water in").
		if not ("blocks_water_generation" in zone_node):
			continue
		if not (zone_node as Object).blocks_water_generation:
			continue
		var aabb := _world_aabb_of_area(zone_node as Area3D)
		if aabb.size == Vector3.ZERO:
			continue
		snapshot.append(aabb)
	return snapshot


func _world_aabb_of_area(area: Area3D) -> AABB:
	# Compute the world-space AABB of an Area3D by unioning the AABBs
	# of every CollisionShape3D child whose shape exposes a get_debug_mesh
	# (covers BoxShape3D, SphereShape3D, ConvexPolygonShape3D, etc.).
	# Falls back to a zero AABB if no usable child is found — the
	# caller drops zero-size AABBs.
	if area == null:
		return AABB()
	var combined := AABB()
	var first: bool = true
	for child in area.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		# Each shape's debug mesh is in shape-local space. Apply the
		# CollisionShape3D's global transform to get world-space verts,
		# then take their min/max.
		var debug_mesh: Mesh = shape_node.shape.get_debug_mesh()
		if debug_mesh == null:
			continue
		var local_aabb: AABB = debug_mesh.get_aabb()
		var xform: Transform3D = shape_node.global_transform
		# Transform the 8 corners of the local AABB into world space and
		# take the resulting AABB. AABB.transform isn't quite right for
		# non-axis-aligned rotations — corner-by-corner is robust.
		var corners: Array[Vector3] = [
			local_aabb.position,
			local_aabb.position + Vector3(local_aabb.size.x, 0, 0),
			local_aabb.position + Vector3(0, local_aabb.size.y, 0),
			local_aabb.position + Vector3(0, 0, local_aabb.size.z),
			local_aabb.position + Vector3(local_aabb.size.x, local_aabb.size.y, 0),
			local_aabb.position + Vector3(local_aabb.size.x, 0, local_aabb.size.z),
			local_aabb.position + Vector3(0, local_aabb.size.y, local_aabb.size.z),
			local_aabb.position + local_aabb.size,
		]
		for c in corners:
			var w: Vector3 = xform * c
			if first:
				combined = AABB(w, Vector3.ZERO)
				first = false
			else:
				combined = combined.expand(w)
	return combined


func _get_space_state() -> PhysicsDirectSpaceState3D:
	# Grab the 3D physics space from the current scene's world.
	# Returns null if no 3D viewport / world is active yet.
	#
	# We walk: SceneTree → root window → world_3d → direct_space_state
	# Every step is null-checked so this can be called safely at any
	# time, including before the main scene loads.
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var root: Window = tree.root
	if root == null:
		return null
	var world: World3D = root.world_3d
	if world == null:
		return null
	return world.direct_space_state
