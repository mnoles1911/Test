extends Node

# =============================================================
# WaterMesherSpike — Stage 6 Phase 2 THROW-AWAY SPIKE
# =============================================================
#
# This is NOT production code. It exists only to answer the single
# question in design/WATER_STAGE6_PLAN.md §11:
#
#   Can a custom per-chunk water *surface* mesh, rebuilt as the player
#   moves, coexist with VoxelLodTerrain streaming at acceptable perf
#   and with no visual regression vs. V2 transparent-cube water?
#
# It deliberately does the cheapest thing that yields a real number:
#   • flat surface only (one Y per column — NO slope, that is Phase 3),
#   • naive per-column quads (NO greedy merge — if naive is unaffordable
#     that is itself a finding),
#   • viewer-centred POLL (NO Zylann signal wiring — §11 allows this),
#   • attaches to the LIVE World3D terrain via VoxelEditManager
#     .get_terrain() (the same pattern WaterDiag / WaterFlowManager use)
#     so it measures the REAL streaming/flooding environment without
#     touching World3DBootstrap.
#
# SETUP (one-time, manual — like every other autoload in this project):
#   Project Settings → Autoload → add res://scripts/_dev/WaterMesherSpike.gd
#   as "WaterMesherSpike". Default OFF; does nothing until F7.
#
# RUN THE SPIKE TEST (the §11 bars):
#   1. Open World3D.tscn. Flood a blasted cavern as usual.
#   2. Press F7 → spike ON. A second flat water surface mesh now
#      renders on top of the V2 cubes (you will see both — expected;
#      this is a measurement rig, not the final look).
#   3. Bar ① perf: read the throttled [MesherSpike] line — build_us
#      this 1 s window + worst single rebuild; compare frame health to
#      F7-OFF. Bar target: << 2 ms added worst-frame, no new >16 ms.
#   4. Bar ② streaming: walk a ~200 m loop through/around the flood.
#      Watch live= (mesh count) rise then FALL as chunks leave radius
#      (eviction working), and vram from the [PERF] line not climbing
#      monotonically. orphans must stay 0.
#   5. Bar ③ visual: eyeball the flat sheet at distance vs. the V2
#      cubes — it must be no worse at the LOD seam.
#   6. Press F7 again → spike OFF, all spike meshes freed (confirms
#      clean teardown / no leak).
#
# STOP / cleanup: delete this file + the autoload line. Nothing else
# references it. (Phase 2 "pass" → productionise into a real mesher;
# Phase 2 "fail" → discard per §11's named fallback options.)


const POLL_INTERVAL_S: float = 0.25      # viewer re-scan cadence
const MESH_RADIUS_M: float = 40.0        # surface meshed out to here
const CHUNK_VOX: int = 16                # voxel chunk edge (matches Zylann)
const VOXELS_PER_METER: float = 6.0
const WATER_TYPE_ID: int = 5
const BUILD_BUDGET_US: int = 3000        # per-poll mesh-build cap (mirrors
#                                          the deleted WaterChunkMesher's
#                                          3 ms adaptive budget) so a fair
#                                          "can it keep up?" is measured.
const REPORT_INTERVAL_S: float = 1.0
const MAT_PATH: String = "res://assets/shaders/water_material.tres"

var _active: bool = false
var _root: Node3D = null                 # parent for all spike MeshInstances
var _meshes: Dictionary = {}             # Vector3i chunk -> MeshInstance3D
var _dirty: Array[Vector3i] = []         # chunks queued for (re)build
var _dirty_set: Dictionary = {}
var _mat: Material = null

var _poll_accum: float = 0.0
var _report_accum: float = 0.0
var _win_build_us: int = 0               # build µs this report window
var _win_worst_us: int = 0               # worst single rebuild this window
var _win_rebuilds: int = 0
var _orphans_freed: int = 0


func _ready() -> void:
	# Inert until toggled. Process even while the game is paused so a
	# diagnostic toggle never gets swallowed (matches WaterDiag).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	print("[MesherSpike] loaded (OFF). F7 toggles. THROW-AWAY — see WATER_STAGE6_PLAN §11.")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F7:
			_set_active(not _active)


