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
