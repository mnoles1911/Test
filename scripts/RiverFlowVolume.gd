extends Node3D

# RiverFlowVolume — designer-authored steady river current (W7,
# design/WATER_FINITE_SIM_PLAN.md).
#
# What this is in plain English:
#
# Drop one of these nodes over a stretch of river in the editor, point
# `flow_direction` downstream, size `extent` to cover the channel, and
# every WATER voxel inside the box gets its flow-DIRECTION bits stamped
# at world load. From then on `WaterFlowManager.get_flow_velocity_at`
# returns a steady push there — swimmers drift downstream, and floating
# objects will ride it once buoyancy lands.
#
# Why this exists even though the finite sim writes flow directions
# itself: the sim only writes DIR while water is MOVING and resets it
# to STILL when a body settles. A permanent river is settled water —
# it has no moving front — so its steady current is an authored fact,
# not a simulated one. This node is how the designer authors it.
#
# Notes:
# - Only the DIR bits change; water level and the infinite-source bit
#   are preserved (read-modify-write in VoxelEditManager's
#   "water_dir_box" command). Non-water voxels inside the box are
#   untouched, so the volume can safely overlap the banks.
# - Stamping goes through the normal edit queue: budgeted (no frame
#   spike — the box is sliced into chunk-sized slabs below), persisted
#   to the save, and MP-replicated like any other edit.
# - Re-stamping an already-stamped river is cheap (the drain skips
#   voxels whose byte wouldn't change).
#
# Setup: add the node to a world scene, put it in group
# "river_flow_volume" (done in _ready), aim +Z of the node or set
# `flow_direction` directly. World3DBootstrap calls stamp() on every
# group member once the terrain is up.

@export var flow_direction: Vector3 = Vector3(1, 0, 0)
# Which way the river pushes, in world space. Snapped to the nearest
# of the 6 cardinal directions at stamp time (the DATA5 byte stores
# one of 6 codes — diagonal rivers are authored as a chain of
# volumes alternating between the two cardinals).

@export var extent: Vector3 = Vector3(10.0, 2.0, 4.0)
# Box size in METRES, centred on this node. Make Y generous enough to
# cover the channel depth — the stamp skips non-water anyway.


func _ready() -> void:
	add_to_group("river_flow_volume")


func stamp() -> void:
	# Convert the box to voxel coords and queue the DIR stamp in
	# chunk-sized slabs (16 voxels per axis), so a long river becomes
	# many small budgeted commands instead of one frame-spiking giant.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return
	var dir_code: int = WaterByteCodec.offset_to_dir(_snap_cardinal(flow_direction))
	if dir_code == WaterByteCodec.DIR_STILL:
		push_warning("[RiverFlowVolume] %s: flow_direction is zero — nothing to stamp." % name)
		return
	var half: Vector3 = extent * 0.5
	var vmin: Vector3i = VoxelEditManager.world_to_voxel(global_position - half)
	var vmax: Vector3i = VoxelEditManager.world_to_voxel(global_position + half) + Vector3i.ONE
	const SLAB: int = 16
	var x: int = vmin.x
	while x < vmax.x:
		var y: int = vmin.y
		while y < vmax.y:
			var z: int = vmin.z
			while z < vmax.z:
				var smax := Vector3i(mini(x + SLAB, vmax.x), mini(y + SLAB, vmax.y), mini(z + SLAB, vmax.z))
				VoxelEditManager.queue_set_water_dir_box(Vector3i(x, y, z), smax, dir_code)
				z += SLAB
			y += SLAB
		x += SLAB
	print("[RiverFlowVolume] %s: stamped dir=%d over voxels %s..%s" % [name, dir_code, str(vmin), str(vmax)])


static func _snap_cardinal(v: Vector3) -> Vector3i:
	# Largest-axis snap: (0.9, 0, 0.3) -> +X. Zero vector -> zero.
	if v.length_squared() < 0.000001:
		return Vector3i.ZERO
	var ax: float = absf(v.x)
	var ay: float = absf(v.y)
	var az: float = absf(v.z)
	if ax >= ay and ax >= az:
		return Vector3i(1 if v.x > 0.0 else -1, 0, 0)
	if az >= ax and az >= ay:
		return Vector3i(0, 0, 1 if v.z > 0.0 else -1)
	return Vector3i(0, 1 if v.y > 0.0 else -1, 0)