func _set_active(on: bool) -> void:
	_active = on
	if _active:
		_mat = load(MAT_PATH) as Material
		_root = Node3D.new()
		_root.name = "WaterMesherSpikeRoot"
		# Park it under the current scene so it streams/frees with play.
		var scn: Node = get_tree().current_scene
		if scn != null:
			scn.add_child(_root)
		else:
			add_child(_root)
		print("[MesherSpike] ON — flat surface rig attached. Walk/flood, read [MesherSpike] lines.")
	else:
		_tear_down()
		print("[MesherSpike] OFF — %d spike meshes freed (clean teardown check)." % _orphans_freed)


func _tear_down() -> void:
	_orphans_freed = 0
	for c in _meshes.keys():
		var mi: MeshInstance3D = _meshes[c]
		if is_instance_valid(mi):
			mi.queue_free()
			_orphans_freed += 1
	_meshes.clear()
	_dirty.clear()
	_dirty_set.clear()
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null


func _process(delta: float) -> void:
	if not _active:
		return
	var terrain: VoxelLodTerrain = _get_terrain()
	if terrain == null:
		return
	_poll_accum += delta
	if _poll_accum >= POLL_INTERVAL_S:
		_poll_accum = 0.0
		_repoll(terrain)
	_drain_build_queue(terrain)
	_report(delta)


func _get_terrain() -> VoxelLodTerrain:
	var vem: Node = get_node_or_null("/root/VoxelEditManager")
	if vem == null or not vem.has_method("get_terrain"):
		return null
	return vem.get_terrain() as VoxelLodTerrain


func _viewer_pos() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return Vector3.ZERO


func _world_to_chunk(p: Vector3) -> Vector3i:
	var vx: int = int(floor(p.x * VOXELS_PER_METER))
	var vy: int = int(floor(p.y * VOXELS_PER_METER))
	var vz: int = int(floor(p.z * VOXELS_PER_METER))
	return Vector3i(
		int(floor(float(vx) / CHUNK_VOX)),
		int(floor(float(vy) / CHUNK_VOX)),
		int(floor(float(vz) / CHUNK_VOX)))


func _repoll(_terrain: VoxelLodTerrain) -> void:
	# Decide which chunks should have a surface mesh, queue missing ones,
	# evict ones that left the radius (bar ② orphan/VRAM check).
	var vp: Vector3 = _viewer_pos()
	var rc: int = int(ceil(MESH_RADIUS_M * VOXELS_PER_METER / float(CHUNK_VOX)))
	var vc: Vector3i = _world_to_chunk(vp)

	# Evict out-of-radius meshes.
	var to_evict: Array = []
	for c in _meshes.keys():
		var cc: Vector3i = c as Vector3i
		if absi(cc.x - vc.x) > rc or absi(cc.z - vc.z) > rc:
			to_evict.append(cc)
	for cc2 in to_evict:
		var mi: MeshInstance3D = _meshes[cc2]
		if is_instance_valid(mi):
			mi.queue_free()
		_meshes.erase(cc2)

	# Queue in-radius chunks that have no mesh yet, plus always refresh
	# the viewer's own chunk + its 8 XZ neighbours (flooding changes the
	# surface there as the fill runs — keeps the rig honest).
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var c3: Vector3i = Vector3i(vc.x + dx, vc.y, vc.z + dz)
			var near: bool = absi(dx) <= 1 and absi(dz) <= 1
			if (not _meshes.has(c3)) or near:
				if not _dirty_set.has(c3):
					_dirty.append(c3)
					_dirty_set[c3] = true


func _drain_build_queue(terrain: VoxelLodTerrain) -> void:
	if _dirty.is_empty():
		return
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var t0: int = Time.get_ticks_usec()
	while not _dirty.is_empty() and (Time.get_ticks_usec() - t0) < BUILD_BUDGET_US:
		var c: Vector3i = _dirty.pop_front()
		_dirty_set.erase(c)
		var b0: int = Time.get_ticks_usec()
		var mesh: ArrayMesh = _build_chunk_surface(tool, c)
		var b_us: int = Time.get_ticks_usec() - b0
		_win_build_us += b_us
		_win_rebuilds += 1
		if b_us > _win_worst_us:
			_win_worst_us = b_us
		var old: MeshInstance3D = _meshes.get(c, null)
		if mesh == null:
			if is_instance_valid(old):
				old.queue_free()
			_meshes.erase(c)
			continue
		if is_instance_valid(old):
			old.mesh = mesh
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if is_instance_valid(_root):
				_root.add_child(mi)
				_meshes[c] = mi
	# Profiler attribution (same category WaterFlowManager uses).
	var prof: Node = get_node_or_null("/root/Profiler")
	if prof != null and prof.has_method("record"):
		prof.record("WATER", "MesherSpike", Time.get_ticks_usec() - t0)


func _build_chunk_surface(tool: VoxelTool, chunk: Vector3i) -> ArrayMesh:
	# For each (x,z) column in the chunk, find the highest CHANNEL_TYPE==5
	# voxel whose cell above is NOT water — that is the surface — and emit
	# one flat top quad (world-space verts). Naive on purpose.
	var ox: int = chunk.x * CHUNK_VOX
	var oy: int = chunk.y * CHUNK_VOX
	var oz: int = chunk.z * CHUNK_VOX
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var inv: float = 1.0 / VOXELS_PER_METER
	for lx in range(CHUNK_VOX):
		var wx: int = ox + lx
		for lz in range(CHUNK_VOX):
			var wz: int = oz + lz
			var surf_y: int = -1
			for ly in range(CHUNK_VOX - 1, -1, -1):
				var wy: int = oy + ly
				if tool.get_voxel(Vector3i(wx, wy, wz)) == WATER_TYPE_ID:
					if tool.get_voxel(Vector3i(wx, wy + 1, wz)) != WATER_TYPE_ID:
						surf_y = wy
						break
			if surf_y < 0:
				continue
			# Top face of the surface voxel, in world space.
			var y: float = float(surf_y + 1) * inv
			var x0: float = float(wx) * inv
			var x1: float = float(wx + 1) * inv
			var z0: float = float(wz) * inv
			var z1: float = float(wz + 1) * inv
			var b: int = verts.size()
			verts.push_back(Vector3(x0, y, z0))
			verts.push_back(Vector3(x1, y, z0))
			verts.push_back(Vector3(x1, y, z1))
			verts.push_back(Vector3(x0, y, z1))
			for _n in range(4):
				normals.push_back(Vector3(0.0, 1.0, 0.0))
			uvs.push_back(Vector2(0.0, 0.0))
			uvs.push_back(Vector2(1.0, 0.0))
			uvs.push_back(Vector2(1.0, 1.0))
			uvs.push_back(Vector2(0.0, 1.0))
			indices.push_back(b)
			indices.push_back(b + 2)
			indices.push_back(b + 1)
			indices.push_back(b)
			indices.push_back(b + 3)
			indices.push_back(b + 2)
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _report(delta: float) -> void:
	_report_accum += delta
	if _report_accum < REPORT_INTERVAL_S:
		return
	_report_accum = 0.0
	var vram: float = 0.0
	if Performance.has_method("get_monitor"):
		vram = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var tris: int = 0
	for c in _meshes.keys():
		var mi: MeshInstance3D = _meshes[c]
		if is_instance_valid(mi) and mi.mesh != null:
			tris += mi.mesh.get_faces().size() / 3
	print("[MesherSpike] live=%d  rebuilds/s=%d  build_us/s=%d  worst_us=%d  queued=%d  tris=%d  vram_mb=%.0f  viewerChunk=%s" % [
		_meshes.size(), _win_rebuilds, _win_build_us, _win_worst_us,
		_dirty.size(), tris, vram, str(_world_to_chunk(_viewer_pos())),
	])
	_win_build_us = 0
	_win_worst_us = 0
	_win_rebuilds = 0
